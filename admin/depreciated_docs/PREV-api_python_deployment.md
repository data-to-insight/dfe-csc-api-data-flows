# API Python Deployment

This guide covers running the **Python** implementation of the CSC API Pipeline, either directly (`python -m ...`) or as a packaged `.exe` built from the Python code.

> If you prefer to avoid installing Python on servers, use the `.exe` from Releases and see the **PowerShell Deployment** page for scheduling/ops patterns. The Python page remains the canonical reference for configuration and behaviour.

---

## Prerequisites

- **Python 3.11+** on the target host (for native Python runs).
- **ODBC Driver for SQL Server** and network access to your reporting DB.
- Access to DfE API credentials (see **API Configuration**).
- Permissions to run as a scheduled task/service account (for automation).

---

## Install (Wheel)

From a machine with internet access (or internal mirror):

```bash
pip install csc_api_pipeline-<version>-py3-none-any.whl
```

Or from source checkout:

```bash
pip install .
```

Validate install:

```bash
python -m api_pipeline --help
```

---

## Configure

1) Copy `.env.example` to `.env`.  
2) Fill in DB and DfE API credentials. See **API Configuration**.

> Keep `.env` alongside the program working directory used by your scheduler, or configure the service user’s environment variables accordingly.

---

## Run Manually (First-Time Verification)

```bash
python -m api_pipeline test_db_connection
python -m api_pipeline test-endpoint
python -m api_pipeline test-schema
python -m api_pipeline run
```

Expected behaviour:
- `test_db_connection` confirms DB connectivity.
- `test-endpoint` checks token/auth and API reachability.
- `test-schema` validates presence of required tables/fields.
- `run` extracts eligible rows, builds payloads, submits (or simulates in testing mode), and updates statuses.

---

## Scheduling (Windows Task Scheduler)

1. Create a **basic task** (e.g., “CSC API Pipeline – Daily”).  
2. **Trigger:** Daily at `02:00` (adjust to your overnight window).  
3. **Action:** Start a program  
   - Program/script: `python`  
   - Arguments: `-m api_pipeline run`  
   - Start in: `C:\path\to\working_dir` (where `.env` resides)
4. **Run whether user is logged on or not**; use a dedicated service account.
5. Enable **“Stop the task if it runs longer than …”** (e.g., 2 hours).
6. Configure **retry** on failure (e.g., 3 attempts, 10 minutes apart).

> For Linux, use `cron`/`systemd` with the same command and environment.

---

## Logging

- By default, the pipeline logs to STDOUT/STDERR. Redirect output to a file in the scheduler configuration if desired:
  - PowerShell task action example:  
    `python -m api_pipeline run *> C:\logs\csc_api_pipeline\%DATE%.log`
- Consider rotating logs (e.g., Windows built-in rotation or a scheduled cleanup).

---

## Validation Checklist

- [ ] `.env` present with DB/API values
- [ ] `test_db_connection` success
- [ ] `test-endpoint` success
- [ ] `test-schema` success
- [ ] `run` updates `submission_status` and `row_state` as expected
- [ ] Hash/previous payload behaviours observed (e.g., after successful send, `previous_json_payload` updated)

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `pyodbc.InterfaceError` | Missing ODBC driver | Install “ODBC Driver 17/18 for SQL Server”. |
| Auth failures | Bad CLIENT_ID/SECRET/SCOPE or token URL | Re-check `.env` values; verify time sync on host. |
| No eligible rows | `row_state`/`submission_status` not set | Confirm staging query logic and test data seeding. |
| “Permission denied” writing logs | Scheduler account lacks rights | Grant write permissions to log folder. |

---

## Packaging to `.exe` (Optional)

If you need a portable single-file executable built internally:

```bash
pyinstaller api_pipeline/entry_point.py --onefile --name csc_api_pipeline
```

Deploy the resulting `dist/csc_api_pipeline.exe` together with your `.env` and any local config. Hash-verify as needed.
