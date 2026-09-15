-- Gold: clinical and financial facts
-- One table per kind of event, each with keys to the dimensions and a date_key.
--
--   fact_encounter      one row per visit or stay (administrative records left out), with length of stay and costs
--   fact_condition      one row per diagnosis recorded for a patient
--   fact_procedure      one row per procedure
--   fact_lab_result     one row per lab result, with abnormal flag
--   fact_medication     one row per medication order, with costs
--   fact_claim          one row per claim, with charges and payments totaled from its transactions
--   fact_member_month   one row per patient per month of insurance coverage (for per-member-per-month measures)

CREATE OR REFRESH MATERIALIZED VIEW gold.fact_encounter
COMMENT 'One row per encounter: setting, dates, length of stay, reason and costs'
AS
SELECT
  e.encounter_id,
  e.source_system,
  e.patient_id,
  e.provider_id,
  e.organization_id                                    AS facility_id,
  e.payer_id,
  CAST(date_format(e.start_date, 'yyyyMMdd') AS INT)   AS start_date_key,
  CAST(date_format(e.end_date, 'yyyyMMdd') AS INT)     AS end_date_key,
  e.start_ts,
  e.end_ts,
  e.care_setting,
  e.encounter_class,
  e.encounter_type,
  e.care_setting = 'Inpatient'                         AS is_inpatient,
  e.care_setting = 'Emergency'                         AS is_emergency,
  -- Length of stay in days for inpatient stays; a same-day stay counts as 1 day.
  CASE WHEN e.care_setting = 'Inpatient' THEN greatest(datediff(e.end_date, e.start_date), 1) END AS length_of_stay_days,
  e.reason_icd10cm_code,
  e.reason_description,
  coalesce(e.reason_condition_group, 'Other')          AS condition_group,
  e.total_claim_cost                                   AS medical_cost,
  e.payer_coverage                                     AS payer_paid,
  e.total_claim_cost - e.payer_coverage                AS patient_responsibility
FROM silver.encounter e
WHERE NOT e.is_administrative;


CREATE OR REFRESH MATERIALIZED VIEW gold.fact_condition
COMMENT 'One row per diagnosis, symptom or history item recorded for a patient (social factors left out)'
AS
SELECT
  c.condition_id,
  c.patient_id,
  c.encounter_id,
  CAST(date_format(c.start_date, 'yyyyMMdd') AS INT)   AS start_date_key,
  c.start_date,
  c.stop_date,
  c.is_active,
  c.icd10cm_code,
  c.snomed_code,
  c.description,
  c.condition_class,
  coalesce(c.condition_group, 'Other')                 AS condition_group,
  coalesce(c.is_chronic, false)                        AS is_chronic,
  c.charlson_category
FROM silver.condition c
WHERE c.condition_class IN ('diagnosis', 'symptom', 'history', 'pregnancy');


CREATE OR REFRESH MATERIALIZED VIEW gold.fact_procedure
COMMENT 'One row per procedure, with billing code and service category'
AS
SELECT
  p.procedure_id,
  p.patient_id,
  p.encounter_id,
  CAST(date_format(p.procedure_date, 'yyyyMMdd') AS INT) AS procedure_date_key,
  p.start_ts,
  p.snomed_code,
  p.description,
  p.billing_code,
  p.billing_code_system,
  p.service_category,
  p.is_billable,
  p.base_cost
FROM silver.procedure p;


CREATE OR REFRESH MATERIALIZED VIEW gold.fact_lab_result
COMMENT 'One row per lab result, with panel, numeric value, reference range and abnormal flag'
AS
SELECT
  o.observation_id                                     AS lab_result_id,
  o.patient_id,
  o.encounter_id,
  CAST(date_format(o.observation_date, 'yyyyMMdd') AS INT) AS result_date_key,
  o.observation_ts                                     AS result_ts,
  o.loinc_code,
  coalesce(o.lab_component, o.description)             AS test_name,
  o.lab_panel,
  o.value_numeric,
  o.value_text,
  o.units,
  o.reference_low,
  o.reference_high,
  o.abnormal_flag,
  o.abnormal_flag IN ('low', 'high', 'critical_low', 'critical_high') AS is_abnormal
FROM silver.observation o
WHERE o.category = 'laboratory';


CREATE OR REFRESH MATERIALIZED VIEW gold.fact_medication
COMMENT 'One row per medication order, with dates, costs and reason'
AS
SELECT
  m.medication_order_id,
  m.patient_id,
  m.encounter_id,
  m.payer_id,
  CAST(date_format(to_date(m.start_ts), 'yyyyMMdd') AS INT) AS start_date_key,
  m.start_ts,
  m.stop_ts,
  m.is_active,
  m.rxnorm_code,
  m.description,
  m.dispenses,
  m.total_cost                                         AS pharmacy_cost,
  m.payer_coverage                                     AS payer_paid,
  m.total_cost - m.payer_coverage                      AS patient_responsibility,
  m.reason_icd10cm_code,
  coalesce(m.reason_condition_group, 'Other')          AS condition_group
FROM silver.medication m;


CREATE OR REFRESH MATERIALIZED VIEW gold.fact_claim
COMMENT 'One row per claim: type, payer, principal diagnosis, and charges, payments and outstanding balance from its transactions'
AS
WITH money AS (
  SELECT
    claim_id,
    sum(charge_amount)                                 AS total_charges,
    sum(payment_amount)                                AS total_payments,
    count_if(transaction_type = 'CHARGE')              AS charge_lines
  FROM silver.claim_transaction
  GROUP BY claim_id
)
SELECT
  c.claim_id,
  c.patient_id,
  c.encounter_id,
  c.provider_id,
  c.primary_payer_id                                   AS payer_id,
  CAST(date_format(c.service_date, 'yyyyMMdd') AS INT) AS service_date_key,
  c.service_date,
  c.primary_claim_type                                 AS claim_type,
  c.principal_diagnosis_icd10cm_code,
  c.principal_diagnosis_description,
  coalesce(m.charge_lines, 0)                          AS charge_lines,
  coalesce(m.total_charges, 0)                         AS total_charges,
  coalesce(m.total_payments, 0)                        AS total_payments,
  coalesce(c.primary_outstanding, 0) + coalesce(c.secondary_outstanding, 0) + coalesce(c.patient_outstanding, 0) AS total_outstanding,
  c.primary_status,
  c.patient_status
FROM silver.claim c
LEFT JOIN money m ON m.claim_id = c.claim_id;


CREATE OR REFRESH MATERIALIZED VIEW gold.fact_member_month
COMMENT 'One row per patient per month of insurance coverage in the reporting period (denominator for per-member-per-month measures)'
AS
WITH months AS (
  SELECT
    c.patient_id,
    c.payer_id,
    c.member_id,
    c.start_date,
    explode(sequence(date_trunc('MONTH', c.start_date)::date,
                     date_trunc('MONTH', coalesce(c.end_date, DATE '${as_of_date}'))::date,
                     INTERVAL 1 MONTH)) AS month_start
  FROM silver.coverage c
)
SELECT
  m.patient_id,
  m.month_start,
  CAST(date_format(m.month_start, 'yyyyMMdd') AS INT)  AS month_date_key,
  m.payer_id,
  py.payer_category,
  m.member_id
FROM months m
JOIN silver.patient p ON p.patient_id = m.patient_id
LEFT JOIN silver.payer py ON py.payer_id = m.payer_id
WHERE m.month_start BETWEEN DATE '${analysis_start_date}' AND DATE '${as_of_date}'
  AND (p.death_date IS NULL OR p.death_date >= m.month_start)
  AND py.payer_type <> 'self_pay'
-- If two coverage periods touch the same month, count the one that started most recently.
QUALIFY row_number() OVER (PARTITION BY m.patient_id, m.month_start ORDER BY m.start_date DESC) = 1;
