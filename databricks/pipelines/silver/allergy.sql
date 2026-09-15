-- Silver: allergy
-- One row per allergy or intolerance recorded for a patient.
--
-- Transformations:
--   1. Build an id from patient, encounter, allergen code and start date, and remove duplicates.
--   2. Cast dates from text; is_active = no stop date.
--   3. Keep up to two reactions with their severity, and add the most severe one (highest_severity).
--   4. Tidy descriptions (drop the "(substance)" style suffix) and capitalize categories.
--
-- Checks (rows are kept; failures are counted):
--   has_patient, known_severity

CREATE OR REFRESH MATERIALIZED VIEW silver.allergy (
  CONSTRAINT has_patient EXPECT (patient_id IS NOT NULL),
  CONSTRAINT known_severity EXPECT (highest_severity IS NULL OR highest_severity IN ('Mild', 'Moderate', 'Severe'))
)
COMMENT 'One row per allergy: allergen, category, reactions and severity'
AS
WITH allergies AS (
  SELECT
    sha2(concat_ws('|', PATIENT, ENCOUNTER, CODE, START), 256) AS allergy_id,
    *
  FROM bronze.synthea_allergies
  QUALIFY row_number() OVER (PARTITION BY PATIENT, ENCOUNTER, CODE, START ORDER BY _ingested_at DESC) = 1
)

SELECT
  a.allergy_id,
  'synthea'                                            AS source_system,
  a.PATIENT                                            AS patient_id,
  a.ENCOUNTER                                          AS encounter_id,
  try_cast(a.START AS DATE)                            AS start_date,
  try_cast(a.STOP AS DATE)                             AS stop_date,
  a.STOP IS NULL                                       AS is_active,

  a.CODE                                               AS allergen_code,
  a.SYSTEM                                             AS allergen_code_system,
  regexp_replace(a.DESCRIPTION, '\\s*\\([^)]*\\)$', '') AS allergen,
  initcap(a.TYPE)                                      AS allergy_type,
  initcap(a.CATEGORY)                                  AS allergy_category,

  regexp_replace(a.DESCRIPTION1, '\\s*\\([^)]*\\)$', '') AS reaction_1,
  initcap(a.SEVERITY1)                                 AS reaction_1_severity,
  regexp_replace(a.DESCRIPTION2, '\\s*\\([^)]*\\)$', '') AS reaction_2,
  initcap(a.SEVERITY2)                                 AS reaction_2_severity,
  CASE
    WHEN 'SEVERE' IN (a.SEVERITY1, a.SEVERITY2) THEN 'Severe'
    WHEN 'MODERATE' IN (a.SEVERITY1, a.SEVERITY2) THEN 'Moderate'
    WHEN 'MILD' IN (a.SEVERITY1, a.SEVERITY2) THEN 'Mild'
  END                                                  AS highest_severity,

  a._run_id                                            AS run_id,
  a._ingested_at                                       AS bronze_ingested_at
FROM allergies a;
