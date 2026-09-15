-- Gold: fact_index_admission
-- One row per inpatient discharge that counts toward the 30-day readmission measure, with the
-- outcome (was the patient readmitted?) and the LACE risk score.
--
-- How it's built (definitions from docs/04_requirements.md, section 6):
--
--   1. Inpatient stays: Inpatient encounters, with the facility, reason and costs.
--
--   2. Planned stays: a stay is planned if it matches ref_planned_admission_rules, by a procedure done
--      during the stay (for example chemotherapy), the admission type, or the reason for the stay.
--
--   3. Index stays (the ones that count): patient 18 or older at admission, alive at discharge,
--      discharged inside the reporting period, and not a stay for cancer treatment, recovery after
--      surgery, or a primary psychiatric or substance use diagnosis (ICD-10-CM F codes).
--      (Transfers and against-medical-advice discharges can't be excluded yet: Synthea doesn't record
--      discharge disposition. That comes in Phase 2.)
--
--   4. Readmission: the first unplanned inpatient admission 1 to 30 days after discharge.
--      Post-discharge ED visit: an ED visit 1 to 30 days after discharge that didn't lead to admission.
--      follow_up_complete = at least 30 days have passed by the reporting date, so the outcome is known.
--      Only those rows count in readmission rates.
--
--   5. LACE score = L + A + C + E, with points from ref_lace_points:
--        L  length of stay in days
--        A  3 points if the patient came in through the ED (an ED visit that started within 12 hours before admission)
--        C  Charlson comorbidity score from the patient's conditions active at admission (ref_charlson_weights)
--        E  ED visits in the 6 months before admission
--
--   6. Risk tier (decision D-4): among all index stays, the top 10% of LACE scores are High,
--      the next 20% Medium, and the rest Low.

CREATE OR REFRESH MATERIALIZED VIEW gold.fact_index_admission (
  CONSTRAINT lace_score_in_range EXPECT (lace_score BETWEEN 0 AND 19),
  CONSTRAINT readmission_after_discharge EXPECT (days_to_readmission IS NULL OR days_to_readmission BETWEEN 1 AND 30)
)
COMMENT 'One row per index inpatient stay: readmission and post-discharge ED outcome, LACE score and risk tier'
AS
WITH stays AS (
  SELECT
    e.encounter_id,
    e.patient_id,
    e.organization_id                                  AS facility_id,
    e.payer_id,
    e.start_ts,
    e.end_ts,
    e.start_date                                       AS admit_date,
    e.end_date                                         AS discharge_date,
    greatest(datediff(e.end_date, e.start_date), 1)    AS length_of_stay_days,
    e.encounter_type_code,
    e.reason_snomed_code,
    e.reason_icd10cm_code,
    e.reason_description,
    coalesce(e.reason_condition_group, 'Other')        AS condition_group,
    e.total_claim_cost                                 AS medical_cost,
    e.payer_coverage                                   AS payer_paid
  FROM silver.encounter e
  WHERE e.care_setting = 'Inpatient'
),

-- Step 2: which stays are planned, and why.
planned AS (
  SELECT s.encounter_id, min(r.category) AS planned_category
  FROM stays s
  JOIN bronze.ref_planned_admission_rules r
    ON (r.match_on = 'encounter_code' AND r.code = s.encounter_type_code)
    OR (r.match_on = 'reason_code'    AND r.code = s.reason_snomed_code)
  GROUP BY s.encounter_id
  UNION ALL
  SELECT s.encounter_id, min(r.category)
  FROM stays s
  JOIN silver.procedure p ON p.encounter_id = s.encounter_id
  JOIN bronze.ref_planned_admission_rules r ON r.match_on = 'procedure_code' AND r.code = p.snomed_code
  GROUP BY s.encounter_id
),

stays_flagged AS (
  SELECT
    s.*,
    pl.planned_category,
    pl.planned_category IS NOT NULL                    AS is_planned,
    floor(months_between(s.admit_date, pt.birth_date) / 12) AS age_at_admission,
    pt.death_date
  FROM stays s
  JOIN silver.patient pt ON pt.patient_id = s.patient_id
  LEFT JOIN (SELECT encounter_id, min(planned_category) AS planned_category FROM planned GROUP BY encounter_id) pl
    ON pl.encounter_id = s.encounter_id
),

-- Step 3: index stays.
index_stays AS (
  SELECT *
  FROM stays_flagged
  WHERE age_at_admission >= 18
    AND (death_date IS NULL OR death_date > discharge_date)
    AND discharge_date BETWEEN DATE '${analysis_start_date}' AND DATE '${as_of_date}'
    AND coalesce(planned_category, '') NOT IN ('cancer_treatment', 'post_surgical_care')
    AND coalesce(reason_icd10cm_code, '') NOT LIKE 'F%'
),

-- Step 4: outcomes.
readmissions AS (
  SELECT
    i.encounter_id,
    min_by(r.encounter_id, r.start_ts)                 AS readmission_encounter_id,
    min(datediff(r.admit_date, i.discharge_date))      AS days_to_readmission,
    min_by(r.medical_cost, r.start_ts)                 AS readmission_cost,
    min_by(r.payer_paid, r.start_ts)                   AS readmission_payer_paid
  FROM index_stays i
  JOIN stays_flagged r
    ON r.patient_id = i.patient_id
   AND r.encounter_id <> i.encounter_id
   AND NOT r.is_planned
   AND datediff(r.admit_date, i.discharge_date) BETWEEN 1 AND 30
  GROUP BY i.encounter_id
),

-- ED visits that didn't turn into an admission (no inpatient stay starting within 12 hours of the ED visit).
ed_visits_not_admitted AS (
  SELECT ed.*
  FROM silver.encounter ed
  LEFT ANTI JOIN stays s
    ON s.patient_id = ed.patient_id
   AND s.start_ts BETWEEN ed.start_ts - INTERVAL 1 HOUR AND ed.start_ts + INTERVAL 12 HOURS
  WHERE ed.care_setting = 'Emergency'
),

post_discharge_ed AS (
  SELECT i.encounter_id, count(*) AS post_discharge_ed_visits
  FROM index_stays i
  JOIN ed_visits_not_admitted ed
    ON ed.patient_id = i.patient_id
   AND datediff(ed.start_date, i.discharge_date) BETWEEN 1 AND 30
  GROUP BY i.encounter_id
),

-- Step 5: LACE components.
came_through_ed AS (
  SELECT DISTINCT i.encounter_id
  FROM index_stays i
  JOIN silver.encounter ed
    ON ed.patient_id = i.patient_id
   AND ed.care_setting = 'Emergency'
   AND ed.start_ts BETWEEN i.start_ts - INTERVAL 12 HOURS AND i.start_ts + INTERVAL 1 HOUR
),

prior_ed_visits AS (
  SELECT i.encounter_id, count(*) AS ed_visits_6_months
  FROM index_stays i
  JOIN silver.encounter ed
    ON ed.patient_id = i.patient_id
   AND ed.care_setting = 'Emergency'
   AND ed.start_ts >= i.start_ts - INTERVAL 180 DAYS
   AND ed.start_ts < i.start_ts - INTERVAL 12 HOURS
  GROUP BY i.encounter_id
),

charlson AS (
  -- Distinct Charlson categories among conditions active on the admission date, with their weights.
  -- If both diabetes categories are present, only "diabetes with complications" counts.
  SELECT
    encounter_id,
    sum(weight) - CASE WHEN array_contains(collect_set(charlson_category), 'diabetes_complicated')
                        AND array_contains(collect_set(charlson_category), 'diabetes_uncomplicated') THEN 1 ELSE 0 END AS charlson_score
  FROM (
    SELECT DISTINCT i.encounter_id, c.charlson_category, CAST(w.weight AS INT) AS weight
    FROM index_stays i
    JOIN silver.condition c
      ON c.patient_id = i.patient_id
     AND c.charlson_category IS NOT NULL
     AND c.start_date <= i.admit_date
     AND (c.stop_date IS NULL OR c.stop_date >= i.admit_date)
    JOIN bronze.ref_charlson_weights w ON w.charlson_category = c.charlson_category
  )
  GROUP BY encounter_id
),

lace_inputs AS (
  SELECT
    i.*,
    ced.encounter_id IS NOT NULL                       AS came_through_ed,
    coalesce(ch.charlson_score, 0)                     AS charlson_score,
    coalesce(pe.ed_visits_6_months, 0)                 AS ed_visits_6_months
  FROM index_stays i
  LEFT JOIN came_through_ed ced ON ced.encounter_id = i.encounter_id
  LEFT JOIN charlson ch ON ch.encounter_id = i.encounter_id
  LEFT JOIN prior_ed_visits pe ON pe.encounter_id = i.encounter_id
),

lace_points AS (
  SELECT component, CAST(lower_bound AS INT) AS lower_bound, CAST(upper_bound AS INT) AS upper_bound, CAST(points AS INT) AS points
  FROM bronze.ref_lace_points
),

-- Look up the points for each component in its band.
lace AS (
  SELECT
    li.*,
    pl.points                                          AS lace_l,
    CASE WHEN li.came_through_ed THEN 3 ELSE 0 END     AS lace_a,
    pc.points                                          AS lace_c,
    pe.points                                          AS lace_e
  FROM lace_inputs li
  LEFT JOIN lace_points pl ON pl.component = 'L' AND li.length_of_stay_days BETWEEN pl.lower_bound AND pl.upper_bound
  LEFT JOIN lace_points pc ON pc.component = 'C' AND li.charlson_score BETWEEN pc.lower_bound AND pc.upper_bound
  LEFT JOIN lace_points pe ON pe.component = 'E' AND li.ed_visits_6_months BETWEEN pe.lower_bound AND pe.upper_bound
),

scored AS (
  SELECT
    l.*,
    l.lace_l + l.lace_a + l.lace_c + l.lace_e          AS lace_score,
    percent_rank() OVER (ORDER BY l.lace_l + l.lace_a + l.lace_c + l.lace_e DESC) AS lace_percentile_from_top
  FROM lace l
)

SELECT
  s.encounter_id,
  s.patient_id,
  s.facility_id,
  s.payer_id,
  CAST(date_format(s.admit_date, 'yyyyMMdd') AS INT)   AS admit_date_key,
  CAST(date_format(s.discharge_date, 'yyyyMMdd') AS INT) AS discharge_date_key,
  s.admit_date,
  s.discharge_date,
  s.age_at_admission,
  s.length_of_stay_days,
  s.reason_icd10cm_code,
  s.reason_description,
  s.condition_group,
  s.condition_group IN ('AMI', 'HF', 'PNEUMONIA', 'COPD') AS is_hrrp_condition,
  s.is_planned,
  s.planned_category,
  s.medical_cost,
  s.payer_paid,

  s.discharge_date <= DATE '${as_of_date}' - INTERVAL 30 DAYS AS follow_up_complete,
  r.encounter_id IS NOT NULL                           AS is_readmitted_30_days,
  r.readmission_encounter_id,
  r.days_to_readmission,
  r.readmission_cost,
  r.readmission_payer_paid,
  coalesce(ped.post_discharge_ed_visits, 0)            AS post_discharge_ed_visits,

  s.came_through_ed,
  s.charlson_score,
  s.ed_visits_6_months,
  s.lace_l,
  s.lace_a,
  s.lace_c,
  s.lace_e,
  s.lace_score,
  CASE WHEN s.lace_percentile_from_top < 0.10 THEN 'High'
       WHEN s.lace_percentile_from_top < 0.30 THEN 'Medium'
       ELSE 'Low' END                                  AS risk_tier
FROM scored s
LEFT JOIN readmissions r ON r.encounter_id = s.encounter_id
LEFT JOIN post_discharge_ed ped ON ped.encounter_id = s.encounter_id;
