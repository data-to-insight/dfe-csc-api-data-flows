# CSC API Dataflow
[draft: 160125]

## Introduction
CSC API dataflow project, with D2I, aims to automate the transfer of Children's Social Care (CSC) data, from pilot Local Authorities (LAs) to an API endpoint. 
Using the Standard Safeguarding Dataset (SSD) as middleware; The automation to include a JSON structured extract from a subset of SSD structured data, sent via the API service to a given endpoint.

## Key Objectives
1. Extract specificied data sub-set as JSON via query 
2. Provide capability for automated JSON query extract via script
3. Enhance automated JSON query extract(now payload) to enable send to defined API endpoint
4. Develop mechanism(s) to enable SSD row-level change tracking towards delta extracts
5. Transition from initial full payload submissions to daily delta updates
6. Ensure minimal manual intervention with configurable automation

## Development Stages
### Stage 1
- Add specified additional fields to SSD (can this be pushed to public SSD front-end?)(impacts all CMS dev streams)
- Initial full specified JSON data extract(query)
- Automate data submission via (PowerShell) scripts with JSON extraction
- Test API integration with a pilot LA (dummy or null data)

### Stage 2
- Expand pilot to further LAs with D2I support
- Develop mechanism(s) to enable SSD row-level change tracking towards delta extracts
- Transition from initial full payload submissions to daily delta updates
- Provide documentation|draft playbook and guidance for LA configurations


## Features
- **Pre-defined JSON Structure**: Data extracted adheres to a standard/specification format
- **API Integration**: JSON data payload sent to an API endpoint
- **Data Change Tracking**: Added functionality to enable record level change tracking
- **Status Tracking**: Store/update API reponse statuses (Sent, Error, Testing) within the SSD


For more details on the JSON structure, see [Configuration and Setup](setup.md)
