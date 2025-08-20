# CSC Dashboard Early Adopters – *Data to Insight* API Solution

<!-- Status Options -->
<!-- ![Status](https://img.shields.io/badge/status-in%20dev-orange)     Active build and feature work -->
![Status](https://img.shields.io/badge/status-phase1beta%20testing-yellow)      <!-- Phase1 pilot group -->
<!-- ![Status](https://img.shields.io/badge/status-phase2beta%20candidate-blue)   Phase2 release, final QA -->
<!-- ![Status](https://img.shields.io/badge/status-released-brightgreen)       Available -->
<!-- ![Status](https://img.shields.io/badge/status-maintenance-lightgrey)      Stable, bug fixes -->
<!-- ![Status](https://img.shields.io/badge/status-deprecated-red)             No longer maintained -->
![Version](https://img.shields.io/badge/version-0.3.4-blue)
![Spec](https://img.shields.io/badge/spec-0.8-blueviolet)
![Platform](https://img.shields.io/badge/platform-Local%20Authority%20CMS-lightgrey)
![SSD%20Compatible](https://img.shields.io/badge/SSD-Compatible-success)
![DfE%20API](https://img.shields.io/badge/DfE%20API-Connected-00703c)<br>
![Data%20Format](https://img.shields.io/badge/data%20format-JSON-yellow)
![Code-Python](https://img.shields.io/badge/code-Python-blue)
![Code-PowerShell](https://img.shields.io/badge/code-PowerShell-5391FE)
![Code-SQL](https://img.shields.io/badge/code-SQL-lightgrey)
![Data%20Transfer](https://img.shields.io/badge/data%20transfer-automated%20daily-success)
<!-- ![DfE](https://img.shields.io/badge/DfE-Project-00703c?logo=gov.uk&logoColor=white) -->

This repository contains solution overview details for the *Data to Insight* (D2I) approach within the CSC Dashboard Early Adopters Scheme.  
It provides documentation, technical resource(s), and updates for local authorities (LAs) **using or looking to deploy the Standard Safeguarding Dataset (SSD) API connection** to share agreed timely children’s social care (CSC) data with the Department for Education (DfE).

## Purpose of this Front End
- **Explain the D2I API approach** — what it is, how it works, and what’s needed to participate  
- **Provide step-by-step onboarding materials** for LAs implementing as part of the pilot scheme or exploring the SSD API connection  
- **Offer reference documentation** for data items, API endpoints, and validation rules  
- **Share updates and troubleshooting guidance** based on live pilot experience  

## Context
The Early Adopters Scheme is part of DfE’s ambition to improve CSC data flows, reduce burden on LAs, and provide more timely insights through a secure, private-access dashboard.  
This front end focuses entirely on the *Data to Insight* API solution — including the needed SSD deployment — and serves as the main resource for Phase 1(pilot) and Phase 2 participants as well as those with a contextual longer-term interest in the project details or progress.

**There are three key elements:**
 
 - Standard Safeguarding Dataset (SSD)
 - JSON extract and API logging from SSD   
 - CSC API connection to DfE  

 - **LA colleagues are encouraged to [feedback any and all running issues, general feedback, deployment requirements](https://forms.gle/rHTs5qJn8t6h6tQF8)**

If you are arriving here without previous knowledge of the wider scheme, please see:  

**DfE Published Project Documentation**  

- [CSC Dashboard EA Application Guide (PDF)](https://assets.publishing.service.gov.uk/media/68516c13f2ccfcfd2f823f84/CSC_Dashboard_EA_Application_Guide.pdf)  
- [Apply to be a CSC Private Dashboard Early Adopter (GOV.UK)](https://www.gov.uk/guidance/apply-to-become-a-childrens-social-care-private-dashboard-early-adopter)  
- [Children’s Social Care Dashboard (Public version)](https://www.gov.uk/government/publications/childrens-social-care-dashboard)  
- [Department for Education APIs currently available](https://beta-find-and-use-an-api.education.gov.uk/find-an-api)  

**SSD schema Technical aspects and Published Project Documentation**  

- [DDSF Project 1a final report](https://www.datatoinsight.org/publications-1/standard-safeguarding-dataset---final-report) 
- [SSD project Github web pages-public access-](https://data-to-insight.github.io/ssd-data-model-next/)
- [SSD project Github repo-request access-](mailto:datatoinsight.enquiries@gmail.com) 
- [SSD deployment guidance summary within this site documentation](deploy_ssd_schema.md)


## Audience
This site is aimed at:
- **Local authority teams** using or preparing to implement the D2I SSD API solution  
- **DfE & D2I project teams** supporting onboarding and technical testing  
- **Stakeholders** interested in the Standard Safeguarding Dataset(SSD)  

## How will the D2I solution work?

The *Standard Safeguarding Dataset* (SSD) acts as a **middleware layer** between a local authority’s case management system (CMS) and standardised LA reporting, but also in this use-case towards a Department for Education’s CSC API. It standardises CSC data into a cross-LA, cross-CMS consistent schema, thus enabling automated, low-burden data sharing.

**Deployment**  
For many LAs, SSD installation is close to plug-and-play; others may need adaptations to align with local|bespoke CMS or reporting structures. Once deployed, the SSD unlocks additional benefits such as:  
- Enabling standardised reporting and dashboards  
- Easier data sharing(if desirable/agreed) and collaboration across the sector  
- Re-use of proven reports and insight tools developed by other LAs (i.e. SSD-LA1 reporting tools will now also works in SSD-LA2, SSD-LA3...) 

**Data flow**  
1. **Extract** — Agreed CSC data is drawn directly from the SSD schema 
2. **Format** — Data is packaged in JSON format, either as:  
   - a **daily snapshot** (initial approach)  
   - or **daily deltas** showing only changes since the previous day  
3. **Transmit** — JSON data is securely sent to DfE via an authenticated API connection 
4. **Acknowledge** — DfE systems confirm receipt and log any errors
5. **Log & store** — The D2I solution keeps a local copy of submitted files and DfE responses within the SSD for audit and troubleshooting

**Outcome**  
The DfE uses this data to produce up-to-date indicators for the *private CSC dashboard*, enabling faster benchmarking against the National Framework and earlier identification of trends across the sector. Interested LA's should read the DfE published project details regarding the data use for details.

More detail on SSD benefits and deployment can be found in the [SSD project documentation](https://data-to-insight.github.io/ssd-data-model-next/) (*opens in new tab*).
