-- Bronze: Synthea CSV files, loaded exactly as they arrive.
--
-- Every table follows the same pattern:
--   * read the table's folder in the landing Volume with Auto Loader (read_files in STREAM mode),
--     so each file is loaded once and new runs are picked up automatically
--   * keep every column as text (inferColumnTypes => false); types are set in Silver
--   * don't turn the run_id=... folder name into an extra column (partitionColumns => ''); we add _run_id ourselves
--   * add load details: which run and file the row came from, and when it was loaded
--   * _rescued_data catches any value that doesn't fit the expected columns
--   * one expectation per table: the key column must be present (rows are kept and counted if not)
--
-- ${landing_root} comes from the pipeline configuration (resources/healthcare_medallion.pipeline.yml).

CREATE OR REFRESH STREAMING TABLE synthea_patients (
  CONSTRAINT has_patient_id EXPECT (Id IS NOT NULL)
)
COMMENT 'Synthea patients.csv, as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/patients/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_organizations (
  CONSTRAINT has_organization_id EXPECT (Id IS NOT NULL)
)
COMMENT 'Synthea organizations.csv (hospitals, clinics and other facilities), as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/organizations/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_providers (
  CONSTRAINT has_provider_id EXPECT (Id IS NOT NULL)
)
COMMENT 'Synthea providers.csv, as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/providers/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_payers (
  CONSTRAINT has_payer_id EXPECT (Id IS NOT NULL)
)
COMMENT 'Synthea payers.csv, as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/payers/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_payer_transitions (
  CONSTRAINT has_patient EXPECT (PATIENT IS NOT NULL)
)
COMMENT 'Synthea payer_transitions.csv (insurance coverage periods), as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/payer_transitions/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_encounters (
  CONSTRAINT has_encounter_id EXPECT (Id IS NOT NULL)
)
COMMENT 'Synthea encounters.csv, as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/encounters/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_conditions (
  CONSTRAINT has_patient EXPECT (PATIENT IS NOT NULL)
)
COMMENT 'Synthea conditions.csv (SNOMED codes), as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/conditions/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_procedures (
  CONSTRAINT has_patient EXPECT (PATIENT IS NOT NULL)
)
COMMENT 'Synthea procedures.csv (SNOMED codes), as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/procedures/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_observations (
  CONSTRAINT has_patient EXPECT (PATIENT IS NOT NULL)
)
COMMENT 'Synthea observations.csv (labs, vitals, surveys; LOINC codes), as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/observations/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_medications (
  CONSTRAINT has_patient EXPECT (PATIENT IS NOT NULL)
)
COMMENT 'Synthea medications.csv (RxNorm codes), as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/medications/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_immunizations (
  CONSTRAINT has_patient EXPECT (PATIENT IS NOT NULL)
)
COMMENT 'Synthea immunizations.csv (CVX codes), as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/immunizations/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_allergies (
  CONSTRAINT has_patient EXPECT (PATIENT IS NOT NULL)
)
COMMENT 'Synthea allergies.csv, as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/allergies/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_claims (
  CONSTRAINT has_claim_id EXPECT (Id IS NOT NULL)
)
COMMENT 'Synthea claims.csv (one claim per encounter or medication), as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/claims/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');

CREATE OR REFRESH STREAMING TABLE synthea_claims_transactions (
  CONSTRAINT has_claim_id EXPECT (CLAIMID IS NOT NULL)
)
COMMENT 'Synthea claims_transactions.csv (charges, payments and transfers per claim line), as-is'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  regexp_extract(_metadata.file_path, 'run_id=([^/]+)', 1) AS _run_id,
  _metadata.file_path AS _source_file,
  _metadata.file_modification_time AS _source_file_modified_at,
  current_timestamp() AS _ingested_at
FROM STREAM read_files('${landing_root}/synthea_csv/claims_transactions/', format => 'csv', header => true, inferColumnTypes => false, partitionColumns => '');
