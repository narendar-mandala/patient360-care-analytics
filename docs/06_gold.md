# 06 - Gold layer

Gold is what Power BI reads: a star schema, KPI tables, and patient-level tables for Patient 360 and care management. Everything is SQL in `databricks/pipelines/gold/`, built from Silver.

## Reporting period

Gold reports on a fixed period set in `databricks.yml`, so results don't change depending on the day the pipeline runs:

| Setting | Value | Used for |
|---|---|---|
| `analysis_start_date` | 2021-09-01 | First month in the KPI tables and index admissions |
| `as_of_date` | 2026-08-31 | Last day of the period; "last 12 months", "last 90 days" and "30-day follow-up" all count back from here |

## Tables

### Dimensions (`dimensions.sql`)

| Table | One row per | Notes |
|---|---|---|
| `dim_date` | Day, 1900 to 2027 | `date_key` (yyyymmdd) joins to every fact; month, quarter and year columns; `is_in_analysis_period` |
| `dim_patient` | Patient | Age and age band on the as-of date (or at death); current payer from the coverage period that includes the as-of date |
| `dim_provider` | Clinician | |
| `dim_facility` | Organization | |
| `dim_payer` | Payer | Payer category (Medicare, Medicare Advantage, Medicaid, Dual Eligible, Commercial, Self-Pay) |
| `dim_diagnosis` | ICD-10-CM code | Description, condition group, `is_hrrp_condition` (AMI, HF, pneumonia, COPD), chronic flag, Charlson category |

### Facts (`facts_clinical.sql`)

| Table | One row per | Notes |
|---|---|---|
| `fact_encounter` | Visit or stay | Death certificate records left out. Length of stay for inpatient stays (a same-day stay counts as 1 day). `medical_cost`, `payer_paid`, `patient_responsibility`. |
| `fact_condition` | Diagnosis, symptom, history or pregnancy record | Social factors and administrative codes left out |
| `fact_procedure` | Procedure | Billing code and service category |
| `fact_lab_result` | Lab result | Value, reference range, abnormal flag, `is_abnormal` |
| `fact_medication` | Medication order | `pharmacy_cost`, `payer_paid`, `patient_responsibility` |
| `fact_claim` | Claim | Charges and payments summed from the claim's transactions; outstanding balance |
| `fact_member_month` | Patient per month of insurance coverage | Denominator for per-member-per-month. Self-pay months aren't counted. |

### Readmissions (`fact_index_admission.sql`)

One row per inpatient stay that counts toward the 30-day readmission measure (section 6.1 of the requirements). The SQL is laid out in the same steps:

1. **Inpatient stays.**
2. **Planned stays**, matched to `ref_planned_admission_rules` by a procedure done during the stay, the admission type or the reason.
3. **Index stays:**
   - patient 18 or older and alive at discharge
   - discharged inside the reporting period
   - not a stay for cancer treatment, recovery after surgery, or a primary psychiatric or substance use diagnosis
4. **Outcomes:**
   - *Readmission:* the first unplanned inpatient admission 1 to 30 days after discharge.
   - *Post-discharge ED visit:* an ED visit in that window that didn't lead to an admission.
   - `follow_up_complete` is true once 30 days have passed by the as-of date. Rates only use those rows.
5. **LACE score:** L (length of stay) + A (3 points if admitted through the ED) + C (Charlson score from conditions active at admission) + E (ED visits in the previous 6 months), with points from `ref_lace_points`.
6. **Risk tier (decision D-4):** the top 10% of LACE scores are High, the next 20% Medium, the rest Low.

Phase 1 limit: Synthea doesn't record discharge disposition, so transfers and against-medical-advice discharges can't be excluded yet.

### KPI tables (`kpis.sql`)

These hold **counts and sums only**. Power BI divides one Gold column by another, so a rate means the same thing on every page and at every level of detail.

| Table | Grain | Columns |
|---|---|---|
| `kpi_monthly` | Month, facility, payer category, condition group | `admissions`, `discharges`, `inpatient_days`, `ed_visits`, `index_admissions`, `readmissions`, `post_discharge_ed_visits`, `readmission_cost`, `medical_cost`, `payer_paid`, `patient_responsibility` |
| `kpi_active_patients_monthly` | Month | `active_patients`: alive and seen at least once in the previous 24 months. Summed across months, it gives patient-months. |

How the KPIs from the requirements come out of these:

| KPI | Calculation in Power BI |
|---|---|
| Readmission rate | `sum(readmissions) / sum(index_admissions)` |
| Average length of stay | `sum(inpatient_days) / sum(discharges)` |
| ED visits per 1,000 per year | `sum(ed_visits) * 12,000 / sum(active_patients)` |
| Post-discharge ED rate | `sum(post_discharge_ed_visits) / sum(index_admissions)` |
| PMPM paid | `sum(payer_paid) / count of fact_member_month rows` |
| Cost per patient | `sum(fact_encounter.payer_paid) / distinct patients with an encounter` |

### Patient 360 and care management (`patient_360.sql`)

| Table | One row per | Notes |
|---|---|---|
| `patient_360` | Patient | Last visit; visits, inpatient stays, ED visits, readmissions, medical cost and payer paid in the last 12 months; high-utilizer flag (2+ inpatient stays or 4+ ED visits); active chronic conditions; active medications; abnormal labs in the last 90 days and the latest one; latest LACE score and risk tier |
| `patient_timeline` | Event | Visits, diagnoses, procedures, medications, abnormal labs and vaccines in one list with `event_ts`, `event_category`, `description`, `code` and `amount` |
| `care_management_worklist` | Discharge in the last 14 days | Ranked by LACE score, with risk tier, the top 3 reasons behind the score in plain language, chronic conditions, active medications, high-utilizer flag and a follow-up status |

## Results on the dev run (as of 2026-08-31)

| Measure | Value |
|---|---|
| Admissions (Sep 2021 to Aug 2026) | 281 |
| Average length of stay | 5.05 days |
| ED visits | 848, or 172 per 1,000 patients per year |
| Index admissions with complete follow-up | 84 |
| 30-day readmissions | 3 (3.6%) |
| Post-discharge ED visits | 0 |
| Medical cost / payer paid | $71.6M / $53.7M |
| Member months | 55,698 (PMPM paid about $964) |
| High utilizers | 11 living patients |
| Risk tiers | 15 High (LACE 9 to 13, 13.3% readmitted), 13 Medium (LACE 7 to 8), 56 Low (LACE 1 to 6, 1.8% readmitted) |
| Care management worklist | 2 patients, led by an 82-year-old discharged with heart failure (LACE 11, High: Charlson score 6, admitted through the ED, 2-day stay) |

As expected in Phase 1, readmissions and post-discharge ED visits are low: Synthea generates very few unplanned return visits, so these numbers become realistic in Phase 2. Costs come from Synthea's claim costs, which are high for some patients, for example those on long-term dialysis.

Every fact joins to `dim_patient`, and every facility in the KPI table joins to `dim_facility`. Both Gold checks pass: LACE scores are between 0 and 19, and readmissions fall 1 to 30 days after discharge.
