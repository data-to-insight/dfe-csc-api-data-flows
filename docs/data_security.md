## Ensuring Data Security & Privacy Protection

All data remains within the local authority systems, and is stored on the same DB instances as the existing CMS up until an agreed point where the API connection has been tested, and live data payloads start. No data is automatically sent, unless the local authority has agreed it. Oversight of the data within each record and each payload is accessible before sending. 

During initial API testing within partner LAs, we're developing options for a phased(1-5) test-payload-data to remove any pre-live data risk during initial connectivity tests. 

Towards the later test phases(3|4), a rigorous scrambling processes can be employed to create this false|scrambled dataset. In essence the process 'models' the structure of the LA's data, but bears no resemblence to the actual data. This ensures that any re-identification of individuals is computationally infeasible during such payload tests between your LA and the DfE endpoint. This enables developers at either end of the process to have visibilty only of trashed|template records where no aspect of the data elements reflect live records. Our approach aligns with best practices in data security, cryptography, and privacy protection. To assist in understanding what the anonymisation process entails, the following details aim to break down the key aspects of it to ensure transparency. 

### Safe Data Testing Approach

1. **Minimised Data Payloads** - During the staged payload tests, in order to further reduce any uneccessary data handling/visability at both process ends(LA|DfE), we n test using an agreed, phased, process towards payload testing:  

    | Test Phase     | Description                                                                                             |
    |----------------|---------------------------------------------------------------------------------------------------------|
    | **Phase 1**    | Low-volume fake/constructed data (single record) to establish basic send/receive process functionality. |
    | **Phase 2**    | High-volume fake/constructed data* to test process scalability and DB connection (in development).                       |
    | **Phase 3**    | Low-volume fake/scrambled payloads (single record) to test live process table.                          |
    | **Phase 4**    | Full/delta payloads of fake/scrambled data* to validate live process table at scale (in development).                    |
    | **Phase 5**    | Live payload table used for final testing after using only fake data in earlier phases.                 |

_*Processes may require LA access to Python/Anaconda in order to run the Py based scripts. D2I cannot run these from outside your LA, but will support._  


2. **Complete Scrambling** - Every single data point (incl.personally identifiable information (PII)) is scrambled with randomised values that bear no correlation to the original stored data. The process creates new/entirely ficticious data record(s) and adds this back into the data structure(s). By doing this, we're able to model each record's data structure but with fake data. This is a second phase approach developed to enable realistic payload testing, with no data. The both constructed and fake data is stored in a staging table prior to any submissions for any local oversight/governance. 
3. **Irreversible Hashing** - Key identifiers are encoded(hashed) using cryptographic techniques, ensuring that reversing the process is mathematically infeasible. In essense, once encoded, it would be impossible to unencode any individual data item/id with commercially available tools. 
4. **Logical & Consistent Randomisation** - All data attributes, including dates and categorical values(e.g. ethnicity, disability) are randomly replaced (using DfE value ranges) while maintaining logical consistency within records.
5. **Minimised Data Retention** - No raw data is retained post-processing, ensuring that even internal/developer access is limited to scrambled versions - E.gg. if developers are accessing the staging table/record and|or the payloaded data, they see only the scrambled records. 
6. **Industry-Trusted Libraries** - We employ industry standard cryptographic and data generation libraries developed and agreed by the global Python development community.

### Scrambling Process

#### 1. System IDs

For all unique identifiers (e.g., person IDs, unique pupil numbers, care worker IDs), we apply a secure encoding("hashing") function:

- SHA-256 hashing* is widely used to generate encoded values (*it's a cryptographic function designed by the National Security Agency (NSA))

- Additional detail:  
  - The resultant hashes are truncated appropriately to fit specific data field requirements(api compliance).
  - Since hashing is deterministic, it allows cross-referencing(instances of care worker for example are maintained(but hashed)) without compromising individual identities.

#### 2. Randomisation of Demographic Information

Personal attributes such as names, ethnicities, and postcodes are completely replaced with randomly generated equivalents:

- Names are substituted with generic placeholders or synthetic names(we use a name generator).
- Dates of birth are randomly shifted within a pre-defined plausible range.
- Ethnicities, gender, and other demographic details are assigned randomly from DfE options list if available e.g. disabilities: ["NONE", "MOB", "HAND", "PC", "INC", "COMM", "LD", "HEAR", "VIS", "BEH", "CON", "AUT", "DDA"]. (Additional detail: We don't maintain statistical distributions within the data.) 

- We ensure all date fields (e.g., birthdates, appointment dates, case start/end dates) are randomised.
- Relative time intervals (e.g., event sequences) are preserved to maintain usability.

#### 3. Structured Records

For structured records like care episodes, worker details, and assessments:

- Unique IDs are replaced with hashed values.
- Dates are adjusted in a way that preserves chronological order but removes specificity.
- Categorical values (e.g., referral sources, closure reasons) are mapped to DfE equivalent random|anonymised alternatives.

#### 4. Validation & Integrity Checks

During D2I pre-deployment testing, we add an additional safety/failsafe check, to further ensure anonymisation:

- Each anonymised record is compared against the original to confirm full transformation.
- Any unchanged values are flagged for additional manual visual checks.  


### Improbability of Re-Identification

Given our approach, any form of direct association with live individual data records is zero:

- **SHA-256 hashing** ensures a brute-force attempt would require computational resources beyond feasibility.
- **Pseudorandom attribute substitution** removes any direct correlation to the original data.
- **Randomised dates and categorical values** eliminate predictability, making any derived connections to real records impossible.
- **Cross-record inconsistencies** prevent meaningful insights from being derived even if partial data was visible.
- **Daily re-scrambling** daily re-scrambling|anonymisation of records ensures an additional level of randomisation between tests.


Through a multi-layered scrambling|anonymisation strategy, we guarantee that re-identification of individuals is infeasible; thus ensuring compliance with data privacy regulations and industry best practices. The highest standards of data security are upheld throughout our processes and no live data leaves the local authority until the 1-4 phased payload tests are completed, and the the final live payloads are agreed sent. 
