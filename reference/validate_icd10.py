"""Check every ICD-10-CM code in the condition crosswalk against the CMS code file.

Usage: python reference/validate_icd10.py <path to icd10cm_codes_YYYY.txt>
Exits non-zero if any code is missing or not billable.
"""

import csv
import sys
from pathlib import Path

CROSSWALK = Path(__file__).parent / "snomed_icd10cm_conditions.csv"


def load_cms_codes(path: Path) -> dict[str, str]:
    with open(path, encoding="latin-1") as f:
        return {line[:7].strip(): line[8:].strip() for line in f if line.strip()}


def main() -> None:
    cms = load_cms_codes(Path(sys.argv[1]))
    rows = list(csv.DictReader(open(CROSSWALK, encoding="utf-8")))
    invalid = [r for r in rows if r["icd10cm_code"] and r["icd10cm_code"].replace(".", "") not in cms]
    mapped = sum(1 for r in rows if r["icd10cm_code"])
    print(f"{mapped} mapped codes checked against {len(cms):,} CMS billable codes")
    for r in invalid:
        print(f"  INVALID {r['icd10cm_code']:<9} {r['snomed_code']} {r['snomed_description']}")
    sys.exit(1 if invalid else 0)


if __name__ == "__main__":
    main()
