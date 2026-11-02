"""Check the frozen reference (when present) and current project registration."""
from pathlib import Path
import argparse,hashlib,json,re,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser()
ap.add_argument('--v1-root',type=Path,default=ROOT.parent/'IMX415_DSI_PCIE_JPEG_EHP2_DSI_FIX_20261016')
ap.add_argument('--run-project',type=Path,help='Check the actual TD-generated synthesis source list')
args=ap.parse_args()
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
errors=[]
v1_manifest_path=ROOT/'docs/v1_source_manifest.json'
project_manifest_path=ROOT/'DEMO_MANIFEST.json'
manifest=[]
if v1_manifest_path.is_file():
    manifest=json.loads(v1_manifest_path.read_text(encoding='utf-8-sig'))
    for entry in manifest:
        path=args.v1_root/entry['path']
        if not path.is_file() or sha(path)!=entry['sha256']:errors.append(str(path))
elif project_manifest_path.is_file():
    project_manifest=json.loads(project_manifest_path.read_text(encoding='utf-8-sig'))
    for entry in project_manifest.get('files',[]):
        path=ROOT/entry['path']
        if not path.is_file() or sha(path)!=entry['sha256']:
            errors.append('manifest mismatch: '+str(path))
project_path=ROOT/'dual_imx415_gray_demo.al'
if not project_path.is_file(): project_path=ROOT/'dual_imx415.al'
project=project_path.read_text(encoding='utf-8-sig')
source_section=re.search(r'<Source_Files>.*?</Source_Files>',project,re.S).group()
# TD uses a literal ampersand in its UsedInP&R attribute name value.
sources=ET.fromstring(source_section.replace('&','&amp;'))
entries={node.attrib['Path']:node for node in sources.iter('File')}
registered=list(entries)
for name in registered:
    if not (ROOT/name).is_file():errors.append('missing project file: '+name)
critical=[p.relative_to(ROOT).as_posix() for p in (ROOT/'rtl').glob('*.v')]
critical+=['rtl/v2_endpoint_body.vh']
critical+=[p.relative_to(ROOT).as_posix() for p in (ROOT/'uisrc/03_ip/mipi_csi_2').glob('*.v') if p.name!='sfifo.v']
# The active RX and JPEG paths now use v2_async_fifo. The old sfifo helper
# is allowed to be auto-excluded; it does not define an instantiated module.
critical+=['uisrc/01_rtl/'+name for name in
           ('jpeg_triple_tile_branch.v','jpeg_gray4_axis_cdc.v','jpeg_byte_packer.v',
            'jpeg_axil_config.v','gray4_to_yuyv4.v','gray_gauss4.v','gray_preprocess4.v')]
critical+=['uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg_37125.v',
           'uisrc/04_pin/fpga_pin.adc','uisrc/04_pin/timing.sdc']
registration=[]
for name in sorted(critical):
    node=entries.get(name)
    if node is None:
        if name.endswith('.vh'):
            included_by=[path for path in registered if path.endswith(('.v','.sv')) and
                         re.search(r'`include\s+"'+re.escape(name)+r'"',
                                   (ROOT/path).read_text(encoding='utf-8-sig'))]
            if included_by:
                registration.append({'path':name,'included_by':included_by})
                continue
        errors.append('unregistered required file: '+name)
        continue
    attrs={a.attrib['Name']:a.attrib['Val'] for a in node.iter('Attr')}
    order=attrs.get('CompileOrder')
    if order is None or not order.isdigit() or int(order)>=len(registered):
        errors.append(name+': invalid/out-of-range CompileOrder '+str(order))
    registration.append({'path':name,**{key:attrs.get(key) for key in
                                     ('AutoExcluded','UsedInSyn','UsedInP&R')}})
    if attrs.get('AutoExcluded','false')=='true':errors.append('required file auto-excluded: '+name)
    for key in ('UsedInSyn','UsedInP&R'):
        if attrs.get(key)!='true':errors.append(name+': '+key+' is not true')
run_project_check=None
if args.run_project:
    run_path=args.run_project.resolve()
    run_errors=[]
    if not run_path.is_file():
        run_errors.append('missing synthesis project: '+str(run_path))
    else:
        run_text=run_path.read_text(encoding='utf-8-sig')
        run_section=re.search(r'<Source_Files>.*?</Source_Files>',run_text,re.S).group()
        run_sources=ET.fromstring(run_section.replace('&','&amp;'))
        run_entries={(run_path.parent/node.attrib['Path']).resolve():node
                     for node in run_sources.iter('File')}
        for name,node in entries.items():
            expected={a.attrib['Name']:a.attrib['Val'] for a in node.iter('Attr')}
            if expected.get('AutoExcluded','false')=='true':continue
            actual_node=run_entries.get((ROOT/name).resolve())
            if actual_node is None:
                run_errors.append('synthesis source list missing: '+name)
                continue
            actual={a.attrib['Name']:a.attrib['Val'] for a in actual_node.iter('Attr')}
            for key,default in (('AutoExcluded','false'),('UsedInSyn','false'),
                                ('UsedInP&R','false'),('CompileOrder',None)):
                if actual.get(key,default)!=expected.get(key,default):
                    run_errors.append('synthesis source list '+name+': stale '+key)
    run_project_check={'path':str(run_path),'errors':run_errors}
    errors.extend(run_errors)
probe=ROOT/'build/resource_inputs.json'
checked=0
if probe.exists():
    for entry in json.loads(probe.read_text(encoding='utf-8-sig')):
        path=ROOT/entry['path']
        if not path.is_file() or sha(path)!=entry['sha256']:errors.append('changed since area probe: '+str(path))
        checked+=1
result={'reference_files_checked':len(manifest),'registered_project_files':len(registered),
        'required_file_registration':registration,
        'resource_probe_input_hashes_checked':checked,'errors':errors}
if run_project_check is not None:result['synthesis_project_check']=run_project_check
(ROOT/'build/source_integrity.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
if errors:raise SystemExit(1)
