"""Capture baseline JPEGs, then verify the timing fix preserves every byte."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
IVERILOG = ROOT.parent / ".tools/iverilog/bin/iverilog.exe"
VVP = IVERILOG.with_name("vvp.exe")
OUTPUT = ROOT / "tools/timingfix_sim"
RTL = [ROOT / "uisrc/03_ip/ui_dbuf/sfifo/sfifo.v"] + [
    ROOT / "uisrc/01_rtl" / name for name in (
        "gray4_to_yuyv4.v", "jpeg_gray4_axis_cdc.v", "jpeg_axil_config.v",
        "jpeg_byte_packer.v", "jpeg_triple_tile_branch.v")
] + sorted((ROOT / "third_party/mjpegZero/rtl").glob("*.v"))
CASES = {
    "ramp_q85": [],
    "wide_noise_q85": ["LARGE_TEST", "NOISE_TEST"],
    "wide_noise_q30": ["LARGE_TEST", "NOISE_TEST", "NOISE_Q30"],
}


def run_case(stage, name, top, defines):
    directory = OUTPUT / stage / name
    directory.mkdir(parents=True, exist_ok=True)
    executable = directory / "test.vvp"
    command = [str(IVERILOG), "-g2012", "-s", top, "-o", str(executable)]
    command += ["-D" + item for item in defines]
    command += [str(path) for path in RTL]
    command.append(str(ROOT / "sim" / (top + (".v" if top == "tb_jpeg_gray4_axis_cdc" else ".sv"))))
    for label, args in (("compile", command), ("simulate", [str(VVP), str(executable)])):
        result = subprocess.run(args, cwd=directory, text=True, capture_output=True, timeout=180)
        (directory / (label + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
        if result.returncode or "FATAL" in result.stdout:
            raise RuntimeError(f"{name} {label} failed: {result.stdout[-2000:]} {result.stderr[-2000:]}")
    print(f"PASS {stage} {name}: {result.stdout.strip()}", flush=True)
    return {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(directory.glob("*.jpg"))}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=("baseline", "candidate"))
    stage = parser.parse_args().stage
    hashes = {}
    for name, defines in CASES.items():
        hashes[name] = run_case(stage, name, "tb_jpeg_triple_tile_branch", ["FAST_ENC"] + defines)
        assert len(hashes[name]) == 3, f"Missing JPEG tile in {name}"
    if stage == "candidate":
        baseline = json.loads((OUTPUT / "baseline/hashes.json").read_text())
        assert hashes == baseline, "JPEG output differs from the original implementation"
        print("PASS all 9 JPEG outputs are byte-identical to the baseline", flush=True)
        for name, top in (
            ("cdc_frames_overflow", "tb_jpeg_gray4_axis_cdc"),
            ("cdc_faults", "tb_jpeg_gray4_axis_faults"),
            ("cdc_backpressure", "tb_jpeg_gray4_axis_backpressure"),
            ("continuous", "tb_jpeg_triple_continuous"),
        ):
            run_case(stage, name, top, [])
    (OUTPUT / stage / "hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")


if __name__ == "__main__":
    main()
