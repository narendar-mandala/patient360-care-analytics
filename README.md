# Healthcare Patient 360 & Predictive Care Analytics Platform

An end-to-end lakehouse on Databricks. It brings Epic FHIR data and Synthea's synthetic health system data (clinical records and claims) into a Bronze/Silver/Gold model. Power BI dashboards on top cover:

- executive overview
- Patient 360
- utilization and cost
- care management

Machine learning and GenAI come in a later phase.

> **About the data.** Epic Clarity and production Epic FHIR endpoints need an Epic customer environment, so this project uses:
> - Epic's public **FHIR sandbox** for real API integration (backend OAuth and real R4 resources)
> - **Synthea**, a synthetic population generator, for volume. It exports FHIR bulk NDJSON and CSV files, including claims.
>
> No real patient data is used anywhere.

## How it fits together (Phase 1)

```text
Epic FHIR sandbox ─┐
Synthea FHIR ──────┼─► Databricks Volume ─► BRONZE ─► SILVER ─► GOLD ─► Power BI
Synthea CSVs ──────┤                        raw,       typed,     star schema,
Reference CSVs ────┘                        as-is      mapped,    KPIs,
                                                       checked    Patient 360
```

- **Local (Python):** extract from the Epic sandbox, generate the Synthea population, and upload files. Nothing else runs locally.
- **Bronze:** files loaded exactly as they arrive, plus lineage columns (source file, run id, load time).
- **Silver:** one SQL transformation per entity. Each casts types, removes duplicates, adds missing codes by joining the reference tables (ICD-10-CM, CPT, payer type and so on), and applies data quality checks.
- **Gold:** a star schema (patients, providers, facilities, payers, dates, diagnoses; encounters, claims, labs) plus KPI tables and a Patient 360 table for Power BI.

## Roadmap

| Phase | What | Status |
|---|---|---|
| **1** | Epic FHIR sandbox extract | Done |
| | Synthea population (1k patients) | Done |
| | Reference tables for code mapping | Done |
| | Bronze: FHIR | Done (`bronze.fhir_resources`, 1.13M rows) |
| | Bronze: Synthea CSVs and reference tables | Done (14 CSV tables, 10 reference tables, reconciled) |
| | Silver: typed, mapped, quality-checked tables | Done (14 tables, see docs/05_silver.md) |
| | Gold: star schema, KPIs, Patient 360 | Done (19 tables, see docs/06_gold.md) |
| | Deploy: Asset Bundle job and CI | Next |
| | Power BI: executive, Patient 360, utilization and cost, care management | |
| **2** | Realistic readmission and ED rates, Clarity-style tables, detailed billing and denials, deliberate data quality defects | Planned (earlier work kept on branch `phase2-realism`) |
| **3** | Readmission risk model, risk explanations, GenAI patient summaries | Planned |

## Repository layout

```text
docs/                      design notes, setup guides, requirements
ingestion/epic_fhir/       Epic sandbox OAuth client and FHIR extractor
data_generation/synthea/   Synthea population generation and profiling
reference/                 lookup CSVs (code mappings, payer types, risk tables) and their checks
scripts/                   upload to the Databricks Volume
databricks/                pipelines (bronze, silver, gold), setup SQL, validation SQL
resources/                 Databricks Asset Bundle resources
data/                      local raw files (git-ignored)
```

## Start here

1. [docs/01_data_sourcing_strategy.md](docs/01_data_sourcing_strategy.md): where the data comes from
2. [docs/02_epic_sandbox_setup.md](docs/02_epic_sandbox_setup.md): register an Epic sandbox app and pull FHIR data
3. [docs/03_databricks_landing_and_bronze.md](docs/03_databricks_landing_and_bronze.md): landing zone and Bronze on Databricks Free Edition
4. [docs/04_requirements.md](docs/04_requirements.md): problem statement, KPIs and what's in each phase
5. [docs/05_silver.md](docs/05_silver.md): the Silver pattern and tables
6. [docs/06_gold.md](docs/06_gold.md): Gold tables, KPI definitions and readmission logic
