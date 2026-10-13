"""Generate independent references and run the existing EHP2 eight-mode test."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--iverilog", type=Path,
                        default=ROOT.parent/".tools/iverilog/bin/iverilog.exe")
    args = parser.parse_args()
    directory = ROOT/"build/sim/small"
    directory.mkdir(parents=True, exist_ok=True)
    executable = directory/"ehp2.vvp"
    steps = [
        ("vectors", [sys.executable, str(ROOT/"tools/prepare_enhance_vectors.py")]),
        ("compile", [str(args.iverilog), "-g2012", "-s", "tb_gray_enhance4", "-o", str(executable),
                      str(ROOT/"sim/tb_gray_enhance4.sv"), str(ROOT/"uisrc/01_rtl/gray_preprocess4.v"),
                      str(ROOT/"uisrc/01_rtl/gray_gauss4.v")]),
        ("simulate", [str(args.iverilog.with_name("vvp.exe")), str(executable)])]
    evidence = ROOT/"reports/verification"
    evidence.mkdir(parents=True, exist_ok=True)
    for name, command in steps:
        result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=90)
        output = result.stdout+result.stderr
        (evidence/f"small_{name}.log").write_text(output, encoding="utf-8")
        if result.returncode or "FATAL" in output:
            raise RuntimeError(output)
        if name == "simulate" and "PASS EHP2 eight modes" not in output:
            raise RuntimeError("Regression did not report PASS")
        print(name, output.strip(), flush=True)


if __name__ == "__main__":
    main()
