# Setup Guide - Deploy SSD

## Prerequisites
Ensure that the [minimum system requirements](system_requirements.md) are already met.


## SSD : Overview

A more complete overview of the SSD schema is available [SSD documentation](https://data-to-insight.github.io/ssd-data-model), note that **we are in the process of porting to a [new SSD front-end and site](https://data-to-insight.github.io/ssd-data-model-next/)** that some might find easier to navigate.
Depending on your CMS type, the SSD is deployed using 1+ SQL scripts; which create and populate a new schema of approx 45 tables within sight of your existing CMS database. The script(s) require no elevated priviledges, are non-destructive and can be run against the database by anyone with SELECT/CREATE permissions.   
This new SSD schema acts as a standardised middleware between your CMS and other possible services or common LA reporting; including the potential for the DfE API feeding into the Private Dashboard. 

---

## SSD : Deployment

**Deploy the SSD**:

 - SSD deployment script(s) are supplied for your CMS type from the [SSD distribution repo] (https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts). Depending on CMS type, the SSD deployment may/may not require localised configuration. 
 - Deployment can use any SQL client with connection to your CMS DB reporting instance e.g. SQL Server Management Studio|Azure Data Studio.
 - If anything fails during the SSD setup, it should be [logged with D2I][((https://github.com/data-to-insight/dfe-csc-api-data-flows/issues) for support and any potential bespoke script configuration.
 - See below for initial deployment steps for your particular CMS type. 

**Deploy ssd_api_data_staging table**:

   In order to enable storing the needed data payload for the DfE's API data flow, we've added an additional non-core table to the core SSD specification. This, and all needed changes to the SSD will be packaged within the initial set up scripts and there is nothing additional that requires action. The ssd_api_data_staging table enables change tracking and the storing of the API submission/status reponses. All related set up and configuration will be supplied by D2I to populate this table with the pending JSON payloads.


**Minimal SSD**

The SSD was developed together with a large number of LA colleagues accross the sector as a basis for much wider LA based reporting and stat-returns than the EA API project 'needs'. If useful to know, the following are considered to be the priority|essential|minimal schema needed by the project and the payload-staging table builder. LA colleagues are encouraged to focus efforts here if they wish to reduce deployment/data sense checks overheads. 

| table_name | usage | columns_used |
|---|---|---|
| ssd_person | READ | pers_person_id; pers_legacy_id; pers_dob; pers_expected_dob; pers_upn; pers_upn_unknown; pers_forename; pers_surname; pers_sex; pers_ethnicity |
| ssd_address | READ | addr_person_id; addr_address_postcode; addr_address_start_date |
| ssd_disability | READ | disa_person_id; disa_disability_code |
| ssd_immigration_status | READ | immi_person_id; immi_immigration_status; immi_immigration_status_start_date; immi_immigration_status_end_date |
| **ssd_api_data_staging (live data only)** | READ_WRITE | id; person_id; legacy_id; previous_json_payload; json_payload; current_hash; previous_hash; submission_status; row_state; last_updated |
| **ssd_api_data_staging_anon (test data only)** | READ_WRITE | id; person_id; legacy_id; previous_json_payload; json_payload; current_hash; previous_hash; submission_status; row_state; last_updated |
| ssd_assessment_factors | READ | cinf_assessment_id; cinf_assessment_factors_json |
| ssd_care_leavers | READ | clea_person_id; clea_care_leaver_latest_contact; clea_care_leaver_activity; clea_care_leaver_accommodation |
| ssd_cin_assessments | READ | cina_assessment_id; cina_referral_id; cina_assessment_start_date; cina_assessment_auth_date |
| ssd_cin_episodes | READ | cine_person_id; cine_referral_id; cine_referral_date; cine_close_date; cine_referral_source_code; cine_close_reason; cine_referral_nfa |
| ssd_cin_plans | READ | cinp_cin_plan_id; cinp_person_id; cinp_referral_id; cinp_cin_plan_start_date; cinp_cin_plan_end_date |
| ssd_cla_episodes | READ | clae_person_id; clae_referral_id; clae_cla_id; clae_cla_episode_start_reason; clae_cla_episode_ceased_reason |
| ssd_cla_placement | READ | clap_cla_placement_id; clap_cla_id; clap_cla_placement_start_date; clap_cla_placement_end_date; clap_cla_placement_postcode; clap_cla_placement_type; clap_cla_placement_change_reason |
| ssd_cp_plans | READ | cppl_cp_plan_id; cppl_person_id; cppl_referral_id; cppl_cp_plan_start_date; cppl_cp_plan_end_date |
| ssd_initial_cp_conference | READ | icpc_s47_enquiry_id; icpc_icpc_date |
| ssd_involvements | READ | invo_referral_id; invo_professional_id; invo_involvement_start_date; invo_involvement_end_date |
| ssd_permanence | READ | perm_person_id; perm_cla_id; perm_adm_decision_date; perm_matched_date; perm_placed_for_adoption_date |
| ssd_professionals | READ | prof_professional_id; prof_social_worker_registration_no |
| ssd_s47_enquiry | READ | s47e_referral_id; s47e_s47_enquiry_id; s47e_s47_start_date; s47e_s47_end_date; s47e_s47_outcome_json |
| ssd_sdq_scores | READ | csdq_person_id; csdq_sdq_completed_date; csdq_sdq_score |


---

## Log SSD/API support tickets  

 - **Phase1 & Phase 2 LAs/deployment teams should [Log deployment bugs, required changes or running issues via](https://github.com/data-to-insight/dfe-csc-api-data-flows/issues) - the basic/free Github account may be required for this**  

 - **LA colleagues are also encouraged to send the project your [general feedback, or your deployment requirements](https://forms.gle/rHTs5qJn8t6h6tQF8)**  

---

## SSD : SystemC (SQL Server)

- Download SystemC SSD: [SSD deployment_extracts/systemc/live](https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts/systemc/live)
- Copy|paste|execute from your SQL client, your LA named|supplied single SSD extract script.
- Dependent on your data estate|reporting infastructure, script typically takes n->15minutes to complete. A summary overview will output. 
- Review console output for possible fail/error points (pass back to D2I to enable changes in your LA's SSD config file).
- Your SSD is now deployed with data current to the run-point. 
- Inclusion of this script into overnights and|or manual daily re-run will refresh data. Table refreshes are otherwise static. 

## SSD : Mosaic (SQL Server | Oracle(Depreciated))

- Download Mosaic SSD: [SSD deployment_extracts/systemc/mosaic](https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts/mosaic/live)
- For Mosaic, there are multiple files to download, and set up requires local access to all the files
- Reference the 'Get started guide' - Mosaic SSD Dataset Configuration.docx
- Copy|paste|execute from your SQL client, the ##populate_ssd_main procedure. This the master procedure which executes all the other needed procedures.
- Type “##populate_ssd_main <your desired number of financial years>” e.g. “##populate_ssd_main 5 for 5 financial years data.  Click ‘Execute’.
- There are ~11 tables that will require your local parameters to be set to align with your Mosaic/LA recording methods. This need only be done
once, and is as simple as adding a number or list of values. 
  - Approx 40 settings in total, with guidance provided for each. e.g:
    - @cla_plan_step_types - List WORKFLOW_STEP_TYPE_ID and DESCRIPTION for all steps represent a CLA Care Plan. Values can be found in the DM_WORKFLOW_STEP_TYPES table.
    - @eh_step_types - List WORKFLOW_STEP_TYPE_ID and DESCRIPTION for steps representing “Period of Early Help”.
    - @immigration_status_start_date_question_user_codes - List question user codes used to capture start date of child immigration status. Found in DM_CACHED_FORM_QUESTIONS table or Form Designer tool.

- Dependent on your data estate|reporting infastructure, the script typically takes n->15minutes to complete.  
- Review console output for possible individual fail/error points and pass back to D2I. 
- Your SSD is now deployed with data current to the run-point. 
- Including populate_ssd_main procedure script into overnights or manual re-run will refresh data. Table refresh otherwise static. 

## SSD : Eclipse (Postgress)

- Download Eclipse SSD: [SSD deployment_extracts/eclipse/live](https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts/eclipse/live)
- Copy|paste|execute from your SQL client, the single SSD extract script.
- Dependent on your data estate|reporting infastructure, script typically takes n->15minutes to complete.  
- Review console output for possible individual fail/error points and pass back to D2I. 
- Your SSD is now deployed with data current to the run-point. 
- Inclusion of this script into overnights and|or manual daily re-run will refresh data. Table refreshes are otherwise static. 

## SSD Azeus (Oracle - development in progress)

- Download Azeus SSD: [SSD deployment_extracts/azeus/live](https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts/azeus/live)
- Timeline for delivery of this development stream is not confirmed. Unavailable until mid/later in project timeline.

## SSD Advanced|CareDirector|Other (tbc)

- Download CareDirector SSD: [SSD deployment_extracts/caredirector/live](https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts/caredirector/live)
- _Not available in this cycle_


---
## JSON Structure

In the _live_ API deployment, child-level data extracted from the SSD will be included in the JSON payload in line with the DfE|agreed data specification. If local authorities have access to a locally running Python/Jupyter environment (E.g. via a Python IDE or Anaconda), D2I can additionally supply the scripted tool(s) to enable non-live testing with either fake data or fully scrambled & anonymised data to reduce uneccessary use of live data. This can enable a local authority to step through phased connection testing without any use of live data.    
<!-- See full [json payload structure specification](payload_structure.md) -->

