"""Compare full-resolution RTL statistics against the software golden model."""
from pathlib import Path
import json,sys,subprocess
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
SW=ROOT.parent/'road_damage_yolov8n/feature_observer_20261026'
sys.path.insert(0,str(SW))
from features import observe
BIN=ROOT.parent/'.tools/iverilog/bin'
rng=np.random.default_rng(20261026)
frames=[np.zeros((1080,1920),np.uint8),np.full((1080,1920),255,np.uint8),
    np.tile(np.arange(1920,dtype=np.uint16).astype(np.uint8),(1080,1)),
    rng.integers(0,256,(1080,1920),dtype=np.uint8)]
cases=json.loads((SW/'cases.json').read_text(encoding='utf-8'))
import cv2
frames.append(cv2.imread(str(SW/'inputs'/cases[0]['path']),cv2.IMREAD_GRAYSCALE))
assert all(im.shape==(1080,1920) for im in frames)
gold=[]
for i,im in enumerate(frames):
    raw=observe(im);gold.append(raw)
    # Test stream carries only the two lanes the observer actually reads.
    packed=im[:,0::4].astype(np.uint16)|(im[:,1::4].astype(np.uint16)<<8)
    (ROOT/f'build/observer_{i}.hex').write_text('\n'.join(f'{v:04x}' for v in packed.ravel()),encoding='ascii')
checks=[]
for i,g in enumerate(gold):
    val=(i+10)|((i%2)<<28)|(1<<29)|((i+100)<<32)|(g['samples']<<64)|(g['luma_sum']<<82)|(g['dark_count']<<107)|(g['bright_count']<<125)|(g['gradient_sum']<<143)|((i+1)<<456)
    for k,n in enumerate(g['hist']): val|=n<<(168+18*k)
    checks.append(f'run_frame({i},512\'h{val:0128x});')
tb='''`timescale 1ns/1ps
module tb_feature_observer;
reg clk=0,rst_n=0;always #3.75 clk=~clk;
reg [127:0] rgb=0,metadata=0;reg valid=0,sof=0,eol=0;
wire [511:0] result;wire result_valid;reg result_ready=1;
v2_feature_observer dut(.*);
reg [15:0] pixels[0:518399];integer k,n;reg [511:0] held;
task run_frame(input integer idx,input [511:0] expected);
begin
    $readmemh($sformatf("build/observer_%0d.hex",idx),pixels);
    metadata=0;metadata[27:0]=idx+10;metadata[32]=idx%2;metadata[95:64]=idx+100;
    for(k=0;k<518400;k=k+1) begin
        @(negedge clk);valid=1;sof=(k==0);eol=(k%480==479);
        rgb=0;rgb[7:0]=pixels[k][7:0];rgb[39:32]=pixels[k][15:8];
        if(k%701==0) begin
            @(negedge clk);valid=0;sof=0;eol=0;repeat(2) @(negedge clk);
        end
    end
    @(negedge clk);valid=0;sof=0;eol=0;
    wait(result_valid);#1;
    if(result!==expected) $fatal(1,"frame %0d expected=%h got=%h",idx,expected,result);
    $display("PASS full1080p frame %0d integer fields and histogram",idx);
    repeat(4) @(negedge clk);
end endtask
initial begin
repeat(4) @(negedge clk);rst_n=1;
CHECKS
// Hold a result while malformed data and another complete frame arrive.
result_ready=0;
run_frame(4,512'hEXPECTED);
held=result;
@(negedge clk);valid=1;sof=1;eol=1;
@(negedge clk);valid=0;sof=0;eol=0;
repeat(5) @(negedge clk);
if(result!==held) $fatal(1,"malformed frame replaced valid result");
// Release pending data, then restart after an incomplete frame.
result_ready=1;repeat(4) @(negedge clk);
@(negedge clk);valid=1;sof=1;eol=0;
@(negedge clk);valid=0;sof=0;
repeat(4) @(negedge clk);
rst_n=0;repeat(3) @(negedge clk);
if(result_valid || result!==0) $fatal(1,"reset did not clear observation");
$display("PASS geometry discard, pending result, pauses and reset");$finish;
end
initial begin #100000000;$fatal(1,"observer timeout");end
endmodule
'''
# A repeated valid frame has the next sequence number, without new errors.
extra=int(checks[-1].split("512'h")[1].split(')')[0],16)+(1<<456)
tb=tb.replace('CHECKS','\n'.join(checks)).replace('EXPECTED',f'{extra:0128x}')
(ROOT/'build/tb_feature_observer.sv').write_text(tb,encoding='ascii')
exe=ROOT/'build/feature_observer.vvp'
subprocess.run([str(BIN/'iverilog.exe'),'-g2012','-s','tb_feature_observer','-o',str(exe),'build/tb_feature_observer.sv','rtl/v2_feature_observer.v'],cwd=ROOT,check=True)
with (ROOT/'build/feature_observer.log').open('w') as log:
    run=subprocess.run([str(BIN/'vvp.exe'),'-i',str(exe)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
print((ROOT/'build/feature_observer.log').read_text())
(ROOT/'build/observer_golden.json').write_text(json.dumps(gold,indent=2),encoding='utf-8')
raise SystemExit(run.returncode)
