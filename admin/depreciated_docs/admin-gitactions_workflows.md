# Git Actions Workflow Overview

This repo uses **3 Git Actions workflows** to automate build, release, and documentation deployment.

---

## 1. `build-api-pipeline-pkg.yml`

**Purpose:**  
Build Python package artifacts (`.tar.gz`, `.whl`) from the `api_pipeline/` folder and uploads them as Git Actions artifacts.

**Trigger:**  
- Push to `main` branch  
- Pull request to `main` branch

**Use case:**  
Enable downloadable Python packages for local installation without publishing to PyPI.

---

## 2. `build-release-exe.yml`

**Purpose:**  
Compile project into a standalone Windows `.exe` using PyInstaller and prepares **multiple release assets** for distribution:  
- `csc_api_pipeline.exe`  
- `release.zip` containing scripts, config, docs, and binary  
- `.whl` and `.tar.gz` Python packages  
- `.env.example`  
- `README.md`

**Trigger:**  
Push of version tag (e.g. `v1.2.3`) or Git Release event.

**Use case:**  
Support distribution of ready-to-run exe and packaged Python builds via Git Releases, avoiding Python dependency for end users.

---

## 3. `gh-pages.yml`

**Purpose:**  
Build and deploys MkDocs documentation site to Git Pages.

**Trigger:**  
Push to `main` branch.

**Use case:**  
Publishe the latest project documentation as a static site using MkDocs with the Material theme.

---

## Summary Table

| Workflow File                  | Description                                                              | Trigger                | Required |
|--------------------------------|--------------------------------------------------------------------------|------------------------|----------|
| `build-api-pipeline-pkg.yml`   | Builds and uploads `.whl` + `.tar.gz` package                            | Push to `main`, PR     | ✅       |
| `build-release-exe.yml`        | Builds `.exe`, `release.zip`, `.env.example`, README, `.whl`, `.tar.gz`  | Release or version tag | ✅       |
| `gh-pages.yml`                 | Deploys MkDocs site to Git Pages                                      | Push to `main`         | ✅       |

---

## Workflow Diagram

```mermaid
flowchart LR
    %% Triggers
    A1[Push to main]:::trigger
    A2[Pull Request to main]:::trigger
    B1[Version tag push<br/>e.g. v1.2.3]:::trigger
    B2[Git Release event]:::trigger

    %% Workflows
    W1[[build-api-pipeline-pkg.yml]]:::workflow
    W2[[build-release-exe.yml]]:::workflow
    W3[[gh-pages.yml]]:::workflow

    %% Outputs
    O11[.whl]:::artifact
    O12[.tar.gz]:::artifact

    O21[csc_api_pipeline.exe]:::artifact
    O22[release.zip]:::artifact
    O23[.whl + .tar.gz]:::artifact
    O24[.env.example]:::artifact
    O25[README.md]:::artifact

    O31[Deployed MkDocs site<br/>(Git Pages)]:::artifact

    %% Edges
    A1 --> W1
    A2 --> W1
    B1 --> W2
    B2 --> W2
    A1 --> W3

    W1 --> O11
    W1 --> O12

    W2 --> O21
    W2 --> O22
    W2 --> O23
    W2 --> O24
    W2 --> O25

    W3 --> O31

    %% Styles
    classDef trigger fill:#eef,stroke:#7a88f3,stroke-width:1px,color:#222;
    classDef workflow fill:#efe,stroke:#4CAF50,stroke-width:1px,color:#222;
    classDef artifact fill:#fff,stroke:#bbb,stroke-dasharray: 3 3,color:#333;
```

---

**Last verified:** 14/08/2025 – aligned with workflow files in `.Git/workflows/`.
