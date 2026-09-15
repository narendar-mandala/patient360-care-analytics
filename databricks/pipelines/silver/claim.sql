-- Silver: claim
-- One row per claim. In Synthea there's a claim for each encounter and for each medication order.
--
-- Transformations:
--   1. Keep the latest copy of each claim.
--   2. Cast dates and amounts from text.
--   3. Decode the claim type (1 = Professional, 2 = Institutional) for the primary and secondary payer.
--   4. Diagnoses: a claim lists up to 8 SNOMED codes. Each one is looked up in the reference mapping,
--      and the principal diagnosis is the first code in the list that has an ICD-10-CM code.
--      (Synthea sometimes lists something that isn't billable first, like "Full-time employment".)
--      All ICD-10-CM codes are kept in order, without repeats, in diagnosis_icd10cm_codes.
--   5. Keep status (BILLED or CLOSED) and the amount still owed, for each of primary insurance,
--      secondary insurance and the patient.
--
-- Checks (rows are kept; failures are counted):
--   has_patient, has_encounter, has_principal_diagnosis

CREATE OR REFRESH MATERIALIZED VIEW silver.claim (
  CONSTRAINT has_patient EXPECT (patient_id IS NOT NULL),
  CONSTRAINT has_encounter EXPECT (encounter_id IS NOT NULL),
  CONSTRAINT has_principal_diagnosis EXPECT (principal_diagnosis_icd10cm_code IS NOT NULL)
)
COMMENT 'One row per claim: patient, encounter, provider, payers, claim type, diagnoses, status and outstanding amounts'
AS
WITH claims AS (
  SELECT *
  FROM bronze.synthea_claims
  QUALIFY row_number() OVER (PARTITION BY Id ORDER BY _ingested_at DESC) = 1
),

-- One row per diagnosis on a claim, with its position (1 to 8) and ICD-10-CM code.
claim_diagnoses AS (
  SELECT
    d.claim_id,
    d.position,
    d.snomed_code,
    ref.icd10cm_code,
    ref.snomed_description
  FROM (
    SELECT c.Id AS claim_id, x.pos + 1 AS position, x.code AS snomed_code
    FROM claims c
    LATERAL VIEW posexplode(array(c.DIAGNOSIS1, c.DIAGNOSIS2, c.DIAGNOSIS3, c.DIAGNOSIS4,
                                  c.DIAGNOSIS5, c.DIAGNOSIS6, c.DIAGNOSIS7, c.DIAGNOSIS8)) x AS pos, code
  ) d
  LEFT JOIN bronze.ref_snomed_icd10cm_conditions ref ON ref.snomed_code = d.snomed_code
  WHERE d.snomed_code IS NOT NULL
),

diagnosis_summary AS (
  SELECT
    claim_id,
    min_by(snomed_code, position) FILTER (WHERE icd10cm_code IS NOT NULL)        AS principal_snomed_code,
    min_by(icd10cm_code, position) FILTER (WHERE icd10cm_code IS NOT NULL)       AS principal_icd10cm_code,
    min_by(snomed_description, position) FILTER (WHERE icd10cm_code IS NOT NULL) AS principal_description,
    array_distinct(transform(array_sort(collect_list(struct(position, snomed_code))), x -> x.snomed_code)) AS snomed_codes,
    array_distinct(transform(array_sort(collect_list(struct(position, icd10cm_code)) FILTER (WHERE icd10cm_code IS NOT NULL)), x -> x.icd10cm_code)) AS icd10cm_codes
  FROM claim_diagnoses
  GROUP BY claim_id
)

SELECT
  c.Id                                                 AS claim_id,
  'synthea'                                            AS source_system,
  c.PATIENTID                                          AS patient_id,
  c.APPOINTMENTID                                      AS encounter_id,
  c.PROVIDERID                                         AS provider_id,
  c.REFERRINGPROVIDERID                                AS referring_provider_id,
  c.SUPERVISINGPROVIDERID                              AS supervising_provider_id,
  nullif(c.PRIMARYPATIENTINSURANCEID, '0')             AS primary_payer_id,
  nullif(c.SECONDARYPATIENTINSURANCEID, '0')           AS secondary_payer_id,

  CASE c.HEALTHCARECLAIMTYPEID1 WHEN '1' THEN 'Professional' WHEN '2' THEN 'Institutional' END AS primary_claim_type,
  CASE c.HEALTHCARECLAIMTYPEID2 WHEN '1' THEN 'Professional' WHEN '2' THEN 'Institutional' END AS secondary_claim_type,

  to_date(try_cast(c.SERVICEDATE AS TIMESTAMP))        AS service_date,
  to_date(try_cast(c.CURRENTILLNESSDATE AS TIMESTAMP)) AS current_illness_date,

  dx.principal_snomed_code                             AS principal_diagnosis_snomed_code,
  dx.principal_icd10cm_code                            AS principal_diagnosis_icd10cm_code,
  dx.principal_description                             AS principal_diagnosis_description,
  dx.snomed_codes                                      AS diagnosis_snomed_codes,
  dx.icd10cm_codes                                     AS diagnosis_icd10cm_codes,

  c.STATUS1                                            AS primary_status,
  c.STATUS2                                            AS secondary_status,
  c.STATUSP                                            AS patient_status,
  try_cast(c.OUTSTANDING1 AS DECIMAL(12, 2))           AS primary_outstanding,
  try_cast(c.OUTSTANDING2 AS DECIMAL(12, 2))           AS secondary_outstanding,
  try_cast(c.OUTSTANDINGP AS DECIMAL(12, 2))           AS patient_outstanding,
  to_date(try_cast(c.LASTBILLEDDATE1 AS TIMESTAMP))    AS primary_last_billed_date,
  to_date(try_cast(c.LASTBILLEDDATEP AS TIMESTAMP))    AS patient_last_billed_date,

  c._run_id                                            AS run_id,
  c._ingested_at                                       AS bronze_ingested_at
FROM claims c
LEFT JOIN diagnosis_summary dx ON dx.claim_id = c.Id;
