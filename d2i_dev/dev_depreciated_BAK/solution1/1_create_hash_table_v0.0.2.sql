IF OBJECT_ID('ssd_change_log_hash', 'U') IS NOT NULL DROP TABLE ssd_change_log_hash;
CREATE TABLE ssd_change_log_hash (
    TableName NVARCHAR(255) NOT NULL,         
    PrimaryKey NVARCHAR(48) NOT NULL,  
    LinkKey NVARCHAR(48) NULL,                -- link value (_person_id or equivalent)       
    CurrentHash BINARY(32) NULL,              -- current hash 
    PreviousHash BINARY(32) NULL,             -- previous hash 
    RowState NVARCHAR(10) DEFAULT 'new',      -- state of row ('new', 'updated', 'deleted', 'unchanged')
    LastUpdated DATETIME DEFAULT GETDATE(),   -- last update
    PRIMARY KEY (TableName, PrimaryKey)
);


-- 1. ssd_person

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_person' AS TableName,
    CAST(pers_person_id AS NVARCHAR(48)) AS PrimaryKey,
    HASHBYTES('SHA2_256', CONCAT_WS('', pers_person_id, pers_dob, pers_sex, pers_ethnicity)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_person;


-- 2. ssd_disability
-- Note _person_id is included in hash 
INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated) 
SELECT
    'ssd_disability' AS TableName,
    CAST(disa_table_id AS NVARCHAR(48)) AS PrimaryKey, 
    CAST(disa_person_id AS NVARCHAR(48)) AS LinkKey,   -- link value (_person_id)
    HASHBYTES('SHA2_256', CONCAT_WS('', disa_table_id, disa_person_id, disa_disability_code)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_disability;


-- 3. ssd_address

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_address' AS TableName,
    CAST(addr_table_id AS NVARCHAR(48)) AS PrimaryKey, 
    CAST(addr_person_id AS NVARCHAR(48)) AS LinkKey,   -- link value (_person_id)
    HASHBYTES('SHA2_256', CONCAT_WS('', addr_table_id, addr_person_id, addr_address_postcode, addr_address_start_date, addr_address_end_date)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_address;


-- 4. ssd_immigration_status

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_immigration_status' AS TableName,
    CAST(immi_immigration_status_id AS NVARCHAR(48)) AS PrimaryKey, 
    CAST(immi_person_id AS NVARCHAR(48)) AS LinkKey,               -- link value (_person_id)
    HASHBYTES('SHA2_256', CONCAT_WS('', immi_immigration_status_id, immi_person_id, immi_immigration_status, immi_immigration_status_start_date, immi_immigration_status_end_date)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_immigration_status;



-- 5. ssd_cin_episodes

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_cin_episodes' AS TableName,
    CAST(cine_referral_id AS NVARCHAR(48)) AS PrimaryKey, 
    CAST(cine_person_id AS NVARCHAR(48)) AS LinkKey,      -- link value (_person_id)
    HASHBYTES('SHA2_256', CONCAT_WS('', cine_referral_id, cine_person_id, cine_referral_date, cine_close_date, cine_close_reason)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_cin_episodes;


-- 6. ssd_cin_assessments

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_cin_assessments' AS TableName,
    CAST(cina_assessment_id AS NVARCHAR(48)) AS PrimaryKey, 
    CAST(cina_person_id AS NVARCHAR(48)) AS LinkKey,        -- link value (_person_id)
    HASHBYTES('SHA2_256', CONCAT_WS('', cina_assessment_id, cina_person_id, cina_assessment_start_date, cina_assessment_auth_date)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_cin_assessments;


-- 7. ssd_cin_plans

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_cin_plans' AS TableName,
    CAST(cinp_cin_plan_id AS NVARCHAR(48)) AS PrimaryKey, 
    CAST(cinp_person_id AS NVARCHAR(48)) AS LinkKey,      -- link value (_person_id)
    HASHBYTES('SHA2_256', CONCAT_WS('', cinp_cin_plan_id, cinp_person_id, cinp_cin_plan_start_date, cinp_cin_plan_end_date)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_cin_plans;


-- 8. ssd_cla_episodes

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_cla_episodes' AS TableName,
    CAST(clae_cla_episode_id AS NVARCHAR(48)) AS PrimaryKey, 
    CAST(clae_person_id AS NVARCHAR(48)) AS LinkKey,         -- link value (_person_id)
    HASHBYTES('SHA2_256', CONCAT_WS('', clae_cla_episode_id, clae_person_id, clae_cla_episode_start_date, clae_cla_episode_ceased)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_cla_episodes;


-- 9. ssd_cp_plans

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_cp_plans' AS TableName,
    CAST(cppl_cp_plan_id AS NVARCHAR(48)) AS PrimaryKey, 
    CAST(cppl_person_id AS NVARCHAR(48)) AS LinkKey,     -- link value (_person_id)
    HASHBYTES('SHA2_256', CONCAT_WS('', cppl_cp_plan_id, cppl_person_id, cppl_cp_plan_start_date, cppl_cp_plan_end_date)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_cp_plans;


-- 10. ssd_professionals

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_professionals' AS TableName,
    CAST(prof_professional_id AS NVARCHAR(48)) AS PrimaryKey, 
    NULL AS LinkKey,                                          -- No _person_id available
    HASHBYTES('SHA2_256', CONCAT_WS('', prof_professional_id, prof_professional_name)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_professionals;


-- 11. ssd_involvements

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_involvements' AS TableName,
    CAST(invo_involvements_id AS NVARCHAR(48)) AS PrimaryKey, 
    CAST(invo_person_id AS NVARCHAR(48)) AS LinkKey,          -- link value (_person_id)
    HASHBYTES('SHA2_256', CONCAT_WS('', invo_involvements_id, invo_person_id, invo_involvement_start_date, invo_involvement_end_date)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_involvements;


-- 12. ssd_sen_need

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_sen_need' AS TableName,
    CAST(senn_table_id AS NVARCHAR(48)) AS PrimaryKey, 
    NULL AS LinkKey,                                   -- No _person_id available
    HASHBYTES('SHA2_256', CONCAT_WS('', senn_table_id, senn_active_ehcp_need_type)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_sen_need;




-- ssd_ehcp_requests

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_ehcp_requests' AS TableName,
    CAST(ehcr_ehcp_request_id AS NVARCHAR(48)) AS PrimaryKey, 
    NULL AS LinkKey,                                         -- No _person_id available
    HASHBYTES('SHA2_256', CONCAT_WS('', ehcr_ehcp_request_id, ehcr_send_table_id, ehcr_ehcp_req_date)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_ehcp_requests;


-- ssd_ehcp_assessment

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_ehcp_assessment' AS TableName,
    CAST(ehca_ehcp_assessment_id AS NVARCHAR(48)) AS PrimaryKey, 
    NULL AS LinkKey,                                            -- No _person_id available
    HASHBYTES('SHA2_256', CONCAT_WS('', ehca_ehcp_assessment_id, ehca_ehcp_request_id, ehca_ehcp_assessment_outcome_date)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_ehcp_assessment;


-- ssd_ehcp_named_plan

INSERT INTO ssd_change_log_hash (TableName, PrimaryKey, LinkKey, CurrentHash, RowState, LastUpdated)
SELECT
    'ssd_ehcp_named_plan' AS TableName,
    CAST(ehcn_named_plan_id AS NVARCHAR(48)) AS PrimaryKey, 
    NULL AS LinkKey,                                       -- No _person_id available
    HASHBYTES('SHA2_256', CONCAT_WS('', ehcn_named_plan_id, ehcn_ehcp_asmt_id, ehcn_named_plan_start_date, ehcn_named_plan_ceased_date)) AS CurrentHash,
    'new' AS RowState,
    GETDATE() AS LastUpdated
FROM ssd_ehcp_named_plan;


-- Update PreviousHash for all rows
-- This only occurs once at set up! 
UPDATE ssd_change_log_hash
SET 
    PreviousHash = CurrentHash
WHERE 
    PreviousHash IS NULL;