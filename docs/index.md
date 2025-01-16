# CSC API Dataflow

## Introduction
CSC API dataflow project, with D2I, aims to automate the transfer of Children's Social Care (CSC) data from pilot Local Authorities (LAs) to an API endpoint. 

Using the Standard Safeguarding Dataset (SSD) as it's intended middleware; The automation to include a JSON extract of a subset of data from the SSD, sent via an API service to a given endpoint.

## Key Objectives
1. Automate data submission via an API
2. Transition from initial full payload submissions to daily delta updates
3. Ensure minimal manual intervention with configurable automation

## Features
- **Pre-defined JSON Structure**: Data extracted adheres to a standard/specification format
- **API Integration**: JSON data payload sent to an API endpoint
- **Data Change Tracking**: Added functionality to enable record level change tracking
- **Status Tracking**: Update submission statuses (Sent, Error, Testing) within the SSD

## Development Stages
### Stage 1
- Initial full payload submission
- Add additional fields to SSD as needed
- Automate data submission via (PowerShell) scripts with JSON extraction
- Test API integration with a pilot LA

### Stage 2
- Expand pilot to multiple LAs
- Support daily delta submissions
- Provide documentation and guidance for LA configurations

For more details on the JSON structure, see [Configuration and Setup](setup.md)
