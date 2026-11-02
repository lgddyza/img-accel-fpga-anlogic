"""Hash registered HDL, constraints and include files before TD reads them."""
from pathlib import Path
import argparse,hashlib,json,re
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--verify',action='store_true')
args=parser.parse_args();manifest=ROOT/'build/resource_inputs.json'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
if args.verify:
    items=json.loads(manifest.read_text(encoding='utf-8'))
    changed=[x['path'] for x in items if not (ROOT/x['path']).is_file() or digest(ROOT/x['path'])!=x['sha256']]
    if changed:raise SystemExit('Build inputs changed during TD run: '+repr(changed))
    print(f'PASS {len(items)} resource-build input hashes unchanged')
else:
    project=ROOT/'dual_imx415_gray_demo.al'
    if not project.is_file():project=ROOT/'dual_imx415.al'
    paths={project,*[ROOT/x for x in re.findall(r'<File Path="([^"]+)"',project.read_text(encoding='utf-8'))]}
    paths.update((ROOT/'rtl').glob('*.vh'))
    paths.update([ROOT/'tools/check_resources.tcl',ROOT/'tools/record_build_inputs.py'])
    items=[{'path':p.relative_to(ROOT).as_posix(),'sha256':digest(p)} for p in sorted(paths)]
    manifest.write_text(json.dumps(items,indent=2),encoding='utf-8')
    print(f'Recorded {len(items)} resource-build input hashes')
