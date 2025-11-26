-- PostgreSQL compatible version of CSC API staging build
-- Target: PostgreSQL 13 plus
-- Notes: enable pgcrypto for SHA256 hashes, use jsonb for payloads, use LATERAL for subqueries
-- Switch database manually if needed, for example in psql use \c db_name


/* Note for: Daily Data Flows Early Adopters
The following table definitions (and populating) can only be run after the main SSD script

META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging"}
META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"} - temp table for API testing, can be removed post testing
*/

-- Optional banner
DO $$ BEGIN
  RAISE NOTICE '== CSC API staging build: v%s ==', '0.1.0';
END $$;

-- Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =============================================================================
-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging"}
-- Description: Table for API payload and logging
-- Author: D2I
-- =============================================================================

CREATE TABLE IF NOT EXISTS ssd_api_data_staging (
    id BIGSERIAL PRIMARY KEY,
    person_id VARCHAR(48),
    previous_json_payload JSONB,
    json_payload JSONB NOT NULL,
    partial_json_payload JSONB,
    current_hash BYTEA,
    previous_hash BYTEA,
    submission_status VARCHAR(50) DEFAULT 'Pending',
    submission_timestamp TIMESTAMPTZ DEFAULT now(),
    api_response TEXT,
    row_state VARCHAR(10) DEFAULT 'New',
    last_updated TIMESTAMPTZ DEFAULT now()
);

-- =============================================================================
-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"}
-- Description: Table for TEST or ANON API payload and logging.
-- This table is non live and solely for pre live data or API testing. It can be
-- removed at any point by the LA once live sends are initiated to DfE.
-- Author: D2I
-- =============================================================================

CREATE TABLE IF NOT EXISTS ssd_api_data_staging_anon (
    id BIGSERIAL PRIMARY KEY,
    person_id VARCHAR(48),
    previous_json_payload JSONB,
    json_payload JSONB NOT NULL,
    partial_json_payload JSONB,
    current_hash BYTEA,
    previous_hash BYTEA,
    submission_status VARCHAR(50) DEFAULT 'Pending',
    submission_timestamp TIMESTAMPTZ DEFAULT now(),
    api_response TEXT,
    row_state VARCHAR(10) DEFAULT 'New',
    last_updated TIMESTAMPTZ DEFAULT now()
);

-- Optional unique index as a guard rail
-- CREATE UNIQUE INDEX IF NOT EXISTS ux_ssd_api_person_hash
--     ON ssd_api_data_staging(person_id, current_hash);

-- =============================================================================
-- Main build and insert, idempotent by hash
-- Requires minimum source tables to exist:
-- ssd_person, ssd_disability, ssd_sdq_scores, ssd_cin_episodes, ssd_involvements,
-- ssd_professionals, ssd_cin_assessments, ssd_assessment_factors, ssd_cin_plans,
-- ssd_s47_enquiry, ssd_initial_cp_conference, ssd_cla_episodes, ssd_cla_placement,
-- ssd_permanence, ssd_care_leavers, ssd_linked_identifiers, ssd_address, ssd_immigration_status
-- =============================================================================

BEGIN;

WITH raw AS (
  SELECT
    p.pers_person_id::VARCHAR(48) AS person_id,

    jsonb_build_object(
      'la_child_id',
        NULLIF(p.pers_person_id::TEXT, ''),
      'mis_child_id',
        COALESCE(NULLIF(p.pers_single_unique_id, ''), 'SSD_SUI'),
      'purge', false,

      'child_details', jsonb_build_object(
        'first_name', NULLIF(p.pers_forename, ''),
        'surname',    NULLIF(p.pers_surname, ''),
        'unique_pupil_number', (
          SELECT li.link_identifier_value
          FROM ssd_linked_identifiers li
          WHERE li.link_person_id = p.pers_person_id
            AND li.link_identifier_type = 'Unique Pupil Number'
            AND length(li.link_identifier_value) = 13
            AND li.link_identifier_value ~ '^\d{13}$'
          ORDER BY li.link_valid_from_date DESC
          LIMIT 1
        ),
        'former_unique_pupil_number', (
          SELECT li.link_identifier_value
          FROM ssd_linked_identifiers li
          WHERE li.link_person_id = p.pers_person_id
            AND li.link_identifier_type = 'Former Unique Pupil Number'
            AND length(li.link_identifier_value) = 13
            AND li.link_identifier_value ~ '^\d{13}$'
          ORDER BY li.link_valid_from_date DESC
          LIMIT 1
        ),
        'unique_pupil_number_unknown_reason', NULLIF(left(COALESCE(p.pers_upn_unknown, ''), 3), ''),
        'date_of_birth', CASE WHEN p.pers_dob IS NULL THEN NULL ELSE to_char(p.pers_dob, 'YYYY-MM-DD') END,
        'expected_date_of_birth', CASE WHEN p.pers_expected_dob IS NULL THEN NULL ELSE to_char(p.pers_expected_dob, 'YYYY-MM-DD') END,
        'sex', CASE WHEN p.pers_sex IN ('M','F') THEN p.pers_sex ELSE 'U' END,
        'ethnicity', NULLIF(left(COALESCE(p.pers_ethnicity, ''), 4), ''),
        'disabilities', COALESCE(disab.disabilities_json, '[]'::jsonb),
        'postcode', (
          SELECT left(a.addr_address_postcode, 8)
          FROM ssd_address a
          WHERE a.addr_person_id = p.pers_person_id
          ORDER BY a.addr_address_start_date DESC
          LIMIT 1
        ),
        'uasc_flag', EXISTS (
          SELECT 1
          FROM ssd_immigration_status immi
          WHERE immi.immi_person_id = p.pers_person_id
            AND (immi.immi_immigration_status = 'UASC' OR immi.immi_immigration_status ILIKE '%UASC%')
        ),
        'uasc_end_date', (
          SELECT to_char(immi2.immi_immigration_status_end_date, 'YYYY-MM-DD')
          FROM ssd_immigration_status immi2
          WHERE immi2.immi_person_id = p.pers_person_id
          ORDER BY (immi2.immi_immigration_status_end_date IS NULL) ASC,
                   immi2.immi_immigration_status_start_date DESC
          LIMIT 1
        ),
        'purge', false
      ),

      'health_and_wellbeing', jsonb_build_object(
        'sdq_assessments', COALESCE(sdq.sdq_array_json, '[]'::jsonb),
        'purge', false
      ),

      'social_care_episodes', COALESCE(sce.episodes_array_json, '[]'::jsonb)
    ) AS json_payload

  FROM ssd_person p

  -- disabilities -> JSON array of short codes
  LEFT JOIN LATERAL (
    SELECT
      COALESCE(
        jsonb_agg(code ORDER BY code),
        '[]'::jsonb
      ) AS disabilities_json
    FROM (
      SELECT DISTINCT upper(substr(btrim(d2.disa_disability_code), 1, 4)) AS code
      FROM ssd_disability d2
      WHERE d2.disa_person_id = p.pers_person_id
        AND d2.disa_disability_code IS NOT NULL
        AND btrim(d2.disa_disability_code) <> ''
    ) x
  ) disab ON true

  -- sdq -> JSON array
  LEFT JOIN LATERAL (
    SELECT
      jsonb_agg(
        jsonb_build_object(
          'date',  to_char(csdq.csdq_sdq_completed_date, 'YYYY-MM-DD'),
          'score', (csdq.csdq_sdq_score)::INT
        )
        ORDER BY csdq.csdq_sdq_completed_date DESC
      ) AS sdq_array_json
    FROM ssd_sdq_scores csdq
    WHERE csdq.csdq_person_id = p.pers_person_id
      AND csdq.csdq_sdq_completed_date IS NOT NULL
      AND csdq.csdq_sdq_completed_date > DATE '1900-01-01'
      AND csdq.csdq_sdq_score ~ '^\d+$'
  ) sdq ON true

  -- episodes -> JSON array with nested arrays
  LEFT JOIN LATERAL (
    SELECT
      jsonb_agg(episode_obj ORDER BY COALESCE(cine.cine_referral_date, DATE '0001-01-01')) AS episodes_array_json
    FROM (
      SELECT
        jsonb_build_object(
          'social_care_episode_id', NULLIF(cine.cine_referral_id::TEXT, ''),
          'referral_date', CASE WHEN cine.cine_referral_date IS NULL THEN NULL ELSE to_char(cine.cine_referral_date, 'YYYY-MM-DD') END,
          'referral_source', NULLIF(left(COALESCE(cine.cine_referral_source_code, ''), 2), ''),
          'referral_no_further_action_flag',
            CASE
              WHEN COALESCE(cine.cine_referral_nfa::TEXT, '') ~* '^(1|true|y|t)$' THEN true
              WHEN COALESCE(cine.cine_referral_nfa::TEXT, '') ~* '^(0|false|n|f)$' THEN false
              ELSE NULL
            END,

          'care_worker_details', COALESCE(
            (
              SELECT jsonb_agg(
                       jsonb_build_object(
                         'worker_id', NULLIF(left(pr.prof_staff_id::TEXT, 12), ''),
                         'start_date', CASE WHEN i.invo_involvement_start_date IS NULL THEN NULL ELSE to_char(i.invo_involvement_start_date, 'YYYY-MM-DD') END,
                         'end_date',   CASE WHEN i.invo_involvement_end_date   IS NULL THEN NULL ELSE to_char(i.invo_involvement_end_date,   'YYYY-MM-DD') END
                       )
                       ORDER BY i.invo_involvement_start_date DESC
                     )
              FROM ssd_involvements i
              JOIN ssd_professionals pr
                ON i.invo_professional_id = pr.prof_professional_id
              WHERE i.invo_referral_id = cine.cine_referral_id
            ),
            '[]'::jsonb
          ),

          'child_and_family_assessments', COALESCE(
            (
              SELECT jsonb_agg(
                       jsonb_build_object(
                         'child_and_family_assessment_id', NULLIF(ca.cina_assessment_id::TEXT, ''),
                         'start_date',        CASE WHEN ca.cina_assessment_start_date IS NULL THEN NULL ELSE to_char(ca.cina_assessment_start_date, 'YYYY-MM-DD') END,
                         'authorisation_date',CASE WHEN ca.cina_assessment_auth_date  IS NULL THEN NULL ELSE to_char(ca.cina_assessment_auth_date,  'YYYY-MM-DD') END,
                         'factors', COALESCE(af.cinf_assessment_factors_json::jsonb, '[]'::jsonb),
                         'purge', false
                       )
                     )
              FROM ssd_cin_assessments ca
              LEFT JOIN ssd_assessment_factors af
                ON af.cinf_assessment_id = ca.cina_assessment_id
              WHERE ca.cina_referral_id = cine.cine_referral_id
            ),
            '[]'::jsonb
          ),

          'child_in_need_plans', COALESCE(
            (
              SELECT jsonb_agg(
                       jsonb_build_object(
                         'child_in_need_plan_id', NULLIF(cinp.cinp_cin_plan_id::TEXT, ''),
                         'start_date', CASE WHEN cinp.cinp_cin_plan_start_date IS NULL THEN NULL ELSE to_char(cinp.cinp_cin_plan_start_date, 'YYYY-MM-DD') END,
                         'end_date',   CASE WHEN cinp.cinp_cin_plan_end_date   IS NULL THEN NULL ELSE to_char(cinp.cinp_cin_plan_end_date,   'YYYY-MM-DD') END,
                         'purge', false
                       )
                     )
              FROM ssd_cin_plans cinp
              WHERE cinp.cinp_referral_id = cine.cine_referral_id
            ),
            '[]'::jsonb
          ),

          'section_47_assessments', COALESCE(
            (
              SELECT jsonb_agg(
                       jsonb_build_object(
                         'section_47_assessment_id', NULLIF(s47e.s47e_s47_enquiry_id::TEXT, ''),
                         'start_date', CASE WHEN s47e.s47e_s47_start_date IS NULL THEN NULL ELSE to_char(s47e.s47e_s47_start_date, 'YYYY-MM-DD') END,
                         'icpc_required_flag', CASE
                           WHEN s47e.s47e_s47_outcome_json IS NULL THEN NULL
                           WHEN position('"CP_CONFERENCE_FLAG":"Y"' in s47e.s47e_s47_outcome_json) > 0
                                OR position('"CP_CONFERENCE_FLAG":"1"' in s47e.s47e_s47_outcome_json) > 0 THEN true
                           WHEN position('"CP_CONFERENCE_FLAG":"N"' in s47e.s47e_s47_outcome_json) > 0
                                OR position('"CP_CONFERENCE_FLAG":"0"' in s47e.s47e_s47_outcome_json) > 0 THEN false
                           ELSE NULL
                         END,
                         'icpc_date', CASE WHEN icpc.icpc_icpc_date IS NULL THEN NULL ELSE to_char(icpc.icpc_icpc_date, 'YYYY-MM-DD') END,
                         'end_date', CASE WHEN s47e.s47e_s47_end_date IS NULL THEN NULL ELSE to_char(s47e.s47e_s47_end_date, 'YYYY-MM-DD') END,
                         'purge', false
                       )
                     )
              FROM ssd_s47_enquiry s47e
              LEFT JOIN ssd_initial_cp_conference icpc
                ON icpc.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
              WHERE s47e.s47e_referral_id = cine.cine_referral_id
            ),
            '[]'::jsonb
          ),

          'child_protection_plans', COALESCE(
            (
              SELECT jsonb_agg(
                       jsonb_build_object(
                         'child_protection_plan_id', NULLIF(cppl.cppl_cp_plan_id::TEXT, ''),
                         'start_date', CASE WHEN cppl.cppl_cp_plan_start_date IS NULL THEN NULL ELSE to_char(cppl.cppl_cp_plan_start_date, 'YYYY-MM-DD') END,
                         'end_date',   CASE WHEN cppl.cppl_cp_plan_end_date   IS NULL THEN NULL ELSE to_char(cppl.cppl_cp_plan_end_date,   'YYYY-MM-DD') END,
                         'purge', false
                       )
                     )
              FROM ssd_cp_plans cppl
              WHERE cppl.cppl_referral_id = cine.cine_referral_id
            ),
            '[]'::jsonb
          ),

          'child_looked_after_placements', COALESCE(
            (
              SELECT jsonb_agg(
                       jsonb_build_object(
                         'child_looked_after_placement_id', NULLIF(clap.clap_cla_placement_id::TEXT, ''),
                         'start_date',   CASE WHEN clap.clap_cla_placement_start_date IS NULL THEN NULL ELSE to_char(clap.clap_cla_placement_start_date, 'YYYY-MM-DD') END,
                         'start_reason', NULLIF(left(COALESCE(clae.clae_cla_episode_start_reason, ''), 1), ''),
                         'placement_type', NULLIF(left(COALESCE(clap.clap_cla_placement_type, ''), 2), ''),
                         'postcode', NULLIF(left(COALESCE(clap.clap_cla_placement_postcode, ''), 8), ''),
                         'end_date',     CASE WHEN clap.clap_cla_placement_end_date IS NULL THEN NULL ELSE to_char(clap.clap_cla_placement_end_date, 'YYYY-MM-DD') END,
                         'end_reason',   NULLIF(left(COALESCE(clae.clae_cla_episode_ceased_reason, ''), 3), ''),
                         'change_reason',NULLIF(left(COALESCE(clap.clap_cla_placement_change_reason, ''), 6), ''),
                         'purge', false
                       )
                       ORDER BY clap.clap_cla_placement_start_date DESC
                     )
              FROM ssd_cla_episodes clae
              JOIN ssd_cla_placement clap
                ON clap.clap_cla_id = clae.clae_cla_id
              WHERE clae.clae_referral_id = cine.cine_referral_id
            ),
            '[]'::jsonb
          ),

          'adoption', (
            SELECT to_jsonb(ROW) FROM (
              SELECT
                CASE WHEN perm.perm_adm_decision_date IS NULL THEN NULL ELSE to_char(perm.perm_adm_decision_date, 'YYYY-MM-DD') END AS initial_decision_date,
                CASE WHEN perm.perm_matched_date        IS NULL THEN NULL ELSE to_char(perm.perm_matched_date,        'YYYY-MM-DD') END AS matched_date,
                CASE WHEN perm.perm_placed_for_adoption_date IS NULL THEN NULL ELSE to_char(perm.perm_placed_for_adoption_date, 'YYYY-MM-DD') END AS placed_date,
                false AS purge
            ) AS t( initial_decision_date, matched_date, placed_date, purge )
            FROM ssd_permanence perm
            WHERE perm.perm_person_id = p.pers_person_id
               OR perm.perm_cla_id IN (
                 SELECT clae2.clae_cla_id
                 FROM ssd_cla_episodes clae2
                 WHERE clae2.clae_person_id = p.pers_person_id
               )
            ORDER BY COALESCE(perm.perm_placed_for_adoption_date, perm.perm_matched_date, perm.perm_adm_decision_date) DESC
            LIMIT 1
          ),

          'care_leavers', (
            SELECT to_jsonb(ROW) FROM (
              SELECT
                CASE WHEN clea.clea_care_leaver_latest_contact IS NULL THEN NULL ELSE to_char(clea.clea_care_leaver_latest_contact, 'YYYY-MM-DD') END AS contact_date,
                NULLIF(left(COALESCE(clea.clea_care_leaver_activity, ''), 2), '') AS activity,
                NULLIF(left(COALESCE(clea.clea_care_leaver_accommodation, ''), 1), '') AS accommodation,
                false AS purge
            ) AS t( contact_date, activity, accommodation, purge )
            FROM ssd_care_leavers clea
            WHERE clea.clea_person_id = p.pers_person_id
            ORDER BY clea.clea_care_leaver_latest_contact DESC
            LIMIT 1
          ),

          'closure_date',  CASE WHEN cine.cine_close_date IS NULL THEN NULL ELSE to_char(cine.cine_close_date, 'YYYY-MM-DD') END,
          'closure_reason', NULLIF(left(COALESCE(cine.cine_close_reason, ''), 3), ''),
          'purge', false
        ) AS episode_obj
      FROM ssd_cin_episodes cine
      WHERE cine.cine_person_id = p.pers_person_id
    ) ep
  ) sce ON true
),
hashed AS (
  SELECT
    person_id,
    json_payload,
    digest(json_payload::TEXT, 'sha256') AS current_hash
  FROM raw
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
  'Pending',
  CASE WHEN prev.current_hash IS NULL THEN 'New' ELSE 'Updated' END,
  now()
FROM hashed h
LEFT JOIN LATERAL (
  SELECT s.json_payload, s.current_hash
  FROM ssd_api_data_staging s
  WHERE s.person_id = h.person_id
  ORDER BY s.id DESC
  LIMIT 1
) prev ON true
WHERE prev.current_hash IS NULL OR prev.current_hash <> h.current_hash;

COMMIT;

-- =============================================================================
-- Seed ANON table with example rows
-- =============================================================================

TRUNCATE TABLE ssd_api_data_staging_anon RESTART IDENTITY;

-- Record 1: Pending
INSERT INTO ssd_api_data_staging_anon
(
  person_id,
  previous_json_payload,
  json_payload,
  partial_json_payload,
  previous_hash,
  current_hash,
  row_state,
  last_updated,
  submission_status,
  api_response,
  submission_timestamp
)
VALUES
(
  'C001',
  NULL,
  '{
    "la_child_id": "Child2234",
    "mis_child_id": "Supplier-Child-2234",
    "purge": false,
    "child_details": {
      "unique_pupil_number": "JKL0123456789",
      "former_unique_pupil_number": "MNO0123456789",
      "date_of_birth": "2004-09-23",
      "sex": "F",
      "ethnicity": "B2",
      "postcode": "BN147ES",
      "purge": false
    },
    "health_and_wellbeing": { "purge": false },
    "social_care_episodes": [
      {
        "social_care_episode_id": "13423",
        "referral_date": "2005-02-11",
        "referral_source": "10",
        "care_worker_details": [
          { "worker_id": "X3323345", "start_date": "2024-01-11" },
          { "worker_id": "Y2234567", "start_date": "2022-01-22" },
          { "worker_id": "Z2235432", "start_date": "2022-09-20", "end_date": "2024-10-21" },
          { "worker_id": "X2234852", "start_date": "2020-04-12" }
        ],
        "child_and_family_assessments": [
          {
            "child_and_family_assessment_id": "BCD123456",
            "start_date": "2022-06-14",
            "authorisation_date": "2022-06-14",
            "factors": ["1C", "4A"],
            "purge": false
          }
        ],
        "child_looked_after_placements": [
          {
            "child_looked_after_placement_id": "BCD123456",
            "start_date": "2011-02-10",
            "start_reason": "S",
            "end_date": "2021-11-11",
            "end_reason": "E17",
            "placement_type": "U4",
            "postcode": "BN14 7ES",
            "change_reason": "SSD_PH",
            "purge": false
          }
        ],
        "care_leavers": {
          "contact_date": "2024-08-11",
          "activity": "F2",
          "accommodation": "Z",
          "purge": false
        },
        "purge": false
      }
    ]
  }'::jsonb,
  NULL,
  NULL,
  digest('{
    "la_child_id": "Child2234",
    "mis_child_id": "Supplier-Child-2234",
    "purge": false,
    "child_details": {
      "unique_pupil_number": "JKL0123456789",
      "former_unique_pupil_number": "MNO0123456789",
      "date_of_birth": "2004-09-23",
      "sex": "F",
      "ethnicity": "B2",
      "postcode": "BN147ES",
      "purge": false
    },
    "health_and_wellbeing": { "purge": false },
    "social_care_episodes": [
      {
        "social_care_episode_id": "13423",
        "referral_date": "2005-02-11",
        "referral_source": "10",
        "care_worker_details": [
          { "worker_id": "X3323345", "start_date": "2024-01-11" },
          { "worker_id": "Y2234567", "start_date": "2022-01-22" },
          { "worker_id": "Z2235432", "start_date": "2022-09-20", "end_date": "2024-10-21" },
          { "worker_id": "X2234852", "start_date": "2020-04-12" }
        ],
        "child_and_family_assessments": [
          {
            "child_and_family_assessment_id": "BCD123456",
            "start_date": "2022-06-14",
            "authorisation_date": "2022-06-14",
            "factors": ["1C", "4A"],
            "purge": false
          }
        ],
        "child_looked_after_placements": [
          {
            "child_looked_after_placement_id": "BCD123456",
            "start_date": "2011-02-10",
            "start_reason": "S",
            "end_date": "2021-11-11",
            "end_reason": "E17",
            "placement_type": "U4",
            "postcode": "BN14 7ES",
            "change_reason": "SSD_PH",
            "purge": false
          }
        ],
        "care_leavers": {
          "contact_date": "2024-08-11",
          "activity": "F2",
          "accommodation": "Z",
          "purge": false
        },
        "purge": false
      }
    ]
  }', 'sha256'),
  'New',
  now(),
  'Pending',
  NULL,
  now()
);

-- Record 2: Error
INSERT INTO ssd_api_data_staging_anon
(
  person_id,
  previous_json_payload,
  json_payload,
  partial_json_payload,
  previous_hash,
  current_hash,
  row_state,
  last_updated,
  submission_status,
  api_response,
  submission_timestamp
)
VALUES
(
  'C002',
  NULL,
  '{
    "la_child_id": "Child3234",
    "mis_child_id": "Supplier-Child-3234",
    "purge": false,
    "child_details": {
      "unique_pupil_number": "PQR0123456789",
      "former_unique_pupil_number": "STU0123456789",
      "date_of_birth": "2005-10-10",
      "sex": "M",
      "ethnicity": "C3",
      "postcode": "BN147ES",
      "purge": false
    },
    "health_and_wellbeing": { "purge": false },
    "social_care_episodes": [
      {
        "social_care_episode_id": "23423",
        "referral_date": "2006-03-01",
        "referral_source": "20",
        "care_worker_details": [
          { "worker_id": "X4323345", "start_date": "2023-01-11" },
          { "worker_id": "Y3234567", "start_date": "2022-02-22" }
        ],
        "child_and_family_assessments": [
          {
            "child_and_family_assessment_id": "CDE123456",
            "start_date": "2021-06-14",
            "authorisation_date": "2021-06-14",
            "factors": ["1C"],
            "purge": false
          }
        ],
        "child_looked_after_placements": [],
        "care_leavers": {
          "contact_date": "2024-09-11",
          "activity": "E2",
          "accommodation": "A",
          "purge": false
        },
        "purge": false
      }
    ]
  }'::jsonb,
  NULL,
  NULL,
  digest('{
    "la_child_id": "Child3234",
    "mis_child_id": "Supplier-Child-3234",
    "purge": false
  }', 'sha256'),  -- previous_hash not known, use placeholder for demo
  digest('{
    "la_child_id": "Child3234",
    "mis_child_id": "Supplier-Child-3234",
    "purge": false,
    "child_details": {
      "unique_pupil_number": "PQR0123456789",
      "former_unique_pupil_number": "STU0123456789",
      "date_of_birth": "2005-10-10",
      "sex": "M",
      "ethnicity": "C3",
      "postcode": "BN147ES",
      "purge": false
    },
    "health_and_wellbeing": { "purge": false },
    "social_care_episodes": [
      {
        "social_care_episode_id": "23423",
        "referral_date": "2006-03-01",
        "referral_source": "20",
        "care_worker_details": [
          { "worker_id": "X4323345", "start_date": "2023-01-11" },
          { "worker_id": "Y3234567", "start_date": "2022-02-22" }
        ],
        "child_and_family_assessments": [
          {
            "child_and_family_assessment_id": "CDE123456",
            "start_date": "2021-06-14",
            "authorisation_date": "2021-06-14",
            "factors": ["1C"],
            "purge": false
          }
        ],
        "child_looked_after_placements": [],
        "care_leavers": {
          "contact_date": "2024-09-11",
          "activity": "E2",
          "accommodation": "A",
          "purge": false
        },
        "purge": false
      }
    ]
  }', 'sha256'),
  'New',
  now(),
  'Error',
  'HTTP 400: Validation failed - missing expected field',
  now()
);

-- Record 3: Sent (with previous payload and hash)
INSERT INTO ssd_api_data_staging_anon
(
  person_id,
  previous_json_payload,
  json_payload,
  partial_json_payload,
  previous_hash,
  current_hash,
  row_state,
  last_updated,
  submission_status,
  api_response,
  submission_timestamp
)
VALUES
(
  'C003',
  '{"la_child_id":"Child4234","mis_child_id":"Supplier-Child-4234","purge":false}'::jsonb,
  '{
    "la_child_id": "Child4234",
    "mis_child_id": "Supplier-Child-4234",
    "purge": false,
    "child_details": {
      "unique_pupil_number": "VWX0123456789",
      "former_unique_pupil_number": "YZA0123456789",
      "date_of_birth": "2006-05-05",
      "sex": "M",
      "ethnicity": "D4",
      "postcode": "BN147ES",
      "purge": false
    },
    "health_and_wellbeing": { "purge": false },
    "social_care_episodes": [
      {
        "social_care_episode_id": "33423",
        "referral_date": "2007-01-15",
        "referral_source": "30",
        "care_worker_details": [
          { "worker_id": "X5323345", "start_date": "2024-01-11" }
        ],
        "child_and_family_assessments": [],
        "child_looked_after_placements": [],
        "care_leavers": {
          "contact_date": "2024-07-11",
          "activity": "H2",
          "accommodation": "B",
          "purge": false
        },
        "purge": false
      }
    ]
  }'::jsonb,
  NULL,
  digest('{"la_child_id":"Child4234","mis_child_id":"Supplier-Child-4234","purge":false}', 'sha256'),
  digest('{
    "la_child_id": "Child4234",
    "mis_child_id": "Supplier-Child-4234",
    "purge": false,
    "child_details": {
      "unique_pupil_number": "VWX0123456789",
      "former_unique_pupil_number": "YZA0123456789",
      "date_of_birth": "2006-05-05",
      "sex": "M",
      "ethnicity": "D4",
      "postcode": "BN147ES",
      "purge": false
    },
    "health_and_wellbeing": { "purge": false },
    "social_care_episodes": [
      {
        "social_care_episode_id": "33423",
        "referral_date": "2007-01-15",
        "referral_source": "30",
        "care_worker_details": [
          { "worker_id": "X5323345", "start_date": "2024-01-11" }
        ],
        "child_and_family_assessments": [],
        "child_looked_after_placements": [],
        "care_leavers": {
          "contact_date": "2024-07-11",
          "activity": "H2",
          "accommodation": "B",
          "purge": false
        },
        "purge": false
      }
    ]
  }', 'sha256'),
  'Unchanged',
  now(),
  'Sent',
  'HTTP 201: Created',
  now()
);

-- Verification or sanity checks
SELECT * FROM ssd_api_data_staging LIMIT 5;
SELECT * FROM ssd_api_data_staging_anon LIMIT 5;
