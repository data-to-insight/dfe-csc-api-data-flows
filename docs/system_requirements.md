# Local Authority System Requirements

## Prerequisites

In preparation towards the CSC API Dataflow project, Local Authorities must ensure that the following are in place.
<!-- [![Download PDF](https://img.shields.io/badge/Download-PDF-red)](/csc_api_data_collection/pdf/csc_ssd_api_documentation.pdf) -->


### System Requirements

**IT System Support Team Requirements**:

A list summary that LA colleagues can share with their IT support teams to enable project access.

- **SSD Deployment**: Analyst access to CMS DB (SELECT/CREATE table+index. *Ideally also* ALTER|DROP table+index)
- **DB Compatibility**: Compatibility setting at **120+** to enable more efficient JSON manipulation options for the SDD and structured data extract required for the API payload. Potential work-arounds exist for compatibility <= 120, but will be less optimised. 
- **Automation**: PowerShell 5.1+ (or Bash) scripts locally with ability to import `SqlServer` module (or alternative) - Script language will be the same that will require running from the server to enable to full API automation later. 

---

**CMS**:

Pilot LAs are expected to be using:

 - **SystemC(Liquid Logic)** | **Mosaic** | **Eclipse** | **Azeus**-In Development/TBC | **Other**-TBC

**Database**:

- **SystemC**   : SQL Server 2017+ with compatibility settings **120+**
- **Mosaic**    : SQL Server 2017+ with compatibility settings **120+**
- **Mosaic**    : Oracle users(**TBC**) - depreciated.
- **Eclipse**   : PostgreSQL (**TBC – development nearing completion**)
- **Eclipse**   : SQL Server data warehouse (**TBC**) - Not within initial phases
- **Azeus**     : Oracle (**TBC - in development**) 

**Database Additions**:

- The **Standard Safeguarding Dataset (SSD)** structure deployed with D2I guidance on CMS database  _(e.g., for SystemC, commonly `HDM_Local`)_

Additional supplied SSD add-on(s), including:

  - CAPI submisison and reponse tracking table to store pending JSON payloads and API response codes (essentially just an additional table added to the SSD deployment, whereby all required SQL is supplied by D2I).

**Automation**:

- **PowerShell 5.1+**  (or potentially an alternative shell/scripting)
- **Permissions to run**: **PowerShell**, **Python**, or **Bash** script locally would reduce early testing overheads, but scripts must be able to run later as part of the **server tasks/overnights** for automating the daily data extraction & API data submissions.

--- 

### Support
D2I will be available to support local authorities directly on some/all of the above where access allows, and to assist with needed set-up config or localised changes to the available scripts.  


