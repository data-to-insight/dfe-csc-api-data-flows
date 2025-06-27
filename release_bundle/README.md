# csc_api_data_collection

![Python](https://img.shields.io/badge/Python-3.10+-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Build](https://img.shields.io/github/actions/workflow/status/data-to-insight/dfe_csc_api_data_flows/build-api-pipeline.yml?branch=main)
![Release](https://img.shields.io/github/v/release/data-to-insight/dfe_csc_api_data_flows)


Collaboration towards a DfE API CSC data workflow
Published: [data-to-insight.github.io/csc_api_data_collection](https://data-to-insight.github.io/csc_api_data_collection/)

## Project| Repo Overview

csc_api_data_collection/
├── LICENSE
├── README.md
├── d2i_dev                     # DEV: in progress D2i development
│   ├── ...
├── docs                        # DELIVERABLE: Documentation and LA playbook | 
│   ├── development_plan.md     # DEV: published as reference during development/not part of deliverables
│   ├── index.md
│       ...                     
├── mkdocs.yml                  # DEV: documentation config file
├── requirements.txt        
│    
├── site                        # DELIVERABLE: Published Documentation
│   ├── ..                      # DEV: gh-deploy site web front end pages incl. 404.html
│ 
└── ssd_json_payload-sql-server-agent_v0.1.4.ps1    # DELIVERABLE: API script

--- 

## mkdocs commands ref
* `mkdocs serve --help`     - see list of options including the below
* `mkdocs build --clean`    - build docs site
* `mkdocs serve`            - live-reload docs server
* `mkdocs serve -a 127.0.0.1:8080`  - serve on new port if blocked

* `mkdocs gh-deploy`        - push to Gitpage front-end(public)

* `pkill mkdocs`            - kill any running MkDocs process
* `lsof -i :8000`           - kill running 
* `kill -9 12345`           - kill process (Replace 12345 with PID)


## DB commands ref
* `EXEC sp_who2;`           - running processes to get kill id, + KILL [session_id];




## Smart City Concept Model (SCCM)
The terminology and relations shown here might not be fully alligned with the SCCM standard(s), this is a work-in-progress.<br/>
<img src="./sccm_graph_static.svg" alt="SCCM Graph" title="Smart City Concept Model Graph" width="100%"> <br/>  

<details> <summary><strong>📦 Entities</strong></summary>

Entity Label	Type	Description
CSC API Data Flows Tool	Method	A D2I tool that extracts, standardises, and transmits CSC data to the DfE daily via API
Local Authority	Organization	An administrative body responsible for children’s services. Has unique la_code.
LA Children’s Social Care	Service	A service team within a Local Authority delivering CSC services
Children Within Social Care	Person	Children whose data is held and managed by the CSC service
Case Management System	Resource	Proprietary or custom system used to manage CSC cases
Standard Safeguarding Dataset (SSD)	Method	Standardised middleware for harmonising CSC data
CSC API Extract Event	Event	Daily extraction and transformation of CSC data into SSD format
CSC API Payload	Object	JSON file submitted to the DfE containing CSC data
API Submission Log	Account	Log of payload submissions and responses
Department for Education (DfE)	Organization	The UK government department for education and children’s services
DfE Private Dashboard	Resource	Dashboard for CSC indicators and benchmarking
Local Authority Area	Place	Geographic area of a Local Authority
Region in England	Place	Statistical area grouping multiple Local Authorities
</details>
<details> <summary><strong>🔗 Relationships</strong></summary>

Subject Entity	Predicate	Object Entity
Local Authority	is_located_in	Local Authority Area
Local Authority Area	is_part_of	Region in England
Local Authority	provides	LA Children’s Social Care
LA Children’s Social Care	serves	Children Within Social Care
LA Children’s Social Care	records	Children Within Social Care
Local Authority	uses	Case Management System
Local Authority	compares_with	Local Authority
CMS	feeds	Standard Safeguarding Dataset (SSD)
SSD	maps_from	CMS
CSC API Data Flows Tool	initiates	CSC API Extract Event
CSC API Extract Event	uses	SSD
CSC API Extract Event	produces	CSC API Payload
CSC API Payload	recorded_in	API Submission Log
CSC API Payload	sent_to	Department for Education (DfE)
CSC API Payload	informs	DfE Private Dashboard
Department for Education (DfE)	populates	DfE Private Dashboard
Department for Education (DfE)	updates	API Submission Log
Local Authority	informed_by	DfE Private Dashboard
</details>
---
References: [istanduk.org Initial SCCM Project](https://istanduk.org/projects/smart-cities-concept-model/) & [smartcityconceptmodel.com Smart Cities Concept Model](http://www.smartcityconceptmodel.com) <br/><br/><br/>  