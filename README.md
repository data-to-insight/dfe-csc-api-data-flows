# csc_api_data_collection

Collaboration towards a CSC API data workflow
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

