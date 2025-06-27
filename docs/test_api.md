# Setup Guide - Deploy API - Test


## Prerequisites
Ensure that the [SSD is already deployed ](deploy_ssd_schema.md) has already been checked|completed.<br> 
Ensure that the [api configuration](configure_api_script.md) details have already been checked|completed. 


## **Phased Local Testing** (in progress):

Prior to sending sample|live data payloads externally we support testing both the data extract and staging collection table process(es) locally. This is part of Phase 1 & 2 testing in the table below. 

During the staged API data payload tests, in order to further reduce any uneccessary data handling/visability at both process ends(LA|DfE), we test using an agreed, phased testing workflow prior to, but building up to, the live payload submission(s):  

    | Test Phase     | Description                                                                                             |
    |----------------|---------------------------------------------------------------------------------------------------------|
    | **Phase 1**    | Low-volume fake/constructed data (single record) to establish basic send/receive process functionality. |
    | **Phase 2**    | High-volume fake/constructed data* to test process scalability and DB connection.                       |
    | **Phase 3**    | Low-volume fake/scrambled payloads (single record) to test live process table.                          |
    | **Phase 4**    | Full/delta payloads of fake/scrambled data* to validate live process table at scale.                    |
    | **Phase 5**    | Live payload table used for final testing after using only fake data in earlier phases.                 |

_*Marked processes require additional LA access to Python/Anaconda in order to run the Python based scripts. D2I cannot run these from outside your LA, but will support you running them._  
The above table also shown in context within the [data security and privacy page](data_security.md)

## **Test API Locally** (in progress):  

- Refer to the API Configuration page, and settings within the *Execution* section, specifically *Testing Mode* flag. 
   - Discuss with D2I support regarding whether your LA has the option to run additional Python based scripts towards creating scrambled models of fake data from your LA's data structures.
   - Run the API-JSON extract script(Powershell) in testing mode `$testingMode = $true` to validate the process without submitting/sending data externally.
   - Verify submission statuses update correctly in the $ssd_api_data_staging table. 


