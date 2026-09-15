-- Gold: Patient 360 and care management
--
--   patient_360               one row per patient: recent use of care, costs, chronic conditions,
--                             medications, abnormal labs and latest risk score, as of the reporting date
--   patient_timeline          one row per event in a patient's history (visits, diagnoses, procedures,
--                             medications, abnormal labs, vaccines), for the timeline visual
--   care_management_worklist  patients discharged in the last 14 days, ranked by LACE score, with
--                             the reasons behind their score
--
-- "Last 12 months" means the 365 days up to and including ${as_of_date}.

CREATE OR REFRESH MATERIALIZED VIEW gold.patient_360
COMMENT 'One row per patient: demographics, 12-month utilization and cost, chronic conditions, medications, labs and risk'
AS
WITH utilization AS (
  SELECT
    patient_id,
    max(to_date(start_ts)) FILTER (WHERE to_date(start_ts) <= DATE '${as_of_date}') AS last_visit_date,
    count(*) FILTER (WHERE to_date(start_ts) > DATE '${as_of_date}' - INTERVAL 365 DAYS AND to_date(start_ts) <= DATE '${as_of_date}') AS visits_12_months,
    count_if(is_inpatient AND to_date(start_ts) > DATE '${as_of_date}' - INTERVAL 365 DAYS AND to_date(start_ts) <= DATE '${as_of_date}') AS inpatient_admissions_12_months,
    count_if(is_emergency AND to_date(start_ts) > DATE '${as_of_date}' - INTERVAL 365 DAYS AND to_date(start_ts) <= DATE '${as_of_date}') AS ed_visits_12_months,
    sum(medical_cost) FILTER (WHERE to_date(start_ts) > DATE '${as_of_date}' - INTERVAL 365 DAYS AND to_date(start_ts) <= DATE '${as_of_date}') AS medical_cost_12_months,
    sum(payer_paid) FILTER (WHERE to_date(start_ts) > DATE '${as_of_date}' - INTERVAL 365 DAYS AND to_date(start_ts) <= DATE '${as_of_date}') AS payer_paid_12_months
  FROM gold.fact_encounter
  GROUP BY patient_id
),

chronic AS (
  SELECT
    patient_id,
    count(DISTINCT icd10cm_code)                        AS chronic_condition_count,
    array_join(array_sort(collect_set(description)), '; ') AS chronic_conditions
  FROM gold.fact_condition
  WHERE is_chronic AND condition_class = 'diagnosis'
    AND start_date <= DATE '${as_of_date}'
    AND (stop_date IS NULL OR stop_date > DATE '${as_of_date}')
  GROUP BY patient_id
),

medications AS (
  SELECT patient_id, count(DISTINCT rxnorm_code) AS active_medication_count
  FROM gold.fact_medication
  WHERE to_date(start_ts) <= DATE '${as_of_date}'
    AND (stop_ts IS NULL OR to_date(stop_ts) > DATE '${as_of_date}')
  GROUP BY patient_id
),

labs AS (
  SELECT
    patient_id,
    count(*)                                            AS abnormal_labs_90_days,
    max_by(concat(test_name, ' ', coalesce(CAST(value_numeric AS STRING), value_text), ' ', coalesce(units, ''), ' (', abnormal_flag, ')'), result_ts) AS latest_abnormal_lab
  FROM gold.fact_lab_result
  WHERE is_abnormal
    AND to_date(result_ts) > DATE '${as_of_date}' - INTERVAL 90 DAYS
    AND to_date(result_ts) <= DATE '${as_of_date}'
  GROUP BY patient_id
),

latest_stay AS (
  SELECT
    patient_id,
    max_by(discharge_date, discharge_date)              AS last_discharge_date,
    max_by(lace_score, discharge_date)                  AS latest_lace_score,
    max_by(risk_tier, discharge_date)                   AS latest_risk_tier,
    count_if(is_readmitted_30_days AND discharge_date > DATE '${as_of_date}' - INTERVAL 365 DAYS) AS readmissions_12_months
  FROM gold.fact_index_admission
  GROUP BY patient_id
)

SELECT
  p.patient_id,
  p.source_system,
  p.patient_name,
  p.age,
  p.age_band,
  p.sex,
  p.race,
  p.ethnicity,
  p.city,
  p.is_deceased,
  p.death_date,
  p.current_payer_name,
  p.current_payer_category,

  u.last_visit_date,
  coalesce(u.visits_12_months, 0)                       AS visits_12_months,
  coalesce(u.inpatient_admissions_12_months, 0)         AS inpatient_admissions_12_months,
  coalesce(u.ed_visits_12_months, 0)                    AS ed_visits_12_months,
  coalesce(s.readmissions_12_months, 0)                 AS readmissions_12_months,
  CAST(coalesce(u.medical_cost_12_months, 0) AS DECIMAL(14, 2)) AS medical_cost_12_months,
  CAST(coalesce(u.payer_paid_12_months, 0) AS DECIMAL(14, 2))   AS payer_paid_12_months,
  -- High utilizer (section 6.2): 2 or more inpatient stays or 4 or more ED visits in 12 months.
  coalesce(u.inpatient_admissions_12_months, 0) >= 2 OR coalesce(u.ed_visits_12_months, 0) >= 4 AS is_high_utilizer,

  coalesce(c.chronic_condition_count, 0)                AS chronic_condition_count,
  c.chronic_conditions,
  coalesce(m.active_medication_count, 0)                AS active_medication_count,
  coalesce(l.abnormal_labs_90_days, 0)                  AS abnormal_labs_90_days,
  l.latest_abnormal_lab,

  s.last_discharge_date,
  s.latest_lace_score,
  s.latest_risk_tier
FROM gold.dim_patient p
LEFT JOIN utilization u ON u.patient_id = p.patient_id
LEFT JOIN chronic c ON c.patient_id = p.patient_id
LEFT JOIN medications m ON m.patient_id = p.patient_id
LEFT JOIN labs l ON l.patient_id = p.patient_id
LEFT JOIN latest_stay s ON s.patient_id = p.patient_id;


CREATE OR REFRESH MATERIALIZED VIEW gold.patient_timeline
COMMENT 'One row per event in a patient''s history, for the Patient 360 timeline'
AS
SELECT patient_id, start_ts AS event_ts, 'Visit' AS event_category, care_setting AS event_type,
       concat_ws(' - ', encounter_type, reason_description) AS description,
       reason_icd10cm_code AS code, encounter_id, medical_cost AS amount
FROM gold.fact_encounter

UNION ALL
SELECT patient_id, CAST(start_date AS TIMESTAMP), 'Diagnosis', condition_group,
       description, icd10cm_code, encounter_id, NULL
FROM gold.fact_condition
WHERE condition_class = 'diagnosis'

UNION ALL
SELECT patient_id, start_ts, 'Procedure', service_category,
       description, billing_code, encounter_id, base_cost
FROM gold.fact_procedure

UNION ALL
SELECT patient_id, start_ts, 'Medication', CASE WHEN is_active THEN 'Active' ELSE 'Stopped' END,
       description, rxnorm_code, encounter_id, pharmacy_cost
FROM gold.fact_medication

UNION ALL
SELECT patient_id, result_ts, 'Abnormal lab', abnormal_flag,
       concat(test_name, ' ', coalesce(CAST(value_numeric AS STRING), value_text), ' ', coalesce(units, '')),
       loinc_code, encounter_id, NULL
FROM gold.fact_lab_result
WHERE is_abnormal

UNION ALL
SELECT patient_id, administered_ts, 'Vaccine', 'Immunization',
       description, cpt_code, encounter_id, base_cost
FROM silver.immunization;


CREATE OR REFRESH MATERIALIZED VIEW gold.care_management_worklist
COMMENT 'Patients discharged in the last 14 days, ranked by LACE score, with the top reasons behind the score'
AS
SELECT
  row_number() OVER (ORDER BY i.lace_score DESC, i.discharge_date DESC, i.encounter_id) AS worklist_rank,
  i.encounter_id,
  i.patient_id,
  p.patient_name,
  p.age,
  p.sex,
  p.current_payer_category,
  f.facility_name,
  i.discharge_date,
  datediff(DATE '${as_of_date}', i.discharge_date)      AS days_since_discharge,
  i.reason_description,
  i.condition_group,
  i.length_of_stay_days,
  i.lace_score,
  i.risk_tier,
  -- The LACE components with points, largest first, as plain-language reasons (top 3).
  array_join(slice(
    transform(
      array_sort(
        filter(array(
          named_struct('points', i.lace_l, 'reason', concat('Length of stay ', i.length_of_stay_days, ' days')),
          named_struct('points', i.lace_a, 'reason', 'Admitted through the ED'),
          named_struct('points', i.lace_c, 'reason', concat('Charlson score ', i.charlson_score)),
          named_struct('points', i.lace_e, 'reason', concat(i.ed_visits_6_months, ' ED visits in the 6 months before'))
        ), x -> x.points > 0),
        (a, b) -> CASE WHEN a.points > b.points THEN -1 WHEN a.points < b.points THEN 1 ELSE 0 END),
      x -> concat(x.reason, ' (+', x.points, ')')),
    1, 3), '; ')                                        AS top_risk_drivers,
  p360.chronic_conditions,
  p360.active_medication_count,
  p360.is_high_utilizer,
  'Not yet contacted'                                   AS follow_up_status
FROM gold.fact_index_admission i
JOIN gold.dim_patient p ON p.patient_id = i.patient_id
LEFT JOIN gold.dim_facility f ON f.facility_id = i.facility_id
LEFT JOIN gold.patient_360 p360 ON p360.patient_id = i.patient_id
WHERE i.discharge_date > DATE '${as_of_date}' - INTERVAL 14 DAYS
  AND i.discharge_date <= DATE '${as_of_date}'
  AND NOT p.is_deceased;
