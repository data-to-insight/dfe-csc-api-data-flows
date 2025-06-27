## ✅ GitHub Actions Workflow Overview

This repository uses **three GitHub Actions workflows**, each with specific purpose:

---

### 1. `build-api-pipeline.yml`

**Purpose:**  
Builds Python package (`.tar.gz`, `.whl`) from `api_pipeline/` folder and uploads as GitHub Actions artifact.

**Trigger:**  
Push to `main` branch or pull request.

**Use case:**  
Enables downloadable Python packages for local install without PyPI.

---

### 2. `release-pyinstaller.yml`

**Purpose:**  
Compiles code into standalone Windows `.exe` using PyInstaller, then attaches these files to GitHub Release:
- `csc_api_pipeline.exe`
- `.env.example`
- `README.md`

**Trigger:**  
Push of version tag (e.g. `v1.2.3`) or GitHub Release event.

**Use case:**  
Supports direct distribution of executable builds via GitHub Releases, avoids Python dependency.

---

### 3. `gh-pages.yml`

**Purpose:**  
Builds and deploys MkDocs documentation site to GitHub Pages.

**Trigger:**  
Push to `main` branch.

**Use case:**  
Publishes static documentation using MkDocs and Material theme.

---

### Summary Table

| Workflow File              | Description                             | Trigger                   | Required |
|----------------------------|-----------------------------------------|---------------------------|----------|
| `build-api-pipeline.yml`   | Builds and uploads `.whl`, `.tar.gz`    | Push to `main`, PR        | ✅       |
| `release-pyinstaller.yml`  | Builds `.exe`, attaches `.env` + README | Release or version tag    | ✅       |
| `gh-pages.yml`             | Deploys MkDocs site to GitHub Pages     | Push to `main`            | ✅       |
