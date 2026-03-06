use hdm_local; 

DECLARE @TableName NVARCHAR(128) = N'table_name_placeholder'; -- Note: also/seperately use of @table_name in non-test|live elements of script. 
-- This is defined elsewhere, here for ref. 
DECLARE @ssd_timeframe_years INT = 6; -- ssd extract time-frame (YRS)

-- META-CONTAINER: {"type": "table", "name": "ssd_cohort"}
-- =============================================================================
-- Description: Test deployment to avoid EXISTS hits on ssd_person + enable source checks 
-- Author: D2I
-- Version: 1.0
--          
-- Status: [R]elease
-- Remarks:  Provides stable join pattern everywhere, shift from ssd_person
--          for WHERE EXISTS to reduce scan loads during ssd deployment. Provide 
--          flags for record(s) source visibility.   
-- Dependencies:

-- =============================================================================


-- META-ELEMENT: {"type": "test"}
SET @TableName = N'ssd_cohort';

-- -- Use-case: We're rolling this out to (new)ssd tables 
-- INNER JOIN ssd_development.ssd_cohort co
--   ON co.dim_person_id = TRY_CONVERT(nvarchar(48), p.DIM_PERSON_ID)
-- -- WHERE co.has_contact = 1 -- e.g. filter on 

-- -- Sanity check (date threshold == today’s date(midnight) - SSDyrs )
-- SELECT DATEADD(year, -@ssd_timeframe_years, CONVERT(datetime, CONVERT(date, GETDATE()))) AS current_cutoff_local;

SET NOCOUNT ON;

DECLARE @src_db     sysname = N'HDM';
DECLARE @src_schema sysname = N'Child_Social';


-- META-ELEMENT: {"type": "drop_table"}
IF OBJECT_ID('ssd_development.ssd_cohort') IS NOT NULL DROP TABLE ssd_development.ssd_cohort;
IF OBJECT_ID('ssd_cohort') IS NOT NULL DROP TABLE ssd_cohort;

IF OBJECT_ID('tempdb..#ssd_cohort') IS NOT NULL DROP TABLE #ssd_cohort;

-- META-ELEMENT: {"type": "create_table"}
IF OBJECT_ID('ssd_development.ssd_cohort','U') IS NULL
BEGIN
  CREATE TABLE ssd_development.ssd_cohort(
    dim_person_id         nvarchar(48)  NOT NULL PRIMARY KEY,
    legacy_id             nvarchar(48)  NULL,

    has_contact           bit           NOT NULL DEFAULT(0),
    has_referral          bit           NOT NULL DEFAULT(0),
    has_903               bit           NOT NULL DEFAULT(0),
    is_care_leaver        bit           NOT NULL DEFAULT(0),
    has_eligibility       bit           NOT NULL DEFAULT(0),
    has_client            bit           NOT NULL DEFAULT(0),
    has_involvement       bit           NOT NULL DEFAULT(0),

    first_activity_dttm   datetime      NULL,   -- min of contact/referral dates
    last_activity_dttm    datetime      NULL    -- max of contact/referral dates
  );
END
ELSE
BEGIN
  TRUNCATE TABLE ssd_development.ssd_cohort;
END;


/* Build the 3-part prefix once */
DECLARE @dbq  nvarchar(260) = QUOTENAME(@src_db);
DECLARE @scq  nvarchar(260) = QUOTENAME(@src_schema);
DECLARE @src3 nvarchar(600) = @dbq + N'.' + @scq + N'.';

/* Template with a placeholder for the 3-part name: __SRC__ */
DECLARE @tpl nvarchar(max) = N'
;WITH contacts AS (
  SELECT
    TRY_CONVERT(nvarchar(48), c.DIM_PERSON_ID) AS dim_person_id,
    MAX(TRY_CONVERT(datetime, c.CONTACT_DTTM)) AS last_contact_dttm,
    MIN(TRY_CONVERT(datetime, c.CONTACT_DTTM)) AS first_contact_dttm
  FROM __SRC__FACT_CONTACTS AS c
  WHERE (@ssd_timeframe_years IS NULL
         OR c.CONTACT_DTTM >= DATEADD(year, -@ssd_timeframe_years, CONVERT(datetime, CONVERT(date, GETDATE()))))
    AND c.DIM_PERSON_ID <> -1
  GROUP BY c.DIM_PERSON_ID
),
a903 AS (
  SELECT DISTINCT TRY_CONVERT(nvarchar(48), f.DIM_PERSON_ID) AS dim_person_id
  FROM __SRC__FACT_903_DATA AS f
  WHERE f.DIM_PERSON_ID <> -1
),
clients AS (
  SELECT TRY_CONVERT(nvarchar(48), p.DIM_PERSON_ID) AS dim_person_id
  FROM __SRC__DIM_PERSON p
  WHERE p.DIM_PERSON_ID <> -1
    AND p.IS_CLIENT = ''Y''
),
refs AS (
  SELECT
    TRY_CONVERT(nvarchar(48), r.DIM_PERSON_ID) AS dim_person_id,
    MAX(TRY_CONVERT(datetime, r.REFRL_START_DTTM)) AS last_ref_dttm,
    MIN(TRY_CONVERT(datetime, r.REFRL_START_DTTM)) AS first_ref_dttm
  FROM __SRC__FACT_REFERRALS r
  WHERE r.DIM_PERSON_ID <> -1
    AND (
         r.REFRL_START_DTTM >= DATEADD(year, -@ssd_timeframe_years, CONVERT(datetime, CONVERT(date, GETDATE())))
      OR r.REFRL_END_DTTM   >= DATEADD(year, -@ssd_timeframe_years, CONVERT(datetime, CONVERT(date, GETDATE())))
      OR r.REFRL_END_DTTM IS NULL
    )
  GROUP BY r.DIM_PERSON_ID
),
careleaver AS (
  SELECT DISTINCT TRY_CONVERT(nvarchar(48), cl.DIM_PERSON_ID) AS dim_person_id
  FROM __SRC__FACT_CLA_CARE_LEAVERS cl
  WHERE cl.DIM_PERSON_ID <> -1
    AND cl.IN_TOUCH_DTTM >= DATEADD(year, -@ssd_timeframe_years, CONVERT(datetime, CONVERT(date, GETDATE())))
),
elig AS (
  SELECT DISTINCT TRY_CONVERT(nvarchar(48), e.DIM_PERSON_ID) AS dim_person_id
  FROM __SRC__DIM_CLA_ELIGIBILITY e
  WHERE e.DIM_PERSON_ID <> -1
    AND e.DIM_LOOKUP_ELIGIBILITY_STATUS_DESC IS NOT NULL
),
involvements AS (
  SELECT DISTINCT TRY_CONVERT(nvarchar(48), i.DIM_PERSON_ID) AS dim_person_id
  FROM __SRC__FACT_INVOLVEMENTS i
  WHERE i.DIM_PERSON_ID <> -1
    AND (i.DIM_LOOKUP_INVOLVEMENT_TYPE_CODE NOT LIKE ''KA%'' 
         OR i.DIM_LOOKUP_INVOLVEMENT_TYPE_CODE IS NOT NULL
         OR i.IS_ALLOCATED_CW_FLAG = ''Y'')
    AND i.DIM_WORKER_ID <> ''-1''
    AND (i.END_DTTM IS NULL OR i.END_DTTM > GETDATE())
),
unioned AS (
  SELECT dim_person_id, 1 AS has_contact, 0 AS has_referral, 0 AS has_903, 0 AS is_care_leaver, 0 AS has_eligibility, 1 AS has_client, 0 AS has_involvement, first_contact_dttm AS first_dttm, last_contact_dttm AS last_dttm FROM contacts
  UNION ALL SELECT dim_person_id, 0,1,0,0,0,0,0, first_ref_dttm,  last_ref_dttm  FROM refs
  UNION ALL SELECT dim_person_id, 0,0,1,0,0,0,0, NULL,            NULL           FROM a903
  UNION ALL SELECT dim_person_id, 0,0,0,1,0,0,0, NULL,            NULL           FROM careleaver
  UNION ALL SELECT dim_person_id, 0,0,0,0,1,0,0, NULL,            NULL           FROM elig
  UNION ALL SELECT dim_person_id, 0,0,0,0,0,1,0, NULL,            NULL           FROM clients
  UNION ALL SELECT dim_person_id, 0,0,0,0,0,0,1, NULL,            NULL           FROM involvements
),
rollup AS (
  SELECT
    u.dim_person_id,
    CAST(MAX(CASE WHEN has_contact     = 1 THEN 1 ELSE 0 END) AS bit) AS has_contact,
    CAST(MAX(CASE WHEN has_referral    = 1 THEN 1 ELSE 0 END) AS bit) AS has_referral,
    CAST(MAX(CASE WHEN has_903         = 1 THEN 1 ELSE 0 END) AS bit) AS has_903,
    CAST(MAX(CASE WHEN is_care_leaver  = 1 THEN 1 ELSE 0 END) AS bit) AS is_care_leaver,
    CAST(MAX(CASE WHEN has_eligibility = 1 THEN 1 ELSE 0 END) AS bit) AS has_eligibility,
    CAST(MAX(CASE WHEN has_client      = 1 THEN 1 ELSE 0 END) AS bit) AS has_client,
    CAST(MAX(CASE WHEN has_involvement = 1 THEN 1 ELSE 0 END) AS bit) AS has_involvement,
    MIN(first_dttm) AS first_activity_dttm,
    MAX(last_dttm)  AS last_activity_dttm
  FROM unioned u
  GROUP BY u.dim_person_id
)
INSERT ssd_development.ssd_cohort(
  dim_person_id, legacy_id,
  has_contact, has_referral, has_903, is_care_leaver, has_eligibility,
  has_client, has_involvement,            -- <<< NEW
  first_activity_dttm, last_activity_dttm
)
SELECT
  r.dim_person_id,
  MAX(dp.LEGACY_ID) AS legacy_id,
  r.has_contact, r.has_referral, r.has_903, r.is_care_leaver, r.has_eligibility,
  r.has_client, r.has_involvement,        -- <<< NEW
  r.first_activity_dttm, r.last_activity_dttm
FROM rollup AS r
LEFT JOIN __SRC__DIM_PERSON AS dp
  ON dp.DIM_PERSON_ID = TRY_CONVERT(int, r.dim_person_id)
GROUP BY r.dim_person_id, r.has_contact, r.has_referral, r.has_903, r.is_care_leaver,
         r.has_eligibility, r.has_client, r.has_involvement,  -- <<< keep in GROUP BY too
         r.first_activity_dttm, r.last_activity_dttm;
';

/* Swap in the 3-part prefix once */
DECLARE @sql nvarchar(max) = REPLACE(@tpl, N'__SRC__', @src3);

-- Optional: inspect the generated SQL around the contacts CTE if needed
-- PRINT LEFT(@sql, 2000);

EXEC sp_executesql @sql, N'@ssd_timeframe_years int', @ssd_timeframe_years;


-- META-ELEMENT: {"type": "create_idx"}
CREATE INDEX IX_ssd_cohort_has_referral ON ssd_development.ssd_cohort(dim_person_id) WHERE has_referral = 1;
CREATE INDEX IX_ssd_cohort_has_involvement ON ssd_development.ssd_cohort(dim_person_id) WHERE has_involvement = 1;



-- META-ELEMENT: {"type": "test"}
PRINT 'Table created: ' + @TableName;

/* summary (optional) 
Show breakdown of why/source of records included in the ssd cohort */
SELECT
  COUNT(*) AS cohort_rows,
  SUM(CASE WHEN has_contact=1      THEN 1 ELSE 0 END) AS with_contacts,
  SUM(CASE WHEN has_referral=1     THEN 1 ELSE 0 END) AS with_referrals,
  SUM(CASE WHEN has_903=1          THEN 1 ELSE 0 END) AS in_903,
  SUM(CASE WHEN is_care_leaver=1   THEN 1 ELSE 0 END) AS care_leavers,
  SUM(CASE WHEN has_eligibility=1  THEN 1 ELSE 0 END) AS with_eligibility,
  SUM(CASE WHEN has_client=1  THEN 1 ELSE 0 END) AS has_client,
  SUM(CASE WHEN has_involvement=1  THEN 1 ELSE 0 END) AS with_involvement
FROM ssd_development.ssd_cohort;

-- META-END


-- META-CONTAINER: {"type": "table", "name": "ADMIN VERIFICATION ONLY"}
-- =============================================================================
-- Description: Enables sanity comparison against ssd_person & for use in EXISTS
-- Author: D2I
-- Version: 1.0
--          
-- Status: [D]ev
-- Remarks:  Verification: compare original ssd_person inclusion vs cohort-driven inclusion
--          Assumes @ssd_timeframe_years is already declared (INT). Uses same midnight cutoff 
--          rule as ssd_cohort build. 
-- Dependencies:

-- =============================================================================


DECLARE @cutoff datetime =
  DATEADD(year, -@ssd_timeframe_years, CONVERT(datetime, CONVERT(date, GETDATE())));

-- clean up any prior temp tables
IF OBJECT_ID('tempdb..#ssd_core_person_cohort') IS NOT NULL DROP TABLE #ssd_core_person_cohort;
IF OBJECT_ID('tempdb..#ssd_review_cohort')      IS NOT NULL DROP TABLE #ssd_review_cohort;

-- original ssd_person inclusion set (IDs only) - mirrors the EXISTS predicates
SELECT DISTINCT CAST(p.DIM_PERSON_ID AS nvarchar(48)) AS dim_person_id
INTO #ssd_core_person_cohort
FROM HDM.Child_Social.DIM_PERSON p
WHERE p.DIM_PERSON_ID IS NOT NULL
  AND p.DIM_PERSON_ID <> -1
  AND (
    p.IS_CLIENT = 'Y'                                                        -- client flag
    OR EXISTS (SELECT 1                                                     -- recent contact
               FROM HDM.Child_Social.FACT_CONTACTS fc
               WHERE fc.DIM_PERSON_ID = p.DIM_PERSON_ID
                 AND fc.CONTACT_DTTM >= @cutoff)
    OR EXISTS (SELECT 1                                                     -- referral start/end in window OR open
               FROM HDM.Child_Social.FACT_REFERRALS fr
               WHERE fr.DIM_PERSON_ID = p.DIM_PERSON_ID
                 AND ( fr.REFRL_START_DTTM >= @cutoff
                    OR fr.REFRL_END_DTTM   >= @cutoff
                    OR fr.REFRL_END_DTTM IS NULL ))
    OR EXISTS (SELECT 1                                                     -- care leaver contact in window
               FROM HDM.Child_Social.FACT_CLA_CARE_LEAVERS fccl
               WHERE fccl.DIM_PERSON_ID = p.DIM_PERSON_ID
                 AND fccl.IN_TOUCH_DTTM >= @cutoff)
    OR EXISTS (SELECT 1                                                     -- eligibility present
               FROM HDM.Child_Social.DIM_CLA_ELIGIBILITY dce
               WHERE dce.DIM_PERSON_ID = p.DIM_PERSON_ID
                 AND dce.DIM_LOOKUP_ELIGIBILITY_STATUS_DESC IS NOT NULL)
    OR EXISTS (SELECT 1                                                     -- involvement meets rules; still active
               FROM HDM.Child_Social.FACT_INVOLVEMENTS fi
               WHERE fi.DIM_PERSON_ID = p.DIM_PERSON_ID
                 AND ( fi.DIM_LOOKUP_INVOLVEMENT_TYPE_CODE NOT LIKE 'KA%'
                    OR fi.DIM_LOOKUP_INVOLVEMENT_TYPE_CODE IS NOT NULL
                    OR fi.IS_ALLOCATED_CW_FLAG = 'Y')
                 AND fi.DIM_WORKER_ID <> '-1'
                 AND (fi.END_DTTM IS NULL OR fi.END_DTTM > GETDATE()))
  );

-- cohort-driven inclusion set (parity with ssd_person reasons; deliberately excludes has_903)
SELECT co.dim_person_id
INTO #ssd_review_cohort
FROM ssd_development.ssd_cohort co
WHERE co.has_contact      = 1
   OR co.has_referral     = 1
   OR co.is_care_leaver   = 1
   OR co.has_eligibility  = 1
   OR co.has_client       = 1
   OR co.has_involvement  = 1;

-- META-ELEMENT: {"type": "test"}
-- headline counts: want intersection == review == core (and both "only_*" = 0)
SELECT
  (SELECT COUNT(*) FROM #ssd_core_person_cohort) AS orig_count,
  (SELECT COUNT(*) FROM #ssd_review_cohort)      AS cohort_count,
  (SELECT COUNT(*) FROM #ssd_core_person_cohort o
    WHERE EXISTS (SELECT 1 FROM #ssd_review_cohort c WHERE c.dim_person_id = o.dim_person_id)) AS intersection,
  (SELECT COUNT(*) FROM #ssd_core_person_cohort o
    WHERE NOT EXISTS (SELECT 1 FROM #ssd_review_cohort c WHERE c.dim_person_id = o.dim_person_id)) AS only_in_orig,
  (SELECT COUNT(*) FROM #ssd_review_cohort c
    WHERE NOT EXISTS (SELECT 1 FROM #ssd_core_person_cohort o WHERE o.dim_person_id = c.dim_person_id)) AS only_in_cohort;

-- -- why-diff sample: show cohort flags for rows only in ssd_person (twds diagnose parity gaps)
-- SELECT TOP 100 o.dim_person_id, co.*
-- FROM #ssd_core_person_cohort o
-- LEFT JOIN #ssd_review_cohort r ON r.dim_person_id = o.dim_person_id
-- LEFT JOIN ssd_development.ssd_cohort co ON co.dim_person_id = o.dim_person_id
-- WHERE r.dim_person_id IS NULL
-- ORDER BY o.dim_person_id;

-- note: keep temp tables if wanting to probe further; otherwise drop
-- DROP TABLE #ssd_core_person_cohort;
-- DROP TABLE #ssd_review_cohort;


-- META-END