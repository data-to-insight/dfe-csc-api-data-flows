
IF OBJECT_ID('ssd_api_data_staging', 'U') IS NOT NULL DROP TABLE ssd_api_data_staging;

-- includes initialisation values on submission_status/row_state
CREATE TABLE ssd_api_data_staging (
    id INT IDENTITY(1,1)            PRIMARY KEY,           
    person_id                       NVARCHAR(48) NULL,                      -- Link value (_person_id or equivalent)
    json_payload                    NVARCHAR(MAX) NOT NULL,                 -- JSON data payload
    previous_json_payload           NVARCHAR(MAX) NULL;                     -- Enable sub-attribute purge tracking
    current_hash                    BINARY(32) NULL,                        -- Current hash of JSON payload
    previous_hash                   BINARY(32) NULL,                        -- Previous hash of JSON payload
    submission_status               NVARCHAR(50) DEFAULT 'Pending',         -- Status: Pending, Sent, Error
    submission_timestamp            DATETIME,                               -- Timestamp on API submission
    api_response                    NVARCHAR(MAX) NULL,                     -- API response or error messages
    row_state                       NVARCHAR(10) DEFAULT 'New',             -- Record state: New, Updated, Deleted, Unchanged
    last_updated                    DATETIME DEFAULT GETDATE()              -- Last update timestamp
);

-- Optimisations...
CREATE NONCLUSTERED INDEX ssd_idx_person_hash ON ssd_api_data_staging (person_id, current_hash, row_state); -- Lookups for change tracking
CREATE NONCLUSTERED INDEX ssd_idx_submission_status ON ssd_api_data_staging (submission_status, submission_timestamp); -- API submission processing
CREATE NONCLUSTERED INDEX ssd_idx_last_updated ON ssd_api_data_staging (last_updated); -- Recent updates retrieval



-- KEY: metadata={AttributeReferenceNum ,SSDReference,Mandatory,GuidanceNotes}

INSERT INTO ssd_api_data_staging (person_id, json_payload)
-- For potential inclusion of 3 digit la_code within payload 
-- use [HDM].[Education].[DIM_LOOKUP_HOME_AUTHORITY].[MAIN_CODE] -- metadata={1 ,N/A,True,Standard 3 digit LA code}
SELECT 
    p.pers_person_id AS person_id, -- stand-alone identifier within staging table
    (
        -- JSON Payload data start 
        SELECT 
            -- Attribute Group: Children
            p.pers_person_id AS [la_child_id],  
            'SSD_PH' AS [first_name],  
            'SSD_PH' AS [surname],  
            (
                SELECT TOP 1 link_identifier_value
                FROM ssd_linked_identifiers
                WHERE link_person_id = p.pers_person_id 
                  AND link_identifier_type = 'Unique Pupil Number'
                ORDER BY link_valid_from_date DESC
            ) AS [unique_pupil_number],  
            (
                SELECT TOP 1 link_identifier_value
                FROM ssd_linked_identifiers
                WHERE link_person_id = p.pers_person_id 
                  AND link_identifier_type = 'Former Unique Pupil Number'
                ORDER BY link_valid_from_date DESC
            ) AS [former_unique_pupil_number],  
            p.pers_upn_unknown AS [unique_pupil_number_unknown_reason],  
            CONVERT(VARCHAR(10), p.pers_dob, 23) AS [date_of_birth],  
            CONVERT(VARCHAR(10), p.pers_expected_dob, 23) AS [expected_date_of_birth],  
            CASE 
                WHEN p.pers_sex = 'M' THEN 'M'
                WHEN p.pers_sex = 'F' THEN 'F'
                ELSE 'U'
            END AS [sex],  
            p.pers_ethnicity AS [ethnicity],  
            (
                SELECT 
                    CASE 
                        WHEN COUNT(d.disa_disability_code) = 0 THEN '[]'
                        ELSE '[' + STRING_AGG(d.disa_disability_code, ',') + ']' 
                    END
                FROM ssd_disability d
                WHERE d.disa_person_id = p.pers_person_id
                GROUP BY d.disa_person_id
            ) AS [disabilities],  
            (
                SELECT TOP 1 a.addr_address_postcode
                FROM ssd_address a
                WHERE a.addr_person_id = p.pers_person_id
                ORDER BY a.addr_address_start_date DESC
            ) AS [postcode],  
            (
                SELECT TOP 1 immi.immi_immigration_status
                FROM ssd_immigration_status immi
                WHERE immi.immi_person_id = p.pers_person_id
                ORDER BY 
                    CASE 
                        WHEN immi.immi_immigration_status_end_date IS NULL THEN 1 
                        ELSE 0 
                    END,
                    immi.immi_immigration_status_start_date DESC
            ) AS [uasc_flag],  
            (
                SELECT TOP 1 CONVERT(VARCHAR(10), immi.immi_immigration_status_end_date, 23)
                FROM ssd_immigration_status immi
                WHERE immi.immi_person_id = p.pers_person_id
                ORDER BY 
                    CASE 
                        WHEN immi.immi_immigration_status_end_date IS NULL THEN 1 
                        ELSE 0 
                    END,
                    immi.immi_immigration_status_start_date DESC
            ) AS [child_details.uasc_end_date],  

            -- **Hardcoded purge flag**
            'false' AS [purge],

            -- Attribute Group: Social Care Episodes
            (
                SELECT  
                    cine.cine_referral_id AS [social_care_episode_id],  
                    CONVERT(VARCHAR(10), cine.cine_referral_date, 23) AS [referral_date],  
                    cine.cine_referral_source_code AS [referral_source],  
                    CONVERT(VARCHAR(10), cine.cine_close_date, 23) AS [closure_date],  
                    cine.cine_close_reason AS [closure_reason],  
                    cine.cine_referral_nfa AS [referral_no_further_action_flag],  

                    -- **Hardcoded purge flag**
                    'false' AS [purge],

                    -- Attribute Group: Child in Need Plans
                    (
                        SELECT 
                            cinp.cinp_cin_plan_id AS [child_in_need_plan_id],  
                            CONVERT(VARCHAR(10), cinp.cinp_cin_plan_start_date, 23) AS [start_date],  
                            CONVERT(VARCHAR(10), cinp.cinp_cin_plan_end_date, 23) AS [end_date],  

                            -- **Hardcoded purge flag**
                            'false' AS [purge]
                        FROM ssd_cin_plans cinp
                        WHERE cinp.cinp_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_in_need_plans],  

                    -- Attribute Group: Child Look After
                    (
                        SELECT 
                            clae.clae_cla_placement_id AS [child_looked_after_placement_id],  
                            CONVERT(VARCHAR(10), clae.clae_cla_episode_start_date, 23) AS [start_date],  
                            LEFT(clae.clae_cla_episode_start_reason, 3) AS [start_reason],  
                            clae.clae_cla_episode_ceased_date AS [ceased],  
                            LEFT(clae.clae_cla_episode_ceased_reason, 3) AS [end_reason],  

                            -- **Hardcoded purge flag**
                            'false' AS [purge]
                        FROM ssd_cla_episodes clae
                        WHERE clae.clae_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_looked_after_placements],  

                    -- Attribute Group: Adoptions
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), perm.perm_adm_decision_date, 23) AS [date_initial_decision],  
                            CONVERT(VARCHAR(10), perm.perm_matched_date, 23) AS [date_match],  
                            CONVERT(VARCHAR(10), perm.perm_placed_for_adoption_date, 23) AS [date_placed],  

                            -- **Hardcoded purge flag**
                            'false' AS [purge]
                        FROM ssd_permanence perm
                        WHERE perm.perm_person_id = p.pers_person_id
                        OR perm.perm_cla_id IN (
                            SELECT clae.clae_cla_id
                            FROM ssd_cla_episodes clae
                            WHERE clae.clae_person_id = p.pers_person_id
                        )
                        FOR JSON PATH
                    ) AS [adoptions]  

                FROM ssd_cin_episodes cine
                WHERE cine.cine_person_id = p.pers_person_id
                FOR JSON PATH
            ) AS [social_care_episodes]  

        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS json_payload
FROM ssd_person p;



-- select * from ssd_api_data_staging;
-- where json_payload like '%child_protection_plans%'
-- AND json_payload like '%section_47_assessments%'
-- WHERE json_payload like '%child_in_need_plans%'
-- AND json_payload like '%cla_episodes%';
-- WHERE json_payload like '%education_health_care_plans%';




-- change tracking hashing seperated from main query (reduce in-query overheads)

-- change tracking hashing
UPDATE ssd_api_data_staging
SET 
    current_hash = HASHBYTES('SHA2_256', CAST(json_payload AS NVARCHAR(MAX))), -- reset/re-evaluate every data refresh
    previous_hash = COALESCE(previous_hash, HASHBYTES('SHA2_256', CAST(json_payload AS NVARCHAR(MAX)))) -- only set if NULL using single pass
                                                                                                        -- Incl. blanket populate during SET-UP (initialisation)

-- Reset status(es) during TESTING
UPDATE ssd_api_data_staging_anon  -- note this is the ANON table
SET submission_status = 'Pending'
WHERE submission_status <> 'Pending' OR submission_status IS NULL;
