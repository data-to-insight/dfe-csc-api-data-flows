
IF OBJECT_ID('ssd_api_data_staging', 'U') IS NOT NULL DROP TABLE ssd_api_data_staging;

CREATE TABLE ssd_api_data_staging (
    id INT IDENTITY(1,1) PRIMARY KEY,           
    person_id NVARCHAR(48) NULL,                        -- Link value (_person_id or equivalent)
    json_payload NVARCHAR(MAX) NOT NULL,                -- JSON data payload
    current_hash BINARY(32) NULL,                       -- Current hash of JSON payload
    previous_hash BINARY(32) NULL,                      -- Previous hash of JSON payload
    submission_status NVARCHAR(50) DEFAULT 'Pending',   -- Status: Pending, Sent, Error
    submission_timestamp DATETIME DEFAULT GETDATE(),    -- Timestamp of data insertion
    api_response NVARCHAR(MAX) NULL,                    -- API response or error messages
    row_state NVARCHAR(10) DEFAULT 'new',               -- Record state: new, updated, deleted, unchanged
    last_updated DATETIME DEFAULT GETDATE()             -- Last update timestamp
);

INSERT INTO ssd_api_data_staging (person_id, json_payload)
SELECT 
    p.pers_person_id AS person_id,
    (
        SELECT 
        -- Attribute Group: Children
            p.pers_person_id AS [la_child_id], -- metadata={2 ,PERS001A, True, Up to 36 Characters allowed|CHILD12345}  
            -- p.pers_common_child_id AS [common_person_id],
            'SSD_PH' AS [first_name], -- metadata={6, Up to 128 characters} 
            'SSD_PH' AS [surname], -- metadata={7, Up to 128 characters} 
            (
                SELECT TOP 1 link_identifier_value
                FROM ssd_linked_identifiers
                WHERE link_person_id = p.pers_person_id 
                  AND link_identifier_type = 'Unique Pupil Number'
                ORDER BY link_valid_from_date DESC
            ) AS [unique_pupil_number], -- metadata={3, } 
            (
                SELECT TOP 1 link_identifier_value
                FROM ssd_linked_identifiers
                WHERE link_person_id = p.pers_person_id 
                  AND link_identifier_type = 'Former Unique Pupil Number'
                ORDER BY link_valid_from_date DESC
            ) AS [former_unique_pupil_number], -- metadata={4, } 
            p.pers_upn_unknown AS [unique_pupil_number_unknown_reason], -- metadata={5,} 
            CONVERT(VARCHAR(10), p.pers_dob, 23) AS [date_of_birth], -- metadata={} 
            CONVERT(VARCHAR(10), p.pers_expected_dob, 23) AS [expected_date_of_birth], -- metadata={} 
            CASE 
                WHEN p.pers_sex = 'M' THEN 'M'
                WHEN p.pers_sex = 'F' THEN 'F'
                ELSE 'U'
            END AS [sex], -- metadata={} 
            p.pers_ethnicity AS [ethnicity], -- metadata={} 
            (
                SELECT 
                    '[' + STRING_AGG('"' + d.disa_disability_code + '"', ',') + ']' -- metadata={} 
                FROM ssd_disability d
                WHERE d.disa_person_id = p.pers_person_id
            ) AS [disabilities] -- metadata={12 ,DISA002A, False, See Additional Notes for list of possible Options|[HAND, VIS]}  
            (
                SELECT TOP 1 a.addr_address_postcode
                FROM ssd_address a
                WHERE a.addr_person_id = p.pers_person_id
                ORDER BY a.addr_address_start_date DESC
            ) AS [Postcode], -- metadata={} 
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
            ) AS [UASC], -- metadata={} 
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
            ) AS [child_details.uasc_end_date], -- metadata={} 

            -- Attribute Group: Social Care Episodes
            -- Social Care Episodes/CIN Episodes
            (
                SELECT  
                    cine.cine_referral_id AS [social_care_episode_id], -- metadata={} 
                    CONVERT(VARCHAR(10), cine.cine_referral_date, 23) AS [referral_date], -- metadata={} 
                    cine.cine_referral_source_code AS [referral_source], -- metadata={} 
                    CONVERT(VARCHAR(10), cine.cine_close_date, 23) AS [closure_date], -- metadata={} 
                    cine.cine_close_reason AS [closure_reason], -- metadata={} 
                    cine.cine_referral_nfa AS [referral_no_further_action_flag], -- metadata={} 

                    -- Attribute Group: Children and Families Assessment
                    -- Nested Child and Family Assessments
                    (
                        SELECT 
                            ca.cina_assessment_id AS [child_and_family_assessment_id], -- metadata={} 
                            CONVERT(VARCHAR(10), ca.cina_assessment_start_date, 23) AS [start_date], -- metadata={} 
                            CONVERT(VARCHAR(10), ca.cina_assessment_auth_date, 23) AS [authorisation_date], -- metadata={} 
                            CASE 
                                WHEN af.cinf_assessment_factors_json IS NULL OR af.cinf_assessment_factors_json = '' THEN '[]'
                                ELSE af.cinf_assessment_factors_json
                            END AS [assessment_factors] -- metadata={}
                        FROM ssd_cin_assessments ca
                        LEFT JOIN ssd_assessment_factors af
                            ON af.cinf_assessment_id = ca.cina_assessment_id
                        WHERE ca.cina_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_and_family_assessments], -- metadata={}

                    -- Attribute Group: Child Protection Plans
                    -- Nested CP Plans
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), cppl.cppl_cp_plan_start_date, 23) AS [start_date], -- metadata={}
                            CONVERT(VARCHAR(10), cppl.cppl_cp_plan_end_date, 23) AS [end_date] -- metadata={}
                        FROM ssd_cp_plans cppl
                        WHERE cppl.cppl_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_protection_plans], -- metadata={}

                    -- Attribute Group: Child Look After
                    -- Nested CLA Episodes
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), clae.clae_cla_episode_start_date, 23) AS [start_date], -- metadata={}
                            clae.clae_cla_episode_start_reason AS [start_reason], -- metadata={}
                            clae.clae_cla_episode_ceased AS [ceased], -- metadata={}
                            clae.clae_cla_episode_ceased_reason AS [ceased_reason], -- metadata={}

                            -- Nested CLA Placement
                            (
                                SELECT 
                                    clap.clap_cla_placement_postcode AS [placement_postcode], -- metadata={}
                                    clap.clap_cla_placement_type AS [placement_type], -- metadata={}
                                    clap.clap_cla_placement_change_reason AS [placement_change_reason] -- metadata={}
                                FROM ssd_cla_placement clap
                                WHERE clap.clap_cla_id = clae.clae_cla_id
                                FOR JSON PATH
                            ) AS [placement_details] -- metadata={}
                        FROM ssd_cla_episodes clae -- metadata={}
                        WHERE clae.clae_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_looked_after_placements], -- metadata={}

                    -- Attribute Group: Child in Need Plans
                    -- Nested CIN Plans
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), cinp.cinp_cin_plan_start_date, 23) AS [start_date], -- metadata={}
                            CONVERT(VARCHAR(10), cinp.cinp_cin_plan_end_date, 23) AS [end_date] -- metadata={}
                        FROM ssd_cin_plans cinp
                        WHERE cinp.cinp_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [child_in_need_plans], -- metadata={}

                    -- Attribute Group: S47 Assessments
                    -- Nested S47 Enquiries
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), s47e.s47e_s47_start_date, 23) AS [start_date], -- metadata={}
                            CONVERT(VARCHAR(10), s47e.s47e_s47_end_date, 23) AS [end_date] -- metadata={}
                        FROM ssd_s47_enquiry s47e
                        WHERE s47e.s47e_referral_id = cine.cine_referral_id
                        FOR JSON PATH
                    ) AS [section_47_assessments], -- metadata={}

                    -- Attribute Group: Health and Wellbeing
                    -- Nested Health and Wellbeing
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), csdq.csdq_sdq_completed_date, 23) AS [sdq_date], -- metadata={}
                            csdq.csdq_sdq_score AS [sdq_score] -- metadata={}
                        FROM ssd_sdq_scores csdq
                        WHERE csdq.csdq_person_id = p.pers_person_id
                        FOR JSON PATH
                    ) AS [health_and_wellbeing], -- metadata={}

                    -- Attribute Group: Adoptions
                    -- Nested Adoptions
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), perm.perm_adm_decision_date, 23) AS [date_initial_decision], -- metadata={}
                            CONVERT(VARCHAR(10), perm.perm_matched_date, 23) AS [date_match], -- metadata={}
                            CONVERT(VARCHAR(10), perm.perm_placed_for_adoption_date, 23) AS [date_placed] -- metadata={}
                        FROM ssd_permanence perm
                        WHERE perm.perm_person_id = p.pers_person_id
                        OR perm.perm_cla_id IN (
                            SELECT clae.clae_cla_id
                            FROM ssd_cla_episodes clae
                            WHERE clae.clae_person_id = p.pers_person_id
                        )
                        FOR JSON PATH
                    ) AS [adoptions], -- metadata={}

                    -- Attribute Group: Care Leavers
                    -- Nested Care Leavers
                    (
                        SELECT 
                            CONVERT(VARCHAR(10), clea.clea_care_leaver_latest_contact, 23) AS [contact_date], -- metadata={}
                            clea.clea_care_leaver_activity AS [activity], -- metadata={}
                            clea.clea_care_leaver_accommodation AS [accommodation] -- metadata={}
                        FROM ssd_care_leavers clea
                        WHERE clea.clea_person_id = p.pers_person_id
                        FOR JSON PATH
                    ) AS [care_leavers] -- metadata={}


                FROM ssd_cin_episodes cine
                WHERE cine.cine_person_id = p.pers_person_id
                FOR JSON PATH
            ) AS [social_care_episodes], -- metadata={}


            -- Attribute Group: Educational Health and Care Plans
            -- Education Health Care Plans
            (
                SELECT 
                    ehcn.ehcn_named_plan_id AS [education_health_care_plan_id],
                    CONVERT(VARCHAR(10), ehcr.ehcr_ehcp_req_date, 23) AS [request_received_date],
                    CONVERT(VARCHAR(10), ehcr.ehcr_ehcp_req_outcome_date, 23) AS [request_outcome_date],
                    CONVERT(VARCHAR(10), ehca.ehca_ehcp_assessment_outcome_date, 23) AS [assessment_outcome_date],
                    CONVERT(VARCHAR(10), ehcn.ehcn_named_plan_start_date, 23) AS [plan_start_date]
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


            -- Attribute Group: Social Care Workers
            -- Social/Case Workers 
            (
                SELECT 
                    pr.prof_staff_id AS [worker_id], -- metadata={}
                    CONVERT(VARCHAR(10), i.invo_involvement_start_date, 23) AS [worker_start_date], -- metadata={}
                    CASE 
                        WHEN i.invo_involvement_end_date IS NULL THEN NULL
                        ELSE CONVERT(VARCHAR(10), i.invo_involvement_end_date, 23)
                    END AS [worker_end_date] -- metadata={}
                FROM ssd_involvements i
                INNER JOIN ssd_professionals pr 
                    ON i.invo_professional_id = pr.prof_professional_id
                WHERE i.invo_person_id = p.pers_person_id
                FOR JSON PATH
            ) AS [social_workers] -- metadata={}
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS json_payload
FROM ssd_person p;


select * from ssd_api_data_staging;
-- where json_payload like '%child_protection_plans%'
-- AND json_payload like '%section_47_assessments%'
-- WHERE json_payload like '%child_in_need_plans%'
-- AND json_payload like '%cla_episodes%';
-- WHERE json_payload like '%education_health_care_plans%';