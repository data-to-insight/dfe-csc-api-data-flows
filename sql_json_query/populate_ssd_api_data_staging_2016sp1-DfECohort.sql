
-- define if required 
use HDM_Local; -- Note: this the SystemC/LLogic default


/* Note for: Daily Data Flows Early Adopters
The following table definitions (and populating) can only be run after the main SSD script, OR the following definitions
can be added into the main SSD - insert locations are marked via the meta tags of:


-- Script compatibility and defaults
-- Default uses XML PATH for aggregations, SQL Server 2012+
-- Payload assembly uses FOR JSON, JSON_QUERY, JSON_VALUE, SQL Server 2016+
-- Optional modern aggregation using STRING_AGG is included as commented block, SQL Server 2022+


META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging"}
META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"} - temp table for API testing, can be removed post testing
*/

DECLARE @VERSION nvarchar(32) = N'0.2.0';
RAISERROR(N'== CSC API staging build: v%s ==', 10, 1, @VERSION) WITH NOWAIT;


-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging"}
-- =============================================================================
-- Description: Table for API payload and logging. 
-- Author: D2I
-- =============================================================================


-- Data pre/smoke test validator(s) (optional) --
-- D2I offers a seperate <simplified> validation VIEW towards your local data verification checks,
-- this offers some pre-process comparison between your data and the DfE API payload schema 
-- File: (SQL 2016+)https://github.com/data-to-insight/dfe-csc-api-data-flows/tree/main/pre_flight_checks/ssd_vw_csc_api_schema_checks.sql
-- -- 


-- IF OBJECT_ID('ssd_api_data_staging', 'U') IS NOT NULL DROP TABLE ssd_api_data_staging;
IF OBJECT_ID(N'ssd_api_data_staging', N'U') IS NULL

IF OBJECT_ID('ssd_api_data_staging') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM ssd_api_data_staging)
        TRUNCATE TABLE ssd_api_data_staging;
END
-- META-ELEMENT: {"type": "create_table"}
ELSE
BEGIN
    CREATE TABLE ssd_api_data_staging (
        id INT IDENTITY(1,1) PRIMARY KEY,           
        person_id NVARCHAR(48) NULL,                        -- link value (_person_id)
        previous_json_payload NVARCHAR(MAX) NULL,           -- historic last copy of last payload sent
        json_payload NVARCHAR(MAX) NOT NULL,                -- current awaiting payload
        partial_json_payload NVARCHAR(MAX) NULL,            -- current awaiting partial payload
        current_hash BINARY(32) NULL,                       -- current hash of JSON payload
        previous_hash BINARY(32) NULL,                      -- previous hash of JSON payload
        submission_status NVARCHAR(50) DEFAULT 'Pending',   -- Status: Pending, Sent, Error
        submission_timestamp DATETIME DEFAULT GETDATE(),    -- data submitted timestamp
        api_response NVARCHAR(MAX) NULL,                    -- API response or error
        row_state NVARCHAR(10) DEFAULT 'New',               -- record state : New, Updated, Deleted, Unchanged
        last_updated DATETIME DEFAULT GETDATE()             -- timestamp data update/insertion
    );

END


-- === Spec window (dynamic: 24 months back --> FY start on 1 April) ===
DECLARE @run_date      date = CONVERT(date, GETDATE());
DECLARE @months_back   int  = 24;
DECLARE @fy_start_month int = 4;  -- April

DECLARE @anchor date = DATEADD(month, -@months_back, @run_date);
DECLARE @fy_start_year int = YEAR(@anchor) - CASE WHEN MONTH(@anchor) < @fy_start_month THEN 1 ELSE 0 END;

DECLARE @window_start date = DATEFROMPARTS(@fy_start_year, @fy_start_month, 1);
DECLARE @window_end   date = @run_date;  -- today


;WITH
EligibleBySpec AS (
    /* Keep if unborn (expected DoB) OR ever ≤25 within window
       (26th birthday on/after window start). Include deceased. */
    SELECT p.pers_person_id
    FROM ssd_person p
    WHERE
          (p.pers_expected_dob IS NOT NULL)  -- unborn allowed
       OR (p.pers_dob IS NOT NULL AND DATEADD(year, 26, p.pers_dob) >= @window_start)
),
ActiveReferral AS (
    /* Episode overlaps window AND is open at run date (active) */
    SELECT DISTINCT cine.cine_person_id AS person_id
    FROM ssd_cin_episodes cine
    WHERE cine.cine_referral_date <= @window_end
      AND (cine.cine_close_date IS NULL OR cine.cine_close_date >= @window_start)
      AND (cine.cine_close_date IS NULL OR cine.cine_close_date >  @run_date)
),
WaitingAssessment AS (
    /* Open referral episode with no assessment started for that referral (placeholder). */
    SELECT DISTINCT cine.cine_person_id AS person_id
    FROM ssd_cin_episodes cine
    WHERE cine.cine_close_date IS NULL
      AND NOT EXISTS (
            SELECT 1
            FROM ssd_cin_assessments ca
            WHERE ca.cina_referral_id = cine.cine_referral_id
              AND ca.cina_assessment_start_date IS NOT NULL
      )
),
HasCINPlan AS (
    SELECT DISTINCT cinp.cinp_person_id AS person_id
    FROM ssd_cin_plans cinp
    WHERE cinp.cinp_cin_plan_start_date <= @window_end
      AND (cinp.cinp_cin_plan_end_date IS NULL OR cinp.cinp_cin_plan_end_date >= @window_start)
),
HasCPPlan AS (
    SELECT DISTINCT cppl.cppl_person_id AS person_id
    FROM ssd_cp_plans cppl
    WHERE cppl.cppl_cp_plan_start_date <= @window_end
      AND (cppl.cppl_cp_plan_end_date IS NULL OR cppl.cppl_cp_plan_end_date >= @window_start)
),
HasLAC AS (
    -- A) LAC episode linked to CIN episode that overlaps the window
    SELECT DISTINCT clae.clae_person_id AS person_id
    FROM ssd_cla_episodes clae
    JOIN ssd_cin_episodes cine
      ON cine.cine_referral_id = clae.clae_referral_id
    WHERE cine.cine_referral_date <= @window_end
      AND (cine.cine_close_date IS NULL OR cine.cine_close_date >= @window_start)

    UNION

    -- B) Or any placement overlapping the window
    SELECT DISTINCT clae2.clae_person_id AS person_id
    FROM ssd_cla_episodes clae2
    JOIN ssd_cla_placement clap
      ON clap.clap_cla_id = clae2.clae_cla_id
    WHERE clap.clap_cla_placement_start_date <= @window_end
      AND (clap.clap_cla_placement_end_date IS NULL OR clap.clap_cla_placement_end_date >= @window_start)
),
IsCareLeaver16to25 AS (
    SELECT DISTINCT clea.clea_person_id AS person_id
    FROM ssd_care_leavers clea
    JOIN ssd_person p ON p.pers_person_id = clea.clea_person_id
    WHERE clea.clea_care_leaver_latest_contact BETWEEN @window_start AND @window_end
      AND (
            (p.pers_dob IS NOT NULL AND DATEDIFF(year, p.pers_dob, @run_date) BETWEEN 16 AND 25)
         OR (p.pers_dob IS NULL AND p.pers_expected_dob IS NOT NULL)  -- rare, kept as guard
      )
),
IsDisabled AS (
    /* If any disability code recorded (no good dates to window), include */
    SELECT DISTINCT d.disa_person_id AS person_id
    FROM ssd_disability d
    WHERE NULLIF(LTRIM(RTRIM(d.disa_disability_code)), '') IS NOT NULL
),
SpecInclusion AS (
    /* Union of the groupings from spec (CIN definition) */
    SELECT person_id FROM ActiveReferral
    UNION SELECT person_id FROM WaitingAssessment
    UNION SELECT person_id FROM HasCINPlan
    UNION SELECT person_id FROM HasCPPlan
    UNION SELECT person_id FROM HasLAC
    UNION SELECT person_id FROM IsCareLeaver16to25
    UNION SELECT person_id FROM IsDisabled
),

RawPayloads AS (
    SELECT
        p.pers_person_id AS person_id,
        (
            SELECT
                -- Note: ids (str)
                LEFT(CAST(p.pers_person_id AS varchar(36)), 36) AS [la_child_id],
                CAST(0 AS bit) AS [purge],

                -- Child details
                JSON_QUERY((
                    SELECT
                        p.pers_forename AS [first_name],
                        p.pers_surname  AS [surname],

                        -- UPNs (13 alphanumeric, else null)
                        (SELECT TOP 1 CASE
                                        WHEN LEN(li.link_identifier_value) = 13
                                         AND TRY_CONVERT(bigint, li.link_identifier_value) IS NOT NULL
                                        THEN li.link_identifier_value
                                      END
                           FROM ssd_linked_identifiers li
                          WHERE li.link_person_id = p.pers_person_id
                            AND li.link_identifier_type = 'Unique Pupil Number'
                          ORDER BY li.link_valid_from_date DESC) AS [unique_pupil_number],

                        (SELECT TOP 1 CASE
                                        WHEN LEN(li2.link_identifier_value) = 13
                                         AND TRY_CONVERT(bigint, li2.link_identifier_value) IS NOT NULL
                                        THEN li2.link_identifier_value
                                      END
                           FROM ssd_linked_identifiers li2
                          WHERE li2.link_person_id = p.pers_person_id
                            AND li2.link_identifier_type = 'Former Unique Pupil Number'
                          ORDER BY li2.link_valid_from_date DESC) AS [former_unique_pupil_number],

                        LEFT(p.pers_upn_unknown, 3) AS [unique_pupil_number_unknown_reason],

                        CONVERT(varchar(10), p.pers_dob, 23) AS [date_of_birth],
                        CONVERT(varchar(10), p.pers_expected_dob, 23) AS [expected_date_of_birth],

                        CASE WHEN p.pers_sex IN ('M','F') THEN p.pers_sex ELSE 'U' END AS [sex],

                        LEFT(p.pers_ethnicity, 4) AS [ethnicity],

                        -- Disabilities array (avoid COALESCE on JSON)
                        JSON_QUERY(
                            CASE WHEN disab.disabilities IS NOT NULL
                                THEN disab.disabilities
                                ELSE '[]'
                            END
                        ) AS [disabilities],


                        -- Postcode (no space)
                        (SELECT TOP 1 LEFT(a.addr_address_postcode, 8)
                           FROM ssd_address a
                          WHERE a.addr_person_id = p.pers_person_id
                          ORDER BY a.addr_address_start_date DESC) AS [postcode],

                        -- UASC bool
                        CASE
                            WHEN EXISTS (
                                SELECT 1
                                  FROM ssd_immigration_status s
                                 WHERE s.immi_person_id = p.pers_person_id
                                   AND ISNULL(s.immi_immigration_status, '') COLLATE Latin1_General_CI_AI LIKE '%UASC%'
                            ) THEN CAST(1 AS bit)
                            ELSE CAST(0 AS bit)
                        END AS [uasc_flag],

                        (SELECT TOP 1 CONVERT(varchar(10), s2.immi_immigration_status_end_date, 23)
                           FROM ssd_immigration_status s2
                          WHERE s2.immi_person_id = p.pers_person_id
                          ORDER BY CASE WHEN s2.immi_immigration_status_end_date IS NULL THEN 1 ELSE 0 END,
                                   s2.immi_immigration_status_start_date DESC) AS [uasc_end_date],

                        CAST(0 AS bit) AS [purge]
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                )) AS [child_details],

                -- Health and wellbeing
                JSON_QUERY((
                    SELECT
                        JSON_QUERY(
                            CASE WHEN EXISTS (
                                    SELECT 1
                                    FROM ssd_sdq_scores csdq
                                    WHERE csdq.csdq_person_id = p.pers_person_id
                                    AND csdq.csdq_sdq_completed_date IS NOT NULL
                                    AND csdq.csdq_sdq_completed_date BETWEEN @window_start AND @window_end
                                    AND TRY_CONVERT(int, csdq.csdq_sdq_score) IS NOT NULL
                                )
                                THEN (
                                    SELECT
                                        CONVERT(varchar(10), csdq.csdq_sdq_completed_date, 23) AS [date],
                                        TRY_CONVERT(int, csdq.csdq_sdq_score) AS [score]
                                    FROM ssd_sdq_scores csdq
                                    WHERE csdq.csdq_person_id = p.pers_person_id
                                    AND csdq.csdq_sdq_completed_date IS NOT NULL
                                    AND csdq.csdq_sdq_completed_date BETWEEN @window_start AND @window_end
                                    AND TRY_CONVERT(int, csdq.csdq_sdq_score) IS NOT NULL
                                    ORDER BY csdq.csdq_sdq_completed_date DESC
                                    FOR JSON PATH
                                )
                                ELSE '[]'
                            END
                        ) AS [sdq_assessments],
                        CAST(0 AS bit) AS [purge]
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                )) AS [health_and_wellbeing],


                -- Social care episodes
                JSON_QUERY((
                    SELECT
                        -- Note: id(str)
                        LEFT(CAST(cine.cine_referral_id AS varchar(36)), 36) AS [social_care_episode_id], -- stringify for JSON
                        CONVERT(varchar(10), cine.cine_referral_date, 23) AS [referral_date],
                        LEFT(cine.cine_referral_source_code, 2) AS [referral_source],

                        CASE
                            WHEN TRY_CONVERT(bit, cine.cine_referral_nfa) IS NOT NULL
                                THEN TRY_CONVERT(bit, cine.cine_referral_nfa)
                            -- SSD source enforces NCHAR(1) however..., some robustness - wrap potential LA source strings
                            -- SSD source field cine_referral_nfa in review as bool
                            WHEN UPPER(LTRIM(RTRIM(cine.cine_referral_nfa))) IN ('Y','T','1','TRUE')
                                THEN CAST(1 AS bit)
                            WHEN UPPER(LTRIM(RTRIM(cine.cine_referral_nfa))) IN ('N','F','0','FALSE')
                                THEN CAST(0 AS bit)
                            ELSE CAST(NULL AS bit)
                        END AS [referral_no_further_action_flag],

                        -- care worker details
                        JSON_QUERY(
                            CASE WHEN EXISTS (
                                    SELECT 1
                                    FROM ssd_involvements i
                                    WHERE i.invo_referral_id = cine.cine_referral_id
                                    AND i.invo_involvement_start_date <= @window_end
                                    AND (i.invo_involvement_end_date IS NULL OR i.invo_involvement_end_date >= @window_start)
                                )
                                THEN (
                                    SELECT
                                        LEFT(CAST(pr.prof_staff_id AS varchar(12)), 12) AS [worker_id],
                                        CONVERT(varchar(10), i.invo_involvement_start_date, 23) AS [start_date],
                                        CONVERT(varchar(10), i.invo_involvement_end_date, 23)   AS [end_date]
                                    FROM ssd_involvements i
                                    JOIN ssd_professionals pr
                                    ON i.invo_professional_id = pr.prof_professional_id
                                    WHERE i.invo_referral_id = cine.cine_referral_id
                                    AND i.invo_involvement_start_date <= @window_end
                                    AND (i.invo_involvement_end_date IS NULL OR i.invo_involvement_end_date >= @window_start)
                                    ORDER BY i.invo_involvement_start_date DESC
                                    FOR JSON PATH
                                )
                                ELSE '[]'
                            END
                        ) AS [care_worker_details],


                        -- child and family assessments
                        JSON_QUERY(
                            CASE WHEN EXISTS (
                                    SELECT 1
                                    FROM ssd_cin_assessments ca
                                    WHERE ca.cina_referral_id = cine.cine_referral_id
                                    AND (
                                            ca.cina_assessment_start_date BETWEEN @window_start AND @window_end
                                        OR ca.cina_assessment_auth_date  BETWEEN @window_start AND @window_end
                                    )
                                )
                                THEN (
                                    SELECT
                                        LEFT(CAST(ca.cina_assessment_id AS varchar(36)), 36) AS [child_and_family_assessment_id],
                                        CONVERT(varchar(10), ca.cina_assessment_start_date, 23) AS [start_date],
                                        CONVERT(varchar(10), ca.cina_assessment_auth_date, 23)  AS [authorisation_date],
                                        JSON_QUERY(CASE
                                            WHEN af.cinf_assessment_factors_json IS NULL OR af.cinf_assessment_factors_json = ''
                                                THEN '[]'
                                            ELSE af.cinf_assessment_factors_json
                                        END) AS [factors],
                                        CAST(0 AS bit) AS [purge]
                                    FROM ssd_cin_assessments ca
                                    LEFT JOIN ssd_assessment_factors af
                                    ON af.cinf_assessment_id = ca.cina_assessment_id
                                    WHERE ca.cina_referral_id = cine.cine_referral_id
                                    AND (
                                            ca.cina_assessment_start_date BETWEEN @window_start AND @window_end
                                        OR ca.cina_assessment_auth_date  BETWEEN @window_start AND @window_end
                                    )
                                    FOR JSON PATH
                                )
                                ELSE '[]'
                            END
                        ) AS [child_and_family_assessments],


                        -- child in need plans
                        JSON_QUERY(
                            CASE WHEN EXISTS (
                                    SELECT 1
                                    FROM ssd_cin_plans cinp
                                    WHERE cinp.cinp_referral_id = cine.cine_referral_id
                                    AND cinp.cinp_cin_plan_start_date <= @window_end
                                    AND (cinp.cinp_cin_plan_end_date IS NULL OR cinp.cinp_cin_plan_end_date >= @window_start)
                                )
                                THEN (
                                    SELECT
                                        LEFT(CAST(cinp.cinp_cin_plan_id AS varchar(36)), 36) AS [child_in_need_plan_id],
                                        CONVERT(varchar(10), cinp.cinp_cin_plan_start_date, 23) AS [start_date],
                                        CONVERT(varchar(10), cinp.cinp_cin_plan_end_date, 23)   AS [end_date],
                                        CAST(0 AS bit) AS [purge]
                                    FROM ssd_cin_plans cinp
                                    WHERE cinp.cinp_referral_id = cine.cine_referral_id
                                    AND cinp.cinp_cin_plan_start_date <= @window_end
                                    AND (cinp.cinp_cin_plan_end_date IS NULL OR cinp.cinp_cin_plan_end_date >= @window_start)
                                    FOR JSON PATH
                                )
                                ELSE '[]'
                            END
                        ) AS [child_in_need_plans],


                        -- s47 assessments
                        JSON_QUERY(
                            CASE WHEN EXISTS (
                                    SELECT 1
                                    FROM ssd_s47_enquiry s47e
                                    WHERE s47e.s47e_referral_id = cine.cine_referral_id
                                    AND (
                                            s47e.s47e_s47_start_date BETWEEN @window_start AND @window_end
                                        OR s47e.s47e_s47_end_date   BETWEEN @window_start AND @window_end
                                        OR EXISTS (
                                            SELECT 1
                                            FROM ssd_initial_cp_conference icpc
                                            WHERE icpc.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                                                AND icpc.icpc_icpc_date BETWEEN @window_start AND @window_end
                                        )
                                    )
                                )
                                THEN (
                                    SELECT
                                        LEFT(CAST(s47e.s47e_s47_enquiry_id AS varchar(36)), 36) AS [section_47_assessment_id],
                                        CONVERT(varchar(10), s47e.s47e_s47_start_date, 23) AS [start_date],
                                        CASE
                                            WHEN JSON_VALUE(s47e.s47e_s47_outcome_json, '$.CP_CONFERENCE_FLAG') IN ('Y','T','1','true','True')
                                                THEN CAST(1 AS bit)
                                            WHEN JSON_VALUE(s47e.s47e_s47_outcome_json, '$.CP_CONFERENCE_FLAG') IN ('N','F','0','false','False')
                                                THEN CAST(0 AS bit)
                                            ELSE CAST(NULL AS bit)
                                        END AS [icpc_required_flag],
                                        CONVERT(varchar(10), icpc.icpc_icpc_date, 23) AS [icpc_date],
                                        CONVERT(varchar(10), s47e.s47e_s47_end_date, 23) AS [end_date],
                                        CAST(0 AS bit) AS [purge]
                                    FROM ssd_s47_enquiry s47e
                                    LEFT JOIN ssd_initial_cp_conference icpc
                                    ON icpc.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                                    WHERE s47e.s47e_referral_id = cine.cine_referral_id
                                    AND (
                                            s47e.s47e_s47_start_date BETWEEN @window_start AND @window_end
                                        OR s47e.s47e_s47_end_date   BETWEEN @window_start AND @window_end
                                        OR icpc.icpc_icpc_date      BETWEEN @window_start AND @window_end
                                    )
                                    FOR JSON PATH
                                )
                                ELSE '[]'
                            END
                        ) AS [section_47_assessments],


                        -- child protection plans
                        JSON_QUERY(
                            CASE WHEN EXISTS (
                                    SELECT 1
                                    FROM ssd_cp_plans cppl
                                    WHERE cppl.cppl_referral_id = cine.cine_referral_id
                                    AND cppl.cppl_cp_plan_start_date <= @window_end
                                    AND (cppl.cppl_cp_plan_end_date IS NULL OR cppl.cppl_cp_plan_end_date >= @window_start)
                                )
                                THEN (
                                    SELECT
                                        LEFT(CAST(cppl.cppl_cp_plan_id AS varchar(36)), 36) AS [child_protection_plan_id],
                                        CONVERT(varchar(10), cppl.cppl_cp_plan_start_date, 23) AS [start_date],
                                        CONVERT(varchar(10), cppl.cppl_cp_plan_end_date, 23)   AS [end_date],
                                        CAST(0 AS bit) AS [purge]
                                    FROM ssd_cp_plans cppl
                                    WHERE cppl.cppl_referral_id = cine.cine_referral_id
                                    AND cppl.cppl_cp_plan_start_date <= @window_end
                                    AND (cppl.cppl_cp_plan_end_date IS NULL OR cppl.cppl_cp_plan_end_date >= @window_start)
                                    FOR JSON PATH
                                )
                                ELSE '[]'
                            END
                        ) AS [child_protection_plans],


                        -- looked after placements
                        JSON_QUERY(
                            CASE WHEN EXISTS (
                                    SELECT 1
                                    FROM ssd_cla_episodes clae
                                    JOIN ssd_cla_placement clap
                                    ON clap.clap_cla_id = clae.clae_cla_id
                                    WHERE clae.clae_referral_id = cine.cine_referral_id
                                    AND clap.clap_cla_placement_start_date <= @window_end
                                    AND (clap.clap_cla_placement_end_date IS NULL OR clap.clap_cla_placement_end_date >= @window_start)
                                )
                                THEN (
                                    SELECT
                                        LEFT(CAST(clap.clap_cla_placement_id AS varchar(36)), 36) AS [child_looked_after_placement_id],
                                        CONVERT(varchar(10), clap.clap_cla_placement_start_date, 23) AS [start_date],
                                        LEFT(clae.clae_cla_episode_start_reason, 1) AS [start_reason],
                                        LEFT(clap.clap_cla_placement_type, 2) AS [placement_type],
                                        LEFT(clap.clap_cla_placement_postcode, 8) AS [postcode],
                                        CONVERT(varchar(10), clap.clap_cla_placement_end_date, 23) AS [end_date],
                                        LEFT(clae.clae_cla_episode_ceased_reason, 3) AS [end_reason],
                                        LEFT(clap.clap_cla_placement_change_reason, 6) AS [change_reason],
                                        CAST(0 AS bit) AS [purge]
                                    FROM ssd_cla_episodes clae
                                    JOIN ssd_cla_placement clap
                                    ON clap.clap_cla_id = clae.clae_cla_id
                                    WHERE clae.clae_referral_id = cine.cine_referral_id
                                    AND clap.clap_cla_placement_start_date <= @window_end
                                    AND (clap.clap_cla_placement_end_date IS NULL OR clap.clap_cla_placement_end_date >= @window_start)
                                    ORDER BY clap.clap_cla_placement_start_date DESC
                                    FOR JSON PATH
                                )
                                ELSE '[]'
                            END
                        ) AS [child_looked_after_placements],


                        -- Adoption (single object)
                        JSON_QUERY((
                            SELECT TOP 1
                                CONVERT(varchar(10), perm.perm_adm_decision_date, 23) AS [initial_decision_date],
                                CONVERT(varchar(10), perm.perm_matched_date, 23)      AS [matched_date],
                                CONVERT(varchar(10), perm.perm_placed_for_adoption_date, 23) AS [placed_date],
                                CAST(0 AS bit) AS [purge]
                              FROM ssd_permanence perm
                             WHERE (perm.perm_person_id = p.pers_person_id
                                OR perm.perm_cla_id IN (
                                       SELECT clae2.clae_cla_id
                                       FROM ssd_cla_episodes clae2
                                       WHERE clae2.clae_person_id = p.pers_person_id
                                   ))
                               AND (
                                    perm.perm_adm_decision_date       BETWEEN @window_start AND @window_end
                                 OR perm.perm_matched_date            BETWEEN @window_start AND @window_end
                                 OR perm.perm_placed_for_adoption_date BETWEEN @window_start AND @window_end
                               )
                             ORDER BY COALESCE(perm.perm_placed_for_adoption_date,
                                               perm.perm_matched_date,
                                               perm.perm_adm_decision_date) DESC
                             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                        )) AS [adoption],

                        -- Care leavers (single object)
                        JSON_QUERY((
                            SELECT TOP 1
                                CONVERT(varchar(10), clea.clea_care_leaver_latest_contact, 23) AS [contact_date],
                                LEFT(clea.clea_care_leaver_activity, 2) AS [activity],
                                LEFT(clea.clea_care_leaver_accommodation, 1) AS [accommodation],
                                CAST(0 AS bit) AS [purge]
                              FROM ssd_care_leavers clea
                             WHERE clea.clea_person_id = p.pers_person_id
                               AND clea.clea_care_leaver_latest_contact BETWEEN @window_start AND @window_end
                             ORDER BY clea.clea_care_leaver_latest_contact DESC
                             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                        )) AS [care_leavers],

                        CONVERT(varchar(10), cine.cine_close_date, 23) AS [closure_date],
                        LEFT(cine.cine_close_reason, 3) AS [closure_reason],
                        CAST(0 AS bit) AS [purge]
                      FROM ssd_cin_episodes cine
                     WHERE cine.cine_person_id = p.pers_person_id
                       AND cine.cine_referral_date <= @window_end
                       AND (cine.cine_close_date IS NULL OR cine.cine_close_date >= @window_start)
                     FOR JSON PATH
                )) AS [social_care_episodes]

            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS json_payload

    -- keep only records who (a) pass age/unborn gate and (b) match at least one api spec groups
    FROM ssd_person p
    JOIN EligibleBySpec elig ON elig.pers_person_id = p.pers_person_id -- either unborn, or 26th bday falls on or after @window_start (deceased not filtered)
    JOIN SpecInclusion  si   ON si.person_id        = p.pers_person_id -- appearing in ActiveReferral, WaitingAssessment, CIN plan, CP plan, LAC, Care leavers 16 to 25, Disabled

    /* Disabilities array producer */
    OUTER APPLY (
        SELECT JSON_QUERY(
            N'[' +
            ISNULL(
                STUFF((
                    SELECT N',' + QUOTENAME(u.code, '"')
                    FROM (
                        SELECT TOP (12) code
                        FROM (
                            SELECT DISTINCT
                                LEFT(UPPER(LTRIM(RTRIM(d2.disa_disability_code))), 4) AS code
                            FROM ssd_disability AS d2
                            WHERE d2.disa_person_id = p.pers_person_id
                              AND d2.disa_disability_code IS NOT NULL
                              AND LTRIM(RTRIM(d2.disa_disability_code)) <> ''
                        ) d
                        ORDER BY code
                    ) u
                    FOR XML PATH(''), TYPE
                ).value('.', 'nvarchar(max)'), 1, 1, N''),
                N''
            ) + N']'
        ) AS disabilities
    ) AS disab
),

Hashed AS (
    SELECT
        person_id,
        json_payload,
        HASHBYTES('SHA2_256', CAST(json_payload AS NVARCHAR(MAX))) AS current_hash
    FROM RawPayloads
)
INSERT INTO ssd_api_data_staging
    (person_id, previous_json_payload, json_payload, current_hash, previous_hash,
     submission_status, row_state, last_updated)
SELECT
    h.person_id,
    prev.json_payload AS previous_json_payload,
    h.json_payload,
    h.current_hash,
    prev.current_hash AS previous_hash,
    'Pending' AS submission_status,
    CASE WHEN prev.current_hash IS NULL THEN 'New' ELSE 'Updated' END AS row_state,
    GETDATE() AS last_updated
FROM Hashed h
OUTER APPLY (
    SELECT TOP (1) s.json_payload, s.current_hash
    FROM ssd_api_data_staging s
    WHERE s.person_id = h.person_id
    ORDER BY s.id DESC
) AS prev
WHERE prev.current_hash IS NULL             -- first time we’ve ever seen this person
   OR prev.current_hash <> h.current_hash;  -- payload has changed



-- -- -- Optional
-- -- CREATE INDEX IX_cin_episodes_dates      ON ssd_cin_episodes(cine_person_id, cine_referral_date, cine_close_date);
-- -- CREATE INDEX IX_cin_plans_dates         ON ssd_cin_plans(cinp_person_id, cinp_cin_plan_start_date, cinp_cin_plan_end_date);
-- -- CREATE INDEX IX_cp_plans_dates          ON ssd_cp_plans(cppl_person_id, cppl_cp_plan_start_date, cppl_cp_plan_end_date);
-- -- CREATE INDEX IX_cla_placements_dates    ON ssd_cla_placement(clap_cla_id, clap_cla_placement_start_date, clap_cla_placement_end_date);
-- -- CREATE INDEX IX_care_leavers_date       ON ssd_care_leavers(clea_person_id, clea_care_leaver_latest_contact);
-- -- CREATE INDEX IX_sdq_date                ON ssd_sdq_scores(csdq_person_id, csdq_sdq_completed_date);

-- -- -- Optional
-- -- CREATE UNIQUE INDEX UX_ssd_api_person_hash
-- -- ON ssd_api_data_staging(person_id, current_hash);

-- Get sample of LIVE rows that def have have an extended/full payload (if available)
SELECT TOP (5)
    person_id,
    LEN(json_payload)        AS payload_chars,
    json_payload  AS preview
FROM ssd_api_data_staging
ORDER BY DATALENGTH(json_payload) DESC, id DESC;




