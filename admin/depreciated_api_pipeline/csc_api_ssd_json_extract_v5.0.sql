-- -- start of initial set up, not included in re-runs, run only once

Use HDM_Local; -- SystemC/LLogic specific

IF OBJECT_ID('ssd_api_data_staging', 'U') IS NOT NULL DROP TABLE ssd_api_data_staging;

-- includes initialisation values on submission_status/row_state
CREATE TABLE ssd_api_data_staging (
    id                      INT IDENTITY(1,1) PRIMARY KEY,           
    person_id               NVARCHAR(48) NULL,              -- Link value (_person_id or equivalent)
    json_payload            NVARCHAR(MAX) NULL,         	-- JSON payload data
    previous_json_payload   NVARCHAR(MAX) NULL,             -- Enable sub-attribute purge tracking (phase 2)
    partial_json_payload    NVARCHAR(MAX) NULL,         	-- Reductive JSON data payload (phase 2)
    previous_hash           BINARY(32) NULL,                -- Previous hash of JSON payload
    current_hash            BINARY(32) NULL,                -- Current hash of JSON payload
    row_state               NVARCHAR(10) DEFAULT 'new',     -- Record state: New(initial default), Updated, Deleted, Unchanged(default+post api send)
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





-- maintain copy of previous/current json data  needed for purge tracking
-- UPDATE ssd_api_data_staging SET previous_json_payload = json_payload;





-- For potential dynamic inclusion of 3 digit la_code within payload 
-- use [HDM].[Education].[DIM_LOOKUP_HOME_AUTHORITY].[MAIN_CODE] -- metadata={1 ,N/A,True,Standard 3 digit LA code}

-- KEY: metadata={AttributeReferenceNum ,SSDReference,Mandatory,GuidanceNotes}
WITH ComputedData AS (
    SELECT top 4000 -- debug | Testing limiter ONLY
    p.pers_person_id AS person_id,
    (
        SELECT  
            p.pers_person_id AS [la_child_id],
            ISNULL(p.pers_common_child_id, 'SSD_PH') AS [mis_child_id],  

            -- JSON_QUERY(
            --     (
            --         SELECT 
            --             'SSD_PH' AS [first_name],  
            --             'SSD_PH' AS [surname],  
            --             (
            --                 SELECT TOP 1 link_identifier_value
            --                 FROM ssd_linked_identifiers
            --                 WHERE link_person_id = p.pers_person_id 
            --                 AND link_identifier_type = 'Unique Pupil Number'
            --                 ORDER BY link_valid_from_date DESC
            --             ) AS [unique_pupil_number], 
            --             CAST(0 AS bit) AS [purge]
            --         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            --     )
            -- ) AS [child_details], 


            -- Child Details
            JSON_QUERY(
                (
                SELECT 
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
                        SELECT JSON_QUERY(
                            (SELECT '[' + STRING_AGG('"' + d.disa_disability_code + '"', ',') + ']' 
                            FROM ssd_disability d
                            WHERE d.disa_person_id = p.pers_person_id)
                        )
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
                            CASE WHEN immi.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                            immi.immi_immigration_status_start_date DESC
                    ) AS [uasc_flag],  
                    (
                        SELECT TOP 1 CONVERT(VARCHAR(10), immi.immi_immigration_status_end_date, 23)
                        FROM ssd_immigration_status immi
                        WHERE immi.immi_person_id = p.pers_person_id
                        ORDER BY 
                            CASE WHEN immi.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                            immi.immi_immigration_status_start_date DESC
                    ) AS [uasc_end_date],  
                    CAST(0 AS bit) AS [purge]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
				)
            ) AS [child_details],  

			-- -- Health and Wellbeing
			-- JSON_QUERY(
			-- 	(
			-- 		SELECT 
			-- 			(
			-- 				SELECT 
			-- 					CONVERT(VARCHAR(10), csdq.csdq_sdq_completed_date, 23) AS [date], 
			-- 					csdq.csdq_sdq_score AS [score]  
			-- 				FROM ssd_sdq_scores csdq
			-- 				WHERE csdq.csdq_person_id = p.pers_person_id
			-- 				ORDER BY csdq.csdq_sdq_completed_date DESC 
			-- 				FOR JSON PATH
			-- 			) AS [sdq_assessments],  
			-- 			CAST(0 AS bit) AS [purge]  
			-- 		FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
			-- 	)
			-- ) AS [health_and_wellbeing],

			-- Health and Wellbeing
			JSON_QUERY(
				(
					SELECT 
						(
							SELECT 
								CONVERT(VARCHAR(10), csdq.csdq_sdq_completed_date, 23) AS [date], 
								csdq.csdq_sdq_score AS [score]  
							FROM ssd_sdq_scores csdq
							WHERE 
								csdq.csdq_person_id = p.pers_person_id
								-- having to filter as some placeholder date values coming through
								AND csdq.csdq_sdq_score IS NOT NULL
								AND csdq.csdq_sdq_completed_date IS NOT NULL
								AND csdq.csdq_sdq_completed_date > '1900-01-01'
							ORDER BY csdq.csdq_sdq_completed_date DESC 
							FOR JSON PATH
						) AS [sdq_assessments],  
						CAST(0 AS bit) AS [purge]  
					FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
				)
			) AS [health_and_wellbeing],


			-- -- Education Health Care Plans
			-- JSON_QUERY(
			-- 	(
			-- 		SELECT 
			-- 			ehcn.ehcn_named_plan_id AS [education_health_care_plan_id],
			-- 			CONVERT(VARCHAR(10), ehcr.ehcr_ehcp_req_date, 23) AS [request_received_date],
			-- 			CONVERT(VARCHAR(10), ehcr.ehcr_ehcp_req_outcome_date, 23) AS [request_outcome_date],
			-- 			CONVERT(VARCHAR(10), ehca.ehca_ehcp_assessment_outcome_date, 23) AS [assessment_outcome_date],
			-- 			CONVERT(VARCHAR(10), ehcn.ehcn_named_plan_start_date, 23) AS [plan_start_date],
			-- 			CAST(0 AS bit) AS [purge]
			-- 		FROM ssd_ehcp_named_plan ehcn
			-- 		INNER JOIN ssd_ehcp_assessment ehca
			-- 			ON ehcn.ehcn_ehcp_asmt_id = ehca.ehca_ehcp_assessment_id
			-- 		INNER JOIN ssd_ehcp_requests ehcr
			-- 			ON ehca.ehca_ehcp_request_id = ehcr.ehcr_ehcp_request_id
			-- 		WHERE ehcr.ehcr_send_table_id IN (
			-- 			SELECT send_table_id
			-- 			FROM ssd_send
			-- 			WHERE send_person_id = p.pers_person_id
			-- 		)
			-- 		FOR JSON PATH
			-- 	)
			-- ) AS [education_health_care_plans],


            JSON_QUERY(
                (
                    SELECT  
                        cine.cine_referral_id AS [social_care_episode_id],  
                        CONVERT(VARCHAR(10), cine.cine_referral_date, 23) AS [referral_date],  
                        cine.cine_referral_source_code AS [referral_source],  
                        cine.cine_referral_nfa AS [referral_no_further_action_flag],  

						(
							SELECT *
							FROM (
								SELECT 
									pr.prof_staff_id AS [worker_id],  
									CONVERT(VARCHAR(10), i.invo_involvement_start_date, 23) AS [start_date],  
									CONVERT(VARCHAR(10), i.invo_involvement_end_date, 23) AS [end_date]
									
								FROM ssd_involvements i
								INNER JOIN ssd_professionals pr 
									ON i.invo_professional_id = pr.prof_professional_id
								WHERE i.invo_referral_id = cine.cine_referral_id
							) AS sorted_sw -- wrapped derived table to order within JSON
							ORDER BY sorted_sw.start_date DESC
							FOR JSON PATH
						) AS [care_worker_details],


						-- Nested Child and Family Assessments
						(
							SELECT 
								ca.cina_assessment_id AS [child_and_family_assessment_id],
								CONVERT(VARCHAR(10), ca.cina_assessment_start_date, 23) AS [start_date],
								CONVERT(VARCHAR(10), ca.cina_assessment_auth_date, 23) AS [authorisation_date],
								JSON_QUERY(		
									CASE 
										WHEN af.cinf_assessment_factors_json IS NULL OR af.cinf_assessment_factors_json = '' 
											THEN '[]'
										ELSE af.cinf_assessment_factors_json
									END
								) AS [factors], 
								CAST(0 AS bit) AS [purge]
							FROM ssd_cin_assessments ca
							LEFT JOIN ssd_assessment_factors af
								ON af.cinf_assessment_id = ca.cina_assessment_id
							WHERE ca.cina_referral_id = cine.cine_referral_id
							FOR JSON PATH
						) AS [child_and_family_assessments],



						-- Nested Child in Need Plans
						(
							SELECT 
								cinp.cinp_cin_plan_id AS [child_in_need_plan_id],
								CONVERT(VARCHAR(10), cinp.cinp_cin_plan_start_date, 23) AS [start_date],
								CONVERT(VARCHAR(10), cinp.cinp_cin_plan_end_date, 23) AS [end_date],
								CAST(0 AS bit) AS [purge]
							FROM ssd_cin_plans cinp
							WHERE cinp.cinp_referral_id = cine.cine_referral_id
							FOR JSON PATH
						) AS [child_in_need_plans],


						
						-- Nested s47 assessments
                        (
                            SELECT 
                                s47e.s47e_s47_enquiry_id AS [section_47_assessment_id],
                                CONVERT(VARCHAR(10), s47e.s47e_s47_start_date, 23) AS [start_date],
                                JSON_VALUE(s47e.s47e_s47_outcome_json, '$.CP_CONFERENCE_FLAG') AS [icpc_required_flag], -- pull from json field
                                CONVERT(VARCHAR(10), icpc.icpc_icpc_date, 23) AS [icpc_date],
                                CONVERT(VARCHAR(10), s47e.s47e_s47_end_date, 23) AS [end_date],
                                CAST(0 AS bit) AS [purge]
                            FROM ssd_s47_enquiry s47e
                            LEFT JOIN ssd_initial_cp_conference icpc
                                ON icpc.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                            WHERE s47e.s47e_referral_id = cine.cine_referral_id
                            FOR JSON PATH
                        ) AS [section_47_assessments],


						-- Nested Child Protection Plans
						(
							SELECT 
								cppl.cppl_cp_plan_id AS [child_protection_plan_id],
								CONVERT(VARCHAR(10), cppl.cppl_cp_plan_start_date, 23) AS [start_date],
								CONVERT(VARCHAR(10), cppl.cppl_cp_plan_end_date, 23) AS [end_date],
								CAST(0 AS bit) AS [purge]
							FROM ssd_cp_plans cppl
							WHERE cppl.cppl_referral_id = cine.cine_referral_id
							FOR JSON PATH
						) AS [child_protection_plans],


						-- Nested Child Looked After Placements
						(
							SELECT 
								clae.clae_cla_placement_id AS [child_looked_after_placement_id],
								CONVERT(VARCHAR(10), clae.clae_cla_episode_start_date, 23) AS [start_date],
								LEFT(clae.clae_cla_episode_start_reason, 3) AS [start_reason],
								CONVERT(VARCHAR(10), clae.clae_cla_episode_ceased, 23) AS [end_date],
								LEFT(clae.clae_cla_episode_ceased_reason, 3) AS [end_reason],
								CAST(0 AS bit) AS [purge],

								-- Nested CLA Placement Details
								(
									SELECT
										clap.clap_cla_placement_id AS [placement_id],
										CONVERT(VARCHAR(10), clap.clap_cla_placement_start_date, 23) AS [start_date],
										'SSD_PH' AS [start_reason], -- debug
										clap.clap_cla_placement_type AS [placement_type],
										clap.clap_cla_placement_postcode AS [postcode],
										CONVERT(VARCHAR(10), clap.clap_cla_placement_end_date, 23) AS [end_date],
										'SSD_PH' AS [end_reason], -- debug
										clap.clap_cla_placement_change_reason AS [change_reason]
									FROM ssd_cla_placement clap
									WHERE clap.clap_cla_id = clae.clae_cla_id
									ORDER BY clap.clap_cla_placement_start_date DESC
									FOR JSON PATH
								) AS [placement_details]
							FROM ssd_cla_episodes clae 
							WHERE clae.clae_referral_id = cine.cine_referral_id
							FOR JSON PATH
						) AS [child_looked_after_placements],


                            -- -- Nested Child Looked After Placements
                            -- (
                            --     SELECT
                            --         clae.clae_cla_placement_id AS [child_looked_after_placement_id],
                            --         CONVERT(VARCHAR(10), clae.clae_cla_episode_start_date, 23) AS [start_date],
                            --         clae.clae_cla_episode_start_reason AS [start_reason],
                            --         clap.clap_cla_placement_type AS [placement_type],
                            --         clap.clap_cla_placement_postcode AS [postcode],
                            --         CONVERT(VARCHAR(10), clae.clae_cla_episode_ceased_date, 23) AS [end_date],
                            --         clae.clae_cla_episode_ceased_reason AS [end_reason],
                            --         clap.clap_cla_placement_change_reason AS [change_reason]
                            --     FROM ssd_development.ssd_cla_episodes clae
                            --     INNER JOIN ssd_development.ssd_cla_placement clap
                            --         ON clae.clae_cla_placement_id = clap.clap_cla_placement_id
                            --     WHERE clae.clae_person_id = cine.cine_person_id
                            --     FOR JSON PATH
                            -- ) AS [child_looked_after_placements],



						-- Nested Adoptions
						(
							SELECT 
								CONVERT(VARCHAR(10), perm.perm_adm_decision_date, 23) AS [initial_decision_date],
								CONVERT(VARCHAR(10), perm.perm_matched_date, 23) AS [matched_date],
								CONVERT(VARCHAR(10), perm.perm_placed_for_adoption_date, 23) AS [placed_date],
								CAST(0 AS bit) AS [purge]
							FROM ssd_permanence perm
							WHERE perm.perm_person_id = p.pers_person_id
							OR perm.perm_cla_id IN (
								SELECT clae.clae_cla_id
								FROM ssd_cla_episodes clae
								WHERE clae.clae_person_id = p.pers_person_id
							)
							FOR JSON PATH
						) AS [adoption],


						-- Nested Care Leavers
						JSON_QUERY(
							(
								SELECT 
									CONVERT(VARCHAR(10), clea.clea_care_leaver_latest_contact, 23) AS [contact_date],
									LEFT(clea.clea_care_leaver_activity, 2) AS [activity],
									LEFT(clea.clea_care_leaver_accommodation, 1) AS [accommodation],
									CAST(0 AS bit) AS [purge]
								FROM ssd_care_leavers clea
								WHERE clea.clea_person_id = p.pers_person_id
								ORDER BY clea.clea_care_leaver_latest_contact DESC
								FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
							)
						) AS [care_leavers],

                        CONVERT(VARCHAR(10), cine.cine_close_date, 23) AS [closure_date],  
                        cine.cine_close_reason AS [closure_reason],  
                        CAST(0 AS bit) AS [purge],

                    FROM ssd_cin_episodes cine
                    WHERE cine.cine_person_id = p.pers_person_id
                    FOR JSON PATH
                )
            ) AS [social_care_episodes]

        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS json_payload
FROM ssd_person p
)

-- -- obtain records with max data examples for testing
-- SELECT *
-- FROM ComputedData
-- ORDER BY LEN(json_payload) DESC, person_id;





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
        target.current_hash = source.new_hash,      -- Refresh/update current hash
        target.last_updated = GETDATE(),           	-- Refresh last updated timestamp
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




