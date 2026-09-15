"""Consistency checks for the reference (lookup) files, against a Synthea output folder.

Run: data_generation/.venv/Scripts/python -m pytest reference -q
(set SYNTHEA_CSV_DIR to point at a run's csv folder)
"""

import csv
import os
import re
from pathlib import Path

import duckdb
import pytest

REF = Path(__file__).parent
SYNTHEA_CSV_DIR = os.environ.get(
    "SYNTHEA_CSV_DIR",
    str(REF.parent / "data/raw/synthea/run_id=p1000_s42_massachusetts/csv"),
)


def read_ref(name: str) -> list[dict]:
    with open(REF / name, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def synthea_codes(file: str) -> dict[str, str]:
    path = Path(SYNTHEA_CSV_DIR) / file
    if not path.exists():
        pytest.skip(f"Synthea output not found at {path}")
    rows = duckdb.sql(f"select CODE, any_value(DESCRIPTION) from read_csv('{path.as_posix()}', all_varchar=true) group by CODE").fetchall()
    return dict(rows)


def test_condition_crosswalk_covers_every_synthea_condition():
    mapped = {r["snomed_code"] for r in read_ref("snomed_icd10cm_conditions.csv")}
    missing = set(synthea_codes("conditions.csv")) - mapped
    assert not missing, f"unmapped condition codes: {sorted(missing)}"


def test_condition_crosswalk_has_no_duplicate_codes():
    codes = [r["snomed_code"] for r in read_ref("snomed_icd10cm_conditions.csv")]
    assert len(codes) == len(set(codes))


def test_every_diagnosis_has_an_icd10_code():
    rows = read_ref("snomed_icd10cm_conditions.csv")
    missing = [r["snomed_description"] for r in rows if r["condition_class"] in ("diagnosis", "symptom", "history") and not r["icd10cm_code"]]
    assert not missing


def test_charlson_categories_are_known():
    weights = {r["charlson_category"] for r in read_ref("charlson_weights.csv")}
    used = {r["charlson_category"] for r in read_ref("snomed_icd10cm_conditions.csv") if r["charlson_category"]}
    assert used <= weights, used - weights


def test_every_synthea_procedure_resolves_to_a_billing_code():
    explicit = {r["snomed_code"]: r for r in read_ref("procedure_code_map.csv")}
    rules = sorted(read_ref("procedure_category_rules.csv"), key=lambda r: int(r["priority"]))
    for code, description in synthea_codes("procedures.csv").items():
        if code in explicit:
            continue
        assert any(re.search(r["description_regex"], description) for r in rules), (code, description)


def test_explicit_procedure_map_has_no_duplicates():
    codes = [r["snomed_code"] for r in read_ref("procedure_code_map.csv")]
    assert len(codes) == len(set(codes))


def test_every_immunization_has_a_cpt_code():
    mapped = {r["cvx_code"] for r in read_ref("immunization_cvx_cpt.csv")}
    missing = set(synthea_codes("immunizations.csv")) - mapped
    assert not missing, missing


def test_lace_bands_do_not_overlap():
    rows = read_ref("lace_points.csv")
    for component in "LACE":
        bands = sorted((int(r["lower_bound"]), int(r["upper_bound"])) for r in rows if r["component"] == component)
        for (_, prev_hi), (lo, _) in zip(bands, bands[1:]):
            assert lo == prev_hi + 1, (component, bands)


def test_every_synthea_payer_has_a_profile():
    path = Path(SYNTHEA_CSV_DIR) / "payers.csv"
    if not path.exists():
        pytest.skip("Synthea output not found")
    names = {n for (n,) in duckdb.sql(f"select NAME from read_csv('{path.as_posix()}', all_varchar=true)").fetchall()}
    profiled = {r["payer_name"] for r in read_ref("payer_profile.csv")}
    assert names <= profiled, names - profiled


def test_lab_reference_ranges_are_for_known_panel_codes():
    panel_codes = {r["loinc_code"] for r in read_ref("lab_panels.csv")}
    range_codes = {r["loinc_code"] for r in read_ref("lab_reference_ranges.csv")}
    assert range_codes <= panel_codes, range_codes - panel_codes
