# 03 - Databricks Free Edition: landing zone and Bronze

**Decision (2026-09-15):** Databricks Free Edition. There's no Azure subscription, so files land in a Unity Catalog **Volume** instead of ADLS Gen2. The pipeline code doesn't depend on where the files live, so moving to ADLS or S3 later only changes a path.

## Free Edition limits that shape the design

| Limit | What we do about it |
|---|---|
| Serverless compute only | SQL and Python only, with dependencies declared in the pipeline or job |
| One active Lakeflow pipeline per type | Bronze, Silver and Gold live in **one** declarative pipeline, writing to separate schemas |
| At most 5 job tasks running at once | A small job: load files, run the pipeline, run checks |
| One small (2X-Small) SQL warehouse | Gold tables are pre-summarized for Power BI, and most visuals use Import mode |
| Daily compute quotas (going over stops compute for the day) | Build on the 1k-patient dataset. Auto Loader only reads new files, so reruns are cheap. |
| Limited outbound internet | The Epic extract and Synthea generation run locally. Files reach Databricks through the CLI. |

Source: [Databricks Free Edition limitations](https://docs.databricks.com/aws/en/getting-started/free-edition-limitations)

## Unity Catalog layout

```text
catalog: healthcare
├── landing        schema holding the raw Volume
│   └── raw        VOLUME  /Volumes/healthcare/landing/raw/
│         epic_fhir/extract_date=.../run_id=.../<Resource>.ndjson
│         synthea_fhir/run_id=.../<Resource>.ndjson
│         synthea_csv/<table>/run_id=.../<table>.csv
│         reference/<lookup>/<lookup>.csv
├── bronze         raw records plus lineage columns
├── silver         typed, deduplicated, code-mapped, quality-checked
├── gold           star schema, KPI tables, Patient 360
└── ops            data quality results (later)
```

## Bronze tables

Records stay exactly as they arrive. Only lineage columns are added.

| Table | Source files | Notes |
|---|---|---|
| `bronze.fhir_resources` | every `*.ndjson` under `epic_fhir` and `synthea_fhir` | One table for all FHIR resource types, with `resource_type`, `resource_id` and the raw JSON. Code: `databricks/pipelines/bronze/fhir_resources.py`. |
| `bronze.synthea_<table>` | `synthea_csv/<table>/run_id=.../<table>.csv` | One streaming table per Synthea CSV (patients, encounters, conditions, procedures, observations, medications, immunizations, allergies, providers, organizations, payers, payer_transitions, claims, claims_transactions). All columns are text; Silver sets the types. Code: `databricks/pipelines/bronze/synthea_csv.sql`. |
| `bronze.ref_<lookup>` | `reference/<lookup>/<lookup>.csv` | The lookup files from `reference/`, as text. They're materialized views because the files get replaced rather than added to, so each run re-reads the current file. Code: `databricks/pipelines/bronze/reference.sql`. |

Lineage columns:

| Table | Columns |
|---|---|
| `fhir_resources` | `source_system` (`epic_fhir_sandbox` or `synthea`), `source_file`, `source_file_modified_at`, `run_id`, `extract_date`, `ingested_at` |
| `synthea_<table>` | `_run_id`, `_source_file`, `_source_file_modified_at`, `_ingested_at`, and `_rescued_data` for any value that didn't fit the columns |
| `ref_<lookup>` | `_source_file` |

The FHIR and CSV tables use **Auto Loader**, so each file is loaded exactly once and new runs are picked up automatically. Each CSV table also has one expectation: its key column (`Id`, `PATIENT` or `CLAIMID`) must be present. Rows that fail are kept and counted in the pipeline's quality metrics.

## Uploading files and running the pipeline

`scripts/upload_to_volume.ps1` copies local files into the Volume. From the repo root:

```powershell
.\scripts\upload_to_volume.ps1 -Source epic_fhir
.\scripts\upload_to_volume.ps1 -Source synthea_fhir -RunId p1000_s42_massachusetts
.\scripts\upload_to_volume.ps1 -Source synthea_csv -RunId p1000_s42_massachusetts
.\scripts\upload_to_volume.ps1 -Source reference
databricks bundle deploy
databricks bundle run healthcare_medallion
```

## Checks

| Check | File | Result on the dev run (2026-09-15) |
|---|---|---|
| FHIR counts by source and resource type | `databricks/validation/bronze_fhir_reconciliation.sql` | 1,126,984 rows, matching the files |
| Row counts for every CSV and reference table against the files, plus rescued rows | `databricks/validation/bronze_csv_reconciliation.sql` | All 24 tables match exactly (2.29 million rows), no rescued rows, no missing keys |

## Deployment

Everything is defined in a **Databricks Asset Bundle** (`databricks.yml` and `resources/`), so the pipeline and jobs are deployed from code with `databricks bundle deploy`.
