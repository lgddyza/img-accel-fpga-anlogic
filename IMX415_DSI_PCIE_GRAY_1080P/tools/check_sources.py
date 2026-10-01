"""Static AST/manifest checks only. Does not invoke TD, a compiler or simulator."""
from pathlib import Path
import re
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / ".tools" / "pyverilog"))
from pyverilog.vparser.parser import VerilogParser
from pyverilog.vparser import ast as vast


def walk(node):
    yield node
    for child in node.children():
        yield from walk(child)


def preprocess(text, defines):
    """Only local object macros/conditionals, deliberately no external program."""
    text = re.sub(r"/\*[\s\S]*?\*/|//[^\n]*", lambda m: "\n" * m.group().count("\n"), text)
    active = True
    stack = []
    output = []
    for line in text.splitlines():
        m = re.match(r"\s*`(\w+)(?:\s+(.*))?$", line)
        if m:
            directive, value = m.group(1), (m.group(2) or "").strip()
            if directive in ("ifdef", "ifndef"):
                condition = (value in defines) == (directive == "ifdef")
                stack.append([active, condition])
                active = active and condition
            elif directive == "elsif":
                parent, taken = stack[-1]
                condition = not taken and value in defines
                stack[-1][1] |= condition
                active = parent and condition
            elif directive == "else":
                parent, taken = stack[-1]
                active = parent and not taken
                stack[-1][1] = True
            elif directive == "endif":
                active = stack.pop()[0]
            elif directive == "define" and active:
                parts = value.split(None, 1)
                defines[parts[0]] = parts[1] if len(parts) > 1 else ""
            elif directive in ("timescale", "default_nettype"):
                pass
            elif directive == "include" and active:
                raise AssertionError("Unexpected include in static-check inputs: " + line)
            output.append("")
            continue
        if active:
            line = re.sub(r"`(\w+)", lambda m: defines[m.group(1)], line)
            output.append(line)
        else:
            output.append("")
    assert not stack, "Unbalanced preprocessor directives"
    return "\n".join(output)


def main():
    # TD's .al dialect uses unescaped P&R and a non-XML element name.
    project_file = ROOT / "fpga_prj.al"
    raw = project_file.read_text(encoding="utf-8-sig")
    xml = raw.replace("P&R", "P&amp;R").replace(
        "BitgenProperty::GeneralOption", "BitgenProperty_GeneralOption")
    project = ET.fromstring(xml)
    assert project.findtext("./Name") == project_file.stem, \
        "TD project name must match the .al filename"
    paths = [f.attrib["Path"] for f in project.findall("./Source_Files/*/File")]
    assert len(paths) == len(set(paths)), "Duplicate project source path"
    for path in paths:
        project_path = Path(path)
        assert not project_path.is_absolute() and ".." not in project_path.parts, \
            f"Non-local project source path: {path}"
        assert (ROOT / path).is_file(), f"Missing project source: {path}"
    assert project.findtext("./TOP_MODULE/MODULE") == "system_top"
    print(f"PASS manifest: {len(paths)} source/IP/constraint files exist")

    fresh = sorted((ROOT / "uisrc/01_rtl").glob("*.v"))
    files = fresh + [
        ROOT / "uisrc/03_ip/ui_isp/ui_isp_top.v",
        ROOT / "uisrc/03_ip/ui_isp/ui_awb/ui_awb.v",
        ROOT / "uisrc/03_ip/ui_isp/ui_data128_96/ui_data128_96.v",
        ROOT / "uisrc/03_ip/ui_isp/ui_data96_128/ui_data96_128.v",
        ROOT / "uisrc/03_ip/ui_isp/ui_saturation_adj/ui_Saturation_adj.v",
        ROOT / "uisrc/03_ip/vid_pipeline/axis_stream_fifo.v",
        ROOT / "uisrc/03_ip/ui_dbuf/sfifo/sfifo.v",
        ROOT / "uisrc/03_ip/sgdma/sgdma_subsys.v",
        ROOT / "al_ip/sgdma_pll.v",
    ]
    defines = {}
    preprocess((ROOT / "uisrc/01_rtl/para_def.vh").read_text(), defines)
    modules = {}
    with tempfile.TemporaryDirectory(prefix="gray_static_") as temp:
        parser = VerilogParser(outputdir=temp, debug=False)
        for path in files:
            text = preprocess(path.read_text(encoding="utf-8-sig", errors="replace"), dict(defines))
            if path.name == "sfifo.v":
                # The untouched vendor RAM model contains SV task syntax not
                # supported by Pyverilog; check the public FIFO wrapper only.
                text = text.split("endmodule", 1)[0] + "endmodule\n"
            parser.lexer.reset_lineno()
            try:
                ast = parser.parse(text)
            except Exception:
                print(f"FAIL Verilog syntax: {path}")
                raise
            for module in ast.description.definitions:
                if isinstance(module, vast.ModuleDef):
                    assert module.name not in modules, f"Duplicate module: {module.name}"
                    modules[module.name] = module
            print(f"PASS syntax: {path.relative_to(ROOT)}")

    checked = 0
    local_module_names = set()
    for path in fresh:
        text = preprocess(path.read_text(encoding="utf-8-sig", errors="replace"), dict(defines))
        local_module_names.update(re.findall(r"\bmodule\s+(\w+)", text))
    for name in sorted(local_module_names):
        module = modules[name]
        for instance in (n for n in walk(module) if isinstance(n, vast.Instance)):
            if instance.module not in modules:
                continue  # vendor IP is not elaborated by this checker
            target = modules[instance.module]
            ports = {p.first.name if isinstance(p, vast.Ioport) else p.name
                     for p in target.portlist.ports}
            connected = [p.portname for p in instance.portlist]
            assert len(connected) == len(set(connected)), f"Duplicate port: {instance.name}"
            assert set(connected) <= ports, f"Unknown port: {instance.name}: {set(connected)-ports}"
            port_decls = list(walk(target.portlist))
            for item in target.items:
                if isinstance(item, vast.Decl):
                    port_decls.extend(item.list)
            for decl in port_decls:
                if isinstance(decl, vast.Input):
                    assert decl.name in connected, f"Unconnected input {instance.name}.{decl.name}"
            checked += 1
    print(f"PASS named connections: {checked} local instances")

    demo = ROOT.parent / "demo"
    base = (demo / "uisrc/01_rtl/system_top.v").read_text(encoding="utf-8-sig")
    merged = (ROOT / "uisrc/01_rtl/system_top.v").read_text(encoding="utf-8-sig")
    assert "u_ui_video_osd" not in merged, \
        "Resource-safe build must not instantiate the BRAM-heavy OSD"
    assert "dsi_status_overlay #(.PIXEL_CLOCK_HZ(50000000)) u_dsi_status" in merged
    assert re.search(r"(?m)^module dsi_status_overlay\b", merged), \
        "DSI overlay must be defined in the already-registered system_top.v"
    assert ".I_data(S_ud_rtdata)" in merged
    assert ".O_data(S_osd_data)" in merged
    assert re.search(r"(?m)^module dsi_color_downscale\b", merged)
    assert "dsi_color_downscale u_dsi_color_downscale" in merged
    assert ".I_tdata(S_dsi_gray_rgb32)" in merged
    assert ".I_tvalid(S_ISP_O_tvalid)" in merged
    assert "dsi_gray_pack4 u_dsi_gray_pack4" in merged
    assert re.search(r"(?m)^module dsi_gray_pack4\b", merged)
    assert "assign O_tdata[pixel*32 +: 32] = {8'd0,y,y,y}" in merged
    assert ".isp_data(S_ISP_O_tdata)" in merged
    assert "dsi_frame_awb" not in merged
    assert "u_dsi_color_saturation" not in merged
    for setting in (".W_XSIZE", ".W_XSTRIDE"):
        assert re.search(rf"{re.escape(setting)}\s*\(256\s*\)", merged)
    for setting in (".W_YSIZE", ".R_YSIZE"):
        assert re.search(rf"{re.escape(setting)}\s*\(576\s*\)", merged)
    assert re.search(r"\.R_XSTRIDE\s*\(1024\s*\)", merged)
    assert re.search(r"\.I_R_tready\s*\(S_dsi_image_active\)", merged)
    isp = (ROOT / "uisrc/03_ip/ui_isp/ui_isp_top.v").read_text(encoding="utf-8-sig")
    demo_isp = (demo / "uisrc/03_ip/ui_isp/ui_isp_top.v").read_text(encoding="utf-8-sig")
    assert "X_ui_Saturation_adj" not in isp, \
        "The shared ISP output must bypass the demo grayscale/saturation stage"
    assert re.search(r"assign\s+O_tdata\s*=\s*Color_O_tdata_128", isp)
    assert re.search(r"assign\s+O_tvalid\s*=\s*Brightness_O_tvalid", isp)
    assert re.search(r"\.I_tdata\s*\(Brightness_O_tdata\s*\)", isp)
    assert re.search(r"\.ADJUST_VAL\s*\(130\s*\)\s*,\s*\.GRAYSCALE_ENABLE\s*\(1'b1\s*\)", demo_isp)
    # The older ui_capture_monitor was intentionally adapted for 256 beats
    # and 576 rows; only the unused demo OSD remains byte-identical.
    for name in ("ui_video_osd",):
        pattern = rf"module {name}\b[\s\S]*?endmodule"
        assert re.search(pattern, base).group() == re.search(pattern, merged).group(), name
    expected_changes = {
        "uisrc/01_rtl/system_top.v",
        "uisrc/03_ip/ui_isp/ui_isp_top.v",
        "uisrc/03_ip/vid_pipeline/axis_stream_fifo.v",
        "uisrc/03_ip/ui_dbuf/sfifo/sfifo.v",
        "uisrc/03_ip/ui_dbuf/uidbuf.v",
        "uisrc/04_pin/fpga_pin.adc",
        "uisrc/04_pin/timing.sdc",
    }
    compared = 0
    for path in (demo / "uisrc").rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(demo).as_posix()
        if relative in expected_changes:
            continue
        counterpart = ROOT / path.relative_to(demo)
        assert counterpart.is_file(), f"Missing copied demo file: {relative}"
        assert path.read_bytes() == counterpart.read_bytes(), \
            f"Unexpected change to demo source: {relative}"
        compared += 1
    print(f"PASS unchanged demo camera/MIPI/DDR/DSI tree: {compared} files")
    print("NOT RUN by this checker: HDL simulation, synthesis, place/route, bit generation, board test")


if __name__ == "__main__":
    main()
