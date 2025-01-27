# D2I DEV (non-prod workbench)

## D2I Development Plan Overview


## Stage 1 & 2 Key Objectives
1. Extract specified data sub-set as JSON via query 
2. Provide capability for automated JSON query extract via script
3. Enhance automated JSON query extract(now payload) to enable send to defined API endpoint
4. Develop mechanism(s) to enable API response logging within SSD/persistent payload table
5. Develop mechanism(s) to enable SSD row-level change tracking towards delta extracts
6. Transition from initial full payload submissions to daily delta updates
7. Ensure minimal manual intervention with configurable automation
8. *Design towards potential additional fields inclusion/future changes*


## Stage 1 Overview
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



## Stage 1 Task Breakdown

<details>
<summary><strong>Development Task Status Key</strong></summary>

[   ] Not started |
[ - ] In progress | 
[ * ] Testing | 
[ x ] Completed | 

[ > ] Ready for Review | 
[ ~ ] Blocked | 
[ D ] Deferred  

</details>


| Task Area                           | Task                                                                                     | Status |
|-------------------------------------|-----------------------------------------------------------------------------------------|--------|
| **Review Initial Specification**    | Review specification for project scope                                                  | [ - ]    |
|                                     | Ensure any project required permissions/software is available                           | [ * ]    |
|                                     | Complete API to SSD fields mapping                                                     | [ * ]    |
| **SSD Changes**                     | Add API specified fields into SSD and data spec (?) *(pushed to public SSD front-end?)* | [ - ]    |
|                                     | SystemC (SQL Server)                                                                  | [ * ]    |
|                                     | Mosaic (SQL Server)                                                                     | [   ]    |
|                                     | Eclipse (Postgres)                                                                      | [   ]    |
| **Create Documentation (Framework & Plan)** | Request client guidance on documentation preferences/standards                        | [ * ]    |
|                                     | Create initial documentation framework *(is there an existing req standard/pref?)*      | [ - ]    |
|                                     | Define/write up development plan stage 1                                               | [ > ]    |
|                                     | Define/write up development plan stage 2                                               | [   ]    |
| **Review and Complete SSD Backlog Tickets** | Backlog board review                                                                  | [ - ]    |
|                                     | Work to close required backlog tickets *(known blockers)*                               | [   ]    |
| **Write JSON Data Extract (SQL Query)** | Partial JSON extract query with Header + Top-level child details only *(process testing)* | [ - ]    |
|                                     | Full JSON extract query with Header + Top-level child details + all sub-level elements  | [   ]    |
| **Automate Data Extraction**        | Investigation towards suitable process/script for data extract + API workflow          | [ - ]    |
|                                     | Develop API workflow *shell* script(s) incl. DB access, JSON query extraction          | [   ]    |
|                                     | Test API workflow locally within host LA *(extract only)*                              | [   ]    |
| **Create Documentation (Playbook)** | Write up final LA playbook details                                                     | [   ]    |
|                                     | Update documentation based on pilot LA 1 + stakeholder(s) feedback                     | [   ]    |
| **Test API Integration with a Pilot LA** | Create/generate/Anonymise dummy data for initial API send *(SSD structure + repeatable)* | [   ]    |
|                                     | Test with complete (non-delta) payload of null/dummy data                              | [   ]    |
|                                     | Test each response code(s), & logging within payload table                              | [   ]    |

## Stage 2 Overview

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

## Stage 2 Task Breakdown (tbc - still flushing this out)


| Task Area                                 | Task                                                                        | Status |
|-------------------------------------------|-----------------------------------------------------------------------------|--------|
| **Enable SSD Row-Level Change Tracking**  | Develop mechanism(s) to enable SSD/record change tracking                  | [   ]    |
|                                           | Re-develop API process to integrate change tracking/record-level deltas    | [   ]    |
| **Provide Configuration Playbook and Guidance for LAs** | SystemC                                                                | [   ]    |
|                                           | Mosaic                                                                     | [   ]    |
|                                           | Eclipse                                                                    | [   ]    |
| **Expand Pilot**                          | Expand pilot to further LAs with D2I support                               | [   ]    |



