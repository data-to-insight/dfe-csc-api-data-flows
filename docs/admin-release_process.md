# CSC API Pipeline – Release Process Guide

Infos regarding the build and release process for CSC API Pipeline project, including the needed process for prepping a new release  
so that anyone in D2I team can manage releases. 

---

## Introduction

CSC API Pipeline packaged and released as versioned distribution with optional Windows executables  
release is automated via Git Actions, but kcik off process initiated manually by running the helper script `release.sh` inside a Codespace.

For consistency
- version numbers managed in `pyproject.toml`  
- git tags eg `v0.2.1` drive release workflow, so running `release.sh` will increment release number  
- git actions workflow `release-and-docs.yml` (auto)handles the rest

---

--8<-- "_partials/release_included_excluded.md"

--8<-- "_partials/release_versioning.md"

--8<-- "_partials/release_manifest_packaging.md"

--8<-- "_partials/release_mermaid_overview.md"

---

## Release Script `release.sh`

Entry point for dev/d2i, within repo root, & run from within Codespace (or Shell)

### does the following
1. confirm on `main` and working tree clean
2. prompt for new version default last tag + patch bump
3. update `pyproject.toml` if version changed and commit
4. clean caches and previous build artefacts
5. build package sdist + wheel, run metadata check, smoke test in fresh venv
6. optionally build `.exe` if on Windows
7. create `release_bundle/` and `release.zip`
8. prompt to tag and push `git push origin main` plus new tag

### run via
```bash
chmod +x release.sh
./release.sh
```

when prompted
- enter version or accept default
- confirm push to origin to trigger Git Actions

git workflow `release-and-docs.yml` then builds and publishes release automatically

---

--8<-- "_partials/release_checklist.md"

--8<-- "_partials/troubleshooting.md"

## Appendix: make release changes

- add or remove package files -> `pyproject.toml` and `MANIFEST.in`
- adjust bundle contents -> `release.sh` copy list to `release_bundle/`
- change trigger logic or jobs -> `.github/workflows/release-and-docs.yml`
- secret rotation and credentials -> repo or org secrets in Git settings (obv no secrets in repo!)
