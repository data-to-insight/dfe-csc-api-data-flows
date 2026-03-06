-- define as required 
use HDM_Local; -- Note: LA should change to bespoke or remove - HDM_Local is SystemC/LLogic default

/* ==========================================================================
   D2I CSC API Payload Builder, SQL Server 2016+ compatible
   ========================================================================== */


/* Note for: Daily Data Flows Early Adopters
The following table definitions (and populating) can only be run <after> the main SSD script, OR the following definitions
can be appended into the main SSD and run as one - insert locations within the SSD are marked via the meta tags of:

-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging"}
-- =============================================================================
&
-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"}
-- =============================================================================

*/


-- Data pre/smoke test validator(s) (optional) --
-- D2I offers a seperate <simplified> validation VIEW towards your local data verification checks,
-- this offers some pre-process comparison between your data and the DfE API payload schema 
-- File: (T-SQL 2016+ only)https://github.com/data-to-insight/dfe-csc-api-data-flows/tree/main/pre_flight_checks/ssd_vw_csc_api_schema_checks.sql
-- -- 




DECLARE @VERSION nvarchar(32) = N'0.3.2';
RAISERROR(N'== CSC API staging build: v%s ==', 10, 1, @VERSION) WITH NOWAIT;


-- -- Apply if/when d2i staging table structual changes have been newly applied
-- DROP TABLE IF EXISTS ssd_api_data_staging_anon;
-- DROP TABLE IF EXISTS ssd_api_data_staging;
-- GO


-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging"}
-- =============================================================================
-- Description: Table for API payload and logging. 
-- Author: D2I
-- =============================================================================


-- IF OBJECT_ID('ssd_api_data_staging', 'U') IS NOT NULL DROP TABLE ssd_api_data_staging;
IF OBJECT_ID('ssd_api_data_staging') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM ssd_api_data_staging)
        TRUNCATE TABLE ssd_api_data_staging; -- clear existing if any rows
END
     
-- META-ELEMENT: {"type": "create_table"}
ELSE
BEGIN
    CREATE TABLE ssd_api_data_staging (
        id INT IDENTITY(1,1) PRIMARY KEY,           
        person_id NVARCHAR(36) NULL,                        -- link value (_person_id)
        legacy_id NVARCHAR(36) NULL,                        -- link value (_mis or _legacy_id)

        previous_json_payload NVARCHAR(MAX) NULL,           -- historic last copy of last payload sent
        json_payload NVARCHAR(MAX) NOT NULL,                -- current awaiting payload
        partial_json_payload NVARCHAR(MAX) NULL,            -- current awaiting partial payload
        current_hash BINARY(32) NULL,                       -- current hash of JSON payload
        previous_hash BINARY(32) NULL,                      -- previous hash of JSON payload
        submission_status NVARCHAR(50) DEFAULT 'Pending',   -- Status: Pending, Sent, Error
        submission_timestamp DATETIME DEFAULT GETDATE(),    -- data submitted timestamp
        api_response NVARCHAR(MAX) NULL,                    -- API response or error
        row_state NVARCHAR(10) DEFAULT 'New',               -- record state : New, Updated, Deleted, Unchanged
        last_updated DATETIME DEFAULT GETDATE()             -- timestamp data update/insertion
    );

END



/* === EA Spec window (dynamic: 24 months back --> FY start on 1 April) ===  */
DECLARE @run_date      date = CONVERT(date, GETDATE());
DECLARE @months_back   int  = 24;
DECLARE @fy_start_month int = 4;  -- April

DECLARE @anchor date = DATEADD(month, -@months_back, @run_date);
DECLARE @fy_start_year int = YEAR(@anchor) - CASE WHEN MONTH(@anchor) < @fy_start_month THEN 1 ELSE 0 END;

DECLARE @ea_cohort_window_start date = DATEFROMPARTS(@fy_start_year, @fy_start_month, 1);
DECLARE @ea_cohort_window_end date = DATEADD(day, 1, @run_date) -- today + 1
;


/* === Cohort CTEs, 2016+ compatible === */

;WITH EligibleBySpec AS (
  /* Include if:
        - Known DoB and age <=25 inclusive at some point during window(we key off the 26th bday)
         (26th birthday after window_start) and born by window_end
        - OR unborn (expected_dob in window)
        - Deceased included, no death-date filter

    Expected cohort: 
    children <=25 at any point between @ea_cohort_window_start and @ea_cohort_window_end (dynamic EA window, derived from 24 months back anchored to FY start)

  */
  SELECT p.pers_person_id
  FROM ssd_person p
  WHERE
    (
      p.pers_dob IS NOT NULL
      AND p.pers_dob <= @ea_cohort_window_end
      AND DATEADD(year, 26, p.pers_dob) > @ea_cohort_window_start -- <=25 at any point in window (DfE spec)
      -- DATEADD(year, 26, p.pers_dob) > @run_date                -- <=25 on run date

    )
    OR
    (
      /* fall back to expected DoB */
      p.pers_dob IS NULL
      AND p.pers_expected_dob IS NOT NULL
      AND p.pers_expected_dob BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
    )


    /* pre-alpha cohort filter (remove this block as required)
      LA use during live PRE-alpha cohort testing, add known child IDs here (< 20 records) */

    --AND p.pers_person_id IN ('1', '2', '3') 

    /* end pre-alpha cohort  */
),


/* === Payload builder 2016Sp1+/Azure SQL compatible === */
RawPayloads AS (
    SELECT
        p.pers_person_id AS person_id,
        p.pers_legacy_id AS legacy_id,
        (
            SELECT
                CAST(p.pers_person_id AS varchar(36)) AS [la_child_id],
                CAST(LEFT(NULLIF(LTRIM(RTRIM(p.pers_legacy_id)), ''), 36) AS varchar(36)) AS [mis_child_id],
                CAST(0 AS bit) AS [purge],

                JSON_QUERY((
                    SELECT
                        p.pers_upn AS [unique_pupil_number],
                        CAST(NULL AS varchar(13)) AS [former_unique_pupil_number],

                        LEFT(
                            NULLIF(
                                CASE
                                    WHEN NULLIF(LTRIM(RTRIM(p.pers_upn_unknown)), '') IS NOT NULL
                                        THEN LTRIM(RTRIM(p.pers_upn_unknown))
                                    WHEN UPPER(NULLIF(LTRIM(RTRIM(p.pers_upn)), ''))
                                        IN ('UN1','UN2','UN3','UN4','UN5','UN6','UN7','UN8','UN9','UN10')
                                        THEN UPPER(LTRIM(RTRIM(p.pers_upn)))
                                    ELSE NULL
                                END,
                                ''
                            ),
                            4
                        ) AS [unique_pupil_number_unknown_reason],

                        p.pers_forename AS [first_name],
                        p.pers_surname AS [surname],
                        CONVERT(varchar(10), p.pers_dob, 23) AS [date_of_birth],
                        CONVERT(varchar(10), p.pers_expected_dob, 23) AS [expected_date_of_birth],

                        CASE
                            WHEN p.pers_sex IN ('M', 'F') THEN p.pers_sex
                            ELSE 'U'
                        END AS [sex],

                        LEFT(NULLIF(LTRIM(RTRIM(p.pers_ethnicity)), ''), 4) AS [ethnicity],

                        JSON_QUERY(
                            CASE
                                WHEN disab.disabilities IS NOT NULL THEN disab.disabilities
                                ELSE '["NONE"]'
                            END
                        ) AS [disabilities],

                        (
                            SELECT TOP 1 a.addr_address_postcode
                            FROM ssd_address a
                            WHERE a.addr_person_id = p.pers_person_id
                            ORDER BY a.addr_address_start_date DESC
                        ) AS [postcode],

                        CAST(0 AS bit) AS [uasc_flag],
                        CAST(NULL AS varchar(10)) AS [uasc_end_date],
                        CAST(0 AS bit) AS [purge]
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES -- retain keys with 'null' 
                )) AS [child_details]
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES -- retain keys with 'null' 
        ) AS json_payload
    FROM ssd_person p
    INNER JOIN EligibleBySpec e
        ON e.pers_person_id = p.pers_person_id
    OUTER APPLY (
        SELECT
          CASE
            WHEN EXISTS (
              SELECT 1
              FROM ssd_disability d0
              WHERE d0.disa_person_id = p.pers_person_id
                AND NULLIF(LTRIM(RTRIM(d0.disa_disability_code)), '') IS NOT NULL
            )
            THEN
              N'[' +
              STUFF((
                  SELECT N',' + QUOTENAME(u.code, '"')
                  FROM (
                      SELECT TOP (12)
                          LEFT(UPPER(LTRIM(RTRIM(d2.disa_disability_code))), 4) AS code
                      FROM ssd_disability d2
                      WHERE d2.disa_person_id = p.pers_person_id
                        AND NULLIF(LTRIM(RTRIM(d2.disa_disability_code)), '') IS NOT NULL
                      GROUP BY LEFT(UPPER(LTRIM(RTRIM(d2.disa_disability_code))), 4)
                      ORDER BY LEFT(UPPER(LTRIM(RTRIM(d2.disa_disability_code))), 4)
                  ) u
                  FOR XML PATH(''), TYPE
              ).value('.', 'nvarchar(max)'), 1, 1, N'')
              + N']'
            ELSE NULL
          END AS disabilities
    ) AS disab
),   -- close RawPayloads CTE
  

/* hash payload + compare, de-dup by person_id and payload content
   Note: SHA2_256 used for change detection only
*/
Hashed AS (
    SELECT
        person_id,
        legacy_id,
        json_payload,
        HASHBYTES('SHA2_256', CAST(json_payload AS NVARCHAR(MAX))) AS current_hash
    FROM RawPayloads
)
INSERT INTO ssd_api_data_staging
    (person_id, legacy_id, previous_json_payload, json_payload, current_hash, previous_hash,
     submission_status, row_state, last_updated)
SELECT
    h.person_id,
    h.legacy_id,
    prev.json_payload AS previous_json_payload,
    h.json_payload,
    h.current_hash,
    prev.current_hash AS previous_hash,
    'Pending' AS submission_status,
    CASE WHEN prev.current_hash IS NULL THEN 'New' ELSE 'Updated' END AS row_state,
    GETDATE() AS last_updated
FROM Hashed h
OUTER APPLY (
    SELECT TOP (1) s.json_payload, s.current_hash
    FROM ssd_api_data_staging s
    WHERE s.person_id = h.person_id
    ORDER BY s.id DESC
) AS prev

-- /* Uncomment to force hard-filter against LA known Stat-Returns cohort table
-- We anticipate/recommend that all LA's do this initially to enable internal cohort auditing for records */
-- INNER JOIN
--     [dbo].[StoredStatReturnsCohortIdTable] STATfilter -- FAILSAFE STAT RETURN COHORT
--     ON STATfilter.[person_id] = h.person_id

WHERE prev.current_hash IS NULL             -- first time we've seen this person record
   OR prev.current_hash <> h.current_hash;  -- or payload has changed



-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"}
-- =============================================================================
-- Description: Table for TEST|ANON API payload and logging 
-- This table is NON-live and solely for the pre-live data/api testing. 

-- Table data sent only to Children in Social Care Data Receiver (TEST)

-- To be depreciated/removed at any point by the LA; we'd expect this to be after 
-- the toggle to LIVE sends are initiated to DfE LIVE Pre-Production(PP) and Production(P) endpoints. 
-- Author: D2I
-- Pre_Requisite: Requires the ssd_api_data_staging table to already exist
-- =============================================================================

-- create a duplicate copy of the staging table structure for anonymised records/data testing
IF OBJECT_ID('ssd_api_data_staging_anon', 'U') IS NULL
BEGIN
    SELECT TOP (0) *
    INTO ssd_api_data_staging_anon
    FROM ssd_api_data_staging;
END
ELSE
BEGIN
    -- Wipe any existing rows, identity col reset to 0 so next insert is 1
    TRUNCATE TABLE ssd_api_data_staging_anon;

    -- or
    -- DBCC CHECKIDENT ('ssd_api_data_staging_anon', RESEED, 0);
END

-- GO

SET NOCOUNT ON;


-- Fake example data incoming

--------------------------------------------------------------------------------
-- Record 1: Pending
--------------------------------------------------------------------------------
DECLARE @p1 NVARCHAR(MAX) = N'{
  "la_child_id": "Child2234",
  "mis_child_id": "Supplier-Child-2234",
  "purge": false,
  "child_details": {
    "unique_pupil_number": "JKL0123456789",
    "former_unique_pupil_number": "MNO0123456789",
    "date_of_birth": "2004-09-23",
    "sex": "F",
    "ethnicity": "B2",
    "postcode": "BN14 7ES",
    "purge": false
  },
  "health_and_wellbeing": { "purge": false },
  "social_care_episodes": [
    {
      "social_care_episode_id": "13423",
      "referral_date": "2005-02-11",
      "referral_source": "10",
      "care_worker_details": [
        { "worker_id": "X3323345", "start_date": "2024-01-11" },
        { "worker_id": "Y2234567", "start_date": "2022-01-22" },
        { "worker_id": "Z2235432", "start_date": "2022-09-20", "end_date": "2024-10-21" },
        { "worker_id": "X2234852", "start_date": "2020-04-12" }
      ],
      "child_and_family_assessments": [
        {
          "child_and_family_assessment_id": "BCD123456",
          "start_date": "2022-06-14",
          "authorisation_date": "2022-06-14",
          "factors": ["1C", "4A"],
          "purge": false
        }
      ],
      "child_looked_after_placements": [
        {
          "child_looked_after_placement_id": "BCD123456",
          "start_date": "2011-02-10",
          "start_reason": "S",
          "end_date": "2021-11-11",
          "end_reason": "E17",
          "placement_type": "U4",
          "postcode": "BN14 7ES",
          "change_reason": "",
          "purge": false
        }
      ],
      "care_leavers": {
        "contact_date": "2024-08-11",
        "activity": "F2",
        "accommodation": "Z",
        "purge": false
      },
      "purge": false
    }
  ]
}';

INSERT INTO ssd_api_data_staging_anon
(
    person_id,
    legacy_id,
    previous_json_payload,
    json_payload,
    partial_json_payload,
    previous_hash,
    current_hash,
    row_state,
    last_updated,
    submission_status,
    api_response,
    submission_timestamp
)
VALUES
(
    N'C001',
    N'L001',
    NULL,
    @p1,
    NULL,
    NULL,
    HASHBYTES('SHA2_256', CAST(@p1 AS NVARCHAR(4000))),
    N'New',
    GETDATE(),
    N'Pending',
    NULL,
    GETDATE()
);

--------------------------------------------------------------------------------
-- Record 2: Error
--------------------------------------------------------------------------------
DECLARE @p2 NVARCHAR(MAX) = N'{
  "la_child_id": "Child3234",
  "mis_child_id": "Supplier-Child-3234",
  "purge": false,
  "child_details": {
    "unique_pupil_number": "PQR0123456789",
    "former_unique_pupil_number": "STU0123456789",
    "date_of_birth": "2005-10-10",
    "sex": "M",
    "ethnicity": "C3",
    "postcode": "BN14 7ES",
    "purge": false
  },
  "health_and_wellbeing": { "purge": false },
  "social_care_episodes": [
    {
      "social_care_episode_id": "23423",
      "referral_date": "2006-03-01",
      "referral_source": "20",
      "care_worker_details": [
        { "worker_id": "X4323345", "start_date": "2023-01-11" },
        { "worker_id": "Y3234567", "start_date": "2022-02-22" }
      ],
      "child_and_family_assessments": [
        {
          "child_and_family_assessment_id": "CDE123456",
          "start_date": "2021-06-14",
          "authorisation_date": "2021-06-14",
          "factors": ["1C"],
          "purge": false
        }
      ],
      "child_looked_after_placements": [],
      "care_leavers": {
        "contact_date": "2024-09-11",
        "activity": "E2",
        "accommodation": "A",
        "purge": false
      },
      "purge": false
    }
  ]
}';

INSERT INTO ssd_api_data_staging_anon
(
    person_id,
    legacy_id,
    previous_json_payload,
    json_payload,
    partial_json_payload,
    previous_hash,
    current_hash,
    row_state,
    last_updated,
    submission_status,
    api_response,
    submission_timestamp
)
VALUES
(
    N'C002',
    N'L002',
    NULL,
    @p2,
    NULL,
    NULL,
    HASHBYTES('SHA2_256', CAST(@p2 AS NVARCHAR(4000))),
    N'New',
    GETDATE(),
    N'Error',
    N'HTTP 400: Validation failed - missing expected field',
    GETDATE()
);

--------------------------------------------------------------------------------
-- Record 3: Sent (with previous payload + hash)
--------------------------------------------------------------------------------
DECLARE @prev3 NVARCHAR(MAX) = N'{
  "la_child_id": "Child4234",
  "mis_child_id": "Supplier-Child-4234",
  "purge": false
}';

DECLARE @p3 NVARCHAR(MAX) = N'{
  "la_child_id": "Child4234",
  "mis_child_id": "Supplier-Child-4234",
  "purge": false,
  "child_details": {
    "unique_pupil_number": "VWX0123456789",
    "former_unique_pupil_number": "YZA0123456789",
    "date_of_birth": "2006-05-05",
    "sex": "M",
    "ethnicity": "D4",
    "postcode": "BN14 7ES",
    "purge": false
  },
  "health_and_wellbeing": { "purge": false },
  "social_care_episodes": [
    {
      "social_care_episode_id": "33423",
      "referral_date": "2007-01-15",
      "referral_source": "30",
      "care_worker_details": [
        { "worker_id": "X5323345", "start_date": "2024-01-11" }
      ],
      "child_and_family_assessments": [],
      "child_looked_after_placements": [],
      "care_leavers": {
        "contact_date": "2024-07-11",
        "activity": "H2",
        "accommodation": "B",
        "purge": false
      },
      "purge": false
    }
  ]
}';

INSERT INTO ssd_api_data_staging_anon
(
    person_id,
    legacy_id,
    previous_json_payload,
    json_payload,
    partial_json_payload,
    previous_hash,
    current_hash,
    row_state,
    last_updated,
    submission_status,
    api_response,
    submission_timestamp
)
VALUES
(
    N'C003',
    N'L003',
    @prev3,
    @p3,
    NULL,
    HASHBYTES('SHA2_256', CAST(@prev3 AS NVARCHAR(4000))),
    HASHBYTES('SHA2_256', CAST(@p3 AS NVARCHAR(4000))),
    N'Unchanged',
    GETDATE(),
    N'Sent',
    N'HTTP 201: Created',
    GETDATE()
);

SET NOCOUNT OFF;


/* 
SAMPLE LIVE PAYLOAD VERIFICATION OUTPUTS
Check table(s) populated
*/
select TOP (5) * from ssd_api_data_staging;
select TOP (5) * from ssd_api_data_staging_anon; -- verify inclusion of x3 fake records added above 



-- /* 
-- SAMPLE LIVE PAYLOAD VERIFICATION OUTPUTS
-- */


-- -- PAYLOAD VERIFICATION 1 : Show records with with extended/nested payload (if available)
-- SELECT TOP (3)
--     person_id,
--     LEN(json_payload)        AS payload_chars,
--     json_payload  AS preview
-- FROM ssd_api_data_staging
-- ORDER BY DATALENGTH(json_payload) DESC, id DESC;



-- -- PAYLOAD VERIFICATION 2 : Show records with health&wellbeing data available
-- ;WITH WithCounts AS (
--     SELECT
--         s.person_id,
--         s.id,
--         s.json_payload,
--         LEN(s.json_payload) AS payload_chars,
--         -- crude count SDQ assessments: instances -date- appears
--         CASE 
--             WHEN j.sdq_text IS NULL OR j.sdq_text = '[]' THEN 0
--             ELSE (LEN(j.sdq_text) - LEN(REPLACE(j.sdq_text, '"date"', ''))) / LEN('"date"')
--         END AS AssessmentCount
--     FROM ssd_api_data_staging AS s
--     CROSS APPLY (
--         SELECT CAST(
--             JSON_QUERY(s.json_payload, '$.health_and_wellbeing.sdq_assessments')
--             AS nvarchar(max)
--         ) AS sdq_text
--     ) AS j
--     WHERE j.sdq_text IS NOT NULL
--       AND j.sdq_text <> '[]'
-- )
-- SELECT TOP (3)
--     person_id,
--     payload_chars,
--     json_payload AS preview
-- FROM WithCounts
-- ORDER BY
--     CASE WHEN AssessmentCount > 1 THEN 0 ELSE 1 END,  -- multi-SDQ first
--     AssessmentCount DESC,
--     payload_chars DESC,
--     id DESC;

-- -- -- LEGACY-PRE2016 (no JSON functions)
-- -- SELECT TOP (5) ...
-- -- FROM ssd_api_data_staging
-- -- WHERE json_payload LIKE '%"health_and_wellbeing"%sdq_assessments%"date"%'
-- -- ORDER BY DATALENGTH(json_payload) DESC, id DESC;


-- -- PAYLOAD VERIFICATION 3 : Show records with adoption data available
-- SELECT TOP (3)
--     person_id,
--     LEN(json_payload) AS payload_chars,
--     json_payload AS preview
-- FROM ssd_api_data_staging
-- WHERE JSON_QUERY(json_payload, '$.social_care_episodes[0].adoption') IS NOT NULL
-- -- -- LEGACY-PRE2016
-- -- WHERE json_payload LIKE '%"adoption"%date_match"%'
-- ORDER BY DATALENGTH(json_payload) DESC, id DESC;


-- -- PAYLOAD VERIFICATION 4 : S47 records where an ICPC date exists
-- -- spot episodes with conference activity recorded
-- SELECT TOP (5)
--     person_id,
--     LEN(json_payload) AS payload_chars,
--     json_payload AS preview
-- FROM ssd_api_data_staging
-- WHERE json_payload LIKE '%"section_47_assessments"%'
--   AND json_payload LIKE '%"icpc_date":"20%'   -- not ideal date presence test yyyy-mm-dd
-- ORDER BY payload_chars DESC, id DESC;



-- -- PAYLOAD VERIFICATION 5 : Show records with S47 assessments
-- -- S47 presence and s47s count per record in order
-- ;WITH WithS47 AS (
--     SELECT
--         s.person_id,
--         s.id,
--         s.json_payload,
--         LEN(s.json_payload) AS payload_chars,
--         -- count S47 items by token occurrence, episode agnostic
--         (LEN(s.json_payload) - LEN(REPLACE(s.json_payload, '"section_47_assessment_id"', '')))
--             / NULLIF(LEN('"section_47_assessment_id"'), 0) AS s47_count,
--         -- quick existence flag via array pattern
--         CASE WHEN CHARINDEX('"section_47_assessments":[{', s.json_payload) > 0 THEN 1 ELSE 0 END AS has_s47
--     FROM ssd_api_data_staging s
-- )
-- SELECT TOP (5)
--     person_id,
--     s47_count,
--     payload_chars,
--     json_payload AS preview
-- FROM WithS47
-- WHERE has_s47 = 1 OR s47_count > 0
-- ORDER BY s47_count DESC, payload_chars DESC, id DESC;



-- -- PAYLOAD VERIFICATION 6 : Show age breakdown of records
-- SELECT
--   DATEDIFF(year, p.pers_dob, CONVERT(date, GETDATE()))
--     - CASE WHEN DATEADD(year, DATEDIFF(year, p.pers_dob, CONVERT(date, GETDATE())), p.pers_dob) > CONVERT(date, GETDATE()) THEN 1 ELSE 0 END
--     AS age_years,
--   COUNT(DISTINCT s.person_id) AS people
-- FROM ssd_api_data_staging s
-- JOIN ssd_person p
--   ON p.pers_person_id = s.person_id
-- WHERE p.pers_dob IS NOT NULL
--   AND DATEADD(year, 16, p.pers_dob) > CONVERT(date, GETDATE())
-- GROUP BY
--   DATEDIFF(year, p.pers_dob, CONVERT(date, GETDATE()))
--     - CASE WHEN DATEADD(year, DATEDIFF(year, p.pers_dob, CONVERT(date, GETDATE())), p.pers_dob) > CONVERT(date, GETDATE()) THEN 1 ELSE 0 END
-- ORDER BY age_years;