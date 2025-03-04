# Setup Guide | API Test - Local


## Prerequisites
Ensure that the [SSD is already deployed ](deploy_ssd.md) has already been checked|completed. 
Ensure that the [api config](api_config.md) has already been checked|completed. 

# Configuration Steps (in progress)

## **Test API Setup**:

Before the API process is set to send live data payloads the project has the possibility to test locally the data extract and staging collection table process(es). Refer to the API Config documentation page, and settings within the *Execution* section, specifically *Testing Mode* flag. 

   - Discuss with D2I support regarding whether your LA has the option to work from anonymised tables and additional Py based scripts. 
   - Run the API-JSON extract script(Powershell) in testing mode `$testingMode = $true` to validate the process without submitting/sending data externally.
   - Verify submission statuses update correctly in the $ssd_api_data_staging table. 


---

