"""Profile a Synthea run: row counts and sizes per CSV / NDJSON file, plus headline realism checks.

Usage: python profile_output.py <run_dir>
Writes <run_dir>/_profile.json. Standard library only.
"""

import csv
import json
import sys
from collections import Counter
from pathlib import Path


def count_lines(path: Path) -> int:
    with open(path, "rb") as f:
        return sum(1 for _ in f)


def human(nbytes: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if nbytes < 1024:
            return f"{nbytes:.1f} {unit}"
        nbytes /= 1024
    return f"{nbytes:.1f} TB"


def encounter_mix(csv_dir: Path) -> dict:
    path = csv_dir / "encounters.csv"
    if not path.exists():
        return {}
    with open(path, newline="", encoding="utf-8") as f:
        return dict(Counter(row.get("ENCOUNTERCLASS", "?") for row in csv.DictReader(f)).most_common())


def main() -> None:
    run_dir = Path(sys.argv[1])
    profile = {"run_dir": str(run_dir), "csv": {}, "fhir_ndjson": {}}

    for sub, key, pattern, header_rows in (("csv", "csv", "*.csv", 1), ("fhir", "fhir_ndjson", "*.ndjson", 0)):
        for path in sorted((run_dir / sub).glob(pattern)):
            size = path.stat().st_size
            profile[key][path.name] = {"rows": count_lines(path) - header_rows, "bytes": size, "size": human(size)}

    profile["encounter_class_mix"] = encounter_mix(run_dir / "csv")
    (run_dir / "_profile.json").write_text(json.dumps(profile, indent=2))

    for key in ("csv", "fhir_ndjson"):
        print(f"\n{key}")
        for name, stats in sorted(profile[key].items(), key=lambda kv: -kv[1]["rows"]):
            print(f"  {name:<35} {stats['rows']:>14,}  {stats['size']:>10}")
    print("\nencounter class mix")
    for cls, n in profile["encounter_class_mix"].items():
        print(f"  {cls:<20} {n:>12,}")


if __name__ == "__main__":
    main()
