# Stakeholders

## Key Stakeholders
### Data to Insight (D2I)
- **Role**: Core development and wider pilot partner support for LA's
- **Responsibilities**:
  - Develop extract for JSON payload in line with spec [in progress]
  - Develop API scripted/automate process 
  - Develop documentation and LA 'playbook' 
  - Collaborate & support pilot LAs to enable both SSD deployment and required API setup/running

### Local Authorities (LAs) | Development Partners
- **Role**: Data providers and API integrators
- **Responsibilities**:
  - Deploy the SSD structure in their databases
  - Allow capacity to work with D2i towards needed integration
  - Extract and submit JSON payloads (this might require manual script kick-off initially)
  - Enable SSD refresh and related submission frequencies
  - Actively participate in testing and feedback during pilot phases
  - Deploy the SSD structure and agree on refresh frequency
  - Oversee the initial 'completeness' of extracted data and work with d2i to effect needed localised changes
  - Address the data causing API failure response codes (data validation)

- Pilot Local Authorities collaborating in the early stages to test the API and data flow
- Feedback from pilot partners will inform improvements and broader rollout

- **IT Support**: If permissions requ, CMS DB access(SSD deployment + overnight refresh), add API script to server(Powershell), outgoing API (whitelisting)
- **Data Analysts|Intelligence Team**: Oversee the accuracy and completeness of extracted data
- **Security Teams**: Ensure proper permissions and secure handling of sensitive information

### API System Owner
- **Role**: Data recipient and system owner
- **Responsibilities**:
  - Define JSON payload structure 
  - Maintain API endpoint
  - Monitor and manage data flow/ingress 
  - Define endpoint response codes if not standard
  - Ensure received data security/encryption/persistance

