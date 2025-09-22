

-- define if required 
use HDM_Local; -- Note: this the SystemC/LLogic default


/* Note for: Daily Data Flows Early Adopters
The following table definitions (and populating) can be run after the main SSD script, OR the following definitions
can be added into the main SSD - insert locations are marked via the meta tags of:


-- Script compatibility and defaults
-- Default uses XML PATH for aggregations, SQL Server 2012+
-- Payload assembly uses FOR JSON, JSON_QUERY, JSON_VALUE, SQL Server 2016+
-- Optional modern aggregation using STRING_AGG is included as a commented block, SQL Server 2022+


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
        partial_json_payload NVARCHAR(MAX) NOT NULL,        -- current awaiting partial payload
        current_hash BINARY(32) NULL,                       -- current hash of JSON payload
        previous_hash BINARY(32) NULL,                      -- previous hash of JSON payload
        submission_status NVARCHAR(50) DEFAULT 'Pending',   -- Status: Pending, Sent, Error
        submission_timestamp DATETIME DEFAULT GETDATE(),    -- data submitted timestamp
        api_response NVARCHAR(MAX) NULL,                    -- API response or error
        row_state NVARCHAR(10) DEFAULT 'New',               -- record state : New, Updated, Deleted, Unchanged
        last_updated DATETIME DEFAULT GETDATE()             -- timestamp data update/insertion
    );

END


/* Helpers, safe on 2012 */
IF OBJECT_ID('dbo.JsonEscape', 'FN') IS NULL
EXEC('CREATE FUNCTION dbo.JsonEscape(@s nvarchar(max)) RETURNS nvarchar(max) AS
BEGIN
    -- Escape backslash and quote first, then control chars 0x00 to 0x1F
    IF @s IS NULL RETURN NULL;
    DECLARE @r nvarchar(max) = REPLACE(REPLACE(@s, N'\', N'\\'), N'"', N'\"');
    -- Common controls
    SET @r = REPLACE(@r, CHAR(8),  N'\b');
    SET @r = REPLACE(@r, CHAR(9),  N'\t');
    SET @r = REPLACE(@r, CHAR(10), N'\n');
    SET @r = REPLACE(@r, CHAR(12), N'\f');
    SET @r = REPLACE(@r, CHAR(13), N'\r');
    RETURN @r;
END');

IF OBJECT_ID('dbo.JsonString', 'FN') IS NULL
EXEC('CREATE FUNCTION dbo.JsonString(@s nvarchar(max)) RETURNS nvarchar(max) AS
BEGIN
    RETURN CASE WHEN @s IS NULL THEN N''null'' ELSE N''"'' + dbo.JsonEscape(@s) + N''"'' END;
END');

IF OBJECT_ID('dbo.JsonDate10', 'FN') IS NULL
EXEC('CREATE FUNCTION dbo.JsonDate10(@d date) RETURNS nvarchar(12) AS
BEGIN
    RETURN CASE WHEN @d IS NULL THEN N''null''
                ELSE N''"'' + CONVERT(varchar(10), @d, 23) + N''"'' END;
END');

/* ===========================================================
   2012-compatible payload builder
   Replaces FOR JSON blocks with manual JSON assembly
   =========================================================== */

;WITH RawPayloads AS
(
    SELECT
        p.pers_person_id AS person_id,

        /* ---------- disabilities array, 2012 safe ---------- */
        disab.disabilities_json,

        /* ---------- child_details object ---------- */
        '{'
        + '"first_name":' + dbo.JsonString(p.pers_forename) + ','
        + '"surname":'    + dbo.JsonString(p.pers_surname)  + ','
        + '"unique_pupil_number":' + dbo.JsonString((
              SELECT TOP 1 link_identifier_value
              FROM ssd_linked_identifiers
              WHERE link_person_id = p.pers_person_id
                AND link_identifier_type = 'Unique Pupil Number'
              ORDER BY link_valid_from_date DESC
          )) + ','
        + '"former_unique_pupil_number":' + dbo.JsonString((
              SELECT TOP 1 link_identifier_value
              FROM ssd_linked_identifiers
              WHERE link_person_id = p.pers_person_id
                AND link_identifier_type = 'Former Unique Pupil Number'
              ORDER BY link_valid_from_date DESC
          )) + ','
        + '"unique_pupil_number_unknown_reason":' + dbo.JsonString(p.pers_upn_unknown) + ','
        + '"date_of_birth":'        + dbo.JsonDate10(p.pers_dob)          + ','
        + '"expected_date_of_birth":' + dbo.JsonDate10(p.pers_expected_dob) + ','
        + '"sex":'        + dbo.JsonString(CASE WHEN p.pers_sex IN ('M','F') THEN p.pers_sex ELSE 'U' END) + ','
        + '"ethnicity":'  + dbo.JsonString(p.pers_ethnicity) + ','
        + '"disabilities":' + ISNULL(disab.disabilities_json, '[]') + ','
        + '"postcode":'   + dbo.JsonString((
              SELECT TOP 1 a.addr_address_postcode
              FROM ssd_address a
              WHERE a.addr_person_id = p.pers_person_id
              ORDER BY a.addr_address_start_date DESC
          )) + ','
        + '"uasc_flag":'  + dbo.JsonString((
              SELECT TOP 1 immi.immi_immigration_status
              FROM ssd_immigration_status immi
              WHERE immi.immi_person_id = p.pers_person_id
              ORDER BY CASE WHEN immi.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                       immi.immi_immigration_status_start_date DESC
          )) + ','
        + '"uasc_end_date":' + dbo.JsonString((
              SELECT TOP 1 CONVERT(varchar(10), immi2.immi_immigration_status_end_date, 23)
              FROM ssd_immigration_status immi2
              WHERE immi2.immi_person_id = p.pers_person_id
              ORDER BY CASE WHEN immi2.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                       immi2.immi_immigration_status_start_date DESC
          )) + ','
        + '"purge":false'
        + '}' AS child_details_json,

        /* ---------- sdq_assessments array inside health_and_wellbeing ---------- */
        sdq.sdq_array_json,

        /* ---------- social_care_episodes array, pared to key pieces ---------- */
        sce.episodes_array_json,

        /* ---------- Top level object assembly ---------- */
        json_payload =
        '{'
        + '"la_child_id":' + dbo.JsonString(CONVERT(nvarchar(48), p.pers_person_id)) + ','
        + '"mis_child_id":' + dbo.JsonString(ISNULL(p.pers_common_child_id, 'SSD_PH_CCI')) + ','
        + '"purge":false,'
        + '"child_details":' + 
              /* embed already formatted object */ child_details_json + ','
        + '"health_and_wellbeing":{'
            + '"sdq_assessments":' + ISNULL(sdq.sdq_array_json, '[]') + ','
            + '"purge":false'
          + '},'
        + '"social_care_episodes":' + ISNULL(sce.episodes_array_json, '[]')
        + '}'
    FROM ssd_person p

    /* disabilities array via XML PATH */
    OUTER APPLY (
        SELECT
            '[' + STUFF((
                SELECT ',' + '"' + dbo.JsonEscape(d2.disa_disability_code) + '"'
                FROM ssd_disability AS d2
                WHERE d2.disa_person_id = p.pers_person_id
                ORDER BY d2.disa_disability_code
                FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(max)'), 1, 1, '') + ']'
    ) AS disab(disabilities_json)

    /* sdq_assessments array */
    OUTER APPLY (
        SELECT
            '[' + STUFF((
                SELECT ',' + '{'
                       + '"date":'  + dbo.JsonString(CONVERT(varchar(10), csdq.csdq_sdq_completed_date, 23)) + ','
                       + '"score":' + CASE WHEN csdq.csdq_sdq_score IS NULL THEN 'null'
                                           ELSE CONVERT(varchar(20), csdq.csdq_sdq_score) END
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

    /* social_care_episodes array, includes nested sub arrays */
    OUTER APPLY (
        SELECT
            '[' + STUFF((
                SELECT ',' + '{'
                    + '"social_care_episode_id":' + ISNULL(CONVERT(varchar(20), cine.cine_referral_id), 'null') + ','
                    + '"referral_date":' + dbo.JsonString(CONVERT(varchar(10), cine.cine_referral_date, 23)) + ','
                    + '"referral_source":' + dbo.JsonString(cine.cine_referral_source_code) + ','
                    + '"referral_no_further_action_flag":' + CASE WHEN cine.cine_referral_nfa = 1 THEN 'true' ELSE 'false' END + ','

                    /* care_worker_details */
                    + '"care_worker_details":' +
                        '[' + STUFF((
                            SELECT ',' + '{'
                                   + '"worker_id":' + dbo.JsonString(CONVERT(nvarchar(50), sw.prof_staff_id)) + ','
                                   + '"start_date":' + dbo.JsonString(CONVERT(varchar(10), sw.start_date, 23)) + ','
                                   + '"end_date":'   + dbo.JsonString(CONVERT(varchar(10), sw.end_date, 23))
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

                    /* child_and_family_assessments */
                    + '"child_and_family_assessments":' +
                        '[' + STUFF((
                            SELECT ',' + '{'
                                   + '"child_and_family_assessment_id":' + ISNULL(CONVERT(varchar(20), ca.cina_assessment_id), 'null') + ','
                                   + '"start_date":' + dbo.JsonString(CONVERT(varchar(10), ca.cina_assessment_start_date, 23)) + ','
                                   + '"authorisation_date":' + dbo.JsonString(CONVERT(varchar(10), ca.cina_assessment_auth_date, 23)) + ','
                                   + '"factors":' + ISNULL(NULLIF(af.cinf_assessment_factors_json, ''), '[]') + ','
                                   + '"purge":false'
                                + '}'
                            FROM ssd_cin_assessments ca
                            LEFT JOIN ssd_assessment_factors af
                              ON af.cinf_assessment_id = ca.cina_assessment_id
                            WHERE ca.cina_referral_id = cine.cine_referral_id
                            FOR XML PATH(''), TYPE
                        ).value('.', 'nvarchar(max)'), 1, 1, '') + ']' + ','

                    /* child_in_need_plans */
                    + '"child_in_need_plans":' +
                        '[' + STUFF((
                            SELECT ',' + '{'
                                   + '"child_in_need_plan_id":' + ISNULL(CONVERT(varchar(20), cinp.cinp_cin_plan_id), 'null') + ','
                                   + '"start_date":' + dbo.JsonString(CONVERT(varchar(10), cinp.cinp_cin_plan_start_date, 23)) + ','
                                   + '"end_date":'   + dbo.JsonString(CONVERT(varchar(10), cinp.cinp_cin_plan_end_date, 23)) + ','
                                   + '"purge":false'
                                + '}'
                            FROM ssd_cin_plans cinp
                            WHERE cinp.cinp_referral_id = cine.cine_referral_id
                            FOR XML PATH(''), TYPE
                        ).value('.', 'nvarchar(max)'), 1, 1, '') + ']' + ','

                    /* section_47_assessments, no JSON_VALUE on 2012, leave icpc flag null or derive from source if available */
                    + '"section_47_assessments":' +
                        '[' + STUFF((
                            SELECT ',' + '{'
                                   + '"section_47_assessment_id":' + ISNULL(CONVERT(varchar(20), s47e.s47e_s47_enquiry_id), 'null') + ','
                                   + '"start_date":' + dbo.JsonString(CONVERT(varchar(10), s47e.s47e_s47_start_date, 23)) + ','
                                   + '"icpc_required_flag":null,'  /* replace with a relational field if you have one */
                                   + '"icpc_date":' + dbo.JsonString(CONVERT(varchar(10), icpc.icpc_icpc_date, 23)) + ','
                                   + '"end_date":' + dbo.JsonString(CONVERT(varchar(10), s47e.s47e_s47_end_date, 23)) + ','
                                   + '"purge":false'
                                + '}'
                            FROM ssd_s47_enquiry s47e
                            LEFT JOIN ssd_initial_cp_conference icpc
                              ON icpc.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                            WHERE s47e.s47e_referral_id = cine.cine_referral_id
                            FOR XML PATH(''), TYPE
                        ).value('.', 'nvarchar(max)'), 1, 1, '') + ']' + ','

                    /* child_protection_plans */
                    + '"child_protection_plans":' +
                        '[' + STUFF((
                            SELECT ',' + '{'
                                   + '"child_protection_plan_id":' + ISNULL(CONVERT(varchar(20), cppl.cppl_cp_plan_id), 'null') + ','
                                   + '"start_date":' + dbo.JsonString(CONVERT(varchar(10), cppl.cppl_cp_plan_start_date, 23)) + ','
                                   + '"end_date":'   + dbo.JsonString(CONVERT(varchar(10), cppl.cppl_cp_plan_end_date, 23)) + ','
                                   + '"purge":false'
                                + '}'
                            FROM ssd_cp_plans cppl
                            WHERE cppl.cppl_referral_id = cine.cine_referral_id
                            FOR XML PATH(''), TYPE
                        ).value('.', 'nvarchar(max)'), 1, 1, '') + ']' + ','

                    /* child_looked_after_placements */
                    + '"child_looked_after_placements":' +
                        '[' + STUFF((
                            SELECT ',' + '{'
                                   + '"child_looked_after_placement_id":' + ISNULL(CONVERT(varchar(20), clap.clap_cla_placement_id), 'null') + ','
                                   + '"start_date":'   + dbo.JsonString(CONVERT(varchar(10), clae.clae_cla_episode_start_date, 23)) + ','
                                   + '"start_reason":' + dbo.JsonString(LEFT(clae.clae_cla_episode_start_reason, 3)) + ','
                                   + '"end_date":'     + dbo.JsonString(CONVERT(varchar(10), clae.clae_cla_episode_ceased_date, 23)) + ','
                                   + '"end_reason":'   + dbo.JsonString(LEFT(clae.clae_cla_episode_ceased_reason, 3)) + ','
                                   + '"placement_id":' + ISNULL(CONVERT(varchar(20), clap.clap_cla_placement_id), 'null') + ','
                                   + '"placement_start_date":' + dbo.JsonString(CONVERT(varchar(10), clap.clap_cla_placement_start_date, 23)) + ','
                                   + '"placement_type":' + dbo.JsonString(clap.clap_cla_placement_type) + ','
                                   + '"postcode":'       + dbo.JsonString(clap.clap_cla_placement_postcode) + ','
                                   + '"placement_end_date":' + dbo.JsonString(CONVERT(varchar(10), clap.clap_cla_placement_end_date, 23)) + ','
                                   + '"change_reason":' + dbo.JsonString(clap.clap_cla_placement_change_reason) + ','
                                   + '"purge":false'
                                + '}'
                            FROM ssd_cla_episodes clae
                            JOIN ssd_cla_placement clap
                              ON clap.clap_cla_id = clae.clae_cla_id
                            WHERE clae.clae_referral_id = cine.cine_referral_id
                            ORDER BY clap.clap_cla_placement_start_date DESC
                            FOR XML PATH(''), TYPE
                        ).value('.', 'nvarchar(max)'), 1, 1, '') + ']' + ','

                    /* adoption as single object, most recent */
                    + '"adoption":' +
                        ISNULL((
                            SELECT TOP 1
                                   '{'
                                   + '"initial_decision_date":' + dbo.JsonString(CONVERT(varchar(10), perm.perm_adm_decision_date, 23)) + ','
                                   + '"matched_date":'          + dbo.JsonString(CONVERT(varchar(10), perm.perm_matched_date, 23)) + ','
                                   + '"placed_date":'           + dbo.JsonString(CONVERT(varchar(10), perm.perm_placed_for_adoption_date, 23)) + ','
                                   + '"purge":false'
                                   + '}'
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
                        ), 'null') + ','

                    /* care_leavers as single object, most recent */
                    + '"care_leavers":' +
                        ISNULL((
                            SELECT TOP 1
                                   '{'
                                   + '"contact_date":' + dbo.JsonString(CONVERT(varchar(10), clea.clea_care_leaver_latest_contact, 23)) + ','
                                   + '"activity":'     + dbo.JsonString(LEFT(clea.clea_care_leaver_activity, 2)) + ','
                                   + '"accommodation":'+ dbo.JsonString(LEFT(clea.clea_care_leaver_accommodation, 1)) + ','
                                   + '"purge":false'
                                   + '}'
                            FROM ssd_care_leavers clea
                            WHERE clea.clea_person_id = p.pers_person_id
                            ORDER BY clea.clea_care_leaver_latest_contact DESC
                        ), 'null') + ','

                    + '"closure_date":'  + dbo.JsonString(CONVERT(varchar(10), cine.cine_close_date, 23)) + ','
                    + '"closure_reason":' + dbo.JsonString(cine.cine_close_reason) + ','
                    + '"purge":false'
                + '}'
                FROM ssd_cin_episodes cine
                WHERE cine.cine_person_id = p.pers_person_id
                FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(max)'), 1, 1, '') + ']'

    ) AS sce(episodes_array_json)
)
SELECT person_id, json_payload
FROM RawPayloads;


;WITH Hashed AS (
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
FROM Hashed h
OUTER APPLY (
    SELECT TOP (1) s.json_payload, s.current_hash
    FROM ssd_api_data_staging s
    WHERE s.person_id = h.person_id
    ORDER BY s.id DESC
) AS prev
WHERE prev.current_hash IS NULL
   OR prev.current_hash <> h.current_hash;



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
        partial_json_payload NVARCHAR(MAX) NOT NULL,        -- current awaiting partial payload
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


