# API Python Deployment

This page explains **how to run the Python implementation** of the CSC API Pipeline in three common ways:
1) Install from a **wheel (.whl)** and run the CLI
2) Run the **Jupyter/Anaconda notebook** for local/analyst testing
3) Run the **raw Python sources** (repo checkout) without installing a package

It also describes a **two‑stage rollout**: Analyst local tests → Server/overnight deployment by IT.

> If you do not want to install Python on servers, you can use the packaged **Windows `.exe`** (see *API Download* and *API PowerShell Deployment* for scheduling patterns).

> Note: As the project remains in pilot/alpha stage(s), there may have been changes in released/current code that differs from or is not reflected in some parts of the documentation detail. Colleague observations and feedback welcomed towards improving this for everyone.

---

## Log SSD/API support tickets  

 - **Phase1 & Phase 2 LAs/deployment teams should [Log deployment bugs, required changes or running issues via](https://github.com/data-to-insight/dfe-csc-api-data-flows/issues) - the basic/free Github account may be required for this**  
 
 - **LA colleagues are also encouraged to send the project your [general feedback, or your deployment requirements](https://forms.gle/rHTs5qJn8t6h6tQF8)**  

---

## Dependencies (net access)

- **Local wheel file only:** Example:
  ```bash
  pip install C:\path\to\csc_api_pipeline-<version>-py3-none-any.whl
  ```

- **If dependencies are missing:** `pip` may try to fetch them from PyPI. To stay **offline**, provide a local folder with all wheels and use:
  ```bash
  pip install --no-index --find-links C:\path\to\wheelhouse C:\path\to\csc_api_pipeline-<version>-py3-none-any.whl
  ```
  where `wheelhouse/` contains wheels for required dependencies (e.g. `pyodbc`, `python-dotenv`, etc.).

- **From source (`pip install .`)**: may need internet to download/build dependencies unless you maintain an internal mirror/wheelhouse.

---

## Recommended: Use a Virtual Environment (isolated)

**venv (Python standard):**
```bash
python -m venv .venv
# Windows
.\.venv\Scripts\activate
# Linux/macOS
source .venv/bin/activate

pip install --upgrade pip
pip install C:\path\to\csc_api_pipeline-<version>-py3-none-any.whl
```

**Conda (Anaconda/Miniconda):**
```bash
conda create -n csc_api py=3.11 -y
conda activate csc_api
pip install C:\path\to\csc_api_pipeline-<version>-py3-none-any.whl
```

---

## Configure (shared pattern)

Place a `.env` file in the **working directory** used to run the commands (or set environment variables). See **API Configuration** for keys.

```ini
DB_CONNECTION_STRING=Driver={ODBC Driver 17 for SQL Server};Server=SERVER\INSTANCE;Database=HDM_Local;Trusted_Connection=yes;
TOKEN_ENDPOINT=...
API_ENDPOINT=...
CLIENT_ID=...
CLIENT_SECRET=...
SCOPE=...
SUPPLIER_KEY=...
DEBUG=true
```

> Keep secrets out of source control. Restrict file permissions to the service/analyst account.

---

## 1) Install & Run from Wheel (CLI)

Install the wheel (offline or online as above), then:

```bash
python -m api_pipeline --help
python -m api_pipeline test-db-connection
python -m api_pipeline test-endpoint
python -m api_pipeline test-schema
python -m api_pipeline run
```

Expected behaviour:
- `test-db-connection` checks DB connectivity
- `test-endpoint` validates token acquisition/API reachability
- `test-schema` confirms required tables/fields
- `run` performs the submission process (or simulates if testing mode enabled in config)

**Scheduling (Windows task example):**
- Program: `python`
- Arguments: `-m api_pipeline run`
- Start in: folder containing `.env`

---

## 2) Analyst Local|Initial Testing via Jupyter/Anaconda

The release bundle includes **`dfe_csc_api_testing.ipynb`** designed for analyst‑led, local smoke tests before server rollout.

**Setup (Conda example):**
```bash
conda create -n csc_api_notebook py=3.11 -y
conda activate csc_api_notebook
pip install C:\path\to\csc_api_pipeline-<version>-py3-none-any.whl  # or `pip install .` from source
pip install jupyterlab  # if not already installed
jupyter lab
```

- Open `dfe_csc_api_testing.ipynb`.
- Ensure `.env` is present in the working dir (or set env vars in the notebook).
- Run the cells in order. The notebook imports and calls the same package modules used by the CLI.

> Jupyter is ideal for **visible diagnostics** and exploring partial/delta behaviour with safe test data before requesting server deployment.


### (Alternative) Zero‑install “Folder‑only” Notebook Run

If you’re **less comfortable with `pip`/environments**, you can do a simple, contained, folder‑only run that many analysts find easier:

1. **Make a new folder** on your machine (e.g. `C:\CSC_API_LocalTest\`)  
2. Copy all `.py` files **into that folder** (from the release bundle or repo):
   - `dfe_csc_api_testing.ipynb` (the notebook)  
   - The contents of **`api_pipeline/`** folder with the `.py` modules (e.g., `entry_point.py`, `db.py`, etc.)  
   - `.env.txt` (a **redacted** config template with your LA's DfE details). Keep secrets safe  
3. Launch Jupyter (`jupyter lab`) and **open the notebook** in that folder  
4. In the **first cell** of the notebook, insert this helper so the local code + `.env.txt` are picked up without any installs:
5. Run the notebook cells in order(or just Run all). The notebook will import the **local** `api_pipeline` modules from the folder you created  

**Note**  
- This avoids installing the wheel and keeps everything self‑contained for quick trials  
- If `python-dotenv` isn’t present, the notebook will complain. Easiest fix: install once with `pip install python-dotenv` inside your notebook environment  

---

## 3) Run from Raw Sources (no wheel)

If you have the repo/source tree:

```bash
pip install -r requirements.txt   # or install deps via your own wheelhouse
# Option A: module
python -m api_pipeline run
# Option B: direct entry point
python api_pipeline/entry_point.py
```

This approach is common for development or pilot evaluations.

---

## Two‑Stage Rollout Model (recommended)

### Stage A – Analyst Local Smoke Tests
- Create an isolated environment (`venv` or `conda`).
- Install the **wheel** or use the **notebook**.
- Prepare `.env` with **testing mode** values and a **non‑live** staging table (e.g. `_anon`).
- Run:
  - `python -m api_pipeline test_db_connection`
  - `python -m api_pipeline test-endpoint`
  - `python -m api_pipeline test-schema`
  - `python -m api_pipeline run`
- Capture logs/output and confirm `row_state` and `submission_status` transitions.

**Hand‑off artefacts to IT:**
- The exact `.whl` used (or `.exe` if that route is chosen)
- A redacted `.env.example` showing required keys
- Notebook (optional) + any validation screenshots
- A short “Server Runbook” note: command line, working dir, log path

### Stage B – Server/Overnight Deployment
- Create a **service account** with required DB/API access.
- Install Python (or use the `.exe` route).
- Install the **wheel** from shared storage (offline install if required).
- Place a production `.env` in the scheduler’s **Start in** folder.
- Configure a **Task Scheduler**/`cron` job to run `python -m api_pipeline run`.
- Enable retries and log redirection/rotation.
- Switch from test to **live** staging table/flags per go‑live plan.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `pyodbc.InterfaceError` | ODBC driver missing | Install “ODBC Driver 17/18 for SQL Server”. |
| `pip` tries internet but you’re offline | Missing deps | Build a **wheelhouse** and use `--no-index --find-links` |
| “Module not found” after install | Wrong environment | Activate the correct `venv`/conda env before running |
| No eligible rows processed | Staging not primed | Seed test rows and verify `row_state` + `submission_status` |
| Auth/token errors | Client secret/scope or clock skew | Verify `.env`; check server time sync/NTP |

---

## Packaging to `.exe` (optional, internal)

```bash
pyinstaller api_pipeline/entry_point.py --onefile --name csc_api_pipeline
```
Distribute the `.exe` with a local `.env`. Use hash verification as described in **Release Overview**.




---
---

## Python wheel (.whl)

A **wheel** is Python’s standard built package format. Installing a wheel with `pip`:
- **Copies** prebuilt code into your Python environment (no compiling)
- **Does not require internet** if you install from a local file and already have dependencies available
- Is repeatable for IT/Infrastruture/Deployment team: place the `.whl` on a server share and install in a controlled environment

> In short: the `.whl` is like an MSI/installer for Python packages

