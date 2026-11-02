"""Record current inputs after TD has saved its actual project registration."""
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = root / 'DEMO_MANIFEST.json'
data = json.loads(manifest.read_text(encoding='utf-8-sig'))
paths = {entry['path'] for entry in data['files']}
paths.discard('tools/check_str2_managed.tcl')
paths.add('tools/STR2_MANAGED_BUILD.md')
paths.add('OBS1_README.md')
project = root/'dual_imx415_gray_demo.al'
section = re.search(r'<Source_Files>.*?</Source_Files>', project.read_text(encoding='utf-8-sig'), re.S).group()
paths.update(node.attrib['Path'] for node in ET.fromstring(section.replace('&', '&amp;')).iter('File'))
paths.update(p.relative_to(root).as_posix() for folder in ('rtl', 'rk', 'sim', 'tools')
             for p in (root / folder).glob('*') if p.suffix in ('.v', '.vh', '.sv', '.py', '.tcl', '.c'))
paths.update(('third_party/mjpegZero/rtl/mjpegzero_enc_top.v',
              'third_party/mjpegZero/rtl/jfif_writer.v',
              'uisrc/01_rtl/jpeg_byte_packer.v',
              'uisrc/01_rtl/jpeg_gray4_axis_cdc.v',
              'uisrc/01_rtl/jpeg_triple_tile_branch.v'))
if (root / 'RTL_STR2_20261025.md').is_file():paths.add('RTL_STR2_20261025.md')
if (root/'RTL_STR3_20261025.md').is_file():
    paths.add('RTL_STR3_20261025.md')
if (root/'RTL_STR4_20261025.md').is_file():
    paths.add('RTL_STR4_20261025.md')
if (root/'RTL_STR5_20261025.md').is_file():
    paths.add('RTL_STR5_20261025.md')
stream_build = re.search(r"16'h028c:\s*rdata<=32'h([0-9a-fA-F]{8})", (root/'rtl/v2_endpoint_body.vh').read_text()).group(1)
data.update(date='2026-10-26', stream_build='0x'+stream_build)
data['files'] = [dict(path=path, sha256=hashlib.sha256((root/path).read_bytes()).hexdigest())
                 for path in sorted(paths)]
manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(f'Recorded {len(paths)} current files; this is an input record, not a test result')
