# CSC API Dataflow (D2I Solution)
Author: Data to Insight | Last Updated: 250225 | Draft

## API Introduction
CSC API dataflow project with D2I, aims to automate the transfer of Children's Social Care(CSC) data, from pilot Local Authorities (LAs) to an agreed API endpoint using a scripted solution in combination with the deployed SSD schema. 

By deploying the Standard Safeguarding Dataset (SSD) as middleware within this data flow solution, the process generates the required JSON structured extract from the SSD data layer, sent via a supplied API process to the defined endpoint.

## Standard Safeguarding Dataset (SSD)

In response to the 2022 independent review of children’s social care (“the MacAlister review”), DfE initiated a whole-system response in the form of a consultation response, revised practice guidance, and a range of innovation projects across practice and enabling technologies. The Data and Digital 
Solutions Fund (DDSF) marked a significant element in this initial response, formalising government’s commitment to “put Local Authorities in the driving seat of change”.

The Standard Safeguarding Dataset (SSD) represents one of the DDSF’s major products: a sector-designed dataset specification for production by any LA, which can improve sector collaboration, help LAs generate insights, and ease data interoperability between local and national government.

The Standard Safeguarding Dataset is broader in scope than existing statutory data returns, more useful to local authorities (LAs), and easy to deploy for most LAs using the major current case management software solutions. API pilot or early-adopter LA's deploying the D2I solution, have the additional benefits of supported, concurrent SSD compatibility testing and deployment in combination with the API data flow automation. 

### Additional SSD detail:

Further detail about both the SSD schema, data points and published outputs are available at: 

- [DDSF Project 1a final report] (https://www.datatoinsight.org/publications-1/standard-safeguarding-dataset---final-report) 
- [SSD project distribution Github web pages-public access-] (https://data-to-insight.github.io/ssd-data-model/)
- [SSD project distribution Github repo-request access-] (https://github.com/data-to-insight/ssd-data-model) 

For many LA's (SystemC/SQL Server), deploying the SSD can take as little as 15minutes, dependent on local|bespoke configurations. 

<!-- For more details on the [JSON payload structure](payload_structure.md) -->
