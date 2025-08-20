## Manifest and Packaging

Python packaging toolchain via `build` respects two files
- `pyproject.toml` project metadata name version dependencies
- `MANIFEST.in` extra non‑code files to include, eg `.env.example`, SQL scripts

combined definition controls what end‑user receives when installing from PyPI or unzipping release file
