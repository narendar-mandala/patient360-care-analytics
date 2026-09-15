-- Silver: procedure
-- One row per procedure performed (screenings, imaging, lab draws, surgeries, dialysis and so on).
--
-- Transformations:
--   1. Build an id from patient, encounter, code and start time, and remove duplicates.
--   2. Cast timestamps and cost from text.
--   3. Add the billing code (CPT, HCPCS or CDT) in two steps:
--        a. look the SNOMED code up in ref_procedure_code_map (covers almost all rows)
--        b. otherwise use the first matching rule in ref_procedure_category_rules, which matches on
--           words in the description (for example "x-ray" -> radiology)
--      code_mapping says which step found the code.
--   4. Add the ICD-10-CM code for the reason, when there is one.
--
-- Checks (rows are kept; failures are counted):
--   has_patient, end_not_before_start, has_billing_category

CREATE OR REFRESH MATERIALIZED VIEW silver.procedure (
  CONSTRAINT has_patient EXPECT (patient_id IS NOT NULL),
  CONSTRAINT end_not_before_start EXPECT (end_ts IS NULL OR end_ts >= start_ts),
  CONSTRAINT has_billing_category EXPECT (service_category IS NOT NULL)
)
COMMENT 'One row per procedure, with SNOMED code, CPT/HCPCS/CDT billing code, service category and reason'
AS
WITH procedures AS (
  SELECT
    sha2(concat_ws('|', PATIENT, ENCOUNTER, CODE, START), 256) AS procedure_id,
    *
  FROM bronze.synthea_procedures
  QUALIFY row_number() OVER (PARTITION BY PATIENT, ENCOUNTER, CODE, START ORDER BY _ingested_at DESC) = 1
),

-- Step 3b: for each distinct procedure, the highest-priority description rule that matches.
rule_match AS (
  SELECT p.CODE AS snomed_code, r.cpt_hcpcs, r.code_system, r.service_category, r.billable_yn
  FROM (SELECT DISTINCT CODE, DESCRIPTION FROM procedures) p
  JOIN bronze.ref_procedure_category_rules r
    ON p.DESCRIPTION RLIKE r.description_regex
  QUALIFY row_number() OVER (PARTITION BY p.CODE ORDER BY CAST(r.priority AS INT)) = 1
)

SELECT
  p.procedure_id,
  'synthea'                                            AS source_system,
  p.PATIENT                                            AS patient_id,
  p.ENCOUNTER                                          AS encounter_id,
  try_cast(p.START AS TIMESTAMP)                       AS start_ts,
  try_cast(p.STOP AS TIMESTAMP)                        AS end_ts,
  to_date(try_cast(p.START AS TIMESTAMP))              AS procedure_date,

  p.CODE                                               AS snomed_code,
  regexp_replace(p.DESCRIPTION, '\\s*\\([^)]*\\)$', '') AS description,

  coalesce(m.cpt_hcpcs, rm.cpt_hcpcs)                  AS billing_code,
  coalesce(m.code_system, rm.code_system)              AS billing_code_system,
  coalesce(m.service_category, rm.service_category)    AS service_category,
  coalesce(m.billable_yn, rm.billable_yn) = 'Y'        AS is_billable,
  CASE WHEN m.snomed_code IS NOT NULL THEN 'explicit_map'
       WHEN rm.snomed_code IS NOT NULL THEN 'category_rule' END AS code_mapping,

  try_cast(p.BASE_COST AS DECIMAL(12, 2))              AS base_cost,

  p.REASONCODE                                         AS reason_snomed_code,
  regexp_replace(p.REASONDESCRIPTION, '\\s*\\([^)]*\\)$', '') AS reason_description,
  reason.icd10cm_code                                  AS reason_icd10cm_code,

  p._run_id                                            AS run_id,
  p._ingested_at                                       AS bronze_ingested_at
FROM procedures p
LEFT JOIN bronze.ref_procedure_code_map m ON m.snomed_code = p.CODE
LEFT JOIN rule_match rm ON rm.snomed_code = p.CODE AND m.snomed_code IS NULL
LEFT JOIN bronze.ref_snomed_icd10cm_conditions reason ON reason.snomed_code = p.REASONCODE;
