# Configuration and Setup

## Pre-requisites
Before setting up the CSC API Dataflow, ensure the following are in place:

### System Requirements
- SQL Server 2017 or later with compatibility settings at 120+
- SSD structure deployed on the CMS database (e.g., HDM_Local)
- Security settings to enable PowerShell or Python for automation

### Stakeholder Engagement
- To ensure that we can implement both the SSD(initially) and enable security settings(Powershell, SSD refresh, Outgoing API)
- Agreement on the SSD refresh frequency (daily recommended)

## Configuration Steps
1. **Deploy the SSD**:
   - A complete overview of the SSD is available [SSD documentation](https://data-to-insight.github.io/ssd-data-model)
   - 1:1 support for LAs to set up the SSD will be given by D2I
   - Ensure all required tables and fields are present in the CMS database (e.g., HDM_Local)

2. **Set Up the $ap_collection_table**:
   - Prepopulate table with pending JSON payloads
   - Fields for tracking submission statuses

3. **Install Required Tools**:
   - PowerShell 5.1 or later with SqlServer module
   - Python (optional) for alternative automation scripts

4. **Configure the API**:
   - The API endpoint URL and authentication token from will be supplied/pre-configured.
   - Main script parameters:
     - `$server`: SQL Server instance
     - `$database`: SSD database
     - `$url`: API endpoint
     - `$token`: Authentication token

5. **Test the Setup**:
   - Run the script in testing mode to validate the process without submitting data
   - Verify submission statuses update correctly in the $api_collection_table

## JSON Structure
Child-level data will be included in the JSON payload in line with the spec. Inlcuding:
- **Children**:
  - LA Child ID, UPN, Former UPN, UPN Unknown Reason
  - First name, Surname, Date of Birth, Expected Date of Birth, Sex, Ethnicity, Disabilities
  - Educational Health and Care Plans
  - Social Care Episodes
  - Health and Wellbeing
  - Adoptions
  - Care Leavers
  - Social Care Workers


## Stakeholder Responsibilities
### Local Authorities (Pilot Development Partners)
- Deploy the SSD structure and agree on refresh frequency
- Extract and submit JSON payloads as per requirements
- Actively participate in testing and feedback during pilot phases

### Data Analysts
- Oversee the completeness and validation of extracted data
- Address any API failure response codes

### Security Teams
- Agree and set up the permissions required for the API script to run (ideally on a server)
- Facilitate the deployment of the SSD structure on the CMS database (e.g., HDM_Local)

---

