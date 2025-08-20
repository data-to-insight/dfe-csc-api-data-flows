# CSC API Pipeline – Release Process Guide

Explanation of how **build and release** process for CSC API Pipeline project is structured, plus what steps devs when prepping a new release.  
Aimed to offer enough info that anyone in d2i team can manage releases.

---

## Introduction

The CSC API Pipeline is packaged and released as versioned distribution with optional Windows executables.  
Releases are **automated via Git Actions**, but process is **initiated manually** by running the helper script (`release.sh`) inside Codespaces.

To ensure consistency:
- **Version numbers** are managed in `pyproject.toml`
- **Git tags** (e.g. `v0.2.1`) drive release workflows - i.e. run `release.sh` and increment release number  
- A **single combined Git workflow** (`release-and-docs.yml`) handles all build, test, and publish steps  

---

## What Gets Released

### Included files
Release bundle constructed in 2 ways:
1. **PEP 517 build system** – creates Python package (`.tar.gz` and `.whl`) inside `dist/`
   Those contain only package code declared in `pyproject.toml` and `MANIFEST.in`
2. **Release bundle** – a convenience archive (`release.zip`) built by `release.sh`, containing:
   - The Python distribution files (`dist/*`)
   - `README.md` (for end-user ref)
   - `.env.example` (sample environment config)
   - Deployment helpers: PowerShell and SQL scripts (part of the needed LA setup)
   - Optional Windows `.exe` if built locally with PyInstaller (contains only API related)

### Excluded files
During packaging and bundling process **explicitly exclude**:
- Development caches (`__pycache__/`, `.pytest_cache/`, `.coverage/`)
- IDE/project files (`.vscode/`, `.idea/`)
- Build directories (`build/`, `dist/`, old `*.egg-info`)
- Test artefacts not required in distribution  

> Full list of incl/excl files maintained in **`pyproject.toml`** and **`MANIFEST.in`**.  
> If you need to add or remove files from Python package, update those  
> If you need to alter wider release bundle, adjust `release.sh`

---

## Release Versioning

Release follows **semantic versioning (SemVer)**:
- **MAJOR** – incompatible changes  
- **MINOR** – new functionality (backwards compatible)  
- **PATCH** – bug fixes or small updates  

Eg:
- `0.2.0` → minor release with new features  
- `0.2.1` → patch release with bug fixes  
- `1.0.0` → stable release milestone  

In practice:
- Tags always prefixed with `v`, e.g. `v0.2.1`
- Version in `pyproject.toml` **must match** numeric form without `v` (e.g. `0.2.1`) but see next.. 
- `release.sh` keeps these in sync automatically: it updates `pyproject.toml`, commits if required, and applies Git tag

---

## Manifest and Packaging

The Python packaging toolchain (via `build`) respects two files:
- **`pyproject.toml`** – defines project metadata (name, version, dependencies)
- **`MANIFEST.in`** – controls extra non-code files (e.g., `.env.example`, SQL scripts) that should be packaged

Together they define **what the end-user receives** when installing from PyPI (if published there) or when unzipping release file.

---

## Single Workflow?

Originally, repo had **split workflows** (separating builds, documentation, and release jobs). 
This caused concurrency issues:
- Problems with jobs stepping on each other - unable to run as the other not completed  
- Releases firing before documentation had been updated  

Hence **merged everything into one workflow** (`release-and-docs.yml`) with controlled job sequencing.  
Which now gives us:
- One canonical release pipeline  
- Artefacts built once  
- Bit easier to manage in some cases, i.e. fewer moving parts  

---

## Overview (Mermaid)

```mermaid
flowchart TD
    A[Dev runs <code>./release.sh</code>] --> B[Clean caches & old artefacts]
    B --> C[Normalise version<br/>(PEP 440 in <code>pyproject.toml</code> + <code>vX.Y.Z</code> tag)]
    C --> D[Build sdist & wheel<br/>(<code>dist/*</code>)]
    D --> E[Twine metadata check + smoke test venv]
    E --> F[Create <code>release_bundle/</code> + <code>release.zip</code>]
    F --> G{Confirm push?}
    G -- yes --> H[Push <code>main</code> + tag <code>vX.Y.Z</code>]
    G -- no --> X[Stop: no release triggered]
    H --> I[Git Actions: <code>release-and-docs.yml</code>]
    I --> J[Build & test jobs]
    J --> K[Publish artefacts / docs]
    K --> L[Create/Update Git Release]
    L --> M[Release assets available for download]
```

---

## The Release Script (`release.sh`)

The `release.sh` script is the single entry point for maintainers. It is located in the repo root and must be run from within a Codespace or shell session.

### What it does
1. Confirms you're on `main` and working tree clean  
2. Prompts for new version (default: last tag + patch bump)  
3. Updates `pyproject.toml` if the version has changed, commits this   
4. Cleans caches and previous build artefacts  
5. Builds package (`sdist` + `wheel`), checks metadata, and smoke tests it in a fresh venv  
6. Optionally builds `.exe` (if on Windows)  
7. Creates `release_bundle/` and `release.zip`  
8. Prompts to tag and push (`git push origin main` + new tag)  

### How to run it
```bash
chmod +x release.sh        # once only, make executable
./release.sh
```

When prompted:
- Enter version (or accept default)  
- Confirm push to origin (this triggers Git Actions)  

The Git workflow (`release-and-docs.yml`) will then build and publish release automatically.

---

## Checklist for Maintainers

- [ ] Pull latest changes from `main`  
- [ ] Run `./release.sh`  
- [ ] Confirm version and tag push  
- [ ] Check Git Actions run (`release-and-docs.yml`) for success  
- [ ] Validate published release artefacts  

---

## Troubleshooting

- **Workflow did not trigger** → check that the tag pushed starts with `v` (e.g. `v0.2.1`)  
- **Version mismatch** → ensure `pyproject.toml` matches intended tag (script should enforce this)  
- **Artefacts missing** → check `MANIFEST.in` and `release.sh` copy list  
- **Historic clutter** → only current release remains visible; old workflows/runs have been cleaned to keep repo manageable  

---

## Appendix: Where to change what

- Add/remove package files → `pyproject.toml` & `MANIFEST.in`  
- Adjust bundle contents → `release.sh` (copy list to `release_bundle/`)  
- Change trigger logic or jobs → `.Git/workflows/release-and-docs.yml`  
- Secret rotation / credentials → repo or org secrets in Git settings
