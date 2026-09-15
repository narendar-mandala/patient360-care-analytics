-- Bronze: reference (lookup) tables from reference/*.csv.
--
-- These are small files that get replaced, not appended to, so they're materialized views:
-- every pipeline update re-reads the current file. Columns stay as text; Silver casts them.

CREATE OR REFRESH MATERIALIZED VIEW ref_snomed_icd10cm_conditions
COMMENT 'SNOMED condition code to ICD-10-CM, with condition group, Charlson category and social-factor tags'
AS SELECT *, _metadata.file_path AS _source_file
FROM read_files('${landing_root}/reference/snomed_icd10cm_conditions/', format => 'csv', header => true, inferColumnTypes => false);

CREATE OR REFRESH MATERIALIZED VIEW ref_procedure_code_map
COMMENT 'SNOMED procedure code to CPT, HCPCS or CDT'
AS SELECT *, _metadata.file_path AS _source_file
FROM read_files('${landing_root}/reference/procedure_code_map/', format => 'csv', header => true, inferColumnTypes => false);

CREATE OR REFRESH MATERIALIZED VIEW ref_procedure_category_rules
COMMENT 'Fallback billing category for procedures not in the explicit map, matched on description'
AS SELECT *, _metadata.file_path AS _source_file
FROM read_files('${landing_root}/reference/procedure_category_rules/', format => 'csv', header => true, inferColumnTypes => false);

CREATE OR REFRESH MATERIALIZED VIEW ref_immunization_cvx_cpt
COMMENT 'Vaccine CVX code to CPT code'
AS SELECT *, _metadata.file_path AS _source_file
FROM read_files('${landing_root}/reference/immunization_cvx_cpt/', format => 'csv', header => true, inferColumnTypes => false);

CREATE OR REFRESH MATERIALIZED VIEW ref_payer_profile
COMMENT 'Payer type and financial class for each Synthea payer'
AS SELECT *, _metadata.file_path AS _source_file
FROM read_files('${landing_root}/reference/payer_profile/', format => 'csv', header => true, inferColumnTypes => false);

CREATE OR REFRESH MATERIALIZED VIEW ref_lab_panels
COMMENT 'Lab LOINC code to panel (for example basic metabolic panel, CBC)'
AS SELECT *, _metadata.file_path AS _source_file
FROM read_files('${landing_root}/reference/lab_panels/', format => 'csv', header => true, inferColumnTypes => false);

CREATE OR REFRESH MATERIALIZED VIEW ref_lab_reference_ranges
COMMENT 'Normal and critical ranges for flagging lab results'
AS SELECT *, _metadata.file_path AS _source_file
FROM read_files('${landing_root}/reference/lab_reference_ranges/', format => 'csv', header => true, inferColumnTypes => false);

CREATE OR REFRESH MATERIALIZED VIEW ref_charlson_weights
COMMENT 'Charlson comorbidity index weights'
AS SELECT *, _metadata.file_path AS _source_file
FROM read_files('${landing_root}/reference/charlson_weights/', format => 'csv', header => true, inferColumnTypes => false);

CREATE OR REFRESH MATERIALIZED VIEW ref_lace_points
COMMENT 'LACE readmission score point bands'
AS SELECT *, _metadata.file_path AS _source_file
FROM read_files('${landing_root}/reference/lace_points/', format => 'csv', header => true, inferColumnTypes => false);

CREATE OR REFRESH MATERIALIZED VIEW ref_planned_admission_rules
COMMENT 'Rules for admissions that are planned and so not counted as readmissions'
AS SELECT *, _metadata.file_path AS _source_file
FROM read_files('${landing_root}/reference/planned_admission_rules/', format => 'csv', header => true, inferColumnTypes => false);
