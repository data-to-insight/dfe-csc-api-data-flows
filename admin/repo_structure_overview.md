# Repo Structure

```text
dfe-csc-api-data-flows/
├── api_pipeline/
│   ├── .env.example
│   ├── README.md
│   ├── __init__.py
│   ├── __main__.py
│   ├── api.py
│   ├── auth.py
│   ├── build.sh
│   ├── build.yml
│   ├── config.py
│   ├── db.py
│   ├── dfe_csc_api_testing.ipynb
│   ├── entry_point.py
│   ├── main.py
│   ├── payload.py
│   ├── requirements.txt
│   ├── test.py
│   └── utils.py
├── api_pipeline_pshell/
│   └── phase_1_api_payload.ps1
├── api_sql_raw_json_query/
│   ├── populate_ssd_api_data_staging.sql
│   └── populate_ssd_api_data_staging_v1.0 - nested CLA.sql
├── build/
│   ├── bdist.linux-x86_64/
│   └── lib/
│       └── api_pipeline/
│           ├── .env.example
│           ├── README.md
│           ├── __init__.py
│           ├── __main__.py
│           ├── api.py
│           ├── auth.py
│           ├── config.py
│           ├── db.py
│           ├── entry_point.py
│           ├── main.py
│           ├── payload.py
│           ├── test.py
│           └── utils.py
├── csc_api_pipeline.egg-info/
│   ├── PKG-INFO
│   ├── SOURCES.txt
│   ├── dependency_links.txt
│   ├── requires.txt
│   └── top_level.txt
├── dist/
│   ├── csc_api_pipeline-0.1.3-py3-none-any.whl
│   └── csc_api_pipeline-0.1.3.tar.gz
├── docs/
│   ├── overrides/
│   │   └── pdf/
│   │       └── default.html.j2
│   ├── theme/
│   │   ├── cover.md
│   │   └── default_cover.html.j2
│   ├── analyst_local_testing.md
│   ├── api_config.md
│   ├── api_powershell_deployment.md
│   ├── api_python_deployment.md
│   ├── api_python_deployment_prev.md
│   ├── configure_api_script_prev.md
│   ├── data_security.md
│   ├── deploy_ssd_schema.md
│   ├── feature_backlog.md
│   ├── gitactions_workflows.md
│   ├── implementation_roadmap.md
│   ├── index.md
│   ├── json_payload_structure.md
│   ├── release.md
│   ├── stakeholders.md
│   ├── system_requirements.md
│   ├── test_api.md
│   └── troubleshooting_faq.md
├── release_bundle/
│   ├── .env.example
│   ├── README.md
│   ├── csc_api_pipeline-0.1.3-py3-none-any.whl
│   ├── csc_api_pipeline-0.1.3.tar.gz
│   ├── phase_1_api_payload.ps1
│   └── populate_ssd_api_data_staging.sql
├── site/
│   ├── analyst_local_testing/
│   │   └── index.html
│   ├── api_config/
│   │   └── index.html
│   ├── api_powershell_deployment/
│   │   └── index.html
│   ├── api_python_deployment/
│   │   └── index.html
│   ├── api_python_deployment_prev/
│   │   └── index.html
│   ├── configure_api_script_prev/
│   │   └── index.html
│   ├── data_security/
│   │   └── index.html
│   ├── deploy_ssd_schema/
│   │   └── index.html
│   ├── feature_backlog/
│   │   └── index.html
│   ├── gitactions_workflows/
│   │   └── index.html
│   ├── implementation_roadmap/
│   │   └── index.html
│   ├── json_payload_structure/
│   │   └── index.html
│   ├── overrides/
│   │   └── pdf/
│   │       └── default.html.j2
│   ├── pdf/
│   │   └── csc_ssd_api_documentation.pdf
│   ├── release/
│   │   └── index.html
│   ├── search/
│   │   └── search_index.json
│   ├── stakeholders/
│   │   └── index.html
│   ├── system_requirements/
│   │   └── index.html
│   ├── test_api/
│   │   └── index.html
│   ├── theme/
│   │   ├── cover/
│   │   │   └── index.html
│   │   └── default_cover.html.j2
│   ├── troubleshooting_faq/
│   │   └── index.html
│   ├── 404.html
│   ├── index.html
│   ├── sitemap.xml
│   └── sitemap.xml.gz
├── src/
│   └── csc-api-pipeline/
│       ├── api_pipeline/
│       │   ├── .env.example
│       │   ├── README.md
│       │   ├── api.py
│       │   ├── auth.py
│       │   ├── build.sh
│       │   ├── build.yml
│       │   ├── config.py
│       │   ├── csc_data_flows_api.ipynb
│       │   ├── db.py
│       │   ├── main.py
│       │   ├── payload.py
│       │   ├── pyproject.toml
│       │   ├── requirements.txt
│       │   └── utils.py
│       ├── docs/
│       │   ├── overrides/
│       │   │   └── pdf/
│       │   │       └── default.html.j2
│       │   ├── theme/
│       │   │   ├── cover.md
│       │   │   └── default_cover.html.j2
│       │   ├── configure_api_script.md
│       │   ├── data_security.md
│       │   ├── deploy_api.md
│       │   ├── deploy_ssd_schema.md
│       │   ├── feature_backlog.md
│       │   ├── implementation_roadmap.md
│       │   ├── index.md
│       │   ├── json_payload_structure.md
│       │   ├── refresh_dev_backlog_page_from_github_api.py
│       │   ├── stakeholders.md
│       │   ├── system_requirements.md
│       │   ├── test_api.md
│       │   └── troubleshooting_faq.md
│       ├── .gitignore
│       ├── LICENSE
│       ├── README.md
│       ├── clean.sh
│       ├── mkdocs.yml
│       ├── pyproject.toml
│       ├── pytest.ini
│       ├── release.sh
│       ├── requirements.txt
│       ├── sccm.yml
│       ├── sccm_graph_static.svg
│       └── setup.sh
├── .gitignore
├── LICENSE
├── MANIFEST.in
├── README.md
├── clean.sh
├── mkdocs.yml
├── pyproject.toml
├── pytest.ini
├── release.sh
├── release.zip
├── requirements.txt
├── sccm.yml
├── sccm_graph_static.svg
└── setup.sh
```
