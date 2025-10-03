

-- define if required 
use HDM_Local; -- Note: this the SystemC/LLogic default

/* Note for: Daily Data Flows Early Adopters
The following table definitions (and populating) can be run after the main SSD script, OR the following definitions
can be added into the main SSD - insert locations are marked via the meta tags of:

-- Script compatibility and defaults
-- SQL Server 2012 and later (compat 110 plus). 
-- If you are on SQL Server 2016 SP1 or later, use the separate 2016 plus script which employs native JSON features for simpler payload assembly.
-- It assembles JSON by string concatenation, with ordered arrays built via FOR XML PATH and STUFF, and all text escaped with nested REPLACE calls.
-- There is no FOR JSON, no JSON_QUERY, no JSON_VALUE in this file, which keeps it 2012 compatible.
-- 
-- Booleans stored as Y or N or 1 or 0 are normalised to true or false (TRY_CONVERT plus a small mapping). Adjust mapping if you use different codes.
-- Adoption and care_leavers are single objects inside each episode, not arrays. Per dfe 0.8 API shape.
-- The insert runs as single multi CTE statement inside one transaction.
-- Idempotency, payloads are hashed with SHA2 256 and compared to last row for each person, only new or changed payloads inserted
-- XACT_ABORT is ON, auto rolls back on most runtime errors, and TRY CATCH block wraps transaction for clarity.
-- Optional unique index on (person_id, current_hash) included below as guard rail. Commented by default.



META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging"}
META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"} - temp table for API testing, can be removed post testing
*/

DECLARE @VERSION nvarchar(32) = N'0.1.3';
RAISERROR(N'== CSC API staging build: v%s ==', 10, 1, @VERSION) WITH NOWAIT;



SET NOCOUNT ON;
SET XACT_ABORT ON;

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

-- single error scope
BEGIN TRY                               -- catch any runtime error, keep control flow clean on 2012
  BEGIN TRANSACTION;                    -- whole payload build and insert atomic, no partial row(s) on fail
                                        -- everything lands, or nothing does
  ;WITH RawPayloads AS
  (
      SELECT
          p.pers_person_id AS person_id,
          disab.disabilities_json,
          cd.child_details_json,
          sdq.sdq_array_json,
          sce.episodes_array_json,
          '{'
          + '"la_child_id":' + CASE WHEN CONVERT(nvarchar(48), p.pers_person_id) IS NULL THEN 'null' ELSE '"' + CONVERT(nvarchar(48), p.pers_person_id) + '"' END + ','
          + '"mis_child_id":' + CASE WHEN ISNULL(p.pers_common_child_id, 'SSD_PH_CCI') IS NULL THEN 'null' ELSE '"' + ISNULL(p.pers_common_child_id, 'SSD_PH_CCI') + '"' END + ','
          + '"purge":false,'
          + '"child_details":' + cd.child_details_json + ','
          + '"health_and_wellbeing":{'
              + '"sdq_assessments":' + ISNULL(sdq.sdq_array_json, '[]') + ','
              + '"purge":false'
            + '},'
          + '"social_care_episodes":' + ISNULL(sce.episodes_array_json, '[]')
          + '}' AS json_payload
        FROM ssd_person p

        /* disabilities -> JSON array */
        OUTER APPLY (
            SELECT
                '[' + STUFF((
                    SELECT ',' + '"' +
                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), d2.disa_disability_code),
                                N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r')
                        + '"'
                    FROM ssd_disability AS d2
                    WHERE d2.disa_person_id = p.pers_person_id
                    ORDER BY d2.disa_disability_code
                    FOR XML PATH(''), TYPE
                ).value('.', 'nvarchar(max)'), 1, 1, '') + ']'
        ) AS disab(disabilities_json)

        /* sdq -> JSON array */
        OUTER APPLY (
            SELECT
                '[' + STUFF((
                    SELECT ',' + '{'
                        + '"date":'  + CASE WHEN csdq.csdq_sdq_completed_date IS NULL
                                                THEN 'null' ELSE '"' + CONVERT(varchar(10), csdq.csdq_sdq_completed_date, 23) + '"' END + ','
                        + '"score":' + CASE WHEN csdq.csdq_sdq_score IS NULL
                                                THEN 'null' ELSE CONVERT(varchar(20), csdq.csdq_sdq_score) END
                        + '}'
                    FROM ssd_sdq_scores csdq
                    WHERE csdq.csdq_person_id = p.pers_person_id
                    AND csdq.csdq_sdq_score IS NOT NULL
                    AND csdq.csdq_sdq_completed_date IS NOT NULL
                    AND csdq.csdq_sdq_completed_date > '19000101'
                    ORDER BY csdq.csdq_sdq_completed_date DESC
                    FOR XML PATH(''), TYPE
                ).value('.', 'nvarchar(max)'), 1, 1, '') + ']'
        ) AS sdq(sdq_array_json)

        /* child_details -> single JSON object */
        CROSS APPLY (
            SELECT
            '{'
            + '"first_name":' +
                CASE WHEN p.pers_forename IS NULL THEN 'null' ELSE '"' +
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), p.pers_forename), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r') + '"' END + ','
            + '"surname":' +
                CASE WHEN p.pers_surname IS NULL THEN 'null' ELSE '"' +
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), p.pers_surname), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r') + '"' END + ','
            + '"unique_pupil_number":' +
                CASE WHEN (SELECT TOP 1 link_identifier_value
                        FROM ssd_linked_identifiers
                        WHERE link_person_id = p.pers_person_id
                            AND link_identifier_type = 'Unique Pupil Number'
                        ORDER BY link_valid_from_date DESC) IS NULL
                    THEN 'null'
                    ELSE '"' + REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max),
                            (SELECT TOP 1 link_identifier_value
                            FROM ssd_linked_identifiers
                            WHERE link_person_id = p.pers_person_id
                            AND link_identifier_type = 'Unique Pupil Number'
                            ORDER BY link_valid_from_date DESC)
                    ), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r') + '"' END + ','
            + '"former_unique_pupil_number":' +
                CASE WHEN (SELECT TOP 1 link_identifier_value
                        FROM ssd_linked_identifiers
                        WHERE link_person_id = p.pers_person_id
                            AND link_identifier_type = 'Former Unique Pupil Number'
                        ORDER BY link_valid_from_date DESC) IS NULL
                    THEN 'null'
                    ELSE '"' + REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max),
                            (SELECT TOP 1 link_identifier_value
                            FROM ssd_linked_identifiers
                            WHERE link_person_id = p.pers_person_id
                            AND link_identifier_type = 'Former Unique Pupil Number'
                            ORDER BY link_valid_from_date DESC)
                    ), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r') + '"' END + ','
            + '"unique_pupil_number_unknown_reason":' +
                CASE WHEN p.pers_upn_unknown IS NULL THEN 'null' ELSE '"' +
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), p.pers_upn_unknown), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r') + '"' END + ','
            + '"date_of_birth":' +
                CASE WHEN p.pers_dob IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), p.pers_dob, 23) + '"' END + ','
            + '"expected_date_of_birth":' +
                CASE WHEN p.pers_expected_dob IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), p.pers_expected_dob, 23) + '"' END + ','
            + '"sex":' +
                CASE WHEN p.pers_sex IN ('M','F') THEN '"' + p.pers_sex + '"' ELSE '"U"' END + ','
            + '"ethnicity":' +
                CASE WHEN p.pers_ethnicity IS NULL THEN 'null' ELSE '"' +
                    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), p.pers_ethnicity), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r') + '"' END + ','
            + '"disabilities":' + ISNULL(disab.disabilities_json, '[]') + ','
            + '"postcode":' +
                CASE WHEN (SELECT TOP 1 a.addr_address_postcode
                        FROM ssd_address a
                        WHERE a.addr_person_id = p.pers_person_id
                        ORDER BY a.addr_address_start_date DESC) IS NULL
                    THEN 'null'
                    ELSE '"' + REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max),
                        (SELECT TOP 1 a.addr_address_postcode
                        FROM ssd_address a
                        WHERE a.addr_person_id = p.pers_person_id
                        ORDER BY a.addr_address_start_date DESC)
                    ), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r') + '"' END + ','

                    
            + '"uasc_flag":' +
                CASE WHEN (SELECT TOP 1 immi.immi_immigration_status
                        FROM ssd_immigration_status immi
                        WHERE immi.immi_person_id = p.pers_person_id
                        ORDER BY CASE WHEN immi.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                                    immi.immi_immigration_status_start_date DESC) IS NULL
                    THEN 'null'
                    ELSE '"' + REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max),
                        (SELECT TOP 1 immi.immi_immigration_status
                        FROM ssd_immigration_status immi
                        WHERE immi.immi_person_id = p.pers_person_id
                        ORDER BY CASE WHEN immi.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                                    immi.immi_immigration_status_start_date DESC)
                    ), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r') + '"' END + ','
            + '"uasc_end_date":' +
                CASE WHEN (SELECT TOP 1 immi2.immi_immigration_status_end_date
                        FROM ssd_immigration_status immi2
                        WHERE immi2.immi_person_id = p.pers_person_id
                        ORDER BY CASE WHEN immi2.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                                    immi2.immi_immigration_status_start_date DESC) IS NULL
                    THEN 'null'
                    ELSE '"' + CONVERT(varchar(10),
                            (SELECT TOP 1 immi2.immi_immigration_status_end_date
                            FROM ssd_immigration_status immi2
                            WHERE immi2.immi_person_id = p.pers_person_id
                            ORDER BY CASE WHEN immi2.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                                    immi2.immi_immigration_status_start_date DESC), 23) + '"' END + ','
            + '"purge":false'
            + '}' AS child_details_json
        ) AS cd

        /* social_care_episodes -> JSON array + nested */
        OUTER APPLY (
            SELECT
                '[' + STUFF((
                    SELECT ',' + '{'
                        + '"social_care_episode_id":' + ISNULL(CONVERT(varchar(20), cine.cine_referral_id), 'null') + ','
                        + '"referral_date":' + CASE WHEN cine.cine_referral_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), cine.cine_referral_date, 23) + '"' END + ','
                        + '"referral_source":' + CASE WHEN cine.cine_referral_source_code IS NULL THEN 'null' ELSE '"' +
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), cine.cine_referral_source_code),
                                N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r')
                            + '"' END + ','
                        + '"referral_no_further_action_flag":'
                        + CASE
                            -- SSD source enforces NCHAR(1) however..., some robustness here to wrap potential LA source strings
                            -- SSD source field cine_referral_nfa in review as bool
                            -- numeric/bit inputs (1/0, actual bit)
                            WHEN TRY_CONVERT(bit, NULLIF(LTRIM(RTRIM(CONVERT(varchar(5), cine.cine_referral_nfa))), '')) IS NOT NULL
                                THEN CASE TRY_CONVERT(bit, NULLIF(LTRIM(RTRIM(CONVERT(varchar(5), cine.cine_referral_nfa))), ''))
                                        WHEN 1 THEN 'true' ELSE 'false' END
                                -- SSD source enforces NCHAR(1) however..., some robustness here to wrap potential LA source strings
                            WHEN UPPER(LTRIM(RTRIM(CONVERT(varchar(5), cine.cine_referral_nfa)))) IN ('Y','T','1')
                                THEN 'true'
                            WHEN UPPER(LTRIM(RTRIM(CONVERT(varchar(5), cine.cine_referral_nfa)))) IN ('N','F','0')
                                THEN 'false'
                            ELSE 'null'  -- unknown/blank
                        END + ','

                        + '"care_worker_details":' +
                            '[' + STUFF((
                                SELECT ',' + '{'
                                    + '"worker_id":' + CASE WHEN sw.prof_staff_id IS NULL THEN 'null' ELSE '"' + CONVERT(nvarchar(50), sw.prof_staff_id) + '"' END + ','
                                    + '"start_date":' + CASE WHEN sw.start_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), sw.start_date, 23) + '"' END + ','
                                    + '"end_date":'   + CASE WHEN sw.end_date   IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), sw.end_date, 23)   + '"' END
                                    + '}'
                                FROM (
                                    SELECT pr.prof_staff_id,
                                        i.invo_involvement_start_date AS start_date,
                                        i.invo_involvement_end_date   AS end_date
                                    FROM ssd_involvements i
                                    JOIN ssd_professionals pr
                                    ON i.invo_professional_id = pr.prof_professional_id
                                    WHERE i.invo_referral_id = cine.cine_referral_id
                                ) AS sw
                                ORDER BY sw.start_date DESC
                                FOR XML PATH(''), TYPE
                            ).value('.', 'nvarchar(max)'), 1, 1, '') + ']' + ','

                        + '"child_and_family_assessments":' +
                            '[' + STUFF((
                                SELECT ',' + '{'
                                    + '"child_and_family_assessment_id":' + ISNULL(CONVERT(varchar(20), ca.cina_assessment_id), 'null') + ','
                                    + '"start_date":'        + CASE WHEN ca.cina_assessment_start_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), ca.cina_assessment_start_date, 23) + '"' END + ','
                                    + '"authorisation_date":' + CASE WHEN ca.cina_assessment_auth_date  IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), ca.cina_assessment_auth_date, 23)  + '"' END + ','
                                    + '"factors":' + ISNULL(NULLIF(af.cinf_assessment_factors_json, ''), '[]') + ','
                                    + '"purge":false'
                                    + '}'
                                FROM ssd_cin_assessments ca
                                LEFT JOIN ssd_assessment_factors af
                                ON af.cinf_assessment_id = ca.cina_assessment_id
                                WHERE ca.cina_referral_id = cine.cine_referral_id
                                FOR XML PATH(''), TYPE
                            ).value('.', 'nvarchar(max)'), 1, 1, '') + ']' + ','

                        + '"child_in_need_plans":' +
                            '[' + STUFF((
                                SELECT ',' + '{'
                                    + '"child_in_need_plan_id":' + ISNULL(CONVERT(varchar(20), cinp.cinp_cin_plan_id), 'null') + ','
                                    + '"start_date":' + CASE WHEN cinp.cinp_cin_plan_start_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), cinp.cinp_cin_plan_start_date, 23) + '"' END + ','
                                    + '"end_date":'   + CASE WHEN cinp.cinp_cin_plan_end_date   IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), cinp.cinp_cin_plan_end_date, 23)   + '"' END + ','
                                    + '"purge":false'
                                    + '}'
                                FROM ssd_cin_plans cinp
                                WHERE cinp.cinp_referral_id = cine.cine_referral_id
                                FOR XML PATH(''), TYPE
                            ).value('.', 'nvarchar(max)'), 1, 1, '') + ']' + ','

                        + '"section_47_assessments":' +
                            '[' + STUFF((
                                SELECT ',' + '{'
                                    + '"section_47_assessment_id":' + ISNULL(CONVERT(varchar(20), s47e.s47e_s47_enquiry_id), 'null') + ','
                                    + '"start_date":' + CASE WHEN s47e.s47e_s47_start_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), s47e.s47e_s47_start_date, 23) + '"' END + ','
                                    + '"icpc_required_flag":null,'
                                    + '"icpc_date":' + CASE WHEN icpc.icpc_icpc_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), icpc.icpc_icpc_date, 23) + '"' END + ','
                                    + '"end_date":' + CASE WHEN s47e.s47e_s47_end_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), s47e.s47e_s47_end_date, 23) + '"' END + ','
                                    + '"purge":false'
                                    + '}'
                                FROM ssd_s47_enquiry s47e
                                LEFT JOIN ssd_initial_cp_conference icpc
                                ON icpc.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                                WHERE s47e.s47e_referral_id = cine.cine_referral_id
                                FOR XML PATH(''), TYPE
                            ).value('.', 'nvarchar(max)'), 1, 1, '') + ']' + ','

                        + '"child_protection_plans":' +
                            '[' + STUFF((
                                SELECT ',' + '{'
                                    + '"child_protection_plan_id":' + ISNULL(CONVERT(varchar(20), cppl.cppl_cp_plan_id), 'null') + ','
                                    + '"start_date":' + CASE WHEN cppl.cppl_cp_plan_start_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), cppl.cppl_cp_plan_start_date, 23) + '"' END + ','
                                    + '"end_date":'   + CASE WHEN cppl.cppl_cp_plan_end_date   IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), cppl.cppl_cp_plan_end_date, 23)   + '"' END + ','
                                    + '"purge":false'
                                    + '}'
                                FROM ssd_cp_plans cppl
                                WHERE cppl.cppl_referral_id = cine.cine_referral_id
                                FOR XML PATH(''), TYPE
                            ).value('.', 'nvarchar(max)'), 1, 1, '') + ']' + ','

                        + '"child_looked_after_placements":' +
                            '[' + STUFF((
                                SELECT ',' + '{'
                                    + '"child_looked_after_placement_id":' + ISNULL(CONVERT(varchar(20), clap.clap_cla_placement_id), 'null') + ','
                                    + '"start_date":'   + CASE WHEN clae.clae_cla_episode_start_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), clae.clae_cla_episode_start_date, 23) + '"' END + ','
                                    + '"start_reason":' + CASE WHEN clae.clae_cla_episode_start_reason IS NULL THEN 'null' ELSE '"' +
                                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), LEFT(clae.clae_cla_episode_start_reason, 3)), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r')
                                            + '"' END + ','
                                    + '"end_date":'     + CASE WHEN clae.clae_cla_episode_ceased_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), clae.clae_cla_episode_ceased_date, 23) + '"' END + ','
                                    + '"end_reason":'   + CASE WHEN clae.clae_cla_episode_ceased_reason IS NULL THEN 'null' ELSE '"' +
                                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), LEFT(clae.clae_cla_episode_ceased_reason, 3)), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r')
                                            + '"' END + ','
                                    + '"placement_id":' + ISNULL(CONVERT(varchar(20), clap.clap_cla_placement_id), 'null') + ','
                                    + '"placement_start_date":' + CASE WHEN clap.clap_cla_placement_start_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), clap.clap_cla_placement_start_date, 23) + '"' END + ','
                                    + '"placement_type":' + CASE WHEN clap.clap_cla_placement_type IS NULL THEN 'null' ELSE '"' +
                                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), clap.clap_cla_placement_type), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r')
                                            + '"' END + ','
                                    + '"postcode":'       + CASE WHEN clap.clap_cla_placement_postcode IS NULL THEN 'null' ELSE '"' +
                                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), clap.clap_cla_placement_postcode), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r')
                                            + '"' END + ','
                                    + '"placement_end_date":' + CASE WHEN clap.clap_cla_placement_end_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), clap.clap_cla_placement_end_date, 23) + '"' END + ','
                                    + '"change_reason":' + CASE WHEN clap.clap_cla_placement_change_reason IS NULL THEN 'null' ELSE '"' +
                                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), clap.clap_cla_placement_change_reason), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r')
                                            + '"' END + ','
                                    + '"purge":false'
                                    + '}'
                                FROM ssd_cla_episodes clae
                                JOIN ssd_cla_placement clap
                                ON clap.clap_cla_id = clae.clae_cla_id
                                WHERE clae.clae_referral_id = cine.cine_referral_id
                                ORDER BY clap.clap_cla_placement_start_date DESC
                                FOR XML PATH(''), TYPE
                            ).value('.', 'nvarchar(max)'), 1, 1, '') + ']' + ','

                        + '"adoption":' +
                        ISNULL((
                            SELECT TOP 1
                                '{'
                                + '"initial_decision_date":' + CASE WHEN perm.perm_adm_decision_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), perm.perm_adm_decision_date, 23) + '"' END + ','
                                + '"matched_date":'          + CASE WHEN perm.perm_matched_date        IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), perm.perm_matched_date, 23)        + '"' END + ','
                                + '"placed_date":'           + CASE WHEN perm.perm_placed_for_adoption_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), perm.perm_placed_for_adoption_date, 23) + '"' END + ','
                                + '"purge":false'
                                + '}'
                            FROM ssd_permanence perm
                            WHERE perm.perm_person_id = p.pers_person_id
                            OR perm.perm_cla_id IN (
                                    SELECT clae2.clae_cla_id
                                    FROM ssd_cla_episodes clae2
                                    WHERE clae2.clae_person_id = p.pers_person_id
                            )
                            ORDER BY COALESCE(perm.perm_placed_for_adoption_date, perm.perm_matched_date, perm.perm_adm_decision_date) DESC
                        ), 'null') + ','

                        + '"care_leavers":' +
                        ISNULL((
                            SELECT TOP 1
                                '{'
                                + '"contact_date":' + CASE WHEN clea.clea_care_leaver_latest_contact IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), clea.clea_care_leaver_latest_contact, 23) + '"' END + ','
                                + '"activity":'     + CASE WHEN clea.clea_care_leaver_activity      IS NULL THEN 'null' ELSE '"' +
                                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), LEFT(clea.clea_care_leaver_activity, 2)), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r')
                                        + '"' END + ','
                                + '"accommodation":'+ CASE WHEN clea.clea_care_leaver_accommodation  IS NULL THEN 'null' ELSE '"' +
                                        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), LEFT(clea.clea_care_leaver_accommodation, 1)), N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r')
                                        + '"' END + ','
                                + '"purge":false'
                                + '}'
                            FROM ssd_care_leavers clea
                            WHERE clea.clea_person_id = p.pers_person_id
                            ORDER BY clea.clea_care_leaver_latest_contact DESC
                        ), 'null') + ','

                        + '"closure_date":'  + CASE WHEN cine.cine_close_date IS NULL THEN 'null' ELSE '"' + CONVERT(varchar(10), cine.cine_close_date, 23) + '"' END + ','
                        + '"closure_reason":' + CASE WHEN cine.cine_close_reason IS NULL THEN 'null' ELSE '"' +
                            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), cine.cine_close_reason),
                                N'\', N'\\'), N'"', N'\"'), CHAR(8), N'\b'), CHAR(9), N'\t'), CHAR(10), N'\n'), CHAR(13), N'\r')
                            + '"' END + ','
                        + '"purge":false'
                    + '}'
                    FROM ssd_cin_episodes cine
                    WHERE cine.cine_person_id = p.pers_person_id
                    FOR XML PATH(''), TYPE
                ).value('.', 'nvarchar(max)'), 1, 1, '') + ']'
        ) AS sce(episodes_array_json)

  ),
  Hashed AS (
      SELECT
          person_id,
          json_payload,
          HASHBYTES('SHA2_256', CAST(json_payload AS nvarchar(max))) AS current_hash
      FROM RawPayloads
  )
  INSERT INTO ssd_api_data_staging
      (person_id, previous_json_payload, json_payload, current_hash, previous_hash,
       submission_status, row_state, last_updated)
  SELECT
      h.person_id,
      prev.json_payload,
      h.json_payload,
      h.current_hash,
      prev.current_hash,
      'Pending',
      CASE WHEN prev.current_hash IS NULL THEN 'New' ELSE 'Updated' END,
      GETDATE()
  FROM Hashed AS h
  OUTER APPLY (
      SELECT TOP (1) s.json_payload, s.current_hash
      FROM ssd_api_data_staging AS s
      WHERE s.person_id = h.person_id
      ORDER BY s.id DESC
  ) AS prev
  WHERE prev.current_hash IS NULL
     OR prev.current_hash <> h.current_hash;

  COMMIT TRANSACTION;                   -- commit only after all steps succeed
END TRY
BEGIN CATCH
  -- XACT_ABORT ON set above, most runtime errors mark the transaction, check state before rollback
  IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;  -- safe for both committable state 1 and uncommittable state minus 1
  THROW;                                 -- rethrow original error (preserve number, severity, state, and stack)
END CATCH



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

-- Verification|sanity checks
-- Check table populated
select TOP (5) * from ssd_api_data_staging;
select TOP (5) * from ssd_api_data_staging_anon; -- should be blank at this point

-- -- Get some rows that def have have the extended/full payload (if available)
-- SELECT TOP (5)
--     person_id,
--     LEN(json_payload)        AS payload_chars,
--     json_payload  AS preview
-- FROM ssd_api_data_staging
-- ORDER BY DATALENGTH(json_payload) DESC, id DESC;