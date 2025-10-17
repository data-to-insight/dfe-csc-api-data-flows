# Analyst Local Testing (Quick Start)

This page is a concise run‑sheet for analysts to validate connectivity and the end‑to‑end flow **from local pc** before requesting server deployment.

---

## Options

- **Notebook route (recommended initial approach):** `dfe_csc_api_testing.ipynb` in Anaconda/Jupyter
- **CLI route:** install the wheel and run `python -m api_pipeline …`
- **Source route:** run the raw `.py` files from the repo checkout

---

## Jupyter Notebook route

### Zero‑install 'Folder‑only' Notebook run

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

## CLI Route (wheel install)

```bash
python -m venv .venv
.\.venv\Scripts\activate   # or source .venv/bin/activate
pip install C:\path\to\csc_api_pipeline-<version>-py3-none-any.whl
python -m api_pipeline test-db-connection
python -m api_pipeline test-endpoint
python -m api_pipeline test-schema
python -m api_pipeline run
```

Place `.env` in the working folder used for the above commands.

---

## Source Route (no install)

```bash
pip install -r requirements.txt   # or use your wheelhouse
python -m api_pipeline run
# or:
python api_pipeline/entry_point.py
```

---

## What to Send to IT/Server or Infrastructure Team for Server Rollout

- The exact **`.whl`** (or `.exe`) used in testing
- A **redacted** `.env` from the supplied template `.env.example` showing required keys
- Any logs/outputs from your tests
- The **command** you used to run the pipeline and the **working directory** path
- Preferred schedule window and log retention expectations
