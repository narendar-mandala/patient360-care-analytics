-- Checks run by the daily job after the pipeline finishes.
-- Each statement stops the job with a clear message (raise_error) if something is wrong, so a failed
-- check shows up as a failed job run and triggers the failure email.

-- 1. Every Gold table has data.
SELECT CASE WHEN min(row_count) = 0
            THEN raise_error(concat('Empty Gold table(s): ', array_join(collect_list(CASE WHEN row_count = 0 THEN table_name END), ', ')))
       END AS gold_tables_have_data
FROM (
  SELECT 'dim_patient' AS table_name, count(*) AS row_count FROM healthcare.gold.dim_patient
  UNION ALL SELECT 'fact_encounter', count(*) FROM healthcare.gold.fact_encounter
  UNION ALL SELECT 'fact_claim', count(*) FROM healthcare.gold.fact_claim
  UNION ALL SELECT 'fact_index_admission', count(*) FROM healthcare.gold.fact_index_admission
  UNION ALL SELECT 'kpi_monthly', count(*) FROM healthcare.gold.kpi_monthly
  UNION ALL SELECT 'patient_360', count(*) FROM healthcare.gold.patient_360
);

-- 2. Silver keeps every record from Bronze (duplicates removed, nothing else lost).
SELECT CASE WHEN count_if(silver_rows <> bronze_keys) > 0
            THEN raise_error(concat('Silver row counts differ from Bronze: ',
                                    array_join(collect_list(CASE WHEN silver_rows <> bronze_keys THEN concat(table_name, ' ', silver_rows, ' vs ', bronze_keys) END), '; ')))
       END AS silver_matches_bronze
FROM (
  SELECT 'patient' AS table_name,
         (SELECT count(*) FROM healthcare.silver.patient WHERE source_system = 'synthea') AS silver_rows,
         (SELECT count(DISTINCT Id) FROM healthcare.bronze.synthea_patients) AS bronze_keys
  UNION ALL
  SELECT 'encounter',
         (SELECT count(*) FROM healthcare.silver.encounter WHERE source_system = 'synthea'),
         (SELECT count(DISTINCT Id) FROM healthcare.bronze.synthea_encounters)
  UNION ALL
  SELECT 'claim',
         (SELECT count(*) FROM healthcare.silver.claim),
         (SELECT count(DISTINCT Id) FROM healthcare.bronze.synthea_claims)
);

-- 3. No data quality expectation failed in the latest pipeline update, other than the two known
--    problems in Synthea's source data (documented in docs/05_silver.md).
WITH latest_update AS (
  SELECT origin.update_id
  FROM event_log(TABLE(healthcare.gold.fact_index_admission))
  WHERE event_type = 'create_update'
  ORDER BY timestamp DESC
  LIMIT 1
),
failures AS (
  SELECT concat(e.origin.flow_name, '.', ex.name) AS expectation, sum(ex.failed_records) AS failed_rows
  FROM event_log(TABLE(healthcare.gold.fact_index_admission)) e
  LATERAL VIEW explode(
    from_json(e.details:flow_progress.data_quality.expectations,
              'array<struct<name:string,dataset:string,passed_records:bigint,failed_records:bigint>>')
  ) t AS ex
  WHERE e.event_type = 'flow_progress'
    AND e.origin.update_id = (SELECT update_id FROM latest_update)
  GROUP BY 1
  HAVING sum(ex.failed_records) > 0
)
SELECT CASE WHEN count(*) > 0
            THEN raise_error(concat('Unexpected data quality failures: ',
                                    array_join(collect_list(concat(expectation, ' (', failed_rows, ' rows)')), '; ')))
       END AS no_unexpected_expectation_failures
FROM failures
WHERE expectation NOT IN (
  'healthcare.silver.claim.has_principal_diagnosis',      -- claims whose only diagnoses are employment or education findings
  'healthcare.silver.medication.stop_not_before_start'    -- medication renewals Synthea records with an earlier stop date
);

-- 4. The readmission measure produced results for the reporting period.
SELECT CASE WHEN count_if(follow_up_complete) = 0
            THEN raise_error('No index admissions with complete follow-up in the reporting period')
       END AS readmission_measure_has_results
FROM healthcare.gold.fact_index_admission;
