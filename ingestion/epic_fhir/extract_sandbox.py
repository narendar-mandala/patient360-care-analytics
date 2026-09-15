"""Extract patient-centric FHIR R4 data from the Epic sandbox to Bulk-FHIR-shaped NDJSON.

Output: <OUTPUT_ROOT>/extract_date=YYYY-MM-DD/run_id=<utc ts>/<ResourceType>.ndjson + _manifest.json
"""

import argparse
import datetime as dt
import json
import logging
import os
from collections import defaultdict
from pathlib import Path

from dotenv import load_dotenv

from epic_auth import EpicBackendAuth
from fhir_client import FhirClient, FhirRequestError

HERE = Path(__file__).parent
REPO_ROOT = HERE.parent.parent

log = logging.getLogger("extract_sandbox")

# Epic requires a category (or code) for Observation and DocumentReference searches.
PATIENT_QUERIES: list[tuple[str, dict]] = [
    ("Encounter", {}),
    ("Condition", {"category": "problem-list-item"}),
    ("Condition", {"category": "encounter-diagnosis"}),
    ("Observation", {"category": "laboratory"}),
    ("Observation", {"category": "vital-signs"}),
    ("MedicationRequest", {}),
    ("Procedure", {}),
    ("AllergyIntolerance", {}),
    ("Immunization", {}),
    ("DocumentReference", {"category": "clinical-note"}),
    ("Coverage", {}),
    ("ExplanationOfBenefit", {}),
]


class NdjsonSink:
    """Collect resources by type, de-duplicated on id, then write one file per type."""

    def __init__(self):
        self.resources: dict[str, dict[str, dict]] = defaultdict(dict)

    def add(self, resource: dict) -> None:
        self.resources[resource["resourceType"]][resource["id"]] = resource

    def write(self, out_dir: Path) -> dict[str, int]:
        out_dir.mkdir(parents=True, exist_ok=True)
        counts = {}
        for rtype, by_id in sorted(self.resources.items()):
            with open(out_dir / f"{rtype}.ndjson", "w", encoding="utf-8") as f:
                for res in by_id.values():
                    f.write(json.dumps(res, separators=(",", ":")) + "\n")
            counts[rtype] = len(by_id)
        return counts


def encounter_references(encounter: dict) -> set[str]:
    refs = set()
    for p in encounter.get("participant", []):
        if ref := p.get("individual", {}).get("reference"):
            refs.add(ref)
    for loc in encounter.get("location", []):
        if ref := loc.get("location", {}).get("reference"):
            refs.add(ref)
    if ref := encounter.get("serviceProvider", {}).get("reference"):
        refs.add(ref)
    return refs


def resolve_patient_ids(client: FhirClient, config: dict) -> list[str]:
    ids = []
    for entry in config["patients"]:
        label = entry.get("label", "")
        if pid := entry.get("id"):
            if pid.startswith("REPLACE"):
                continue
            ids.append(pid)
        elif search := entry.get("search"):
            matches = [r["id"] for r in client.search("Patient", search)]
            if not matches:
                log.warning("No sandbox patient matched %s %s", label, search)
            ids.extend(matches)
    return list(dict.fromkeys(ids))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=HERE / "config" / "test_patients.json", type=Path)
    parser.add_argument("--patient-id", action="append", default=[], help="FHIR Patient id (repeatable); bypasses config")
    parser.add_argument("--check-auth", action="store_true", help="Only obtain a token and exit")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    load_dotenv(HERE / ".env")

    auth = EpicBackendAuth(
        client_id=os.environ.get("EPIC_CLIENT_ID", ""),
        private_key_path=HERE / os.environ.get("EPIC_PRIVATE_KEY_PATH", "keys/privatekey.pem"),
        token_url=os.environ["EPIC_TOKEN_URL"],
        jwks_path=HERE / os.environ.get("EPIC_JWKS_PATH", "keys/jwks.json"),
    )
    auth.get_token()
    log.info("Obtained access token")
    if args.check_auth:
        return

    client = FhirClient(os.environ["EPIC_FHIR_BASE_URL"], auth)
    started = dt.datetime.now(dt.timezone.utc)

    patient_ids = args.patient_id or resolve_patient_ids(client, json.loads(args.config.read_text()))
    if not patient_ids:
        raise SystemExit("No patients to extract; fill config/test_patients.json or pass --patient-id")

    sink = NdjsonSink()
    failures: list[dict] = []
    references: set[str] = set()

    for pid in patient_ids:
        log.info("Patient %s", pid)
        try:
            sink.add(client.read("Patient", pid))
        except FhirRequestError as exc:
            failures.append({"query": f"Patient/{pid}", "status": exc.status, "error": str(exc)})
            continue

        for rtype, extra in PATIENT_QUERIES:
            query = {"patient": pid, **extra}
            try:
                n = 0
                for res in client.search(rtype, query):
                    sink.add(res)
                    n += 1
                    if rtype == "Encounter":
                        references |= encounter_references(res)
                log.info("  %-20s %-40s %d", rtype, json.dumps(extra), n)
            except FhirRequestError as exc:
                log.warning("  %-20s %-40s FAILED (%s)", rtype, json.dumps(extra), exc.status)
                failures.append({"query": rtype, "params": query, "status": exc.status, "error": str(exc)[:300]})

    for ref in sorted(references):
        try:
            sink.add(client.read_reference(ref))
        except FhirRequestError as exc:
            failures.append({"query": ref, "status": exc.status, "error": str(exc)[:300]})

    out_dir = REPO_ROOT / os.environ.get("OUTPUT_ROOT", "data/raw/epic_fhir") / f"extract_date={started:%Y-%m-%d}" / f"run_id={started:%Y%m%dT%H%M%SZ}"
    counts = sink.write(out_dir)
    manifest = {
        "source_system": "epic_fhir_sandbox",
        "fhir_base_url": os.environ["EPIC_FHIR_BASE_URL"],
        "started_utc": started.isoformat(),
        "finished_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "patient_ids": patient_ids,
        "resource_counts": counts,
        "failures": failures,
    }
    (out_dir / "_manifest.json").write_text(json.dumps(manifest, indent=2))
    log.info("Wrote %s resources to %s (%d failed queries)", sum(counts.values()), out_dir, len(failures))


if __name__ == "__main__":
    main()
