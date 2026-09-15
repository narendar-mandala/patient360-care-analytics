-- Silver: medication
-- One row per medication order (prescription), with its RxNorm code, cost and the reason it was prescribed.
--
-- Transformations:
--   1. Build an id from patient, encounter, code, start and stop, and remove duplicates.
--      (The stop time is part of the id: Synthea sometimes records the same drug twice in one visit
--      with different stop times.)
--   2. Cast timestamps, counts and costs from text.
--   3. is_active = the order has no stop time.
--   4. Add the ICD-10-CM code for the reason, when there is one.
--
-- Checks (rows are kept; failures are counted):
--   has_patient, stop_not_before_start, cost_not_negative

CREATE OR REFRESH MATERIALIZED VIEW silver.medication (
  CONSTRAINT has_patient EXPECT (patient_id IS NOT NULL),
  CONSTRAINT stop_not_before_start EXPECT (stop_ts IS NULL OR stop_ts >= start_ts),
  CONSTRAINT cost_not_negative EXPECT (total_cost IS NULL OR total_cost >= 0)
)
COMMENT 'One row per medication order: RxNorm code, dates, dispenses, costs and reason'
AS
WITH medications AS (
  SELECT
    sha2(concat_ws('|', PATIENT, ENCOUNTER, CODE, START, coalesce(STOP, '')), 256) AS medication_order_id,
    *
  FROM bronze.synthea_medications
  QUALIFY row_number() OVER (PARTITION BY PATIENT, ENCOUNTER, CODE, START, STOP ORDER BY _ingested_at DESC) = 1
)

SELECT
  m.medication_order_id,
  'synthea'                                            AS source_system,
  m.PATIENT                                            AS patient_id,
  m.ENCOUNTER                                          AS encounter_id,
  m.PAYER                                              AS payer_id,
  try_cast(m.START AS TIMESTAMP)                       AS start_ts,
  try_cast(m.STOP AS TIMESTAMP)                        AS stop_ts,
  m.STOP IS NULL                                       AS is_active,

  m.CODE                                               AS rxnorm_code,
  m.DESCRIPTION                                        AS description,
  try_cast(m.DISPENSES AS INT)                         AS dispenses,

  try_cast(m.BASE_COST AS DECIMAL(12, 2))              AS base_cost_per_dispense,
  try_cast(m.PAYER_COVERAGE AS DECIMAL(12, 2))         AS payer_coverage,
  try_cast(m.TOTALCOST AS DECIMAL(12, 2))              AS total_cost,

  m.REASONCODE                                         AS reason_snomed_code,
  regexp_replace(m.REASONDESCRIPTION, '\\s*\\([^)]*\\)$', '') AS reason_description,
  reason.icd10cm_code                                  AS reason_icd10cm_code,
  reason.cohort                                        AS reason_condition_group,

  m._run_id                                            AS run_id,
  m._ingested_at                                       AS bronze_ingested_at
FROM medications m
LEFT JOIN bronze.ref_snomed_icd10cm_conditions reason ON reason.snomed_code = m.REASONCODE;
