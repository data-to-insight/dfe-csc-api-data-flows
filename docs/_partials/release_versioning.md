## Release Versioning

Release follows **semantic versioning (SemVer)**  
- **MAJOR** incompatible changes  
- **MINOR** new functionality backwards compatible  
- **PATCH** bug fixes or small updates  

eg.  
- `0.2.0` minor release with new features  
- `0.2.1` patch release with bug fixes  
- `1.0.0` stable release milestone  

**in practice**  
- tags always prefixed with `v`, eg `v0.2.1`  
- version in `pyproject.toml` must match numeric form without `v`, eg `0.2.1`  
- `release.sh` keeps values in sync, updates `pyproject.toml`, commits if required, applies git tag  
