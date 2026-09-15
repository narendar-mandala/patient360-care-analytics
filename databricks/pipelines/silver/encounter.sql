-- Silver: encounter
-- One row per visit or hospital stay, from Synthea (CSV) and the Epic FHIR sandbox.
--
-- Transformations:
--   1. Keep the latest copy of each encounter.
--   2. Cast timestamps and costs from text.
--   3. Group encounter classes into care settings used by the reports
--      (Inpatient, Emergency, Urgent Care, Outpatient, Virtual, Post-Acute).
--   4. Add the ICD-10-CM code for the reason for the visit, using the reference mapping
--      (Synthea only provides SNOMED codes).
--   5. Flag Synthea's "Death Certification" records, which are paperwork, not patient visits.
--   6. Epic sandbox encounters: read fields out of the FHIR Encounter JSON. Epic uses its own
--      class names ("HOV", "Support OP Encounter", "Preadmission"), which all count as outpatient
--      unless they say inpatient or emergency.
--
-- Checks (rows are kept; failures are counted):
--   has_patient, end_not_before_start, known_encounter_class, reason_code_mapped

CREATE OR REFRESH MATERIALIZED VIEW silver.encounter (
  CONSTRAINT has_patient EXPECT (patient_id IS NOT NULL),
  CONSTRAINT end_not_before_start EXPECT (end_ts IS NULL OR end_ts >= start_ts),
  CONSTRAINT known_encounter_class EXPECT (care_setting IS NOT NULL),
  CONSTRAINT reason_code_mapped EXPECT (reason_snomed_code IS NULL OR reason_icd10cm_code IS NOT NULL OR reason_condition_class <> 'diagnosis')
)
COMMENT 'One row per encounter: dates, setting, facility, provider, payer, reason (SNOMED and ICD-10-CM) and cost'
AS
WITH synthea AS (
  SELECT *
  FROM bronze.synthea_encounters
  QUALIFY row_number() OVER (PARTITION BY Id ORDER BY _ingested_at DESC) = 1
),

epic AS (
  SELECT *
  FROM bronze.fhir_resources
  WHERE source_system = 'epic_fhir_sandbox' AND resource_type = 'Encounter'
  QUALIFY row_number() OVER (PARTITION BY resource_id ORDER BY ingested_at DESC) = 1
)

SELECT
  e.Id                                                 AS encounter_id,
  'synthea'                                            AS source_system,
  e.PATIENT                                            AS patient_id,
  e.ORGANIZATION                                       AS organization_id,
  e.PROVIDER                                           AS provider_id,
  e.PAYER                                              AS payer_id,

  e.ENCOUNTERCLASS                                     AS encounter_class,
  CASE e.ENCOUNTERCLASS
    WHEN 'inpatient'  THEN 'Inpatient'
    WHEN 'emergency'  THEN 'Emergency'
    WHEN 'urgentcare' THEN 'Urgent Care'
    WHEN 'ambulatory' THEN 'Outpatient'
    WHEN 'outpatient' THEN 'Outpatient'
    WHEN 'wellness'   THEN 'Outpatient'
    WHEN 'virtual'    THEN 'Virtual'
    WHEN 'snf'        THEN 'Post-Acute'
    WHEN 'hospice'    THEN 'Post-Acute'
    WHEN 'home'       THEN 'Post-Acute'
  END                                                  AS care_setting,
  e.CODE                                               AS encounter_type_code,
  regexp_replace(e.DESCRIPTION, '\\s*\\([^)]*\\)$', '') AS encounter_type,
  'finished'                                           AS encounter_status,
  e.CODE = '308646001'                                 AS is_administrative,

  try_cast(e.START AS TIMESTAMP)                       AS start_ts,
  try_cast(e.STOP AS TIMESTAMP)                        AS end_ts,
  to_date(try_cast(e.START AS TIMESTAMP))              AS start_date,
  to_date(try_cast(e.STOP AS TIMESTAMP))               AS end_date,

  e.REASONCODE                                         AS reason_snomed_code,
  regexp_replace(e.REASONDESCRIPTION, '\\s*\\([^)]*\\)$', '') AS reason_description,
  ref.icd10cm_code                                     AS reason_icd10cm_code,
  ref.condition_class                                  AS reason_condition_class,
  ref.cohort                                           AS reason_condition_group,

  try_cast(e.BASE_ENCOUNTER_COST AS DECIMAL(12, 2))    AS base_encounter_cost,
  try_cast(e.TOTAL_CLAIM_COST AS DECIMAL(12, 2))       AS total_claim_cost,
  try_cast(e.PAYER_COVERAGE AS DECIMAL(12, 2))         AS payer_coverage,

  e._run_id                                            AS run_id,
  e._ingested_at                                       AS bronze_ingested_at
FROM synthea e
LEFT JOIN bronze.ref_snomed_icd10cm_conditions ref
  ON ref.snomed_code = e.REASONCODE

UNION ALL

SELECT
  resource_id                                          AS encounter_id,
  'epic_fhir_sandbox'                                  AS source_system,
  split_part(raw:subject.reference::string, '/', 2)    AS patient_id,
  split_part(raw:serviceProvider.reference::string, '/', 2) AS organization_id,
  split_part(raw:participant[0].individual.reference::string, '/', 2) AS provider_id,
  NULL                                                 AS payer_id,

  raw:class.display::string                            AS encounter_class,
  CASE
    WHEN raw:class.display::string ILIKE '%inpatient%' THEN 'Inpatient'
    WHEN raw:class.display::string ILIKE '%emergency%' THEN 'Emergency'
    ELSE 'Outpatient'
  END                                                  AS care_setting,
  raw:type[0].coding[0].code::string                   AS encounter_type_code,
  raw:type[0].text::string                             AS encounter_type,
  raw:status::string                                   AS encounter_status,
  false                                                AS is_administrative,

  raw:period.start::timestamp                          AS start_ts,
  raw:period.end::timestamp                            AS end_ts,
  to_date(raw:period.start::timestamp)                 AS start_date,
  to_date(raw:period.end::timestamp)                   AS end_date,

  NULL                                                 AS reason_snomed_code,
  raw:reasonCode[0].text::string                       AS reason_description,
  NULL                                                 AS reason_icd10cm_code,
  NULL                                                 AS reason_condition_class,
  NULL                                                 AS reason_condition_group,

  NULL                                                 AS base_encounter_cost,
  NULL                                                 AS total_claim_cost,
  NULL                                                 AS payer_coverage,

  run_id,
  ingested_at                                          AS bronze_ingested_at
FROM epic;
