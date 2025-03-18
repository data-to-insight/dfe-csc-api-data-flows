## Ensuring Data Anonymisation & Privacy Protection

This section outlines the rigorous anonymisation processes employed to ensure that re-identification of individuals is computationally infeasible during initial payload tests between LA and DfE endpoint/internal review. Our approach aligns with best practices in data security, cryptography, and privacy protection.

### Key Principles of the Anonymisation Approach

1. **Complete Pseudonymisation** - All personally identifiable information (PII) is replaced with pseudo-randomised values that bear no correlation to the original data.
2. **Irreversible Hashing** - Key identifiers are hashed using cryptographic techniques, ensuring that reversing the process is mathematically infeasible.
3. **Logical & Consistent Randomisation** - Dates, attributes, and categorical values are randomly replaced while maintaining logical consistency within records.
4. **Minimised Data Retention** - No raw data is retained post-processing, ensuring that even internal access is limited to anonymised versions - if developers are accessing only the anon staging table/record and|or the payloaded data. 
5. **Minimised Data Payloads** - During the staged payload tests, in order to further reduce uneccessary data handling/visability at both process ends, we develop/test within a staged process towards payload testing:  

 - 1) low-volume constructed data to establish the send-receive processes are functional. Once this is confirmed we initiate (2) 
 - 2) low-volume anonymised payloads 
 - 3) full|delta payloads of anonymised records
 - 4) live payload table for live testing. 

6. **Industry-Trusted Libraries** - We employ industry standard cryptographic and data generation libraries developed and agreed by the global Python development community.

### Anonymisation Process

#### 1. Hashing Identifiable Data

For all unique identifiers (e.g., person IDs, unique pupil numbers, care worker IDs), we apply a secure hashing function:

- SHA-256 hashing is used to generate fixed-length, irreversible hashed values.
- The resultant hashes are truncated appropriately to fit specific data field requirements(api compliance).
- Since hashing is deterministic, it allows cross-referencing(instances of care worker for example are maintained(but hashed)) without compromising individual identities.

#### 2. Randomisation of Demographic Information

Personal attributes such as names, ethnicities, and postcodes are completely replaced with randomly generated equivalents:

- Names are substituted with generic placeholders or synthetic names.
- Dates of birth are randomly shifted within a pre-defined plausible range.
- Ethnicities, gender, and other demographic details are assigned pseudo-randomly from DfE options list if available e.g. disabilities: ["NONE", "MOB", "HAND", "PC", "INC", "COMM", "LD", "HEAR", "VIS", "BEH", "CON", "AUT", "DDA"]. We do however, not maintain statistical distributions within the data set. 

#### 3. Controlled Temporal Randomisation

- We ensure all date fields (e.g., birthdates, appointment dates, case start/end dates) are randomised within logical constraints.
- Relative time intervals (e.g., event sequences) are preserved to maintain usability for analytics.

#### 4. Pseudonymisation of Structured Records

For structured records like care episodes, worker details, and assessments:

- Unique IDs are replaced with hashed values.
- Dates are adjusted in a way that preserves chronological order but removes specificity.
- Categorical values (e.g., referral sources, closure reasons) are mapped to DfE equivalent random|pseudo-anonymised alternatives.

#### 5. Validation & Integrity Checks

During D2I pre-deployment testing, we add an additional safety/failsafe check, to ensure anonymisation:

- Each anonymised record is compared against the original to confirm full transformation.
- Any unchanged values are flagged for additional manual visual checks.  


### Mathematical Improbability of Re-Identification

Given our approach, the probability of either successfully reconstructing original records, or any form of direct association with live individual data records is effectively zero:

- **SHA-256 hashing** ensures a brute-force attempt would require computational resources beyond feasibility.
- **Pseudorandom attribute substitution** removes any direct correlation to the original data.
- **Randomised dates and categorical values** eliminate predictability, making linkage attacks impractical.
- **Cross-record inconsistencies** prevent meaningful insights from being derived even if partial data is visible.
- **Daily re-anonymisation** daily re-anonymisation of records ensures an additional level of randomisation between tests.


Through a multi-layered anonymisation strategy, we guarantee that re-identification of individuals is infeasible, ensuring compliance with data privacy regulations and best practices. The highest standards of data security are upheld throughout our processes.
