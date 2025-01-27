# csc_api_data_collection
Collaboration towards a CSC API data workflow

## Repo commands ref
* `mkdocs serve`        - live-reload docs server
* `mkdocs build`        - build docs site
* `mkdocs gh-deploy`    - push to Gitpage front-end(public)

## DB commands ref
* `EXEC sp_who2;`       - running processes to get kill id, + KILL [session_id];


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