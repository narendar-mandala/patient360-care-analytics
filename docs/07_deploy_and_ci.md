# 07 - Deployment, scheduling and CI

Everything in Databricks is defined as code in a **Databricks Asset Bundle**. Nothing is created by hand in the workspace UI, so the whole setup can be recreated from the repo.

## What the bundle contains

| File | Defines |
|---|---|
| `databricks.yml` | The bundle, its settings (catalog, landing folder, reporting period, SQL warehouse) and the `dev` target |
| `resources/healthcare_medallion.pipeline.yml` | The `healthcare-medallion` pipeline: every Bronze, Silver and Gold SQL file, serverless |
| `resources/healthcare_daily.job.yml` | The `healthcare-daily-refresh` job |

The workspace URL isn't in the repo. The Databricks CLI takes it from your login (`databricks auth login`) locally, or from the `DATABRICKS_HOST` secret in GitHub Actions.

## The daily job

```text
healthcare-daily-refresh   (6:00 AM America/New_York)
  1. refresh_pipeline   run healthcare-medallion: load new files, rebuild Silver and Gold
  2. data_checks        run databricks/validation/job_checks.sql on the SQL warehouse
```

`job_checks.sql` stops the run with a clear message if any check fails:

| Check | Fails when |
|---|---|
| Gold tables have data | Any key Gold table is empty |
| Silver matches Bronze | Silver has a different number of patients, encounters or claims than Bronze has unique records |
| No unexpected data quality failures | Any expectation failed in the latest pipeline update, other than the two known Synthea source-data issues listed in [05_silver.md](05_silver.md) |
| Readmission measure has results | No index admissions with complete follow-up |

A failed run sends an email to the user who deployed the bundle.

**Tested on 2026-09-15:** the job ran successfully (pipeline and checks, about 7 minutes). The quality check was also run with its list of known issues removed, and it failed as expected, naming both issues.

**Schedule in development mode:** the `dev` target uses development mode, which pauses schedules. Start the job with `databricks bundle run healthcare_daily`, or unpause the schedule on the job's page in the workspace.

## Commands

```bash
databricks bundle validate            # check the configuration
databricks bundle deploy              # create or update the pipeline and job
databricks bundle run healthcare_daily   # run the job now
databricks bundle summary             # links to the deployed resources
```

## CI with GitHub Actions

`.github/workflows/ci.yml` runs on every push and pull request:

| Job | What it does |
|---|---|
| Reference data checks | Runs `pytest reference`. Tests that need a local Synthea run are skipped; the rest check the lookup files against each other. |
| Databricks bundle | Validates the bundle. On pushes to `main`, it also deploys it, so the workspace always matches `main`. |

### One-time setup: repository secrets

The bundle job needs two secrets. Set them up once:

1. **Create a Databricks token.** In the workspace, click your profile picture (top right), then **Settings**, then **Developer**. Next to **Access tokens**, click **Manage**, then **Generate new token**. Enter a comment like `github-actions` and a lifetime (for example 90 days), click **Generate**, and copy the token. It's shown only once.
2. **Add the secrets in GitHub.** In the repository, go to **Settings > Secrets and variables > Actions > New repository secret** and add:
   - `DATABRICKS_HOST`: your workspace URL, like `https://dbc-xxxxxxxx-xxxx.cloud.databricks.com` (no trailing slash)
   - `DATABRICKS_TOKEN`: the token from step 1
3. **Run the workflow.** Push a commit, or go to **Actions > CI > Run workflow**.

The token acts as you, so deployments from GitHub update the same pipeline and job as deployments from your machine. When the token expires, generate a new one and update the secret.
