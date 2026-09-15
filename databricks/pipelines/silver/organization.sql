-- Silver: organization
-- One row per facility (hospitals, clinics, urgent care, nursing facilities), from Synthea (CSV)
-- and the Epic FHIR sandbox (Organization).
--
-- Transformations:
--   1. Keep the latest copy of each organization.
--   2. Cast coordinates from text and tidy the name.
--   3. Epic sandbox organizations: read name and address from the FHIR JSON.
--
-- Checks (rows are kept; failures are counted):
--   has_name

CREATE OR REFRESH MATERIALIZED VIEW silver.organization (
  CONSTRAINT has_name EXPECT (organization_name IS NOT NULL)
)
COMMENT 'One row per organization (facility): name, address, NPI and location'
AS
WITH synthea AS (
  SELECT *
  FROM bronze.synthea_organizations
  QUALIFY row_number() OVER (PARTITION BY Id ORDER BY _ingested_at DESC) = 1
),

epic AS (
  SELECT *
  FROM bronze.fhir_resources
  WHERE source_system = 'epic_fhir_sandbox' AND resource_type = 'Organization'
  QUALIFY row_number() OVER (PARTITION BY resource_id ORDER BY ingested_at DESC) = 1
)

SELECT
  Id                                                   AS organization_id,
  'synthea'                                            AS source_system,
  initcap(trim(NAME))                                  AS organization_name,
  ADDRESS                                              AS address,
  CITY                                                 AS city,
  STATE                                                AS state,
  ZIP                                                  AS zip,
  PHONE                                                AS phone,
  NPI                                                  AS npi,
  try_cast(LAT AS DOUBLE)                              AS latitude,
  try_cast(LON AS DOUBLE)                              AS longitude,
  _run_id                                              AS run_id,
  _ingested_at                                         AS bronze_ingested_at
FROM synthea

UNION ALL

SELECT
  resource_id                                          AS organization_id,
  'epic_fhir_sandbox'                                  AS source_system,
  raw:name::string                                     AS organization_name,
  raw:address[0].line[0]::string                       AS address,
  initcap(raw:address[0].city::string)                 AS city,
  raw:address[0].state::string                         AS state,
  raw:address[0].postalCode::string                    AS zip,
  raw:telecom[0].value::string                         AS phone,
  NULL                                                 AS npi,
  NULL                                                 AS latitude,
  NULL                                                 AS longitude,
  run_id,
  ingested_at                                          AS bronze_ingested_at
FROM epic;
