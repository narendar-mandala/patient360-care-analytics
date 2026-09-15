# Reference data

Small, hand-built lookup files. They get loaded into Databricks as tables and joined in the Silver layer to fill in codes and categories that Synthea doesn't provide, such as ICD-10-CM for diagnoses or CPT for procedures.

| File | What it's for |
|---|---|
| `snomed_icd10cm_conditions.csv` | Maps each Synthea condition, visit reason and claim diagnosis code (SNOMED) to an ICD-10-CM code. Also tags the condition group (HF, COPD, AMI and so on), Charlson category, whether it's chronic, and whether it's really a social factor such as housing or employment. |
| `procedure_code_map.csv` | Maps Synthea procedures to CPT, HCPCS or CDT (dental) codes, with a service category and whether the service is billed on its own. |
| `procedure_category_rules.csv` | Fallback for procedures not in the explicit map: the first matching description pattern (by priority) wins. |
| `immunization_cvx_cpt.csv` | Vaccine CVX code to CPT product code. |
| `payer_profile.csv` | Each payer's type (Medicare, Medicare Advantage, Medicaid, dual, commercial, self-pay) and financial class. |
| `lab_panels.csv` | Groups lab results (by LOINC) into panels such as a basic metabolic panel or CBC, with a short component name. |
| `lab_reference_ranges.csv` | Normal and critical ranges used to flag lab results as high, low or critical. |
| `charlson_weights.csv` | Charlson comorbidity index weights. |
| `lace_points.csv` | Point bands for the LACE readmission risk score. |
| `planned_admission_rules.csv` | What makes an admission "planned", so it isn't counted as a readmission. |

## How good are the mappings?

Measured on the 1k-patient dev run:

- **Conditions, visit reasons and claim diagnoses:** all 262 Synthea condition codes are mapped, plus 20 codes Synthea only uses as the reason for a visit (referrals, screenings, contraception care, food allergens) and 13 visit-type codes Synthea puts in the diagnosis slot of claims (checkups, urgent care, eye exams and so on). All 290 ICD-10-CM codes were checked against the CMS FY2026 (April 1, 2026) code file, and every one is a valid billable code. To check again:
  `python reference/validate_icd10.py <path to icd10cm_codes_2026.txt>`
- **Procedures:** 98.2% of procedure rows use the explicit map and 1.8% fall back to the category rules.
- Each mapping has a `map_quality` of `exact`, `close`, `approximate` or `none`, so it's always clear how much to trust it.

## Limits

- The mappings were built by hand for the codes Synthea actually produces. They aren't a full licensed crosswalk.
- CPT codes are used as identifiers only. No AMA CPT descriptions are included.
- CPT and CDT codes haven't been checked against an official list. ICD-10-CM codes have.

## Checks

`reference/test_reference_data.py` checks that the files are consistent with each other and cover every code in the Synthea data:

```bash
data_generation/.venv/Scripts/python -m pytest reference -q
```
