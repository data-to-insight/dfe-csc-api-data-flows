
# CSC API Pipeline – Release Overview

This page provides an overview of official releases of the **CSC API Pipeline** tool. 
It includes a brief changelog, download instructions, and what D2I expect to be in each releasse package.

> You can visit the GitHub Releases page directly:  
> [https://github.com/data-to-insight/dfe-csc-api-data-flows/releases](https://github.com/data-to-insight/dfe-csc-api-data-flows/releases)

---

## Download

- **Primary:** GitHub Releases → latest tag for this project
  URL: https://github.com/data-to-insight/dfe-csc-api-data-flows/releases

Each release typically includes (may vary during pilot):

| File | Description |
|------|-------------|
| `csc_api_pipeline.exe` | Windows executable (standalone runner) |
| `csc_api_pipeline-*.whl` | Python Wheel package (for pip install) |
| `csc_api_pipeline-*.tar.gz` | Source distribution (for building manually) |
| `release.zip` | Bundled zip with scripts, docs, `.exe`, and SQL |
| `.env.example` | Example or template environment config file |
| `phase_1_api_payload.ps1` | PowerShell script for phase 1 & data-flow testing |
| `populate_ssd_api_data_staging.sql` | SQL setup script for staging data |

> If you're not sure what to download, firstly do speak to your IT/Infrastructure/Project team before running anything from these release files, then start with the `.exe` or the `release.zip` or get in touch with us(D2I).

---

# Verify Downloads

To ensure the authenticity and integrity of the downloaded files from the CSC API Pipeline GitHub release, verify them using the provided SHA-256 checksums. Git release page displays the SHA-256 checksum for each file. 

---

## Verify Windows, PowerShell

### Windows PowerShell
```powershell
Get-FileHash .\csc_api_pipeline.exe -Algorithm SHA256
```
Compare with the hash shown next to the asset on the Releases page.

### Linux/macOS
```bash
sha256sum csc_api_pipeline.exe
```

Compare the hash result with the one shown on the [GitHub Releases page](https://github.com/data-to-insight/dfe-csc-api-data-flows/releases).


Or for other files:

```bash
sha256sum phase_1_api_payload.ps1
sha256sum populate_ssd_api_data_staging.sql
```


---


## Changelog

### v0.1.2 
**Released:** 13/08/2025  **Tag:** `v0.1.2`  

**Changes**
- Updated `release.sh` to:
  - Auto-increment and tag versions based on latest release
  - Bump version in `pyproject.toml` and commit the change
  - Include `.ps1` and `.sql` helper scripts in the release bundle
- Ensured `.whl`, `.tar.gz`, and `.zip` archives are consistently built and included
- Added a safety check to only run the release script from the `main` branch
- Added summary output showing bundled contents after release
- Improved inline documentation for the release script and workflows

#### Notes
- Release focused on cleanup/consistency/usability improvements in packaging and deployment process  
- Release re-aligns local `release.sh` script and GitHub Actions workflow 
- Supporting documentation and helper scripts bundled


### v0.1.1
**Released:** 30 June 2025  **Tag:** `v0.1.1`

**Changes:**
- Initial CLI refactor with `entry_point.py`
- Added support for running as `.exe` via PyInstaller
- New `release.sh` script for automating version bumps and packaging
- Improved documentation and CLI help text output
- GitHub Actions now builds and uploads `.exe`, docs, and `.env.example`

---


## Release Process (for Devs)

- Versioning follows semantic versioning (`v0.1.0`, `v1.2.3`, etc.)
- Releases are made from the `main` branch only
- Packaging is handled by `release.sh` and Git Actions
- Assets are uploaded automatically with each release tag

---


## What Should I Download?

- **Most LAs (if awaiting Python|Anaconda install):** download `csc_api_pipeline.exe` (or `release.zip`) and follow **API PowerShell Deployment** _or_ **API Python Deployment** depending on your preferred runtime.
- **Teams with Python 3.11+:** download the **`.whl`** and follow **API Python Deployment**.
- **Audit/Build engineers:** download **`.tar.gz`** and rebuild locally if required.