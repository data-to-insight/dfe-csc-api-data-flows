DECLARE @TableList TABLE (TableName NVARCHAR(255));

INSERT INTO @TableList (TableName)
VALUES
    ('ssd_person'),
    ('ssd_disability'),
    ('ssd_address'),
    ('ssd_immigration_status'),
    ('ssd_ehcp_requests'),
    ('ssd_ehcp_assessment'),
    ('ssd_ehcp_named_plan'),
    ('ssd_cin_episodes'),
    ('ssd_cin_assessments'),
    ('ssd_assessment_factors'),
    ('ssd_cin_plans'),
    ('ssd_s47_enquiry'),
    ('ssd_initial_cp_conference'),
    ('ssd_cp_plans'),
    ('ssd_cla_episodes'),
    ('ssd_cla_placement'),
    ('ssd_sdq_scores'),
    ('ssd_permanence'),
    ('ssd_care_leavers'),
    ('ssd_professionals'),
    ('ssd_involvements'),
    ('ssd_sen_need');

SELECT 
    t.TableName,
    c.COLUMN_NAME AS ColumnName,
    c.DATA_TYPE AS DataType,
    c.CHARACTER_MAXIMUM_LENGTH AS MaxLength
FROM 
    @TableList t
INNER JOIN 
    INFORMATION_SCHEMA.COLUMNS c
    ON c.TABLE_NAME = t.TableName
ORDER BY 
    t.TableName, c.ORDINAL_POSITION;



-- TableName	ColumnName	DataType	MaxLength
-- ssd_address	addr_table_id	nvarchar	48
-- ssd_address	addr_person_id	nvarchar	48
-- ssd_address	addr_address_type	nvarchar	48
-- ssd_address	addr_address_start_date	datetime	NULL
-- ssd_address	addr_address_end_date	datetime	NULL
-- ssd_address	addr_address_postcode	nvarchar	15
-- ssd_address	addr_address_json	nvarchar	1000
-- ssd_assessment_factors	cinf_table_id	nvarchar	48
-- ssd_assessment_factors	cinf_assessment_id	nvarchar	48
-- ssd_assessment_factors	cinf_assessment_factors_json	nvarchar	1000
-- ssd_care_leavers	clea_table_id	nvarchar	48
-- ssd_care_leavers	clea_person_id	nvarchar	48
-- ssd_care_leavers	clea_care_leaver_eligibility	nvarchar	100
-- ssd_care_leavers	clea_care_leaver_in_touch	nvarchar	100
-- ssd_care_leavers	clea_care_leaver_latest_contact	datetime	NULL
-- ssd_care_leavers	clea_care_leaver_accommodation	nvarchar	100
-- ssd_care_leavers	clea_care_leaver_accom_suitable	nvarchar	100
-- ssd_care_leavers	clea_care_leaver_activity	nvarchar	100
-- ssd_care_leavers	clea_pathway_plan_review_date	datetime	NULL
-- ssd_care_leavers	clea_care_leaver_personal_advisor	nvarchar	100
-- ssd_care_leavers	clea_care_leaver_allocated_team	nvarchar	48
-- ssd_care_leavers	clea_care_leaver_worker_id	nvarchar	100
-- ssd_cin_assessments	cina_assessment_id	nvarchar	48
-- ssd_cin_assessments	cina_person_id	nvarchar	48
-- ssd_cin_assessments	cina_referral_id	nvarchar	48
-- ssd_cin_assessments	cina_assessment_start_date	datetime	NULL
-- ssd_cin_assessments	cina_assessment_child_seen	nchar	1
-- ssd_cin_assessments	cina_assessment_auth_date	datetime	NULL
-- ssd_cin_assessments	cina_assessment_outcome_json	nvarchar	1000
-- ssd_cin_assessments	cina_assessment_outcome_nfa	nchar	1
-- ssd_cin_assessments	cina_assessment_team	nvarchar	48
-- ssd_cin_assessments	cina_assessment_worker_id	nvarchar	100
-- ssd_cin_episodes	cine_referral_id	nvarchar	48
-- ssd_cin_episodes	cine_person_id	nvarchar	48
-- ssd_cin_episodes	cine_referral_date	datetime	NULL
-- ssd_cin_episodes	cine_cin_primary_need_code	nvarchar	3
-- ssd_cin_episodes	cine_referral_source_code	nvarchar	48
-- ssd_cin_episodes	cine_referral_source_desc	nvarchar	255
-- ssd_cin_episodes	cine_referral_outcome_json	nvarchar	4000
-- ssd_cin_episodes	cine_referral_nfa	nchar	1
-- ssd_cin_episodes	cine_close_reason	nvarchar	100
-- ssd_cin_episodes	cine_close_date	datetime	NULL
-- ssd_cin_episodes	cine_referral_team	nvarchar	48
-- ssd_cin_episodes	cine_referral_worker_id	nvarchar	100
-- ssd_cin_plans	cinp_cin_plan_id	nvarchar	48
-- ssd_cin_plans	cinp_referral_id	nvarchar	48
-- ssd_cin_plans	cinp_person_id	nvarchar	48
-- ssd_cin_plans	cinp_cin_plan_start_date	datetime	NULL
-- ssd_cin_plans	cinp_cin_plan_end_date	datetime	NULL
-- ssd_cin_plans	cinp_cin_plan_team	nvarchar	48
-- ssd_cin_plans	cinp_cin_plan_worker_id	nvarchar	100
-- ssd_cla_episodes	clae_cla_episode_id	nvarchar	48
-- ssd_cla_episodes	clae_person_id	nvarchar	48
-- ssd_cla_episodes	clae_cla_placement_id	nvarchar	48
-- ssd_cla_episodes	clae_cla_episode_start_date	datetime	NULL
-- ssd_cla_episodes	clae_cla_episode_start_reason	nvarchar	100
-- ssd_cla_episodes	clae_cla_primary_need_code	nvarchar	3
-- ssd_cla_episodes	clae_cla_episode_ceased	datetime	NULL
-- ssd_cla_episodes	clae_cla_episode_ceased_reason	nvarchar	255
-- ssd_cla_episodes	clae_cla_id	nvarchar	48
-- ssd_cla_episodes	clae_referral_id	nvarchar	48
-- ssd_cla_episodes	clae_cla_last_iro_contact_date	datetime	NULL
-- ssd_cla_episodes	clae_entered_care_date	datetime	NULL
-- ssd_cla_placement	clap_cla_placement_id	nvarchar	48
-- ssd_cla_placement	clap_cla_id	nvarchar	48
-- ssd_cla_placement	clap_person_id	nvarchar	48
-- ssd_cla_placement	clap_cla_placement_start_date	datetime	NULL
-- ssd_cla_placement	clap_cla_placement_type	nvarchar	100
-- ssd_cla_placement	clap_cla_placement_urn	nvarchar	48
-- ssd_cla_placement	clap_cla_placement_distance	float	NULL
-- ssd_cla_placement	clap_cla_placement_provider	nvarchar	48
-- ssd_cla_placement	clap_cla_placement_postcode	nvarchar	8
-- ssd_cla_placement	clap_cla_placement_end_date	datetime	NULL
-- ssd_cla_placement	clap_cla_placement_change_reason	nvarchar	100
-- ssd_cp_plans	cppl_cp_plan_id	nvarchar	48
-- ssd_cp_plans	cppl_referral_id	nvarchar	48
-- ssd_cp_plans	cppl_icpc_id	nvarchar	48
-- ssd_cp_plans	cppl_person_id	nvarchar	48
-- ssd_cp_plans	cppl_cp_plan_start_date	datetime	NULL
-- ssd_cp_plans	cppl_cp_plan_end_date	datetime	NULL
-- ssd_cp_plans	cppl_cp_plan_ola	nchar	1
-- ssd_cp_plans	cppl_cp_plan_initial_category	nvarchar	100
-- ssd_cp_plans	cppl_cp_plan_latest_category	nvarchar	100
-- ssd_disability	disa_table_id	nvarchar	48
-- ssd_disability	disa_person_id	nvarchar	48
-- ssd_disability	disa_disability_code	nvarchar	48
-- ssd_ehcp_assessment	ehca_ehcp_assessment_id	nvarchar	48
-- ssd_ehcp_assessment	ehca_ehcp_request_id	nvarchar	48
-- ssd_ehcp_assessment	ehca_ehcp_assessment_outcome_date	datetime	NULL
-- ssd_ehcp_assessment	ehca_ehcp_assessment_outcome	nvarchar	100
-- ssd_ehcp_assessment	ehca_ehcp_assessment_exceptions	nvarchar	100
-- ssd_ehcp_named_plan	ehcn_named_plan_id	nvarchar	48
-- ssd_ehcp_named_plan	ehcn_ehcp_asmt_id	nvarchar	48
-- ssd_ehcp_named_plan	ehcn_named_plan_start_date	datetime	NULL
-- ssd_ehcp_named_plan	ehcn_named_plan_ceased_date	datetime	NULL
-- ssd_ehcp_named_plan	ehcn_named_plan_ceased_reason	nvarchar	100
-- ssd_ehcp_requests	ehcr_ehcp_request_id	nvarchar	48
-- ssd_ehcp_requests	ehcr_send_table_id	nvarchar	48
-- ssd_ehcp_requests	ehcr_ehcp_req_date	datetime	NULL
-- ssd_ehcp_requests	ehcr_ehcp_req_outcome_date	datetime	NULL
-- ssd_ehcp_requests	ehcr_ehcp_req_outcome	nvarchar	100
-- ssd_immigration_status	immi_immigration_status_id	nvarchar	48
-- ssd_immigration_status	immi_person_id	nvarchar	48
-- ssd_immigration_status	immi_immigration_status_start_date	datetime	NULL
-- ssd_immigration_status	immi_immigration_status_end_date	datetime	NULL
-- ssd_immigration_status	immi_immigration_status	nvarchar	100
-- ssd_initial_cp_conference	icpc_icpc_id	nvarchar	48
-- ssd_initial_cp_conference	icpc_icpc_meeting_id	nvarchar	48
-- ssd_initial_cp_conference	icpc_s47_enquiry_id	nvarchar	48
-- ssd_initial_cp_conference	icpc_person_id	nvarchar	48
-- ssd_initial_cp_conference	icpc_cp_plan_id	nvarchar	48
-- ssd_initial_cp_conference	icpc_referral_id	nvarchar	48
-- ssd_initial_cp_conference	icpc_icpc_transfer_in	nchar	1
-- ssd_initial_cp_conference	icpc_icpc_target_date	datetime	NULL
-- ssd_initial_cp_conference	icpc_icpc_date	datetime	NULL
-- ssd_initial_cp_conference	icpc_icpc_outcome_cp_flag	nchar	1
-- ssd_initial_cp_conference	icpc_icpc_outcome_json	nvarchar	1000
-- ssd_initial_cp_conference	icpc_icpc_team	nvarchar	48
-- ssd_initial_cp_conference	icpc_icpc_worker_id	nvarchar	100
-- ssd_involvements	invo_involvements_id	nvarchar	48
-- ssd_involvements	invo_professional_id	nvarchar	48
-- ssd_involvements	invo_professional_role_id	nvarchar	200
-- ssd_involvements	invo_professional_team	nvarchar	48
-- ssd_involvements	invo_person_id	nvarchar	48
-- ssd_involvements	invo_involvement_start_date	datetime	NULL
-- ssd_involvements	invo_involvement_end_date	datetime	NULL
-- ssd_involvements	invo_worker_change_reason	nvarchar	200
-- ssd_involvements	invo_referral_id	nvarchar	48
-- ssd_permanence	perm_table_id	nvarchar	48
-- ssd_permanence	perm_person_id	nvarchar	48
-- ssd_permanence	perm_cla_id	nvarchar	48
-- ssd_permanence	perm_adm_decision_date	datetime	NULL
-- ssd_permanence	perm_part_of_sibling_group	nchar	1
-- ssd_permanence	perm_siblings_placed_together	int	NULL
-- ssd_permanence	perm_siblings_placed_apart	int	NULL
-- ssd_permanence	perm_ffa_cp_decision_date	datetime	NULL
-- ssd_permanence	perm_placement_order_date	datetime	NULL
-- ssd_permanence	perm_matched_date	datetime	NULL
-- ssd_permanence	perm_adopter_sex	nvarchar	48
-- ssd_permanence	perm_adopter_legal_status	nvarchar	100
-- ssd_permanence	perm_number_of_adopters	int	NULL
-- ssd_permanence	perm_placed_for_adoption_date	datetime	NULL
-- ssd_permanence	perm_adopted_by_carer_flag	nchar	1
-- ssd_permanence	perm_placed_foster_carer_date	datetime	NULL
-- ssd_permanence	perm_placed_ffa_cp_date	datetime	NULL
-- ssd_permanence	perm_placement_provider_urn	nvarchar	48
-- ssd_permanence	perm_decision_reversed_date	datetime	NULL
-- ssd_permanence	perm_decision_reversed_reason	nvarchar	100
-- ssd_permanence	perm_permanence_order_date	datetime	NULL
-- ssd_permanence	perm_permanence_order_type	nvarchar	100
-- ssd_permanence	perm_adoption_worker_id	nvarchar	100
-- ssd_person	pers_legacy_id	nvarchar	48
-- ssd_person	pers_person_id	nvarchar	48
-- ssd_person	pers_sex	nvarchar	20
-- ssd_person	pers_gender	nvarchar	10
-- ssd_person	pers_ethnicity	nvarchar	48
-- ssd_person	pers_dob	datetime	NULL
-- ssd_person	pers_common_child_id	nvarchar	48
-- ssd_person	pers_upn_unknown	nvarchar	6
-- ssd_person	pers_send_flag	nchar	5
-- ssd_person	pers_expected_dob	datetime	NULL
-- ssd_person	pers_death_date	datetime	NULL
-- ssd_person	pers_is_mother	nchar	1
-- ssd_person	pers_nationality	nvarchar	48
-- ssd_professionals	prof_professional_id	nvarchar	48
-- ssd_professionals	prof_staff_id	nvarchar	48
-- ssd_professionals	prof_professional_name	nvarchar	300
-- ssd_professionals	prof_social_worker_registration_no	nvarchar	48
-- ssd_professionals	prof_agency_worker_flag	nchar	1
-- ssd_professionals	prof_professional_job_title	nvarchar	500
-- ssd_professionals	prof_professional_caseload	int	NULL
-- ssd_professionals	prof_professional_department	nvarchar	100
-- ssd_professionals	prof_full_time_equivalency	float	NULL
-- ssd_s47_enquiry	s47e_s47_enquiry_id	nvarchar	48
-- ssd_s47_enquiry	s47e_referral_id	nvarchar	48
-- ssd_s47_enquiry	s47e_person_id	nvarchar	48
-- ssd_s47_enquiry	s47e_s47_start_date	datetime	NULL
-- ssd_s47_enquiry	s47e_s47_end_date	datetime	NULL
-- ssd_s47_enquiry	s47e_s47_nfa	nchar	1
-- ssd_s47_enquiry	s47e_s47_outcome_json	nvarchar	1000
-- ssd_s47_enquiry	s47e_s47_completed_by_team	nvarchar	48
-- ssd_s47_enquiry	s47e_s47_completed_by_worker_id	nvarchar	100
-- ssd_sdq_scores	csdq_table_id	nvarchar	48
-- ssd_sdq_scores	csdq_person_id	nvarchar	48
-- ssd_sdq_scores	csdq_sdq_completed_date	datetime	NULL
-- ssd_sdq_scores	csdq_sdq_score	int	NULL
-- ssd_sdq_scores	csdq_sdq_reason	nvarchar	100
-- ssd_sen_need	senn_table_id	nvarchar	48
-- ssd_sen_need	senn_active_ehcp_id	nvarchar	48
-- ssd_sen_need	senn_active_ehcp_need_type	nvarchar	100
-- ssd_sen_need	senn_active_ehcp_need_rank	nchar	1