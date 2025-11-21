-- -- SystemC / LLogic only
-- USE [HDM_Local];
-- GO


/* View: ssd_development.ssd_vw_csc_api_schema_checks

   SQL Server 2016+ (not legacy versions)
   Simplified NON-COMPREHENSIVE pre-processing verification checks against DfE v0.9.0 API schema
   - Supplied as example. Script can be built-on to increase usefulness within individual LAs. 

   When implementing, remember to search/replace on 'ssd_development.' to either remove entirely(replace with '' empty str), 
   or add LA own schema location. If setting HDM_Local as above, then everything below default creates in this reporting instance. 
*/

CREATE OR ALTER VIEW ssd_development.ssd_vw_csc_api_schema_checks
AS
WITH
Persons AS (
    SELECT DISTINCT
           CAST(p.pers_person_id AS varchar(128))           AS person_id,
           CAST(ISNULL(p.pers_single_unique_id,'SSD_SUI') AS varchar(128)) AS mis_child_id,
           p.pers_upn_unknown
    FROM ssd_development.ssd_person p
),
Episodes AS (
    SELECT DISTINCT
           CAST(c.cine_referral_id AS varchar(128)) AS episode_id,
           c.cine_referral_source_code              AS referral_source_code
    FROM ssd_development.ssd_cin_episodes c
),
Workers AS (
    SELECT DISTINCT
           CAST(pr.prof_staff_id AS varchar(128)) AS worker_id
    FROM ssd_development.ssd_involvements i
    JOIN ssd_development.ssd_professionals pr
      ON pr.prof_professional_id = i.invo_professional_id
),
Assessments AS (
    SELECT DISTINCT CAST(ca.cina_assessment_id AS varchar(128)) AS assessment_id
    FROM ssd_development.ssd_cin_assessments ca
),
CinPlans AS (
    SELECT DISTINCT CAST(cp.cinp_cin_plan_id AS varchar(128)) AS cin_plan_id
    FROM ssd_development.ssd_cin_plans cp
),
S47 AS (
    SELECT DISTINCT CAST(s.s47e_s47_enquiry_id AS varchar(128)) AS s47_id
    FROM ssd_development.ssd_s47_enquiry s
),
CPPlans AS (
    SELECT DISTINCT CAST(cp.cppl_cp_plan_id AS varchar(128)) AS cp_plan_id
    FROM ssd_development.ssd_cp_plans cp
),
Placements AS (
    SELECT DISTINCT
           CAST(p.clap_cla_placement_id AS varchar(128)) AS placement_id,
            p.clap_cla_placement_type                    AS placement_type,
            p.clap_cla_placement_postcode                AS postcode,
            p.clap_cla_placement_change_reason           AS change_reason
    FROM ssd_development.ssd_cla_placement p
),
EpisodeReasons AS (
    SELECT DISTINCT
           CAST(e.clae_cla_id AS varchar(128))               AS cla_id,
           e.clae_cla_episode_start_reason                   AS start_reason,
           e.clae_cla_episode_ceased_reason                  AS end_reason
    FROM ssd_development.ssd_cla_episodes e
),
CareLeavers AS (
    SELECT DISTINCT
           clea_care_leaver_activity      AS activity_code,
           clea_care_leaver_accommodation AS accommodation_code
    FROM ssd_development.ssd_care_leavers
),
UPNs AS (
    SELECT DISTINCT
           CAST(p.pers_person_id AS varchar(128)) AS person_id,
           p.pers_upn                             AS upn
    FROM ssd_development.ssd_person p
    WHERE p.pers_upn IS NOT NULL
)
SELECT
    check_child_id,
    [entity],
    [rule],
    violations,
    example_value,
    example_key
FROM (
    -- id pattern checks
    SELECT 'la_child_id pattern' AS check_child_id, 'person' AS [entity], '^[A-Za-z0-9_-]*$' AS [rule],
           SUM(CASE WHEN person_id LIKE '%[^A-Za-z0-9_-]%' THEN 1 ELSE 0 END) AS violations,
           MAX(CASE WHEN person_id LIKE '%[^A-Za-z0-9_-]%' THEN person_id ELSE '' END) AS example_value,
           MAX(CASE WHEN person_id LIKE '%[^A-Za-z0-9_-]%' THEN person_id ELSE '' END) AS example_key
    FROM Persons

    UNION ALL
    SELECT 'mis_child_id pattern', 'person', '^[A-Za-z0-9_-]*$',
           SUM(CASE WHEN mis_child_id LIKE '%[^A-Za-z0-9_-]%' THEN 1 ELSE 0 END),
           MAX(CASE WHEN mis_child_id LIKE '%[^A-Za-z0-9_-]%' THEN mis_child_id ELSE '' END),
           MAX(CASE WHEN mis_child_id LIKE '%[^A-Za-z0-9_-]%' THEN person_id   ELSE '' END)
    FROM Persons

    UNION ALL
    SELECT 'social_care_episode_id pattern', 'cin_episode', '^[A-Za-z0-9_-]*$',
           SUM(CASE WHEN episode_id LIKE '%[^A-Za-z0-9_-]%' THEN 1 ELSE 0 END),
           MAX(CASE WHEN episode_id LIKE '%[^A-Za-z0-9_-]%' THEN episode_id ELSE '' END),
           MAX(CASE WHEN episode_id LIKE '%[^A-Za-z0-9_-]%' THEN episode_id ELSE '' END)
    FROM Episodes

    UNION ALL
    SELECT 'worker_id pattern', 'professional', '^[A-Za-z0-9_-]*$',
           SUM(CASE WHEN worker_id LIKE '%[^A-Za-z0-9_-]%' THEN 1 ELSE 0 END),
           MAX(CASE WHEN worker_id LIKE '%[^A-Za-z0-9_-]%' THEN worker_id ELSE '' END),
           MAX(CASE WHEN worker_id LIKE '%[^A-Za-z0-9_-]%' THEN worker_id ELSE '' END)
    FROM Workers

    UNION ALL
    SELECT 'child_and_family_assessment_id pattern', 'assessment', '^[A-Za-z0-9_-]*$',
           SUM(CASE WHEN assessment_id LIKE '%[^A-Za-z0-9_-]%' THEN 1 ELSE 0 END),
           MAX(CASE WHEN assessment_id LIKE '%[^A-Za-z0-9_-]%' THEN assessment_id ELSE '' END),
           MAX(CASE WHEN assessment_id LIKE '%[^A-Za-z0-9_-]%' THEN assessment_id ELSE '' END)
    FROM Assessments

    UNION ALL
    SELECT 'child_in_need_plan_id pattern', 'cin_plan', '^[A-Za-z0-9_-]*$',
           SUM(CASE WHEN cin_plan_id LIKE '%[^A-Za-z0-9_-]%' THEN 1 ELSE 0 END),
           MAX(CASE WHEN cin_plan_id LIKE '%[^A-Za-z0-9_-]%' THEN cin_plan_id ELSE '' END),
           MAX(CASE WHEN cin_plan_id LIKE '%[^A-Za-z0-9_-]%' THEN cin_plan_id ELSE '' END)
    FROM CinPlans

    UNION ALL
    SELECT 'section_47_assessment_id pattern', 's47', '^[A-Za-z0-9_-]*$',
           SUM(CASE WHEN s47_id LIKE '%[^A-Za-z0-9_-]%' THEN 1 ELSE 0 END),
           MAX(CASE WHEN s47_id LIKE '%[^A-Za-z0-9_-]%' THEN s47_id ELSE '' END),
           MAX(CASE WHEN s47_id LIKE '%[^A-Za-z0-9_-]%' THEN s47_id ELSE '' END)
    FROM S47

    UNION ALL
    SELECT 'child_protection_plan_id pattern', 'cp_plan', '^[A-Za-z0-9_-]*$',
           SUM(CASE WHEN cp_plan_id LIKE '%[^A-Za-z0-9_-]%' THEN 1 ELSE 0 END),
           MAX(CASE WHEN cp_plan_id LIKE '%[^A-Za-z0-9_-]%' THEN cp_plan_id ELSE '' END),
           MAX(CASE WHEN cp_plan_id LIKE '%[^A-Za-z0-9_-]%' THEN cp_plan_id ELSE '' END)
    FROM CPPlans

    UNION ALL
    SELECT 'child_looked_after_placement_id pattern', 'placement', '^[A-Za-z0-9_-]*$',
           SUM(CASE WHEN placement_id LIKE '%[^A-Za-z0-9_-]%' THEN 1 ELSE 0 END),
           MAX(CASE WHEN placement_id LIKE '%[^A-Za-z0-9_-]%' THEN placement_id ELSE '' END),
           MAX(CASE WHEN placement_id LIKE '%[^A-Za-z0-9_-]%' THEN placement_id ELSE '' END)
    FROM Placements

    -- id length checks
    UNION ALL
    SELECT 'la_child_id length', 'person', '<= 36',
           SUM(CASE WHEN LEN(person_id) > 36 THEN 1 ELSE 0 END),
           MAX(CASE WHEN LEN(person_id) > 36 THEN person_id ELSE '' END),
           MAX(CASE WHEN LEN(person_id) > 36 THEN person_id ELSE '' END)
    FROM Persons

    UNION ALL
    SELECT 'mis_child_id length', 'person', '<= 36',
           SUM(CASE WHEN LEN(mis_child_id) > 36 THEN 1 ELSE 0 END),
           MAX(CASE WHEN LEN(mis_child_id) > 36 THEN mis_child_id ELSE '' END),
           MAX(CASE WHEN LEN(mis_child_id) > 36 THEN person_id   ELSE '' END)
    FROM Persons

    UNION ALL
    SELECT 'social_care_episode_id length', 'cin_episode', '<= 36',
           SUM(CASE WHEN LEN(episode_id) > 36 THEN 1 ELSE 0 END),
           MAX(CASE WHEN LEN(episode_id) > 36 THEN episode_id ELSE '' END),
           MAX(CASE WHEN LEN(episode_id) > 36 THEN episode_id ELSE '' END)
    FROM Episodes

    UNION ALL
    SELECT 'worker_id length', 'professional', '<= 12',
           SUM(CASE WHEN LEN(worker_id) > 12 THEN 1 ELSE 0 END),
           MAX(CASE WHEN LEN(worker_id) > 12 THEN worker_id ELSE '' END),
           MAX(CASE WHEN LEN(worker_id) > 12 THEN worker_id ELSE '' END)
    FROM Workers

    UNION ALL
    SELECT 'child_and_family_assessment_id length', 'assessment', '<= 36',
           SUM(CASE WHEN LEN(assessment_id) > 36 THEN 1 ELSE 0 END),
           MAX(CASE WHEN LEN(assessment_id) > 36 THEN assessment_id ELSE '' END),
           MAX(CASE WHEN LEN(assessment_id) > 36 THEN assessment_id ELSE '' END)
    FROM Assessments

    UNION ALL
    SELECT 'child_in_need_plan_id length', 'cin_plan', '<= 36',
           SUM(CASE WHEN LEN(cin_plan_id) > 36 THEN 1 ELSE 0 END),
           MAX(CASE WHEN LEN(cin_plan_id) > 36 THEN cin_plan_id ELSE '' END),
           MAX(CASE WHEN LEN(cin_plan_id) > 36 THEN cin_plan_id ELSE '' END)
    FROM CinPlans

    UNION ALL
    SELECT 'section_47_assessment_id length', 's47', '<= 36',
           SUM(CASE WHEN LEN(s47_id) > 36 THEN 1 ELSE 0 END),
           MAX(CASE WHEN LEN(s47_id) > 36 THEN s47_id ELSE '' END),
           MAX(CASE WHEN LEN(s47_id) > 36 THEN s47_id ELSE '' END)
    FROM S47

    UNION ALL
    SELECT 'child_protection_plan_id length', 'cp_plan', '<= 36',
           SUM(CASE WHEN LEN(cp_plan_id) > 36 THEN 1 ELSE 0 END),
           MAX(CASE WHEN LEN(cp_plan_id) > 36 THEN cp_plan_id ELSE '' END),
           MAX(CASE WHEN LEN(cp_plan_id) > 36 THEN cp_plan_id ELSE '' END)
    FROM CPPlans

    UNION ALL
    SELECT 'child_looked_after_placement_id length', 'placement', '<= 36',
           SUM(CASE WHEN LEN(placement_id) > 36 THEN 1 ELSE 0 END),
           MAX(CASE WHEN LEN(placement_id) > 36 THEN placement_id ELSE '' END),
           MAX(CASE WHEN LEN(placement_id) > 36 THEN placement_id ELSE '' END)
    FROM Placements

    -- code and length checks, when value exists
    UNION ALL
    SELECT 'referral_source length', 'cin_episode', '<= 2',
           SUM(CASE WHEN referral_source_code IS NOT NULL AND LEN(referral_source_code) > 2 THEN 1 ELSE 0 END),
           MAX(CASE WHEN referral_source_code IS NOT NULL AND LEN(referral_source_code) > 2 THEN referral_source_code ELSE '' END),
           '' AS example_key
    FROM Episodes

    UNION ALL
    SELECT 'start_reason length', 'cla_episode', '<= 1',
            SUM(CASE WHEN start_reason IS NOT NULL AND LEN(start_reason) > 1 THEN 1 ELSE 0 END),
            MAX(CASE WHEN start_reason IS NOT NULL AND LEN(start_reason) > 1 THEN start_reason ELSE '' END),
            '' AS example_key
    FROM EpisodeReasons

    UNION ALL
    SELECT 'end_reason length', 'cla_episode', '<= 3',
            SUM(CASE WHEN end_reason IS NOT NULL AND LEN(end_reason) > 3 THEN 1 ELSE 0 END),
            MAX(CASE WHEN end_reason IS NOT NULL AND LEN(end_reason) > 3 THEN end_reason ELSE '' END),
            '' AS example_key
    FROM EpisodeReasons

    UNION ALL
    SELECT 'placement_type length', 'placement', '<= 2',
           SUM(CASE WHEN placement_type IS NOT NULL AND LEN(placement_type) > 2 THEN 1 ELSE 0 END),
           MAX(CASE WHEN placement_type IS NOT NULL AND LEN(placement_type) > 2 THEN placement_type ELSE '' END),
           '' AS example_key
    FROM Placements

    UNION ALL
    SELECT 'postcode length', 'placement', '<= 8',
           SUM(CASE WHEN postcode IS NOT NULL AND LEN(postcode) > 8 THEN 1 ELSE 0 END),
           MAX(CASE WHEN postcode IS NOT NULL AND LEN(postcode) > 8 THEN postcode ELSE '' END),
           '' AS example_key
    FROM Placements

    UNION ALL
    SELECT 'change_reason length', 'placement', '<= 6',
           SUM(CASE WHEN change_reason IS NOT NULL AND LEN(change_reason) > 6 THEN 1 ELSE 0 END),
           MAX(CASE WHEN change_reason IS NOT NULL AND LEN(change_reason) > 6 THEN change_reason ELSE '' END),
           '' AS example_key
    FROM Placements

       -- UPN unknown reason code, when value exists
    UNION ALL
    SELECT 'upn_unknown code', 'person', 'IN (UN1..UN10)',
           SUM(
               CASE
                   WHEN pers_upn_unknown IS NOT NULL
                        AND pers_upn_unknown NOT IN (
                            'UN1','UN2','UN3','UN4','UN5',
                            'UN6','UN7','UN8','UN9','UN10'
                        )
                   THEN 1
                   ELSE 0
               END
           ) AS violations,
           MAX(
               CASE
                   WHEN pers_upn_unknown IS NOT NULL
                        AND pers_upn_unknown NOT IN (
                            'UN1','UN2','UN3','UN4','UN5',
                            'UN6','UN7','UN8','UN9','UN10'
                        )
                   THEN pers_upn_unknown
                   ELSE ''
               END
           ) AS example_value,
           MAX(
               CASE
                   WHEN pers_upn_unknown IS NOT NULL
                        AND pers_upn_unknown NOT IN (
                            'UN1','UN2','UN3','UN4','UN5',
                            'UN6','UN7','UN8','UN9','UN10'
                        )
                   THEN person_id
                   ELSE ''
               END
           ) AS example_key
    FROM Persons

    UNION ALL
    SELECT 'care_leaver_activity code', 'care_leaver', 'IN (F1,P1,F2,P2,F4,P4,F5,P5,G4,G5,G6)',
           SUM(
               CASE
                   WHEN activity_code IS NOT NULL
                        AND activity_code NOT IN (
                            'F1','P1','F2','P2','F4','P4','F5','P5','G4','G5','G6'
                        )
                   THEN 1
                   ELSE 0
               END
           ) AS violations,
           MAX(
               CASE
                   WHEN activity_code IS NOT NULL
                        AND activity_code NOT IN (
                            'F1','P1','F2','P2','F4','P4','F5','P5','G4','G5','G6'
                        )
                   THEN activity_code
                   ELSE ''
               END
           ) AS example_value,
           '' AS example_key
    FROM CareLeavers

    UNION ALL
    SELECT 'care_leaver_accommodation code', 'care_leaver', 'IN (B,C,D,E,G,H,K,R,S,T,U,V)',
           SUM(
               CASE
                   WHEN accommodation_code IS NOT NULL
                        AND accommodation_code NOT IN (
                            'B','C','D','E','G','H','K','R','S','T','U','V'
                        )
                   THEN 1
                   ELSE 0
               END
           ) AS violations,
           MAX(
               CASE
                   WHEN accommodation_code IS NOT NULL
                        AND accommodation_code NOT IN (
                            'B','C','D','E','G','H','K','R','S','T','U','V'
                        )
                   THEN accommodation_code
                   ELSE ''
               END
           ) AS example_value,
           '' AS example_key
    FROM CareLeavers

        -- UPN if exists
    UNION ALL
    SELECT 'unique_pupil_number format', 'person', '13 alphanumeric characters',
           SUM(
               CASE
                   WHEN upn IS NOT NULL
                        AND NOT (LEN(upn) = 13 AND upn NOT LIKE '%[^0-9A-Za-z]%')
                   THEN 1
                   ELSE 0
               END
           ) AS violations,
           MAX(
               CASE
                   WHEN upn IS NOT NULL
                        AND NOT (LEN(upn) = 13 AND upn NOT LIKE '%[^0-9A-Za-z]%')
                   THEN upn
                   ELSE ''
               END
           ) AS example_value,
           MAX(
               CASE
                   WHEN upn IS NOT NULL
                        AND NOT (LEN(upn) = 13 AND upn NOT LIKE '%[^0-9A-Za-z]%')
                   THEN person_id
                   ELSE ''
               END
           ) AS example_key
    FROM UPNs
) x;
GO








-- -- ALL checks shown, sorted by violations
-- SELECT *
-- FROM ssd_development.ssd_vw_csc_api_schema_checks
-- ORDER BY violations DESC, check_child_id;

-- FAILING checks only
SELECT *
FROM ssd_development.ssd_vw_csc_api_schema_checks
WHERE violations > 0
ORDER BY violations DESC;
