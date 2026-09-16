# 02 - Epic FHIR sandbox setup

Goal: pull real R4 resources from Epic's public sandbox using the **Backend Services** (system-to-system) OAuth flow. This is the same pattern a hospital data platform uses for scheduled extracts.

> Epic's developer portal UI changes from time to time. If a label below doesn't match what you see, follow the intent of the step. The OAuth mechanics (JWT client assertion, RS384) are standards-based and stable.

## Step 1: Create a developer account

1. Go to **https://fhir.epic.com** and sign up for a free account.
2. Confirm your email and log in.

## Step 2: Generate your key pair (locally)

Run from `ingestion\epic_fhir` (PowerShell). Call the venv's Python directly rather than `activate`: Windows' default execution policy blocks `Activate.ps1`.

```powershell
cd ingestion\epic_fhir
python -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
.venv\Scripts\python.exe generate_keys.py
```

This creates, all git-ignored:

| File | Purpose | Share it? |
|---|---|---|
| `keys/privatekey.pem` | Signs your JWT client assertions | **Never** |
| `keys/jwks.json` | Public key as a JWK Set (with `kid`) | Yes, public by design |
| `keys/publickey509.pem` | Public key as an X.509 cert | Yes, public by design |

## Step 3: Register the app

In the portal: **Build Apps → Create**.

| Field | Value |
|---|---|
| Application Name | `Healthcare Data Platform - Analytics Extract` |
| Application Audience | **Backend Systems** |
| Incoming APIs | See list below. Pick the **R4** versions. |
| Public key | Epic asks for a **Non-Production JWK Set URL**. Host `keys/jwks.json` at any public HTTPS URL, such as a GitHub Pages site or a public gist's *raw* URL. It is only a public key. If your form offers a certificate upload instead, upload `publickey509.pem`. |
| FHIR version | R4 |
| Summary / description | Short description of the analytics use case |

Suggested **Incoming APIs** (R4):

- Patient.Read, Patient.Search
- Encounter.Read, Encounter.Search
- Condition.Search (Problems, Encounter Diagnosis)
- Observation.Search (Labs, Vital Signs)
- MedicationRequest.Search
- Procedure.Search
- AllergyIntolerance.Search
- Immunization.Search
- DocumentReference.Search (Clinical Notes)
- Coverage.Search
- ExplanationOfBenefit.Search (if listed)
- Practitioner.Read, Organization.Read, Location.Read
- Bulk Data: Group export kick-off / status / file request (if listed)

Accept the terms and click **Save & Ready for Sandbox**. Copy the **Non-Production Client ID**.

> A new client ID can take a while to become active in the sandbox, anywhere from minutes to many hours. An `invalid_client` error right after registration usually just means "wait".

## Step 4: Configure and extract

```powershell
copy .env.example .env                                   # paste EPIC_CLIENT_ID
copy config\test_patients.example.json config\test_patients.json
.venv\Scripts\python.exe extract_sandbox.py --check-auth # token only
.venv\Scripts\python.exe extract_sandbox.py              # full extract
```

Put Epic's published **sandbox test patients** in `config/test_patients.json`. Search for "test patients" in the fhir.epic.com documentation to find the list. Each entry is either:

- a known FHIR ID: `{"id": "..."}`
- search parameters: `{"search": {"family": "...", "given": "...", "birthdate": "YYYY-MM-DD"}}`

Output:

```text
data/raw/epic_fhir/extract_date=2026-09-13/run_id=20260913T101500Z/
  Patient.ndjson  Encounter.ndjson  Condition.ndjson  Observation.ndjson ...
  _manifest.json   ← counts, failed queries, timing
```

## Epic behaviors the client handles

| Behavior | Handling |
|---|---|
| JWT must be RS384, `iss`=`sub`=client ID, `aud`=token URL, `exp` ≤ 5 min | `epic_auth.py` |
| Tokens are short-lived | Cached and refreshed 60 s before expiry; one forced refresh on 401 |
| `Observation` search requires `category` (or `code`) | Separate `laboratory` / `vital-signs` queries |
| Search bundles contain `OperationOutcome` entries (warnings) | Logged, not written as data |
| Paging via `Bundle.link[relation=next]` | Followed until exhausted |
| APIs not enabled on your app return 403 | Recorded in the manifest; extract continues |
| 429 / 5xx | Exponential backoff, honoring `Retry-After` |

## Why the sandbox alone isn't enough

The sandbox has only a handful of patients. It shows that the **integration** works, but it cannot show **scale**. The volume comes from Synthea, which writes the same NDJSON shape (see [01_data_sourcing_strategy.md](01_data_sourcing_strategy.md)).
