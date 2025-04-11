

-- Create API DfE table for API payload and logging

IF OBJECT_ID('ssd_dfe_api_data_collection', 'U') IS NOT NULL DROP TABLE ssd_dfe_api_data_collection;

CREATE TABLE ssd_dfe_api_data_collection (
    id INT IDENTITY(1,1) PRIMARY KEY, -- Unique identifier for each JSON entry
    json_payload NVARCHAR(MAX) NOT NULL, -- The JSON data from your query
    submission_status NVARCHAR(50) DEFAULT 'Pending', -- Status: Pending, Sent, Error
    submission_timestamp DATETIME DEFAULT GETDATE(), -- Timestamp of data insertion
    api_response NVARCHAR(MAX) NULL -- Store the API response or error messages
);

-- sample rows into the table

-- 'Pending' status
INSERT INTO ssd_dfe_api_data_collection (json_payload, submission_status)
VALUES (
    '{
        "LA_Child_ID_id": 1,
        "common_person_id": "C12345",
        "FirstName": "SSD_PH",
        "Surname": "SSD_PH",
        "UPN": "UPN123456",
        "Former_UPN": "UPN54321",
        "UPN_Unknown": false,
        "Date_of_Birth": "2010-05-15",
        "Expected_Date_of_Birth": null,
        "Sex": "M",
        "Ethnicity": "White",
        "Disabilities": [{"Disability": "D001"}],
        "Postcode": "BN12 4AX",
        "UASC": "Yes",
        "UASC_End_Date": "2023-12-31",
        "SDQ_Scores": [{"SDQ_Completed_Date": "2023-01-15", "SDQ_Score": 15}],
        "EHCP": {
            "EHCP_Request_Date": "2023-02-01",
            "Assessment": {
                "EHCP_Assessment_Outcome_Date": "2023-03-01",
                "EHCP_Assessment_Outcome": "Approved",
                "Named_Plan": [{"Named_Plan_Start_Date": "2023-04-01"}]
            }
        },
        "CIN_Episodes": [{
            "Referral_Date": "2022-12-01",
            "Source_of_Referral": "Social Worker",
            "Closure_Date": "2023-06-01",
            "Reason_for_Closure": "Resolved",
            "CP_Plans": [{"Plan_Start_Date": "2022-12-15", "Plan_End_Date": "2023-05-31"}]
        }]
    }',
    'Pending'
);

-- 'Sent' status
INSERT INTO ssd_dfe_api_data_collection (json_payload, submission_status, api_response)
VALUES (
    '{
        "LA_Child_ID_id": 2,
        "common_person_id": "C67890",
        "FirstName": "SSD_PH",
        "Surname": "SSD_PH",
        "UPN": "UPN987654",
        "Former_UPN": null,
        "UPN_Unknown": false,
        "Date_of_Birth": "2012-11-22",
        "Expected_Date_of_Birth": null,
        "Sex": "F",
        "Ethnicity": "Asian",
        "Disabilities": [],
        "Postcode": "BN13 8XR",
        "UASC": null,
        "UASC_End_Date": null,
        "SDQ_Scores": [],
        "EHCP": null,
        "CIN_Episodes": [{
            "Referral_Date": "2023-06-15",
            "Source_of_Referral": "Police",
            "Closure_Date": null,
            "Reason_for_Closure": null,
            "CP_Plans": []
        }]
    }',
    'Sent',
    'API response: {"status": "success", "message": "Data submitted successfully"}'
);

-- 'Error' status
INSERT INTO ssd_dfe_api_data_collection (json_payload, submission_status, api_response)
VALUES (
    '{
        "LA_Child_ID_id": 3,
        "common_person_id": "C54321",
        "FirstName": "SSD_PH",
        "Surname": "SSD_PH",
        "UPN": "UPN543210",
        "Former_UPN": null,
        "UPN_Unknown": true,
        "Date_of_Birth": "2008-03-10",
        "Expected_Date_of_Birth": null,
        "Sex": "U",
        "Ethnicity": "Mixed",
        "Disabilities": [{"Disability": "D002"}, {"Disability": "D003"}],
        "Postcode": "BN14 7GH",
        "UASC": "No",
        "UASC_End_Date": null,
        "SDQ_Scores": [{"SDQ_Completed_Date": "2023-03-05", "SDQ_Score": 12}],
        "EHCP": null,
        "CIN_Episodes": null
    }',
    'Error',
    'API response: {"status": "error", "message": "Invalid UPN format"}'
);


--------------------



-- -- Example of live data going into table 

-- INSERT INTO ssd_dfe_api_data_collection (json_payload)
-- SELECT 
-- (
--     SELECT 
--         p.pers_person_id AS [LA_Child_ID_id],
--         p.pers_common_child_id AS [common_person_id],
--         'SSD_PH' AS [FirstName],
--         'SSD_PH' AS [Surname],
--         (
--             SELECT TOP 1 link_identifier_value
--             FROM ssd_linked_identifiers
--             WHERE link_person_id = p.pers_person_id 
--               AND link_identifier_type = 'Unique Pupil Number'
--             ORDER BY link_valid_from_date DESC
--         ) AS [UPN],
--         (
--             SELECT TOP 1 link_identifier_value
--             FROM ssd_linked_identifiers
--             WHERE link_person_id = p.pers_person_id 
--               AND link_identifier_type = 'Former Unique Pupil Number'
--             ORDER BY link_valid_from_date DESC
--         ) AS [Former_UPN],
--         p.pers_upn_unknown AS [UPN_Unknown],
--         CONVERT(VARCHAR(10), p.pers_dob, 23) AS [Date_of_Birth],
--         CONVERT(VARCHAR(10), p.pers_expected_dob, 23) AS [Expected_Date_of_Birth],
--         CASE 
--             WHEN p.pers_sex = 'M' THEN 'M'
--             WHEN p.pers_sex = 'F' THEN 'F'
--             ELSE 'U'
--         END AS [Sex],
--         p.pers_ethnicity AS [Ethnicity],
--         (
--             SELECT 
--                 d.disa_disability_code AS [Disability]
--             FROM ssd_disability d
--             WHERE d.disa_person_id = p.pers_person_id
--             FOR JSON PATH
--         ) AS [Disabilities],
--         (
--             SELECT TOP 1 a.addr_address_postcode
--             FROM ssd_address a
--             WHERE a.addr_person_id = p.pers_person_id
--             ORDER BY a.addr_address_start_date DESC
--         ) AS [Postcode],
--         (
--             SELECT TOP 1 immi.immi_immigration_status
--             FROM ssd_immigration_status immi
--             WHERE immi.immi_person_id = p.pers_person_id
--             ORDER BY 
--                 CASE 
--                     WHEN immi.immi_immigration_status_end_date IS NULL THEN 1 
--                     ELSE 0 
--                 END,
--                 immi.immi_immigration_status_start_date DESC
--         ) AS [UASC]
--     FROM ssd_person p
--     FOR JSON PATH, ROOT('Children')
-- ) AS json_payload;


select * from ssd_dfe_api_data_collection;