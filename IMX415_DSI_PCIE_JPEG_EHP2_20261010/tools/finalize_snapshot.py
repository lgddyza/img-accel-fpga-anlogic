"""Create checksums for the clean fixed snapshot, excluding build caches."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    manifest = json.loads((ROOT/"manifest.json").read_text())
    for entry in manifest["files"]:
        assert sha(ROOT/entry["path"]) == entry["sha256"], entry["path"]
    verified = json.loads((ROOT/"reports/verification/project_validation.json").read_text())
    assert verified["all_copied_hashes_match"]
    assert "EHP2_CLEAN_ELABORATE_PASS" in (ROOT/"reports/verification/td_elaborate_console.log").read_text(encoding="utf-8")
    assert "PASS EHP2 eight modes" in (ROOT/"reports/verification/small_simulate.log").read_text(encoding="utf-8")
    summary = {"version": "EHP2 2026-10-10", "project_references": 106, "design_dependencies": 143,
               "source_copy_verified": True, "td_load_elaboration_passed": True,
               "eight_mode_small_regression_passed": True, "original_bit_copied_unchanged": True,
               "synthesis_route_bitgen_rerun": False, "source_project_retained": True,
               "bit_sha256": manifest["bit_sha256"], "compressed_bit_sha256": manifest["compressed_bit_sha256"]}
    (ROOT/"reports/verification/summary.json").write_text(json.dumps(summary, indent=2))
    files = sorted(p for p in ROOT.rglob("*") if p.is_file()
                   and "build" not in p.relative_to(ROOT).parts
                   and "__pycache__" not in p.parts
                   and p.name != "CHECKSUMS.sha256" and p.suffix != ".pyc")
    data = "".join(f"{sha(path)}  {path.relative_to(ROOT).as_posix()}\n" for path in files)
    (ROOT/"CHECKSUMS.sha256").write_text(data, encoding="ascii")
    for line in data.splitlines():
        digest, name = line.split("  ", 1)
        assert sha(ROOT/name) == digest
    print(json.dumps({"files_checksummed": len(files), "snapshot_bytes": sum(p.stat().st_size for p in files),
                      **summary}, indent=2))


if __name__ == "__main__":
    main()
