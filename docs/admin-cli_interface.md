

# Admin – CLI Interface

!!! info "Scope & Audience"
    This page documents the **command‑line interface (CLI)** for the `api_pipeline` package and the bundled `.exe`.  
    It covers both **source (Python)** and **binary (EXE)** usage, including the built‑in **diagnostic tests** from `test.py`.

---

## Prerequisites

- Windows host (for EXE) or Python 3.10+ (recommended 3.11) for source usage.
- **ODBC Driver 18 for SQL Server** installed.
- Network reachability to your SQL Server and the CSC API.
- A configured `.env` (see `.env.example`) or equivalent environment variables.

### Required environment variables (minimum)
| Key | Purpose |
|---|---|
| `SQL_CONN_STR` | Full ODBC connection string to SQL Server (user/pwd or integrated security). |
| `TOKEN_ENDPOINT` | OAuth2 token URL (client credentials). |
| `CLIENT_ID` / `CLIENT_SECRET` | OAuth2 client credentials. |
| `SCOPE` | Token scope/audience expected by the API. |
| `API_ENDPOINT_LA` | **GET‑safe** endpoint used for connectivity checks (e.g., health/metadata). |
| `SUPPLIER_KEY` | Supplier identifier header required by the API (if applicable). |

> Important: keep secrets out of scripts. Use `.env` or OS‑level secrets.

---

## Install / Run

**From EXE** (recommended for deployment):
```text
csc_api_pipeline.exe [command]
```

**From source** (developer/analyst):
```bash
python -m api_pipeline [command]
```

> All commands write diagnostics to **stdout**. Integrate with the scheduler or capture to log file.

---

## Quick start (no data needed)

To validate the environment **without any staging rows**, run the smoke diagnostics:
```text
csc_api_pipeline.exe smoke
# or
python -m api_pipeline --mode smoke
```
This will:
- open the DB and run `SELECT 1`,
- acquire an OAuth token,
- perform a harmless **GET** to `API_ENDPOINT_LA`,
- check key staging table columns (advisory).

**Expected success snippet:**
```
[OK] Database connection successful (SELECT 1)
[OK] Token acquired
[OK] API GET reachable
Required columns present: id, json_payload, partial_json_payload, submission_status
Summary:
  DB connectivity : PASS
  API GET/Auth    : PASS
  Schema advisory : PASS
```

---

## Usage

```text
Usage:
  csc_api_pipeline.exe [command]
  python -m api_pipeline [command]        # run from source

# No‑data smoke check (safe diagnostics; no staging rows required)
  csc_api_pipeline.exe smoke
  python -m api_pipeline --mode smoke     # alias for 'smoke'
```

---

## Command reference

| Command | What it does | Side‑effects | Needs staging rows? | Exit code |
|---|---|---|---:|---:|
| `run` | Full pipeline: load rows, build payloads, submit to API, update statuses. | **Yes** (writes to DB, calls API). | Optional | 0 on success; non‑zero on error |
| `smoke` | Composite **no‑data** diagnostics: DB `SELECT 1`, OAuth token, API GET, schema advisory. | **No** | No | 0 on pass; non‑zero if any probe fails |
| `test-endpoint` | Acquire token and perform a **GET** to `API_ENDPOINT_LA`. | No | No | 0 on 2xx; else non‑zero |
| `test-db-connection` | Connect using `SQL_CONN_STR` and execute `SELECT 1`. | No | No | 0 on success; non‑zero on failure |
| `test-schema` | Check required columns exist in `ssd_api_data_staging_anon`. | No | **Table required** | 0 if present; non‑zero if missing |

> **GET‑safe endpoint:** Ensure `API_ENDPOINT_LA` is a safe GET (e.g., health/metadata). If your primary API is POST‑only, configure a separate health URL in your `.env`.

---

## Command details & examples

### `run` — full pipeline
Runs your end‑to‑end submission flow: reads staging rows, computes payloads (full/partial), submits to the API with retry logic, and updates `submission_status`, `row_state`, and related columns.

**Examples**
```text
csc_api_pipeline.exe run
python -m api_pipeline run
```
**Typical results**
- On 200‑OK: `submission_status = 'sent'`, `previous_json_payload` updated, timestamps/logs recorded.
- On failure after retries: `submission_status = 'error'` (or equivalent).

---

### `smoke` — no‑data diagnostics
Chains the built‑in tests; ideal for first‑time setup and support tickets.

**Examples**
```text
csc_api_pipeline.exe smoke
python -m api_pipeline --mode smoke
```

**Pass/Fail logic**
- Pass requires: DB connectivity + token acquisition + API GET 2xx + required schema columns present.
- Non‑zero exit code if any probe fails.

---

### `test-endpoint` — API connectivity & auth
Obtains an OAuth token and performs a harmless GET to validate outbound HTTPS, headers, and trust store.

**Examples**
```text
csc_api_pipeline.exe test-endpoint
python -m api_pipeline test-endpoint
```

**Common issues surfaced**
- Wrong `SCOPE` / audience or token URL.
- Proxy/TLS inspection breaking cert validation.
- Missing `SUPPLIER_KEY` (if required by the API).

---

### `test-db-connection` — SQL connectivity
Confirms ODBC driver and credentials are correct using `SELECT 1` (no write).

**Examples**
```text
csc_api_pipeline.exe test-db-connection
python -m api_pipeline test-db-connection
```

**If it fails**
- Verify `SQL_CONN_STR` (server, database, auth).
- Ensure **ODBC Driver 18 for SQL Server** is installed.
- Check firewalls/VPN routing.

---

### `test-schema` — staging table shape
Checks the required columns in `ssd_api_data_staging_anon`:
- **Required:** `id`, `json_payload`, `partial_json_payload`, `submission_status`
- **Recommended:** `row_state`, `previous_json_payload` (informational)

**Examples**
```text
csc_api_pipeline.exe test-schema
python -m api_pipeline test-schema
```

**Notes**
- Uses `SELECT TOP 0 *` for speed—no data is read.
- Will return non‑zero if the required columns are missing.

---

## Exit codes

- `0` — Success / pass
- Non‑zero — Failure (at least one check or step failed)

Use these codes in Scheduled Tasks or CI to detect failures.

---

## Scheduling (Windows Task Scheduler)

- **Program/script:** `C:\path\to\csc_api_pipeline.exe`  
- **Arguments:** `run` (or `smoke`, etc.)  
- **Start in:** `C:\path\to\deployment\folder`

**Logging tip:** redirect console output
```text
csc_api_pipeline.exe smoke > logs\smoke_%DATE:~10,4%-%DATE:~4,2%-%DATE:~7,2%.log 2>&1
```

Ensure the service account has:
- "Log on as a batch job"
- Read/write permissions to the deployment and logs folders
- Access to `.env`/secrets

---

## Troubleshooting checklist

- **Try `smoke` first** — fastest way to pinpoint which layer fails.
- **DB fails:** check `SQL_CONN_STR`, ODBC Driver 18, firewall/VPN.
- **Token fails:** verify `CLIENT_ID/SECRET`, `TOKEN_ENDPOINT`, `SCOPE`.
- **API GET fails:** confirm `API_ENDPOINT_LA` is GET‑safe and not blocked by proxy/TLS inspection.
- **Schema fails:** create/alter `ssd_api_data_staging_anon` and rerun.

For deeper issues, see: *Troubleshooting & FAQ*.



**Last verified:** 18/08/2025 