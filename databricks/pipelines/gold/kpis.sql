-- Gold: KPI tables for Power BI
--
-- These hold counts and sums, never rates. Power BI divides one Gold column by another
-- (for example readmissions / index_admissions), so every rate uses the same definition
-- no matter how a report slices it.
--
--   kpi_monthly                month x facility x payer category x condition group
--   kpi_active_patients_monthly month: patients with any visit in the previous 24 months (the ED per 1,000 denominator)
--
-- Measures and the month they count in:
--   admissions, medical_cost, payer_paid, patient_responsibility   month the encounter started
--   ed_visits                                                      month the ED visit started
--   discharges, inpatient_days                                     month of discharge (ALOS = inpatient_days / discharges)
--   index_admissions, readmissions, post_discharge_ed_visits,
--   readmission_cost                                               month of the index discharge, only when follow-up is complete

CREATE OR REFRESH MATERIALIZED VIEW gold.kpi_monthly
COMMENT 'Monthly counts and sums for the executive and utilization reports, by facility, payer category and condition group'
AS
WITH encounter_measures AS (
  SELECT
    date_trunc('MONTH', to_date(e.start_ts))::date      AS month_start,
    e.facility_id,
    coalesce(py.payer_category, 'Unknown')              AS payer_category,
    e.condition_group,
    CASE WHEN e.is_inpatient THEN 1 ELSE 0 END          AS admissions,
    CASE WHEN e.is_emergency THEN 1 ELSE 0 END          AS ed_visits,
    0 AS discharges, 0 AS inpatient_days,
    0 AS index_admissions, 0 AS readmissions, 0 AS post_discharge_ed_visits, 0 AS readmission_cost,
    coalesce(e.medical_cost, 0)                         AS medical_cost,
    coalesce(e.payer_paid, 0)                           AS payer_paid,
    coalesce(e.patient_responsibility, 0)               AS patient_responsibility
  FROM gold.fact_encounter e
  LEFT JOIN gold.dim_payer py ON py.payer_id = e.payer_id
),

discharge_measures AS (
  SELECT
    date_trunc('MONTH', to_date(e.end_ts))::date        AS month_start,
    e.facility_id,
    coalesce(py.payer_category, 'Unknown'),
    e.condition_group,
    0, 0,
    1                                                   AS discharges,
    e.length_of_stay_days                               AS inpatient_days,
    0, 0, 0, 0,
    0, 0, 0
  FROM gold.fact_encounter e
  LEFT JOIN gold.dim_payer py ON py.payer_id = e.payer_id
  WHERE e.is_inpatient
),

readmission_measures AS (
  SELECT
    date_trunc('MONTH', i.discharge_date)::date         AS month_start,
    i.facility_id,
    coalesce(py.payer_category, 'Unknown'),
    i.condition_group,
    0, 0, 0, 0,
    1                                                   AS index_admissions,
    CASE WHEN i.is_readmitted_30_days THEN 1 ELSE 0 END AS readmissions,
    i.post_discharge_ed_visits,
    coalesce(i.readmission_cost, 0)                     AS readmission_cost,
    0, 0, 0
  FROM gold.fact_index_admission i
  LEFT JOIN gold.dim_payer py ON py.payer_id = i.payer_id
  WHERE i.follow_up_complete
),

all_measures AS (
  SELECT * FROM encounter_measures
  UNION ALL SELECT * FROM discharge_measures
  UNION ALL SELECT * FROM readmission_measures
)

SELECT
  month_start,
  CAST(date_format(month_start, 'yyyyMMdd') AS INT)     AS month_date_key,
  facility_id,
  payer_category,
  condition_group,
  sum(admissions)                                       AS admissions,
  sum(discharges)                                       AS discharges,
  sum(inpatient_days)                                   AS inpatient_days,
  sum(ed_visits)                                        AS ed_visits,
  sum(index_admissions)                                 AS index_admissions,
  sum(readmissions)                                     AS readmissions,
  sum(post_discharge_ed_visits)                         AS post_discharge_ed_visits,
  CAST(sum(readmission_cost) AS DECIMAL(14, 2))         AS readmission_cost,
  CAST(sum(medical_cost) AS DECIMAL(14, 2))             AS medical_cost,
  CAST(sum(payer_paid) AS DECIMAL(14, 2))               AS payer_paid,
  CAST(sum(patient_responsibility) AS DECIMAL(14, 2))   AS patient_responsibility
FROM all_measures
WHERE month_start BETWEEN DATE '${analysis_start_date}' AND DATE '${as_of_date}'
GROUP BY ALL;


CREATE OR REFRESH MATERIALIZED VIEW gold.kpi_active_patients_monthly
COMMENT 'Active patients per month: alive, born, and seen at least once in the previous 24 months. Summing across months gives patient-months.'
AS
WITH months AS (
  SELECT explode(sequence(DATE '${analysis_start_date}', DATE '${as_of_date}', INTERVAL 1 MONTH)) AS month_start
),
visit_months AS (
  SELECT DISTINCT patient_id, date_trunc('MONTH', to_date(start_ts))::date AS visit_month
  FROM gold.fact_encounter
)
SELECT
  m.month_start,
  CAST(date_format(m.month_start, 'yyyyMMdd') AS INT)   AS month_date_key,
  count(DISTINCT p.patient_id)                          AS active_patients
FROM months m
JOIN gold.dim_patient p
  ON p.birth_date <= m.month_start
 AND (p.death_date IS NULL OR p.death_date >= m.month_start)
JOIN visit_months v
  ON v.patient_id = p.patient_id
 AND v.visit_month BETWEEN add_months(m.month_start, -24) AND m.month_start
GROUP BY m.month_start;
