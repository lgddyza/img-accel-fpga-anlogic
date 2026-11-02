"""Verify raw-page decoding and recovery protocol without the video hardware."""
from pathlib import Path
import json,sys,subprocess,difflib
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'rk'))
from feature_observer import decode,read_observations
gold=json.loads((ROOT/'build/observer_golden.json').read_text())
for raw in gold:
    packet=(1<<29)|(raw['samples']<<64)|(raw['luma_sum']<<82)|(raw['dark_count']<<107)|(raw['bright_count']<<125)|(raw['gradient_sum']<<143)
    for i,n in enumerate(raw['hist']): packet|=n<<(168+18*i)
    decoded=decode([(packet>>(32*i))&0xffffffff for i in range(16)])
    for name in ('samples','luma_sum','dark_count','bright_count','gradient_sum','hist'): assert decoded[name]==raw[name]
    assert list(decoded['features'].values())==raw['features']
assert read_observations(lambda _: (_ for _ in ()).throw(AssertionError('old bit page read')),0x53545235) is None
assert not decode([0]*16)['valid']
try: decode([1<<29,0,1]+[0]*13)
except ValueError: pass
else: raise AssertionError('Invalid active page was accepted')
BIN=ROOT.parent/'.tools/iverilog/bin';exe=ROOT/'build/observer_protocol.vvp'
subprocess.run([str(BIN/'iverilog.exe'),'-g2012','-s','tb_observer_protocol','-o',str(exe),'sim/tb_observer_protocol.sv','rtl/v2_feature_observer.v'],cwd=ROOT,check=True)
with (ROOT/'build/observer_protocol.log').open('w') as log:
    result=subprocess.run([str(BIN/'vvp.exe'),str(exe)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
print((ROOT/'build/observer_protocol.log').read_text())
if result.returncode: raise SystemExit(result.returncode)
print('PASS Python decoding matches five full-frame software golden records; STR5 is skipped')
# Record the exact compatibility changes relative to the latest live PC sources.
patch=[];old=ROOT.parent/'rk_dual_vision_host'
for relative in ('board_agent.py','app.py','rk/dual_control.py','rk/dual_hdmi_bringup.py'):
    patch.extend(difflib.unified_diff((old/relative).read_text(encoding='utf-8').splitlines(True),
        (ROOT/'host_compat'/relative).read_text(encoding='utf-8').splitlines(True),
        fromfile='stable_host/'+relative,tofile='OBS1_host/'+relative))
(ROOT/'build/host_compat.patch').write_text(''.join(patch),encoding='utf-8')
