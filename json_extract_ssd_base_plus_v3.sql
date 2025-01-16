SELECT 
    NULL AS [local_authority_code], -- Placeholder for local_authority_code (not present in the data)
    p.pers_person_id AS [la_child_id],
    (
        SELECT TOP 1 link_identifier_value
        FROM ssd_linked_identifiers
        WHERE link_person_id = p.pers_person_id 
          AND link_identifier_type = 'Unique Pupil Number'
        ORDER BY link_valid_from_date DESC
    ) AS [child_details.unique_pupil_number],
    (
        SELECT TOP 1 link_identifier_value
        FROM ssd_linked_identifiers
        WHERE link_person_id = p.pers_person_id 
          AND link_identifier_type = 'Former Unique Pupil Number'
        ORDER BY link_valid_from_date DESC
    ) AS [child_details.former_unique_pupil_number],
    p.pers_upn_unknown AS [child_details.unique_pupil_number_unknown_reason],
    'SSD_PH' AS [child_details.first_name],
    'SSD_PH' AS [child_details.surname],
    CONVERT(VARCHAR(10), p.pers_dob, 23) AS [child_details.date_of_birth],
    CONVERT(VARCHAR(10), p.pers_expected_dob, 23) AS [child_details.expected_date_of_birth],
    CASE 
        WHEN p.pers_sex = 'M' THEN 'M'
        WHEN p.pers_sex = 'F' THEN 'F'
        ELSE 'U'
    END AS [child_details.sex],
    p.pers_ethnicity AS [child_details.ethnicity],
    (
        SELECT 
            '[' + STRING_AGG('"' + d.disa_disability_code + '"', ',') WITHIN GROUP (ORDER BY d.disa_disability_code) + ']'
        FROM ssd_disability d
        WHERE d.disa_person_id = p.pers_person_id
    ) AS [child_details.disabilities],
    (
        SELECT TOP 1 a.addr_address_postcode
        FROM ssd_address a
        WHERE a.addr_person_id = p.pers_person_id
        ORDER BY a.addr_address_start_date DESC
    ) AS [child_details.postcode],
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
    ) AS [child_details.uasc_flag],
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
    -- Social Care Episodes/CIN Episodes
    (
        SELECT 
            cine.cine_referral_id AS [social_care_episodes.social_care_episode_id],
            CONVERT(VARCHAR(10), cine.cine_referral_date, 23) AS [social_care_episodes.referral_date],
            cine.cine_referral_source_code AS [social_care_episodes.referral_source],
            CONVERT(VARCHAR(10), cine.cine_close_date, 23) AS [social_care_episodes.closure_date],
            cine.cine_close_reason AS [social_care_episodes.closure_reason],
            -- Nested CP Plans
            (
                SELECT 
                    cppl.cppl_cp_plan_start_date AS [social_care_episodes.child_protection_plans.start_date],
                    cppl.cppl_cp_plan_end_date AS [social_care_episodes.child_protection_plans.end_date]
                FROM ssd_cp_plans cppl
                WHERE cppl.cppl_referral_id = cine.cine_referral_id
                FOR JSON PATH
            ) AS [social_care_episodes.child_protection_plans],
            -- Nested CIN Plans
            (
                SELECT 
                    cinp.cinp_cin_plan_start_date AS [social_care_episodes.child_in_need_plans.start_date],
                    cinp.cinp_cin_plan_end_date AS [social_care_episodes.child_in_need_plans.end_date]
                FROM ssd_cin_plans cinp
                WHERE cinp.cinp_referral_id = cine.cine_referral_id
                FOR JSON PATH
            ) AS [social_care_episodes.child_in_need_plans],
            -- Nested S47 Enquiries
            (
                SELECT 
                    s47e.s47e_s47_start_date AS [social_care_episodes.section_47_assessments.start_date],
                    s47e.s47e_s47_end_date AS [social_care_episodes.section_47_assessments.end_date]
                FROM ssd_s47_enquiry s47e
                WHERE s47e.s47e_referral_id = cine.cine_referral_id
                FOR JSON PATH
            ) AS [social_care_episodes.section_47_assessments]
        FROM ssd_cin_episodes cine
        WHERE cine.cine_person_id = p.pers_person_id
        FOR JSON PATH
    ) AS [social_care_episodes],
    -- Social Workers (moved to a separate block)
    (
        SELECT 
            pr.prof_staff_id AS [worker_id],
            CONVERT(VARCHAR(10), i.invo_involvement_start_date, 23) AS [worker_start_date],
            CASE 
                WHEN i.invo_involvement_end_date IS NULL THEN NULL
                ELSE CONVERT(VARCHAR(10), i.invo_involvement_end_date, 23)
            END AS [worker_end_date]
        FROM ssd_involvements i
        INNER JOIN ssd_professionals pr 
            ON i.invo_professional_id = pr.prof_professional_id
        WHERE i.invo_person_id = p.pers_person_id -- Changed from cine.cine_referral_id
        FOR JSON PATH
    ) AS [social_workers]

FROM ssd_person p
FOR JSON PATH, ROOT('Children');
