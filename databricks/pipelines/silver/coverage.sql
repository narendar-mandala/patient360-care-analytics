-- Silver: coverage
-- One row per insurance coverage period for a patient (from Synthea's payer_transitions).
--
-- Transformations:
--   1. Build an id from patient, payer and start date, and remove duplicates.
--   2. Cast the start and end timestamps to dates.
--   3. Remove the digits Synthea appends to the policy owner's name.
--   4. Add the payer type through the payer's name and ref_payer_profile.
--
-- Checks (rows are kept; failures are counted):
--   has_patient, has_payer, end_not_before_start

CREATE OR REFRESH MATERIALIZED VIEW silver.coverage (
  CONSTRAINT has_patient EXPECT (patient_id IS NOT NULL),
  CONSTRAINT has_payer EXPECT (payer_id IS NOT NULL),
  CONSTRAINT end_not_before_start EXPECT (end_date IS NULL OR end_date >= start_date)
)
COMMENT 'One row per coverage period: patient, payer, member id, dates and policy owner'
AS
WITH coverage AS (
  SELECT
    sha2(concat_ws('|', PATIENT, PAYER, START_DATE), 256) AS coverage_id,
    *
  FROM bronze.synthea_payer_transitions
  QUALIFY row_number() OVER (PARTITION BY PATIENT, PAYER, START_DATE ORDER BY _ingested_at DESC) = 1
)

SELECT
  c.coverage_id,
  'synthea'                                            AS source_system,
  c.PATIENT                                            AS patient_id,
  c.MEMBERID                                           AS member_id,
  c.PAYER                                              AS payer_id,
  c.SECONDARY_PAYER                                    AS secondary_payer_id,
  to_date(try_cast(c.START_DATE AS TIMESTAMP))         AS start_date,
  to_date(try_cast(c.END_DATE AS TIMESTAMP))           AS end_date,
  coalesce(initcap(c.PLAN_OWNERSHIP), 'Unknown')       AS plan_ownership,
  regexp_replace(c.OWNER_NAME, '[0-9]+', '')           AS policy_owner_name,
  prof.payer_type,
  c._run_id                                            AS run_id,
  c._ingested_at                                       AS bronze_ingested_at
FROM coverage c
LEFT JOIN bronze.synthea_payers py ON py.Id = c.PAYER
LEFT JOIN bronze.ref_payer_profile prof ON prof.payer_name = py.NAME;
