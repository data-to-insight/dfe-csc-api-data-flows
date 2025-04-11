# CSC API Dataflow (D2I)

## Deployment Reference Guide [ver:0.3.4 - spec:0.8] 
The following page(s) offer an overview in deploying a D2I solution to extract specific Children’s Social Care (CSC) data from local authorities Case Management System (CMS) that can also be transmitted to DfE’s CSC API. There are two key elements:
 
- Standard Safeguarding Dataset (SSD)
- CSC API connection to DfE
 
The SSD is a CSC data middleware solution from D2I that allows local authorities to interact with a new standardised schema with sector defined data items. The extracted CMS data remains hosted within, and alongside the LA's existing local reporting database/warehouse. The standard data solution provides local authorities with a broader set of data than existing statutory data returns and the CSC data model is intended to evolve based on sector needs to improve collaboration, support the creation of standardised insights and deliver improved data interoperability with local and national government.  It is easy to deploy for most local authorities using the major CMS providers and will be kept up to date as the model evolves.
 
The DfE has created a CSC API to securely receive timely CSC data from local authorities CMS to support learning across the sector in improving outcomes for children. D2I will assist deployment of the SSD, extract the agreed CSC data and will supply the tool(s) needed to automate both the extraction of the data, and to enable secure transmit to the DfE API daily. The sent data is not shared outside the DfE, and only the DfE and the local authority will have sight of the resultant dashboard that the data powers. 
 
## How will this solution work?
 
The SSD creates a standardised data mapping to the CMS supplier’s data model using live CSC data or the suppliers data warehouse, thus acting as a middleware layer. The D2I solution will initially extract CMS held data (daily) into a standardised SSD model/schema, which is stored alongside the existing data within the local authorities data warehouse. Once the SSD is deployed, the local authority also has the additional potential to develop (or use from others) standardised reporting solutions to identify insights and support collaboration with the sector.
 
The CSC API data can then be extracted from the SSD in JSON format, using either a data snapshot each day(initially) or by extracting only identified changes to relevant children’s records from the previous day(daily deltas). Once JSON formatted file is generated, its securely transmitted using automation to DfE using an authenticated token. DfE systems will then acknowledge the submitted file (payload). As part of the D2I provided solution, payload responses and submitted data are recorded internally for reference/logging. The DfE will use the data to automate the creation of required indicators to support more timely benchmarking of key indicators across the sector through the lens of the national framework.  


## Additional SSD detail:

Where possible the SSD extract has been designed to run as a single SQL script. Once deployed, you will have instant access to the SSD schema, and the associated benefits. Initially this includes establishing SSD compatibility with your system(s), access to our suggested API solution and a bank of stat-returns scripts. Future benefits include access to tools from other SSD LA’s, improved cross-LA benchmarking, the potential to work with any other LA collaboratively to develop data|insights tools as well as D2I's own developing SSD tools library. 

More detailed information and technical aspects regarding the SSD schema and published project report are available at: 

- [DDSF Project 1a final report](https://www.datatoinsight.org/publications-1/standard-safeguarding-dataset---final-report) 
- [SSD project distribution Github web pages-public access-](https://data-to-insight.github.io/ssd-data-model/)
- [SSD project distribution Github repo-request access-](https://github.com/data-to-insight/ssd-data-model) 
- [SSD deployment guidance summary in this documentation](deploy_ssd.md)

For many LA's (SystemC/SQL Server), deploying the SSD can take as little as 15minutes, dependent on local|bespoke configurations. 

<!-- For more details on the [JSON payload structure](payload_structure.md) -->
