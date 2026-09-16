# 09 - Project status and repository layout

Where the project stands, and where everything lives. The [README](../README.md) covers what the project is and why.

## Status

| Phase | Item | Status |
|---|---|---|
| **1** | Epic FHIR sandbox extract | Done (279 resources) |
| | Synthea population (1,000 patients, 10 years) | Done |
| | Reference tables for code mapping | Done (10 lookup files, ICD-10-CM checked against the CMS FY2026 file) |
| | Bronze: FHIR | Done (`bronze.fhir_resources`, 1.13M rows) |
| | Bronze: Synthea CSVs and reference tables | Done (14 CSV tables, 10 reference tables, all reconciled) |
| | Silver: typed, mapped, quality-checked tables | Done (14 tables, see [05_silver.md](05_silver.md)) |
| | Gold: star schema, KPIs, Patient 360 | Done (19 tables, see [06_gold.md](06_gold.md)) |
| | Deployment: Asset Bundle, daily job, CI | Done (see [07_deploy_and_ci.md](07_deploy_and_ci.md)) |
| | Power BI: 4 report pages | Done (see [08_power_bi.md](08_power_bi.md)) |
| **2** | Realistic readmission and ED rates, Clarity-style tables, detailed billing and denials, deliberate data quality defects, patient matching, history tracking, row-level security | Planned. Earlier prototype work is kept on the `phase2-realism` branch. |
| **3** | Readmission risk model, risk explanations, generated patient summaries | Planned |

## Results on the current data

Reporting period 2021-09-01 to 2026-08-31, as of 2026-08-31.

| Measure | Value |
|---|---|
| Admissions | 281 |
| Average length of stay | 5.05 days |
| ED visits | 848, or 172 per 1,000 patients per year |
| Index admissions with complete follow-up | 84 |
| 30-day readmissions | 3 (3.6%) |
| Medical cost / payer paid | $71.6M / $53.7M |
| Member months | 55,698 (about $964 per member per month) |
| Risk tiers | 15 High (13.3% readmitted), 13 Medium, 56 Low (1.8% readmitted) |

Readmissions are low because Synthea generates few unplanned return visits. Phase 2 addresses that; see [06_gold.md](06_gold.md) for the detail.

## Repository layout

```text
docs/                      design notes, setup guides, requirements
docs/images/               dashboard screenshots used in the README
ingestion/epic_fhir/       Epic sandbox OAuth client and FHIR extractor
data_generation/synthea/   Synthea population generation and profiling
reference/                 lookup CSVs (code mappings, payer types, risk tables) and their tests
scripts/                   upload to the Databricks Volume
databricks/pipelines/      bronze, silver and gold transformations
databricks/setup/          Unity Catalog objects
databricks/validation/     reconciliation queries and the daily job's data checks
resources/                 Databricks Asset Bundle resources (pipeline and daily job)
powerbi/                   Power BI project: semantic model (TMDL) and report (PBIR)
.github/workflows/         CI: reference data tests, bundle validate and deploy
data/                      local raw files (git-ignored)
```

## Pipeline files, in the order the data flows

| Layer | Files |
|---|---|
| Bronze | `fhir_resources.py`, `synthea_csv.sql`, `reference.sql` |
| Silver | `patient`, `encounter`, `condition`, `procedure`, `observation`, `medication`, `immunization`, `allergy`, `provider`, `organization`, `payer`, `coverage`, `claim`, `claim_transaction` |
| Gold | `dimensions.sql`, `facts_clinical.sql`, `fact_index_admission.sql`, `kpis.sql`, `patient_360.sql` |

All of them are listed in `resources/healthcare_medallion.pipeline.yml` and run as one pipeline.

## Settings that shape the results

Set in `databricks.yml` and passed into the SQL, so results don't change with the day the pipeline runs.

| Setting | Value | Used for |
|---|---|---|
| `catalog` | `healthcare` | Catalog holding all layers |
| `landing_root` | `/Volumes/healthcare/landing/raw` | Where source files land |
| `analysis_start_date` | 2021-09-01 | First month in the KPI tables and index admissions |
| `as_of_date` | 2026-08-31 | Last day of the period; "last 12 months", "last 90 days" and "30-day follow-up" count back from here |

## Known limitations in Phase 1

- Synthea produces few unplanned readmissions, so rates are lower than real life.
- Synthea doesn't record discharge disposition, so transfers and against-medical-advice discharges can't be excluded from the readmission measure yet.
- 3,272 claims have no billable principal diagnosis, because their only diagnoses are employment or education findings. Kept as a known warning rather than given an invented code.
- 27 medication records have a stop date before the start date, a Synthea quirk with renewals. Also kept as a warning.
- The Epic sandbox's clinical notes API returns 403 for this app, so no notes are extracted.
