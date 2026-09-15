-- Silver: observation
-- One row per clinical observation: lab results, vital signs, survey and screening answers,
-- social history and exam findings.
--
-- Transformations:
--   1. Remove exact duplicate rows (same patient, encounter, time, code and value).
--   2. Leave out Synthea's quality-of-life scores (QOLS, QALY, DALY). They're simulation outputs,
--      not something a clinician recorded.
--   3. Cast the timestamp, and turn numeric results into numbers (value_numeric). Text results
--      stay in value_text.
--   4. For labs, add the panel the test belongs to (for example basic metabolic panel, CBC) from
--      ref_lab_panels.
--   5. Flag lab results outside the normal range, using ref_lab_reference_ranges:
--      critical_low, low, normal, high or critical_high.
--
-- Checks (rows are kept; failures are counted):
--   has_patient, known_category, numeric_value_parsed

CREATE OR REFRESH MATERIALIZED VIEW silver.observation (
  CONSTRAINT has_patient EXPECT (patient_id IS NOT NULL),
  CONSTRAINT known_category EXPECT (category IS NOT NULL),
  CONSTRAINT numeric_value_parsed EXPECT (value_type <> 'numeric' OR value_numeric IS NOT NULL)
)
COMMENT 'One row per observation (labs, vitals, surveys), with numeric values, lab panel and abnormal flag'
AS
WITH observations AS (
  SELECT
    sha2(concat_ws('|', PATIENT, ENCOUNTER, DATE, CODE, VALUE), 256) AS observation_id,
    *
  FROM bronze.synthea_observations
  WHERE CODE NOT IN ('QOLS', 'QALY', 'DALY')
  QUALIFY row_number() OVER (PARTITION BY PATIENT, ENCOUNTER, DATE, CODE, VALUE ORDER BY _ingested_at DESC) = 1
),

typed AS (
  SELECT
    o.*,
    try_cast(o.DATE AS TIMESTAMP) AS observation_ts,
    CASE WHEN o.TYPE = 'numeric' THEN try_cast(o.VALUE AS DOUBLE) END AS value_numeric
  FROM observations o
)

SELECT
  t.observation_id,
  'synthea'                                            AS source_system,
  t.PATIENT                                            AS patient_id,
  t.ENCOUNTER                                          AS encounter_id,
  t.observation_ts,
  to_date(t.observation_ts)                            AS observation_date,
  t.CATEGORY                                           AS category,

  t.CODE                                               AS loinc_code,
  t.DESCRIPTION                                        AS description,
  panel.panel_name                                     AS lab_panel,
  panel.component_short_name                           AS lab_component,

  t.TYPE                                               AS value_type,
  t.VALUE                                              AS value_text,
  t.value_numeric,
  t.UNITS                                              AS units,

  try_cast(rr.reference_low AS DOUBLE)                 AS reference_low,
  try_cast(rr.reference_high AS DOUBLE)                AS reference_high,
  CASE
    WHEN t.CATEGORY <> 'laboratory' OR t.value_numeric IS NULL OR rr.loinc_code IS NULL THEN NULL
    WHEN t.value_numeric < try_cast(rr.critical_low AS DOUBLE)   THEN 'critical_low'
    WHEN t.value_numeric > try_cast(rr.critical_high AS DOUBLE)  THEN 'critical_high'
    WHEN t.value_numeric < try_cast(rr.reference_low AS DOUBLE)  THEN 'low'
    WHEN t.value_numeric > try_cast(rr.reference_high AS DOUBLE) THEN 'high'
    ELSE 'normal'
  END                                                  AS abnormal_flag,

  t._run_id                                            AS run_id,
  t._ingested_at                                       AS bronze_ingested_at
FROM typed t
LEFT JOIN bronze.ref_lab_panels panel ON panel.loinc_code = t.CODE AND t.CATEGORY = 'laboratory'
LEFT JOIN bronze.ref_lab_reference_ranges rr ON rr.loinc_code = t.CODE;
