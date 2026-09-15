-- Gold: dimensions
-- The "who, what, where and when" tables that facts join to in Power BI.
--
--   dim_date       one row per calendar day, with a numeric date_key (yyyymmdd) used by every fact
--   dim_patient    one row per patient, with age and current payer as of the reporting date
--   dim_provider   one row per clinician
--   dim_facility   one row per organization (hospital, clinic and so on)
--   dim_payer      one row per payer, with payer category
--   dim_diagnosis  one row per ICD-10-CM code, with condition group and chronic flag
--
-- ${as_of_date} is the last day of the reporting period (pipeline configuration).

CREATE OR REFRESH MATERIALIZED VIEW gold.dim_date
COMMENT 'One row per day from 1900 to 2027. date_key (yyyymmdd) joins to every fact.'
AS
SELECT
  CAST(date_format(d, 'yyyyMMdd') AS INT)              AS date_key,
  d                                                    AS date,
  year(d)                                              AS year,
  quarter(d)                                           AS quarter,
  concat(year(d), '-Q', quarter(d))                    AS year_quarter,
  month(d)                                             AS month,
  date_format(d, 'MMMM')                               AS month_name,
  date_trunc('MONTH', d)::date                         AS month_start,
  date_format(d, 'yyyy-MM')                            AS year_month,
  dayofweek(d)                                         AS day_of_week,
  date_format(d, 'EEEE')                               AS day_name,
  d BETWEEN DATE '${analysis_start_date}' AND DATE '${as_of_date}' AS is_in_analysis_period
FROM (SELECT explode(sequence(DATE '1900-01-01', DATE '2027-12-31', INTERVAL 1 DAY)) AS d);


CREATE OR REFRESH MATERIALIZED VIEW gold.dim_patient
COMMENT 'One row per patient: demographics, age and current payer as of the reporting date'
AS
WITH current_coverage AS (
  -- The coverage period that includes the reporting date; if none does, the most recent one.
  SELECT
    c.patient_id,
    c.payer_id,
    c.member_id
  FROM silver.coverage c
  WHERE c.start_date <= DATE '${as_of_date}'
  QUALIFY row_number() OVER (
    PARTITION BY c.patient_id
    ORDER BY (DATE '${as_of_date}' BETWEEN c.start_date AND coalesce(c.end_date, DATE '9999-12-31')) DESC, c.start_date DESC
  ) = 1
)
SELECT
  p.patient_id,
  p.source_system,
  concat_ws(' ', p.first_name, p.last_name)            AS patient_name,
  p.first_name,
  p.last_name,
  p.birth_date,
  p.death_date,
  p.is_deceased,
  -- Age on the reporting date, or at death.
  floor(months_between(least(DATE '${as_of_date}', coalesce(p.death_date, DATE '${as_of_date}')), p.birth_date) / 12) AS age,
  CASE
    WHEN floor(months_between(least(DATE '${as_of_date}', coalesce(p.death_date, DATE '${as_of_date}')), p.birth_date) / 12) < 18 THEN '0-17'
    WHEN floor(months_between(least(DATE '${as_of_date}', coalesce(p.death_date, DATE '${as_of_date}')), p.birth_date) / 12) < 45 THEN '18-44'
    WHEN floor(months_between(least(DATE '${as_of_date}', coalesce(p.death_date, DATE '${as_of_date}')), p.birth_date) / 12) < 65 THEN '45-64'
    WHEN floor(months_between(least(DATE '${as_of_date}', coalesce(p.death_date, DATE '${as_of_date}')), p.birth_date) / 12) < 75 THEN '65-74'
    ELSE '75+'
  END                                                  AS age_band,
  p.sex,
  p.race,
  p.ethnicity,
  p.marital_status,
  p.city,
  p.county,
  p.state,
  p.zip,
  p.latitude,
  p.longitude,
  cc.payer_id                                          AS current_payer_id,
  coalesce(py.payer_name, 'Unknown')                   AS current_payer_name,
  coalesce(py.payer_category, 'Unknown')               AS current_payer_category,
  cc.member_id                                         AS current_member_id
FROM silver.patient p
LEFT JOIN current_coverage cc ON cc.patient_id = p.patient_id
LEFT JOIN silver.payer py ON py.payer_id = cc.payer_id;


CREATE OR REFRESH MATERIALIZED VIEW gold.dim_provider
COMMENT 'One row per provider'
AS
SELECT provider_id, source_system, provider_name, sex, specialty, organization_id AS facility_id, npi, city, state
FROM silver.provider;


CREATE OR REFRESH MATERIALIZED VIEW gold.dim_facility
COMMENT 'One row per facility (organization)'
AS
SELECT organization_id AS facility_id, source_system, organization_name AS facility_name, address, city, state, zip,
       npi, latitude, longitude
FROM silver.organization;


CREATE OR REFRESH MATERIALIZED VIEW gold.dim_payer
COMMENT 'One row per payer, with payer category'
AS
SELECT payer_id, payer_name, payer_type, payer_category, ownership
FROM silver.payer;


CREATE OR REFRESH MATERIALIZED VIEW gold.dim_diagnosis
COMMENT 'One row per ICD-10-CM code: description, condition class, condition group, chronic flag and Charlson category'
AS
WITH codes AS (
  -- Codes from the reference mapping, plus any ICD-10-CM codes that came directly from Epic.
  SELECT icd10cm_code, snomed_description AS description, condition_class, cohort AS condition_group,
         chronic_yn = 'Y' AS is_chronic, charlson_category, 1 AS source_priority
  FROM bronze.ref_snomed_icd10cm_conditions
  WHERE icd10cm_code IS NOT NULL
  UNION ALL
  SELECT icd10cm_code, description, condition_class, condition_group, is_chronic, charlson_category, 2
  FROM silver.condition
  WHERE icd10_source = 'source'
)
SELECT
  icd10cm_code,
  left(icd10cm_code, 3)                                AS icd10cm_category,
  description,
  condition_class,
  coalesce(condition_group, 'Other')                   AS condition_group,
  condition_group IN ('AMI', 'HF', 'PNEUMONIA', 'COPD') AS is_hrrp_condition,
  coalesce(is_chronic, false)                          AS is_chronic,
  charlson_category
FROM codes
-- Several SNOMED codes can share one ICD-10-CM code; keep one description per code.
QUALIFY row_number() OVER (PARTITION BY icd10cm_code ORDER BY source_priority, condition_group IS NULL, description) = 1;
