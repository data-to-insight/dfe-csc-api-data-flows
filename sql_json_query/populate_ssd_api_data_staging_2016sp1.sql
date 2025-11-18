
-- define if required 
use HDM_Local; -- Note: this the SystemC/LLogic default


/* Note for: Daily Data Flows Early Adopters
The following table definitions (and populating) can only be run after the main SSD script, OR the following definitions
can be added into the main SSD - insert locations are marked via the meta tags of:


-- Script compatibility and defaults
-- Default uses XML PATH for aggregations, SQL Server 2012+
-- Payload assembly uses FOR JSON, JSON_QUERY, JSON_VALUE, SQL Server 2016+
-- Optional modern aggregation using STRING_AGG is included as commented block, SQL Server 2022+


META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging"}
META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"} - temp table for API testing, can be removed post testing
*/

DECLARE @VERSION nvarchar(32) = N'0.1.3';
RAISERROR(N'== CSC API staging build: v%s ==', 10, 1, @VERSION) WITH NOWAIT;


-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging"}
-- =============================================================================
-- Description: Table for API payload and logging. For most LA's this is a placeholder 
-- structure as source data not common|confirmed
-- Author: D2I
-- =============================================================================


-- Data pre/smoke test validator(s) (optional) --
-- D2I offers a <simplified> validation VIEW towards your local data verification checks
-- This offers pre-process comparison between your data and the DfE API payload schema 
-- File: ssd_vw_csc_api_schema_checks.sql (SQL Server 2016+)
-- dfe-csc-api-data-flows/pre_flight_checks/ssd_vw_csc_api_schema_checks.sql
-- -- 


-- IF OBJECT_ID('ssd_api_data_staging', 'U') IS NOT NULL DROP TABLE ssd_api_data_staging;
IF OBJECT_ID(N'ssd_api_data_staging', N'U') IS NULL
BEGIN
    CREATE TABLE ssd_api_data_staging (
        id INT IDENTITY(1,1) PRIMARY KEY,           
        person_id NVARCHAR(48) NULL,                        -- link value (_person_id)
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


;WITH RawPayloads AS (
    SELECT
        p.pers_person_id AS person_id,
        (
            SELECT
                -- Note: ids (str)
                LEFT(CAST(p.pers_person_id AS varchar(36)), 36) AS [la_child_id],
                LEFT(CAST(ISNULL(p.pers_single_unique_id, 'SSD_SUI') AS varchar(36)), 36) AS [mis_child_id],
                CAST(0 AS bit) AS [purge],

                -- Child details
                JSON_QUERY((
                    SELECT
                        p.pers_forename AS [first_name],
                        p.pers_surname  AS [surname],

                        -- UPNs (13 numeric, else null)
                        (SELECT TOP 1 CASE
                                        WHEN LEN(li.link_identifier_value) = 13
                                         AND TRY_CONVERT(bigint, li.link_identifier_value) IS NOT NULL
                                        THEN li.link_identifier_value
                                      END
                           FROM ssd_linked_identifiers li
                          WHERE li.link_person_id = p.pers_person_id
                            AND li.link_identifier_type = 'Unique Pupil Number'
                          ORDER BY li.link_valid_from_date DESC) AS [unique_pupil_number],

                        (SELECT TOP 1 CASE
                                        WHEN LEN(li2.link_identifier_value) = 13
                                         AND TRY_CONVERT(bigint, li2.link_identifier_value) IS NOT NULL
                                        THEN li2.link_identifier_value
                                      END
                           FROM ssd_linked_identifiers li2
                          WHERE li2.link_person_id = p.pers_person_id
                            AND li2.link_identifier_type = 'Former Unique Pupil Number'
                          ORDER BY li2.link_valid_from_date DESC) AS [former_unique_pupil_number],

                        LEFT(p.pers_upn_unknown, 3) AS [unique_pupil_number_unknown_reason],

                        CONVERT(varchar(10), p.pers_dob, 23) AS [date_of_birth],
                        CONVERT(varchar(10), p.pers_expected_dob, 23) AS [expected_date_of_birth],

                        CASE WHEN p.pers_sex IN ('M','F') THEN p.pers_sex ELSE 'U' END AS [sex],

                        LEFT(p.pers_ethnicity, 4) AS [ethnicity],

                        -- Disabilities array, input from builder below
                        COALESCE(JSON_QUERY(disab.disabilities), JSON_QUERY('[]')) AS [disabilities],

                        -- Postcode (max 8)
                        (SELECT TOP 1 LEFT(a.addr_address_postcode, 8)
                           FROM ssd_address a
                          WHERE a.addr_person_id = p.pers_person_id
                          ORDER BY a.addr_address_start_date DESC) AS [postcode],

                        -- UASC bool
                        CASE
                            WHEN EXISTS (
                                SELECT 1
                                  FROM ssd_immigration_status s
                                 WHERE s.immi_person_id = p.pers_person_id
                                   AND ISNULL(s.immi_immigration_status, '') COLLATE Latin1_General_CI_AI LIKE '%UASC%'
                            ) THEN CAST(1 AS bit)
                            ELSE CAST(0 AS bit)
                        END AS [uasc_flag],

                        (SELECT TOP 1 CONVERT(varchar(10), s2.immi_immigration_status_end_date, 23)
                           FROM ssd_immigration_status s2
                          WHERE s2.immi_person_id = p.pers_person_id
                          ORDER BY CASE WHEN s2.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                                   s2.immi_immigration_status_start_date DESC) AS [uasc_end_date],

                        CAST(0 AS bit) AS [purge]
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                )) AS [child_details],

                -- Health and wellbeing
                JSON_QUERY((
                    SELECT
                        COALESCE(JSON_QUERY((
                            SELECT
                                CONVERT(varchar(10), csdq.csdq_sdq_completed_date, 23) AS [sdq_date],
                                TRY_CONVERT(int, csdq.csdq_sdq_score) AS [sdq_score] -- is (decimal(10,2) required
                            FROM ssd_sdq_scores csdq
                            WHERE csdq.csdq_person_id = p.pers_person_id
                            AND csdq.csdq_sdq_completed_date IS NOT NULL
                            AND csdq.csdq_sdq_completed_date > '1900-01-01'
                            AND TRY_CONVERT(int, csdq.csdq_sdq_score) IS NOT NULL -- exclude when val not valid int
                            ORDER BY csdq.csdq_sdq_completed_date DESC
                            FOR JSON PATH
                        )), JSON_QUERY('[]')) AS [sdq_assessments],
                        CAST(0 AS bit) AS [purge]
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                )) AS [health_and_wellbeing],

                -- Social care episodes
                JSON_QUERY((
                    SELECT
                        -- Note: id(str)
                        LEFT(CAST(cine.cine_referral_id AS varchar(36)), 36) AS [social_care_episode_id], -- stringify for JSON
                        CONVERT(varchar(10), cine.cine_referral_date, 23) AS [referral_date],
                        LEFT(cine.cine_referral_source_code, 2) AS [referral_source],

                        CASE
                            WHEN TRY_CONVERT(bit, cine.cine_referral_nfa) IS NOT NULL
                                THEN TRY_CONVERT(bit, cine.cine_referral_nfa)
                            -- SSD source enforces NCHAR(1) however..., some robustness - wrap potential LA source strings
                            -- SSD source field cine_referral_nfa in review as bool
                            WHEN UPPER(LTRIM(RTRIM(cine.cine_referral_nfa))) IN ('Y','T','1','TRUE')
                                THEN CAST(1 AS bit)
                            WHEN UPPER(LTRIM(RTRIM(cine.cine_referral_nfa))) IN ('N','F','0','FALSE')
                                THEN CAST(0 AS bit)
                            ELSE CAST(NULL AS bit)
                        END AS [referral_no_further_action_flag],

                        -- care worker details
                        COALESCE(JSON_QUERY((
                            SELECT
                                -- Note: id(str)
                                LEFT(CAST(pr.prof_staff_id AS varchar(12)), 12) AS [worker_id],
                                CONVERT(varchar(10), i.invo_involvement_start_date, 23) AS [start_date],
                                CONVERT(varchar(10), i.invo_involvement_end_date, 23)   AS [end_date]
                              FROM ssd_involvements i
                              JOIN ssd_professionals pr
                                ON i.invo_professional_id = pr.prof_professional_id
                             WHERE i.invo_referral_id = cine.cine_referral_id
                             ORDER BY i.invo_involvement_start_date DESC
                             FOR JSON PATH
                        )), JSON_QUERY('[]')) AS [care_worker_details],

                        -- child and family assessments
                        COALESCE(JSON_QUERY((
                            SELECT
                                -- Note: id(str)
                                LEFT(CAST(ca.cina_assessment_id AS varchar(36)), 36) AS [child_and_family_assessment_id],
                                CONVERT(varchar(10), ca.cina_assessment_start_date, 23) AS [start_date],
                                CONVERT(varchar(10), ca.cina_assessment_auth_date, 23)  AS [authorisation_date],
                                JSON_QUERY(CASE
                                    WHEN af.cinf_assessment_factors_json IS NULL OR af.cinf_assessment_factors_json = ''
                                        THEN '[]'
                                    ELSE af.cinf_assessment_factors_json
                                END) AS [factors],
                                CAST(0 AS bit) AS [purge]
                              FROM ssd_cin_assessments ca
                              LEFT JOIN ssd_assessment_factors af
                                ON af.cinf_assessment_id = ca.cina_assessment_id
                             WHERE ca.cina_referral_id = cine.cine_referral_id
                             FOR JSON PATH
                        )), JSON_QUERY('[]')) AS [child_and_family_assessments],

                        -- child in need plans
                        COALESCE(JSON_QUERY((
                            SELECT
                                -- Note: id(str)
                                LEFT(CAST(cinp.cinp_cin_plan_id AS varchar(36)), 36) AS [child_in_need_plan_id],
                                CONVERT(varchar(10), cinp.cinp_cin_plan_start_date, 23) AS [start_date],
                                CONVERT(varchar(10), cinp.cinp_cin_plan_end_date, 23)   AS [end_date],
                                CAST(0 AS bit) AS [purge]
                              FROM ssd_cin_plans cinp
                             WHERE cinp.cinp_referral_id = cine.cine_referral_id
                             FOR JSON PATH
                        )), JSON_QUERY('[]')) AS [child_in_need_plans],

                        -- s47 assessments
                        COALESCE(JSON_QUERY((
                            SELECT
                                -- Note: id(str)
                                LEFT(CAST(s47e.s47e_s47_enquiry_id AS varchar(36)), 36) AS [section_47_assessment_id],
                                CONVERT(varchar(10), s47e.s47e_s47_start_date, 23) AS [start_date],
                                CASE
                                    WHEN JSON_VALUE(s47e.s47e_s47_outcome_json, '$.CP_CONFERENCE_FLAG') IN ('Y','T','1','true','True')
                                        THEN CAST(1 AS bit)
                                    WHEN JSON_VALUE(s47e.s47e_s47_outcome_json, '$.CP_CONFERENCE_FLAG') IN ('N','F','0','false','False')
                                        THEN CAST(0 AS bit)
                                    ELSE CAST(NULL AS bit)
                                END AS [icpc_required_flag],
                                CONVERT(varchar(10), icpc.icpc_icpc_date, 23) AS [icpc_date],
                                CONVERT(varchar(10), s47e.s47e_s47_end_date, 23) AS [end_date],
                                CAST(0 AS bit) AS [purge]
                              FROM ssd_s47_enquiry s47e
                              LEFT JOIN ssd_initial_cp_conference icpc
                                ON icpc.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                             WHERE s47e.s47e_referral_id = cine.cine_referral_id
                             FOR JSON PATH
                        )), JSON_QUERY('[]')) AS [section_47_assessments],

                        -- child protection plans
                        COALESCE(JSON_QUERY((
                            SELECT
                                -- Note: id(str)
                                LEFT(CAST(cppl.cppl_cp_plan_id AS varchar(36)), 36) AS [child_protection_plan_id],
                                CONVERT(varchar(10), cppl.cppl_cp_plan_start_date, 23) AS [start_date],
                                CONVERT(varchar(10), cppl.cppl_cp_plan_end_date, 23)   AS [end_date],
                                CAST(0 AS bit) AS [purge]
                              FROM ssd_cp_plans cppl
                             WHERE cppl.cppl_referral_id = cine.cine_referral_id
                             FOR JSON PATH
                        )), JSON_QUERY('[]')) AS [child_protection_plans],

                        -- looked after placements
                        COALESCE(JSON_QUERY((
                            SELECT
                                -- Note: id(str)
                                -- Issue #31
                                -- There are some open questions around which data to fullfil placement start/end/reason
                                -- hence combined use of episode+placement detail here. To *review in LA data verification* process(es)
                                LEFT(CAST(clap.clap_cla_placement_id AS varchar(36)), 36) AS [child_looked_after_placement_id],
                                CONVERT(varchar(10), clap.clap_cla_placement_start_date, 23) AS [start_date],
                                LEFT(clae.clae_cla_episode_start_reason, 1) AS [start_reason],
                                LEFT(clap.clap_cla_placement_type, 2) AS [placement_type],
                                LEFT(clap.clap_cla_placement_postcode, 8) AS [postcode],
                                CONVERT(varchar(10), clap.clap_cla_placement_end_date, 23) AS [end_date],
                                LEFT(clae.clae_cla_episode_ceased_reason, 3) AS [end_reason], -- access to ceased reason uncertain in systemC
                                LEFT(clap.clap_cla_placement_change_reason, 6) AS [change_reason],
                                CAST(0 AS bit) AS [purge]
                              FROM ssd_cla_episodes clae
                              JOIN ssd_cla_placement clap
                                ON clap.clap_cla_id = clae.clae_cla_id
                             WHERE clae.clae_referral_id = cine.cine_referral_id
                             ORDER BY clap.clap_cla_placement_start_date DESC
                             FOR JSON PATH
                        )), JSON_QUERY('[]')) AS [child_looked_after_placements],

                        -- Adoption
                        JSON_QUERY((
                            SELECT TOP 1
                                CONVERT(varchar(10), perm.perm_adm_decision_date, 23) AS [initial_decision_date],
                                CONVERT(varchar(10), perm.perm_matched_date, 23)      AS [matched_date],
                                CONVERT(varchar(10), perm.perm_placed_for_adoption_date, 23) AS [placed_date],
                                CAST(0 AS bit) AS [purge]
                              FROM ssd_permanence perm
                             WHERE perm.perm_person_id = p.pers_person_id
                                OR perm.perm_cla_id IN (
                                        SELECT clae2.clae_cla_id
                                          FROM ssd_cla_episodes clae2
                                         WHERE clae2.clae_person_id = p.pers_person_id
                                    )
                             ORDER BY COALESCE(perm.perm_placed_for_adoption_date, perm.perm_matched_date, perm.perm_adm_decision_date) DESC
                             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                        )) AS [adoption],

                        -- Care leavers
                        JSON_QUERY((
                            SELECT TOP 1
                                CONVERT(varchar(10), clea.clea_care_leaver_latest_contact, 23) AS [contact_date],
                                LEFT(clea.clea_care_leaver_activity, 2) AS [activity],
                                LEFT(clea.clea_care_leaver_accommodation, 1) AS [accommodation],
                                CAST(0 AS bit) AS [purge]
                              FROM ssd_care_leavers clea
                             WHERE clea.clea_person_id = p.pers_person_id
                             ORDER BY clea.clea_care_leaver_latest_contact DESC
                             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                        )) AS [care_leavers],

                        CONVERT(varchar(10), cine.cine_close_date, 23) AS [closure_date],
                        LEFT(cine.cine_close_reason, 3) AS [closure_reason],
                        CAST(0 AS bit) AS [purge]
                      FROM ssd_cin_episodes cine
                     WHERE cine.cine_person_id = p.pers_person_id
                     FOR JSON PATH
                )) AS [social_care_episodes]

            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS json_payload
    FROM ssd_person p

    /* Option A, XML PATH, SQL Server 2012+ (default for 2016 script) */
    OUTER APPLY (
        SELECT JSON_QUERY(
            N'[' +
            ISNULL(
                STUFF((
                    SELECT N',' + QUOTENAME(u.code, '"')
                    FROM (
                        SELECT TOP (12) code
                        FROM (
                            SELECT DISTINCT
                                LEFT(UPPER(LTRIM(RTRIM(d2.disa_disability_code))), 4) AS code
                            FROM ssd_disability AS d2
                            WHERE d2.disa_person_id = p.pers_person_id
                            AND d2.disa_disability_code IS NOT NULL
                            AND LTRIM(RTRIM(d2.disa_disability_code)) <> ''
                        ) d
                        ORDER BY code
                    ) u
                    FOR XML PATH(''), TYPE
                ).value('.', 'nvarchar(max)'), 1, 1, N''),
                N''
            ) + N']'
        ) AS disabilities
    ) AS disab

    /* Option B, STRING_AGG, SQL Server 2022+ */
    -- OUTER APPLY (
    --     SELECT JSON_QUERY(
    --         N'[' +
    --         ISNULL(
    --             (
    --               SELECT STRING_AGG('"' + u.code + '"', N',')
    --                      WITHIN GROUP (ORDER BY u.code)
    --               FROM (
    --                   SELECT TOP (12) code
    --                   FROM (
    --                       SELECT DISTINCT LEFT(UPPER(LTRIM(RTRIM(d2.disa_disability_code))), 4) AS code
    --                       FROM ssd_disability AS d2
    --                       WHERE d2.disa_person_id = p.pers_person_id
    --                         AND d2.disa_disability_code IS NOT NULL
    --                         AND LTRIM(RTRIM(d2.disa_disability_code)) <> ''
    --                   ) d
    --                   ORDER BY code
    --               ) u
    --             ),
    --             N''
    --         ) + N']'
    --     ) AS disabilities
    -- ) AS disab

),

Hashed AS (
    SELECT
        person_id,
        json_payload,
        HASHBYTES('SHA2_256', CAST(json_payload AS NVARCHAR(MAX))) AS current_hash
    FROM RawPayloads
)
INSERT INTO ssd_api_data_staging
    (person_id, previous_json_payload, json_payload, current_hash, previous_hash,
     submission_status, row_state, last_updated)
SELECT
    h.person_id,
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
WHERE prev.current_hash IS NULL             -- first time we’ve ever seen this person
   OR prev.current_hash <> h.current_hash;  -- payload has changed



-- -- Optional
-- CREATE UNIQUE INDEX UX_ssd_api_person_hash
-- ON ssd_api_data_staging(person_id, current_hash);





-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"}
-- =============================================================================
-- Description: Table for TEST|ANON API payload and logging. 
-- This table is non-live and solely for the pre-live data/api testing. It can be 
-- depreciated/removed at any point by the LA; we'd expect this to be once 
-- the toggle to LIVE sends are initiated to DfE. 
-- Author: D2I
-- =============================================================================

-- IF OBJECT_ID('ssd_api_data_staging_anon', 'U') IS NOT NULL DROP TABLE ssd_api_data_staging_anon;
IF OBJECT_ID(N'ssd_api_data_staging_anon', N'U') IS NULL
BEGIN
    CREATE TABLE ssd_api_data_staging_anon (
        id INT IDENTITY(1,1) PRIMARY KEY,           
        person_id NVARCHAR(48) NULL,                        -- link value (_person_id)
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


GO
-- Wipe existing rows
DELETE FROM ssd_api_data_staging_anon;
-- reset identity to 0 so next insert is 1
-- DBCC CHECKIDENT ('ssd_api_data_staging_anon', RESEED, 0);
GO


SET NOCOUNT ON;



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
    "postcode": "BN147ES",
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
          "change_reason": "SSD_PH",
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
    "postcode": "BN147ES",
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
    "postcode": "BN147ES",
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


 
-- Verification|sanity checks
-- Check table(s) populated
select TOP (5) * from ssd_api_data_staging;
select TOP (5) * from ssd_api_data_staging_anon; -- should be blank at this point




-- -- Get sample of LIVE rows that def have have an extended/full payload (if available)
-- SELECT TOP (5)
--     person_id,
--     LEN(json_payload)        AS payload_chars,
--     json_payload  AS preview
-- FROM ssd_api_data_staging
-- ORDER BY DATALENGTH(json_payload) DESC, id DESC;