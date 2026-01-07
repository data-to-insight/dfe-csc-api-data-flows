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




DECLARE @VERSION nvarchar(32) = N'0.3.0';
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
        TRUNCATE TABLE ssd_api_data_staging;        -- clear existing if any rows
END
-- META-ELEMENT: {"type": "create_table"}
ELSE
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


/* === EA Spec window (dynamic: 24 months back --> FY start on 1 April) ===  */
DECLARE @run_date      date = CONVERT(date, GETDATE());
DECLARE @months_back   int  = 24;
DECLARE @fy_start_month int = 4;  -- April

DECLARE @anchor date = DATEADD(month, -@months_back, @run_date);
DECLARE @fy_start_year int = YEAR(@anchor) - CASE WHEN MONTH(@anchor) < @fy_start_month THEN 1 ELSE 0 END;

DECLARE @ea_cohort_window_start date = DATEFROMPARTS(@fy_start_year, @fy_start_month, 1);
DECLARE @ea_cohort_window_end date = DATEADD(day, 1, @run_date) -- today + 1

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


ActiveReferral AS (
  /* episode overlaps window, and open at run_date
     overlap, referral_date <= window_end and (close_date null or close_date >= window_start)
     open, close_date null or close_date > run_date
  */
    SELECT DISTINCT cine.cine_person_id AS person_id
    FROM ssd_cin_episodes cine
    WHERE cine.cine_referral_date <= @ea_cohort_window_end
      AND (cine.cine_close_date IS NULL OR cine.cine_close_date >= @ea_cohort_window_start)
    
),
WaitingAssessment AS (
    /* Open referral episode with no assessment started for that referral (placeholder). */
    SELECT DISTINCT cine.cine_person_id AS person_id
    FROM ssd_cin_episodes cine
    WHERE cine.cine_close_date IS NULL
      AND NOT EXISTS (
            SELECT 1
            FROM ssd_cin_assessments ca
            WHERE ca.cina_referral_id = cine.cine_referral_id
              AND ca.cina_assessment_start_date IS NOT NULL
      )
),
HasCINPlan AS (
    /*
      Include if any CiN plan overlaps window
      Overlap, plan_start <= window_end and (plan_end null or plan_end >= window_start)
    */
    SELECT DISTINCT cinp.cinp_person_id AS person_id
    FROM ssd_cin_plans cinp
    WHERE cinp.cinp_cin_plan_start_date <= @ea_cohort_window_end
      AND (cinp.cinp_cin_plan_end_date IS NULL OR cinp.cinp_cin_plan_end_date >= @ea_cohort_window_start)
),
HasCPPlan AS (
    /*
      Include if any CP plan overlaps window
      Overlap, plan_start <= window_end and (plan_end null or plan_end >= window_start)
    */
    SELECT DISTINCT cppl.cppl_person_id AS person_id
    FROM ssd_cp_plans cppl
    WHERE cppl.cppl_cp_plan_start_date <= @ea_cohort_window_end
      AND (cppl.cppl_cp_plan_end_date IS NULL OR cppl.cppl_cp_plan_end_date >= @ea_cohort_window_start)
),
HasLAC AS (
    /*
      Include if LAC by either 
      A, LAC episode linked to CIN referral overlapping window
      B, any placement overlapping window, independent of CIN linkage
    */

    -- A) LAC episode linked to CIN episode that overlaps window
    SELECT DISTINCT clae.clae_person_id AS person_id
    FROM ssd_cla_episodes clae
    JOIN ssd_cin_episodes cine
      ON cine.cine_referral_id = clae.clae_referral_id
    WHERE cine.cine_referral_date <= @ea_cohort_window_end
      AND (cine.cine_close_date IS NULL OR cine.cine_close_date >= @ea_cohort_window_start)

    UNION

    -- B) Or any placement overlapping window
    SELECT DISTINCT clae2.clae_person_id AS person_id
    FROM ssd_cla_episodes clae2
    JOIN ssd_cla_placement clap
      ON clap.clap_cla_id = clae2.clae_cla_id
    WHERE clap.clap_cla_placement_start_date <= @ea_cohort_window_end
      AND (clap.clap_cla_placement_end_date IS NULL OR clap.clap_cla_placement_end_date >= @ea_cohort_window_start)
),



IsCareLeaver16to25 AS (
    /*
      Include if care leaver latest contact in window [REVIEW]
      And age between 16 and 25 by DATEDIFF year, coarse boundary -not- birthday precise
      Allow expected DoB guard when DoB null

    Expected Care leavers cohort subset:
    Care leavers classified 16-25 (at run date), plus latest contact in window
    Include care leavers who have a non null clea_care_leaver_latest_contact date inside the window
    */
  SELECT DISTINCT p.pers_person_id AS person_id
  FROM ssd_person p
  WHERE p.pers_dob IS NOT NULL
    AND DATEADD(year, 16, p.pers_dob) <  @ea_cohort_window_end    -- classified 16-25 (within window)
    AND DATEADD(year, 26, p.pers_dob) >= @ea_cohort_window_start  -- classified 16-25 (within window)

    AND EXISTS (
      SELECT 1
      FROM ssd_care_leavers clea
      WHERE clea.clea_person_id = p.pers_person_id

        -- [REVIEW] Opt: gate on latest contact being within cohort window
        AND clea.clea_care_leaver_latest_contact >= @ea_cohort_window_start
        AND clea.clea_care_leaver_latest_contact <  @ea_cohort_window_end

        -- [REVIEW] Opt: require they are considered in touch
        -- AND NULLIF(LTRIM(RTRIM(clea.clea_care_leaver_in_touch)), '') IS NOT NULL
    )

    -- AND @run_date >= DATEADD(year, 16, p.pers_dob) -- [REVIEW] classified 16-25 (at run date)
    -- AND @run_date <  DATEADD(year, 26, p.pers_dob) -- [REVIEW] classified 16-25 (at run date)
),


-- IsDisabled AS (
--     /*
--       Include if -any- disability code recorded
--       No dates, treat as ever recorded
--     */
--     SELECT DISTINCT d.disa_person_id AS person_id
--     FROM ssd_disability d
--     WHERE NULLIF(LTRIM(RTRIM(d.disa_disability_code)), '') IS NOT NULL
-- ),

SpecInclusion AS (
    /*
      Union of inclusion sets per spec
      de-dup across groups
    */
    SELECT person_id FROM ActiveReferral
    UNION SELECT person_id FROM WaitingAssessment
    UNION SELECT person_id FROM HasCINPlan
    -- UNION SELECT person_id FROM HasCPPlan
    UNION SELECT person_id FROM HasLAC
    UNION SELECT person_id FROM IsCareLeaver16to25
    -- UNION SELECT person_id FROM IsDisabled
),

/* === Payload builder 2016Sp1+/Azure SQL compatible === */
RawPayloads AS (
    SELECT
        -- LA Payload record id
        p.pers_person_id AS person_id,
        (
            -- DfE payload start 
            SELECT
                -- (Spec attribute numbers 2..55 commented)
                CAST(p.pers_person_id AS varchar(36)) AS [la_child_id],                             -- 2 :str(id) [Mandatory]
                -- CASE 
                --     WHEN p.pers_legacy_id IS NULL                                                   
                --         OR LTRIM(RTRIM(p.pers_legacy_id)) = '' THEN NULL
                --     ELSE CAST(p.pers_legacy_id AS varchar(36))
                -- END AS [mis_child_id],                                                              -- only exists in openjson spec
                CAST(0 AS bit) AS [purge],


                /* ================= child_details (3..15), per child, top level =================
                  - unique_pupil_number now from person table
                  - former_unique_pupil_number from linked_identifiers, latest by valid_from, ==13 chars
                  - disabilities prebuilt array, [] when none
                  - uasc_flag via case insensitive LIKE on immigration status
                */
                JSON_QUERY((
                    SELECT
                        p.pers_upn AS [unique_pupil_number],                                        -- 3

                        (SELECT TOP 1 
                                CASE 
                                    WHEN LEN(li2.link_identifier_value) = 13 
                                    THEN li2.link_identifier_value
                                END
                        FROM ssd_linked_identifiers li2
                        WHERE li2.link_person_id       = p.pers_person_id
                        AND li2.link_identifier_type = 'Former Unique Pupil Number'
                        ORDER BY li2.link_valid_from_date DESC
                        ) AS [former_unique_pupil_number],                                          -- 4

                        /* SSD data coerce into API JSON spec */
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
                        ) AS [unique_pupil_number_unknown_reason],                                  -- 5

                        p.pers_forename        AS [first_name],                                     -- 6
                        p.pers_surname         AS [surname],                                        -- 7
                        CONVERT(varchar(10), p.pers_dob,          23) AS [date_of_birth],           -- 8
                        CONVERT(varchar(10), p.pers_expected_dob, 23) AS [expected_date_of_birth],  -- 9

                        CASE 
                            WHEN p.pers_sex IN ('M', 'F') THEN p.pers_sex 
                            ELSE 'U' 
                        END AS [sex],                                                               -- 10

                        /* SSD data coerce into API JSON spec (Note: Max 12 codes in array! */
                        LEFT(NULLIF(LTRIM(RTRIM(p.pers_ethnicity)), ''), 4) AS [ethnicity],         -- 11

                        JSON_QUERY(
                            CASE 
                                WHEN disab.disabilities IS NOT NULL 
                                    THEN disab.disabilities 
                                -- force ["NONE"] when outer apply returns NULL|no disabilities
                                ELSE '["NONE"]'
                            END
                        ) AS [disabilities],                                                        -- 12
                                                     
                        (SELECT TOP 1 a.addr_address_postcode
                        FROM ssd_address a
                        WHERE a.addr_person_id = p.pers_person_id
                        ORDER BY a.addr_address_start_date DESC
                        ) AS [postcode],                                                            -- 13

                        CASE 
                            WHEN EXISTS (
                                SELECT 1
                                FROM ssd_immigration_status s
                                WHERE s.immi_person_id = p.pers_person_id
                                AND ISNULL(s.immi_immigration_status, '') 
                                    COLLATE Latin1_General_CI_AI LIKE '%UASC%'
                            ) THEN CAST(1 AS bit) 
                            ELSE CAST(0 AS bit) 
                        END AS [uasc_flag],                                                         -- 14

                        (SELECT TOP 1 CONVERT(varchar(10), s2.immi_immigration_status_end_date, 23)
                        FROM ssd_immigration_status s2
                        WHERE s2.immi_person_id = p.pers_person_id
                        ORDER BY 
                            CASE WHEN s2.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                            s2.immi_immigration_status_start_date DESC
                        ) AS [uasc_end_date],                                                       -- 15

                        CAST(0 AS bit) AS [purge] -- child_details purge
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                )) AS [child_details],

              
                /* ============ health_and_wellbeing (45..46), single object(or null), top level ============
                  - include SDQs for child in cohort window
                  - sdq scores ordered numeric array, TRY_CONVERT guard
                */
                /* [REVIEW] - revised - omit whole block when no SDQs in window */
                CASE WHEN sdq.has_sdq = 1
                    THEN JSON_QUERY((
                            SELECT
                                JSON_QUERY(sdq.sdq_assessments_json) AS [sdq_assessments],  -- 45, 46
                                CAST(0 AS bit)                       AS [purge]
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                          ))
                    ELSE NULL
                END AS [health_and_wellbeing],

                -- /* [REVIEW] - depreciated */
                -- JSON_QUERY((
                --     SELECT
                --         (
                --             SELECT
                --                 CONVERT(varchar(10), csdq.csdq_sdq_completed_date, 23) AS [date],   -- 45
                --                 TRY_CONVERT(int, csdq.csdq_sdq_score)                 AS [score]    -- 46
                --             FROM ssd_sdq_scores csdq
                --             WHERE csdq.csdq_person_id = p.pers_person_id
                --               AND csdq.csdq_sdq_score IS NOT NULL
                --               AND csdq.csdq_sdq_completed_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                --             ORDER BY csdq.csdq_sdq_completed_date DESC
                --             FOR JSON PATH
                --         ) AS [sdq_assessments],
                --         CAST(0 AS bit) AS [purge]
                --     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                -- )) AS [health_and_wellbeing],


                /* ================= social_care_episodes (16..44 and 47..55), array =================
                - include episode if referral_date <= window_end and close_date is null or >= window_start, overlap with cohort window
                - id string 36 chars max, referral_source 2 chars, closure_reason 3 chars, cast and trim as in spec
                - referral_no_further_action_flag derived only, not gate for inclusion, try convert to bit else map Y T 1 TRUE to 1, N F 0 FALSE to 0, else null
                - unused episode level purge false
                */
                JSON_QUERY((
                    SELECT
                        -- str(id) for JSON
                        CAST(cine.cine_referral_id AS varchar(36)) AS [social_care_episode_id],                             -- 16  [Mandatory]
                        CONVERT(varchar(10), cine.cine_referral_date, 23) AS [referral_date],                               -- 17
                        CASE
                          /* SSD data coerce into API JSON spec */
                          -- extracted data being coerced until superceded by change in source SSD data field for systemC users
                          WHEN cine.cine_referral_source_code IS NULL THEN NULL
                          WHEN LTRIM(RTRIM(cine.cine_referral_source_code)) LIKE '10%'        THEN '10'
                          WHEN LTRIM(RTRIM(cine.cine_referral_source_code)) LIKE '[1-3][A-F]%' THEN LEFT(LTRIM(RTRIM(cine.cine_referral_source_code)), 2)
                          WHEN LTRIM(RTRIM(cine.cine_referral_source_code)) LIKE '5[A-D]%'     THEN LEFT(LTRIM(RTRIM(cine.cine_referral_source_code)), 2)
                          WHEN LTRIM(RTRIM(cine.cine_referral_source_code)) LIKE '[46789]%'    THEN LEFT(LTRIM(RTRIM(cine.cine_referral_source_code)), 1)
                          ELSE NULL
                        END AS [referral_source],                                                                           -- 18    

                        CONVERT(varchar(10), cine.cine_close_date, 23) AS [closure_date],                                   -- 19

                        LEFT(NULLIF(LTRIM(RTRIM(cine.cine_close_reason)), ''), 3) AS [closure_reason]                       -- 20 

                        CASE
                            WHEN TRY_CONVERT(bit, cine.cine_referral_nfa) IS NOT NULL
                                THEN TRY_CONVERT(bit, cine.cine_referral_nfa)
                            -- SSD source enforces NCHAR(1) but some robustness added
                            -- SSD source field cine_referral_nfa in review as bool
                            WHEN UPPER(LTRIM(RTRIM(cine.cine_referral_nfa))) IN ('Y','T','1','TRUE')
                                THEN CAST(1 AS bit)
                            WHEN UPPER(LTRIM(RTRIM(cine.cine_referral_nfa))) IN ('N','F','0','FALSE')
                                THEN CAST(0 AS bit)
                            ELSE CAST(NULL AS bit)
                        END AS [referral_no_further_action_flag],                                                           -- 21


                        /* ================= child_and_family_assessments (22..25), array (or []) per episode =================
                          - include assessment if start or authorisation date in cohort window
                          - factors passed as JSON array, [] when none
                        */
                        JSON_QUERY((
                            SELECT
                                CAST(ca.cina_assessment_id AS varchar(36)) AS [child_and_family_assessment_id],             -- 22 [Mandatory]
                                CONVERT(varchar(10), ca.cina_assessment_start_date, 23) AS [start_date],                    -- 23
                                CONVERT(varchar(10), ca.cina_assessment_auth_date, 23)  AS [authorisation_date],            -- 24

                                JSON_QUERY(CASE
                                    -- Note: Max num of assessment factors defined in spec but not restricted here
                                    WHEN af.cinf_assessment_factors_json IS NULL
                                         OR af.cinf_assessment_factors_json = ''
                                        THEN '[]'
                                    ELSE af.cinf_assessment_factors_json
                                END) AS [factors],                                                                          -- 25
                                CAST(0 AS bit) AS [purge]
                            FROM ssd_cin_assessments ca
                            LEFT JOIN ssd_assessment_factors af
                                   ON af.cinf_assessment_id = ca.cina_assessment_id
                            WHERE ca.cina_referral_id = cine.cine_referral_id
                              AND (
                                    ca.cina_assessment_start_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                                 OR ca.cina_assessment_auth_date  BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                                  )
                            FOR JSON PATH
                        )) AS [child_and_family_assessments],



                        /* ================= child_in_need_plans (26..28), array (or []) per episode =================
                          - include CIN plan if plan dates overlap cohort window
                          - newest first by start date opt in outer ORDER
                        */
                        JSON_QUERY((
                            SELECT
                                CAST(cinp.cinp_cin_plan_id AS varchar(36)) AS [child_in_need_plan_id],                     -- 26 [Mandatory]
                                CONVERT(varchar(10), cinp.cinp_cin_plan_start_date, 23) AS [start_date],                   -- 27
                                CONVERT(varchar(10), cinp.cinp_cin_plan_end_date, 23)   AS [end_date],                     -- 28
                                CAST(0 AS bit) AS [purge]
                            FROM ssd_cin_plans cinp
                            WHERE cinp.cinp_referral_id = cine.cine_referral_id
                              AND cinp.cinp_cin_plan_start_date <= @ea_cohort_window_end
                              AND (cinp.cinp_cin_plan_end_date IS NULL
                                   OR cinp.cinp_cin_plan_end_date >= @ea_cohort_window_start)
                            FOR JSON PATH
                        )) AS [child_in_need_plans],



                        /* ============== section_47_assessments (29..33), array (or []) per episode ==============           
                          - CP flag derived only, does not filter
                          - Include S47 if
                              i) S47 dates overlap the cohort window, or
                              ii) there is >=1 ICPC for S47 with date inside cohort window
                          - OUTER APPLY for latest ICPC date per S47, avoid duplicate S47 rows if multiple ICPCs exist
                          - CP flag parsed from s47e_s47_outcome_json using JSON_VALUE If missing or not Y or N, flag returned as NULL     
                        */
                        JSON_QUERY((
                          -- [IMPORTANT]
                          -- There is a known bug impacting the extraction of these data points from MOSAIC 
                          -- See https://github.com/data-to-insight/ssd-data-model/issues/265 for updates
                            SELECT
                                CAST(s47e.s47e_s47_enquiry_id AS varchar(36)) AS [section_47_assessment_id],            -- 29 [Mandatory]
                                CONVERT(varchar(10), s47e.s47e_s47_start_date, 23) AS [start_date],                     -- 30

                                -- CP conference flag derived, not gate for inclusion
                                CASE
                                    WHEN JSON_VALUE(s47e.s47e_s47_outcome_json, '$.CP_CONFERENCE_FLAG')
                                        IN ('Y','T','1','true','True') THEN CAST(1 AS bit)
                                    WHEN JSON_VALUE(s47e.s47e_s47_outcome_json, '$.CP_CONFERENCE_FLAG')
                                        IN ('N','F','0','false','False') THEN CAST(0 AS bit)
                                    ELSE CAST(NULL AS bit)
                                END AS [icpc_required_flag],                                                            -- 31

                                -- Single ICPC date per S47, choose latest, avoid dup rows from possible multiple ICPC records
                                CONVERT(varchar(10), icpc.icpc_icpc_date, 23) AS [icpc_date],                           -- 32

                                -- Keep end date if present
                                CONVERT(varchar(10), s47e.s47e_s47_end_date, 23) AS [end_date],                         -- 33
                                CAST(0 AS bit) AS [purge]
                            FROM ssd_s47_enquiry s47e

                            OUTER APPLY (
                                SELECT TOP 1 i.icpc_icpc_date
                                FROM ssd_initial_cp_conference i
                                WHERE i.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                                ORDER BY i.icpc_icpc_date DESC
                            ) AS icpc

                            WHERE s47e.s47e_referral_id = cine.cine_referral_id
                              AND (
                                    -- Overlap test, include if S47 period intersects cohort window 
                                    (s47e.s47e_s47_start_date <= @ea_cohort_window_end
                                    AND (s47e.s47e_s47_end_date IS NULL OR s47e.s47e_s47_end_date >= @ea_cohort_window_start))
                                    -- Or include if ICPC in window, even where S47 dates outside window 
                                OR (icpc.icpc_icpc_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end)
                              )
                            FOR JSON PATH
                        )) AS [section_47_assessments],




                        /* ================= child_protection_plans (34..36), array (or []) per episode =================
                          - include CP plan if plan dates overlap cohort window
                        */
                        JSON_QUERY((
                            SELECT
                                CAST(cppl.cppl_cp_plan_id AS varchar(36)) AS [child_protection_plan_id],                 -- 34 [Mandatory]
                                CONVERT(varchar(10), cppl.cppl_cp_plan_start_date, 23) AS [start_date],                  -- 35
                                CONVERT(varchar(10), cppl.cppl_cp_plan_end_date, 23)   AS [end_date],                    -- 36
                                CAST(0 AS bit) AS [purge]
                            FROM ssd_cp_plans cppl
                            WHERE cppl.cppl_referral_id = cine.cine_referral_id
                              AND cppl.cppl_cp_plan_start_date <= @ea_cohort_window_end
                              AND (cppl.cppl_cp_plan_end_date IS NULL
                                   OR cppl.cppl_cp_plan_end_date >= @ea_cohort_window_start)
                            FOR JSON PATH
                        )) AS [child_protection_plans],



                        /* ================= child_looked_after_placements (37..44), array (or []) per episode =================
                          - include placement if placement dates overlap cohort window
                          - group by placement id to prevent duplication in case episode joins +1 rows
                          - start_reason, end_reason taken from min across episode reasons per placement, consistent single code
                        */
                        JSON_QUERY((
                            SELECT
                                CAST(clap.clap_cla_placement_id AS varchar(36)) AS [child_looked_after_placement_id],             -- 37 [Mandatory]
                                CONVERT(varchar(10), clap.clap_cla_placement_start_date, 23) AS [start_date],                     -- 38

                                /* SSD data coerce into API JSON spec */
                                -- this data point being coerced until superceded by change in source data field for systemC users
                                MIN(LEFT(NULLIF(LTRIM(RTRIM(clae.clae_cla_episode_start_reason)), ''), 1)) AS [start_reason],     -- 39 
                                
                                clap.clap_cla_placement_postcode AS [postcode],                                                   -- 40
                                
                                /* SSD data coerce into API JSON spec */
                                LEFT(NULLIF(LTRIM(RTRIM(clap.clap_cla_placement_type)), ''), 2) AS [placement_type],              -- 41

                                CONVERT(
                                    varchar(10),
                                    CASE
                                        WHEN clap.clap_cla_placement_end_date IS NULL
                                            OR clap.clap_cla_placement_end_date >= clap.clap_cla_placement_start_date
                                            THEN clap.clap_cla_placement_end_date
                                        ELSE NULL
                                    END,
                                    23
                                ) AS [end_date],                                                                                  -- 42

                                /* SSD data coerce into API JSON spec */
                                MIN(          -- different approach needed here as needed raw data part has varied length
                                  NULLIF(     -- this process to be superceded by replacement source field for systemC users
                                    REPLACE(
                                      REPLACE(
                                        REPLACE(
                                          REPLACE(LEFT(clae.clae_cla_episode_ceased_reason, 3), ' ', ''),   -- remove spaces after max length truncation
                                        CHAR(9), ''),   -- tabs
                                      CHAR(10), ''),    -- LF
                                    CHAR(13), ''),      -- CR
                                    ''                  -- empty string to NULL
                                  )
                                ) AS [end_reason],                                                                                -- 43

                                clap.clap_cla_placement_change_reason AS [change_reason],                                         -- 44
                                
                                CAST(0 AS bit) AS [purge]
                            FROM ssd_cla_episodes clae
                            JOIN ssd_cla_placement clap
                            ON clap.clap_cla_id = clae.clae_cla_id
                            WHERE clae.clae_referral_id = cine.cine_referral_id
                            -- AND clap.clap_cla_placement_type <> 'T0'    -- IF LA not reporting some (e.g. TEMP) placements
                            AND clap.clap_cla_placement_start_date <= @ea_cohort_window_end
                            AND (
                                    clap.clap_cla_placement_end_date IS NULL
                                OR clap.clap_cla_placement_end_date >= @ea_cohort_window_start
                                )
                            GROUP BY
                                clap.clap_cla_placement_id,
                                clap.clap_cla_placement_start_date,
                                clap.clap_cla_placement_type,
                                clap.clap_cla_placement_postcode,
                                clap.clap_cla_placement_end_date,
                                clap.clap_cla_placement_change_reason
                            ORDER BY clap.clap_cla_placement_start_date DESC
                            FOR JSON PATH
                        )) AS [child_looked_after_placements],



                        /* ================= adoption (47..49), single object(or null) per episode =================
                          - include adoption object when any permanence date in window
                          - choose latest by placed, then matched, then decision
                        */
                        JSON_QUERY((
                            SELECT TOP 1
                                CONVERT(varchar(10), perm.perm_adm_decision_date, 23)        AS [initial_decision_date],        -- 47
                                CONVERT(varchar(10), perm.perm_matched_date, 23)             AS [matched_date],                 -- 48
                                CONVERT(varchar(10), perm.perm_placed_for_adoption_date, 23) AS [placed_date],                  -- 49
                                CAST(0 AS bit) AS [purge]
                            FROM ssd_permanence perm
                            WHERE (perm.perm_person_id = p.pers_person_id
                                   OR perm.perm_cla_id IN (
                                        SELECT clae2.clae_cla_id
                                        FROM ssd_cla_episodes clae2
                                        WHERE clae2.clae_person_id = p.pers_person_id
                                   ))
                              AND (
                                    perm.perm_adm_decision_date        BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                                 OR perm.perm_matched_date             BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                                 OR perm.perm_placed_for_adoption_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                                  )
                            ORDER BY COALESCE(
                                        perm.perm_placed_for_adoption_date,
                                        perm.perm_matched_date,
                                        perm.perm_adm_decision_date
                                     ) DESC
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                        )) AS [adoption],


                        /* ================= care_leavers (50..52), single object(or null) per episode =================
                          - latest contact in window
                        */
                        JSON_QUERY((
                            SELECT TOP 1
                                CONVERT(varchar(10), clea.clea_care_leaver_latest_contact, 23) AS [contact_date],          -- 50
                                clea.clea_care_leaver_activity AS [activity],                                              -- 51
                                clea.clea_care_leaver_accommodation AS [accommodation],                                    -- 52
                                CAST(0 AS bit) AS [purge]
                              FROM ssd_care_leavers clea
                             WHERE clea.clea_person_id = p.pers_person_id
                               -- NOTE: cohort gating for care leavers now handled in IsCareLeaver16to25 CTE
                               -- AND clea.clea_care_leaver_latest_contact BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                             ORDER BY clea.clea_care_leaver_latest_contact DESC
                             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                        )) AS [care_leavers],


                        /* ================= care_worker_details (53..55), array (or []) per episode =================
                          - join involvements by referral, include rows overlapping window
                          - newest first by start date
                        */
                        JSON_QUERY((
                            SELECT
                                -- CAST(pr.prof_staff_id AS varchar(12)) AS [worker_id],                                    -- 53 IF LA workerID contains only ID's
                                CAST(pr.prof_social_worker_registration_no AS varchar(12)) AS [worker_id],                  -- 53 IF LA workerID is username use SWE REG instead
                                CONVERT(varchar(10), i.invo_involvement_start_date, 23) AS [start_date],                    -- 54
                                CONVERT(varchar(10), i.invo_involvement_end_date, 23) AS [end_date]                         -- 55
                            FROM ssd_involvements i
                            JOIN ssd_professionals pr
                              ON i.invo_professional_id = pr.prof_professional_id
                            WHERE i.invo_referral_id = cine.cine_referral_id
                              AND i.invo_involvement_start_date <= @ea_cohort_window_end
                              AND (i.invo_involvement_end_date IS NULL
                                   OR i.invo_involvement_end_date >= @ea_cohort_window_start)
                            ORDER BY i.invo_involvement_start_date DESC
                            FOR JSON PATH
                        )) AS [care_worker_details],

                        CAST(0 AS bit) AS [purge]
                      FROM ssd_cin_episodes cine
                     WHERE cine.cine_person_id = p.pers_person_id
                       AND cine.cine_referral_date <= @ea_cohort_window_end
                       AND (cine.cine_close_date IS NULL OR cine.cine_close_date >= @ea_cohort_window_start)
                     FOR JSON PATH
                )) AS [social_care_episodes]

            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS json_payload

    -- keep only records who (a) pass age/unborn gate and (b) match at least one api spec groups
    FROM ssd_person p
    JOIN EligibleBySpec elig ON elig.pers_person_id = p.pers_person_id -- either unborn, or 26th bday falls on or after @ea_cohort_window_start (deceased not filtered)
    JOIN SpecInclusion  si   ON si.person_id        = p.pers_person_id -- appearing in ActiveReferral, WaitingAssessment, CIN plan, CP plan, LAC, Care leavers 16 to 25, Disabled

    /* Disabilities array, return NULL when no codes */
    OUTER APPLY (
        SELECT
          CASE
            WHEN EXISTS (
              SELECT 1
              FROM ssd_disability d0
              WHERE d0.disa_person_id = p.pers_person_id
                AND NULLIF(LTRIM(RTRIM(d0.disa_disability_code)), '') IS NOT NULL
            )
            THEN JSON_QUERY(
              N'[' +
              STUFF((
                  SELECT N',' + QUOTENAME(u.code, '"')
                  FROM (
                      SELECT TOP (12)
                          UPPER(LTRIM(RTRIM(d2.disa_disability_code))) AS code
                      FROM ssd_disability d2
                      WHERE d2.disa_person_id = p.pers_person_id
                        AND NULLIF(LTRIM(RTRIM(d2.disa_disability_code)), '') IS NOT NULL
                      GROUP BY UPPER(LTRIM(RTRIM(d2.disa_disability_code)))
                      ORDER BY UPPER(LTRIM(RTRIM(d2.disa_disability_code)))
                  ) u
                  FOR XML PATH(''), TYPE
              ).value('.', 'nvarchar(max)'), 1, 1, N'')
              + N']'
            )
            ELSE NULL
          END AS disabilities
    ) AS disab

    /* SDQ prebuild, reuse once, and flag presence */
    OUTER APPLY (
        SELECT
            (
                SELECT
                    CONVERT(varchar(10), csdq.csdq_sdq_completed_date, 23) AS [date],   -- 45
                    TRY_CONVERT(int, csdq.csdq_sdq_score)                  AS [score]   -- 46
                FROM ssd_sdq_scores csdq
                WHERE csdq.csdq_person_id = p.pers_person_id
                  AND csdq.csdq_sdq_score IS NOT NULL
                  AND csdq.csdq_sdq_completed_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                ORDER BY csdq.csdq_sdq_completed_date DESC
                FOR JSON PATH
            ) AS sdq_assessments_json,
            CASE WHEN EXISTS (
                SELECT 1
                FROM ssd_sdq_scores csdq
                WHERE csdq.csdq_person_id = p.pers_person_id
                  AND csdq.csdq_sdq_score IS NOT NULL
                  AND csdq.csdq_sdq_completed_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
            ) THEN 1 ELSE 0 END AS has_sdq
    ) AS sdq

),   -- close RawPayloads CTE
  

/* hash payload + compare, de-dup by person_id and payload content
   Note: SHA2_256 used for change detection only
*/
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

-- /* Uncomment to force hard-filter against LA known Stat-Returns cohort table*/
-- INNER JOIN
--     [dbo].[StoredStatReturnsCohortIdTable] STATfilter -- FAILSAFE STAT RETURN COHORT
--     ON STATfilter.[person_id] = h.person_id

WHERE prev.current_hash IS NULL             -- first time we've seen this person record
   OR prev.current_hash <> h.current_hash;  -- or payload has changed



-- -- -- Optional
-- -- CREATE INDEX IX_ssd_cin_episodes_dates      ON ssd_cin_episodes(cine_person_id, cine_referral_date, cine_close_date);
-- -- CREATE INDEX IX_ssd_cin_plans_dates         ON ssd_cin_plans(cinp_person_id, cinp_cin_plan_start_date, cinp_cin_plan_end_date);
-- -- CREATE INDEX IX_ssd_cp_plans_dates          ON ssd_cp_plans(cppl_person_id, cppl_cp_plan_start_date, cppl_cp_plan_end_date);
-- -- CREATE INDEX IX_ssd_cla_placements_dates    ON ssd_cla_placement(clap_cla_id, clap_cla_placement_start_date, clap_cla_placement_end_date);
-- -- CREATE INDEX IX_ssd_care_leavers_date       ON ssd_care_leavers(clea_person_id, clea_care_leaver_latest_contact);
-- -- CREATE INDEX IX_ssd_sdq_date                ON ssd_sdq_scores(csdq_person_id, csdq_sdq_completed_date);

-- -- CREATE UNIQUE INDEX UX_ssd_api_person_hash ON ssd_api_data_staging(person_id, current_hash);





-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"}
-- =============================================================================
-- Description: Table for TEST|ANON API payload and logging 
-- This table is NON-live and solely for the pre-live data/api testing. 

-- Table data sent only to Children in Social Care Data Receiver (TEST)

-- To be depreciated/removed at any point by the LA; we'd expect this to be after 
-- the toggle to LIVE sends are initiated to DfE LIVE Pre-Production(PP) and Production(P) endpoints. 
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