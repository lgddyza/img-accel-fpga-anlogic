`timescale 1ns/1ps
module tb_observer_protocol;
reg clk=0,rst_n=0;always #5 clk=~clk;
reg [127:0] rgb=0,metadata=0;reg valid=0,sof=0,eol=0;
wire [511:0] result;wire result_valid;reg result_ready=0;
v2_feature_observer #(.WIDTH(16),.HEIGHT(2)) dut(.*);
reg [511:0] held;
task frame(input integer id);
integer b;
begin
    metadata=0;metadata[27:0]=id;metadata[32]=id%2;
    for(b=0;b<8;b=b+1) begin
        @(negedge clk);valid=1;sof=b==0;eol=b%4==3;
        rgb=0;rgb[7:0]=b<4 ? 224 : 225;rgb[39:32]=b<4 ? 32 : 31;
    end
    @(negedge clk);valid=0;sof=0;eol=0;
    repeat(5) @(negedge clk);
end endtask
initial begin
    repeat(3) @(negedge clk);rst_n=1;
    // Invalid first line: discard it and count the error.
    @(negedge clk);valid=1;sof=1;eol=1;
    @(negedge clk);valid=0;sof=0;eol=0;
    repeat(4) @(negedge clk);
    if(result_valid) $fatal(1,"bad geometry published");
    frame(1);
    if(!result_valid || result[27:0]!=1 || result[28]!=1 || result[81:64]!=2 ||
       result[106:82]!=449 || result[124:107]!=0 || result[142:125]!=1 ||
       result[167:143]!=386 || result[168+14*18+:18]!=2 || result[487:472]!=1)
        $fatal(1,"threshold/gradient/geometry recovery mismatch %h",result);
    held=result;
    frame(2);
    if(result!==held) $fatal(1,"blocked result was overwritten");
    result_ready=1;repeat(4) @(negedge clk);result_ready=0;
    frame(3);
    if(result[27:0]!=3 || result[471:456]!=3 || result[487:472]!=2)
        $fatal(1,"overflow diagnostic or recovery lost %h",result);
    result_ready=1;repeat(4) @(negedge clk);result_ready=0;
    @(negedge clk);valid=1;sof=1;eol=0;
    @(negedge clk);valid=0;sof=0;
    frame(4);
    if(result[27:0]!=4 || result[487:472]!=3 || result[81:64]!=2)
        $fatal(1,"unexpected SOF failed to resynchronize %h",result);
    $display("PASS strict thresholds, incomplete frame discard, SOF resync, pending overrun and recovery");
    $finish;
end
initial begin #100000;$fatal(1,"protocol timeout");end
endmodule
