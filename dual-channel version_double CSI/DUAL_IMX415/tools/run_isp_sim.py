from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
BIN=ROOT.parent/'.tools/iverilog/bin'
files=[ROOT/'rtl/v2_line_replay.v']+sorted((ROOT/'uisrc/03_ip/ui_isp').rglob('*.v'))
ram_files=[p for p in files if p.name in ('ui_ram_awb_delay_signal.v','ui_ram_demosaic.v','ui_ram_zhenghe.v')]
files=[p for p in files if 'divider_gate.v' not in p.name and p not in ram_files]
# Icarus cannot run TD's encrypted simulator model. Use synchronous, old-data
# RAM behavior at the existing wrapper boundary. This checks pipeline/state
# logic only; electrical/timing validation still requires TD/board testing.
models=[]
for ram in ram_files:
 header=ram.read_text(encoding='utf-8-sig').split('PH1_LOGIC_ERAM',1)[0]
 models.append(header+'''
    reg [DATA_WIDTH_A-1:0] memory [0:DATA_DEPTH_A-1];
    reg [DATA_WIDTH_A-1:0] qa;
    reg [DATA_WIDTH_B-1:0] qb;
    integer i;
    initial begin
        qa=0;qb=0;
        for(i=0;i<DATA_DEPTH_A;i=i+1) memory[i]=0;
    end
    always @(posedge clka) begin
        if(wea) memory[addra]<=dia;
        else qa<=memory[addra];
    end
    always @(posedge clkb) begin
        if(web) memory[addrb]<=dib;
        else qb<=memory[addrb];
    end
    assign doa=qa;
    assign dob=qb;
endmodule
''')
ram_model=ROOT/'build/isp_ram_behavioral.v'
models.append('''
// Dynamic AWB is disabled in ui_isp_top. These divider results cannot reach
// RGB or marker outputs; the unity gains are explicit reset constants.
module divider(input wire clk,rst,start,input wire [31:0] denominator,
    input wire [47:0] numerator,output wire done,output wire [47:0] quotient,
    output wire [31:0] remainder);
    assign done=0;assign quotient=0;assign remainder=0;
endmodule
''')
ram_model.write_text('\n'.join(models),encoding='utf-8')
files+=[ram_model]
if __name__=='__main__':
 exe=ROOT/'build/isp_replay.vvp'
 subprocess.run([str(BIN/'iverilog.exe'),'-g2012','-s','tb_isp_replay','-o',str(exe),str(ROOT/'sim/tb_isp_replay.sv'),*[str(p) for p in files]],cwd=ROOT,check=True)
 with (ROOT/'build/isp_replay.log').open('w',encoding='utf-8') as log:
  result=subprocess.run([str(BIN/'vvp.exe'),'-i',str(exe)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
 print((ROOT/'build/isp_replay.log').read_text())
 raise SystemExit(result.returncode)
