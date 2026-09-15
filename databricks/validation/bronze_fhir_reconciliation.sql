-- Bronze FHIR reconciliation: compare against local counts (_manifest.json for Epic, _profile.json for Synthea).
-- Baseline 2026-09-15: total 1,126,984 = Epic 279 + Synthea 1,126,705 (Claim/EOB/Provenance excluded by design).

-- 1. Rows, distinct ids and files per source x resource type (rows should equal ids: no duplicates at Bronze)
SELECT source_system, resource_type,
       count(*)                    AS row_count,
       count(DISTINCT resource_id) AS distinct_ids,
       count(DISTINCT source_file) AS files,
       max(ingested_at)            AS last_ingested_at
FROM healthcare.bronze.fhir_resources
GROUP BY ALL
ORDER BY source_system, row_count DESC;

-- 2. Expectation columns must be clean
SELECT count(*)                                           AS total_rows,
       count_if(resource_type IS NULL)                    AS null_resource_type,
       count_if(resource_id IS NULL)                      AS null_resource_id,
       count_if(run_id IS NULL)                           AS null_run_id
FROM healthcare.bronze.fhir_resources;

-- 3. Same resource id appearing in more than one file (would indicate a re-landed run)
SELECT source_system, resource_type, resource_id, count(DISTINCT source_file) AS files
FROM healthcare.bronze.fhir_resources
GROUP BY ALL
HAVING count(DISTINCT source_file) > 1
LIMIT 100;
