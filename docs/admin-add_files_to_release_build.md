# D2I Admin - Release change checklist
## adding or renaming shipped files

This guide describes how to include **new files** in your release outputs, and what to change when you **rename or move** files that are already shipped. It covers, in order, the **wheel**, **sdist**, **release.zip**, and the **CI workflows**. UK spelling, minimal ceremony, forward‑looking.

---

## 0) Decide what the file is for
Tick all that apply, then follow the steps below accordingly.

- Runtime asset inside the Python package, for example templates, SQL, PS1, notebooks
- Source artefact that should be present in the sdist for reproducibility
- Convenience copy that should be in `release.zip` and attached to GitHub Release
- Docs asset that must be part of the MkDocs build

> Rule of thumb, runtime assets go **inside** `api_pipeline/…`, everything else can live at the repo root and be grafted into the sdist or bundled via the release steps.

---

## 1) Wheel, include runtime assets in the package

### 1.1 If the file lives under `api_pipeline/…` and must ship in the wheel
Update `pyproject.toml` once, using wildcard patterns under `tool.setuptools.package-data`.

```toml
[tool.setuptools.package-data]
api_pipeline = [
  "notebooks/**",
  "pshell/*.ps1",
  "templates/*.json",        # example, add your new path
  "sql/*.sql"                # example, add if you move SQL inside the package
]
```

No need to touch `MANIFEST.in` for wheels, package‑data controls wheel content.

### 1.2 Runtime import path, no absolute paths, no `__file__` maths
Use `importlib.resources` to read packaged files, works in wheels and zips.

```python
from importlib import resources as ir

def get_pkg_path(rel: str) -> str:
    return str(ir.files("api_pipeline").joinpath(rel))

# examples
ps1 = get_pkg_path("pshell/api_payload_sender.ps1")
tpl = get_pkg_path("templates/example.json")
```
Keep this helper, it prevents path drift when you reorganise folders.

---

## 2) sdist, include sources for reproducibility

If the file is **outside** the package, add it to `MANIFEST.in`:

- New single file at repo root:
  ```ini
  include path/to/file.ext
  ```

- New folder tree of files:
  ```ini
  graft path/to/folder
  # or, pattern based
  recursive-include path/to/folder *.sql
  ```

If the file is **inside** `api_pipeline/…` and you want it visible in the sdist, add a graft too, for example:
```ini
graft api_pipeline/templates
```

Quick self‑check:
```bash
rm -rf build dist *.egg-info
python -m build --sdist --wheel
grep -E 'your/new/path|your/new/file' csc_api_pipeline.egg-info/SOURCES.txt || echo "Missing from sdist"
```

---

## 3) release.zip, copy into the bundle

Update both the **local** bundler and the **Windows workflow** bundler.

### 3.1 `release.sh` copy block
```bash
# add new line mirroring the others
cp path/to/your_new_file.ext release_bundle/ || true
# or, for a folder
cp -R path/to/new_folder/* release_bundle/new_folder/ || true
```

### 3.2 `.github/workflows/release-and-docs.yml` copy block
```powershell
# add new line mirroring the others
Copy-Item path	o\your_new_file.ext -Destination release_bundle# or a folder
Copy-Item path	o
ew_folder\* -Destination release_bundle
ew_folder\ -Recurse -Force
```

### 3.3 Add to the uploaded assets list
In the `softprops/action-gh-release` step, add the new relative paths:
```
files: |
  dist/*.whl
  dist/*.tar.gz
  release.zip
  path/in/repo/your_new_file.ext
```

---

## 4) CI, keep PR checks close to changes

If you added a **new path** not already watched by PR workflow, add it to `package-ci-pr.yml`:
```yaml
on:
  pull_request:
    paths:
      - 'api_pipeline/**'
      - 'sql_json_query/**'
      - 'scripts/**'
      - 'mkdocs.yml'
      - 'docs/**'
      - 'pyproject.toml'
      - 'MANIFEST.in'
      - 'release.sh'
      - '.github/workflows/release-and-docs.yml'
      - 'path/to/your_new_folder/**'  # add if needed
```

If the file is a docs asset, confirm the docs job builds locally and in the PR job:
```bash
pip install ".[docs]"
mkdocs build
```

---

## 5) When you rename or move an already‑shipped file

1. **Search and replace** all occurrences of the old path:
   ```bash
   git grep -n "old/path/name.ext"
   ```
   Update in:
   - `pyproject.toml` `package-data` if the pattern changes
   - `MANIFEST.in` include or graft patterns
   - `release.sh` copy block
   - `.github/workflows/release-and-docs.yml` copy block and the `files:` list
   - `package-ci-pr.yml` path filters if the directory changed
   - Any runtime code using `importlib.resources`, adjust the relative path

2. **Local sanity build**:
   ```bash
   rm -rf build dist *.egg-info
   python -m build --sdist --wheel
   twine check dist/*
   ```

3. **Dry run bundling**:
   ```bash
   bash release.sh   # stop before tagging if wanted, or run fully with pre-release tag
   ```

4. **Commit, PR, merge, tag**.

---

## 6) Tagging, recovering a failed release

If a release workflow on tag `vX.Y.Z` fails due to old paths in the YAML at that tag, you have two options:

### Option A, simplest, bump and supersede
- Commit the fixes
- Bump version in `pyproject.toml`, for example `X.Y.Z+1`
- Run `release.sh`, push the new tag, done
- Leaves history clean, avoids mutating an existing tag

### Option B, re‑point the same tag to the fixed commit
Only do this if you are comfortable rewriting tag history.

```bash
# Ensure the fixed workflow file is in the current commit on main
git tag -d vX.Y.Z
git push origin :refs/tags/vX.Y.Z   # delete remote tag
git tag vX.Y.Z
git push origin vX.Y.Z
```

If a GitHub Release object already exists for that tag, you can keep it. `softprops/action-gh-release` will update assets. If you prefer a clean slate, delete the Release in the GitHub UI before pushing the tag again.

---

## 7) Optional guards to prevent path drift

Add a preflight check in **both** bundlers.

### In `release.sh` after the version bump:
```bash
for f in   api_pipeline/pshell/phase_1_api_payload.ps1   api_pipeline/pshell/phase_1_api_credentials_smoke_test.ps1   sql_json_query/populate_ssd_api_data_staging_2016sp1.sql   sql_json_query/ssd_csc_api_schema_checks.sql
do
  [ -e "$f" ] || { echo "Missing expected file: $f"; exit 1; }
done
```

### In `release-and-docs.yml` before `Compress-Archive`:
```powershell
$required = @(
  "dist\csc_api_pipeline.exe",
  "README.md",
  "api_pipeline\.env.example",
  "api_pipeline\pshell\phase_1_api_payload.ps1",
  "api_pipeline\pshell\phase_1_api_credentials_smoke_test.ps1",
  "sql_json_query\populate_ssd_api_data_staging_2016sp1.sql",
  "sql_json_query\ssd_csc_api_schema_checks.sql"
)
$missing = @()
foreach ($p in $required) { if (-not (Test-Path $p)) { $missing += $p } }
if ($missing.Count -gt 0) {
  Write-Error ("Missing required files: " + ($missing -join ", "))
  exit 1
}
```

These fail early with a clear message instead of a later cryptic copy error.

---

## 8) Speed and stability tips

- Enable pip caching in all jobs using `actions/setup-python`, set `cache: pip`
- Keep the release and PR jobs in lockstep, use the same copy lists to avoid drift
- Prefer recursive patterns in `MANIFEST.in` for groups of files, it reduces maintenance
- Keep the runtime file access via `importlib.resources`, it is zip‑safe and wheel‑safe

---

## 9) Mini checklist, the 30‑second flow

1. Add or rename the file in the repo
2. If runtime and under `api_pipeline`, update `tool.setuptools.package-data`
3. Update `MANIFEST.in` include or graft rules if needed
4. Update `release.sh` copy block
5. Update `release-and-docs.yml` copy block and `files:` list
6. Update `package-ci-pr.yml` `paths:` if you introduced a new directory
7. Local build, `python -m build`, run `twine check`
8. Run `release.sh`, tag, push
9. Verify GitHub artifacts match local bundle
