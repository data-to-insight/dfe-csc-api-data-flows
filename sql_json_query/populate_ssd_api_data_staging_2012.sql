-- define as required 
use HDM_Local; -- Note: this the SystemC/LLogic default, LA should change to bespoke 

/* ==========================================================================
   D2I CSC API Payload Builder, Legacy SQL Server 2012 compatible
   - No OPENJSON, JSON_VALUE, STRING_AGG
   - JSON built with QUOTENAME + FOR XML PATH
   ========================================================================== */


/* Note for: Daily Data Flows Early Adopters
The following table definitions (and populating) can only be run <after> the main SSD script, OR the following definitions
can be appended into the main SSD and run as one - insert locations within the SSD are marked via the meta tags of:

-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging"}
-- =============================================================================
&
-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"}
-- =============================================================================


-- Script compatibility and defaults
-- Default uses XML PATH for aggregations, SQL Server 2012+

*/


-- Data pre/smoke test validator(s) (optional) --
-- D2I offers a seperate <simplified> validation VIEW towards your local data verification checks,
-- this offers some pre-process comparison between your data and the DfE API payload schema 
-- File: (SQL 2016+)https://github.com/data-to-insight/dfe-csc-api-data-flows/tree/main/pre_flight_checks/ssd_vw_csc_api_schema_checks.sql
-- -- 




DECLARE @VERSION nvarchar(32) = N'0.2.5';
RAISERROR(N'== CSC API staging build: v%s ==', 10, 1, @VERSION) WITH NOWAIT;


-- -- Apply if/when d2i staging table structual changes have been newly applied
-- IF OBJECT_ID(N'ssd_api_data_staging_anon', N'U') IS NOT NULL DROP TABLE ssd_api_data_staging_anon;
-- IF OBJECT_ID(N'ssd_api_data_staging', N'U') IS NOT NULL DROP TABLE ssd_api_data_staging;
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




/* === EA Spec window, dynamic: 24 months back to FY start on 1 April === */
DECLARE @run_date       date = CONVERT(date, GETDATE());
DECLARE @months_back    int  = 24;
DECLARE @fy_start_month int  = 4;

DECLARE @anchor date = DATEADD(month, -@months_back, @run_date);

DECLARE @fy_start_year int =
  YEAR(@anchor) - CASE WHEN MONTH(@anchor) < @fy_start_month THEN 1 ELSE 0 END;

-- datetime2 for cohort window
DECLARE @ea_cohort_window_start datetime2(0) = DATEFROMPARTS(@fy_start_year, @fy_start_month, 1);
DECLARE @ea_cohort_window_end   datetime2(0) = CAST(@run_date AS datetime2(0));



;WITH
EligibleBySpec AS (
  /* unborn or 26th birthday on/after window start */
  SELECT p.pers_person_id
  FROM ssd_person p
  WHERE (p.pers_expected_dob IS NOT NULL)
     OR (p.pers_dob IS NOT NULL AND DATEADD(year, 26, p.pers_dob) >= @ea_cohort_window_start)
),
ActiveReferral AS (
  SELECT DISTINCT cine.cine_person_id AS person_id
  FROM ssd_cin_episodes cine
  WHERE cine.cine_referral_date <= @ea_cohort_window_end
    AND (cine.cine_close_date IS NULL OR cine.cine_close_date >= @ea_cohort_window_start)
    AND (cine.cine_close_date IS NULL OR cine.cine_close_date >  @run_date)
),
WaitingAssessment AS (
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
  SELECT DISTINCT cinp.cinp_person_id AS person_id
  FROM ssd_cin_plans cinp
  WHERE cinp.cinp_cin_plan_start_date <= @ea_cohort_window_end
    AND (cinp.cinp_cin_plan_end_date IS NULL OR cinp.cinp_cin_plan_end_date >= @ea_cohort_window_start)
),
HasCPPlan AS (
  SELECT DISTINCT cppl.cppl_person_id AS person_id
  FROM ssd_cp_plans cppl
  WHERE cppl.cppl_cp_plan_start_date <= @ea_cohort_window_end
    AND (cppl.cppl_cp_plan_end_date IS NULL OR cppl.cppl_cp_plan_end_date >= @ea_cohort_window_start)
),
HasLAC AS (
  /* A: LAC linked to CIN episode overlapping window */
  SELECT DISTINCT clae.clae_person_id AS person_id
  FROM ssd_cla_episodes clae
  JOIN ssd_cin_episodes cine
    ON cine.cine_referral_id = clae.clae_referral_id
  WHERE cine.cine_referral_date <= @ea_cohort_window_end
    AND (cine.cine_close_date IS NULL OR cine.cine_close_date >= @ea_cohort_window_start)
  UNION
  /* B: any placement overlapping window */
  SELECT DISTINCT clae2.clae_person_id AS person_id
  FROM ssd_cla_episodes clae2
  JOIN ssd_cla_placement clap
    ON clap.clap_cla_id = clae2.clae_cla_id
  WHERE clap.clap_cla_placement_start_date <= @ea_cohort_window_end
    AND (clap.clap_cla_placement_end_date IS NULL OR clap.clap_cla_placement_end_date >= @ea_cohort_window_start)
),
IsCareLeaver16to25 AS (
  SELECT DISTINCT clea.clea_person_id AS person_id
  FROM ssd_care_leavers clea
  JOIN ssd_person p ON p.pers_person_id = clea.clea_person_id
  WHERE clea.clea_care_leaver_latest_contact BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
    AND (
         (p.pers_dob IS NOT NULL AND DATEDIFF(year, p.pers_dob, @run_date) BETWEEN 16 AND 25)
      OR (p.pers_dob IS NULL AND p.pers_expected_dob IS NOT NULL)
    )
),
IsDisabled AS (
  SELECT DISTINCT d.disa_person_id AS person_id
  FROM ssd_disability d
  WHERE NULLIF(LTRIM(RTRIM(d.disa_disability_code)), '') IS NOT NULL
),
SpecInclusion AS (
  SELECT person_id FROM ActiveReferral
  UNION SELECT person_id FROM WaitingAssessment
  UNION SELECT person_id FROM HasCINPlan
  UNION SELECT person_id FROM HasCPPlan
  UNION SELECT person_id FROM HasLAC
  UNION SELECT person_id FROM IsCareLeaver16to25
  UNION SELECT person_id FROM IsDisabled
),

/* ====================== Payload builder, 2012-safe ======================= */
RawPayloads AS (
  SELECT
    p.pers_person_id AS person_id,

    /* disabilities array as JSON text like ["A","B"] or [] */
    dis.disabilities_json,

    /* child_details JSON object, attributes 3..15 */
    cd.child_details_json,

    /* health_and_wellbeing JSON object, attributes 45..46, top level per child */
    hw.health_json,

    /* episodes array JSON, attributes 16..44 and 47..55 */
    ep.episodes_json,

    /* final payload assembly, includes 2 and top purge flag */
    '{'
      + '"la_child_id":"'   + LEFT(CONVERT(varchar(36), p.pers_person_id), 36) + '",'              -- 2
      + '"mis_child_id":"'  + LEFT(CONVERT(varchar(36), ISNULL(p.pers_single_unique_id, 'SSD_SUI')), 36) + '",'
      + '"child_details":'  + cd.child_details_json + ','
      + '"health_and_wellbeing":' + hw.health_json + ','
      + '"social_care_episodes":' + ep.episodes_json + ','
      + '"purge":false'
    + '}' AS json_payload

  FROM ssd_person p
  JOIN EligibleBySpec elig ON elig.pers_person_id = p.pers_person_id
  JOIN SpecInclusion  si   ON si.person_id        = p.pers_person_id

  /* build disabilities array once */
  OUTER APPLY (
    SELECT
      '[' + ISNULL(
        STUFF((
          SELECT
            ',' + '"' + u.code + '"'
          FROM (
            SELECT DISTINCT
              LEFT(UPPER(LTRIM(RTRIM(d2.disa_disability_code))), 4) AS code
            FROM ssd_disability AS d2
            WHERE d2.disa_person_id = p.pers_person_id
              AND d2.disa_disability_code IS NOT NULL
              AND LTRIM(RTRIM(d2.disa_disability_code)) <> ''
          ) u
          FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 1, ''), ''
      ) + ']' AS disabilities_json
  ) AS dis

  -- Child details (Attributes 3..15)
CROSS APPLY (
  SELECT
    '{'
      + '"unique_pupil_number":'
        + CASE 
            WHEN NULLIF(LTRIM(RTRIM(p.pers_upn)), '') IS NULL
              THEN 'null'
            ELSE '"' + p.pers_upn + '"'
          END                                                                                                   -- 3
      + ',"former_unique_pupil_number":'
        + ISNULL((
            SELECT TOP 1
              '"' + li2.link_identifier_value + '"'
            FROM ssd_linked_identifiers li2
            WHERE li2.link_person_id = p.pers_person_id
              AND li2.link_identifier_type = 'Former Unique Pupil Number'
              AND LEN(li2.link_identifier_value) = 13
              AND TRY_CONVERT(bigint, li2.link_identifier_value) IS NOT NULL
            ORDER BY li2.link_valid_from_date DESC
          ), 'null')                                                                                            -- 4
      + ',"unique_pupil_number_unknown_reason":' + ISNULL('"' + LEFT(p.pers_upn_unknown, 3) + '"', 'null')      -- 5
      + ',"first_name":'   + ISNULL('"' + REPLACE(p.pers_forename, '"', '\"') + '"', 'null')                    -- 6
      + ',"surname":'      + ISNULL('"' + REPLACE(p.pers_surname , '"', '\"') + '"', 'null')                    -- 7
      + ',"date_of_birth":' + CASE WHEN p.pers_dob IS NULL
                                   THEN 'null' ELSE '"' + CONVERT(varchar(10), p.pers_dob, 23) + '"' END        -- 8
      + ',"expected_date_of_birth":' + CASE WHEN p.pers_expected_dob IS NULL
                                            THEN 'null' ELSE '"' + CONVERT(varchar(10), p.pers_expected_dob, 23) + '"' END -- 9
      + ',"sex":"' + CASE WHEN p.pers_sex IN ('M','F') THEN p.pers_sex ELSE 'U' END + '"'                        -- 10
      + ',"ethnicity":' + ISNULL('"' + LEFT(p.pers_ethnicity, 4) + '"', 'null')                                 -- 11
      + ',"disabilities":' + dis.disabilities_json                                                              -- 12
      + ',"postcode":'
        + ISNULL((
            SELECT
              '"' + LEFT(REPLACE(LTRIM(RTRIM(aa.addr_address_postcode)), ' ', ''), 8) + '"'
            FROM (
              SELECT TOP 1 a.addr_address_postcode
              FROM ssd_address a
              WHERE a.addr_person_id = p.pers_person_id
              ORDER BY a.addr_address_start_date DESC
            ) aa
          ), 'null')                                                                                             -- 13
      + ',"uasc_flag":' + CASE
                            WHEN EXISTS (
                              SELECT 1
                              FROM ssd_immigration_status s
                              WHERE s.immi_person_id = p.pers_person_id
                                AND ISNULL(s.immi_immigration_status, '') COLLATE Latin1_General_CI_AI LIKE '%UASC%'
                            ) THEN '1' ELSE '0'
                          END                                                                                    -- 14
      + ',"uasc_end_date":'
          + ISNULL((
              SELECT TOP 1
                '"' + CONVERT(varchar(10), s2.immi_immigration_status_end_date, 23) + '"'
              FROM ssd_immigration_status s2
              WHERE s2.immi_person_id = p.pers_person_id
              ORDER BY CASE WHEN s2.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                       s2.immi_immigration_status_start_date DESC
            ), 'null')                                                                                           -- 15
      + ',"purge":false'
    + '}' AS child_details_json
) AS cd


  -- Health and wellbeing (45..46) (per child not episode)
  -- Returns: object with sdq_assessments array
  CROSS APPLY (
    SELECT
      '{'
        + '"sdq_assessments":'
        + '[' + ISNULL(
            STUFF((
              SELECT
                ',' + '{'
                  + '"date":"'  + CONVERT(varchar(10), csdq.csdq_sdq_completed_date, 23) + '",'                               -- 45
                  + '"score":'  + CAST(TRY_CONVERT(int, csdq.csdq_sdq_score) AS nvarchar(12))                                 -- 46
                + '}'
              FROM ssd_sdq_scores csdq
              WHERE csdq.csdq_person_id = p.pers_person_id
                AND TRY_CONVERT(int, csdq.csdq_sdq_score) IS NOT NULL
                AND csdq.csdq_sdq_completed_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
              ORDER BY csdq.csdq_sdq_completed_date DESC
              FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(max)'), 1, 1, ''), '')
        + ']'
        + ',"purge":false'
      + '}' AS health_json
  ) AS hw

  -- Social care episodes (Attributes 16..55)
  -- Returns: array
  OUTER APPLY (
    SELECT
      '[' + ISNULL(
        STUFF((
          SELECT
            ',' + '{' -- str(id) for JSON
              + '"social_care_episode_id":"' + LEFT(CONVERT(varchar(36), cine.cine_referral_id), 36) + '",'      -- 16
              + '"referral_date":"' + CONVERT(varchar(10), cine.cine_referral_date, 23) + '",'                    -- 17
              + '"referral_source":"' + LEFT(cine.cine_referral_source_code, 2) + '",'                            -- 18
              + '"closure_date":' + CASE WHEN cine.cine_close_date IS NULL THEN 'null'
                                         ELSE '"' + CONVERT(varchar(10), cine.cine_close_date, 23) + '"' END + ',' -- 19
              + '"closure_reason":' + ISNULL('"' + LEFT(cine.cine_close_reason, 3) + '"', 'null') + ','           -- 20
              + '"referral_no_further_action_flag":'
                + CASE
                    WHEN TRY_CONVERT(bit, cine.cine_referral_nfa) IS NOT NULL
                      THEN CAST(TRY_CONVERT(int, cine.cine_referral_nfa) AS nvarchar(1))

                    -- SSD source enforces NCHAR(1) but some robustness added
                    -- SSD source field cine_referral_nfa in review as bool
                    WHEN UPPER(LTRIM(RTRIM(cine.cine_referral_nfa))) IN ('Y','T','1','TRUE')  THEN '1'
                    WHEN UPPER(LTRIM(RTRIM(cine.cine_referral_nfa))) IN ('N','F','0','FALSE') THEN '0'
                    ELSE 'null'
                  END + ','                                                                                       -- 21

              -- Child and family assessments (22..25)
              -- Returns: array (or [])
              + '"child_and_family_assessments":'
              + '[' + ISNULL(
                  STUFF((
                    SELECT
                      ',' + '{'
                        + '"child_and_family_assessment_id":' + CASE WHEN ca.cina_assessment_id IS NULL
                                                                      THEN 'null' ELSE '"' + LEFT(CONVERT(varchar(36), ca.cina_assessment_id), 36) + '"' END + ','  -- 22
                        + '"start_date":'        + CASE WHEN ca.cina_assessment_start_date IS NULL
                                                          THEN 'null' ELSE '"' + CONVERT(varchar(10), ca.cina_assessment_start_date, 23) + '"' END + ','            -- 23
                        + '"authorisation_date":' + CASE WHEN ca.cina_assessment_auth_date  IS NULL
                                                          THEN 'null' ELSE '"' + CONVERT(varchar(10), ca.cina_assessment_auth_date , 23) + '"' END + ','            -- 24
                        + '"assessment_factors":' + ISNULL(NULLIF(af.cinf_assessment_factors_json, ''), '[]') + ','                                                  -- 25
                        + '"purge":false'
                      + '}'
                    FROM ssd_cin_assessments ca
                    LEFT JOIN ssd_assessment_factors af
                      ON af.cinf_assessment_id = ca.cina_assessment_id
                    WHERE ca.cina_referral_id = cine.cine_referral_id
                      AND (
                           ca.cina_assessment_start_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                           OR ca.cina_assessment_auth_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                      )
                    FOR XML PATH(''), TYPE
                  ).value('.', 'nvarchar(max)'), 1, 1, ''), '')
              + '],' + 

              -- Child in need plans (26..28)
              -- Returns: array (or [])
              '"child_in_need_plans":'
              + '[' + ISNULL(
                  STUFF((
                    SELECT
                      ',' + '{'
                        + '"child_in_need_plan_id":"' + LEFT(CONVERT(varchar(36), cinp.cinp_cin_plan_id), 36) + '",'            -- 26
                        + '"start_date":"' + CONVERT(varchar(10), cinp.cinp_cin_plan_start_date, 23) + '",'                      -- 27
                        + '"end_date":' + CASE WHEN cinp.cinp_cin_plan_end_date IS NULL
                                                THEN 'null' ELSE '"' + CONVERT(varchar(10), cinp.cinp_cin_plan_end_date, 23) + '"' END + ',' -- 28
                        + '"purge":false'
                      + '}'
                    FROM ssd_cin_plans cinp
                    WHERE cinp.cinp_referral_id = cine.cine_referral_id
                      AND cinp.cinp_cin_plan_start_date <= @ea_cohort_window_end
                      AND (cinp.cinp_cin_plan_end_date IS NULL OR cinp.cinp_cin_plan_end_date >= @ea_cohort_window_start)
                    FOR XML PATH(''), TYPE
                  ).value('.', 'nvarchar(max)'), 1, 1, ''), '')
              + '],' +

              -- s47 assessments (29..33)
              -- Returns: array (or [])
              '"section_47_assessments":'
              + '[' + ISNULL(
                  STUFF((
                    SELECT
                      ',' + '{'
                        + '"section_47_assessment_id":"' + LEFT(CONVERT(varchar(36), s47e.s47e_s47_enquiry_id), 36) + '",'       -- 29
                        + '"start_date":"' + CONVERT(varchar(10), s47e.s47e_s47_start_date, 23) + '",'                            -- 30
                        + '"icpc_required_flag":'
                          + CASE -- CP flag via string search */
                              WHEN CHARINDEX('"CP_CONFERENCE_FLAG":"Y"', s47e.s47e_s47_outcome_json) > 0 THEN '1'
                              WHEN CHARINDEX('"CP_CONFERENCE_FLAG":"N"', s47e.s47e_s47_outcome_json) > 0 THEN '0'
                              ELSE 'null'
                            END + ','                                                                                             -- 31
                        + '"icpc_date":' + CASE WHEN icpc.icpc_icpc_date IS NULL
                                               THEN 'null' ELSE '"' + CONVERT(varchar(10), icpc.icpc_icpc_date, 23) + '"' END + ',' -- 32
                        + '"end_date":' + CASE WHEN s47e.s47e_s47_end_date IS NULL
                                               THEN 'null' ELSE '"' + CONVERT(varchar(10), s47e.s47e_s47_end_date, 23) + '"' END + ',' -- 33
                        + '"purge":false'
                      + '}'
                    FROM ssd_s47_enquiry s47e
                    LEFT JOIN ssd_initial_cp_conference icpc
                      ON icpc.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                    WHERE s47e.s47e_referral_id = cine.cine_referral_id
                      AND (
                           s47e.s47e_s47_start_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                           OR s47e.s47e_s47_end_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                           OR icpc.icpc_icpc_date BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                      )
                    FOR XML PATH(''), TYPE
                  ).value('.', 'nvarchar(max)'), 1, 1, ''), '')
              + '],' +

              -- Child protection plans (34..36)
              -- Returns: array (or [])
              '"child_protection_plans":'
              + '[' + ISNULL(
                  STUFF((
                    SELECT
                      ',' + '{'
                        + '"child_protection_plan_id":"' + LEFT(CONVERT(varchar(36), cppl.cppl_cp_plan_id), 36) + '",'           -- 34
                        + '"start_date":"' + CONVERT(varchar(10), cppl.cppl_cp_plan_start_date, 23) + '",'                       -- 35
                        + '"end_date":' + CASE WHEN cppl.cppl_cp_plan_end_date IS NULL
                                              THEN 'null' ELSE '"' + CONVERT(varchar(10), cppl.cppl_cp_plan_end_date, 23) + '"' END + ',' -- 36
                        + '"purge":false'
                      + '}'
                    FROM ssd_cp_plans cppl
                    WHERE cppl.cppl_referral_id = cine.cine_referral_id
                      AND cppl.cppl_cp_plan_start_date <= @ea_cohort_window_end
                      AND (cppl.cppl_cp_plan_end_date IS NULL OR cppl.cppl_cp_plan_end_date >= @ea_cohort_window_start)
                    FOR XML PATH(''), TYPE
                  ).value('.', 'nvarchar(max)'), 1, 1, ''), '')
              + '],' +

              -- Looked after placements (37..44)
              -- Returns: array (or [])
              '"child_looked_after_placements":'
              + '[' + ISNULL(
                  STUFF((
                    SELECT
                      ',' + '{'
                        + '"child_looked_after_placement_id":"' + LEFT(CONVERT(varchar(36), g.clap_cla_placement_id), 36) + '",'  -- 37
                        + '"start_date":"' + CONVERT(varchar(10), g.clap_cla_placement_start_date, 23) + '",'                     -- 38
                        + '"start_reason":"' + g.start_reason + '",'                                                              -- 39
                        + '"postcode":"' + REPLACE(LTRIM(RTRIM(LEFT(g.clap_cla_placement_postcode, 8))), ' ', '') + '",'          -- 40
                        + '"placement_type":"' + LEFT(g.clap_cla_placement_type, 2) + '",'                                        -- 41
                        + '"end_date":' + CASE WHEN g.clap_cla_placement_end_date IS NULL
                                              THEN 'null' ELSE '"' + CONVERT(varchar(10), g.clap_cla_placement_end_date, 23) + '"' END + ',' -- 42
                        + '"end_reason":"' + g.end_reason + '",'                                                                  -- 43
                        + '"change_reason":"' + LEFT(g.clap_cla_placement_change_reason, 6) + '",'                                -- 44
                        + '"purge":false'
                      + '}'
                    FROM (
                      SELECT
                        clap.clap_cla_placement_id,
                        clap.clap_cla_placement_start_date,
                        clap.clap_cla_placement_type,
                        clap.clap_cla_placement_postcode,
                        clap.clap_cla_placement_end_date,
                        clap.clap_cla_placement_change_reason,
                        LEFT(MIN(clae.clae_cla_episode_start_reason), 1) AS start_reason,
                        LEFT(MIN(clae.clae_cla_episode_ceased_reason), 3) AS end_reason
                      FROM ssd_cla_episodes clae
                      JOIN ssd_cla_placement clap
                        ON clap.clap_cla_id = clae.clae_cla_id
                      WHERE clae.clae_referral_id = cine.cine_referral_id
                        AND clap.clap_cla_placement_start_date <= @ea_cohort_window_end
                        AND (clap.clap_cla_placement_end_date IS NULL OR clap.clap_cla_placement_end_date >= @ea_cohort_window_start)
                      GROUP BY
                        clap.clap_cla_placement_id,
                        clap.clap_cla_placement_start_date,
                        clap.clap_cla_placement_type,
                        clap.clap_cla_placement_postcode,
                        clap.clap_cla_placement_end_date,
                        clap.clap_cla_placement_change_reason
                    ) g
                    ORDER BY g.clap_cla_placement_start_date DESC
                    FOR XML PATH(''), TYPE
                  ).value('.', 'nvarchar(max)'), 1, 1, ''), '')
              + '],' +


            -- Adoption (47..49)
            -- Returns: single object or null
            '"adoption":'
            + ISNULL((
                SELECT TOP 1
                  '{'
                    + '"initial_decision_date":' + CASE
                        WHEN perm.perm_adm_decision_date IS NULL
                          THEN 'null'
                        ELSE '"' + CONVERT(varchar(10), perm.perm_adm_decision_date, 23) + '"'
                      END + ','                                                                                               -- 47
                    + '"matched_date":' + CASE
                        WHEN perm.perm_matched_date IS NULL
                          THEN 'null'
                        ELSE '"' + CONVERT(varchar(10), perm.perm_matched_date, 23) + '"'
                      END + ','                                                                                               -- 48
                    + '"placed_date":' + CASE
                        WHEN perm.perm_placed_for_adoption_date IS NULL
                          THEN 'null'
                        ELSE '"' + CONVERT(varchar(10), perm.perm_placed_for_adoption_date, 23) + '"'
                      END + ','                                                                                               -- 49
                    + '"purge":false'
                  + '}'
                FROM ssd_permanence perm
                WHERE
                  (perm.perm_person_id = p.pers_person_id
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
              ), 'null')
            + ','
            

              -- Care leavers (50..52)
              -- Returns: single object (or null)
              '"care_leavers":'
              + ISNULL((
                  SELECT TOP 1
                    '{'
                      + '"contact_date":"' + CONVERT(varchar(10), clea.clea_care_leaver_latest_contact, 23) + '",'          -- 50
                      + '"activity":"' + LEFT(clea.clea_care_leaver_activity, 2) + '",'                                     -- 51
                      + '"accommodation":"' + LEFT(clea.clea_care_leaver_accommodation, 1) + '",'                           -- 52
                      + '"purge":false'
                    + '}'
                  FROM ssd_care_leavers clea
                  WHERE clea.clea_person_id = p.pers_person_id
                    AND clea.clea_care_leaver_latest_contact BETWEEN @ea_cohort_window_start AND @ea_cohort_window_end
                  ORDER BY clea.clea_care_leaver_latest_contact DESC
                ), '{}') + ',' +

              -- Care worker details (53..55)
              -- Returns: array (or [])
              N',"care_worker_details":' +
                N'[' +
                ISNULL(
                  STUFF((
                    SELECT
                      N',{' +
                      N'"worker_id":'    + QUOTENAME(LEFT(CAST(pr.prof_staff_id AS varchar(12)), 12), '"') +
                      N',"start_date":'  + QUOTENAME(CONVERT(varchar(10), i.invo_involvement_start_date, 23), '"') +
                      N',"end_date":'    + CASE
                                            WHEN i.invo_involvement_end_date IS NULL
                                              THEN N'null'
                                            ELSE QUOTENAME(CONVERT(varchar(10), i.invo_involvement_end_date, 23), '"')
                                          END +
                      N'}'
                    FROM ssd_involvements i
                    JOIN ssd_professionals pr
                      ON i.invo_professional_id = pr.prof_professional_id
                    WHERE i.invo_referral_id = cine.cine_referral_id
                      AND i.invo_involvement_start_date <= @ea_cohort_window_end
                      AND (
                            i.invo_involvement_end_date IS NULL
                        OR i.invo_involvement_end_date >= @ea_cohort_window_start
                          )
                    ORDER BY i.invo_involvement_start_date DESC
                    FOR XML PATH(''), TYPE
                  ).value('.', 'nvarchar(max)'), 1, 1, N''), N'') +
                N']' +

              '"purge":false'
            + '}'
          FROM ssd_cin_episodes cine
          WHERE cine.cine_person_id = p.pers_person_id
            AND cine.cine_referral_date <= @ea_cohort_window_end
            AND (cine.cine_close_date IS NULL OR cine.cine_close_date >= @ea_cohort_window_start)
          FOR XML PATH(''), TYPE
        ).value('.', 'nvarchar(max)'), 1, 1, ''), '')
      + ']' AS episodes_json
  ) AS ep
)
,

Hashed AS (
  SELECT
    person_id,
    json_payload,
    HASHBYTES('SHA2_256', CAST(json_payload AS NVARCHAR(MAX))) AS current_hash
  FROM RawPayloads
)

/* Upsert new or changed payloads */
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
WHERE prev.current_hash IS NULL
   OR prev.current_hash <> h.current_hash;



-- -- Optional
-- CREATE INDEX IX_ssd_cin_episodes_dates      ON ssd_cin_episodes(cine_person_id, cine_referral_date, cine_close_date);
-- CREATE INDEX IX_ssd_cin_plans_dates         ON ssd_cin_plans(cinp_person_id, cinp_cin_plan_start_date, cinp_cin_plan_end_date);
-- CREATE INDEX IX_ssd_cp_plans_dates          ON ssd_cp_plans(cppl_person_id, cppl_cp_plan_start_date, cppl_cp_plan_end_date);
-- CREATE INDEX IX_ssd_cla_placements_dates    ON ssd_cla_placement(clap_cla_id, clap_cla_placement_start_date, clap_cla_placement_end_date);
-- CREATE INDEX IX_ssd_care_leavers_date       ON ssd_care_leavers(clea_person_id, clea_care_leaver_latest_contact);
-- CREATE INDEX IX_ssd_sdq_date                ON ssd_sdq_scores(csdq_person_id, csdq_sdq_completed_date);

-- CREATE UNIQUE INDEX UX_ssd_api_person_hash ON ssd_api_data_staging(person_id, current_hash);





-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"}
-- =============================================================================
-- Description: Table for TEST|ANON API payload and logging 
-- This table is non-live and solely for the pre-live data/api testing. It can be 
-- depreciated/removed at any point by the LA; we'd expect this to be after 
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


-- Verification|sanity checks
-- Check table(s) populated
select TOP (5) * from ssd_api_data_staging;
select TOP (5) * from ssd_api_data_staging_anon; -- should be blank at this point



-- /* 
-- SAMPLE LIVE PAYLOAD VERIFICATION OUTPUTS
-- */


-- -- PAYLOAD VERIFICATION : Show records with with extended/nested payload (if available)
-- SELECT TOP (3)
--     person_id,
--     LEN(json_payload)        AS payload_chars,
--     json_payload  AS preview
-- FROM ssd_api_data_staging
-- ORDER BY DATALENGTH(json_payload) DESC, id DESC;



-- -- PAYLOAD VERIFICATION : Show records with health&wellbeing data available
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

-- -- -- LEGACY-PRE2016 (pattern search fallback, no JSON functions)
-- -- SELECT TOP (5) ...
-- -- FROM ssd_api_data_staging
-- -- WHERE json_payload LIKE '%"health_and_wellbeing"%sdq_assessments%"date"%'
-- -- ORDER BY DATALENGTH(json_payload) DESC, id DESC;




-- -- PAYLOAD VERIFICATION : Show records with adoption data available
-- SELECT TOP (3)
--     person_id,
--     LEN(json_payload) AS payload_chars,
--     json_payload AS preview
-- FROM ssd_api_data_staging
-- WHERE JSON_QUERY(json_payload, '$.social_care_episodes[0].adoption') IS NOT NULL

-- -- -- LEGACY-PRE2016
-- -- WHERE json_payload LIKE '%"adoption"%date_match"%'
-- ORDER BY DATALENGTH(json_payload) DESC, id DESC;


