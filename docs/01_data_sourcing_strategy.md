# 01 — Data Sourcing Strategy

## The constraint

Epic customers see their data in three places:

- **Chronicles**: the operational database behind Hyperspace (the clinician app)
- **Clarity**: a relational SQL Server/Oracle copy, refreshed nightly, with about 18,000 tables
- **Caboodle**: a dimensional warehouse

Integrations use **FHIR R4 APIs**, and **Bulk FHIR** for population-level exports.

None of this can be reached without being an Epic customer or vendor. What *is* public:

| Source | What you get | Volume | Access |
|---|---|---|---|
| **Epic on FHIR sandbox** (fhir.epic.com) | Real Epic R4 endpoints, real OAuth 2.0 backend-services auth, Epic-specific behavior (required search params, `OperationOutcome` warnings, Epic IDs) | **Tiny**: a few dozen test patients | Free developer account |
| **Synthea** (MITRE) | Synthetic patients with full lifetime histories. Exports FHIR R4 Bulk NDJSON **and** CSV, including payers, claims and claim transactions. | **Unlimited** (you choose N) | Open source, runs locally on Java |
| SMART Health IT sandbox / HAPI public server | Generic FHIR test servers | Small–medium | Open |
| CMS DE-SynPUF / CMS synthetic Medicare claims | Realistic Medicare claims structure | Millions of rows | Public download |
| MIMIC-IV (PhysioNet) | Real, de-identified ICU data | Large | Credentialing + training required; **not** Epic-shaped |

> **Phases.** Phase 1 uses the Epic FHIR sandbox and Synthea's data as generated (FHIR and CSV), with codes added from the reference tables. The Clarity-style tables, claims shaping and realism fixes described below are Phase 2 (see section 2a of the requirements).

## Decision: three layers

```text
 ┌──────────────────────┐   proves: real Epic API integration
 │ Epic FHIR Sandbox    │   (OAuth JWT, paging, Epic search rules)
 └──────────┬───────────┘
            │  same NDJSON shape
 ┌──────────▼───────────┐   proves: scale — Bulk FHIR export of a
 │ Synthea Bulk NDJSON  │   25k–100k patient health system
 └──────────┬───────────┘
            │  reshaped
 ┌──────────▼───────────┐   proves: understanding of Epic's analytical
 │ Clarity-style tables │   model (PAT_ENC, ORDER_RESULTS, HSP_ACCOUNT…)
 │ + 837/835 claims     │   and the clinical ↔ financial join
 └──────────────────────┘
```

Why this is realistic rather than a toy:

1. **One ingestion code path.** Epic sandbox output and Synthea output land as identical `ResourceType.ndjson` files. In production you would point the same Bronze pipeline at a real Epic Bulk FHIR `$export`.
2. **Two ways to read Epic data.** Real Epic shops use FHIR for integration and Clarity for analytics. The project handles both and reconciles them in Silver.
3. **Volume that stresses Spark.** Observations alone reach tens of millions of rows at 25k+ patients. The profiling script records the exact counts.

## Where Synthea is *not* like real Epic data (and what we do about it)

Being clear about these gaps up front keeps the results honest.

| Gap | Real hospital data | Synthea | Our fix (Phase 2) |
|---|---|---|---|
| Diagnosis coding | ICD-10-CM on encounters & claims | SNOMED CT | Curated SNOMED→ICD-10-CM crosswalk for the finite set of Synthea condition codes |
| Procedure coding | CPT/HCPCS (professional), ICD-10-PCS (inpatient) | SNOMED CT | Crosswalk to CPT/HCPCS; revenue codes by department |
| Inpatient grouping | MS-DRG on hospital accounts | none | Rule-based DRG assignment from principal dx + LOS |
| Denials / remits | 835 with CARC/RARC codes | payments only | Synthesize denials with payer-specific rates + CARC codes |
| Readmissions | ~14–15% all-cause (Medicare) | Weak / module-driven | Measure first; if the signal is too weak, add a documented, calibrated readmission layer so the ML target is realistic |
| Data quality | Messy: duplicate MRNs, late claims, bad units, free-text | Very clean | **Deliberate defect injection** (duplicates, nulls, future dates, unit mismatches, orphan claims, late-arriving files) with a defect manifest so Silver DQ rules can be scored against it |
| Operational realism | Departments, cost centers, IDs like CSN/MRN | UUIDs | Generate Epic-style identifiers (`PAT_ID`, `PAT_MRN_ID`, `PAT_ENC_CSN_ID`) and a department hierarchy |

## Target Clarity-style tables (Phase 2)

Names follow real Clarity conventions: `_C` columns are category values that join to `ZC_` lookup tables, and `_YN` columns are Y/N flags.

| Clarity-style table | Grain | Built from Synthea |
|---|---|---|
| `PATIENT` | patient | patients.csv |
| `PAT_ENC` | every patient contact (CSN) | encounters.csv |
| `PAT_ENC_HSP` | hospital encounters (IP/ED/OBS) with admit/discharge, disposition | encounters.csv (inpatient, emergency) |
| `PAT_ENC_DX` | diagnoses per encounter, primary flag | conditions.csv + ICD-10 crosswalk |
| `PROBLEM_LIST` | active chronic problems | conditions.csv (no stop date) |
| `CLARITY_EDG` | diagnosis master | distinct condition codes |
| `ORDER_PROC` / `ORDER_RESULTS` / `CLARITY_COMPONENT` | lab orders, result components, reference ranges, abnormal flags | observations.csv (laboratory) |
| `IP_FLWSHT_MEAS` | vitals flowsheet rows | observations.csv (vital-signs) |
| `ORDER_MED` / `CLARITY_MEDICATION` | medication orders | medications.csv |
| `ALLERGY` | allergies | allergies.csv |
| `CLARITY_SER` | providers | providers.csv |
| `CLARITY_DEP` | departments | organizations.csv + synthesized departments |
| `CLARITY_EPM` / `COVERAGE` | payers, coverage | payers.csv, payer_transitions.csv |
| `HSP_ACCOUNT` / `HSP_TRANSACTIONS` | hospital billing, DRG, total charges | claims.csv, claims_transactions.csv |
| `ARPB_TRANSACTIONS` | professional billing | claims_transactions.csv |
| `ZC_*` | lookups (encounter type, patient class, disposition, sex…) | static seeds |

Claims (payer view) are a separate source system:

- `CLAIM_HEADER` and `CLAIM_LINE` (837-style)
- `REMITTANCE` (835-style)
- `MEMBER_ELIGIBILITY`

## Scale plan

| Tier | Patients | Purpose |
|---|---|---|
| dev | 1,000 | Build & debug pipelines quickly |
| demo | 25,000 | Full dataset: a realistic mid-size health system |
| stretch | 100,000 | Performance tuning story (partitioning, liquid clustering, Photon) |

Synthea's `-s` seed makes every run reproducible. Always record the seed in the run manifest.

## Landing zone layout

```text
raw/
  epic_fhir/extract_date=YYYY-MM-DD/run_id=<ts>/Patient.ndjson ...
  synthea_fhir/run_id=<label>/Patient.ndjson ...         (Bulk FHIR shape)
  clarity/run_id=<label>/PAT_ENC/part-*.csv ...          (Phase 2)
  claims/run_id=<label>/CLAIM_HEADER/part-*.csv ...       (Phase 2)
```

On Databricks this path becomes a Unity Catalog Volume (e.g. `/Volumes/healthcare/landing/raw/`). On Azure it becomes an ADLS Gen2 container. The pipelines stay the same either way.

## Dev run profile — `p1000_s42_massachusetts` (2026-09-15)

1,144 patients (1,000 alive, 144 deceased). 3.5 GB on disk: CSV 744 MB, FHIR NDJSON 2.7 GB, notes 84 MB.

| Entity | Rows |
|---|---|
| claims_transactions | 1,023,970 |
| observations (CSV) / Observation (FHIR) | 762,751 / 514,766 |
| procedures | 174,594 |
| claims / ExplanationOfBenefit | 112,578 |
| encounters / DocumentReference (notes) | 62,199 |
| medications | 50,379 |
| conditions | 39,178 |

Realism findings that drive Phase 2:

| Check | Result | Real-world benchmark | Action |
|---|---|---|---|
| 30-day all-cause readmission rate | 13.3% (136 of 1,023 stays) | ~14–15% Medicare | Rate looks right, **but 90% of readmits come from the stage-1 lung cancer module**. Those are planned treatment admissions, which CMS excludes. CHF readmits: 4. → Exclude planned admissions and inject a calibrated unplanned readmission layer (CHF, COPD, pneumonia, AMI, sepsis). |
| Inpatient LOS | median 3.4 d, p90 10.7 d | mean ~4.5–5 d | OK |
| ED visits | ~144 / 1,000 patients / year | ~400 / 1,000 (US) | Low → add ED visit injection for high-utilizer segment |
| Diagnosis coding | 100% SNOMED CT | ICD-10-CM | Crosswalk needed (confirmed) |
| Conditions include SDOH findings | e.g. "Full-time employment (finding)", "Social isolation (finding)" | Separate SDOH screening data | Silver classifies SNOMED `(finding)`/`(situation)` as SDOH/observations, not diagnoses. SDOH becomes a risk feature. |
| History window | Some encounters date back to 1917 | Typical EHR go-live ~2010s | Silver filters the analytic window. Older rows are kept only as history flags. |
| Payers | Medicare, Medicaid, Dual, Humana, BCBS, UHC, Aetna, Cigna, Anthem, uninsured | Realistic mix | OK |
| Claim transactions | CHARGE / PAYMENT / TRANSFERIN / TRANSFEROUT | 837 + 835 with adjustments & denials | Add CARC denial codes & contractual adjustments |

Upload scope: skip `Claim`, `ExplanationOfBenefit` and `Provenance` NDJSON (about 1.3 GB). Claims come from the CSV path as 837/835-style tables, which is closer to how payer data really arrives.
