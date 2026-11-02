from pathlib import Path
import argparse,hashlib,json,re
ROOT=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--record',action='store_true');ap.add_argument('--from-gate',action='store_true');args=ap.parse_args()
out=ROOT/'build/rtl_hsfix';out.mkdir(exist_ok=True)
manifest=out/'inputs.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
project=ROOT/'dual_imx415_hsfix.al'
paths={project,*[ROOT/x for x in re.findall(r'<File Path="([^"]+)"',project.read_text(encoding='utf-8'))]}
paths.update((ROOT/'rtl').glob('*.vh'))
paths.update([ROOT/'tools/build_hsfix.tcl'])
if (ROOT/'tools/resume_hsfix.tcl').exists():paths.add(ROOT/'tools/resume_hsfix.tcl')
if args.from_gate:
 # Reuse synthesis only if every recorded input except the corrected SDC is
 # byte-identical. Keep the gate input manifest and DB hash for provenance.
 previous=json.loads(manifest.read_text())
 changed=[x['path'].replace('\\','/') for x in previous if sha(ROOT/x['path'])!=x['sha256']]
 if changed!=['uisrc/04_pin/timing.sdc']:raise SystemExit('Unexpected gate-source changes: '+repr(changed))
 (out/'gate_inputs.json').write_text(json.dumps(previous,indent=2))
 (out/'gate_provenance.json').write_text(json.dumps(dict(gate_sha256=sha(out/'gate.db'),changed_inputs=changed,reason='Only reset-entry SDC selectors changed; all synthesized RTL is identical.'),indent=2))
if args.record:
 manifest.write_text(json.dumps([dict(path=str(p.relative_to(ROOT)),sha256=sha(p)) for p in sorted(paths)],indent=2))
errors=[]
for x in json.loads(manifest.read_text()):
 p=ROOT/x['path']
 if not p.exists() or sha(p)!=x['sha256']:errors.append(x['path'])
v1=ROOT.parent/'IMX415_DSI_PCIE_JPEG_EHP2_DSI_FIX_20261016'
original=json.loads((ROOT/'docs/v1_source_manifest.json').read_text(encoding='utf-8-sig'))
for x in original:
 p=v1/x['path']
 if not p.exists() or sha(p)!=x['sha256']:errors.append('V1:'+x['path'])
result=dict(registered_inputs=len(paths),v1_files_checked=len(original),errors=errors)
(out/'integrity.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
if errors:raise SystemExit(1)
