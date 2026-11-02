"""Generate a namespaced simulation reference from the preserved 14 Oct sources."""
import re
import shutil
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / 'build/dsi_color_diagnosis/legacy_reference.v'
out.parent.mkdir(parents=True, exist_ok=True)
frozen = root / 'sim/reference_20261014/legacy_reference.v'
if frozen.exists():
    shutil.copyfile(frozen, out)
    print(f'Using frozen 14 Oct legacy reference: {frozen}')
    raise SystemExit(0)
old = root.parent / 'IMX415_DSI_PCIE_JPEG_EHP2_DSI_COLOR_20261014'
files = sorted((old / 'uisrc/03_ip/ui_isp').rglob('*.v'))
files = [p for p in files if 'ui_ram_' not in str(p) and 'divider_gate' not in str(p)]
files.append(old / 'uisrc/03_ip/ui_csi_raw/ui_image_correction.v')
sources = [p.read_text(encoding='utf-8-sig') for p in files]
names = set(re.findall(r'\bmodule\s+(\w+)', '\n'.join(sources)))
pattern = re.compile(r'\b(' + '|'.join(sorted(names, key=len, reverse=True)) + r')\b')
out.write_text('\n'.join(pattern.sub(lambda m: 'legacy_' + m[0], s) for s in sources), encoding='utf-8')
print(f'Generated reference from {len(files)} preserved RTL files: {out}')
