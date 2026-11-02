"""Release OBS1 only when current managed synthesis, routing and timing pass."""
from pathlib import Path
import difflib,hashlib,json,re,shutil,subprocess,sys
from record_str4_results import stages,resources
ROOT=Path(__file__).resolve().parents[1]
SYN=ROOT/'dual_imx415_gray_demo_Runs/syn_1'
PHY=ROOT/'dual_imx415_gray_demo_Runs/phy_1'
RELEASE=ROOT/'release/OBS1_20261026'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    inputs=json.loads((ROOT/'build/resource_inputs.json').read_text())
    for x in inputs:
        if sha(ROOT/x['path'])!=x['sha256']: raise SystemExit('Changed build input: '+x['path'])
    integrity=json.loads((ROOT/'build/source_integrity.json').read_text())
    if integrity['errors'] or integrity.get('synthesis_project_check',{}).get('errors',['missing']):
        raise SystemExit('Effective synthesis source registration is not verified')
    result=dict(revision='OBS1',build='0x4f425331',board_tested=False,
        project='dual_imx415_gray_demo.al',top='dual_imx415_top',device='PH1A90SEG324-2',
        synthesis=stages(SYN,('read_design','opt_rtl','opt_gate')),
        physical=stages(PHY,('opt_place','opt_route','bitgen')),
        synthesis_resources=resources(SYN/'dual_imx415_gray_demo_gate.area'),
        physical_resources=resources(PHY/'dual_imx415_gray_demo_phy.area'))
    # Physical strategy changes are saved in .al after gate mapping. Verify
    # all HDL/constraint hashes against the pre-strategy record separately.
    gate_inputs=json.loads((ROOT/'build/obs1_initial_inputs.json').read_text())
    for x in gate_inputs:
        if x['path']!='dual_imx415_gray_demo.al' and sha(ROOT/x['path'])!=x['sha256']:
            raise SystemExit('Changed synthesized input: '+x['path'])
    result['gate_input_record_sha256']=sha(ROOT/'build/obs1_initial_inputs.json')
    if result['synthesis']['read_design']['begin']<max((ROOT/x['path']).stat().st_mtime for x in inputs if x['path']!='dual_imx415_gray_demo.al'):
        raise SystemExit('Synthesis predates inputs')
    if result['physical']['opt_place']['begin']<result['synthesis']['opt_gate']['end']:
        raise SystemExit('Physical build predates synthesis')
    syn=(SYN/'run.log').read_text()
    for module in ('v2_feature_observer','v2_pcie_endpoint','dual_imx415_top'):
        if 'elaborate module '+module not in syn: raise SystemExit('Not elaborated: '+module)
    timing_path=PHY/'dual_imx415_gray_demo_pr.timing'
    timing=timing_path.read_text()
    result['base_managed_timing']={k:float(re.search(r'\b'+k+r':\s*([-\d.]+)ns',timing)[1]) for k in ('SWNS','STNS','HWNS','HTNS')}
    compressed=PHY/'dual_imx415_gray_demo_compress.bit'
    bit=compressed if compressed.exists() and compressed.stat().st_mtime>=result['physical']['bitgen']['begin'] else PHY/'dual_imx415_gray_demo.bit'
    polish=ROOT/'build/obs1_polish'
    polish_log=ROOT/'build/obs1_polish_run.log'
    use_polish=False
    if polish_log.exists():
        log=polish_log.read_text(encoding='utf-8-sig',errors='replace')
        use_polish=('OBS1_POLISH_COMPLETE_NO_PROGRAMMING' in log and 'OBS1_POLISH_FAIL:' not in log
                    and (polish/'route.db').stat().st_mtime>(PHY/'dual_imx415_gray_demo_pr.db').stat().st_mtime)
    if use_polish:
        timing_path=polish/'route.timing';timing=timing_path.read_text()
        result['physical_resources']=resources(polish/'route.area')
        result['supplementary_optimization']=dict(log_sha256=sha(polish_log),
            imported_managed_route_sha256=sha(PHY/'dual_imx415_gray_demo_pr.db'),
            final_route_sha256=sha(polish/'route.db'),script_sha256=sha(ROOT/'tools/polish_observer.tcl'))
        compressed=polish/'dual_imx415_OBS1_compress_compress.bit'
        bit=compressed if compressed.exists() else polish/'dual_imx415_OBS1_compress.bit'
    result['timing']={k:float(re.search(r'\b'+k+r':\s*([-\d.]+)ns',timing)[1]) for k in ('SWNS','STNS','HWNS','HTNS')}
    result['timing']['coverage_percent']=float(re.search(r'STA coverage\s*:\s*([\d.]+)%',timing)[1])
    if 'Confidence          : Routed' not in timing or any(result['timing'][k]<0 for k in ('SWNS','STNS','HWNS','HTNS')):
        raise SystemExit('Routed setup/hold not closed; bitstream not released')
    if result['physical_resources']['slice']['percent']>85 or result['physical_resources']['eram']['used']>230:
        raise SystemExit('Resource review limit exceeded')
    result['tests']={}
    for name,marker in (('feature_observer','PASS full1080p frame 4'),('observer_protocol','PASS strict thresholds'),
                        ('endpoint_control','PASS AXI-Lite'),('header','PASS DJP2'),('dual_preproc','PASS gray-only')):
        p=ROOT/'build'/f'{name}.log';text=p.read_text()
        if marker not in text or 'FATAL' in text: raise SystemExit('Failed simulation: '+name)
        result['tests'][name]=sha(p)
    # Verify every changed RTL file and retain a readable diff from frozen STR5.
    baseline=ROOT.parent/'DUAL_IMX415_PCIE_JPEG_GRAY_DEMO_20261024'
    patch=[]
    for p in sorted((ROOT/'rtl').glob('*')):
        if p.suffix not in ('.v','.vh'): continue
        old=baseline/'rtl'/p.name
        if not old.exists() or sha(p)!=sha(old):
            patch.extend(difflib.unified_diff(old.read_text().splitlines(True) if old.exists() else [],
                p.read_text().splitlines(True),fromfile='STR5/rtl/'+p.name,tofile='OBS1/rtl/'+p.name))
    if bit.stat().st_mtime<result['physical']['bitgen']['begin']: raise SystemExit('Stale bitstream')
    RELEASE.mkdir(parents=True,exist_ok=True)
    suffix='_compress' if 'compress' in bit.stem else ''
    target=RELEASE/f'dual_imx415_OBS1_20261026{suffix}.bit';shutil.copy2(bit,target)
    result['bitstream']=dict(path=target.relative_to(ROOT).as_posix(),bytes=target.stat().st_size,sha256=sha(target))
    result['physical_increment_vs_STR5']={k:result['physical_resources'][k]['used']-v for k,v in (('slice',50483),('eram',203),('dsp',81))}
    (RELEASE/'rtl_changes.patch').write_text(''.join(patch),encoding='utf-8')
    for folder,files in ((SYN,('run.log','dual_imx415_gray_demo.prj','dual_imx415_gray_demo_gate.area')),
                         (PHY,('run.log','dual_imx415_gray_demo_phy.area','dual_imx415_gray_demo_pr.timing','dual_imx415_gray_demo_phy.ts'))):
        dest=RELEASE/folder.name;dest.mkdir(exist_ok=True)
        for name in files: shutil.copy2(folder/name,dest/name)
    if polish_log.exists():
        dest=RELEASE/'polish';dest.mkdir(exist_ok=True)
        for p in polish.iterdir():
            if p.suffix in ('.area','.timing','.ts','.txt'): shutil.copy2(p,dest/p.name)
        shutil.copy2(polish_log,dest/'run.log')
        shutil.copy2(ROOT/'tools/polish_observer.tcl',dest/'polish_observer.tcl')
        result['supplementary_attempt_used']=use_polish
    initial=ROOT/'build/obs1_initial_phy'
    dest=RELEASE/'initial_managed';dest.mkdir(exist_ok=True)
    for name in ('run.log','dual_imx415_gray_demo_phy.area','dual_imx415_gray_demo_pr.timing','dual_imx415_gray_demo_phy.ts'):
        shutil.copy2(initial/name,dest/name)
    for name in ('resource_inputs.json','obs1_initial_inputs.json','source_integrity.json','feature_observer.log','observer_protocol.log','endpoint_control.log','header.log','dual_preproc.log','host_compat.patch','host_compat_tests.log'):
        shutil.copy2(ROOT/'build'/name,RELEASE/name)
    release_doc=(ROOT/'OBS1_README.md').read_text(encoding='utf-8').replace(
        '../road_damage_yolov8n/feature_observer_20261026/REPORT.md','experiment/REPORT.md')
    (RELEASE/'OBS1_README.md').write_text(release_doc,encoding='utf-8')
    software=ROOT.parent/'road_damage_yolov8n/feature_observer_20261026'
    experiment=RELEASE/'experiment';experiment.mkdir(exist_ok=True)
    for name in ('REPORT.md','settings.json','summary.json','score_model.json','score_rules.txt','model_search.json',
                 'per_case.csv','cases.json','score_summary.png','features.py','analyze.py','experiment.py','board_batch.cpp','render_comparisons.py'):
        shutil.copy2(software/name,experiment/name)
    shutil.copytree(software/'examples',experiment/'examples',dirs_exist_ok=True)
    (experiment/'board').mkdir(exist_ok=True)
    for name in ('before.json','after.json','environment.json','results.jsonl'):
        shutil.copy2(software/'board'/name,experiment/'board'/name)
    runtime=RELEASE/'host_compat'
    shutil.copytree(ROOT/'host_compat',runtime,dirs_exist_ok=True,
        ignore=shutil.ignore_patterns('__pycache__','build','dist'))
    result['runtime_payload_sha256']=sha(runtime/'rk_payload.zip')
    result['physical_strategy']='TimingHigh'
    (RELEASE/'validation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    manifest={p.relative_to(RELEASE).as_posix():sha(p) for p in sorted(RELEASE.rglob('*'))
              if p.is_file() and p.name!='MANIFEST.json'}
    (RELEASE/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))

if __name__=='__main__': main()
