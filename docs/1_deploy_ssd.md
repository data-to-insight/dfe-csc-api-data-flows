# Playbook and Setup Guide | Deploy SSD
<!-- [![Download Deploy SSD](https://img.shields.io/badge/Download-PDF-red)](pdf/1_deploy_ssd.pdf) -->

## Prerequisites
Ensure that the [minimum system requirements](system_requirements.md) are already met.

A complete overview of the SSD is available [SSD documentation](https://data-to-insight.github.io/ssd-data-model).
The SSD is deployed using 1+ SQL scripts, which create and populate a new schema of approx 45 tables. 
This new schema can act as a standardised middleware between your CMS and other services and common reporting. 

---
Guidance aimed at Analyst/Data/Performance/Intelligence leads looking to run the SSD extract script(s) for their LA. 
Where possible the SSD extract is combined within a single script. In brief, if your LA runs the SSD SQL script(s), you will have instant access to the SSD structure. You then have access to available project tools, tools from other SSD LA’s and the potential to work with any other LA collaboratively to develop those or new tools. That’s it!  

Feedback welcomed regarding any aspect of the SSD, or it's continuous change process towards improving the project/processes/SSD outcomes; for all involved.   


## SSD Config: General

**Deploy the SSD**:

 - SSD deployment script(s) will be supplied for your CMS type from [SSD distribution repo] (https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts). Depending on CMS type, the SSD deployment may/may not require any localised configuration. 
 - Script deployment is done via SQL client, with connection to your CMS DB reporting instance e.g. SQL Server Management Studio|Azure Data Studio.
 - Log any fail points during the SSD setup and feedback asap to D2I for support and next steps.
 - See below for the deployment steps for your particular CMS type. 

**Deploy $ssd_api_data_staging table**:

   This a supplied add-on table to the core SSD structure to enable record change tracking and submission/api status reponse. All related set up and config will be supplied to populate this table with pending JSON payloads.

**DB/CMS Config details required for API**:

   - The API script, is stored and run from within your LA, and will need to be configured with some Local DB connection parameters :
     - `$server`: CMS Reporting Server name, e.g. ESLLREPORTS00X
     - `$database`: Database instance where the SSD is deployed, e.g. for SystemC the default is : HDM_Local


## SSD Config: SystemC (SQL Server)

- Download SystemC SSD: [SSD deployment_extracts/systemc/live](https://github.com//workspaces/ssd-data-model/deployment_extracts_la_release/)
- Copy|paste|execute from your SQL client, your LA named|supplied single SSD extract script.
- Dependent on your data estate|reporting infastructure, script typically takes n->15minutes to complete. A summary overview will output. 
- Review console output for possible individual fail/error points and pass back to D2I to enable changes in your LA's SSD config file.
- Your SSD is now deployed with data current to the run-point. 
- Inclusion of this script into overnights and|or manual daily re-run will refresh data. Table refreshes are otherwise static. 

## SSD Config: Mosaic (SQL Server | Oracle(Depreciated))

- Download Mosaic SSD: [SSD deployment_extracts/systemc/mosaic](https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts/mosaic/live)
- For Mosaic, there are multiple files to download, and set up requires local access to all the files
- Reference the 'Get started guide' - Mosaic SSD Dataset Configuration.docx
- Copy|paste|execute from your SQL client, the ##populate_ssd_main procedure. This the master procedure which executes all the other needed procedures.
- Type “##populate_ssd_main <your desired number of financial years>” e.g. “##populate_ssd_main 5 for 5 financial years data.  Click ‘Execute’.
- There are ~11 tables that will require your local parameters to be set to align with your Mosaic/LA recording methods. This need only be done
once, and is as simple as adding a number or list of values. 
  - Approx 40 settings in total, with guidance provided for each. 
  - e.g. 
    - @cla_plan_step_types - List the WORKFLOW_STEP_TYPE_ID and DESCRIPTION for all workflow steps represent a CLA Care Plan. Values can be found in the DM_WORKFLOW_STEP_TYPES table.
    - @eh_step_types - List WORKFLOW_STEP_TYPE_ID and DESCRIPTION for workflow steps representing a “Period of Early Help”.
    - @immigration_status_start_date_question_user_codes - List question user codes used to capture start date of child immigration status. Found in DM_CACHED_FORM_QUESTIONS table or Form Designer tool.

- Dependent on your data estate|reporting infastructure, the script typically takes n->15minutes to complete.  
- Review console output for possible individual fail/error points and pass back to D2I. 
- Your SSD is now deployed with data current to the run-point. 
- Inclusion of populate_ssd_main procedure script into overnights and|or manual daily re-run will refresh data. Table refreshes are otherwise static. 

## SSD Config: Eclipse (Postgress)

- Download Eclipse SSD: [SSD deployment_extracts/eclipse/live](https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts/eclipse/live)
- Copy|paste|execute from your SQL client, the single SSD extract script.
- Dependent on your data estate|reporting infastructure, script typically takes n->15minutes to complete.  
- Review console output for possible individual fail/error points and pass back to D2I. 
- Your SSD is now deployed with data current to the run-point. 
- Inclusion of this script into overnights and|or manual daily re-run will refresh data. Table refreshes are otherwise static. 

## SSD Config Azeus (Oracle - development in progress)

- Download Azeus SSD: [SSD deployment_extracts/azeus/live](https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts/azeus/live)
- Timeline for delivery of this development stream is not yet confirmed. Potentially not available until mid/later in project timeline.

## SSD Config Advanced|CareDirector|Other (tbc)

- Download CareDirector SSD: [SSD deployment_extracts/caredirector/live](https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts/caredirector/live)
- Not available in this cycle

---

## JSON Structure

In the live API deployment, child-level data extracted from the SSD will be included in the JSON payload in line with the specification. If local authorities have access to local running Python environment (incl. within Anaconda), D2I can supply both the process and script to enable non-live testing with fully anonymised data to reduce uneccessary use of live data.   
<!-- See full [json payload structure specification](payload_structure.md) -->



---

