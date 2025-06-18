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
UPDATE ssd_api_data_staging SET previous_json_payload = json_payload;

-- For potential inclusion of 3 digit la_code within payload 
-- use [HDM].[Education].[DIM_LOOKUP_HOME_AUTHORITY].[MAIN_CODE] -- metadata={1 ,N/A,True,Standard 3 digit LA code}


-- KEY: metadata={AttributeReferenceNum ,SSDReference,Mandatory,GuidanceNotes}
WITH ComputedData AS (
    SELECT top 4000 -- debug | Testing limiter ONLY
        p.pers_person_id AS person_id,
        (
            SELECT 
            -- Attribute Group: Children
                p.pers_person_id AS [la_child_id],                                      -- metadata={2 ,PERS001A,True,Max 36 Chars|CHILD12345}  
            -- p.pers_common_child_id AS [common_person_id],                            -- metadata={N/A, PERS002A, False, FUTURE USE Max 20 Chars}
            'SSD_PH' AS [first_name],                                                   -- metadata={6,PERS0015A,False,Max 128 chars} 
            'SSD_PH' AS [surname],                                                      -- metadata={7,PERS0016A,False,Max 128 chars} 
            (
                SELECT TOP 1 link_identifier_value
                FROM ssd_linked_identifiers
                WHERE link_person_id = p.pers_person_id 
                  AND link_identifier_type = 'Unique Pupil Number'
                ORDER BY link_valid_from_date DESC
            ) AS [unique_pupil_number],                                                 -- metadata={3,LINK004A,False,13 char UPN} 
            (
                SELECT TOP 1 link_identifier_value
                FROM ssd_linked_identifiers
                WHERE link_person_id = p.pers_person_id 
                  AND link_identifier_type = 'Former Unique Pupil Number'
                ORDER BY link_valid_from_date DESC
            ) AS [former_unique_pupil_number],                                          -- metadata={4,LINK004A,False,13 char UPN} 
            p.pers_upn_unknown AS [unique_pupil_number_unknown_reason],                 -- metadata={5,PERS007A,False,See Additional Notes for list|UN1} 
            CONVERT(VARCHAR(10), p.pers_dob, 23) AS [date_of_birth],                    -- metadata={8,PERS005A,False,YYYY-MM-DD} 
            CONVERT(VARCHAR(10), p.pers_expected_dob, 23) AS [expected_date_of_birth],  -- metadata={9,PERS009A,False,YYYY-MM-DD} 
            CASE 
                WHEN p.pers_sex = 'M' THEN 'M'
                WHEN p.pers_sex = 'F' THEN 'F'
                ELSE 'U'
            END AS [sex],                                                               -- metadata={10,PERS002A,False,See Additional Notes for list|M|F} 
            p.pers_ethnicity AS [ethnicity],                                            -- metadata={11,PERS004A,False,See Additional Notes for list} 
            (
                SELECT 
                    CASE 
                        WHEN COUNT(d.disa_disability_code) = 0 THEN '[]' -- empty array if none
                        ELSE '[' + STRING_AGG(d.disa_disability_code, ',') + ']' 
                    END
                FROM ssd_disability d
                WHERE d.disa_person_id = p.pers_person_id
                GROUP BY d.disa_person_id
            ) AS [disabilities],                                                        -- metadata={12,DISA002A, False, See Additional Notes for list|[HAND, VIS]}  
            (
                SELECT TOP 1 a.addr_address_postcode
                FROM ssd_address a
                WHERE a.addr_person_id = p.pers_person_id
                ORDER BY a.addr_address_start_date DESC
            ) AS [postcode],                                                            -- metadata={13,ADDR006A,False,Up to 8 characters matching a Postcode format} 
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
            ) AS [uasc_flag],                                                           -- metadata={14,IMMI002A,False,TRUE|FALSE} 
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
            ) AS [child_details.uasc_end_date],                                         -- metadata={15,IMMI004A,False,YYYY-MM-DD} 

            -- Attribute Group: Social Care Episodes
            -- Social Care Episodes/CIN Episodes
            (
                SELECT  
                    cine.cine_referral_id AS [social_care_episode_id],                                              -- metadata={16,CINE001A,True,Max 36 Chars} 
                    CONVERT(VARCHAR(10), cine.cine_referral_date, 23) AS [referral_date],                           -- metadata={17,CINE003A,False,YYYY-MM-DD} 
                    cine.cine_referral_source_code AS [referral_source],                                            -- metadata={18,CINE004A,False,See Additional Notes for list} 
                    CONVERT(VARCHAR(10), cine.cine_close_date, 23) AS [closure_date],                               -- metadata={19,CINE007A,False,YYYY-MM-DD} 
                    cine.cine_close_reason AS [closure_reason],                                                     -- metadata={20,CINE006A,False,See Additional Notes for list} 
                    cine.cine_referral_nfa AS [referral_no_further_action_flag],                                    -- metadata={21,CINE011A,False,TRUE|FALSE} 

                    -- Attribute Group: Children and Families Assessment
                    -- Nested Child and Family Assessments
                    (
                        SELECT 
                            ca.cina_assessment_id AS [child_and_family_assessment_id],                              -- metadata={22,CINA001A,True,Max 36 Chars} 
                            CONVERT(VARCHAR(10), ca.cina_assessment_start_date, 23) AS [start_date],                -- metadata={23,CINA003A,False,YYYY-MM-DD} 
                            CONVERT(VARCHAR(10), ca.cina_assessment_auth_date, 23) AS [authorisation_date],         -- metadata={24,CINA005A,False,YYYY-MM-DD} 
                            CASE 
                                WHEN af.cinf_assessment_factors_json IS NULL OR af.cinf_assessment_factors_json = '' THEN '[]'
                                ELSE af.cinf_assessment_factors_json
                            END AS [assessment_factors]                                                             -- metadata={25,CINF002A,False,See Additional Notes for list|[1A, 3C]}
                        FROM ssd_cin_assessments ca
                        LEFT JOIN ssd_assessment_factors af
                            ON af.cinf_assessment_id = ca.cina_assessment_id
                        WHERE ca.cina_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_and_family_assessments], 


                    -- Attribute Group: Child in Need Plans
                    -- Nested CIN Plans
                    (
                        SELECT 
                            cinp.cinp_cin_plan_id AS [child_in_need_plan_id],                                       -- metadata={26,,True,Max 36 Chars}
                            CONVERT(VARCHAR(10), cinp.cinp_cin_plan_start_date, 23) AS [start_date],                -- metadata={27,,False,YYYY-MM-DD}
                            CONVERT(VARCHAR(10), cinp.cinp_cin_plan_end_date, 23) AS [end_date]                     -- metadata={28,,False,YYYY-MM-DD}
                        FROM ssd_cin_plans cinp
                        WHERE cinp.cinp_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_in_need_plans], 


                    -- Attribute Group: S47 Assessments
                    -- Nested S47 Enquiries
                    (
                        SELECT 
                            s47e.s47e_s47_enquiry_id AS [section_47_assessment_id],                                 -- metadata={29,,True,Max 36 Chars}
                            CONVERT(VARCHAR(10), s47e.s47e_s47_start_date, 23) AS [start_date],                     -- metadata={30,,False,YYYY-MM-DD}
                            JSON_VALUE(s47e.s47e_s47_outcome_json, '$.CP_CONFERENCE_FLAG') AS [icpc_required_flag], -- metadata={31,S47E007A,False,TRUE|FALSE}
                            CONVERT(VARCHAR(10), icpc.icpc_icpc_date, 23) AS [icpc_date],                           -- metadata={32,,False,YYYY-MM-DD}
                            CONVERT(VARCHAR(10), s47e.s47e_s47_end_date, 23) AS [end_date]                          -- metadata={33,,False,YYYY-MM-DD}
                        FROM ssd_s47_enquiry s47e
                        LEFT JOIN ssd_initial_cp_conference icpc
                            ON icpc.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                        WHERE s47e.s47e_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [section_47_assessments],


                    -- Attribute Group: Child Protection Plans
                    -- Nested CP Plans
                    (
                        SELECT 
                            cppl.cppl_cp_plan_id AS [child_protection_plan_id],                                     -- metadata={34,,True,Max 36 Chars}
                            CONVERT(VARCHAR(10), cppl.cppl_cp_plan_start_date, 23) AS [start_date],                 -- metadata={35,,False,YYYY-MM-DD}
                            CONVERT(VARCHAR(10), cppl.cppl_cp_plan_end_date, 23) AS [end_date]                      -- metadata={36,,False,YYYY-MM-DD}
                        FROM ssd_cp_plans cppl
                        WHERE cppl.cppl_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_protection_plans], 


                    -- Attribute Group: Child Look After
                    -- Nested CLA Episodes
                    (
                        SELECT 
                            clae.clae_cla_placement_id AS [child_looked_after_placement_id],                        -- metadata={37,CLAE001A,True,Max 36 Chars} # TESTING
                            CONVERT(VARCHAR(10), clae.clae_cla_episode_start_date, 23) AS [start_date],             -- metadata={38,CLAE003A,False,YYYY-MM-DD} # TESTING (should this be clap.? as below)
                            LEFT(clae.clae_cla_episode_start_reason, 3) AS [start_reason],                          -- metadata={39,CLAE004A,False,See Additional Notes for list}
                            clae.clae_cla_episode_ceased AS [ceased],  -- needs SSD spec - updating to clae_cla_episode_ceased_date                                               -- metadata={42,CLAE005A,False,YYYY-MM-DD} # TESTING
                            LEFT(clae.clae_cla_episode_ceased_reason, 3) AS [end_reason],                           -- metadata={43,CLAE006A,False,See Additional Notes for list|e.g. E11} # TESTING

                            -- Nested CLA Placement () # TESTING - some sub elements potentially not correctly nested here! 
                            (
                                SELECT
                                    clap.clap_cla_placement_id AS [placement_id],                                   -- metadata={37,CLAP001A,True,Max 36 Chars} # TESTING
                                    CONVERT(VARCHAR(10), clap.clap_cla_placement_start_date, 23) AS [start_date],   -- metadata={38,CLAP003A,False,YYYY-MM-DD} # TESTING
                                    clap.clap_cla_placement_postcode AS [placement_postcode],                       -- metadata={40,CLAP008A,False, tbc}
                                    clap.clap_cla_placement_type AS [placement_type],                               -- metadata={41,CLAP004A,False,See Additional Notes for list|E.g. R1}
                                    CONVERT(VARCHAR(10), clap.clap_cla_placement_end_date, 23) AS [end_date],       -- metadata={42,CLAP009A,False,YYYY-MM-DD}
                                    clap.clap_cla_placement_change_reason AS [placement_change_reason]              -- metadata={44,CLAP010A,False,See Additional Notes for list|E.g. CARPL}
                                
                                FROM ssd_cla_placement clap
                                WHERE clap.clap_cla_id = clae.clae_cla_id
                                ORDER BY clap.clap_cla_placement_start_date desc -- most recent placement first
                                FOR JSON PATH
                            ) AS [placement_details] 
                        FROM ssd_cla_episodes clae 
                        WHERE clae.clae_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_looked_after_placements], 


                    -- Attribute Group: Health and Wellbeing
                    -- Nested Health and Wellbeing
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), csdq.csdq_sdq_completed_date, 23) AS [sdq_date],                   -- metadata={45,,False,YYYY-MM-DD}
                            csdq.csdq_sdq_score AS [sdq_score]                                                      -- metadata={46,,False,Integer between 0 and 40 (Inclusive)}
                        FROM ssd_sdq_scores csdq
                        WHERE csdq.csdq_person_id = p.pers_person_id
                        ORDER BY csdq.csdq_sdq_completed_date DESC -- most recent first
                        FOR JSON PATH
                    ) AS [health_and_wellbeing], 

                    -- Attribute Group: Adoptions
                    -- Nested Adoptions
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), perm.perm_adm_decision_date, 23) AS [date_initial_decision],       -- metadata={47,PERM003A,False,YYYY-MM-DD}
                            CONVERT(VARCHAR(10), perm.perm_matched_date, 23) AS [date_match],                       -- metadata={48,PERM008A,False,YYYY-MM-DD}
                            CONVERT(VARCHAR(10), perm.perm_placed_for_adoption_date, 23) AS [date_placed]           -- metadata={49,PERM007A,False,YYYY-MM-DD}
                        FROM ssd_permanence perm
                        WHERE perm.perm_person_id = p.pers_person_id
                        OR perm.perm_cla_id IN (
                            SELECT clae.clae_cla_id
                            FROM ssd_cla_episodes clae
                            WHERE clae.clae_person_id = p.pers_person_id
                        )
                        FOR JSON PATH
                    ) AS [adoptions], 

                    -- Attribute Group: Care Leavers
                    -- Nested Care Leavers
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), clea.clea_care_leaver_latest_contact, 23) AS [contact_date],       -- metadata={50,CLEA005A,False,YYYY-MM-DD}
                            LEFT(clea.clea_care_leaver_activity, 2) AS [activity],                                  -- metadata={51,CLEA008A,False,See Additional Notes for list}
                            LEFT(clea.clea_care_leaver_accommodation, 1) AS [accommodation]                         -- metadata={52,CLEA006A,False,See Additional Notes for list}
                        FROM ssd_care_leavers clea
                        WHERE clea.clea_person_id = p.pers_person_id
                        ORDER BY clea.clea_care_leaver_latest_contact DESC -- most recent contact first
                        FOR JSON PATH
                        
                    ) AS [care_leavers] 

                FROM ssd_cin_episodes cine
                WHERE cine.cine_person_id = p.pers_person_id
                FOR JSON PATH
            ) AS [social_care_episodes], 


            -- Attribute Group: Social Care Workers
            -- Social/Case Workers 
            (
                SELECT 
                    pr.prof_staff_id AS [worker_id],                                                                -- metadata={53,PROF010A,True,Max 12 chars}
                    CONVERT(VARCHAR(10), i.invo_involvement_start_date, 23) AS [worker_start_date],                 -- metadata={54,INVO002A,False,YYYY-MM-DD}
                    CASE 
                        WHEN i.invo_involvement_end_date IS NULL THEN NULL
                        ELSE CONVERT(VARCHAR(10), i.invo_involvement_end_date, 23)
                    END AS [worker_end_date]                                                                        -- metadata={55,INVO003A,False,YYYY-MM-DD}
                FROM ssd_involvements i
                INNER JOIN ssd_professionals pr 
                    ON i.invo_professional_id = pr.prof_professional_id
                WHERE i.invo_person_id = p.pers_person_id
                ORDER BY i.invo_involvement_start_date DESC -- most recent involvement first
                FOR JSON PATH
            ) AS [social_workers], 


            -- Attribute Group: Educational Health and Care Plans
            -- Education Health Care Plans
            (
                SELECT 
                    ehcn.ehcn_named_plan_id AS [education_health_care_plan_id],                                     -- metadata={56,EHCN001A,True,Max 36 chars}
                    CONVERT(VARCHAR(10), ehcr.ehcr_ehcp_req_date, 23) AS [request_received_date],                   -- metadata={57,EHCR003A,False,YYYY-MM-DD}
                    CONVERT(VARCHAR(10), ehcr.ehcr_ehcp_req_outcome_date, 23) AS [request_outcome_date],            -- metadata={58,EHCA003A,False,YYYY-MM-DD}
                    CONVERT(VARCHAR(10), ehca.ehca_ehcp_assessment_outcome_date, 23) AS [assessment_outcome_date],  -- metadata={59,EHCR003A,False,YYYY-MM-DD}
                    CONVERT(VARCHAR(10), ehcn.ehcn_named_plan_start_date, 23) AS [plan_start_date]                  -- metadata={60,EHCN003A,False,YYYY-MM-DD}
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
