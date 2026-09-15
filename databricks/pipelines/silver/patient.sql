-- Silver: patient
-- One row per patient, from Synthea (CSV) and the Epic FHIR sandbox, with proper types and cleaned-up values.
--
-- Transformations:
--   1. Keep the latest copy of each patient if the same patient was loaded more than once.
--   2. Cast dates and numbers from text.
--   3. Remove the digits Synthea appends to names ("Abe604" -> "Abe").
--   4. Decode short codes into readable values (marital status M/S/D/W, sex M/F).
--   5. Leave out identifiers nobody downstream needs (SSN, driver's license, passport).
--   6. Epic sandbox patients: read the fields out of the FHIR Patient JSON (raw:field::type),
--      including race and ethnicity, which FHIR stores as US Core extensions.
--
-- Checks (rows are kept; failures are counted in the pipeline's data quality metrics):
--   valid_birth_date, death_not_before_birth, known_sex

CREATE OR REFRESH MATERIALIZED VIEW silver.patient (
  CONSTRAINT valid_birth_date EXPECT (birth_date IS NOT NULL AND birth_date <= current_date()),
  CONSTRAINT death_not_before_birth EXPECT (death_date IS NULL OR death_date >= birth_date),
  CONSTRAINT known_sex EXPECT (sex IN ('Female', 'Male'))
)
COMMENT 'One row per patient: demographics and address, typed and cleaned (Synthea and Epic FHIR sandbox)'
AS
WITH synthea AS (
  SELECT *
  FROM bronze.synthea_patients
  QUALIFY row_number() OVER (PARTITION BY Id ORDER BY _ingested_at DESC) = 1
),

epic AS (
  SELECT
    *,
    -- FHIR keeps race and ethnicity in extensions; each has a nested "text" entry with a readable value.
    from_json(raw:extension, 'array<struct<url:string, extension:array<struct<url:string, valueString:string>>>>') AS ext
  FROM bronze.fhir_resources
  WHERE source_system = 'epic_fhir_sandbox' AND resource_type = 'Patient'
  QUALIFY row_number() OVER (PARTITION BY resource_id ORDER BY ingested_at DESC) = 1
)

SELECT
  Id                                                   AS patient_id,
  'synthea'                                            AS source_system,
  regexp_replace(FIRST, '[0-9]+', '')                  AS first_name,
  regexp_replace(MIDDLE, '[0-9]+', '')                 AS middle_name,
  regexp_replace(LAST, '[0-9]+', '')                   AS last_name,
  try_cast(BIRTHDATE AS DATE)                          AS birth_date,
  try_cast(DEATHDATE AS DATE)                          AS death_date,
  DEATHDATE IS NOT NULL                                AS is_deceased,
  CASE GENDER WHEN 'F' THEN 'Female' WHEN 'M' THEN 'Male' END AS sex,
  initcap(RACE)                                        AS race,
  CASE ETHNICITY WHEN 'hispanic' THEN 'Hispanic or Latino'
                 WHEN 'nonhispanic' THEN 'Not Hispanic or Latino' END AS ethnicity,
  CASE MARITAL WHEN 'M' THEN 'Married' WHEN 'S' THEN 'Single'
               WHEN 'D' THEN 'Divorced' WHEN 'W' THEN 'Widowed' ELSE 'Unknown' END AS marital_status,
  ADDRESS                                              AS address,
  CITY                                                 AS city,
  STATE                                                AS state,
  COUNTY                                               AS county,
  ZIP                                                  AS zip,
  try_cast(LAT AS DOUBLE)                              AS latitude,
  try_cast(LON AS DOUBLE)                              AS longitude,
  try_cast(INCOME AS INT)                              AS household_income,
  _run_id                                              AS run_id,
  _ingested_at                                         AS bronze_ingested_at
FROM synthea

UNION ALL

SELECT
  resource_id                                          AS patient_id,
  'epic_fhir_sandbox'                                  AS source_system,
  raw:name[0].given[0]::string                         AS first_name,
  raw:name[0].given[1]::string                         AS middle_name,
  raw:name[0].family::string                           AS last_name,
  raw:birthDate::date                                  AS birth_date,
  try_cast(raw:deceasedDateTime::string AS DATE)       AS death_date,
  coalesce(raw:deceasedBoolean::boolean, raw:deceasedDateTime IS NOT NULL) AS is_deceased,
  initcap(raw:gender::string)                          AS sex,
  filter(filter(ext, e -> e.url LIKE '%us-core-race')[0].extension, x -> x.url = 'text')[0].valueString      AS race,
  filter(filter(ext, e -> e.url LIKE '%us-core-ethnicity')[0].extension, x -> x.url = 'text')[0].valueString AS ethnicity,
  coalesce(raw:maritalStatus.text::string, 'Unknown')  AS marital_status,
  raw:address[0].line[0]::string                       AS address,
  initcap(raw:address[0].city::string)                 AS city,
  raw:address[0].state::string                         AS state,
  raw:address[0].district::string                      AS county,
  raw:address[0].postalCode::string                    AS zip,
  NULL                                                 AS latitude,
  NULL                                                 AS longitude,
  NULL                                                 AS household_income,
  run_id,
  ingested_at                                          AS bronze_ingested_at
FROM epic;
