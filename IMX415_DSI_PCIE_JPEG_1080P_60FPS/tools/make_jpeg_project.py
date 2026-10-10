"""Build a separate TD project manifest with the triple-tile JPEG sources.

The pre-JPEG manifest is retained under archive_pre_jpeg for traceability.
The generated project always uses the directory containing this script's parent.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "archive_pre_jpeg" / "fpga_prj.pre_jpeg.al"
OUTPUT = ROOT / "fpga_prj_jpeg.al"
JPEG_SOURCES = [
    "uisrc/01_rtl/gray4_to_yuyv4.v",
    "uisrc/01_rtl/jpeg_gray4_axis_cdc.v",
    "uisrc/01_rtl/jpeg_axil_config.v",
    "uisrc/01_rtl/jpeg_byte_packer.v",
    "uisrc/01_rtl/jpeg_clk_pll.v",
    "uisrc/01_rtl/jpeg_triple_tile_branch.v",
    "third_party/mjpegZero/rtl/axi4_lite_regs.v",
    "third_party/mjpegZero/rtl/bitstream_packer.v",
    "third_party/mjpegZero/rtl/bram_sdp.v",
    "third_party/mjpegZero/rtl/dct_1d.v",
    "third_party/mjpegZero/rtl/dct_2d.v",
    "third_party/mjpegZero/rtl/huffman_encoder.v",
    "third_party/mjpegZero/rtl/input_buffer.v",
    "third_party/mjpegZero/rtl/jfif_writer.v",
    "third_party/mjpegZero/rtl/mjpegzero_enc_top.v",
    "third_party/mjpegZero/rtl/quantizer.v",
    "third_party/mjpegZero/rtl/rgb_to_ycbcr.v",
    "third_party/mjpegZero/rtl/zigzag_reorder.v",
]


def main():
    text = BASE.read_text(encoding="utf-8")
    text, count = re.subn(
        r'(<Project Version="[^"]+" Minor="[^"]+" Path=")[^"]+(">)',
        lambda match: f'{match.group(1)}{ROOT.as_posix()}{match.group(2)}',
        text,
        count=1,
    )
    if count != 1:
        raise RuntimeError("TD project root path not found")
    text, count = re.subn(r"<Name>fpga_prj</Name>", "<Name>fpga_prj_jpeg</Name>", text, count=1)
    if count != 1:
        raise RuntimeError("TD base project name not found")
    anchor = '            <File Path="uisrc/01_rtl/system_top.v">'
    if text.count(anchor) != 1:
        raise RuntimeError("system_top.v source entry not unique")
    if any(not (ROOT / source).is_file() for source in JPEG_SOURCES):
        raise RuntimeError("one or more JPEG RTL sources are missing")
    entries = []
    for order, source in enumerate(JPEG_SOURCES, 87):
        entries.append(
            f'            <File Path="{source}">\n'
            '                <FileInfo>\n'
            '                    <Attr Name="UsedInSyn" Val="true"/>\n'
            '                    <Attr Name="UsedInP&R" Val="true"/>\n'
            '                    <Attr Name="BelongTo" Val="design_1"/>\n'
            f'                    <Attr Name="CompileOrder" Val="{order}"/>\n'
            '                </FileInfo>\n'
            '            </File>\n'
        )
    text = text.replace(anchor, "".join(entries) + anchor, 1)
    sources = re.findall(r'<File Path="([^"]+)"', text)
    if len(sources) != len(set(sources)):
        raise RuntimeError("duplicate project source")
    if any(not (ROOT / source).exists() for source in sources):
        raise RuntimeError("project source path missing")
    OUTPUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {OUTPUT}: {len(sources)} source paths, {len(JPEG_SOURCES)} JPEG additions")


if __name__ == "__main__":
    main()
