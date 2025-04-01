## Ensuring Data Anonymisation & Privacy Protection

During initial API testing within partner LAs, we can offer staged test-data payloads to remove pre-live data risk. Option i) uses minimal volume constructed fake data(<10 records) to enable confirmation of the required data-flow between LA and DfE. Subsequently option ii), once safe connectivity has been established (API correctly received constructed data), it can be useful to broaden the scope of the test(s) to more realistic data breadth and volume. This is particularly important during phase 1, where complete|larger data sets(as the 'payload') are being sent, as opposed to the intended much smaller updated data(as phase 2 'deltas'). In order to achieve this, we can generate an anonymised and scrambled 'model' of the relevant LA's live (SSD)data, and use this 'template data' to further ensure the data flow is working, without ever sending any live data.  

Towards this, a rigorous anonymisation processes is employed to create this false|scrambled dataset. In essence the process 'models' the structure of the LA's data, but bears no resemblence to the actual data. This ensures that any re-identification of individuals is computationally infeasible during such payload tests between LA and DfE endpoint/internal review. This enables developers at either end of the process to have visibilty only of trashed|template records where no aspect of the data elements reflects live records. Our approach aligns with best practices in data security, cryptography, and privacy protection. To assist in understanding what the anonymisation process entails, the following details aim to break down the key aspects of it to ensure transparency.  

### Key Principles of the Anonymisation Approach

1. **Complete Pseudonymisation** - All personally identifiable information (PII) is replaced with randomised values that bear no correlation to the original data.
2. **Irreversible Hashing** - Key identifiers are encoded(hashed) using cryptographic techniques, ensuring that reversing the process is mathematically infeasible. In essense, once encoded, it would be near-impossible to unencode any individual data item/id with commercially available tools. 
3. **Logical & Consistent Randomisation** - Dates, attributes, and categorical values(e.g. ethnicity, disability) are randomly replaced (using DfE values) while maintaining logical consistency within records.
4. **Minimised Data Retention** - No raw data is retained post-processing, ensuring that even internal/developer access is limited to anonymised versions - Thsi applies if developers are accessing only the anon staging table/record and|or the payloaded data. 
5. **Minimised Data Payloads** - During the staged payload tests, in order to further reduce uneccessary data handling/visability at both process ends(LA|DfE), we test using an agreed, stepped, process towards payload testing:  

 - 1) low-volume constructed data to establish the send-receive processes are functional. Once this is confirmed we initiate (2) 
 - 2) low-volume anonymised payloads 
 - 3) full|delta payloads of anonymised records
 - 4) live payload table for live testing. 

6. **Industry-Trusted Libraries** - We employ industry standard cryptographic and data generation libraries developed and agreed by the global Python development community.

### Anonymisation Process

#### 1. System Identifiable Data

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

Given our approach, the probability of either successfully reconstructing original records, or any form of direct association with live individual data records is effectively zero:

- **SHA-256 hashing** ensures a brute-force attempt would require computational resources beyond feasibility.
- **Pseudorandom attribute substitution** removes any direct correlation to the original data.
- **Randomised dates and categorical values** eliminate predictability, making any derived connections to real records impractical.
- **Cross-record inconsistencies** prevent meaningful insights from being derived even if partial data is visible.
- **Daily re-anonymisation** daily re-anonymisation of records ensures an additional level of randomisation between tests.


Through a multi-layered anonymisation strategy, we guarantee that re-identification of individuals is infeasible, ensuring compliance with data privacy regulations and best practices. The highest standards of data security are upheld throughout our processes.
