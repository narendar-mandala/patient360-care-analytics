-- Silver: payer
-- One row per insurance payer (Medicare, Medicaid, commercial plans, and "No Insurance").
--
-- Transformations:
--   1. Keep the latest copy of each payer.
--   2. Add the payer type (medicare, medicare_advantage, medicaid, dual, commercial, self_pay) from
--      ref_payer_profile. Synthea doesn't say what kind of payer each one is.
--   3. Make names readable ("NO_INSURANCE" -> "No Insurance").
--
-- Checks (rows are kept; failures are counted):
--   has_payer_type

CREATE OR REFRESH MATERIALIZED VIEW silver.payer (
  CONSTRAINT has_payer_type EXPECT (payer_type IS NOT NULL)
)
COMMENT 'One row per payer, with payer type'
AS
WITH payers AS (
  SELECT *
  FROM bronze.synthea_payers
  QUALIFY row_number() OVER (PARTITION BY Id ORDER BY _ingested_at DESC) = 1
)

SELECT
  p.Id                                                 AS payer_id,
  'synthea'                                            AS source_system,
  CASE WHEN p.NAME = 'NO_INSURANCE' THEN 'No Insurance' ELSE p.NAME END AS payer_name,
  prof.payer_type,
  CASE prof.payer_type
    WHEN 'medicare'           THEN 'Medicare'
    WHEN 'medicare_advantage' THEN 'Medicare Advantage'
    WHEN 'medicaid'           THEN 'Medicaid'
    WHEN 'dual'               THEN 'Dual Eligible'
    WHEN 'commercial'         THEN 'Commercial'
    WHEN 'self_pay'           THEN 'Self-Pay'
  END                                                  AS payer_category,
  initcap(p.OWNERSHIP)                                 AS ownership,
  p.CITY                                               AS city,
  p.STATE_HEADQUARTERED                                AS state_headquartered,
  p.PHONE                                              AS phone,
  p._run_id                                            AS run_id,
  p._ingested_at                                       AS bronze_ingested_at
FROM payers p
LEFT JOIN bronze.ref_payer_profile prof ON prof.payer_name = p.NAME;
