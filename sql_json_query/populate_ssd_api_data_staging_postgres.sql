-- PostgreSQL compatible version of CSC API staging build
-- Target: PostgreSQL 13 plus
-- Notes: enable pgcrypto for SHA256 hashes, use jsonb for payloads, use LATERAL for subqueries
-- Switch database manually if needed, for example in psql use \c db_name

/* ==========================================================================
   D2I CSC API Payload Builder, SQL Server 2016+ compatible
   ========================================================================== */


/* Note for: Daily Data Flows Early Adopters
The following table definitions (and populating) can only be run <after> the main SSD script, OR the following definitions
can be appended into the main SSD and run as one - insert locations within the SSD are marked via the meta tags of:

-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging"}
-- =============================================================================
&
-- META-CONTAINER: {"type": "table", "name": "ssd_api_data_staging_anon"}
-- =============================================================================

*/

-- Data pre/smoke test validator(s) (optional) --
-- D2I offers a seperate <simplified> validation VIEW towards your local data verification checks,
-- this offers some pre-process comparison between your data and the DfE API payload schema 
-- File: (T-SQL 2016+ only)https://github.com/data-to-insight/dfe-csc-api-data-flows/tree/main/pre_flight_checks/ssd_vw_csc_api_schema_checks.sql
-- -- 



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

/* === Payload builder Postgres 13+ compatible === */
BEGIN;

/* === EA Spec window dynamic, 24 months back to FY start on 1 April === */
WITH settings AS (
  SELECT
    CURRENT_DATE::date AS run_date,
    24::int            AS months_back,
    4::int             AS fy_start_month
),
win AS (
  SELECT
    (run_date - make_interval(months => months_back))::date AS anchor,
    run_date,
    fy_start_month
  FROM settings
),
window AS (
  SELECT
    make_date(
      extract(year from anchor)::int
      - CASE WHEN extract(month from anchor) < fy_start_month THEN 1 ELSE 0 END,
      fy_start_month,
      1
    )                       AS ea_cohort_window_start,
    (run_date + INTERVAL '1 day')::date AS ea_cohort_window_end   /* exclusive end */
  FROM win
),

raw AS (
  SELECT
    p.pers_person_id::varchar(48) AS person_id,

    /* ---------- top level object: 2.., purge as 3rd ---------- */
    (
      /* base 2, 3, then append the rest in order using || */
      jsonb_build_object(
        'la_child_id',  left(p.pers_person_id::text, 36)                                    -- 2
      , 'mis_child_id', left(coalesce(nullif(p.pers_single_unique_id, ''), 'SSD_SUI'), 36)  
      , 'purge', false                                                                       -- top level purge
      )

      /* child_details 3..15, ordered, omit null keys */
      || jsonb_build_object(
           'child_details',
           (
             jsonb_build_object(
               'sex', case when p.pers_sex in ('M','F') then p.pers_sex else 'U' end         -- 10
             )
             || case when nullif(btrim(p.pers_upn), '') is not null
                     then jsonb_build_object('unique_pupil_number', p.pers_upn)              -- 3
                     else '{}'::jsonb end
             || coalesce((
                  select jsonb_build_object('former_unique_pupil_number', li.link_identifier_value)
                  from ssd_linked_identifiers li
                  where li.link_person_id = p.pers_person_id
                    and li.link_identifier_type = 'Former Unique Pupil Number'
                    and length(li.link_identifier_value) = 13
                    and li.link_identifier_value ~ '^\d{13}$'
                  order by li.link_valid_from_date desc
                  limit 1
                ), '{}'::jsonb)                                                              -- 4
             || case when nullif(btrim(coalesce(p.pers_upn_unknown,'')), '') is not null
                     then jsonb_build_object('unique_pupil_number_unknown_reason', left(p.pers_upn_unknown, 3))  -- 5
                     else '{}'::jsonb end
             || case when nullif(p.pers_forename, '') is not null
                     then jsonb_build_object('first_name', replace(p.pers_forename, '"', '\"'))  -- 6
                     else '{}'::jsonb end
             || case when nullif(p.pers_surname, '') is not null
                     then jsonb_build_object('surname',    replace(p.pers_surname,  '"', '\"'))  -- 7
                     else '{}'::jsonb end
             || case when p.pers_dob is not null
                     then jsonb_build_object('date_of_birth', to_char(p.pers_dob, 'YYYY-MM-DD')) -- 8
                     else '{}'::jsonb end
             || case when p.pers_expected_dob is not null
                     then jsonb_build_object('expected_date_of_birth', to_char(p.pers_expected_dob, 'YYYY-MM-DD')) -- 9
                     else '{}'::jsonb end
             || case when nullif(btrim(coalesce(p.pers_ethnicity,'')), '') is not null
                     then jsonb_build_object('ethnicity', left(p.pers_ethnicity, 4))            -- 11
                     else '{}'::jsonb end
             || case when disab.disabilities_json is not null
                     then jsonb_build_object('disabilities', disab.disabilities_json)           -- 12
                     else '{}'::jsonb end
             || coalesce((
                  select case when nullif(btrim(a.addr_address_postcode), '') is not null
                              then jsonb_build_object('postcode', a.addr_address_postcode)
                              else null end
                  from (
                    select a.addr_address_postcode
                    from ssd_address a
                    where a.addr_person_id = p.pers_person_id
                    order by a.addr_address_start_date desc
                    limit 1
                  ) a
                ), '{}'::jsonb)                                                                -- 13
             || jsonb_build_object(
                  'uasc_flag',
                  exists(
                    select 1
                    from ssd_immigration_status s
                    where s.immi_person_id = p.pers_person_id
                      and coalesce(s.immi_immigration_status,'') ilike '%UASC%'
                  )
                )                                                                              -- 14
             || coalesce((
                  select case when s2.immi_immigration_status_end_date is not null
                              then jsonb_build_object('uasc_end_date', to_char(s2.immi_immigration_status_end_date, 'YYYY-MM-DD'))
                              else null end
                  from (
                    select *
                    from ssd_immigration_status s2
                    where s2.immi_person_id = p.pers_person_id
                    order by (s2.immi_immigration_status_end_date is null) asc,
                             s2.immi_immigration_status_start_date desc
                    limit 1
                  ) s2
                ), '{}'::jsonb)                                                                -- 15
             || jsonb_build_object('purge', false)
           )
         )

      /* health_and_wellbeing 45..46, omit whole block if NULL */
      || case when sdq.has_sdq
              then jsonb_build_object(
                     'health_and_wellbeing',
                     jsonb_build_object(
                       'sdq_assessments', sdq.sdq_array_json                                   -- 45, 46
                     , 'purge', false
                     )
                   )
              else '{}'::jsonb end

      /* social_care_episodes 16..44, 47..55, empty arrays and objects omitted */
      || jsonb_build_object('social_care_episodes', coalesce(sce.episodes_array_json, '[]'::jsonb))
    ) AS json_payload

  FROM ssd_person p
  CROSS JOIN window w   /* expose w.ea_cohort_window_start and w.ea_cohort_window_end */

  /* disabilities array, return NULL if empty */
  left join lateral (
    select nullif(jsonb_agg(code order by code), '[]'::jsonb) as disabilities_json
    from (
      select distinct upper(substr(btrim(d2.disa_disability_code), 1, 4)) as code
      from ssd_disability d2
      where d2.disa_person_id = p.pers_person_id
        and d2.disa_disability_code is not null
        and btrim(d2.disa_disability_code) <> ''
    ) x
  ) disab on true

  /* SDQs prebuild filtered to EA window */
  left join lateral (
    select
      coalesce(
        (
          select jsonb_agg(
                   jsonb_build_object(
                     'date',  to_char(csdq.csdq_sdq_completed_date, 'YYYY-MM-DD')              -- 45
                   , 'score', (csdq.csdq_sdq_score)::int                                       -- 46
                   )
                   order by csdq.csdq_sdq_completed_date desc
                 )
          from ssd_sdq_scores csdq
          where csdq.csdq_person_id = p.pers_person_id
            and csdq.csdq_sdq_score ~ '^\d+$'
            and csdq.csdq_sdq_completed_date >= w.ea_cohort_window_start
            and csdq.csdq_sdq_completed_date <  w.ea_cohort_window_end
        ),
        '[]'::jsonb
      ) as sdq_array_json,
      exists(
        select 1
        from ssd_sdq_scores csdq
        where csdq.csdq_person_id = p.pers_person_id
          and csdq.csdq_sdq_score ~ '^\d+$'
          and csdq.csdq_sdq_completed_date >= w.ea_cohort_window_start
          and csdq.csdq_sdq_completed_date <  w.ea_cohort_window_end
      ) as has_sdq
  ) sdq on true

  /* episodes and nested blocks, all EA window rules applied */
  left join lateral (
    select
      jsonb_agg(ep.episode_obj order by coalesce(ep.referral_date_sort, date '0001-01-01')) as episodes_array_json
    from (
      select
        cine.cine_referral_date as referral_date_sort,
        /* episode base with ordered keys 16..18 */
        (
          jsonb_build_object(
            'social_care_episode_id', nullif(cine.cine_referral_id::text, '')                         -- 16
          , 'referral_date', case when cine.cine_referral_date is null
                                   then null else to_char(cine.cine_referral_date, 'YYYY-MM-DD') end  -- 17
          , 'referral_source', nullif(left(coalesce(cine.cine_referral_source_code,''), 2), '')       -- 18
          )

          /* closure_date */                                                                          -- 19
          || case when cine.cine_close_date is not null
                  then jsonb_build_object('closure_date', to_char(cine.cine_close_date, 'YYYY-MM-DD'))
                  else '{}'::jsonb end

          /* closure_reason */                                                                        -- 20
          || case when nullif(left(coalesce(cine.cine_close_reason,''), 3), '') is not null
                  then jsonb_build_object('closure_reason', left(cine.cine_close_reason, 3))
                  else '{}'::jsonb end

          /* referral_no_further_action_flag, include only when mappable */                           -- 21
          || case
               when coalesce(cine.cine_referral_nfa::text,'') ~* '^(1|true|y|t)$'
                 then jsonb_build_object('referral_no_further_action_flag', true)
               when coalesce(cine.cine_referral_nfa::text,'') ~* '^(0|false|n|f)$'
                 then jsonb_build_object('referral_no_further_action_flag', false)
               else '{}'::jsonb
             end

          /* 22..25 child_and_family_assessments filtered to EA window on start or auth date */
          || coalesce((
               select case when caf.arr is not null
                           then jsonb_build_object('child_and_family_assessments', caf.arr)
                           else null end
               from (
                 select nullif(
                          jsonb_agg(
                            jsonb_strip_nulls(
                              jsonb_build_object(
                                'child_and_family_assessment_id', nullif(ca.cina_assessment_id::text, '')                             -- 22
                              ) ||
                              case when ca.cina_assessment_start_date is not null
                                   then jsonb_build_object('start_date', to_char(ca.cina_assessment_start_date, 'YYYY-MM-DD'))        -- 23
                                   else '{}'::jsonb end
                              || case when ca.cina_assessment_auth_date is not null
                                   then jsonb_build_object('authorisation_date', to_char(ca.cina_assessment_auth_date, 'YYYY-MM-DD')) -- 24
                                   else '{}'::jsonb end
                              || coalesce(
                                   case
                                     when af.cinf_assessment_factors_json is not null
                                          and btrim(af.cinf_assessment_factors_json) <> ''
                                          and af.cinf_assessment_factors_json::jsonb <> '[]'::jsonb
                                     then jsonb_build_object('factors', af.cinf_assessment_factors_json::jsonb)                       -- 25
                                     else null
                                   end,
                                   '{}'::jsonb
                                 )
                              || jsonb_build_object('purge', false)
                            )
                          ), '[]'::jsonb
                        ) as arr
                 from ssd_cin_assessments ca
                 left join ssd_assessment_factors af
                   on af.cinf_assessment_id = ca.cina_assessment_id
                 where ca.cina_referral_id = cine.cine_referral_id
                   and (
                         ca.cina_assessment_start_date >= w.ea_cohort_window_start
                         and ca.cina_assessment_start_date <  w.ea_cohort_window_end
                       or ca.cina_assessment_auth_date  >= w.ea_cohort_window_start
                         and ca.cina_assessment_auth_date  <  w.ea_cohort_window_end
                   )
               ) caf
             ), '{}'::jsonb)

          /* 26..28 child_in_need_plans overlap EA window */
          || coalesce((
               select case when cin.arr is not null
                           then jsonb_build_object('child_in_need_plans', cin.arr)
                           else null end
               from (
                 select nullif(
                          jsonb_agg(
                            jsonb_strip_nulls(
                              jsonb_build_object(
                                'child_in_need_plan_id', nullif(cinp.cinp_cin_plan_id::text, '')                   -- 26
                              , 'start_date', case when cinp.cinp_cin_plan_start_date is null then null
                                                   else to_char(cinp.cinp_cin_plan_start_date, 'YYYY-MM-DD') end   -- 27
                              , 'end_date',   case when cinp.cinp_cin_plan_end_date   is null then null
                                                   else to_char(cinp.cinp_cin_plan_end_date,   'YYYY-MM-DD') end   -- 28
                              , 'purge', false
                              )
                            )
                            order by cinp.cinp_cin_plan_start_date desc
                          ), '[]'::jsonb
                        ) as arr
                 from ssd_cin_plans cinp
                 where cinp.cinp_referral_id = cine.cine_referral_id
                   and cinp.cinp_cin_plan_start_date <  w.ea_cohort_window_end
                   and (cinp.cinp_cin_plan_end_date is null or cinp.cinp_cin_plan_end_date >= w.ea_cohort_window_start)
               ) cin
             ), '{}'::jsonb)

          /* 29..33 section_47_assessments overlap EA window or ICPC in window */
          || coalesce((
               select case when s47.arr is not null
                           then jsonb_build_object('section_47_assessments', s47.arr)
                           else null end
               from (
                 select nullif(
                          jsonb_agg(
                            jsonb_strip_nulls(
                              jsonb_build_object(
                                'section_47_assessment_id', nullif(s47e.s47e_s47_enquiry_id::text, '')                    -- 29
                              ) ||
                              case when s47e.s47e_s47_start_date is not null
                                   then jsonb_build_object('start_date', to_char(s47e.s47e_s47_start_date, 'YYYY-MM-DD')) -- 30
                                   else '{}'::jsonb end
                              || case
                                   when s47e.s47e_s47_outcome_json is null then '{}'::jsonb
                                   when position('"CP_CONFERENCE_FLAG":"Y"' in s47e.s47e_s47_outcome_json) > 0
                                     or position('"CP_CONFERENCE_FLAG":"T"' in s47e.s47e_s47_outcome_json) > 0
                                     or position('"CP_CONFERENCE_FLAG":"1"' in s47e.s47e_s47_outcome_json) > 0
                                     or position('"CP_CONFERENCE_FLAG":"true"' in s47e.s47e_s47_outcome_json) > 0
                                     or position('"CP_CONFERENCE_FLAG":"True"' in s47e.s47e_s47_outcome_json) > 0
                                     then jsonb_build_object('icpc_required_flag', true)                                  -- 31
                                   when position('"CP_CONFERENCE_FLAG":"N"' in s47e.s47e_s47_outcome_json) > 0
                                     or position('"CP_CONFERENCE_FLAG":"F"' in s47e.s47e_s47_outcome_json) > 0
                                     or position('"CP_CONFERENCE_FLAG":"0"' in s47e.s47e_s47_outcome_json) > 0
                                     or position('"CP_CONFERENCE_FLAG":"false"' in s47e.s47e_s47_outcome_json) > 0
                                     or position('"CP_CONFERENCE_FLAG":"False"' in s47e.s47e_s47_outcome_json) > 0
                                     then jsonb_build_object('icpc_required_flag', false)
                                   else '{}'::jsonb
                                 end
                              || coalesce((
                                   select case when icpc.icpc_icpc_date is not null
                                               then jsonb_build_object('icpc_date', to_char(icpc.icpc_icpc_date, 'YYYY-MM-DD'))
                                               else null end
                                   from (
                                     select i.icpc_icpc_date
                                     from ssd_initial_cp_conference i
                                     where i.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                                       and i.icpc_icpc_date >= w.ea_cohort_window_start            /* EA window */
                                       and i.icpc_icpc_date <  w.ea_cohort_window_end
                                     order by i.icpc_icpc_date desc
                                     limit 1
                                   ) icpc
                                 ), '{}'::jsonb)                                                                          -- 32
                              || case when s47e.s47e_s47_end_date is not null
                                      then jsonb_build_object('end_date', to_char(s47e.s47e_s47_end_date, 'YYYY-MM-DD'))  -- 33
                                      else '{}'::jsonb end
                              || jsonb_build_object('purge', false)
                            )
                          ), '[]'::jsonb
                        ) as arr
                 from ssd_s47_enquiry s47e
                 where s47e.s47e_referral_id = cine.cine_referral_id
                   and (
                        s47e.s47e_s47_start_date <= w.ea_cohort_window_end
                        and (s47e.s47e_s47_end_date is null or s47e.s47e_s47_end_date >= w.ea_cohort_window_start)
                       or exists (
                            select 1 from ssd_initial_cp_conference i
                            where i.icpc_s47_enquiry_id = s47e.s47e_s47_enquiry_id
                              and i.icpc_icpc_date >= w.ea_cohort_window_start
                              and i.icpc_icpc_date <  w.ea_cohort_window_end
                         )
                   )
               ) s47
             ), '{}'::jsonb)

          /* 34..36 child_protection_plans overlap EA window */
          || coalesce((
               select case when cpp.arr is not null
                           then jsonb_build_object('child_protection_plans', cpp.arr)
                           else null end
               from (
                 select nullif(
                          jsonb_agg(
                            jsonb_strip_nulls(
                              jsonb_build_object(
                                'child_protection_plan_id', nullif(cppl.cppl_cp_plan_id::text, '')                        -- 34
                              , 'start_date', case when cppl.cppl_cp_plan_start_date is null then null
                                                   else to_char(cppl.cppl_cp_plan_start_date, 'YYYY-MM-DD') end           -- 35
                              , 'end_date',   case when cppl.cppl_cp_plan_end_date   is null then null
                                                   else to_char(cppl.cppl_cp_plan_end_date,   'YYYY-MM-DD') end           -- 36
                              , 'purge', false
                              )
                            )
                          ), '[]'::jsonb
                        ) as arr
                 from ssd_cp_plans cppl
                 where cppl.cppl_referral_id = cine.cine_referral_id
                   and cppl.cppl_cp_plan_start_date <  w.ea_cohort_window_end
                   and (cppl.cppl_cp_plan_end_date is null or cppl.cppl_cp_plan_end_date >= w.ea_cohort_window_start)
               ) cpp
             ), '{}'::jsonb)

          /* 37..44 child_looked_after_placements overlap EA window */
          || coalesce((
               select case when cla.arr is not null
                           then jsonb_build_object('child_looked_after_placements', cla.arr)
                           else null end
               from (
                 select nullif(
                          jsonb_agg(
                            jsonb_strip_nulls(
                              jsonb_build_object(
                                'child_looked_after_placement_id', nullif(clap.clap_cla_placement_id::text, '')           -- 37
                              , 'start_date', to_char(clap.clap_cla_placement_start_date, 'YYYY-MM-DD')                   -- 38
                              , 'start_reason', nullif(left(coalesce(clae.clae_cla_episode_start_reason,''), 1), '')      -- 39
                              , 'postcode',     nullif(coalesce(clap.clap_cla_placement_postcode,''), '')                 -- 40
                              , 'placement_type', nullif(left(coalesce(clap.clap_cla_placement_type,''), 2), '')          -- 41
                              )
                              || case when clap.clap_cla_placement_end_date is not null
                                      then jsonb_build_object('end_date', to_char(clap.clap_cla_placement_end_date, 'YYYY-MM-DD'))  -- 42
                                      else '{}'::jsonb end
                              || jsonb_build_object(
                                   'end_reason',   nullif(left(coalesce(clae.clae_cla_episode_ceased_reason,''), 3), '')            -- 43
                                 , 'change_reason',nullif(left(coalesce(clap.clap_cla_placement_change_reason,''), 6), '')          -- 44
                                 , 'purge', false
                                 )
                            )
                            order by clap.clap_cla_placement_start_date desc
                          ), '[]'::jsonb
                        ) as arr
                 from ssd_cla_episodes clae
                 join ssd_cla_placement clap on clap.clap_cla_id = clae.clae_cla_id
                 where clae.clae_referral_id = cine.cine_referral_id
                   and clap.clap_cla_placement_start_date <  w.ea_cohort_window_end
                   and (clap.clap_cla_placement_end_date is null or clap.clap_cla_placement_end_date >= w.ea_cohort_window_start)
               ) cla
             ), '{}'::jsonb)

          /* 47..49 adoption filtered to EA window on any permanence date */
          || coalesce((
               select jsonb_build_object('adoption', adopt.obj)
               from (
                 select to_jsonb(row) as obj
                 from (
                   select
                     case when perm.perm_adm_decision_date is null then null else to_char(perm.perm_adm_decision_date, 'YYYY-MM-DD') end as initial_decision_date,      -- 47
                     case when perm.perm_matched_date        is null then null else to_char(perm.perm_matched_date,        'YYYY-MM-DD') end as matched_date,           -- 48
                     case when perm.perm_placed_for_adoption_date is null then null else to_char(perm.perm_placed_for_adoption_date, 'YYYY-MM-DD') end as placed_date,  -- 49
                     false as purge
                 ) as row
                 from ssd_permanence perm
                 where (perm.perm_person_id = p.pers_person_id
                        or perm.perm_cla_id in (
                             select clae2.clae_cla_id
                             from ssd_cla_episodes clae2
                             where clae2.clae_person_id = p.pers_person_id
                           ))
                   and (
                        perm.perm_adm_decision_date        >= w.ea_cohort_window_start and perm.perm_adm_decision_date        < w.ea_cohort_window_end
                     or perm.perm_matched_date             >= w.ea_cohort_window_start and perm.perm_matched_date             < w.ea_cohort_window_end
                     or perm.perm_placed_for_adoption_date >= w.ea_cohort_window_start and perm.perm_placed_for_adoption_date < w.ea_cohort_window_end
                   )
                 order by coalesce(perm.perm_placed_for_adoption_date, perm.perm_matched_date, perm.perm_adm_decision_date) desc
                 limit 1
               ) adopt
             ), '{}'::jsonb)

          /* 50..52 care_leavers, single object in EA window */
          || coalesce((
               select jsonb_build_object('care_leavers', cl.obj)
               from (
                 select to_jsonb(row) as obj
                 from (
                   select
                     case when clea.clea_care_leaver_latest_contact is null then null else to_char(clea.clea_care_leaver_latest_contact,'YYYY-MM-DD') end as contact_date, -- 50
                     nullif(left(coalesce(clea.clea_care_leaver_activity,''), 2), '') as activity,                                -- 51
                     nullif(left(coalesce(clea.clea_care_leaver_accommodation,''), 1), '') as accommodation,                      -- 52
                     false as purge
                 ) as row
                 from ssd_care_leavers clea
                 where clea.clea_person_id = p.pers_person_id
                   and clea.clea_care_leaver_latest_contact >= w.ea_cohort_window_start
                   and clea.clea_care_leaver_latest_contact <  w.ea_cohort_window_end
                 order by clea.clea_care_leaver_latest_contact desc
                 limit 1
               ) cl
             ), '{}'::jsonb)

          /* 53..55 care_worker_details involvement overlaps EA window */
          || coalesce((
               select case when cw.arr is not null
                           then jsonb_build_object('care_worker_details', cw.arr)
                           else null end
               from (
                 select nullif(
                          jsonb_agg(
                            jsonb_strip_nulls(
                              jsonb_build_object(
                                'worker_id',  nullif(left(pr.prof_staff_id::text, 12), '')                           -- 53
                              , 'start_date', to_char(i.invo_involvement_start_date, 'YYYY-MM-DD')                   -- 54
                              , 'end_date',   case when i.invo_involvement_end_date is null then null
                                                   else to_char(i.invo_involvement_end_date, 'YYYY-MM-DD') end       -- 55
                              )
                            )
                            order by i.invo_involvement_start_date desc
                          ), '[]'::jsonb
                        ) as arr
                 from ssd_involvements i
                 join ssd_professionals pr on i.invo_professional_id = pr.prof_professional_id
                 where i.invo_referral_id = cine.cine_referral_id
                   and i.invo_involvement_start_date <  w.ea_cohort_window_end
                   and (i.invo_involvement_end_date is null or i.invo_involvement_end_date >= w.ea_cohort_window_start)
               ) cw
             ), '{}'::jsonb)

          /* episode level purge */
          || jsonb_build_object('purge', false)
        ) as episode_obj

      from ssd_cin_episodes cine
      where cine.cine_person_id = p.pers_person_id
        and cine.cine_referral_date <  w.ea_cohort_window_end
        and (cine.cine_close_date is null or cine.cine_close_date >= w.ea_cohort_window_start)
    ) ep
  ) sce on true
),

hashed AS (
  select
    person_id,
    json_payload,
    digest(json_payload::text, 'sha256') as current_hash
  from raw
)

insert into ssd_api_data_staging
  (person_id, previous_json_payload, json_payload, current_hash, previous_hash,
   submission_status, row_state, last_updated)
select
  h.person_id,
  prev.json_payload as previous_json_payload,
  h.json_payload,
  h.current_hash,
  prev.current_hash as previous_hash,
  'Pending',
  case when prev.current_hash is null then 'New' else 'Updated' end,
  now()
from hashed h
left join lateral (
  select s.json_payload, s.current_hash
  from ssd_api_data_staging s
  where s.person_id = h.person_id
  order by s.id desc
  limit 1
) prev on true
where prev.current_hash is null or prev.current_hash <> h.current_hash;

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
