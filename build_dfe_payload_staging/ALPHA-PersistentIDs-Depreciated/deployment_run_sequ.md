
# SSD Persistent Identity Pipeline
## Script Execution Order: Initial Setup, Testing & Normal Operation

This guide separates initial installation, local testing, transition to normal operation & recurring processing.

**Key principle:** Identity tables do not need resetting when moving from testing to normal operation, provided existing GUIDs are correct & suitable for retention as permanent identities.

**External API submissions remain disabled throughout testing until explicitly authorised.**

---

## 1 Init-Setup: Run Once

| Order | Script | Purpose |
|---|---|---|
| 00 | `00_OPTIONAL_TEST_ONLY_reset_identity_data.sql` | **Optional ** Clear existing test identity history if starting completely fresh. Never use after identities have been published |
| 01 | `01_create_identity_tables.sql` | Create three permanent identity tables |
| 02 | `02_capture_five_entities.sql` | Capture initial SSD records into observation history |
| 03 | `03_bootstrap_entity_registry.sql` | Generate first permanent GUIDs & establish registry. **One-time only** |
| 04 | `04_verify_identity_baseline.sql` | Verify baseline identities & parent relationships |
| 05 | `05_identity_reconciliation_lab.sql` | Optional initial acceptance test for simulated DW source-ID regeneration |

### What happens?

**01_create_identity_tables.sql**
- Creates `ssd_api_identity_run`, `ssd_api_entity_observation` & `ssd_api_entity_registry`
- Establishes permanent storage for capture history, identity evidence & stable GUIDs
- Tables persist across subsequent DW refreshes

**02_capture_five_entities.sql**
- Reads five supported SSD entity types
- Creates temporary `#ReferralPerson` & `#Incoming` tables
- Inserts one new `Captured` run into `ssd_api_identity_run`
- Inserts unresolved observations into `ssd_api_entity_observation`

**03_bootstrap_entity_registry.sql**
- Creates temporary `#BootstrapIds`
- Generates unique GUIDs using `NEWID()`
- Inserts permanent identities into `ssd_api_entity_registry`
- Assigns `stable_id` & `parent_stable_id` to baseline observations
- Changes run status from `Captured` to `Validated`

**04_verify_identity_baseline.sql**
- Read-only verification
- Checks GUID uniqueness, registry references & parent-child relationships
- No permanent table modifications

**05_identity_reconciliation_lab.sql**
- Simulates regenerated DW source identifiers
- Tests matching rules against existing identities
- Uses temporary tables; does not modify permanent identity history

**Outcome:** Permanent identity registry established, with validated baseline observations

**Important:** Script `03` must never be repeated during subsequent refreshes

---

## 2 Local Testing: Repeat as Required

This workflow tests reconciliation, identity continuity & staging integration without external submission.

| Order | Script | Purpose |
|---|---|---|
| 01 | `02_capture_five_entities.sql` | Capture current SSD snapshot, producing new `Captured` run |
| 02 | `06_apply_identity_reconciliation.sql` | Execute with `@dry_run = 1`; inspect proposed identity matches |
| 03 | `06_apply_identity_reconciliation.sql` | Rerun same capture with `@dry_run = 0`; commit validated GUID mappings |
| 04 | `06_verify_reconciled_run.sql` | Verify current identities, registry references & parent relationships |
| 05 | **CSC API staging v0.6.0** | Build JSON using `#IdentityMap`; update `ssd_api_data_staging` |
| 06 | `08_verify_staging_identity_integrity.sql` | Check outgoing JSON GUIDs against permanent registry |
| 07 | `05_identity_reconciliation_lab.sql` | Optional separate simulation of regenerated identifiers |

### What happens?

**02_capture_five_entities.sql**
- Inserts another capture run & its current observations
- Preserves all historical observations & existing GUIDs
- Does not generate replacement GUIDs

**06_apply_identity_reconciliation.sql — Dry Run**
- Reads current observations, historical observations & registry
- Attempts to recognise existing logical records
- Resolves parent episodes before nested records
- Proposes GUID matches & identifies unresolved records
- Does not modify permanent tables

**06_apply_identity_reconciliation.sql — Commit**
- Applies successfully validated mappings
- Updates current observations with permanent GUIDs
- Updates registry last-seen information
- Creates new GUIDs only when explicitly permitted under restricted rules
- Changes run status to `Validated` when all observations resolve
- Blocks incomplete or ambiguous runs rather than guessing

**06_verify_reconciled_run.sql**
- Read-only post-reconciliation validation
- Confirms GUID assignments, registry mappings & parent relationships

**CSC API staging v0.6.0**
- Creates temporary `#IdentityMap` using selected validated run
- Builds outgoing JSON with permanent GUIDs
- Creates temporary `#Hashed` containing JSON & SHA-256 hashes
- Updates changed staging records
- Inserts new staging records
- Soft-deletes records genuinely absent from current eligible source population

**08_verify_staging_identity_integrity.sql**
- Read-only verification of outgoing JSON identifiers
- Confirms GUIDs exist within permanent registry & belong to correct person/entity type

### Testing considerations

- Run `02` only once per intended capture
- Use same `run_id` for dry-run, commit, verification & staging
- Do not rerun `03_bootstrap_entity_registry.sql`
- `05_identity_reconciliation_lab.sql` is simulation-only; no permanent identity writes
- `08_verify_staging_identity_integrity.sql` is the suggested name for previously supplied read-only SQL, not yet a confirmed packaged script
- Staging v0.6.0 is the existing modified staging SQL, not yet a separately packaged `07` script
- External submission remains **OFF**

---

## 3 Moving From Testing to Normal Operation

Two possible approaches.

### Opt A: Retain Tested Identities (Recommended)

If registry, historical observations & staged GUIDs are correct:

**No reset required.**

Retain:

- `ssd_api_entity_registry`
- `ssd_api_entity_observation`
- `ssd_api_identity_run`
- `ssd_api_data_staging`

### What happens?

- Existing test baseline becomes retained permanent identity history
- Previously generated GUIDs continue unchanged
- Future snapshots reconcile against existing history
- Staging continues using permanent GUIDs
- No need to rebuild or re-bootstrap identity registry

**Before unattended operation:** Complete acceptance testing for source-ID regeneration, genuinely new records, changed identifying attributes & ambiguous matches.

### Opt B: Completely Fresh Deployment After Testing

Only appropriate where existing test GUIDs have **never been consumed or published externally**.

| Order | Script / Action | Purpose |
|---|---|---|
| 00 | `00_OPTIONAL_TEST_ONLY_reset_identity_data.sql` | Clear existing identity run, observation & registry records |
| 01 | Separate staging reset | Clear existing test data from `ssd_api_data_staging` |
| 02 | `02_capture_five_entities.sql` | Capture fresh baseline source records |
| 03 | `03_bootstrap_entity_registry.sql` | Generate completely new permanent GUIDs |
| 04 | `04_verify_identity_baseline.sql` | Validate new baseline identities |
| 05 | CSC API staging v0.6.0 | Rebuild outgoing JSON using new baseline GUIDs |
| 06 | `08_verify_staging_identity_integrity.sql` | Validate outgoing GUIDs against new registry |

### Important reset considerations

- Script `00` resets identity data **not staging data**
- Staging reset must be managed separately
- Do not clear identity registry while retaining staging JSON referencing discarded GUIDs
- `01_create_identity_tables.sql` does not need repeating if compatible tables already exist
- Do not reset identities after any GUID has been consumed externally
- A fresh baseline produces different GUIDs from the previous test baseline

---

## 4 Normal Running: Every Subsequent SSD Refresh

| Order | Script / Process | Purpose |
|---|---|---|
| 01 | Upstream **DW / SSD refresh** | Refresh source tables; protect three permanent identity tables |
| 02 | `02_capture_five_entities.sql` | Capture latest source records & insert new observations |
| 03 | `06_apply_identity_reconciliation.sql` | Resolve current observations to permanent GUIDs; dry-run then commit during manual operation |
| 04 | `06_verify_reconciled_run.sql` | Confirm reconciliation completed successfully |
| 05 | **CSC API staging v0.6.0** | Select current validated `run_id`, build JSON & update/insert/soft-delete staging records as appropriate |
| 06 | `08_verify_staging_identity_integrity.sql` | Verify permanent GUIDs in staged JSON |
| 07 | External submission process | Remains disabled until explicitly authorised |

### What happens?

**DW / SSD refresh**
- Source tables updated or rebuilt
- Source identifiers may change
- Persistent identity tables remain untouched

**02_capture_five_entities.sql**
- Recreates temporary capture tables
- Inserts new run into `ssd_api_identity_run`
- Inserts new observations into `ssd_api_entity_observation`
- Retains historical runs & permanent GUID registry

**06_apply_identity_reconciliation.sql**
- Compares latest observations against historical identity evidence
- Reuses GUIDs for confidently matched logical records
- Matches parent episodes before nested assessments & plans
- Optionally generates restricted new identities when explicitly permitted
- Holds unresolved or ambiguous matches for investigation
- Updates current observations & validates completed run

**06_verify_reconciled_run.sql**
- Confirms current identities are correctly resolved
- Checks registry & parent-child integrity
- No persistent changes

**CSC API staging v0.6.0**
- Recreates temporary `#IdentityMap` from current validated observations
- Recreates temporary `#Hashed` from generated JSON
- Uses permanent GUIDs for five supported nested record types
- Compares JSON hashes with existing staging records
- Updates changed records, inserts new records & handles genuine cohort removals
- Does not routinely truncate `ssd_api_data_staging`

**08_verify_staging_identity_integrity.sql**
- Checks outgoing JSON IDs against registry
- Confirms valid permanent identity references
- Does not modify staging records

**External submission**
- Separate controlled operation
- Disabled throughout testing
- Successful reconciliation or staging verification does not automatically enable submission

---

## 5 Scripts Not Normally Repeated

| Script | Reason |
|---|---|
| `00_OPTIONAL_TEST_ONLY_reset_identity_data.sql` | Would erase persistent identity history. Test-only reset |
| `01_create_identity_tables.sql` | Permanent tables already exist |
| `03_bootstrap_entity_registry.sql` | Initial GUID allocation already completed |
| `04_verify_identity_baseline.sql` | Initial baseline verification; recurring runs use `06_verify_reconciled_run.sql` |
| `05_identity_reconciliation_lab.sql` | Optional development simulation, not normal processing |

---

## 6 Simplified Process Lifecycle

### ONE-TIME INSTALLATION

`01 --> 02 --> 03 --> 04`

- Create permanent identity tables
- Capture initial baseline
- Allocate permanent GUIDs
- Verify baseline identities

### LOCAL ACCEPTANCE TESTING

`05 (optional simulation)`

Then:

`02 --> 06 (dry-run) --> 06 (commit) --> verification --> staging --> staging verification`

- Test existing identity matching
- Test reconciliation write-back
- Test permanent GUIDs in outgoing JSON
- Keep external submissions disabled

### TRANSITION TO NORMAL OPERATION

**Recommended: No reset.**

- Retain existing registry
- Retain observation history
- Retain valid staging records
- Complete outstanding acceptance tests
- Continue subsequent refresh workflow

**Alternative: Deliberate full test reset.**

`00 --> staging reset --> 02 --> 03 --> 04 --> staging --> verification`

Only before external consumption or publication of generated GUIDs

### NORMAL RECURRING OPERATION

`DW refresh --> 02 --> 06 --> verification --> staging --> staging verification`

- Capture current source records
- Reconcile against historical GUIDs
- Validate current identity assignments
- Build JSON using permanent GUIDs
- Update staging without routine truncation
- Keep submission separately controlled

---

## 7 Current Implementation Position

**Completed & tested:**
- Permanent identity table creation
- Five-type baseline capture
- Initial GUID allocation
- Baseline identity verification
- Simulated source-ID regeneration matching
- Subsequent capture reconciliation
- Transactional reconciliation write-back
- Post-reconciliation identity verification
- Staging JSON generation with permanent GUIDs

**Further acceptance testing required:**
- Real or shadow end-to-end source-ID regeneration
- Genuine new-record GUID allocation
- Changed identifying attributes
- Ambiguous record handling 
- Disappearing & reappearing records 
- Complete staging integrity verification
- Unattended pipeline execution safeguards

**Current recommendation:** Retain existing populated identity tables & staging records. No benefit from regenerating permanent GUIDs solely to transition from testing into normal operation.

**External API submissions: Disabled until explicit auth/manual run**
