
-- define if required 
use HDM_Local; -- Note: this the SystemC/LLogic default


/* Note for: Daily Data Flows Early Adopters
The following table definitions (and populating) can be run after the main SSD script, OR the following definitions
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
-- Description: Table for API payload and logging. For most LA's this is a placeholder structure as source data not common|confirmed
-- Author: D2I
-- =============================================================================


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
    SELECT --TOP (100) -- REMOVE TEST LIMITER BEFORE DEPLOYING
           p.pers_person_id AS person_id,
           (
               SELECT
                   p.pers_person_id AS [la_child_id],
                   ISNULL(p.pers_common_child_id, 'SSD_PH_CCI') AS [mis_child_id],
                   CAST(0 AS bit) AS [purge],
                   
                   -- Child details
                   JSON_QUERY((
                       SELECT
                           p.pers_forename AS [first_name],
                           p.pers_surname  AS [surname],
                           (SELECT TOP 1 link_identifier_value
                              FROM ssd_linked_identifiers
                              WHERE link_person_id = p.pers_person_id
                                AND link_identifier_type = 'Unique Pupil Number'
                              ORDER BY link_valid_from_date DESC) AS [unique_pupil_number],
                           (SELECT TOP 1 link_identifier_value
                              FROM ssd_linked_identifiers
                              WHERE link_person_id = p.pers_person_id
                                AND link_identifier_type = 'Former Unique Pupil Number'
                              ORDER BY link_valid_from_date DESC) AS [former_unique_pupil_number],
                           p.pers_upn_unknown AS [unique_pupil_number_unknown_reason],
                           CONVERT(VARCHAR(10), p.pers_dob, 23) AS [date_of_birth],
                           CONVERT(VARCHAR(10), p.pers_expected_dob, 23) AS [expected_date_of_birth],
                           CASE WHEN p.pers_sex IN ('M','F') THEN p.pers_sex ELSE 'U' END AS [sex],
                           p.pers_ethnicity AS [ethnicity],

                           -- uses XML PATH OUTER APPLY below
                           COALESCE(JSON_QUERY(disab.disabilities), JSON_QUERY('[]')) AS [disabilities],

                           (SELECT TOP 1 a.addr_address_postcode
                              FROM ssd_address a
                              WHERE a.addr_person_id = p.pers_person_id
                              ORDER BY a.addr_address_start_date DESC) AS [postcode],
                           (SELECT TOP 1 immi.immi_immigration_status
                              FROM ssd_immigration_status immi
                              WHERE immi.immi_person_id = p.pers_person_id
                              ORDER BY CASE WHEN immi.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                                       immi.immi_immigration_status_start_date DESC) AS [uasc_flag],
                           (SELECT TOP 1 CONVERT(VARCHAR(10), immi2.immi_immigration_status_end_date, 23)
                              FROM ssd_immigration_status immi2
                              WHERE immi2.immi_person_id = p.pers_person_id
                              ORDER BY CASE WHEN immi2.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                                       immi2.immi_immigration_status_start_date DESC) AS [uasc_end_date],
                           CAST(0 AS bit) AS [purge]
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                   )) AS [child_details],

                   -- Health and wellbeing
                   JSON_QUERY((
                       SELECT
                           (SELECT CONVERT(VARCHAR(10), csdq.csdq_sdq_completed_date, 23) AS [date],
                                   csdq.csdq_sdq_score AS [score]
                              FROM ssd_sdq_scores csdq
                              WHERE csdq.csdq_person_id = p.pers_person_id
                                AND csdq.csdq_sdq_score IS NOT NULL
                                AND csdq.csdq_sdq_completed_date IS NOT NULL
                                AND csdq.csdq_sdq_completed_date > '1900-01-01'
                              ORDER BY csdq.csdq_sdq_completed_date DESC
                              FOR JSON PATH) AS [sdq_assessments],
                           CAST(0 AS bit) AS [purge]
                       FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                   )) AS [health_and_wellbeing],

                   -- Social care episodes
                   JSON_QUERY((
                       SELECT
                           cine.cine_referral_id AS [social_care_episode_id],
                           CONVERT(VARCHAR(10), cine.cine_referral_date, 23) AS [referral_date],
                           cine.cine_referral_source_code AS [referral_source],
                           cine.cine_referral_nfa AS [referral_no_further_action_flag],
                           (SELECT *
                              FROM (SELECT pr.prof_staff_id AS [worker_id],
                                           CONVERT(VARCHAR(10), i.invo_involvement_start_date, 23) AS [start_date],
                                           CONVERT(VARCHAR(10), i.invo_involvement_end_date, 23)   AS [end_date]
                                      FROM ssd_involvements i
                                      JOIN ssd_professionals pr
                                        ON i.invo_professional_id = pr.prof_professional_id
                                     WHERE i.invo_referral_id = cine.cine_referral_id) AS sorted_sw
                              ORDER BY sorted_sw.start_date DESC
                              FOR JSON PATH) AS [care_worker_details],

                            -- Nested child and family assessments
                           (SELECT ca.cina_assessment_id AS [child_and_family_assessment_id],
                                   CONVERT(VARCHAR(10), ca.cina_assessment_start_date, 23) AS [start_date],
                                   CONVERT(VARCHAR(10), ca.cina_assessment_auth_date, 23)  AS [authorisation_date],
                                   JSON_QUERY(CASE WHEN af.cinf_assessment_factors_json IS NULL
                                                    OR af.cinf_assessment_factors_json = ''
                                                   THEN '[]' ELSE af.cinf_assessment_factors_json END) AS [factors],
                                   CAST(0 AS bit) AS [purge]
                              FROM ssd_cin_assessments ca
                              LEFT JOIN ssd_assessment_factors af
                                ON af.cinf_assessment_id = ca.cina_assessment_id
                             WHERE ca.cina_referral_id = cine.cine_referral_id
                             FOR JSON PATH) AS [child_and_family_assessments],

                            -- Nested child in need plans
                           (SELECT cinp.cinp_cin_plan_id AS [child_in_need_plan_id],
                                   CONVERT(VARCHAR(10), cinp.cinp_cin_plan_start_date, 23) AS [start_date],
                                   CONVERT(VARCHAR(10), cinp.cinp_cin_plan_end_date, 23)   AS [end_date],
                                   CAST(0 AS bit) AS [purge]
                              FROM ssd_cin_plans cinp
                             WHERE cinp.cinp_referral_id = cine.cine_referral_id
                             FOR JSON PATH) AS [child_in_need_plans],

                            -- Nested s47 assessments
                           (SELECT s47e.s47e_s47_enquiry_id AS [section_47_assessment_id],
                                   CONVERT(VARCHAR(10), s47e.s47e_s47_start_date, 23) AS [start_date],
                                   JSON_VALUE(s47e.s47e_s47_outcome_json, '$.CP_CONFERENCE_FLAG') AS [icpc_required_flag],
                                   CONVERT(VARCHAR(10), icpc.icpc_icpc_date, 23) AS [icpc_date],
                                   CONVERT(VARCHAR(10), s47e.s47e_s47_end_date, 23) AS [end_date],
                                   CAST(0 AS bit) AS [purge]
                              FROM ssd_s47_enquiry s47e
                              LEFT JOIN ssd_initial_cp_conference icpc
                                ON icpc.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                             WHERE s47e.s47e_referral_id = cine.cine_referral_id
                             FOR JSON PATH) AS [section_47_assessments],

                            -- Nested child protection pplans
                           (SELECT cppl.cppl_cp_plan_id AS [child_protection_plan_id],
                                   CONVERT(VARCHAR(10), cppl.cppl_cp_plan_start_date, 23) AS [start_date],
                                   CONVERT(VARCHAR(10), cppl.cppl_cp_plan_end_date, 23)   AS [end_date],
                                   CAST(0 AS bit) AS [purge]
                              FROM ssd_cp_plans cppl
                             WHERE cppl.cppl_referral_id = cine.cine_referral_id
                             FOR JSON PATH) AS [child_protection_plans],

                            -- Nested child looked after placements
                           (SELECT clae.clae_cla_placement_id AS [child_looked_after_placement_id],
                                   CONVERT(VARCHAR(10), clae.clae_cla_episode_start_date, 23) AS [start_date],
                                   LEFT(clae.clae_cla_episode_start_reason, 3) AS [start_reason],
                                   CONVERT(VARCHAR(10), clae.clae_cla_episode_ceased_date, 23) AS [end_date],
                                   LEFT(clae.clae_cla_episode_ceased_reason, 3) AS [end_reason],
                                   clap.clap_cla_placement_id AS [placement_id],
                                   CONVERT(VARCHAR(10), clap.clap_cla_placement_start_date, 23) AS [placement_start_date],
                                   clap.clap_cla_placement_type AS [placement_type],
                                   clap.clap_cla_placement_postcode AS [postcode],
                                   CONVERT(VARCHAR(10), clap.clap_cla_placement_end_date, 23) AS [placement_end_date],
                                   clap.clap_cla_placement_change_reason AS [change_reason],
                                   CAST(0 AS bit) AS [purge]
                              FROM ssd_cla_episodes clae
                              JOIN ssd_cla_placement clap
                                ON clap.clap_cla_id = clae.clae_cla_id
                             WHERE clae.clae_referral_id = cine.cine_referral_id
                             ORDER BY clap.clap_cla_placement_start_date DESC
                             FOR JSON PATH) AS [child_looked_after_placements],

                            -- Nested adoption (single JSON object, not an array, or null)
                            JSON_QUERY((
                                SELECT TOP 1
                                    CONVERT(VARCHAR(10), perm.perm_adm_decision_date, 23)       AS [initial_decision_date],
                                    CONVERT(VARCHAR(10), perm.perm_matched_date, 23)            AS [matched_date],
                                    CONVERT(VARCHAR(10), perm.perm_placed_for_adoption_date, 23) AS [placed_date],
                                    CAST(0 AS bit) AS [purge]
                                FROM ssd_permanence perm
                                WHERE perm.perm_person_id = p.pers_person_id
                                OR perm.perm_cla_id IN (
                                        SELECT clae2.clae_cla_id
                                        FROM ssd_cla_episodes clae2
                                        WHERE clae2.clae_person_id = p.pers_person_id
                                    )
                                ORDER BY COALESCE(
                                            perm.perm_placed_for_adoption_date,
                                            perm.perm_matched_date,
                                            perm.perm_adm_decision_date
                                        ) DESC
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                            )) AS [adoption],

                            -- Nested care leaver (single JSON object, not an array, or null)
                            JSON_QUERY((
                                SELECT TOP 1
                                    CONVERT(VARCHAR(10), clea.clea_care_leaver_latest_contact, 23) AS [contact_date],
                                    LEFT(clea.clea_care_leaver_activity, 2) AS [activity],
                                    LEFT(clea.clea_care_leaver_accommodation, 1) AS [accommodation],
                                    CAST(0 AS bit) AS [purge]
                                FROM ssd_care_leavers clea
                                WHERE clea.clea_person_id = p.pers_person_id
                                ORDER BY clea.clea_care_leaver_latest_contact DESC
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                            )) AS [care_leavers],


                           CONVERT(VARCHAR(10), cine.cine_close_date, 23) AS [closure_date],
                           cine.cine_close_reason AS [closure_reason],
                           CAST(0 AS bit) AS [purge]
                       FROM ssd_cin_episodes cine
                       WHERE cine.cine_person_id = p.pers_person_id
                       FOR JSON PATH
                   )) AS [social_care_episodes]

               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
           ) AS json_payload
    FROM ssd_person p

    OUTER APPLY (
        /* Option A, XML PATH, SQL Server 2012+ (default for 2016 script) */
        SELECT
          JSON_QUERY(
            N'[' +
            STUFF((
                SELECT N',' + QUOTENAME(d2.disa_disability_code, '"')
                FROM ssd_disability AS d2
                WHERE d2.disa_person_id = p.pers_person_id
                ORDER BY d2.disa_disability_code
                FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(max)'), 1, 1, N'') +
            N']'
          ) AS disabilities

        /* Option B, STRING_AGG, SQL Server 2022+
           Leave commented, uncomment to use, performance adv if running latest versions
           Notes:
           - WITHIN GROUP (ORDER BY ...) requ SQL Server 2022|Azure SQL
           - Keep QUOTENAME and ORDER BY for deterministic, safe quoted output
        */
        -- SELECT
        --   JSON_QUERY(
        --     N'[' +
        --     ISNULL(
        --       STRING_AGG('"' + d.disa_disability_code + '"', N',')
        --         WITHIN GROUP (ORDER BY d.disa_disability_code),
        --       N''
        --     ) +
        --     N']'
        --   ) AS disabilities
    ) AS disab

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
WHERE prev.current_hash IS NULL         -- first time we’ve ever seen this person
   OR prev.current_hash <> h.current_hash;  -- payload has changed



-- -- Optional guard-rail to prevent exact duplicates
-- IF NOT EXISTS (
--     SELECT 1 FROM sys.indexes
--     WHERE name = 'UX_ssd_api_person_hash'
--       AND object_id = OBJECT_ID('ssd_api_data_staging')
-- )
-- CREATE UNIQUE INDEX UX_ssd_api_person_hash
-- ON ssd_api_data_staging(person_id, current_hash);



-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"}
-- =============================================================================
-- Description: Table for TEST|ANON API payload and logging. 
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


-- 
select * from ssd_api_data_staging;
select * from ssd_api_data_staging_anon;


