SELECT 
    (
        SELECT 
            p.pers_person_id AS [la_child_id],
            NULL AS [mis_child_id],
            0 AS [purge], -- Default value
            (
                SELECT 
                    (
                        SELECT TOP 1 link_identifier_value
                        FROM ssd_linked_identifiers
                        WHERE link_person_id = p.pers_person_id 
                        AND link_identifier_type = 'Unique Pupil Number'
                        ORDER BY link_valid_from_date DESC
                    ) AS [unique_pupil_number],
                    p.pers_upn_unknown AS [unique_pupil_number_unknown_reason],
                    'SSD_PH' AS [first_name],
                    'SSD_PH' AS [surname],
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
                            '[' + STRING_AGG('"' + d.disa_disability_code + '"', ',') WITHIN GROUP (ORDER BY d.disa_disability_code) + ']'
                        FROM ssd_disability d
                        WHERE d.disa_person_id = p.pers_person_id
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
                    ) AS [uasc_end_date]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS json_payload
FROM ssd_person p;
