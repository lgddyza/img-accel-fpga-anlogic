"""Load/elaborate this project with TD; keep generated logs under build/."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--td", type=Path, default=Path("F:/FPGA/AnLu/bin/td_commands_prompt.exe"))
    args = parser.parse_args()
    logs = ROOT/"build/td_verify"
    logs.mkdir(parents=True, exist_ok=True)
    evidence = ROOT/"reports/verification/td_elaborate_console.log"
    before = set(ROOT.glob("td_*.log*"))
    with evidence.open("w", encoding="utf-8") as output:
        result = subprocess.run([str(args.td), (ROOT/"tools/verify_td_project.tcl").as_posix()],
                                cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                text=True, timeout=180)
    for source in set(ROOT.glob("td_*.log*"))-before:
        target = logs/source.name
        assert source.parent.resolve() == ROOT.resolve() and target.parent.resolve() == logs.resolve()
        if not target.exists():
            source.rename(target)
    text = evidence.read_text(encoding="utf-8", errors="replace")
    if result.returncode or "EHP2_CLEAN_ELABORATE_PASS" not in text:
        raise RuntimeError(f"TD verification failed; see {evidence}")
    print("PASS TD project load and complete top-level elaboration")
    print("NOT RUN: synthesis, place/route or bit generation")


if __name__ == "__main__":
    main()
