# Repo Structure

```text
dfe-csc-api-data-flows/
├── api_pipeline/
│   ├── notebooks/
│   │   ├── csc_api_pipeline_cli_wrapper.ipynb
│   │   ├── csc_api_pipeline_fabric_flat.ipynb
│   │   └── env.example.txt
│   ├── pshell_api_sender/
│   │   └── api_payload_sender.ps1
│   ├── scripts/
│   │   ├── build.sh
│   │   └── build.yml
│   ├── .env.example
│   ├── README.md
│   ├── __init__.py
│   ├── __main__.py
│   ├── api.py
│   ├── auth.py
│   ├── config.py
│   ├── db.py
│   ├── entry_point.py
│   ├── main.py
│   ├── payload.py
│   ├── requirements.txt
│   ├── test.py
│   └── utils.py
├── build/
│   ├── bdist.linux-x86_64/
│   └── lib/
│       └── api_pipeline/
│           ├── notebooks/
│           │   ├── csc_api_pipeline_cli_wrapper.ipynb
│           │   ├── csc_api_pipeline_fabric_flat.ipynb
│           │   └── env.example.txt
│           ├── pshell/
│           │   └── api_payload_sender.ps1
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
├── build_dfe_payload_staging/
│   ├── dev/
│   │   ├── archive/
│   │   │   ├── populate_ssd_api_data_staging_2012.sql
│   │   │   └── populate_ssd_api_data_staging_2016sp1.sql
│   │   ├── 0.1.2-BAK-pre2016 refactor.sql
│   │   ├── gitattributes
│   │   ├── populate_ssd_api_data_staging v0.1.0.sql
│   │   ├── populate_ssd_api_data_staging.sql
│   │   ├── populate_ssd_api_data_staging_2012+_DfECohort - pre Dfe API adoptions fix.sql
│   │   ├── populate_ssd_api_data_staging_2012.sql
│   │   ├── populate_ssd_api_data_staging_2016sp1-DfECohort.sql
│   │   ├── populate_ssd_api_data_staging_balanced.sql
│   │   └── populate_ssd_api_data_staging_v1.0 - nested CLA.sql
│   ├── populate_ssd_api_data_staging_2016.sql
│   ├── populate_ssd_api_data_staging_postgres.sql
│   └── ssd_cohort.sql
├── csc_api_pipeline.egg-info/
│   ├── PKG-INFO
│   ├── SOURCES.txt
│   ├── dependency_links.txt
│   ├── entry_points.txt
│   ├── requires.txt
│   └── top_level.txt
├── dfe-csc-ea-pilot-onboarding/
│   ├── media/
│   │   ├── SSD-schema-reductive-views.png
│   │   ├── d2i-logo.png
│   │   ├── ddsf-ssd-cover.png
│   │   ├── deployment-week0-3-flow.png
│   │   ├── dfe-csc-api-data-flows-releases.png
│   │   ├── ssd-data-model-deployment-extracts.png
│   │   ├── ssd-schema-map.png
│   │   └── week0-project-prep.png
│   └── index.html
├── docs/
│   ├── _partials/
│   │   ├── release_checklist.md
│   │   ├── release_included_excluded.md
│   │   ├── release_manifest_packaging.md
│   │   ├── release_mermaid_overview.md
│   │   ├── release_versioning.md
│   │   └── troubleshooting.md
│   ├── overrides/
│   │   └── pdf/
│   │       └── default.html.j2
│   ├── theme/
│   │   ├── cover.md
│   │   └── default_cover.html.j2
│   ├── UNPUBLISHED-analyst_local_testing.md
│   ├── UNPUBLISHED-feature_backlog.md
│   ├── admin-actions_workflow_overview.md
│   ├── admin-add_files_to_release_build.md
│   ├── admin-cli_interface.md
│   ├── admin-make_proxy_changes.md
│   ├── admin-release_process.md
│   ├── api_config.md
│   ├── api_powershell_deployment.md
│   ├── api_powershell_guidance.md
│   ├── api_python_deployment.md
│   ├── data_security.md
│   ├── deploy_ssd_schema.md
│   ├── index.md
│   ├── json_payload_structure.md
│   ├── release.md
│   ├── roadmap_implementation.md
│   ├── roadmap_la_deployment.md
│   ├── stakeholders.md
│   ├── system_requirements.md
│   ├── test_api.md
│   └── troubleshooting_faq.md
├── pre_flight_checks/
│   ├── api_credentials_smoke_test.ps1
│   └── ssd_vw_csc_api_schema_checks.sql
├── .gitattributes
├── .gitcliff.toml
├── .gitignore
├── CHANGELOG.md
├── LICENSE
├── MANIFEST.in
├── README.md
├── mkdocs.yml
├── pyproject.toml
├── pytest.ini
├── release.sh
├── requirements.txt
├── sccm.yml
├── sccm_graph_static.svg
└── setup.sh
```
