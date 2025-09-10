# D2I DEV (non-prod workbench)

## D2I Development Plan Overview

## Key Objectives (Phase 1 & 2)
1. Extract specified data sub-set as JSON via query 
2. Provide capability for automated JSON query extract via script
3. Enhance automated JSON query extract(now payload) to enable send to defined API endpoint
4. Develop mechanism(s) to enable API response logging within SSD/persistent payload table
5. Develop mechanism(s) to enable SSD row-level change tracking towards delta extracts
6. Transition from initial full payload submissions to daily delta updates
7. Ensure minimal manual intervention with configurable automation
8. *Design towards potential additional fields inclusion/future changes*

## Development Data flows Roadmap (Phase 1 & 2)

```mermaid

sequenceDiagram
    autonumber
    participant DevSim as Python Script (Simulate Changes)
    participant SQL as CMS Db Server: ssd_api_data_staging(_anon)
    participant Ingest as SQL Update SSD Staging Table
    participant PSScript as PowerShell Script (Delta Submission)
    participant API as External API

    %% Development | Testing
    DevSim->>SQL: Modify json_payload, current_hash
    DevSim->>SQL: Set row_state = 'updated'
    DevSim->>SQL: Set submission_status = 'pending'

    Note over DevSim,SQL: Development | Testing

    %% Deployment | Live Start
    Ingest->>SQL: Build JSON structure (per child record)
    Ingest->>SQL: MERGE into SSD staging table
    alt Matched and changed
        SQL->>SQL: Update json_payload, current_hash
        SQL->>SQL: Set row_state = 'updated'
    else Matched and unchanged
        SQL->>SQL: Set row_state = 'unchanged'
    else New record (not matched)
        SQL->>SQL: Insert new row
        SQL->>SQL: Set row_state = 'new'
        SQL->>SQL: Set submission_status = 'pending'
    else Missing in source
        SQL->>SQL: Set row_state = 'deleted'
    end

    Note over Ingest,SQL: Deployment | Live Daily Ingestion

    %% PowerShell Script Starts
    PSScript->>SQL: SELECT records WHERE submission_status IN ('pending', 'error')
    alt usePartialPayload = true
        PSScript->>SQL: Generate-AllPartialPayloads()
        SQL-->>PSScript: partial_json_payload
    else use full json_payload
        SQL-->>PSScript: json_payload
    end

    loop Max 100 records per batch
        PSScript->>API: POST JSON batch
        alt HTTP 200 OK
            API-->>PSScript: DfE uuid response + timestamp
            PSScript->>SQL: Set submission_status = 'sent'
            PSScript->>SQL: Set api_response = DfE uuid
            PSScript->>SQL: Copy json_payload → previous_json_payload
            PSScript->>SQL: Copy current_hash → previous_hash
            PSScript->>SQL: Set row_state = 'unchanged'
        else Retryable Errors (401, 403, 429)
            API-->>PSScript: Retryable error
            PSScript->>API: Retry with backoff
            alt Max retries reached
                PSScript->>SQL: Set submission_status = 'error'
                PSScript->>SQL: Set api_response = error message
            end
        else Fatal Errors (400, 204, 413)
            API-->>PSScript: Non-retryable error
            PSScript->>SQL: Set submission_status = 'error'
            PSScript->>SQL: Set api_response = error message
        end
    end

    Note over PSScript,API: Deployment | Daily Submission (Batched, Status-driven)

```

## SSD Staging Table Load|API Event Flag Updates (Phase 1 & 2)

| Event                              | `submission_status` | `row_state`   |
|--------------------------------------|----------------------|---------------|
| Initial load (new record)            | `pending`            | `new`         |
| JSON modified (Python or SQL hash)   | `pending`            | `updated`     |
| API success                          | `sent`               | `unchanged`   |
| API failure (retry exhausted)        | `error`              | *(unchanged)* |
| Deleted in source                    | *(unchanged)*        | `deleted`     |

---

## Conceptual Overview (Phase 1)
```mermaid
flowchart TD
    %% Local Authority systems
    subgraph Local_Authority ["**Local Authority**"]
        style Local_Authority font-weight:bold
        style Local_Authority width:360px,height:500px  %% Ensures wider boundary for Local Authority

        subgraph Source_DB ["Source DB (CMS)"]
            style Source_DB width:300px,height:250px  %% Wider and taller to fit SSD box
            cms_raw_tables["CMS Raw CSC Tables"]
            style cms_raw_tables text-align:center

            subgraph SSD ["Standard Safeguarding Dataset"]
                style SSD width:230px,height:200px  %% Adjust height to fit content
                ssd_tables["SSD"]
                style ssd_tables text-align:center
            end
        end

        subgraph Shell_Process ["Scripted-Shell Process"]
            style Shell_Process padding-top:100px  %% Adds spacing from the box label
            json_query["JSON Extract Query"]
            api_payload["Prepare API Payload"]
            handle_status["Handle Response Status"]
            style json_query text-align:center
            style api_payload text-align:center
            style handle_status text-align:center
        end
    end
    style Local_Authority stroke-dasharray: 5,5  %% LA boundary

    %% API System Owner system(s)
    subgraph API_System ["**API System Owner**"]
        style API_System font-weight:bold

        api_receive["Receive JSON Data"]
        api_status["Send Response Status"]
    end


    %% Arrows showing data flow
    cms_raw_tables -->|Extract| ssd_tables
    ssd_tables -->|Full Data Extract | json_query
    json_query -->|Format for API - Full Data Extract| api_payload
    api_payload -->|Send Payload| api_receive
    api_receive -->|Response Status| api_status
    api_status -->|Process Response| handle_status

    %% Apply Colors Using Class Definitions
    classDef existingProcess fill:#cfe2f3,stroke:#000,stroke-width:1px  %% Light Blue
    classDef newProcess fill:#f9cb9c,stroke:#000,stroke-width:1px  %% Light Orange

    %% Assign Classes
    class json_query newProcess
    class api_payload newProcess
    class handle_status newProcess

    %% Legend
    subgraph Legend ["Legend"]
        new_process_key["Stage 1 Development"]
        style new_process_key fill:#f9cb9c,stroke:#000,stroke-width:1px  %% Match newProcess color
    end
    style Legend width:200px  %% Legend size

```


## Project Breakdown (Phase 1)
<details>
<summary><strong>Development Task Status Key</strong></summary>

🔲 Backlog | 🔄 In Progress | 🛠 Testing | 🚀 In Review |  ✅ Completed 
⏳ Blocked | 🗄 Deferred

</details>

| Task Area                           | Task                                                                                     | Status |
|-------------------------------------|-----------------------------------------------------------------------------------------|--------|
| **Review Initial Specification**    | Review specification for project scope                                                  | ✅ |
|                                      | Ensure any project required permissions/software is available                           | ✅ |
|                                      | Complete API to SSD fields mapping                                                     | ✅ |
| **SSD Changes**                     | Add API specified fields into SSD and data spec *(pushed to public SSD front-end?)*    | ✅ |
|                                      | SystemC (SQL Server)                                                                    | 🗄 |
|                                      | Mosaic (SQL Server)                                                                     | 🗄 |
|                                      | Eclipse (Postgres+)                                                                      | 🗄 |
|                                      | Azeus (Oracle) (March development to prioritise API object requirements)         | 🗄 |
| **Create Documentation (Framework & Plan)** | Request guidance on documentation preferences/standards                        | ⏳ |
|                                      | Create initial documentation framework *(is there an existing req standard/pref?)*      | ✅ |
|                                      | Define/write up development plan stage 1                                               | 🚀 |
|                                      | Define/write up development plan stage 2                                               | 🔄 |
| **Review and Complete SSD Backlog Tickets** | Backlog board review                                                                  | 🔄 |
|                                      | Work to close required backlog tickets *(known blockers affecting API data flow processes or data)* | 🔲 |
| **Write JSON Data Extract (SQL Query)** | Partial JSON extract query with Header + Top-level child details only *(process testing)* | ✅ |
|                                      | Full JSON extract query with Header + Top-level child details + all sub-level elements  | ✅ |
| **Automate Data Extraction**        | Investigation towards suitable process/script for data extract + API workflow          | 🚀 |
|                                      | Develop API workflow *shell* script(s) incl. DB access, JSON query extraction          | 🚀 |
|                                      | Test API workflow locally within host LA *(extract only)*                              | 🚀 |
| **Create Documentation (Playbook)** | Write up final LA playbook details                                                     | 🚀 |
|                                      | Update documentation based on pilot LA 1 + stakeholder(s) feedback                     | 🔲 |
| **Simulate API Integration local within ESCC** | Create/generate/Anonymise dummy data for initial API send *(SSD structure + repeatable)* | ✅ |
|                                      | Test with complete (non-delta) payload of null/dummy data                              | ✅ |
|                                      | Test each response code(s), & logging within payload table                              | ✅ |
| **Test API Integration with a Pilot LA** | Test with complete (non-delta) payload of null/dummy data                              | ⏳ |
|                                      | Test each response code(s), & logging within payload table                              | ⏳ |
| **Refinements/Granular end-goal fixes** | Process to handle (mid-)record 'purges'                                                | ⏳ |
|                                      | Discuss/investigate longer-term/wider API use and potential process changes *(e.g. do we need combined payload staging table as mid-term historic record)* | 🔲 |



## Simulated API Overview (Phase 1 #1)

```mermaid

flowchart TD

    %% Legend
    subgraph Legend ["Legend"]
        process_key["Process Steps"]
        style process_key fill:#cfe2f3;
        api_key["API Interaction"]
        style api_key fill:#f9cb9c;
        hosted_key["Hosted CMS DB Server"]
        style hosted_key fill:#d9ead3;
        python_key["During Development Phase"]
        style python_key fill:#ffe599;
        external_key["External Receiving System"]
        style external_key fill:#f4cccc;
    end

```

```mermaid

flowchart TD

    Title["**API Data Flow - Phase1 Pt1**"]

    subgraph LA_Server_Instance
        %% SystemC Reporting Instance DB (Containing all DB-related and API elements)
        subgraph SystemC_DB ["SystemC Reporting Instance DB"]
            style SystemC_DB fill:#d9ead3,stroke:#000,stroke-width:1px;  %% Light Green, same as CMS CSC Schema

            subgraph CMS_CSC_Schema ["CMS CSC Schema"]
            end
            style CMS_CSC_Schema fill:#d9ead3,stroke:#000,stroke-width:1px;  %% Light Green

            CMS_CSC_Schema -->|Extract SSD Data| SSD_Tables["SSD Tables"]

            %% Child-Level JSON Extract Step
            SSD_Tables -->|SQL JSON Extract| Child_JSON_Extract["Child-level JSON Extract Process"]
            Child_JSON_Extract -->|Extract API JSON Data| Bulk_Populate["ssd_api_data_staging table submission_status=Pending curr_prev_hash_vals=checksums"]

            subgraph Development_Phase_Only_DB
            %% Anonymised Data in DB
            SSD_Staging_Anon["ssd_api_data_staging_anon Replicated staging table **ANONYMISED**"]
            end
        end

    API_Powershell_Live -->|Anon API Array Payload+Header| API_External["API Live Call"]
    
        subgraph Development_Phase_Only_API ["Development Phase only"]
            API_Powershell_Dev -->|Anon API Array Payload| API_Simulated["API Simulated Call"]
        
        end
    end


    %% External Receiving System (Outside LA Server)
    subgraph External_Receiving_System ["External Receiving System"]
        style External_Receiving_System fill:#f4cccc;  %% Light Red for external systems
        API_External -->|API Send Request| API_Endpoint
        API_Endpoint -->|API Response Codes| API_External
    %% API Processing (Inside LA Server)
    
        SSD_Staging_Anon -->|Extract Anon JSON | API_Powershell_Live["API Powershell Live"]
        SSD_Staging_Anon -->|Extract Anon JSON | API_Powershell_Dev["API Powershell Dev"]
    end


    %% Ensure the return flow is fully outside LA_Server_Instance

    API_Simulated -->|Simulated Test Response| API_Powershell_Dev
    API_External -->|Handle API Response| API_Powershell_Live
    API_Powershell_Dev -->|Update R-Cd & sub_status| SSD_Staging_Anon

    API_Powershell_Live -->|Update R-Code & status| SSD_Staging_Anon




    %% Local Anaconda Environment for Python Processing
    subgraph Development_Phase_Only_Py ["Development Phase only"]
        Python_Anon["Python Anonymisation in Local Anaconda Env."]
    end

    %% Anonymisation Flow (now separated)
    Bulk_Populate -->|Process Data for Anonymisation| Python_Anon
    Python_Anon -->|Store Anonymised Data| SSD_Staging_Anon

    %% Apply Colors Using Class Definitions
    classDef processNode fill:#cfe2f3;  %% Light Blue for processes
    classDef apiNode fill:#f9cb9c;  %% Light Orange for API interaction
    classDef hostedNode fill:#d9ead3;  %% Light Green for Hosted DB elements
    classDef Testing fill:#ffe599,stroke:#000,stroke-width:1px;  %% Light Yellow for Python Processing
    classDef externalNode fill:#f4cccc,stroke:#000,stroke-width:1px;  %% Light Red for External Receiving System

    %% Assign Classes
    class SystemC_DB hostedNode;
    class CMS_CSC_Schema hostedNode;
    class SSD_Tables,Child_JSON_Extract,Bulk_Populate,SSD_Staging_Anon processNode;
    class API_Powershell,API_External,API_Endpoint apiNode;
    class External_Receiving_System externalNode;
    class Development_Phase_Only_Py Testing;
    class Development_Phase_Only_API Testing;
    class Development_Phase_Only_DB Testing;
    class Python_Anon pythonEnv;
    
```

### Ref: ssd_api_data_staging
The Phase 1(S1) payload data is agreed as the full refresh of all payload data. A staging table, added to the core SSD implementation is the suggested method towards achieving this and onward stages, an example shown here. This enables all staged 'Pending' records to be extracted by the API process. (Note: Hashed/Anonymised test data table shown here). 
![Anon JSON records](assets/images/ssd_api_data_staging_anon_row-statuses.png)
As per the above diagram, during development, we're aiming to replicate the live staging table using anonymised data. It's from this replicated oject that all Phase 1 tests will be run. At the point where live data from an agreed pilot/project LA can be sent, the shown api data flows will switch over to using the live staging table. During Phase|Stage 2 development (From May 2025->), the staging and API process will be further developed such that a row|record status provides the flag of which records form each delta-payload, e.g. 'New', 'Deleted', 'Updated' included with 'Unchanged' records being ignored. 


## Switch to data hitting API endpoint Overview (Phase1 #2) 

Essentially as #1 above, but switch to (full payload) data hitting defined endpoint. It's recommended that initially this be continued using only the anonymised data, and thus retain the 'development' process areas defined above(orange). The aim that when agreed, to shift the data flow onto live data, dropping the anonymisation processes labelled in the diagram as in development. 
  
```mermaid

flowchart TD

    Title["**API Data Flow - Phase1 #2**"]

    subgraph LA_Server_Instance
        %% SystemC Reporting Instance DB (Containing all DB-related and API elements)
        subgraph SystemC_DB ["SystemC Reporting Instance DB"]
            style SystemC_DB fill:#d9ead3,stroke:#000,stroke-width:1px;  %% Light Green, same as CMS CSC Schema

            subgraph CMS_CSC_Schema ["CMS CSC Schema"]
            end
            style CMS_CSC_Schema fill:#d9ead3,stroke:#000,stroke-width:1px;  %% Light Green

            CMS_CSC_Schema -->|Extract SSD Data| SSD_Tables["SSD Tables"]

            %% Child-Level JSON Extract Step
            SSD_Tables -->|SQL JSON Extract| Child_JSON_Extract["Child-level JSON Extract Process"]
            Child_JSON_Extract -->|Extract API JSON Data| Bulk_Populate["ssd_api_data_staging table submission_status=Pending curr_prev_hash_vals=checksums"]

        end

    API_Powershell_Live -->|Prepare Payload and Header| API_External["API Live Call"]
    

    end


    %% External Receiving System (Outside LA Server)
    subgraph External_Receiving_System ["External Receiving System"]
        style External_Receiving_System fill:#f4cccc;  %% Light Red for external systems
        API_External -->|API Send Request| API_Endpoint
        API_Endpoint -->|API Response Codes| API_External
    %% API Processing (Inside LA Server)
    
        Bulk_Populate -->|Extract JSON to API array | API_Powershell_Live["API Powershell Live"]
    end


    %% Ensure the return flow is fully outside LA_Server_Instance

    API_External -->|API Response| API_Powershell_Live
    API_Powershell_Live -->|Update R-Cd & sub_status| Bulk_Populate


    %% Apply Colors Using Class Definitions
    classDef processNode fill:#cfe2f3;  %% Light Blue for processes
    classDef apiNode fill:#f9cb9c;  %% Light Orange for API interaction
    classDef hostedNode fill:#d9ead3;  %% Light Green for Hosted DB elements
    classDef Testing fill:#ffe599,stroke:#000,stroke-width:1px;  %% Light Yellow for Python Processing
    classDef externalNode fill:#f4cccc,stroke:#000,stroke-width:1px;  %% Light Red for External Receiving System

    %% Assign Classes
    class SystemC_DB hostedNode;
    class CMS_CSC_Schema hostedNode;
    class SSD_Tables,Child_JSON_Extract,Bulk_Populate processNode;
    class API_Powershell,API_External,API_Endpoint apiNode;
    class External_Receiving_System externalNode;
    class Python_Anon pythonEnv;

```


## Conceptual Overview (Phase2)

On completion of Phase 1 #2, development work shifts to refine the full data payloads into record-level update deltas. This to be combined with both the ongoing support of, and wider take-on where agreed pilot LAs into the testing/development of the API data flow process. 

```mermaid
flowchart TD
    %% Local Authority systems
    subgraph Local_Authority ["**Local Authority**"]
        style Local_Authority font-weight:bold;

        subgraph Source_DB ["Source DB (CMS)"]
            cms_raw_tables["CMS Raw CSC Tables"]

            subgraph SSD ["Standard Safeguarding Dataset (SSD)"]
                ssd_tables["SSD"]
                hash_table_process["SSD Change Management & API Log"]
            end
        end

        subgraph Shell_Process ["Scripted-Shell Process"]
            json_query["JSON Extract Query"]
            api_payload["Prepare API Payload"]
            handle_status["Handle Response Status"]
        end
    end
    style Local_Authority stroke-dasharray: 5,5  %% LA boundary

    %% API System Owner system(s)
    subgraph API_System ["**API System Owner**"]
        style API_System font-weight:bold;

        api_receive["Receive JSON Data"]
        api_status["Send Response Status"]
    end

    %% Arrows showing data flow
    cms_raw_tables -->|Extract| ssd_tables
    ssd_tables -->|SSD Generate Hash Log| hash_table_process
    hash_table_process -->|Extract Changes| json_query
    json_query -->|Format for API - Delta Changes| api_payload
    json_query -->|Store Payload| hash_table_process
    api_payload -->|Send Payload| api_receive
    api_receive -->|Response Status| api_status
    api_status -->|Process Response| handle_status
    handle_status -->|Update| hash_table_process

    %% Apply Colors Using Class Definitions
    classDef existingProcess fill:#cfe2f3,stroke:#000,stroke-width:1px;  %% Light Blue
    classDef newProcess fill:#f9cb9c,stroke:#000,stroke-width:1px;  %% Light Orange

    %% Assign Classes
    class json_query newProcess;
    class api_payload newProcess;
    class handle_status newProcess;
    class hash_table_process newProcess;

    %% Legend
    subgraph Legend ["Legend"]
        new_process_key["Stage 2 Development"]
        style new_process_key fill:#f9cb9c,stroke:#000,stroke-width:1px;  %% Match newProcess color
    end
    style Legend width:200px  %% Legend size

```


## Project Breakdown (Phase 2) (tbc)

<details>
<summary><strong>Development Task Status Key</strong></summary>

🔲 Backlog | 🔄 In Progress | 🛠 Testing | 🚀 In Review |  ✅ Completed 
⏳ Blocked | 🗄 Deferred

</details>

| Task Area                                 | Task                                                                        | Status |
|-------------------------------------------|-----------------------------------------------------------------------------|--------|
| **Enable SSD Row-Level Change Tracking**  | Develop mechanism(s) to enable record-level/deltas change tracking         | 🔄  |
|                                           | Re-develop API process to integrate change tracking/record-level deltas    |🔲 |
| **Provide Configuration Playbook and Guidance for LAs** | SystemC                                                      | 🔄  |
|                                           | Mosaic                                                                     | ⏳  |
|                                           | Eclipse                                                                    | ⏳ |
| **Expand Pilot**                          | Expand pilot to further LAs with D2I support                               |🔲 |



