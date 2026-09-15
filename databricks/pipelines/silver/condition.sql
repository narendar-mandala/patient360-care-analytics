-- Silver: condition
-- One row per condition recorded for a patient (diagnoses, symptoms, history and social factors),
-- from Synthea (CSV) and the Epic FHIR sandbox.
--
-- Transformations:
--   1. Synthea conditions have no id, so build one from patient, encounter, code and start date,
--      and use it to remove duplicates.
--   2. Cast dates from text.
--   3. Add the ICD-10-CM code and categories from the reference mapping:
--        condition_class   diagnosis, symptom, history, social factor (sdoh) and so on
--        condition_group   heart failure (HF), COPD, diabetes, and so on
--        charlson_category used for the Charlson comorbidity score
--        is_chronic, sdoh_domain, map_quality
--   4. Drop the "(disorder)" / "(finding)" suffix from descriptions.
--   5. Epic sandbox conditions already carry an ICD-10-CM code, so it's taken straight from the
--      FHIR JSON (icd10_source = 'source'). Categories are still looked up by SNOMED code when possible.
--
-- Checks (rows are kept; failures are counted):
--   has_patient, has_code, diagnosis_has_icd10, stop_not_before_start

CREATE OR REFRESH MATERIALIZED VIEW silver.condition (
  CONSTRAINT has_patient EXPECT (patient_id IS NOT NULL),
  CONSTRAINT has_code EXPECT (condition_class IS NOT NULL),
  CONSTRAINT diagnosis_has_icd10 EXPECT (condition_class <> 'diagnosis' OR icd10cm_code IS NOT NULL),
  CONSTRAINT stop_not_before_start EXPECT (stop_date IS NULL OR stop_date >= start_date)
)
COMMENT 'One row per patient condition, with SNOMED and ICD-10-CM codes and condition categories'
AS
WITH synthea AS (
  SELECT
    sha2(concat_ws('|', PATIENT, ENCOUNTER, CODE, START), 256) AS condition_id,
    *
  FROM bronze.synthea_conditions
  QUALIFY row_number() OVER (PARTITION BY PATIENT, ENCOUNTER, CODE, START ORDER BY _ingested_at DESC) = 1
),

epic AS (
  SELECT
    *,
    from_json(raw:code.coding, 'array<struct<system:string, code:string, display:string>>') AS codings
  FROM bronze.fhir_resources
  WHERE source_system = 'epic_fhir_sandbox' AND resource_type = 'Condition'
  QUALIFY row_number() OVER (PARTITION BY resource_id ORDER BY ingested_at DESC) = 1
),

epic_parsed AS (
  SELECT
    resource_id,
    split_part(raw:subject.reference::string, '/', 2)   AS patient_id,
    split_part(raw:encounter.reference::string, '/', 2) AS encounter_id,
    coalesce(try_cast(raw:onsetDateTime::string AS DATE), try_cast(raw:recordedDate::string AS DATE)) AS start_date,
    try_cast(raw:abatementDateTime::string AS DATE)     AS stop_date,
    raw:clinicalStatus.coding[0].code::string           AS clinical_status,
    filter(codings, c -> c.system = 'http://snomed.info/sct')[0].code          AS snomed_code,
    filter(codings, c -> c.system = 'http://hl7.org/fhir/sid/icd-10-cm')[0].code AS icd10cm_code,
    raw:code.text::string                               AS description,
    run_id,
    ingested_at
  FROM epic
)

SELECT
  c.condition_id,
  'synthea'                                            AS source_system,
  c.PATIENT                                            AS patient_id,
  c.ENCOUNTER                                          AS encounter_id,
  try_cast(c.START AS DATE)                            AS start_date,
  try_cast(c.STOP AS DATE)                             AS stop_date,
  c.STOP IS NULL                                       AS is_active,

  c.CODE                                               AS snomed_code,
  regexp_replace(c.DESCRIPTION, '\\s*\\([^)]*\\)$', '') AS description,
  ref.icd10cm_code,
  CASE WHEN ref.icd10cm_code IS NOT NULL THEN 'reference_map' END AS icd10_source,
  ref.condition_class,
  ref.cohort                                           AS condition_group,
  ref.charlson_category,
  ref.chronic_yn = 'Y'                                 AS is_chronic,
  ref.sdoh_domain,
  ref.map_quality,

  c._run_id                                            AS run_id,
  c._ingested_at                                       AS bronze_ingested_at
FROM synthea c
LEFT JOIN bronze.ref_snomed_icd10cm_conditions ref
  ON ref.snomed_code = c.CODE

UNION ALL

SELECT
  e.resource_id                                        AS condition_id,
  'epic_fhir_sandbox'                                  AS source_system,
  e.patient_id,
  nullif(e.encounter_id, '')                           AS encounter_id,
  e.start_date,
  e.stop_date,
  coalesce(e.clinical_status = 'active', e.stop_date IS NULL) AS is_active,

  e.snomed_code,
  e.description,
  e.icd10cm_code,
  CASE WHEN e.icd10cm_code IS NOT NULL THEN 'source' END AS icd10_source,
  coalesce(ref.condition_class, CASE WHEN e.icd10cm_code IS NOT NULL THEN 'diagnosis' END) AS condition_class,
  ref.cohort                                           AS condition_group,
  ref.charlson_category,
  ref.chronic_yn = 'Y'                                 AS is_chronic,
  ref.sdoh_domain,
  CASE WHEN ref.snomed_code IS NOT NULL THEN ref.map_quality ELSE 'source' END AS map_quality,

  e.run_id,
  e.ingested_at                                        AS bronze_ingested_at
FROM epic_parsed e
LEFT JOIN bronze.ref_snomed_icd10cm_conditions ref
  ON ref.snomed_code = e.snomed_code;
