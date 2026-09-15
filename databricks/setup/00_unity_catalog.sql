-- Unity Catalog objects for the healthcare platform.
-- Free Edition (Default Storage): catalogs must be created via SQL or UI; the REST/CLI catalogs API fails without a managed location.

CREATE CATALOG IF NOT EXISTS healthcare COMMENT 'Healthcare Patient 360 & Predictive Care Analytics Platform (synthetic data, no PHI)';

CREATE SCHEMA IF NOT EXISTS healthcare.landing COMMENT 'Raw files landed from source systems';
CREATE SCHEMA IF NOT EXISTS healthcare.bronze  COMMENT 'Raw records + ingestion metadata, append-only';
CREATE SCHEMA IF NOT EXISTS healthcare.silver  COMMENT 'Typed, conformed, deduplicated, DQ-flagged';
CREATE SCHEMA IF NOT EXISTS healthcare.gold    COMMENT 'Dimensional model, Patient 360, KPIs, ML features';
CREATE SCHEMA IF NOT EXISTS healthcare.ops     COMMENT 'DQ results, pipeline audit, defect manifest';

CREATE VOLUME IF NOT EXISTS healthcare.landing.raw COMMENT 'Landing zone: epic_fhir, synthea_fhir, clarity, claims';
