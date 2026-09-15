# 05 - Silver layer

Silver turns Bronze's raw text into clean, typed tables that are easy to join. Every Silver table is one SQL file in `databricks/pipelines/silver/`, and they all follow the same steps.

## The pattern

Each file is a materialized view that does the same things:

1. **Remove duplicates.** If the same record was loaded more than once, keep the latest copy (`QUALIFY row_number() ... = 1`). Tables without an id in Synthea get one built from the columns that identify a row.
2. **Set types.** Dates, timestamps and amounts are cast from text with `try_cast`, so a bad value becomes empty instead of failing the load.
3. **Clean and decode.** Readable names replace short codes (for example `M` becomes `Male`), and Synthea's quirks are cleaned up (digits on names, "(disorder)" at the end of descriptions).
4. **Add missing codes.** A join to a reference table adds what Synthea doesn't provide, such as ICD-10-CM codes, CPT codes, lab panels and payer types.
5. **Combine sources.** Where the Epic FHIR sandbox has the same kind of record (patients, encounters, conditions, providers, organizations), its rows are read out of the FHIR JSON and added with `UNION ALL`, marked with `source_system`.

Each table also has a few **expectations** (data quality checks). Rows that fail are kept, but the pipeline counts them, so problems are visible without losing data.

## Tables

| Table | One row per | Built from | Key transformations |
|---|---|---|---|
| `patient` | Patient | `synthea_patients`, Epic `Patient` | Dates cast; digits removed from names; sex, ethnicity and marital status decoded; SSN, driver's license and passport left out; Epic race and ethnicity read from US Core extensions |
| `encounter` | Visit or hospital stay | `synthea_encounters`, Epic `Encounter` | Timestamps and costs cast; care setting (Inpatient, Emergency, Urgent Care, Outpatient, Virtual, Post-Acute); ICD-10-CM code for the visit reason; death certificate records flagged as administrative |
| `condition` | Condition recorded for a patient | `synthea_conditions`, Epic `Condition` | ICD-10-CM code, condition class, condition group, Charlson category, chronic flag and social-factor domain. Epic already sends ICD-10-CM (`icd10_source = 'source'`). |
| `procedure` | Procedure performed | `synthea_procedures` | CPT, HCPCS or CDT code: first from the explicit map, otherwise from a description rule (`code_mapping` says which); service category and billable flag; reason ICD-10-CM |
| `observation` | Lab result, vital sign or survey answer | `synthea_observations` | Exact duplicates removed; Synthea's quality-of-life scores (QOLS, QALY, DALY) left out; numeric values parsed; lab panel; abnormal flag from reference ranges (critical_low, low, normal, high, critical_high) |
| `medication` | Medication order | `synthea_medications` | Timestamps, dispenses and costs cast; active flag; reason ICD-10-CM and condition group |
| `immunization` | Vaccine dose | `synthea_immunizations` | CPT code from the CVX code |
| `allergy` | Allergy | `synthea_allergies` | Reactions and severities; highest severity |
| `provider` | Clinician | `synthea_providers`, Epic `Practitioner` | Names cleaned; sex decoded; specialty |
| `organization` | Facility | `synthea_organizations`, Epic `Organization` | Names tidied; coordinates cast |
| `payer` | Insurance payer | `synthea_payers` | Payer type and category (Medicare, Medicare Advantage, Medicaid, Dual Eligible, Commercial, Self-Pay) |
| `coverage` | Coverage period | `synthea_payer_transitions` | Dates cast; policy owner name cleaned; payer type |
| `claim` | Claim | `synthea_claims` | Claim type (Professional or Institutional); every diagnosis looked up, principal diagnosis = first one with an ICD-10-CM code, all ICD-10-CM codes kept as a list; status and outstanding amounts |
| `claim_transaction` | Charge, payment or balance transfer | `synthea_claims_transactions` | Amounts cast; who a transfer went to (primary insurance, secondary insurance, patient); payment method; CPT for procedure and vaccine lines |

## Results on the dev run (2026-09-15)

| Table | Rows | From Epic sandbox | Failed checks |
|---|---|---|---|
| `patient` | 1,145 | 1 | 0 |
| `encounter` | 62,209 | 10 | 0 |
| `condition` | 39,185 | 7 | 0 |
| `procedure` | 174,594 | | 0 |
| `observation` | 730,801 | | 0 |
| `medication` | 50,379 | | 27 (see below) |
| `immunization` | 16,604 | | 0 |
| `allergy` | 1,302 | | 0 |
| `provider` | 814 | 3 | 0 |
| `organization` | 812 | 1 | 0 |
| `payer` | 10 | | 0 |
| `coverage` | 41,216 | | 0 |
| `claim` | 112,578 | | 3,272 (see below) |
| `claim_transaction` | 1,023,970 | | 0 |

Every id is unique. Every encounter, claim and encounter-linked condition points to a patient and encounter that exist.

Some numbers worth knowing:

- **Observations:** 762,751 Bronze rows became 730,801. 267 were exact duplicates and 31,683 were quality-of-life scores.
- **Procedures:** 171,432 rows got their billing code from the explicit map and 3,162 from a description rule.
- **Labs:** 165,858 normal, 33,986 high, 16,827 low, 1,972 critically low and 116 critically high. 107,081 have no flag because they're text results or tests without a reference range.
- **Claims:** 109,306 of 112,578 (97.1%) have an ICD-10-CM principal diagnosis.

## What the checks caught

| Check | What happened | What we did |
|---|---|---|
| `encounter.reason_code_mapped` | 9,911 visit reasons had no ICD-10-CM code. Synthea uses 20 SNOMED codes only as visit reasons (dental referrals, contraception care, screenings, food allergens), so they weren't in the condition mapping. | Added them to `reference/snomed_icd10cm_conditions.csv`, checked against the CMS code file. Now passes. |
| `claim.has_principal_diagnosis` | 13,803 claims listed a visit type (checkup, urgent care, eye exam, vaccine visit) as the diagnosis, and about 26,000 listed "Medication review due" or a positive social factor like "Full-time employment" first. | Added the visit types as ICD-10-CM encounter codes (Z00.00, Z00.129, Z23 and so on) and "Medication review due" as Z79.899, and changed the rule to use the first diagnosis on the claim that has an ICD-10-CM code. 3,272 claims still fail: their only diagnoses are employment or education findings, which have no billable code. They're kept and flagged. |
| `medication.stop_not_before_start` | 27 medication orders stop before they start. They're renewals of diabetes medications where Synthea recorded the stop from the previous order. | Kept and flagged. This is a real problem in the source data, so the check stays. |

## Running the checks

- `databricks/validation/data_quality_results.sql`: passed and failed rows for every expectation in the latest pipeline update.

## Not in Phase 1

- Epic sandbox observations, medications, allergies and immunizations. Only one sandbox patient comes through, so these can be added later without changing the pattern.
