-- Update All addr_address_end_date NULL Values to Current Date

UPDATE [HDM_Local].[ssd_development].[ssd_address]
SET addr_address_end_date = GETDATE()
WHERE addr_address_end_date IS NULL;


-- Update 30% of Rows with addr_address_type = 'MAIN' to 'PREV'
UPDATE [HDM_Local].[ssd_development].[ssd_address]
SET addr_address_type = 'PREV'
WHERE addr_table_id IN (
    SELECT TOP (30) PERCENT addr_table_id
    FROM [HDM_Local].[ssd_development].[ssd_address]
    WHERE addr_address_type = 'MAIN'
    ORDER BY NEWID()
);


-- Add a New disa_disability_code for 50% of People (Ensuring No Duplicate)
--- need to make structure changes to make this work with current data
-- Drop the existing primary key constraint (if necessary)
ALTER TABLE [HDM_Local].[ssd_development].[ssd_disability] DROP CONSTRAINT PK__ssd_disa__380F73DAA780F4DE;

-- Alter the column to be an auto-incrementing identity
ALTER TABLE [HDM_Local].[ssd_development].[ssd_disability] 
DROP COLUMN disa_table_id;

-- Re-add the column as an identity column
ALTER TABLE [HDM_Local].[ssd_development].[ssd_disability]
ADD disa_table_id INT IDENTITY(1,1) PRIMARY KEY;


WITH SelectedPersons AS (
    -- Select 50% of unique disa_person_id values randomly
    SELECT disa_person_id
    FROM (
        SELECT DISTINCT disa_person_id, ROW_NUMBER() OVER (ORDER BY NEWID()) AS rownum
        FROM [HDM_Local].[ssd_development].[ssd_disability]
        WHERE disa_person_id IS NOT NULL
    ) AS sub
    WHERE rownum <= (SELECT COUNT(DISTINCT disa_person_id) / 2 FROM [HDM_Local].[ssd_development].[ssd_disability])
)
INSERT INTO [HDM_Local].[ssd_development].[ssd_disability] (disa_person_id, disa_disability_code)
SELECT 
    sp.disa_person_id, 
    (SELECT TOP 1 value 
     FROM (VALUES ('NONE'), ('MOB'), ('HAND'), ('PC'), ('INC'), ('COMM'), ('LD'), ('HEAR'), ('VIS'), ('BEH'), ('CON'), ('AUT'), ('DDA')) 
     AS v(value) 
     WHERE v.value NOT IN (
        SELECT disa_disability_code 
        FROM [HDM_Local].[ssd_development].[ssd_disability] d2 
        WHERE d2.disa_person_id = sp.disa_person_id
     ) ORDER BY NEWID()) AS disa_disability_code
FROM SelectedPersons sp;




-- Update clav_cla_visit_seen from NULL to 'Y'
UPDATE [HDM_Local].[ssd_development].[ssd_cla_visits]
SET clav_cla_visit_seen = 'Y'
WHERE clav_cla_visit_seen IS NULL;


-- Update clai_immunisations_status = 'Y' Where It’s N, and Set a New Date
UPDATE [HDM_Local].[ssd_development].[ssd_cla_immunisations]
SET clai_immunisations_status = 'Y',
    clai_immunisations_status_date = GETDATE()
WHERE clai_immunisations_status = 'N';


-- Update 50% of NULL addr_address_end_date Values to Current Date
UPDATE [HDM_Local].[ssd_development].[ssd_address]
SET addr_address_end_date = GETDATE()
WHERE addr_table_id IN (
    SELECT TOP (50) PERCENT addr_table_id
    FROM [HDM_Local].[ssd_development].[ssd_address]
    WHERE addr_address_end_date IS NULL
    ORDER BY NEWID()
);





-- 1
-- NOW RUN MERGE ON SSD_API_DATA_STAGING to pick up changes



-- 2
-- NOW RUN

-- FIX the testing environment after subsequent changes on SSD have been brought through as part of testing. 
UPDATE ssd_api_data_staging
            SET submission_status = 'sent', -- Status: Pending, Sent, Error
                api_response = 'Simulated API Call'
            WHERE row_state = 'unchanged'; -- new, updated, deleted, unchanged



UPDATE ssd_api_data_staging_anon
            SET submission_status = 'sent', -- Status: Pending, Sent, Error
                api_response = 'Simulated API Call'
            WHERE row_state = 'unchanged'; -- new, updated, deleted, unchanged



-- Update 30% of Rows to become DEleted status
UPDATE [HDM_Local].[ssd_development].[ssd_api_data_staging_anon]
SET submission_status = 'pending', api_response = NULL, row_state = 'deleted'
WHERE row_state IN (
    SELECT TOP (30) PERCENT row_state
    FROM [HDM_Local].[ssd_development].[ssd_api_data_staging_anon]
    WHERE row_state = 'unchanged'
);
-- -- OR DELETE at source:
-- WITH PersonsToDelete AS (
--     SELECT person_id
--     FROM (
--         SELECT person_id, ROW_NUMBER() OVER (ORDER BY NEWID()) AS rownum
--         FROM ssd_person
--     ) AS sub
--     WHERE rownum <= (SELECT COUNT(*) * 0.2 FROM ssd_person) -- 20% of total records
-- )
-- DELETE FROM ssd_person
-- WHERE person_id IN (SELECT person_id FROM PersonsToDelete);




-- Reduce test data down to v.small number of records for testing
DECLARE @KeepRows INT = 2;

WITH DistinctRowStates AS (
    SELECT DISTINCT row_state 
    FROM ssd_api_data_staging -- Get unique row_state vals
),
RowsToDelete AS (
    SELECT id, row_state, 
           ROW_NUMBER() OVER (PARTITION BY row_state ORDER BY NEWID()) AS rn
    FROM ssd_api_data_staging
    WHERE row_state IN (SELECT row_state FROM DistinctRowStates) -- Ensure only known row_state values are considered
)
DELETE FROM ssd_api_data_staging
WHERE id IN (
    SELECT id FROM RowsToDelete WHERE rn > @KeepRows -- Delete excess rows
);




select * from ssd_api_data_staging_anon;
select * from ssd_api_data_staging_anon where submission_status != 'sent' and row_state != 'deleted';
