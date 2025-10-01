# Setup Guide - Deploy SSD

## Prerequisites
Ensure that the [minimum system requirements](system_requirements.md) are already met.


## SSD : Overview

A more complete overview of the SSD schema is available [SSD documentation](https://data-to-insight.github.io/ssd-data-model), note that **we are in the process of porting to a [new SSD front-end and site](https://data-to-insight.github.io/ssd-data-model-next/)** that some might find easier to navigate.
The SSD is deployed using 1+ SQL scripts, which create and populate a new schema of approx 45 tables within your existing CMS database. The script(s) require no elevated privilledges, is non-destructive and can be run against the database by anyone with SELECT/CREATE permissions.   
This new schema acts as a standardised middleware between your CMS and other possible services or common LA reporting; including the potential for the DfE API into the Private Dashboard. 

---

## SSD : Deployment

**Deploy the SSD**:

 - SSD deployment script(s) are supplied for your CMS type from the [SSD distribution repo] (https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts). Depending on CMS type, the SSD deployment may/may not require localised configuration. 
 - Deployment can use any SQL client with connection to your CMS DB reporting instance e.g. SQL Server Management Studio|Azure Data Studio.
 - If anything fails during the SSD setup, it should be recorded and returned to D2I for support and the needed bespoke script configuration.
 - See below for initial deployment steps for your particular CMS type. 

**Deploy ssd_api_data_staging table**:

   In order to enable storing the needed data payload for the DfE's API data flow, we've added an additional non-core table to the core SSD specification. This, and all needed changes to the SSD will be packaged within the initial set up scripts and there is nothing additional that requires action. The ssd_api_data_staging table enables change tracking and the storing of the API submission/status reponses. All related set up and configuration will be supplied by D2I to populate this table with the pending JSON payloads.

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

