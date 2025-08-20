# API PowerShell Deployment

This guide covers running the **PowerShell-driven** flow used in early pilot and Phase 1 testing. It remains a valid option for environments without managed Python, and aligns with the same staging table and expected API behaviours.

> The **Python** implementation is the strategic path for everyone heading to Phase 2 (deltas/partials). Use this page if you need a lightweight operational path or cannot initially/yet deploy Python.

_Note: We believe that access to MS Powershell within LA's is more commonplace, than other scripting options. Thus we have assumed compatibility for at least this until such point that the pilot/early adopter group are able to contribute to the project understanding regarding local restrictions. However, the level of data manipulation needed to achieve the sending of data deltas required in Phase 2, we believe will require a shift to processes run using Python, not Powershell._

_The exploratory nature of this pilot, equates to some as-yet-unknowns to both the anticipated tech stack and implementation requirements. D2I have developed towards a Python driven solution that can function across both Phase 1 and Phase 2. Previous development has enabled a Powershell version that we can test with LA's locally whilst the technical questions around deploying Python are reviewed by IT/infrastructure services/compliance_

---

## Prerequisites

- **PowerShell 5.1+**
- **SqlServer** module:  
  ```powershell
  Install-Module -Name SqlServer -AllowClobber -Scope CurrentUser
  ```
- Network access to reporting DB and outbound to DfE token/API endpoints.
- DfE credentials (see **API Configuration**).

---

## Obtain Scripts

From the project release bundle (`release.zip`) or repo `scripts/` (if provided). Example filenames:

- `phase_1_api_payload.ps1` *(testing-mode friendly)*
- `ssd_json_payload-sql-server-agent_vX.Y.Z.ps1` *(production‑leaning)*

> Filenames may vary slightly during the pilot – follow the same variable names and flags described below.

---

## Configure

Open the script and set variables (or pass as parameters):

```powershell
$testingMode   = $true        # true = simulate/no external send
$server        = "ESLLREPORTS00X"
$database      = "HDM_Local"

$tokenEndpoint = "..."        # from DfE
$apiEndpoint   = "..."
$clientId      = "..."
$clientSecret  = "..."
$scope         = "..."
$supplierKey   = "..."
```

For table expectations and flag semantics see **API Configuration**.

---

## First-Time Test Run

Run from an elevated PowerShell prompt in a working directory with write permissions:

```powershell
.\phase_1_api_payload.ps1
```


Check:
- console/log output
- changes to `submission_status` and `row_state` in staging tables
- when `testingMode = $true`, ensure **no external** submission occurs

---

## Switch to Live

Set:
```powershell
$testingMode = $false
```
Re-run the script. Confirm that eligible records are submitted and statuses change to `sent` (on success) or `error` (after retries).

---

## Scheduling (SQL Server Agent or Task Scheduler)

Fully implemented scheduling will only be in place once the refresh mechanisms are agreed and in place for the SSD data to be refreshed. SSD data is by default in static tables, and as such needs it's own refresh policy/workflow to be set up|included. 

### Option A – SQL Server Agent (on DB servers)

- Create a **PowerShell Job Step** invoking your `.ps1` with a service account.
- Configure schedule (e.g., daily at 02:00) and notifications on failure.
- Store logs to a shared drive accessible to support.

### Option B – Windows Task Scheduler

- **Action:** `powershell.exe`
- **Arguments:** `-ExecutionPolicy Bypass -File "C:\path\phase_1_api_payload.ps1"`
- **Start in:** working folder containing any local config
- **Triggers:** Overnight window
- **Run as:** Service account with DB/API access
- **Retries:** 3 attempts, 10 minutes apart
- **Stop if running longer than:** 2 hours

---

## Logging

Add transcript/log redirection to your command line or script:

```powershell
Start-Transcript -Path "C:\logs\csc_api_pipeline\$(Get-Date -Format yyyy-MM-dd_HHmm).log"
# ... script body ...
Stop-Transcript
```

Or use:
```powershell
.\phase_1_api_payload.ps1 *>> "C:\logs\csc_api_pipeline\$(Get-Date -Format yyyy-MM-dd).log"
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `Invoke-Sqlcmd` not found | SqlServer module missing | `Install-Module SqlServer` |
| Auth/token errors | Wrong client secret/scope or clock skew | Verify values, NTP/time sync |
| No updates in staging | Filter/WHERE or flags not set | Seed test rows; check `row_state`/`submission_status` |
| Script blocked | Execution policy | Use `-ExecutionPolicy Bypass` for the scheduled action |

---

## Operational Notes

- PowerShell flow is simpler than the Py approach, but less feature‑rich and cannot handle the needed partial/delta logic
- For Phase 2, plan to migrate to **Python** for robust change‑detection and diagnostics
