# Step 1: Deploy SSD
[draft: 160125]

## Pre-requisites
Ensure that the [minimum system requirements ](system_requirements.md) are already met. 
Note that support for LAs to set up the SSD will be given by D2I

## Configuration Steps
1. **Deploy the SSD**:
   A complete overview of the SSD is available [SSD documentation](https://data-to-insight.github.io/ssd-data-model).
   The SSD is deployed with a single SQL script creating and populating the schema of approx 45 tables. 
   - SSD deployment script(s) will be supplied for your CMS type from the main [SSD distribution repo] (https://github.com/data-to-insight/ssd-data-model/tree/main/deployment_extracts).
   - Depending on CMS type, the SSD deployment may/may not require any localised configuration - these instructions would be supplied by D2I
   - Should they occur, log any fail points during the SSD setup and feedback asap to D2I for support and next steps


2. **Deploy $api_collection_table**:
   This an add-on table to the core SSD structure to enable change tracking.
   - Prepopulate table with pending JSON payloads
   - Contains fields for tracking submission statuses

3. **DB Config details required for API**:
   - The API script, is held locally and will need to be configured with some DB related connection parameters :
     - `$server`: SQL Server instance, e.g. ESLLREPORTS04V
     - `$database`: Database instance where the SSD is deployed, e.g. HDM_Local

4. **Test API Setup**:
   - Run the API-JSON extract script(Powershell) in testing mode `$testingMode = $true` to validate the process without submitting/sending data externally
   - Verify submission statuses update correctly in the $api_collection_table


## JSON Structure
Child-level data will be included in the JSON payload in line with the spec. 
See full [json payload structure specification](payload_structure.md)



---

