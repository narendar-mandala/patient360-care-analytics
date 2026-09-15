-- Bronze CSV reconciliation: row counts in Bronze vs the source files.
-- Expected counts come from the local files for run p1000_s42_massachusetts (header row excluded).
-- Every row in the result should show difference = 0.

WITH expected (table_name, expected_rows) AS (
  VALUES
    ('synthea_patients', 1144), ('synthea_organizations', 811), ('synthea_providers', 811), ('synthea_payers', 10),
    ('synthea_payer_transitions', 41216), ('synthea_encounters', 62199), ('synthea_conditions', 39178),
    ('synthea_procedures', 174594), ('synthea_observations', 762751), ('synthea_medications', 50379),
    ('synthea_immunizations', 16604), ('synthea_allergies', 1302), ('synthea_claims', 112578),
    ('synthea_claims_transactions', 1023970),
    ('ref_snomed_icd10cm_conditions', 295), ('ref_procedure_code_map', 254), ('ref_procedure_category_rules', 12),
    ('ref_immunization_cvx_cpt', 22), ('ref_payer_profile', 10), ('ref_lab_panels', 71), ('ref_lab_reference_ranges', 60),
    ('ref_charlson_weights', 17), ('ref_lace_points', 19), ('ref_planned_admission_rules', 19)
),
actual AS (
  SELECT 'synthea_patients' AS table_name, count(*) AS bronze_rows FROM healthcare.bronze.synthea_patients
  UNION ALL SELECT 'synthea_organizations', count(*) FROM healthcare.bronze.synthea_organizations
  UNION ALL SELECT 'synthea_providers', count(*) FROM healthcare.bronze.synthea_providers
  UNION ALL SELECT 'synthea_payers', count(*) FROM healthcare.bronze.synthea_payers
  UNION ALL SELECT 'synthea_payer_transitions', count(*) FROM healthcare.bronze.synthea_payer_transitions
  UNION ALL SELECT 'synthea_encounters', count(*) FROM healthcare.bronze.synthea_encounters
  UNION ALL SELECT 'synthea_conditions', count(*) FROM healthcare.bronze.synthea_conditions
  UNION ALL SELECT 'synthea_procedures', count(*) FROM healthcare.bronze.synthea_procedures
  UNION ALL SELECT 'synthea_observations', count(*) FROM healthcare.bronze.synthea_observations
  UNION ALL SELECT 'synthea_medications', count(*) FROM healthcare.bronze.synthea_medications
  UNION ALL SELECT 'synthea_immunizations', count(*) FROM healthcare.bronze.synthea_immunizations
  UNION ALL SELECT 'synthea_allergies', count(*) FROM healthcare.bronze.synthea_allergies
  UNION ALL SELECT 'synthea_claims', count(*) FROM healthcare.bronze.synthea_claims
  UNION ALL SELECT 'synthea_claims_transactions', count(*) FROM healthcare.bronze.synthea_claims_transactions
  UNION ALL SELECT 'ref_snomed_icd10cm_conditions', count(*) FROM healthcare.bronze.ref_snomed_icd10cm_conditions
  UNION ALL SELECT 'ref_procedure_code_map', count(*) FROM healthcare.bronze.ref_procedure_code_map
  UNION ALL SELECT 'ref_procedure_category_rules', count(*) FROM healthcare.bronze.ref_procedure_category_rules
  UNION ALL SELECT 'ref_immunization_cvx_cpt', count(*) FROM healthcare.bronze.ref_immunization_cvx_cpt
  UNION ALL SELECT 'ref_payer_profile', count(*) FROM healthcare.bronze.ref_payer_profile
  UNION ALL SELECT 'ref_lab_panels', count(*) FROM healthcare.bronze.ref_lab_panels
  UNION ALL SELECT 'ref_lab_reference_ranges', count(*) FROM healthcare.bronze.ref_lab_reference_ranges
  UNION ALL SELECT 'ref_charlson_weights', count(*) FROM healthcare.bronze.ref_charlson_weights
  UNION ALL SELECT 'ref_lace_points', count(*) FROM healthcare.bronze.ref_lace_points
  UNION ALL SELECT 'ref_planned_admission_rules', count(*) FROM healthcare.bronze.ref_planned_admission_rules
)
SELECT e.table_name, e.expected_rows, a.bronze_rows, a.bronze_rows - e.expected_rows AS difference
FROM expected e LEFT JOIN actual a USING (table_name)
ORDER BY abs(coalesce(a.bronze_rows, 0) - e.expected_rows) DESC, e.table_name;

-- Rows that didn't fit the columns (should be 0 in every table).
SELECT 'synthea_encounters' AS table_name, count_if(_rescued_data IS NOT NULL) AS rescued_rows FROM healthcare.bronze.synthea_encounters
UNION ALL SELECT 'synthea_observations', count_if(_rescued_data IS NOT NULL) FROM healthcare.bronze.synthea_observations
UNION ALL SELECT 'synthea_claims_transactions', count_if(_rescued_data IS NOT NULL) FROM healthcare.bronze.synthea_claims_transactions;
