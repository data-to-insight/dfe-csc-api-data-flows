
IF OBJECT_ID('ssd_change_log_hash', 'U') IS NOT NULL DROP TABLE ssd_change_log_hash  ;
CREATE TABLE ssd_change_log_hash (
    TableName NVARCHAR(255) NOT NULL,         -- Name of the source table
    PrimaryKey NVARCHAR(48) NOT NULL,         -- Primary key value
    CurrentHash BINARY(32) NULL,              -- Current hash of the row
    PreviousHash BINARY(32) NULL,             -- Previous hash of the row
    RowState NVARCHAR(10) DEFAULT 'new',      -- State of the row ('new', 'updated', 'deleted', 'unchanged')
    LastUpdated DATETIME DEFAULT GETDATE(),   -- Timestamp of the last update
    PRIMARY KEY (TableName, PrimaryKey)
);

-- loop to populate hash values for all tables
DECLARE @TableName NVARCHAR(255);
DECLARE @PrimaryKey NVARCHAR(48);
DECLARE @SQL NVARCHAR(MAX);

-- tmp store table schema details
CREATE TABLE #TableSchema (
    TableName NVARCHAR(255),
    PrimaryKey NVARCHAR(48)
);


-- populate table schema details
INSERT INTO #TableSchema (TableName, PrimaryKey)
-- API SSD table set -- 
INSERT INTO #TableSchema (TableName, PrimaryKey)
VALUES
    ('ssd_person', 'pers_person_id'),
    ('ssd_disability', 'disa_person_id'),
    ('ssd_address', 'addr_table_id'),
    ('ssd_immigration_status', 'immi_person_id'),
    ('ssd_ehcp_requests', 'ehcr_ehcp_request_id'),
    ('ssd_ehcp_assessment', 'ehca_ehcp_assessment_id'),
    ('ssd_ehcp_named_plan', 'ehcn_named_plan_id'),
    ('ssd_cin_episodes', 'cine_referral_id'),
    ('ssd_cin_assessments', 'cina_assessment_id'),
    ('ssd_assessment_factors', 'cinf_table_id'),
    ('ssd_cin_plans', 'cinp_cin_plan_id'),
    ('ssd_s47_enquiry', 's47e_s47_enquiry_id'),
    ('ssd_initial_cp_conference', 'icpc_icpc_id'),
    ('ssd_cp_plans', 'cppl_cp_plan_id'),
    ('ssd_cla_episodes', 'clae_cla_episode_id'),
    ('ssd_cla_placement', 'clap_cla_placement_id'),
    ('ssd_sdq_scores', 'csdq_table_id'),
    ('ssd_permanence', 'perm_table_id'),
    ('ssd_care_leavers', 'clea_table_id'),
    ('ssd_professionals', 'prof_professional_id'),
    ('ssd_involvements', 'invo_involvements_id'),
    ('ssd_sen_need', 'senn_table_id');

-- -- FULL SSD table set -- 
-- VALUES
--     ('ssd_person', 'pers_person_id'),
--     ('ssd_family', 'fami_table_id'),
--     ('ssd_address', 'addr_table_id'),
--     ('ssd_disability', 'disa_person_id'),
--     ('ssd_immigration_status', 'immi_person_id'),
--     ('ssd_mother', 'moth_table_id'),
--     ('ssd_legal_status', 'lega_legal_status_id'),
--     ('ssd_contacts', 'cont_contact_id'),
--     ('ssd_early_help_episodes', 'earl_episode_id'),
--     ('ssd_cin_episodes', 'cine_referral_id'),
--     ('ssd_cin_assessments', 'cina_assessment_id'),
--     ('ssd_assessment_factors', 'cinf_table_id'),
--     ('ssd_cin_plans', 'cinp_cin_plan_id'),
--     ('ssd_cin_visits', 'cinv_cin_visit_id'),
--     ('ssd_s47_enquiry', 's47e_s47_enquiry_id'),
--     ('ssd_initial_cp_conference', 'icpc_icpc_id'),
--     ('ssd_cp_plans', 'cppl_cp_plan_id'),
--     ('ssd_cp_visits', 'cppv_cp_visit_id'),
--     ('ssd_cp_reviews', 'cppr_cp_review_id'),
--     ('ssd_cla_episodes', 'clae_cla_episode_id'),
--     ('ssd_cla_convictions', 'clac_cla_conviction_id'),
--     ('ssd_cla_health', 'clah_health_check_id'),
--     ('ssd_cla_immunisations', 'clai_person_id'),
--     ('ssd_cla_substance_misuse', 'clas_substance_misuse_id'),
--     ('ssd_cla_placement', 'clap_cla_placement_id'),
--     ('ssd_cla_reviews', 'clar_cla_review_id'),
--     ('ssd_cla_visits', 'clav_cla_visit_id'),
--     ('ssd_cla_previous_permanence', 'lapp_table_id'),
--     ('ssd_cla_care_plan', 'lacp_table_id'),
--     ('ssd_sdq_scores', 'csdq_table_id'),
--     ('ssd_missing', 'miss_table_id'),
--     ('ssd_care_leavers', 'clea_table_id'),
--     ('ssd_permanence', 'perm_table_id'),
--     ('ssd_involvements', 'invo_involvements_id'),
--     ('ssd_professionals', 'prof_professional_id'),
--     ('ssd_send', 'send_table_id'),
--     ('ssd_ehcp_requests', 'ehcr_ehcp_request_id'),
--     ('ssd_ehcp_assessment', 'ehca_ehcp_assessment_id'),
--     ('ssd_ehcp_named_plan', 'ehcn_named_plan_id'),
--     ('ssd_ehcp_active_plans', 'ehcp_active_ehcp_id'),
--     ('ssd_sen_need', 'senn_table_id'),
--     ('ssd_pre_proceedings', 'prep_table_id'),
--     ('ssd_voice_of_child', 'voch_table_id'),
--     ('ssd_linked_identifiers', 'link_table_id'),
--     ('ssd_s251_finance', 's251_table_id'),
--     ('ssd_department', 'dept_team_id'),
--     ('ssd_version_log', 'version_number');

-- loop through tables
DECLARE table_cursor CURSOR FOR
SELECT TableName, PrimaryKey FROM #TableSchema;

OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @TableName, @PrimaryKey;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- SQL to calculate and insert hash vals
    SET @SQL = N'
        INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, CurrentHash, RowState, LastUpdated)
        SELECT
            ''' + @TableName + ''' AS TableName,
            CAST(' + @PrimaryKey + ' AS NVARCHAR(48)) AS PrimaryKey,
            HASHBYTES(''SHA2_256'', CONCAT_WS('''', *)) AS CurrentHash,
            ''new'' AS RowState,
            GETDATE() AS LastUpdated
        FROM ' + @TableName + ';
    ';
    EXEC sp_executesql @SQL;

    FETCH NEXT FROM table_cursor INTO @TableName, @PrimaryKey;
END;

CLOSE table_cursor;
DEALLOCATE table_cursor;


DROP TABLE #TableSchema;




-- populate hash table
MERGE INTO ssd_change_log_hash AS target
USING (
    SELECT 
        'ssd_person' AS TableName,
        pers_person_id AS PrimaryKey,
        HASHBYTES('SHA2_256', CONCAT(pers_person_id, pers_dob, pers_sex, pers_ethnicity)) AS NewHash
    FROM ssd_person
) AS source
ON target.TableName = source.TableName AND target.PrimaryKey = source.PrimaryKey

WHEN MATCHED AND target.CurrentHash <> source.NewHash THEN
    UPDATE SET 
        PreviousHash = target.CurrentHash,
        CurrentHash = source.NewHash,
        RowState = 'updated',
        LastUpdated = GETDATE()

WHEN MATCHED THEN
    UPDATE SET 
        RowState = 'unchanged',
        LastUpdated = GETDATE()

WHEN NOT MATCHED BY TARGET THEN
    INSERT (TableName, PrimaryKey, CurrentHash, RowState, LastUpdated)
    VALUES (source.TableName, source.PrimaryKey, source.NewHash, 'new', GETDATE())

WHEN NOT MATCHED BY SOURCE THEN
    UPDATE SET 
        RowState = 'deleted',
        PreviousHash = target.CurrentHash,
        CurrentHash = NULL,
        LastUpdated = GETDATE();


-- reset on API success... (needs to come from api! )
UPDATE ssd_change_log_hash
SET RowState = 'unchanged'
WHERE RowState IN ('new', 'updated', 'deleted');
