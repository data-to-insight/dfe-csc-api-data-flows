# Local Authority System Requirements

## Prerequisites

In preparation towards the CSC API Dataflow project, Local Authorities must ensure that the following are in place.
[![Download PDF](https://img.shields.io/badge/Download-PDF-red)](/csc_api_data_collection/pdf/csc_ssd_api_documentation.pdf)


### System Requirements

**IT System Support Team Requirements**:

A list summary that LA colleagues can share with their IT teams to enable project access.

- **SSD Deployment**: Analyst access to CMS DB with elevated DB privilledges (table+index create|alter|drop)
- **CMS Server/DB Compatibility**: Compatibility setting at **120+** to enable more efficient JSON manipulation options for the SDD and structured data extract required for the API payload. 
- **Automation**: PowerShell 5.1+ (or Bash) scripts locally with ability to import `SqlServer` module (or alternative) - Script language will be the same that will require running from the server to enable to full API automation later. Alternative to use Python(incl. within Anaconda). 

---

**CMS**:

Pilot LAs are expected to be using:

 - **SystemC** | **Mosaic** | **Eclipse** | **Azeus**-In Development/TBC | **Other**-TBC

**Database**:

- **SystemOne** : SQL Server 2017 or later with compatibility settings at **120+**.
- **Mosaic**    : SQL Server 2017 or later with compatibility settings at **120+**.
- **Mosaic**    : Oracle (**TBC - depreciated**).
- **Eclipse**   : PostgreSQL
- **Azeus**     : Oracle (**TBC - in development**).

**Database Additions**:

- **Standard Safeguarding Dataset (SSD)** structure deployed on CMS database  
  _(e.g., for SystemC, that's commonly `HDM_Local`)_

Additional supplied SSD add-on(s), including:

  - Change tracking table to store pending JSON payloads and API response codes (essentially just an extra link table added to the SSD deployment and all required SQL is supplied).

**Automation**:

- **PowerShell 5.1+** with `SqlServer` module (or alternative shell/scripting)
- **Permissions to run**: **PowerShell**, **Python**, or **Bash** script locally, integrating later to **server job** for automating the daily data extraction & API 

--- 

### Support
D2I will be available to support on some of the above where access allows, and to assist with needed set-up config or localised changes to the available scripts.  


