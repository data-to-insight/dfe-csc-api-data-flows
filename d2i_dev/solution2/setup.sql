-- combined prev hash table and json payload collection table into one. 
-- uses hashes on payload table instead of two split tables as per solution 1

IF OBJECT_ID('ssd_api_data_staging', 'U') IS NOT NULL DROP TABLE ssd_api_data_staging;

CREATE TABLE ssd_api_data_staging (
    id INT IDENTITY(1,1) PRIMARY KEY,           
    person_id NVARCHAR(48) NULL,               -- link value (_person_id)
    json_payload NVARCHAR(MAX) NOT NULL,      
    current_hash BINARY(32) NULL,              -- current hash of JSON payload
    previous_hash BINARY(32) NULL,             -- previous hash of JSON payload
    submission_status NVARCHAR(50) DEFAULT 'Pending', -- Status: Pending, Sent, Error
    submission_timestamp DATETIME DEFAULT GETDATE(),  -- data submitted timestamp
    api_response NVARCHAR(MAX) NULL,          -- API response or error
    row_state NVARCHAR(10) DEFAULT 'New',     -- record state : New, Updated, Deleted, Unchanged
    last_updated DATETIME DEFAULT GETDATE()   -- timestamp data update/insertion
);

INSERT INTO ssd_api_data_staging (person_id, json_payload, current_hash)
SELECT 
    p.pers_person_id AS person_id,
    -- Generate JSON Payload
    (
        SELECT 
            p.pers_person_id AS [LA_Child_id],
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
            ) AS [UASC]
        FOR JSON PATH, ROOT('Children')
    ) AS json_payload,
    -- Calculate Current Hash
    HASHBYTES('SHA2_256', 
        CAST((
            SELECT 
                p.pers_person_id AS [LA_Child_id],
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
                ) AS [UASC]
            FOR JSON PATH
        ) AS NVARCHAR(MAX))
    ) AS current_hash
FROM ssd_person p;



-- -- only once at initialisation
-- UPDATE ssd_api_data_staging
-- SET previous_hash = current_hash;


-- only once at initialisation
UPDATE ssd_api_data_staging
SET submission_status = 'Pending'
WHERE person_id in (100006, 100009, 100014, 100097);


select * from ssd_api_data_staging;



-- -- only after 
-- --- transition to deltas

-- -- Recalculate hashes for existing records
-- UPDATE ssd_api_data_staging
-- SET 
--     current_hash = HASHBYTES('SHA2_256', json_payload),
--     row_state = CASE 
--         WHEN current_hash <> previous_hash THEN 'updated'
--         ELSE 'unchanged'
--     END,
--     last_updated = GETDATE();


-- -- Identify new rows (not in ssd_api_data_staging)
-- INSERT INTO ssd_api_data_staging (person_id, json_payload, current_hash)
-- SELECT 
--     p.pers_person_id AS person_id,
--     (
--         SELECT 
--             p.pers_person_id AS [LA_Child_ID_id],
--             p.pers_common_child_id AS [common_person_id],
--             'SSD_PH' AS [FirstName],
--             'SSD_PH' AS [Surname],
--             -- Add all other fields here
--             FOR JSON PATH, ROOT('Children')
--     ) AS json_payload,
--     HASHBYTES('SHA2_256', 
--         CAST((
--             SELECT 
--                 p.pers_person_id AS [LA_Child_ID_id],
--                 p.pers_common_child_id AS [common_person_id],
--                 'SSD_PH' AS [FirstName],
--                 'SSD_PH' AS [Surname],
--                 -- Add all other fields here
--                 FOR JSON PATH
--         ) AS NVARCHAR(MAX))
--     ) AS current_hash
-- FROM ssd_person p
-- WHERE NOT EXISTS (
--     SELECT 1 
--     FROM ssd_api_data_staging s 
--     WHERE s.person_id = p.pers_person_id
-- );



