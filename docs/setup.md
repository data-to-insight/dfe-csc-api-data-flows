# LA Configuration and Setup
[draft: 160125]

## Pre-requisites
Before setting up the CSC API Dataflow, ensure the [minimum system requirements ](system_requirements.md) are met 


## Configuration Steps
1. **Deploy the SSD**:
   - A complete overview of the SSD is available [SSD documentation](https://data-to-insight.github.io/ssd-data-model)
   - 1:1 support for LAs to set up the SSD will be given by D2I
   - Ensure all required tables and fields are present in the CMS database (e.g., HDM_Local)

2. **Set Up the $ap_collection_table**:
   This an add-on table to the core SSD structure to enable change tracking.
   - Prepopulate table with pending JSON payloads
   - Fields for tracking submission statuses

3. **Install Required Tools**:
   - PowerShell 5.1 or later with SqlServer module
   - Python (optional) for alternative automation scripts

4. **Configure the API**:
   - The API endpoint URL and auth token from will be supplied/pre-configured.
   - Main script parameters:
     - `$server`: SQL Server instance
     - `$database`: SSD database
     - `$url`: API endpoint
     - `$token`: Auth token

5. **Test the Setup**:
   - Run the script in testing mode to validate the process without submitting data
   - Verify submission statuses update correctly in the $api_collection_table

## JSON Structure
Child-level data will be included in the JSON payload in line with the spec. 
See full [json payload structure specification](payload_structure.md)
Inlcuding:
- **Children**:
  - LA Child ID, UPN, Former UPN, UPN Unknown Reason
  - First name, Surname, Date of Birth, Expected Date of Birth, Sex, Ethnicity, Disabilities
  - Educational Health and Care Plans
  - Social Care Episodes
  - Health and Wellbeing
  - Adoptions
  - Care Leavers
  - Social Care Workers




---

