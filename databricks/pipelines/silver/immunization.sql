-- Silver: immunization
-- One row per vaccine dose given.
--
-- Transformations:
--   1. Build an id from patient, encounter, vaccine code and date, and remove duplicates.
--   2. Cast the timestamp and cost from text.
--   3. Add the CPT code for the vaccine from ref_immunization_cvx_cpt (Synthea provides CVX codes).
--
-- Checks (rows are kept; failures are counted):
--   has_patient, has_cpt_code

CREATE OR REFRESH MATERIALIZED VIEW silver.immunization (
  CONSTRAINT has_patient EXPECT (patient_id IS NOT NULL),
  CONSTRAINT has_cpt_code EXPECT (cpt_code IS NOT NULL)
)
COMMENT 'One row per vaccine dose: CVX and CPT codes, date and cost'
AS
WITH immunizations AS (
  SELECT
    sha2(concat_ws('|', PATIENT, ENCOUNTER, CODE, DATE), 256) AS immunization_id,
    *
  FROM bronze.synthea_immunizations
  QUALIFY row_number() OVER (PARTITION BY PATIENT, ENCOUNTER, CODE, DATE ORDER BY _ingested_at DESC) = 1
)

SELECT
  i.immunization_id,
  'synthea'                                            AS source_system,
  i.PATIENT                                            AS patient_id,
  i.ENCOUNTER                                          AS encounter_id,
  try_cast(i.DATE AS TIMESTAMP)                        AS administered_ts,
  to_date(try_cast(i.DATE AS TIMESTAMP))               AS administered_date,
  i.CODE                                               AS cvx_code,
  regexp_replace(i.DESCRIPTION, '\\s+', ' ')           AS description,
  ref.cpt_code,
  ref.short_name                                       AS vaccine_short_name,
  try_cast(i.BASE_COST AS DECIMAL(12, 2))              AS base_cost,
  i._run_id                                            AS run_id,
  i._ingested_at                                       AS bronze_ingested_at
FROM immunizations i
LEFT JOIN bronze.ref_immunization_cvx_cpt ref ON ref.cvx_code = i.CODE;
