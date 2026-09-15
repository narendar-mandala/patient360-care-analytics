# 04 - Problem Statement and Requirements

| | |
|---|---|
| Document | Requirements for the Healthcare Patient 360 and Predictive Care Analytics Platform |
| Version | 1.0 |
| Date | 2026-09-15 |
| Author | Narendar Mandala |
| Status | Approved. Decisions are in section 15. |
| Data | All data is synthetic. We still handle it as if it were real patient data. |

---

## 1. Problem statement

Picture a regional health system that uses Epic for clinical care and gets claims and remittances back from nine payers. Two of its biggest avoidable costs are patients who come back to the hospital within 30 days of discharge, and patients who keep ending up in the emergency department.

Why this matters:

- Medicare's Hospital Readmissions Reduction Program (HRRP) cuts payments by up to 3% for hospitals with higher than expected readmissions for heart attack, heart failure, pneumonia, COPD, bypass surgery and hip or knee replacement.
- A readmission costs around $15K on average (AHRQ HCUP), and much of that isn't reimbursed under fixed or value-based contracts.
- The care management team can only follow a limited number of patients. Right now they choose who to call from discharge lists and doctor referrals, not from any measure of risk.

The data needed to do better already exists. It's just spread across systems that don't talk to each other:

| System | What it has | What it's missing |
|---|---|---|
| Epic (FHIR / Clarity) | Visits, diagnoses, labs, vitals, medications, notes | Cost, what the payer paid, care received elsewhere |
| Claims and remittances (837/835) | Charges, allowed and paid amounts, denials, payer | How sick the patient is, lab results, social factors |
| Care management spreadsheets | Who was contacted | Whether it made a difference |

**In short:** when a patient is discharged, the health system can't easily tell who is likely to come back, why, or what it will cost. So care managers end up spending their time on the wrong patients.

### 1.1 What we're building

A lakehouse that brings Epic clinical data and claims together into a single view of each patient. It will:

- give each inpatient discharge a 30-day readmission risk score
- explain that score in plain language
- give care managers a ranked call list, and give leadership reports on quality, utilization and cost

### 1.2 How we'll know it worked

| ID | Outcome | How we measure it | Target |
|---|---|---|---|
| BO-1 | Care managers reach the right patients | Capture rate in the top 20% risk tier: the share of actual readmissions that fall in the top 20% of risk scores (on held-out data) | At least 50%. Picking at random would get 20%. |
| BO-2 | Better than what clinicians use today | Model AUROC compared with the LACE index on the same data | At least 0.03 higher than LACE, and at least 0.70 overall |
| BO-3 | Everyone uses the same numbers | KPIs are defined once in Gold and reused by every report | 0 KPI definitions outside Gold and the Power BI semantic model |
| BO-4 | The cost of the problem is visible | Paid amounts for readmissions and high utilizers, by condition, payer and facility | Refreshed monthly |
| BO-5 | People can trust the data | Every Silver and Gold table has quality checks, and the defects we deliberately inject get caught | At least 95% of injected defects detected |

---

## 2. Goals and non-goals

**Goals**

1. Combine Epic FHIR data, Clarity-style tables and payer claims into one consistent model.
2. Build Power BI reports for Patient 360, readmissions, utilization and cost, and care management.
3. Predict 30-day readmission at the time of discharge, and show what's driving each prediction.
4. Generate short patient summaries for care managers that are based only on the patient's actual records.
5. Follow the practices a real team would: medallion layers, data quality checks, access control, CI/CD and documentation.

**Not in this project**

- Anything that recommends treatment or runs inside a clinician's workflow.
- Real patient data, real Clarity access, or writing anything back to Epic.
- Real-time streaming. A daily batch with incremental loads is enough.
- An officially certified CMS measure. Our definitions follow CMS closely but aren't certified.

## 2a. Delivery phases

The platform is delivered in three phases, so there's a working, explainable version with dashboards first and more realism and intelligence added after.

| Phase | Goal | What's in it |
|---|---|---|
| **1. Working platform** | Data flowing end to end into dashboards, with transformations that are easy to follow | Epic FHIR sandbox extract; Synthea CSVs and reference tables loaded to Bronze as-is; Silver in SQL (types, deduplication, code mapping with the reference tables, quality checks); Gold star schema, KPIs, Patient 360 and a rule-based (LACE) care management worklist; Asset Bundle deployment; Power BI pages 1 to 4 |
| **2. Realism** | Data that behaves like a real health system | Realistic admission, readmission and ED rates; Clarity-style tables; detailed billing, denials and remittances; deliberate data quality defects and quarantine; patient matching across sources; history (SCD2); row-level security |
| **3. Intelligence** | Prediction and plain-language insight | Readmission model compared with LACE, explanations, fairness checks, monitoring; GenAI patient summaries with citations |

Requirement IDs by phase:

| Phase | Requirements |
|---|---|
| 1 | ING-01 to ING-06, SLV-01, SLV-02, SLV-04, SLV-05 (expectations only), SLV-06, SLV-08, GLD-01 to GLD-06, GLD-08 (LACE-based ranking), DQ-01, DQ-02, DQ-04, BI-01 to BI-07 (without AI summaries or denial analysis), OPS-01 to OPS-04, OPS-06 |
| 2 | ING-07, SHP-01 to SHP-09, SLV-03, SLV-05 (quarantine), SLV-07, DQ-03, DQ-05, DQ-06, BI-06 (denials), BI-09, OPS-05 |
| 3 | ING-08, GLD-07, GLD-09, ML-01 to ML-09, AI-01 to AI-08, BI-05 (AI summary panel), BI-08 |

**What Phase 1 looks like in the numbers.** Phase 1 uses Synthea's data as generated, plus code mappings. Synthea produces fewer unplanned hospital admissions and readmissions than a real health system (a readmission rate of about 4%), and its costs are lower than real hospital prices. The dashboards and KPIs work correctly on that data; the rates become realistic in Phase 2.

---

## 3. Who uses it

| Who | Role | What they need | Where they'll find it |
|---|---|---|---|
| Chief Medical Officer / VP of Quality | Owns readmission performance and penalties | Trends, and where the problem is concentrated | Executive Overview page |
| Care manager (RN) | Calls patients after discharge and coordinates follow-up | Who to call today, and why | Care Management worklist and patient summary |
| Primary care doctor / hospitalist | Treats the patient | A quick, reliable picture of recent history before a visit | Patient 360 page |
| Finance / revenue cycle analyst | Tracks cost, denials and payer performance | What's driving cost, denial patterns, payer mix | Utilization and Cost page |
| Data engineering | Builds and runs the platform | Pipelines that are reliable and easy to monitor | Pipelines, `ops` schema, CI |
| Privacy and compliance | HIPAA oversight | People only see what they need, and access is logged | Unity Catalog grants, masking, audit queries |

---

## 4. Business questions

Section 14 maps each question to its KPIs, tables and report page.

| ID | Question | Asked by |
|---|---|---|
| BQ-01 | What's our 30-day readmission rate, and how is it trending by month, facility, service line and condition? | Leadership |
| BQ-02 | Which conditions (heart failure, COPD, pneumonia, heart attack, sepsis, etc.) account for the most readmissions and readmission cost? | Leadership, Finance |
| BQ-03 | Which recently discharged patients are most at risk, and what's driving their risk? | Care managers |
| BQ-04 | What has happened with this patient over the past year: visits, diagnoses, labs, medications, claims? | Doctors, care managers |
| BQ-05 | Who are our high utilizers, and how much of our total cost do they account for? | Leadership, Finance |
| BQ-06 | How many ED visits do we see per 1,000 patients, and how many happen soon after a discharge? | Leadership |
| BQ-07 | What's the total cost and cost per member per month (PMPM) by payer, condition, facility and provider? | Finance |
| BQ-08 | What's our denial rate, and how much is denied, by payer and reason? | Finance |
| BQ-09 | How good is the risk model, and does it beat LACE? | Leadership, Data |
| BQ-10 | Can we trust today's data? Did the pipelines run and did the checks pass? | Data, Compliance |

---

## 5. Scope

| In scope | Out of scope |
|---|---|
| Sources: Epic FHIR sandbox, Synthea FHIR exports, and Clarity-style tables plus 837/835-style claims built from Synthea | Real Clarity or Caboodle, HL7v2 ADT feeds, real clearinghouse data |
| Adults (18+) for readmission analysis; all ages for utilization | Pediatric measures |
| Inpatient, ED, outpatient, office, urgent care, SNF, home and virtual visits | Detailed pharmacy (PBM) claims |
| Analysis window of 2021-09-01 to 2026-08-31 (5 years). Older history is kept only as flags like "had bypass surgery". | Trend analysis before 2021 |
| Daily batch with incremental loading | Streaming |
| Power BI Desktop reports saved as PBIP, published to the Service if a license is available (see section 15) | Embedded or public web reports |
| One readmission model, one patient summary use case, and optionally one claims anomaly view | Multiple ML services in production |

---

## 6. KPI definitions

Every KPI is calculated once in the Gold layer. Power BI measures use these results as-is rather than recalculating them.

### 6.1 Readmissions

We follow the CMS approach, simplified for this project.

| Term | What it means here |
|---|---|
| Index admission | An inpatient stay that ends during the reporting period, where the patient was 18 or older, went home alive, wasn't transferred to another hospital, and didn't leave against medical advice. Like the CMS hospital-wide measure, we also leave out stays for cancer treatment, stays with a primary psychiatric or substance use diagnosis (ICD-10-CM F codes), and short recovery stays right after surgery that are really part of the same hospitalization. The discharge also has to be at least 30 days before the end of the period so we can see the full follow-up window. |
| Readmission | An unplanned inpatient admission to any facility 1 to 30 days after the index discharge. |
| Planned admission | An admission for something scheduled, like a chemotherapy or radiation cycle, rehab, or an elective surgery such as a joint replacement. These don't count as readmissions. The list is kept in a small reference table, `ops.ref_planned_admission`, loosely based on the CMS Planned Readmission Algorithm. |
| Chained stays | A readmission can also be the index admission for a later readmission. |
| What doesn't count | ED visits and observation stays. We track them separately as post-discharge ED visits. |
| Readmission rate | Readmissions divided by index admissions. |
| Condition groups | Based on the principal ICD-10-CM diagnosis. We use the HRRP groups (heart attack, heart failure, pneumonia, COPD, bypass surgery, hip/knee replacement) and add sepsis and diabetes. |

### 6.2 Utilization and cost

| KPI | How it's calculated | Notes |
|---|---|---|
| Admissions | Number of inpatient stays with an admit date in the period | |
| Average length of stay (ALOS) | Total days in hospital divided by number of discharges | A same-day stay counts as 1 day |
| ED visits per 1,000 | ED visits divided by the average number of active patients, times 1,000, annualized | "Active" means the patient had any visit in the last 24 months |
| Post-discharge ED visits | ED visits within 1 to 30 days of an inpatient discharge that didn't lead to an admission | |
| High utilizer | In the past 12 months: 2 or more inpatient stays, or 4 or more ED visits | Checked monthly and at each discharge |
| Billed, allowed, paid, patient responsibility | Totals from `fact_claim_line`, matched to remittances | "Paid" is what the payer paid |
| PMPM paid | Total paid divided by member months | Member months come from coverage periods |
| Cost per patient | Total paid divided by the number of patients with a claim | |
| Denial rate | Denied claim lines divided by adjudicated (processed) claim lines, also shown by denied amount | Grouped by denial reason code (CARC) |
| Readmission cost | Amount paid on claims tied to readmission stays | |

### 6.3 Risk scores and model

| Metric | What it means |
|---|---|
| LACE score | The standard readmission score clinicians already use. It adds up points for Length of stay, Acuity (was it an emergency admission), Comorbidities (Charlson index), and ED visits in the last 6 months. This is the baseline our model has to beat. |
| Readmission probability | The model's calibrated prediction (0 to 1) at discharge |
| Risk tier | High is the top 10% of scored discharges, Medium is the next 20%, Low is everything else. The cut-offs are saved with each model version. |
| Model performance | AUROC, AUPRC, Brier score, calibration slope, and capture rate in the top 10% and 20% (the share of actual readmissions that land in those tiers), all on held-out data |

---

## 7. Functional requirements

Priorities: M = must have, S = should have, C = could have, W = won't do this time. "Done" means it's already built.

### 7.1 Ingestion and landing (ING)

| ID | Requirement | Priority |
|---|---|---|
| ING-01 | Pull patient FHIR R4 data from the Epic sandbox using backend service authentication, with paging, retries and a run summary | M (done) |
| ING-02 | Save FHIR data as NDJSON files, organized by `extract_date` and `run_id` | M (done) |
| ING-03 | Generate a repeatable Synthea population using a fixed seed, at 1k patients for development and 25k for the demo | M (1k done) |
| ING-04 | Upload files to `/Volumes/healthcare/landing/raw` without sending any secrets or unrelated local files | M (done) |
| ING-05 | Load all FHIR data into `bronze.fhir_resources` incrementally, processing each file only once, with lineage columns | M (done) |
| ING-06 | Load the Synthea CSV files and the reference lookup files into their own Bronze tables, keeping every column as text and adding lineage columns (Phase 2 adds Clarity-style and claims files the same way) | M |
| ING-07 | Simulate a claims file that arrives late and a file that gets sent twice, and make sure neither creates duplicates | S |
| ING-08 | Add an Epic Bulk FHIR `$export` client, if the sandbox allows it | C |

### 7.2 Making the data look like a real Epic shop (SHP), Phase 2

A first working version of these steps is kept on the `phase2-realism` branch.

This is Phase 2 and runs locally.

| ID | Requirement | Priority |
|---|---|---|
| SHP-01 | Build Clarity-style tables (`PATIENT`, `PAT_ENC`, `PAT_ENC_HSP`, `PAT_ENC_DX`, `PROBLEM_LIST`, `CLARITY_EDG`, `ORDER_PROC`, `ORDER_RESULTS`, `CLARITY_COMPONENT`, `IP_FLWSHT_MEAS`, `ORDER_MED`, `CLARITY_MEDICATION`, `ALLERGY`, `CLARITY_SER`, `CLARITY_DEP`, `CLARITY_EPM`, `COVERAGE`, `HSP_ACCOUNT`, `HSP_TRANSACTIONS`, `ARPB_TRANSACTIONS`, and the `ZC_` lookups) using Epic-style IDs like `PAT_ID`, `PAT_MRN_ID` and `PAT_ENC_CSN_ID` | Phase 2 |
| SHP-02 | Build payer-side tables: `CLAIM_HEADER` and `CLAIM_LINE` (like an 837), `REMITTANCE` (like an 835, with denial codes) and `MEMBER_ELIGIBILITY` | Phase 2 |
| SHP-03 | Map SNOMED codes to ICD-10-CM for diagnoses and to CPT/HCPCS for procedures. Add revenue codes, place of service, and a rule-based MS-DRG for inpatient stays. Keep and flag any codes we can't map. | Phase 2 |
| SHP-04 | Treat SNOMED "finding" and "situation" records (like employment status or social isolation) as social factors, not diagnoses | Phase 2 |
| SHP-05 | Add discharge disposition (home, home health, SNF, transfer, left against advice, died) and admission type (emergency, urgent, elective) to hospital stays | Phase 2 |
| SHP-06 | Make hospital use realistic. Flag planned admissions, add unplanned medical admissions so the admission rate is around 90 to 100 per 1,000 patients a year, then add unplanned readmissions and post-discharge ED visits that follow real risk factors: heart failure, COPD, pneumonia, heart attack, sepsis, kidney disease, many medications, past hospital use, social factors, abnormal labs, and no follow-up visit. All settings live in a config file, and each run writes a before-and-after calibration report. | Phase 2 |
| SHP-07 | Raise ED visits to around 350 to 450 per 1,000 patients a year, concentrated in a group of frequent users | Phase 2 |
| SHP-08 | Deliberately add data problems and record each one in a `defect_manifest`: duplicate MRNs, missing or invalid birth dates, visits dated in the future, discharge before admit, wrong lab units, claim lines with no claim, duplicate claims, unmapped codes, late files | Phase 2 |
| SHP-09 | The same seed and config always produce exactly the same output | Phase 2 |

### 7.3 Silver: clean and standardize (SLV)

| ID | Requirement | Priority |
|---|---|---|
| SLV-01 | Turn raw FHIR JSON into typed Silver tables: `patient`, `encounter`, `condition`, `observation`, `medication_request`, `procedure`, `allergy`, `immunization`, `document_reference`, `practitioner`, `organization`, `location` | M |
| SLV-02 | Clean up the tabular sources: proper dates, decimals and codes. In Phase 1 that's the Synthea CSVs, with ICD-10-CM and CPT added from the reference tables; in Phase 2 it's the Clarity-style and claims tables, including decoding `ZC_` values. | M |
| SLV-03 | Match patients across sources. `silver.patient_xref` links FHIR patient IDs, Clarity `PAT_ID` and MRN, and claims member IDs to a single `patient_key`. | M |
| SLV-04 | Remove duplicates using business keys with clear tie-break rules: most recently updated wins, and for clinical fields Clarity is preferred over FHIR, which is preferred over claims | M |
| SLV-05 | Run the data quality rules in section 9. Serious failures go to quarantine tables in `ops`. Minor issues are flagged in a `dq_flags` column. | M |
| SLV-06 | Standardize units for key labs (glucose and creatinine in mg/dL, HbA1c in %) and use LOINC as the common lab code | M |
| SLV-07 | Keep history of changes to patient demographics and insurance coverage (SCD Type 2) | S |
| SLV-08 | Keep the Epic sandbox patients in the same tables as Synthea patients, marked by `source_system` | M |

### 7.4 Gold: reporting model and data products (GLD)

| ID | Requirement | Priority |
|---|---|---|
| GLD-01 | Shared dimensions: `dim_patient`, `dim_provider`, `dim_facility`, `dim_department`, `dim_payer`, `dim_date`, `dim_diagnosis` (with ICD-10, CCSR category and HRRP group), `dim_procedure`, `dim_encounter_type` | M |
| GLD-02 | Fact tables: `fact_encounter` (one row per visit), `fact_diagnosis` (visit by diagnosis), `fact_lab_result`, `fact_medication_order`, `fact_procedure`, `fact_claim_line`, `fact_remittance`, `fact_member_month` | M |
| GLD-03 | `fact_index_admission`: one row per index admission, with readmission flag, days until readmission, planned flag, condition group, LACE score and paid amounts | M |
| GLD-04 | `patient_360`: one row per patient with current risk tier, last visit, visits and cost over the past 12 months, chronic conditions, number of active medications, recent abnormal labs, payer and high-utilizer flag | M |
| GLD-05 | `patient_timeline`: one row per clinical or financial event, used for the Patient 360 timeline and for the patient summaries | M |
| GLD-06 | Pre-summarized KPI tables by month, facility, payer and condition group, small enough to run well on the 2X-Small warehouse | M |
| GLD-07 | `ml_features_discharge`: model features calculated using only what was known on the discharge date | M |
| GLD-08 | `care_management_worklist`: patients discharged in the last 14 days, scored and ranked, with their top 3 risk drivers and a link to their summary | M |
| GLD-09 | `claims_provider_anomaly`: compare each provider's volume and cost per procedure against their peers | C |

### 7.5 Data quality and monitoring (DQ)

| ID | Requirement | Priority |
|---|---|---|
| DQ-01 | Quality checks (pipeline expectations) on every Bronze, Silver and Gold table | M |
| DQ-02 | Store results in `ops.dq_results`: rule, table, run, rows checked, rows failed, severity, pass or fail | M |
| DQ-03 | Compare what the checks caught against `defect_manifest` to measure how many injected problems were found, by type | M |
| DQ-04 | Row count checks between layers: landing to Bronze, Bronze to Silver (after quarantine), Silver to Gold | M (Bronze done) |
| DQ-05 | Gold should be refreshed within 24 hours of new files landing, with an email alert if a pipeline fails | S |
| DQ-06 | A data quality page in Power BI or a Databricks dashboard | S |

### 7.6 Power BI reports (BI)

| ID | Requirement | Priority |
|---|---|---|
| BI-01 | Save reports as PBIP (Power BI Project) so the report and model are version-controlled in `powerbi/` | M |
| BI-02 | Connect to the Databricks SQL warehouse. Use Import mode for summary data, and DirectQuery for Patient 360 details only if needed. | M |
| BI-03 | Build a star schema model on the Gold tables. DAX measures should use the Gold KPIs from section 6 rather than recalculating them. | M |
| BI-04 | Page 1, Executive Overview: cards for patients, admissions, readmission rate, ALOS, ED visits per 1,000, post-discharge ED visits, total paid, PMPM and number of high-risk patients; readmission trend against target; breakdown by condition; comparison across facilities and payers | M |
| BI-05 | Page 2, Patient 360: pick a patient and see a header (age, payer, risk tier and probability, chronic conditions), a timeline of events, tabs for diagnoses, labs (with abnormal flags), medications, procedures and claims, and the patient summary | M |
| BI-06 | Page 3, Utilization and Cost: admission and ED trends; cost by condition, payer, facility and provider; share of cost from high utilizers; denial rate and reasons | M |
| BI-07 | Page 4, Care Management: ranked worklist that can be filtered by risk tier, condition, discharge date and facility; top risk drivers; a follow-up status column (simulated) | M |
| BI-08 | Page 5, Model Performance: AUROC and AUPRC compared with LACE, calibration plot, capture rate by risk decile, feature importance, model version | S |
| BI-09 | Row-level security so a care manager only sees patients from their assigned facilities | S |
| BI-10 | Click through from any patient row to their Patient 360 page | M |
| BI-11 | Accessible design: color-blind-friendly colors, alt text on visuals, and never rely on color alone to show meaning | S |

### 7.7 Machine learning (ML)

| ID | Requirement | Priority |
|---|---|---|
| ML-01 | Target: whether each index admission was followed by an unplanned readmission within 30 days (section 6.1) | M |
| ML-02 | Features, all as of discharge: age, sex, payer type, length of stay, admission type, disposition, main condition group, Charlson and Elixhauser comorbidities, number of chronic conditions, inpatient and ED visits in the past 6 and 12 months, past readmissions, number of active medications (10+ counts as polypharmacy), high-risk medication classes, recent abnormal labs (sodium, creatinine, hemoglobin, BNP, HbA1c), vitals at discharge, social factors, days since last primary care visit, and amount paid in the past 12 months | M |
| ML-03 | Split by time: train on older discharges and test on newer ones. No random splits. | M |
| ML-04 | Compare against LACE and a logistic regression, then try gradient-boosted trees (LightGBM or XGBoost) | M |
| ML-05 | Track experiments in MLflow and register the model in Unity Catalog with its version, metrics, risk tier cut-offs and feature list | M |
| ML-06 | Use SHAP to explain each prediction. Save the top 5 drivers with a readable label, for example "3 ED visits in the last 6 months". | M |
| ML-07 | A batch scoring job writes to `gold.readmission_predictions`: discharge, probability, tier, drivers, model version and scoring time | M |
| ML-08 | Check fairness: compare AUROC and capture rate across sex, age group, race/ethnicity and payer type, and flag any AUROC gap bigger than 0.05 | S |
| ML-09 | Monitor for drift in scores over time and track real-world performance once outcomes are known | C |

### 7.8 GenAI (AI)

| ID | Requirement | Priority |
|---|---|---|
| AI-01 | Patient summary: pull the patient's events from `patient_timeline` and relevant parts of their notes, and write a 120 to 200 word summary of the past 12 months | M |
| AI-02 | Every fact in the summary has to point back to where it came from (visit ID or date). If it can't be backed up, it shouldn't be in the summary. | M |
| AI-03 | Turn the SHAP drivers and patient details into 3 to 5 plain-language bullet points that explain the risk score to a care manager | M |
| AI-04 | Search clinical notes (from Synthea DocumentReference) using a single vector index, since Free Edition allows only one, filtered by `patient_key` | M |
| AI-05 | Safety rules: no diagnoses or treatment advice; say "not enough information" instead of guessing; show a note that the summary is AI-generated and should be checked; don't show identifiers the viewer isn't allowed to see | M |
| AI-06 | Build a test set of 30 patients with hand-checked facts. Measure accuracy, whether sources are cited correctly, and how often it makes things up. The goal is zero unsupported clinical statements on the test set. | M |
| AI-07 | Generate summaries in batch for patients on the worklist and show them in Power BI; optionally allow on-demand summaries through a Databricks App | S / C |
| AI-08 | Let people ask questions about the KPIs in plain English using a Genie space | C |

### 7.9 Deployment and operations (OPS)

| ID | Requirement | Priority |
|---|---|---|
| OPS-01 | Define all Databricks resources (pipeline, jobs, model scoring, dashboards) in the Asset Bundle | M (started) |
| OPS-02 | One job that runs everything in order: Bronze, Silver and Gold pipeline, quality report, feature build, scoring, patient summaries | M |
| OPS-03 | GitHub Actions: run linting, unit tests and `bundle validate` on every change, and `bundle deploy` to dev when changes are merged to `main` | M |
| OPS-04 | Unit tests for code mappings, readmission logic, LACE scoring and data quality rules, using small test datasets | M |
| OPS-05 | A runbook covering how to rerun a failed job, reload a date range, rotate the Epic keys and add a new source | S |
| OPS-06 | Keep secrets (Epic private key, tokens) out of git and bundle files, and use Databricks secret scopes where needed | M |

---

## 8. Data requirements

### 8.1 Sources

| Source | Format | What's in it | Size (dev / demo) | Refresh | Status |
|---|---|---|---|---|---|
| Epic FHIR sandbox | NDJSON (R4) | Patient, Encounter, Condition, Observation, MedicationRequest, AllergyIntolerance, Immunization, Practitioner, Location, Organization | About 280 records | On demand | In Bronze |
| Synthea FHIR export | NDJSON (R4) | 21 resource types | 1.13M rows / about 28M | Each generated run | In Bronze (1k) |
| Clarity-style tables | One CSV per table | See SHP-01 | Known after Phase 2 | Each run, split by day | Phase 2 |
| Claims (837/835 style) | One CSV per table | Claim headers and lines, remittances, eligibility | About 1M lines / about 25M | Each run, including a late file | Phase 2 |
| Reference data | CSV files in git | ICD-10-CM, CCSR, HRRP groups, SNOMED mappings, CPT and revenue codes, denial codes, LACE and Charlson tables, planned admission list | Small | Versioned in git | Phase 2 |

### 8.2 Table grain and keys (Gold)

| Table | One row per | Key |
|---|---|---|
| `dim_patient` | Patient version (SCD2) | `patient_key` plus valid dates |
| `fact_encounter` | Visit | `encounter_key` (from CSN) |
| `fact_index_admission` | Index inpatient admission | `encounter_key` |
| `fact_claim_line` | Claim line | `claim_id`, `line_number` |
| `fact_member_month` | Patient, payer and month | All three together |
| `patient_360` | Patient (current) | `patient_key` |
| `readmission_predictions` | Discharge and model version | `encounter_key`, `model_version` |

### 8.3 How long we keep data

- Bronze is append-only and kept for the whole project, so we can always rebuild from it.
- Silver and Gold cover the analysis window in section 5. Anything older is kept only as flags, such as "had bypass surgery".

---

## 9. Data quality rules (starting list)

| ID | Rule | Layer | Severity | What happens |
|---|---|---|---|---|
| DQR-01 | Resource type and ID are present | Bronze | Critical | Counted, then dropped in Silver |
| DQR-02 | Birth date is valid, not in the future, and age is 120 or under | Silver | Critical | Quarantined |
| DQR-03 | Each MRN maps to only one active patient; duplicates are resolved by patient matching | Silver | Critical | Merged and logged |
| DQR-04 | Visit end is on or after the start, and no visit is dated after the extract date | Silver | Critical | Quarantined |
| DQR-05 | Every visit belongs to a patient that exists | Silver | Critical | Quarantined |
| DQR-06 | Lab values are numeric where they should be, and units are valid for that LOINC code | Silver | Warning | Flagged, and converted if possible |
| DQR-07 | Lab values are within a realistic range | Silver | Warning | Flagged |
| DQR-08 | Diagnosis codes map to a valid ICD-10-CM code | Silver | Warning | Flagged as unmapped |
| DQR-09 | Every claim line has a matching claim header and patient | Silver | Critical | Quarantined |
| DQR-10 | Duplicate claims (same patient, provider, date, CPT code and amount) | Silver | Warning | Flagged and left out of cost totals |
| DQR-11 | Paid is no more than allowed, allowed is no more than billed, and amounts aren't negative (except reversals) | Silver | Critical | Quarantined |
| DQR-12 | Every remittance matches a claim that was sent | Silver | Warning | Flagged as unmatched |
| DQR-13 | Number of index admissions is within 10% of the last run for the same population | Gold | Warning | Alert |
| DQR-14 | Readmission rate falls between 8% and 22% | Gold | Warning | Alert |
| DQR-15 | Every worklist row has a probability, a tier and at least one driver | Gold | Critical | Job fails |

---

## 10. Non-functional requirements

| Area | Requirement |
|---|---|
| Performance | A full refresh takes 30 minutes or less on the 1k dataset and 2 hours or less on 25k. A Power BI refresh finishes within 15 minutes, and report pages load within 5 seconds on the 2X-Small warehouse. |
| Cost and limits | Stay within Free Edition's daily compute limits. Develop on the 1k dataset and use 25k only for final builds. Load incrementally, don't leave compute running, and let the warehouse stop automatically. |
| Reliability | Rerunning a job never creates duplicates, failures send an alert, and data can be regenerated from the same seed. |
| Security and privacy | Handled as if the data were real patient data. Access is granted by role with the minimum needed. Names, SSN, address, phone and MRN are masked for non-clinical users. Care managers only see patients from their own facilities. No patient details in logs or prompts beyond what's needed. Secrets live in secret scopes. Access is audited through system tables. |
| HIPAA | `docs/HIPAA_considerations.md` explains how the design lines up with the HIPAA Security Rule (access control, audit, integrity, secure transfer), and makes clear the data is synthetic. |
| Governance | Every Silver and Gold table and column has a description. Lineage comes from Unity Catalog, and the data dictionary is generated from it. |
| Maintainability | Transformation logic lives in Python modules that can be tested. Code is linted. Key design decisions are written down in `docs/`. |
| Portability | The storage path and catalog are bundle variables, so moving from Free Edition to a paid Azure or AWS workspace doesn't require code changes. |
| Responsible AI | A model card and a summary evaluation report are committed. A person always reviews the output before acting on it. |

---

## 11. Access by role (Unity Catalog groups)

| Group | Bronze | Silver | Gold | Identifiers | Rows visible |
|---|---|---|---|---|---|
| `hc_data_engineers` | Read/write | Read/write | Read/write | Visible | All |
| `hc_clinical` (doctors, care managers) | None | None | Read | Visible | Care managers: their facilities only |
| `hc_executive` | None | None | Read (summaries) | Masked | All |
| `hc_finance` | None | None | Read | Masked | All |
| `hc_compliance` | Read (audit) | Read | Read | Visible | All |

Free Edition may only have one user, so some of these groups will be simulated. The grant SQL will still be written and committed.

---

## 12. Assumptions and constraints

1. All data is synthetic. We'll make it clinically reasonable in Phase 2, but it hasn't been validated by clinicians.
2. We're on Databricks Free Edition. That means serverless compute only, one active pipeline of each type, one 2X-Small SQL warehouse, one vector search endpoint, daily compute limits and limited internet access.
3. The Epic sandbox only has a handful of patients, and our app can't read clinical notes there (it returns 403). The Epic data shows the integration works; the volume comes from Synthea.
4. The SNOMED to ICD-10 and CPT mappings are built by hand for the codes Synthea uses. They aren't a complete licensed mapping.
5. Readmissions are measured using the health system's own data plus claims, so claims also capture readmissions at other hospitals.
6. The simulation's "today" is 2026-08-31.

## 13. Risks

| Risk | Impact | How we'll handle it |
|---|---|---|
| Synthetic readmissions are too weak, or so obviously injected that the model just learns our rule | The ML results won't be convincing | Add readmissions using random, multi-factor patterns with noise, leave some factors out of the injection, and document it openly |
| The model accidentally sees data from after discharge | Results look better than they really are | Build features as of the discharge date, and add a test that checks feature dates against discharge dates |
| We hit Free Edition's daily compute limit | Work stops for the rest of the day | Develop on 1k, load incrementally, and plan heavy runs |
| No Power BI license for publishing | Can't share reports online | Keep PBIP in git, and share screenshots or a short video from Desktop |
| The AI summary makes things up | People stop trusting it, or it's unsafe | Require sources, test against the evaluation set, and say "not enough information" when data is missing |
| Scope keeps growing | The project never finishes | Stick to "must have" items until Phase 8 |

---

## 14. Traceability

| Question | KPIs | Gold tables | Report page | Requirements |
|---|---|---|---|---|
| BQ-01 | Readmission rate, index admissions | `fact_index_admission`, KPI summary tables | Executive | SHP-06, GLD-03, BI-04 |
| BQ-02 | Readmissions and paid amount by condition | `fact_index_admission`, `dim_diagnosis`, `fact_claim_line` | Executive, Utilization and Cost | SHP-03, GLD-01, GLD-03, BI-04, BI-06 |
| BQ-03 | Probability, tier, drivers | `readmission_predictions`, `care_management_worklist` | Care Management | ML-01 to ML-07, GLD-08, AI-03, BI-07 |
| BQ-04 | None | `patient_360`, `patient_timeline` | Patient 360 | GLD-04, GLD-05, AI-01, AI-02, BI-05 |
| BQ-05 | High utilizer count, share of paid | `patient_360`, `fact_claim_line` | Utilization and Cost | GLD-04, BI-06 |
| BQ-06 | ED visits per 1,000, post-discharge ED visits | `fact_encounter` | Executive | SHP-07, GLD-02, BI-04 |
| BQ-07 | Paid, PMPM, cost per patient | `fact_claim_line`, `fact_member_month` | Utilization and Cost | SHP-02, GLD-02, BI-06 |
| BQ-08 | Denial rate, denied amount | `fact_remittance` | Utilization and Cost | SHP-02, GLD-02, BI-06 |
| BQ-09 | AUROC, capture rate vs LACE | Model metrics table | Model Performance | ML-03 to ML-05, BI-08 |
| BQ-10 | Quality check pass rate, freshness | `ops.dq_results` | Data Quality | DQ-01 to DQ-06 |

---

## 15. Decisions

Agreed on 2026-09-15.

| # | Question | Decision |
|---|---|---|
| D-1 | Power BI: Desktop only, or Pro/PPU for publishing, row-level security testing and scheduled refresh? | Build in Power BI Desktop and save as PBIP. Publish to the Service later if a license becomes available. |
| D-2 | Headline readmission number: all unplanned readmissions, or only the HRRP conditions? | Both. All unplanned readmissions is the headline number and the model target. HRRP conditions are shown as a breakdown. |
| D-3 | Demo size | 25k patients. We'll revisit once Silver and Gold are running on 1k. |
| D-4 | Risk tiers | Percentile tiers: top 10% High, next 20% Medium, the rest Low. This matches how many patients care managers can actually follow. |
| D-5 | LLM for summaries | First check whether Free Edition has Databricks Foundation Model APIs. If not, use an outside API such as Claude through a Databricks App. Keep the provider easy to switch. |
| D-6 | Analysis window | 2021-09-01 to 2026-08-31 |
| D-7 | Delivery approach | Three phases (section 2a). Phase 1 keeps transformations in SQL on Databricks and uses Synthea's data as generated. Realism work moves to Phase 2 and ML/GenAI to Phase 3. |

---|---|---|---|
| D-1 | Power BI: Desktop only, or Pro/PPU so we can publish, test row-level security and schedule refreshes? | Build in Desktop (PBIP) either way, and publish if a license is available | Narendar |
| D-2 | Headline readmission number: all unplanned readmissions, or only the HRRP conditions? | Both. Use all unplanned readmissions as the headline and model target, and show HRRP conditions as a breakdown. | Narendar |
| D-3 | Demo size: 25k patients or 50k+? | 25k, and revisit once Silver and Gold are running on 1k | Narendar |
| D-4 | Risk tiers: top 10% and next 20%, or a fixed probability cut-off? | Percentages, since they match how many patients care managers can actually handle | Narendar |
| D-5 | LLM for summaries: Databricks Foundation Model APIs (if Free Edition has them) or an outside API like Claude through a Databricks App? | Check what Free Edition offers first, and keep it easy to switch | Narendar |
| D-6 | Analysis window of 2021-09-01 to 2026-08-31? | Accept | Narendar |

---

## 16. When each phase is done

| Phase | Done when |
|---|---|
| 1: Working platform | Synthea CSVs and reference tables are in Bronze with row counts matching the files; Silver tables are typed, deduplicated and code-mapped, with quality expectations; Gold star schema, KPI tables, Patient 360 and the LACE-based worklist are built; KPIs match hand calculations for 5 patients; `bundle deploy` and the job run end to end; Power BI pages 1 to 4 are finished and every visual uses a KPI from section 6 |
| 2: Realism | Readmission rate 12% to 18% with no single condition group above 20% of readmissions; admissions and ED visits in realistic ranges; Clarity-style and claims tables in Bronze and Silver; injected defects logged in a manifest and at least 95% caught |
| 3: Intelligence | The model beats LACE on a time-based holdout (BO-2); predictions and explanations are in Gold; the summary evaluation meets AI-06; a model card is committed |

---|---|
| 2: Data shaping | All "must have" SHP tables are generated for 1k patients from a seed; at least 95% of condition rows map to ICD-10; readmission rate is 12% to 18% with no single condition group making up more than 20% of readmissions; the defect manifest exists; unit tests pass |
| 3b: Bronze CSV | All Clarity-style and claims tables are in Bronze, and row counts match the files exactly |
| 5: Silver and Gold | All "must have" GLD tables are built; quality results are written; at least 95% of injected defects are caught; KPIs match hand calculations for 5 patients |
| 6: Deployment | `bundle deploy` and the end-to-end job both succeed; CI passes on `main` |
| 7: Power BI | Pages 1 to 4 are finished in PBIP; every visual uses a KPI from section 6; pages load within 5 seconds |
| 8: AI | The model beats LACE on the time-based holdout (BO-2); predictions and SHAP drivers are in Gold; the summary evaluation meets AI-06; the model card is committed |

---

*Once this is signed off, the next step is Phase 2 data shaping (SHP-01 to SHP-09).*
