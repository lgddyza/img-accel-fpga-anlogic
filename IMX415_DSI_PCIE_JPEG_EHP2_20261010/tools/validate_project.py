"""Verify the relocated source set, dependency files and pinned EHP2 bit."""
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    raw = (ROOT/"fpga_prj_jpeg.al").read_text(encoding="utf-8-sig")
    project = ET.fromstring(raw.replace("P&R", "P&amp;R").replace(
        "BitgenProperty::GeneralOption", "BitgenProperty_GeneralOption"))
    assert Path(project.attrib["Path"]).resolve() == ROOT.resolve(), "TD project root needs relocation"
    assert project.findtext("Name") == "fpga_prj_jpeg"
    assert project.findtext("TOP_MODULE/MODULE") == "system_top"
    assert project.findtext("HardWare/Device") == "PH1A90SEG324"
    paths = [node.attrib["Path"] for node in project.findall("./Source_Files/*/File")]
    assert len(paths) == len(set(paths)) == 106
    for path in paths:
        reference = Path(path)
        assert not reference.is_absolute() and ".." not in reference.parts
        assert (ROOT/path).is_file(), path
    manifest = json.loads((ROOT/"manifest.json").read_text())
    for entry in manifest["files"]:
        assert sha(ROOT/entry["path"]) == entry["sha256"], f"File changed: {entry['path']}"
    for dep in manifest["memory_dependencies"]:
        assert (ROOT/dep["resolved"]).is_file()
    for ipc in (ROOT/p for p in paths if p.endswith(".ipc")):
        for node in ET.parse(ipc).getroot().findall("./GeneratedFiles/*"):
            if node.attrib.get("Enable") == "true":
                assert (ipc.parent/node.text.strip()).is_file(), (ipc, node.text)
    assert sha(ROOT/"output/fpga_prj_jpeg.bit") == manifest["bit_sha256"]
    assert sha(ROOT/"output/fpga_prj_jpeg_compress.bit") == manifest["compressed_bit_sha256"]
    preproc = (ROOT/"uisrc/01_rtl/gray_preprocess4.v").read_text(encoding="utf-8-sig")
    for name in ("gray_preprocess4", "gray_clahe4", "gray_sobel_guided4",
                 "gray_blackhat4", "gray_direction_open4"):
        assert re.search(rf"(?m)^module {name}\b", preproc)
    endpoint = (ROOT/"uisrc/01_rtl/system_top.v").read_text(encoding="utf-8-sig").lower().replace("_", "")
    assert "45485032" in endpoint and "000000ff" in endpoint
    report = {"project_references": len(paths), "dependency_files": manifest["design_dependency_count"],
              "all_copied_hashes_match": True, "enabled_ip_outputs_present": True,
              "memory_initializations_present": True, "bit_hashes_match": True,
              "design_sources_unchanged": True, "full_synthesis_route_rerun": False}
    out = ROOT/"reports/verification"
    out.mkdir(parents=True, exist_ok=True)
    (out/"project_validation.json").write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
