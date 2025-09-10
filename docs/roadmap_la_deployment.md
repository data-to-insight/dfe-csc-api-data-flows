# 3-Week Deployment Roadmap

This very simplified deployment plan is designed for local authorities wanting to visualise how to stage successful deployment of the D2I Private Dashboard solution via the Standard Safeguarding Dataset (SSD) combined API. It assumes an LA project team minimum of a single Analyst lead with availability and involvement from IT support|infrastructure|performance team and a reporting DB with sight of CMS data.

---

## Week-by-Week Overview

### **Stage 0 - Project Prep - Roles and Access (Week 0)**
**Tasks**  
**Analyst/Lead**  
> - Obtain DfE API credentials via [education.gov.uk/find-an-api](https://pp-find-and-use-an-api.education.gov.uk/find-an-api)  
 - Confirm read access to source CMS reporting views/tables, 
 - Confirm permission to run `CREATE TABLE` on a reporting instance(development or existing data team reporting instance is ideal). 
 - Confirm access needed to PowerShell 5.1+ locally, and ideally local Anaconda/Python  

**IT / DBA**  
> - Ensure ability to schedule additional server job (SQL(SSD) & script(API)), approve `.py` or `.exe` execution, outbound HTTPS to DfE API endpoint, service account/ credential setup. Support to make Powershell or Anaconda/Python available to analyst/deployment team   
- Agree environments: SSD schema location(within sight of CMS data), optional: file/log locations  
- Book with **IT/server team** week-3 slot to port jobs to server (raise awareness for needed feedback loop between this team and either project team or D2I direct)  

**Entry criteria**  
- ✅ Access, tech stack and approvals confirmed/agreement initiated  
- ✅ Target DB for SSD schema and credentials agreed  
- ✅ Server deployment window pencilled with IT/Server team

---

### **Stage 1 - Deploy SSD and Staging (Week 1)**
**Tasks**  
- Deploy and verify **SSD core objects** (run SSD install and/or compatibility checks if awaiting CREATE permissions)  
- Deploy and verify **API staging tables**:  
  - `ssd_api_data_staging` (live)  
  - `ssd_api_data_staging_anon` (test/dummy data)  
- Test re-deploy (i.e. simulate daily refresh)  **SSD core objects**  

**Exit criteria**  
- ✅ SSD schema is manually deployed by analyst/other  
- ✅ Staging table(s) manually deployed by analyst/other  
- ✅ API *priority* tables are at least populating (data might not yet be verified)  

---

### **Stage 2 - Local Test Send (Week 2)**
**Tasks**  
- Load 1+ dummy or agreed scrambled records into `_anon` staging table  
- Run Either **Python/Jupyter** script or **PowerShell** script locally to send using fake payload to DfE test endpoint (1+ dummy records from `_anon`)  
- Verify **HTTP response handling** and logging in `_anon` staging (status codes, response IDs, retries)  
- Perform local (non-send) simulated API on `ssd_api_data_staging` (live)  

**Exit criteria**  
- ✅ Creating/inserting 1+ dummy records as fake payload  
- ✅ End-to-end POST works from Analyst machine  
- ✅ Response codes and DfE UUIDs logged   
- ✅ Error paths handled and recorded  

---

### **Stage 3 - Scale and Readiness (Week 2 cont.)**
**Tasks**  
- Increase test records volume in `_anon` staging table to validate API batching, internal performace issues and back-off  
- Confirm **daily snapshot** works reliably, potentially trial manual **daily deltas** if data-flow ready  
- Finalise server locations, credentials, and job parameters with IT (runtime environment for `.py` or `.exe`, logs, retries)  

**Exit criteria**  
- ✅ Stable runs with larger dummy batches (D2I might be able to support with scaled fake records)  
- ✅ Operational runbook agreed (parameters, logs, failure handling)  
- ✅ IT confirms server execution plan  

---

### **Stage 4 - Server Automation (Week 3)**
**Tasks**  
- **Port to server jobs**:
  - SQL job: SSD refresh/load to repopulate `ssd_api_data_staging`
  - Script job: API sender (`.py` or `.exe`) with schedule and monitoring
- Point from `_anon` to **live** staging table when approved
- Validate first automated runs, confirm monitoring and alerting

**Exit criteria**  
- ✅ Jobs scheduled and running on server  
- ✅ First server-side submissions succeed, logs retained  
- ✅ RACI agreed for ongoing support

---

## Deliverables Checklist

- **DB:** SSD schema deployed, `ssd_api_data_staging` (+ `_anon`) created  
- **Scripts:** PowerShell sender, optional Python/Jupyter test notebook  
- **Ops:** Runbook (when and how), failure and rollback steps, log locations  
- **IT:** Scheduled jobs, credentials, outbound API access, monitoring

---

## Simplified Timeline

```kroki-graphviz
digraph Deployment {
  rankdir=TB;
  node [shape=box, fontsize=11, width=4.0, height=1.2, fixedsize=true, style=filled];

  // Week colours
  Stage0 [label="Stage 0 - Prep\n(Week 0)\n- Access & permissions\n- IT conversations\n- Deployment slot booked", fillcolor="#f79758ff"];
  Stage1 [label="Stage 1 - SSD Deploy\n(Week 1)\n- SSD schema deployed\n- Staging tables created\n- Refresh tested", fillcolor="#fff2cc"];

  Stage2 [label="Stage 2 - Local Test Send\n(Week 2)\n- Dummy data into anon table\n- Local script test send\n- Response logging verified", fillcolor="#cfe2f3"];
  Stage3 [label="Stage 3 - Scale & Readiness\n(Week 2 cont.)\n- Increase test volume\n- Trial snapshots/deltas\n- Runbook agreed with IT", fillcolor="#cfe2f3"];

  Stage4 [label="Stage 4 - Server Automation\n(Week 3)\n- Port SSD + API scripts to server\n- Schedule jobs\n- Validate first automated runs", fillcolor="#319c09ff"];

  // Flow
  Stage0 -> Stage1 -> Stage2 -> Stage3 -> Stage4;
}

```