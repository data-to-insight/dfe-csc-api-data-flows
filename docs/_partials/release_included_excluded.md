### What Gets Released

#### Included files
Release bundle constructed in 2 ways  
1. **PEP 517 build system** – creates Python package (`.tar.gz` and `.whl`) inside `dist/`
   contains only package code declared in `pyproject.toml` and `MANIFEST.in`  
2. **Release bundle** – convenience archive (`release.zip`) built by `release.sh`, containing
   - Python distribution files `dist/*`  
   - `README.md` for end‑user ref  
   - `.env.example` sample environment config  
   - deployment helpers PowerShell and SQL scripts used in LA setup  
   - optional Windows `.exe` built locally with PyInstaller  

#### Excluded files
During packaging and bundling process **explicitly exclude**  
- development caches `__pycache__/`, `.pytest_cache/`, `.coverage/`  
- IDE files `.vscode/`, `.idea/`  
- build directories `build/`, `dist/`, old `*.egg-info`  
- test artefacts not required in distribution  

> Full list of include/exclude rules maintained in `pyproject.toml` and `MANIFEST.in`  
> Update those to change Python package contents or adjust `release.sh` to change wider release bundle  
