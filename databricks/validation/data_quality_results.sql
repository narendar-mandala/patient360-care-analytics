-- Data quality results from the latest pipeline update: passed and failed rows for every expectation.
-- event_log(TABLE(...)) reads the event log of the pipeline that builds that table, so no pipeline id is needed.

WITH latest_update AS (
  SELECT origin.update_id
  FROM event_log(TABLE(healthcare.gold.fact_index_admission))
  WHERE event_type = 'create_update'
  ORDER BY timestamp DESC
  LIMIT 1
)
SELECT
  e.origin.flow_name     AS table_name,
  ex.name                AS expectation,
  sum(ex.passed_records) AS passed_rows,
  sum(ex.failed_records) AS failed_rows
FROM event_log(TABLE(healthcare.gold.fact_index_admission)) e
LATERAL VIEW explode(
  from_json(e.details:flow_progress.data_quality.expectations,
            'array<struct<name:string,dataset:string,passed_records:bigint,failed_records:bigint>>')
) t AS ex
WHERE e.event_type = 'flow_progress'
  AND e.origin.update_id = (SELECT update_id FROM latest_update)
GROUP BY ALL
ORDER BY failed_rows DESC, table_name, expectation;
