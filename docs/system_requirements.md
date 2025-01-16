# Local Authority System Requirements
[draft: 160125]

## Pre-requisites
Before setting up, or in preparation towards the CSC API Dataflow, Local Authorities must ensure that the following are in place.


### System Requirements

**CMS**:
- Pilot LAs are expected to be using: SystemOne, Mosaic or Eclipse.

**Database**:
- SystemOne: SQL Server 2017 or later with compatibility settings at 120+.
- Mosaic: SQL Server 2017 or later with compatibility settings at 120+.
- Eclipse: Posgress .... tbc.


**Database additions**:
- Standard Safeguarding Dataset (SSD) structure deployed on CMS database (e.g., for SystemOne that's commonly' 'HDM_Local')
- Additional supplied SSD add-on(s), incl. Change tracking table to store pending JSON payloads/response codes

**Automation**:
- PowerShell 5.1 or later with SqlServer module
- PErmissions to run PowerShell (or Python, bash) script locally, + later as a server job towards data query extract and API send


### Support
D2I will be available to support on some of the above where access allows, and to assist with needed set-up config or localised changes to the available scripts.  


**IT System Support Team list of Required Tools**:
- PowerShell 5.1 or later + SqlServer module
- 