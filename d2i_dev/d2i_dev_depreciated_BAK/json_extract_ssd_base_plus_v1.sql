SELECT 
    p.pers_person_id AS [LA_Child_ID_id],
    p.pers_common_child_id AS [common_person_id],
    'SSD_PH' AS [FirstName],
    'SSD_PH' AS [Surname],
    (
        SELECT TOP 1 link_identifier_value
        FROM ssd_linked_identifiers
        WHERE link_person_id = p.pers_person_id 
          AND link_identifier_type = 'Unique Pupil Number'
        ORDER BY link_valid_from_date DESC
    ) AS [UPN],
    (
        SELECT TOP 1 link_identifier_value
        FROM ssd_linked_identifiers
        WHERE link_person_id = p.pers_person_id 
          AND link_identifier_type = 'Former Unique Pupil Number'
        ORDER BY link_valid_from_date DESC
    ) AS [Former_UPN],
    p.pers_upn_unknown AS [UPN_Unknown],
    CONVERT(VARCHAR(10), p.pers_dob, 23) AS [Date_of_Birth],
    CONVERT(VARCHAR(10), p.pers_expected_dob, 23) AS [Expected_Date_of_Birth],
    CASE 
        WHEN p.pers_sex = 'M' THEN 'M'
        WHEN p.pers_sex = 'F' THEN 'F'
        ELSE 'U'
    END AS [Sex],
    p.pers_ethnicity AS [Ethnicity],
    (
        SELECT 
            d.disa_disability_code AS [Disability]
        FROM ssd_disability d
        WHERE d.disa_person_id = p.pers_person_id
        FOR JSON PATH
    ) AS [Disabilities],
    (
        SELECT TOP 1 a.addr_address_postcode
        FROM ssd_address a
        WHERE a.addr_person_id = p.pers_person_id
        ORDER BY a.addr_address_start_date DESC
    ) AS [Postcode],
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
    ) AS [UASC],
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
    ) AS [UASC_End_Date],
    -- Nested CIN Episodes
    (
        SELECT 
            cine.cine_referral_date AS [Referral_Date],
            cine.cine_referral_source_code AS [Source_of_Referral],
            cine.cine_close_date AS [Closure_Date],
            cine.cine_close_reason AS [Reason_for_Closure],
            -- Nested CP Plans
            (
                SELECT 
                    cppl.cppl_cp_plan_start_date AS [Plan_Start_Date],
                    cppl.cppl_cp_plan_end_date AS [Plan_End_Date]
                FROM ssd_cp_plans cppl
                WHERE cppl.cppl_referral_id = cine.cine_referral_id
                FOR JSON PATH
            ) AS [CP_Plans],
            -- Nested CIN Plans
            (
                SELECT 
                    cinp.cinp_cin_plan_start_date AS [Plan_Start_Date],
                    cinp.cinp_cin_plan_end_date AS [Plan_End_Date]
                FROM ssd_cin_plans cinp
                WHERE cinp.cinp_referral_id = cine.cine_referral_id
                FOR JSON PATH
            ) AS [CIN_Plans],
            -- Nested S47 Enquiries
            (
                SELECT 
                    s47e.s47e_s47_start_date AS [Enquiry_Start_Date],
                    s47e.s47e_s47_end_date AS [Enquiry_End_Date]
                FROM ssd_s47_enquiry s47e
                WHERE s47e.s47e_referral_id = cine.cine_referral_id
                FOR JSON PATH
            ) AS [S47_Enquiries]
        FROM ssd_cin_episodes cine
        WHERE cine.cine_person_id = p.pers_person_id
        FOR JSON PATH
    ) AS [CIN_Episodes]

FROM ssd_person p
FOR JSON PATH, ROOT('Children');
