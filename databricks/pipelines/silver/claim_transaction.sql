-- Silver: claim_transaction
-- One row per money movement on a claim line. Synthea records four kinds:
--   CHARGE       the original charge for a service
--   PAYMENT      a payment against a charge, by a payer or the patient
--   TRANSFERIN / TRANSFEROUT   the remaining balance moving to secondary insurance or the patient
--
-- Transformations:
--   1. Keep the latest copy of each transaction.
--   2. Cast dates, units and amounts from text.
--   3. Decode who a transfer went to (1 = primary insurance, 2 = secondary insurance, p = patient)
--      and the payment method.
--   4. Add a billing code for the service line: CPT/HCPCS for procedures (ref_procedure_code_map)
--      and CPT for vaccines (ref_immunization_cvx_cpt). Visit and medication lines keep only
--      their original code.
--
-- Checks (rows are kept; failures are counted):
--   has_claim, known_transaction_type, amounts_not_negative

CREATE OR REFRESH MATERIALIZED VIEW silver.claim_transaction (
  CONSTRAINT has_claim EXPECT (claim_id IS NOT NULL),
  CONSTRAINT known_transaction_type EXPECT (transaction_type IN ('CHARGE', 'PAYMENT', 'ADJUSTMENT', 'TRANSFERIN', 'TRANSFEROUT')),
  CONSTRAINT amounts_not_negative EXPECT (coalesce(charge_amount, 0) >= 0 AND coalesce(payment_amount, 0) >= 0)
)
COMMENT 'One row per claim transaction: charges, payments and balance transfers, with billing codes'
AS
WITH transactions AS (
  SELECT *
  FROM bronze.synthea_claims_transactions
  QUALIFY row_number() OVER (PARTITION BY ID ORDER BY _ingested_at DESC) = 1
)

SELECT
  t.ID                                                 AS transaction_id,
  'synthea'                                            AS source_system,
  t.CLAIMID                                            AS claim_id,
  try_cast(t.CHARGEID AS INT)                          AS charge_line_number,
  t.PATIENTID                                          AS patient_id,
  t.APPOINTMENTID                                      AS encounter_id,
  t.PROVIDERID                                         AS provider_id,
  t.PLACEOFSERVICE                                     AS place_of_service_organization_id,
  t.PATIENTINSURANCEID                                 AS member_id,

  t.TYPE                                               AS transaction_type,
  CASE t.METHOD WHEN 'CC' THEN 'Credit Card' WHEN 'ECHECK' THEN 'Electronic Check'
                ELSE initcap(t.METHOD) END             AS payment_method,
  CASE t.TRANSFERTYPE WHEN '1' THEN 'Primary Insurance' WHEN '2' THEN 'Secondary Insurance'
                      WHEN 'p' THEN 'Patient' END      AS transfer_to,

  to_date(try_cast(t.FROMDATE AS TIMESTAMP))           AS from_date,
  to_date(try_cast(t.TODATE AS TIMESTAMP))             AS to_date,

  t.PROCEDURECODE                                      AS service_code,
  coalesce(pm.cpt_hcpcs, imm.cpt_code)                 AS billing_code,
  t.MODIFIER1                                          AS modifier_1,
  t.MODIFIER2                                          AS modifier_2,
  try_cast(t.UNITS AS INT)                             AS units,
  try_cast(t.UNITAMOUNT AS DECIMAL(12, 2))             AS unit_amount,

  CASE WHEN t.TYPE = 'CHARGE' THEN try_cast(t.AMOUNT AS DECIMAL(12, 2)) END AS charge_amount,
  try_cast(t.PAYMENTS AS DECIMAL(12, 2))               AS payment_amount,
  try_cast(t.ADJUSTMENTS AS DECIMAL(12, 2))            AS adjustment_amount,
  try_cast(t.TRANSFERS AS DECIMAL(12, 2))              AS transfer_amount,
  try_cast(t.OUTSTANDING AS DECIMAL(12, 2))            AS outstanding_amount,

  t._run_id                                            AS run_id,
  t._ingested_at                                       AS bronze_ingested_at
FROM transactions t
LEFT JOIN bronze.ref_procedure_code_map pm ON pm.snomed_code = t.PROCEDURECODE
LEFT JOIN bronze.ref_immunization_cvx_cpt imm ON imm.cvx_code = t.PROCEDURECODE;
