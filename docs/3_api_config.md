# Playbook and Setup Guide | Config Shell Script 

## Prerequisites
Ensure that the [initial local api testing](2_test_api.md) has already been completed. 

## Configuration Steps

# **Overview**

This guide explains how to configure and set up the supplied (Power)Shell script for automated data submission within/from your Local Authority environment to a/the pre-agreed API endpoint. 

## PowerShell Script Docstring Notes

### **Description**

The (Power)Shell script automates the process of extracting JSON structured Child Social Care records (payload) from an SSD defined table (data collection or staging table), sending the extracted payload to an API before updating appropriate submission status flags within the data collection or response table.

### **Key Features**

- Extracts pending JSON payload(s) from the SSD staging table(s)
- Sends JSON data to API endpoint or simulates the same process during localised initial testing.
- Updates submission status flags: `Sent`, `Error`, or `Testing` (ref: stored flags and settings are lowercase).

### **Parameters**

- **`$testingMode`**: Bool flag to toggle btwn LA testing and data being sent externally. **`true`=NO data leaves the LA.** 
- **`$server`**: SQL Server instance name
- **`$database`**: Database name (where the SSD is deployed)

Params configured and requiring no local changes:

- **`$ssd-api_data_staging`**: Add-on non-core SSD table containing JSON payloads and payload status information
  *(or `ssd-api_data_staging_anon` if in dev/testing)*
- **`$url`**: API endpoint path
- **`$token`**: Authentication token for the API

### **Prerequisites**

- PowerShell 5.1+ with ability to install `SqlServer` module.
- SQL Server with access to the specified database.

--- 


# **API Minimum Requirements**

### **System Requirements:**

 - PowerShell: Version 5.1+ (check with $PSVersionTable.PSVersion) or alternative script language access.
 - SQL Server: Ensure the database instance is accessible and deployed SSD includes the additional ssd_api_data_staging table.
 - Network: Ensure the SQL Server instance is reachable (e.g., via ping, will be visible if you run test API script and it fails).

### **Software Dependencies:**

SqlServer PowerShell Module:
 - This can be installed using: Install-Module -Name SqlServer -AllowClobber -Scope CurrentUser
 - Verify install:  Get-Module -ListAvailable SqlServer

DB: 
 - Ensure the ssd_api_data_staging table has been created and populated as required.

---


# **Script Configuration**
Open the script in a text editor or Powershell and update the following variables to match your environment:

### **Connection details**
 - `$server` = "YourSQLServerInstance"   # E.g. "ESLLREPORTS00X"
 - `$database` = "HDM_Local"             # E.g. default for SystemC/LLogic; update for Mosaic etc

### **API details**
 - `$url` = "https://api.gov/endpoint"   # API endpoint (already set)
 - `$token` = "your-auth-token"          # From client/API endpoint owner or supplied by D2I

### **Testing flag**
 - `$testingMode` = `$true`                # $true == **NO data leaves the LA.** | Set to $false for production-Live. See **Execution** for more detail. 

--- 


# **Execution**

### Testing Mode:

 - Ensure `$testingMode = $true` to simulate API calls without sending data.
 - Run the script in PowerShell:
   - .\ssd_json_payload-sql-server-agent_v0.2.4.ps1 (supplied filename may vary)

### Production Mode:

 - After verifying functionality in testing, set `$testingMode = $false`.
 - Re-run the script to send data to the API.
 
### Verify Updates:

 - Check the ssd_api_data_staging table to ensure submission_status and api_response are updated correctly.

---


