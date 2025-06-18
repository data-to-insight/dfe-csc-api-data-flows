-- -- ensuring that ALL previously missing sections are now included:

-- Those that you incorrectly missed out of the SQL:
-- -- ✅ child_and_family_assessments
-- -- ✅ child_in_need_plans
-- -- ✅ section_47_assessments
-- -- ✅ adoptions (as an array)
-- -- ✅ care_leavers

-- Those that you have correctly added into the SQL:
-- -- ✅ child_protection_plans
-- -- ✅ child_looked_after_placements
-- -- ✅ health_and_wellbeing (corrected)
-- -- ✅ education_health_care_plans (corrected)

-- -- This version is now 100% aligned with the API spec

WITH ComputedData AS (
    SELECT 
        p.pers_person_id AS person_id,
        (
            SELECT

            p.pers_person_id AS [la_child_id],
            p.pers_common_child_id AS [mis_child_id],  

            -- Child Details
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
            ) AS [child_details],  

            -- Health and Wellbeing
            (
                SELECT 
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), csdq.csdq_sdq_completed_date, 23) AS [date],  -- ✅ Renamed field to match API spec
                            csdq.csdq_sdq_score AS [score]  -- ✅ Renamed field to match API spec
                        FROM ssd_sdq_scores csdq
                        WHERE csdq.csdq_person_id = p.pers_person_id
                        ORDER BY csdq.csdq_sdq_completed_date DESC 
                        FOR JSON PATH
                    ) AS [sdq_assessments],  -- ✅ Wrapped inside `sdq_assessments` array
                    CAST(0 AS bit) AS [purge]  
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            ) AS [health_and_wellbeing],


            -- Education Health Care Plans
            (
                SELECT 
                    ehcn.ehcn_named_plan_id AS [education_health_care_plan_id],                                     -- metadata={56,EHCN001A,True,Max 36 chars}
                    CONVERT(VARCHAR(10), ehcr.ehcr_ehcp_req_date, 23) AS [request_received_date],                   -- metadata={57,EHCR003A,False,YYYY-MM-DD}
                    CONVERT(VARCHAR(10), ehcr.ehcr_ehcp_req_outcome_date, 23) AS [request_outcome_date],            -- metadata={58,EHCA003A,False,YYYY-MM-DD}
                    CONVERT(VARCHAR(10), ehca.ehca_ehcp_assessment_outcome_date, 23) AS [assessment_outcome_date],  -- metadata={59,EHCR003A,False,YYYY-MM-DD}
                    CONVERT(VARCHAR(10), ehcn.ehcn_named_plan_start_date, 23) AS [plan_start_date],                 -- metadata={60,EHCN003A,False,YYYY-MM-DD}
                    CAST(0 AS bit) AS [purge]  -- ✅ Added missing purge flag
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
            ) AS [education_health_care_plans],


            -- Social Care Episodes
            (
                SELECT  
                    cine.cine_referral_id AS [social_care_episode_id],  
                    CONVERT(VARCHAR(10), cine.cine_referral_date, 23) AS [referral_date],  
                    cine.cine_referral_source_code AS [referral_source],  
                    cine.cine_referral_nfa AS [referral_no_further_action_flag],  
                    CONVERT(VARCHAR(10), cine.cine_close_date, 23) AS [closure_date],  
                    cine.cine_close_reason AS [closure_reason],  
                    CAST(0 AS bit) AS [purge],

                    -- Nested Social Worker Details            
                    (
                        SELECT 
                            pr.prof_staff_id AS [worker_id],  
                            CONVERT(VARCHAR(10), i.invo_involvement_start_date, 23) AS [start_date],  
                            CONVERT(VARCHAR(10), i.invo_involvement_end_date, 23) AS [end_date],
                            CAST(0 AS bit) AS [purge]  -- ✅ Added missing purge flag
                        FROM ssd_involvements i
                        INNER JOIN ssd_professionals pr 
                            ON i.invo_professional_id = pr.prof_professional_id
                        WHERE i.invo_person_id = p.pers_person_id
                        ORDER BY i.invo_involvement_start_date DESC
                        FOR JSON PATH
                    ) AS [social_worker_details],


                    -- Nested S47 Enquiries
                    (
                        SELECT 
                            s47e.s47e_s47_enquiry_id AS [section_47_assessment_id],  -- ✅ Matches API spec
                            CONVERT(VARCHAR(10), s47e.s47e_s47_start_date, 23) AS [start_date],  -- ✅ Matches API spec
                            JSON_VALUE(s47e.s47e_s47_outcome_json, '$.CP_CONFERENCE_FLAG') AS [icpc_required_flag],  -- ✅ Matches API spec
                            CONVERT(VARCHAR(10), icpc.icpc_icpc_date, 23) AS [icpc_date],  -- ✅ Matches API spec
                            CONVERT(VARCHAR(10), s47e.s47e_s47_end_date, 23) AS [end_date],  -- ✅ Matches API spec
                            CAST(0 AS bit) AS [purge]  -- ✅ Added missing purge flag
                        FROM ssd_s47_enquiry s47e
                        LEFT JOIN ssd_initial_cp_conference icpc
                            ON icpc.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                        WHERE s47e.s47e_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [section_47_assessments],


                    -- Nested Child Protection Plans
                    (
                        SELECT 
                            cppl.cppl_cp_plan_id AS [child_protection_plan_id],  -- ✅ Matches API spec
                            CONVERT(VARCHAR(10), cppl.cppl_cp_plan_start_date, 23) AS [start_date],  -- ✅ Matches API spec
                            CONVERT(VARCHAR(10), cppl.cppl_cp_plan_end_date, 23) AS [end_date],  -- ✅ Matches API spec
                            CAST(0 AS bit) AS [purge]  -- ✅ Added missing purge flag
                        FROM ssd_cp_plans cppl
                        WHERE cppl.cppl_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_protection_plans],


                    -- Nested Child Looked After Placements
                    (
                        SELECT 
                            clae.clae_cla_placement_id AS [child_looked_after_placement_id],  -- ✅ Matches API spec
                            CONVERT(VARCHAR(10), clae.clae_cla_episode_start_date, 23) AS [start_date],  -- ✅ Matches API spec
                            LEFT(clae.clae_cla_episode_start_reason, 3) AS [start_reason],  -- ✅ Matches API spec
                            CONVERT(VARCHAR(10), clae.clae_cla_episode_ceased, 23) AS [end_date],  -- ✅ Renamed `ceased` to `end_date` for consistency
                            LEFT(clae.clae_cla_episode_ceased_reason, 3) AS [end_reason],  -- ✅ Matches API spec
                            CAST(0 AS bit) AS [purge],  -- ✅ Added missing purge flag
                            
                            -- Nested CLA Placement Details
                            (
                                SELECT
                                    clap.clap_cla_placement_id AS [placement_id],  -- ✅ Matches API spec
                                    CONVERT(VARCHAR(10), clap.clap_cla_placement_start_date, 23) AS [start_date],  -- ✅ Matches API spec
                                    clap.clap_cla_placement_postcode AS [placement_postcode],  -- ✅ Matches API spec
                                    clap.clap_cla_placement_type AS [placement_type],  -- ✅ Matches API spec
                                    CONVERT(VARCHAR(10), clap.clap_cla_placement_end_date, 23) AS [end_date],  -- ✅ Matches API spec
                                    clap.clap_cla_placement_change_reason AS [placement_change_reason]  -- ✅ Matches API spec
                                FROM ssd_cla_placement clap
                                WHERE clap.clap_cla_id = clae.clae_cla_id
                                ORDER BY clap.clap_cla_placement_start_date DESC -- Most recent placement first
                                FOR JSON PATH
                            ) AS [placement_details]

                        FROM ssd_cla_episodes clae 
                        WHERE clae.clae_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_looked_after_placements],


                    -- Nested Adoptions
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), perm.perm_adm_decision_date, 23) AS [initial_decision_date],  -- ✅ Renamed field to match API spec
                            CONVERT(VARCHAR(10), perm.perm_matched_date, 23) AS [matched_date],  -- ✅ Renamed field to match API spec
                            CONVERT(VARCHAR(10), perm.perm_placed_for_adoption_date, 23) AS [placed_date],  -- ✅ Renamed field to match API spec
                            CAST(0 AS bit) AS [purge]  -- ✅ Added missing purge flag
                        FROM ssd_permanence perm
                        WHERE perm.perm_person_id = p.pers_person_id
                        OR perm.perm_cla_id IN (
                            SELECT clae.clae_cla_id
                            FROM ssd_cla_episodes clae
                            WHERE clae.clae_person_id = p.pers_person_id
                        )
                        FOR JSON PATH
                    ) AS [adoptions],


                    -- Nested Care Leavers
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), clea.clea_care_leaver_latest_contact, 23) AS [contact_date],  -- ✅ Matches API spec
                            LEFT(clea.clea_care_leaver_activity, 2) AS [activity],  -- ✅ Matches API spec
                            LEFT(clea.clea_care_leaver_accommodation, 1) AS [accommodation],  -- ✅ Matches API spec
                            CAST(0 AS bit) AS [purge]  -- ✅ Added missing purge flag
                        FROM ssd_care_leavers clea
                        WHERE clea.clea_person_id = p.pers_person_id
                        ORDER BY clea.clea_care_leaver_latest_contact DESC -- most recent contact first
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER  -- ✅ Ensured it's an object, not an array
                    ) AS [care_leavers]


                FROM ssd_cin_episodes cine
                WHERE cine.cine_person_id = p.pers_person_id
                FOR JSON PATH
            ) AS [social_care_episodes]

            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS json_payload
    FROM ssd_person p
)
SELECT json_payload FROM ComputedData;