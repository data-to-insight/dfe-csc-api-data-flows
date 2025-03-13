-- -- start of initial set up, not included in re-runs, run only once

Use HDM_Local; -- SystemC/LLogic specific

IF OBJECT_ID('ssd_api_data_staging', 'U') IS NOT NULL DROP TABLE ssd_api_data_staging;

-- includes initialisation values on submission_status/row_state
CREATE TABLE ssd_api_data_staging (
    id                      INT IDENTITY(1,1) PRIMARY KEY,           
    person_id               NVARCHAR(48) NULL,              -- Link value (_person_id or equivalent)
    previous_json_payload   NVARCHAR(MAX) NULL,             -- Enable sub-attribute purge tracking
    json_payload            NVARCHAR(MAX) NULL,         -- JSON data
    partial_json_payload    NVARCHAR(MAX) NULL,         -- Reductive JSON data payload
    previous_hash           BINARY(32) NULL,                -- Previous hash of JSON payload
    current_hash            BINARY(32) NULL,                -- Current hash of JSON payload
    row_state               NVARCHAR(10) DEFAULT 'new',     -- Record state: New, Updated, Deleted, Unchanged
    last_updated            DATETIME DEFAULT GETDATE(),     -- Last update timestamp
    submission_status       NVARCHAR(50) DEFAULT 'pending', -- Status: Pending, Sent, Error
    api_response            NVARCHAR(MAX) NULL,             -- API response or error messages
    submission_timestamp    DATETIME                        -- Timestamp on API submission
);
GO

-- Optimisations...
CREATE NONCLUSTERED INDEX ssd_idx_person_hash ON ssd_api_data_staging (person_id, current_hash, row_state); -- Lookups for change tracking
CREATE NONCLUSTERED INDEX ssd_idx_submission_status ON ssd_api_data_staging (submission_status, submission_timestamp); -- API submission processing
CREATE NONCLUSTERED INDEX ssd_idx_last_updated ON ssd_api_data_staging (last_updated); -- Recent updates retrieval


-- -- end of initial set up 



-- KEY: metadata={AttributeReferenceNum ,SSDReference,Mandatory,GuidanceNotes}

-- maintain copy of previous/current json data  needed for purge tracking
-- should we do this within the shell script? on successful send? 
UPDATE ssd_api_data_staging SET previous_json_payload = json_payload;

-- For potential inclusion of 3 digit la_code within payload 
-- use [HDM].[Education].[DIM_LOOKUP_HOME_AUTHORITY].[MAIN_CODE] -- metadata={1 ,N/A,True,Standard 3 digit LA code}


-- KEY: metadata={AttributeReferenceNum ,SSDReference,Mandatory,GuidanceNotes}
WITH ComputedData AS (
    SELECT top 4000 -- Debug | Testing limiter ONLY
        p.pers_person_id AS person_id,
        (
            SELECT 
                -- Attribute Group: Children
                p.pers_person_id AS [la_child_id],  
                p.pers_common_child_id AS [mis_child_id],  
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

                -- child_details.purge applies only to child_details
                CAST(0 AS bit) AS [child_details.purge], 

                -- Top-level purge applies to everything in this child record
                CAST(0 AS bit) AS [purge], 

                -- Health and Wellbeing (incl. purge flag)
                (
                    SELECT 
                        CONVERT(VARCHAR(10), csdq.csdq_sdq_completed_date, 23) AS [sdq_date],  
                        csdq.csdq_sdq_score AS [sdq_score],  
                        CAST(0 AS bit) AS [purge]  
                    FROM ssd_sdq_scores csdq
                    WHERE csdq.csdq_person_id = p.pers_person_id
                    ORDER BY csdq.csdq_sdq_completed_date DESC 
                    FOR JSON PATH
                ) AS [health_and_wellbeing],  

                -- Social Care Episodes (incl. purge flag)
                (
                    SELECT  
                        cine.cine_referral_id AS [social_care_episode_id],  
                        CONVERT(VARCHAR(10), cine.cine_referral_date, 23) AS [referral_date],  
                        cine.cine_referral_source_code AS [referral_source],  
                        CONVERT(VARCHAR(10), cine.cine_close_date, 23) AS [closure_date],  
                        cine.cine_close_reason AS [closure_reason],  
                        cine.cine_referral_nfa AS [referral_no_further_action_flag],  
                        CAST(0 AS bit) AS [purge],  

                        -- Care Worker Details
                        (
                            SELECT 
                                pr.prof_staff_id AS [worker_id],  
                                CONVERT(VARCHAR(10), i.invo_involvement_start_date, 23) AS [start_date],  
                                CONVERT(VARCHAR(10), i.invo_involvement_end_date, 23) AS [end_date]  
                            FROM ssd_involvements i
                            INNER JOIN ssd_professionals pr 
                                ON i.invo_professional_id = pr.prof_professional_id
                            WHERE i.invo_person_id = p.pers_person_id
                            ORDER BY i.invo_involvement_start_date DESC
                            FOR JSON PATH
                        ) AS [care_worker_details]

                    FROM ssd_cin_episodes cine
                    WHERE cine.cine_person_id = p.pers_person_id
                    FOR JSON PATH
                ) AS [social_care_episodes],  

                -- Education Health Care Plans (incl. purge flag)
                (
                    SELECT 
                        ehcn.ehcn_named_plan_id AS [education_health_care_plan_id],  
                        CONVERT(VARCHAR(10), ehcr.ehcr_ehcp_req_date, 23) AS [request_received_date],  
                        CONVERT(VARCHAR(10), ehcr.ehcr_ehcp_req_outcome_date, 23) AS [request_outcome_date],  
                        CONVERT(VARCHAR(10), ehca.ehca_ehcp_assessment_outcome_date, 23) AS [assessment_outcome_date],  
                        CONVERT(VARCHAR(10), ehcn.ehcn_named_plan_start_date, 23) AS [plan_start_date],  
                        CAST(0 AS bit) AS [purge]  
                    FROM ssd_ehcp_named_plan ehcn
                    INNER JOIN ssd_ehcp_assessment ehca
                        ON ehcn.ehcn_ehcp_asmt_id = ehca.ehca_ehcp_assessment_id
                    INNER JOIN ssd_ehcp_requests ehcr
                        ON ehca.ehca_ehcp_request_id = ehcr.ehcr_ehcp_request_id
                    WHERE ehcr.ehcr_send_table_id IN (
                        SELECT send_table_id
                        FROM ssd_send
                        WHERE send_person_id = p.pers_person_id
                    )
                    FOR JSON PATH
                ) AS [education_health_care_plans]

            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS json_payload
    FROM ssd_person p
)
-- end of CTE


-- Opt 1: Combined update and compute hash vals
-- Use Option 1 (Single-Step Merge & Hash) for:
-- Small to Medium sized LAs - i.e. datasets ~under 500k records - additional hash computation overhead isn't significant.

-- Merge computed data into API staging table, handle inserts, updates, and deletions
MERGE INTO ssd_api_data_staging AS target
USING (
    -- Select new computed data, generate SHA-256 hash for change tracking
    SELECT 
        person_id, 
        json_payload,
        HASHBYTES('SHA2_256', CAST(json_payload AS NVARCHAR(MAX))) AS new_hash
    FROM ComputedData
) AS source
ON target.person_id = source.person_id  -- Match records based on person_id

-- If record match found, update existing record
WHEN MATCHED THEN
    UPDATE SET 
        target.json_payload = source.json_payload,  -- Update JSON payload
        target.current_hash = source.new_hash,      -- Update hash to detect future changes
        target.last_updated = GETDATE(),           -- Refresh last updated timestamp
        target.row_state = 
            CASE 
                WHEN target.current_hash <> source.new_hash THEN 'Updated' -- Mark as "Updated" if hash differs
                ELSE 'Unchanged' -- Otherwise, retain "Unchanged" status
            END

-- If no match exists (new record), insert into staging table
WHEN NOT MATCHED THEN
    INSERT (person_id, json_payload, current_hash, submission_status, row_state, last_updated)
    VALUES (source.person_id, source.json_payload, source.new_hash, 'Pending', 'New', GETDATE())

-- If record exists in staging table but not/no-longer in source, mark as deleted
WHEN NOT MATCHED BY SOURCE THEN
    UPDATE SET 
        target.row_state = 'Deleted',
        target.last_updated = GETDATE(); -- Track deletion timestamp

--- End opt1








-- -- Opt 2: Compute hash vals in seperate process - reduced update overheads on high date loads
-- -- Use Option 2 (Separate Hash Computation) for:
-- -- Larger LAs - i.e. datasets ~million records -  where computing hashes inline could slow down MERGE.
-- -- UPDATE will only run on fresh records that need hashing.

-- MERGE INTO ssd_api_data_staging AS target
-- USING ComputedData AS source
-- ON target.person_id = source.person_id

-- -- WHEN MATCHED logic into single update
-- WHEN MATCHED THEN
--     UPDATE SET 
--         target.json_payload = source.json_payload,
--         target.last_updated = GETDATE(),
--         target.row_state = 
--             CASE 
--                 WHEN target.json_payload <> source.json_payload THEN 'Updated'
--                 ELSE 'Unchanged' 
--             END

-- WHEN NOT MATCHED THEN
--     INSERT (person_id, json_payload, submission_status, row_state, last_updated)
--     VALUES (source.person_id, source.json_payload, 'Pending', 'New', GETDATE())

-- WHEN NOT MATCHED BY SOURCE THEN
--     UPDATE SET 
--         target.row_state = 'Deleted',
--         target.last_updated = GETDATE();


-- -- (2)Update hash vals
-- UPDATE ssd_api_data_staging
-- SET 
--     current_hash = HASHBYTES('SHA2_256', CAST(json_payload AS NVARCHAR(MAX))),
--     previous_hash = COALESCE(previous_hash, HASHBYTES('SHA2_256', CAST(json_payload AS NVARCHAR(MAX))))
-- WHERE current_hash IS NULL;
-- --- End opt 2






-- -- Reduce data in staging table for testing
-- DECLARE @percent INT = 50;
-- DECLARE @rows_to_delete INT;

-- SELECT @rows_to_delete = COUNT(*) * @percent / 100 FROM ssd_api_data_staging;

-- DELETE FROM ssd_api_data_staging
-- WHERE id IN (
--     SELECT TOP (@rows_to_delete) id
--     FROM ssd_api_data_staging
--     ORDER BY NEWID()
-- );
