
-- change logging checksum table 
IF OBJECT_ID('ssd_checksum', 'U') IS NOT NULL DROP TABLE ssd_checksum;
CREATE TABLE ssd_checksum (
    table_name NVARCHAR(128) NOT NULL,
    record_key NVARCHAR(255) NOT NULL,
    checksum_value NVARCHAR(128),
    last_modified DATETIME DEFAULT GETDATE(),
    PRIMARY KEY (table_name, record_key)
);

-- -- Need elevated permissions to do this
-- ALTER TABLE ssd_checksum
-- ADD CONSTRAINT pk_ssd_checksum PRIMARY KEY (table_name, record_key);

CREATE INDEX idx_checksum_value ON ssd_checksum (checksum_value);
CREATE INDEX idx_last_modified ON ssd_checksum (last_modified);


-- metadata table has full list of tables and PK fields 
-- this table used to assist creating record keys, without having to dynamically access the info
-- getting ssd_ table names rarely an issue, but accessing PKs might be... hence this route. 
IF OBJECT_ID('ssd_table_metadata', 'U') IS NOT NULL DROP TABLE ssd_table_metadata;
CREATE TABLE ssd_table_metadata (
    table_name NVARCHAR(128) PRIMARY KEY,
    primary_key NVARCHAR(48) NOT NULL
);

CREATE INDEX idx_primary_key ON ssd_table_metadata (primary_key);

INSERT INTO ssd_table_metadata (table_name, primary_key)
VALUES 
    ('ssd_person', 'pers_person_id'),
    ('ssd_family', 'fami_table_id'),
    ('ssd_address', 'addr_table_id'),
    ('ssd_disability', 'disa_person_id'),
    ('ssd_immigration_status', 'immi_person_id'),
    ('ssd_mother', 'moth_table_id'),
    ('ssd_legal_status', 'lega_legal_status_id'),
    ('ssd_contacts', 'cont_contact_id'),
    ('ssd_early_help_episodes', 'earl_episode_id'),
    ('ssd_cin_episodes', 'cine_referral_id'),
    ('ssd_cin_assessments', 'cina_assessment_id'),
    ('ssd_assessment_factors', 'cinf_table_id'),
    ('ssd_cin_plans', 'cinp_cin_plan_id'),
    ('ssd_cin_visits', 'cinv_cin_visit_id'),
    ('ssd_s47_enquiry', 's47e_s47_enquiry_id'),
    ('ssd_initial_cp_conference', 'icpc_icpc_id'),
    ('ssd_cp_plans', 'cppl_cp_plan_id'),
    ('ssd_cp_visits', 'cppv_cp_visit_id'),
    ('ssd_cp_reviews', 'cppr_cp_review_id'),
    ('ssd_cla_episodes', 'clae_cla_episode_id'),
    ('ssd_cla_convictions', 'clac_cla_conviction_id'),
    ('ssd_cla_health', 'clah_health_check_id'),
    ('ssd_cla_immunisations', 'clai_person_id'),
    ('ssd_cla_substance_misuse', 'clas_substance_misuse_id'),
    ('ssd_cla_placement', 'clap_cla_placement_id'),
    ('ssd_cla_reviews', 'clar_cla_review_id'),
    ('ssd_cla_visits', 'clav_cla_visit_id'),
    ('ssd_cla_previous_permanence', 'lapp_table_id'),
    ('ssd_cla_care_plan', 'lacp_table_id'),
    ('ssd_sdq_scores', 'csdq_table_id'),
    ('ssd_missing', 'miss_table_id'),
    ('ssd_care_leavers', 'clea_table_id'),
    ('ssd_permanence', 'perm_table_id'),
    ('ssd_involvements', 'invo_involvements_id'),
    ('ssd_professionals', 'prof_professional_id'),
    ('ssd_send', 'send_table_id'),
    ('ssd_ehcp_requests', 'ehcr_ehcp_request_id'),
    ('ssd_ehcp_assessment', 'ehca_ehcp_assessment_id'),
    ('ssd_ehcp_named_plan', 'ehcn_named_plan_id'),
    ('ssd_ehcp_active_plans', 'ehcp_active_ehcp_id'),
    ('ssd_sen_need', 'senn_table_id'),
    ('ssd_pre_proceedings', 'prep_table_id'),
    ('ssd_voice_of_child', 'voch_table_id'),
    ('ssd_linked_identifiers', 'link_table_id'),
    ('ssd_s251_finance', 's251_table_id'),
    ('ssd_department', 'dept_team_id'),
    ('ssd_version_log', 'version_number');



-- pre-populate the checksum table from the meta data
DECLARE @tableName NVARCHAR(128);
DECLARE @primaryKey NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

-- Cursor to loop through all tables in the metadata table
DECLARE tableCursor CURSOR FOR
SELECT table_name, primary_key
FROM ssd_table_metadata;

OPEN tableCursor;

FETCH NEXT FROM tableCursor INTO @tableName, @primaryKey;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Generate and insert record_key and checksum into ssd_checksum
    -- Checksum of all columns (Debug: needs adjustment to disallow AGG/DTTM fields!! )
    SET @sql = N'
    INSERT INTO ssd_checksum (table_name, record_key, checksum_value, last_modified)
    SELECT 
        ''' + @tableName + ''' AS table_name, -- Table name
        ''' + @tableName + ''' + ''|'' + CAST(' + @primaryKey + ' AS NVARCHAR(MAX)) AS record_key, -- Composite record key
        CHECKSUM(*), -- Checksum of all columns (Debug: needs adjustment to disallow AGG/DTTM fields!! )
        GETDATE() AS last_modified -- Current timestamp
    FROM ' + @tableName + ';';

    EXEC sp_executesql @sql;

    FETCH NEXT FROM tableCursor INTO @tableName, @primaryKey;
END;

CLOSE tableCursor;
DEALLOCATE tableCursor;


-- verify ssd_checksum table
SELECT table_name, COUNT(*) AS record_count
FROM ssd_checksum
GROUP BY table_name;










-- -- MERGE - incremental updates rather than truncating and repopulating
-- MERGE INTO ssd_checksum AS target
-- USING (
--     SELECT 
--         'ssd_cp_reviews' AS table_name, 
--         'ssd_cp_reviews' + '|' + CAST(cppr_cp_review_id AS NVARCHAR(MAX)) AS record_key,
--         CHECKSUM(cppr_cp_plan_id, cppr_person_id, cppr_cp_review_due) AS checksum_value,
--         GETDATE() AS last_modified
--     FROM ssd_cp_reviews
-- ) AS source
-- ON target.table_name = source.table_name AND target.record_key = source.record_key
-- WHEN MATCHED AND target.checksum_value <> source.checksum_value THEN
--     UPDATE SET checksum_value = source.checksum_value, last_modified = source.last_modified
-- WHEN NOT MATCHED BY TARGET THEN
--     INSERT (table_name, record_key, checksum_value, last_modified)
--     VALUES (source.table_name, source.record_key, source.checksum_value, source.last_modified)
-- WHEN NOT MATCHED BY SOURCE THEN
--     DELETE;
