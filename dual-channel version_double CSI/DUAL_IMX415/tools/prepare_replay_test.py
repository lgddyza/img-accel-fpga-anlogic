"""Adapt the frozen V1 OpenCV-vector test to the V2 DDR replay cadence."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'sim/reference_tb_v1.sv.txt').read_text(encoding='utf-8-sig')
s=s.replace('module tb_gray_enhance4;','module tb_preproc_replay;')
s=s.replace('sim/enhance_vectors/','sim/reference_enhance_vectors/')
s=s.replace('gap=(tx+ty+frame)%3;','gap=(tx%2==1) ? 2 : 0;')
s=s.replace('valid=0;sof=0;eol=0;repeat(4) @(negedge clk);','valid=0;sof=0;eol=0;')
s=s.replace('PASS EHP2 eight modes','PASS V2 two-valid/two-idle replay, eight modes')
(ROOT/'sim/tb_preproc_replay.sv').write_text(s,encoding='utf-8')
print('Prepared V2 replay test with frozen OpenCV vectors')
