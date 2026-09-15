-- Silver: provider
-- One row per clinician, from Synthea (CSV) and the Epic FHIR sandbox (Practitioner).
--
-- Transformations:
--   1. Keep the latest copy of each provider.
--   2. Remove the digits Synthea appends to names; decode sex; capitalize the specialty.
--   3. Cast coordinates from text.
--   4. Epic sandbox practitioners: read name and sex from the FHIR JSON.
--
-- Checks (rows are kept; failures are counted):
--   has_name

CREATE OR REFRESH MATERIALIZED VIEW silver.provider (
  CONSTRAINT has_name EXPECT (provider_name IS NOT NULL)
)
COMMENT 'One row per provider: name, specialty, organization, NPI and location'
AS
WITH synthea AS (
  SELECT *
  FROM bronze.synthea_providers
  QUALIFY row_number() OVER (PARTITION BY Id ORDER BY _ingested_at DESC) = 1
),

epic AS (
  SELECT *
  FROM bronze.fhir_resources
  WHERE source_system = 'epic_fhir_sandbox' AND resource_type = 'Practitioner'
  QUALIFY row_number() OVER (PARTITION BY resource_id ORDER BY ingested_at DESC) = 1
)

SELECT
  Id                                                   AS provider_id,
  'synthea'                                            AS source_system,
  regexp_replace(NAME, '[0-9]+', '')                   AS provider_name,
  CASE GENDER WHEN 'F' THEN 'Female' WHEN 'M' THEN 'Male' END AS sex,
  initcap(SPECIALITY)                                  AS specialty,
  ORGANIZATION                                         AS organization_id,
  NPI                                                  AS npi,
  ADDRESS                                              AS address,
  CITY                                                 AS city,
  STATE                                                AS state,
  ZIP                                                  AS zip,
  try_cast(LAT AS DOUBLE)                              AS latitude,
  try_cast(LON AS DOUBLE)                              AS longitude,
  _run_id                                              AS run_id,
  _ingested_at                                         AS bronze_ingested_at
FROM synthea

UNION ALL

SELECT
  resource_id                                          AS provider_id,
  'epic_fhir_sandbox'                                  AS source_system,
  coalesce(raw:name[0].text::string,
           concat_ws(' ', raw:name[0].given[0]::string, raw:name[0].family::string)) AS provider_name,
  initcap(raw:gender::string)                          AS sex,
  NULL                                                 AS specialty,
  NULL                                                 AS organization_id,
  NULL                                                 AS npi,
  NULL                                                 AS address,
  NULL                                                 AS city,
  NULL                                                 AS state,
  NULL                                                 AS zip,
  NULL                                                 AS latitude,
  NULL                                                 AS longitude,
  run_id,
  ingested_at                                          AS bronze_ingested_at
FROM epic;
