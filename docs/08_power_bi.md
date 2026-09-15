# 08 - Power BI report

The report lives in `powerbi/` as a **Power BI Project** (PBIP). Instead of one binary `.pbix` file, the model and the report are saved as text files, so every change shows up in git like any other code.

```text
powerbi/
  Patient360.pbip                       open this in Power BI Desktop
  Patient360.SemanticModel/definition/  the model (TMDL)
    expressions.tmdl                    connection parameters
    relationships.tmdl                  joins between tables
    tables/*.tmdl                       one file per Gold table, plus _Measures
  Patient360.Report/definition/pages/   one folder per page, one folder per visual
  Patient360.Report/StaticResources/    report theme
```

## Connect to Databricks

The model imports the Gold tables from the SQL warehouse with the Databricks connector. The warehouse details are two parameters in `expressions.tmdl`, and the repo only has placeholders.

1. **Get the connection details.** In Databricks, go to **SQL Warehouses > Serverless Starter Warehouse > Connection details** and copy the **Server hostname** and **HTTP path**.
2. **Stop git from tracking your local values**, so they don't get committed by accident:
   ```bash
   git update-index --skip-worktree powerbi/Patient360.SemanticModel/definition/expressions.tmdl
   ```
3. **Enter the values.** Open `powerbi/Patient360.pbip`. Go to **Home > Transform data > Edit parameters**, paste the hostname and HTTP path, and click **OK**.
4. **Sign in.** When Power BI asks for Databricks credentials, pick **Personal Access Token**. Create one in Databricks under **Settings > Developer > Access tokens** with the **BI Tools** scope, and paste it in the dialog. (The **Azure Active Directory** option only works for Azure Databricks. On AWS it fails with a 404.)
5. **Refresh.** Click **Home > Refresh**. The import takes a few minutes on the 2X-Small warehouse.

If Desktop says the project needs a preview feature, turn on **File > Options and settings > Options > Preview features > Power BI Project (.pbip) save option**, **Store semantic model using TMDL format** and **Store reports using enhanced metadata format (PBIR)**, then restart Desktop.

## Model

- **Import mode**, one query per Gold table. Every query follows the same steps: catalog `healthcare`, schema `gold`, then the table. No transformations happen in Power Query; all the logic stays in the Gold SQL.
- **Star schema.** Facts join to dimensions (many-to-one, filtering from the dimension to the fact). `dim_date` joins on the date keys (`start_date_key`, `discharge_date_key`, `month_date_key` and so on).
- **Measures** are all in the `_Measures` table, grouped in folders. They only add up or divide Gold columns, as described in [06_gold.md](06_gold.md).

| Folder | Measures |
|---|---|
| Utilization | Admissions, Discharges, Inpatient Days, Average Length of Stay, ED Visits, Active Patient Months, ED Visits per 1,000, Patients Seen, High Utilizers |
| Readmissions | Index Admissions, Readmissions, Readmission Rate, Readmission Rate Benchmark, Post-Discharge ED Visits, Post-Discharge ED Rate, Readmission Cost |
| Cost | Medical Cost, Payer Paid, Patient Responsibility, Member Months, PMPM Paid, Encounter Payer Paid, Cost per Patient, High Utilizer Share of Cost |
| Care Management | High-Risk Patients, Worklist Patients, Scored Discharges, Readmission Rate for Scored Discharges |

The benchmark is a fixed 14%, roughly the national 30-day all-cause readmission rate, shown only for comparison.

## Look and feel

The report uses a dark, Windows 11 style theme based on the Metricalist "Power BI Windows 11 Theme": dark grey page, rounded tiles, blue palette and Segoe UI fonts. It's stored with the report in `StaticResources/RegisteredResources/Windows11DarkTheme.json`, with two changes from the original: larger KPI card values (22pt) and dark gridlines so charts stay readable on the dark background. To change the look, edit that file or pick another theme under **View > Themes**.

## Pages

| Page | Question it answers | What's on it |
|---|---|---|
| **Executive Overview** | How are we doing overall? | Year, payer category and condition group slicers. Cards for admissions, readmission rate, average length of stay, ED visits per 1,000, post-discharge ED rate, payer paid, PMPM paid and high-risk patients. Readmission rate by quarter against the benchmark, admissions and readmissions by condition group, admissions by facility, payer paid by payer category. |
| **Patient 360** | What's going on with this patient? | Pick one patient. Summary (age, payer, risk tier, LACE, 12-month visits and cost), chronic conditions, full timeline (newest first), diagnoses, lab results and medications. |
| **Utilization and Cost** | Where does the money go? | Cost cards, including high utilizers' share of cost. Admissions and ED visits by month. Cost by condition group, payer category, facility and provider. |
| **Care Management** | Who should we call today? | Worklist of patients discharged in the last 14 days, ranked by LACE, with the reasons behind each score. Readmission rate by risk tier, and every index stay with its outcome. |

## Things to know

- Executive Overview and Utilization and Cost have a hidden page filter, `dim_date[is_in_analysis_period] = true`, so trends start in September 2021. `dim_date` itself goes back to 1900 for birth dates.
- `patient_360` and `care_management_worklist` are snapshots as of the reporting date (2026-08-31), so the year slicer doesn't change them.
- ED visits per 1,000 uses active patients per month as the denominator, which has no payer or facility breakdown. With a payer category selected, the numerator is filtered but the denominator isn't.
- Readmission numbers are low in Phase 1 (3 readmissions from 84 index stays), so the quarterly line sits at 0% except for the quarters with a readmission. See [06_gold.md](06_gold.md).
