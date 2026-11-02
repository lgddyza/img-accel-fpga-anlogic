`timescale 1ns/1ps
module tb_isp_row_credit;
    reg clk=0,rst_n=0,start=0,pv=0,ps=0,pe=0;
    reg [35:0] queued=0;
    wire ready,fault;
    wire [35:0] debt,peak;
    always #5 clk=~clk;
    v2_isp_row_credit #(.WIDTH(16),.HEIGHT(24),.FIFO_GROUPS(64)) dut(
        .clk(clk),.rst_n(rst_n),.line_started(start),.processed_valid(pv),
        .processed_sof(ps),.processed_eol(pe),.queued_groups(queued),
        .line_ready(ready),.fault(fault),.reserved_groups(debt),.peak_groups(peak));
    task tick;
        begin @(posedge clk); #1; @(negedge clk); end
    endtask
    task reset;
        begin rst_n=0;start=0;pv=0;ps=0;pe=0;queued=0;
            tick;tick;rst_n=1;tick;end
    endtask
    task reserve;
        begin if(!ready) $fatal(1,"unexpected admission stall");start=1;tick;start=0;end
    endtask
    task output_row(input integer row);
        begin
            for(integer x=0;x<4;x=x+1) begin
                pv=1;ps=row==0 && x==0;pe=x==3;tick;
                if(fault) $fatal(1,"valid row rejected row=%0d x=%0d",row,x);
            end
            pv=0;ps=0;pe=0;
        end
    endtask
    initial begin
        reset;
        queued[11:0]=52;tick;if(ready) $fatal(1,"delayed observation safety margin missing");
        queued[11:0]=51;tick;if(!ready) $fatal(1,"safe capacity refused");
        reserve;
        if(debt[11:0]!=4 || ready) $fatal(1,"row not reserved");
        queued=0;tick;
        // Retire and reserve on the same cycle, with output flags checked.
        start=1;pv=1;ps=1;pe=0;tick;start=0;ps=0;
        if(debt[11:0]!=7 || fault) $fatal(1,"simultaneous accounting");
        for(integer x=1;x<4;x=x+1) begin pe=x==3;tick;end
        pv=0;pe=0;
        output_row(1);
        if(debt!=0) $fatal(1,"row debt leaked");
        for(integer row=2;row<24;row=row+1) begin reserve;output_row(row);end
        if(debt!=0 || fault) $fatal(1,"stripe/frame accounting failed");
        reserve;output_row(0);
        if(debt!=0 || fault) $fatal(1,"next frame state failed");
        reset;
        for(integer row=0;row<24;row=row+1) reserve;
        if(debt!={12'd32,12'd32,12'd32}) $fatal(1,"stripe assignment");
        for(integer row=0;row<24;row=row+1) output_row(row);
        if(debt!=0 || fault) $fatal(1,"delayed output accounting failed");
        reset;
        pv=1;ps=1;tick;
        if(!fault) $fatal(1,"unsolicited output not detected");
        if(debt!=0) $fatal(1,"unsolicited output wrapped reservation");
        repeat(20) tick;
        if(!fault || debt!=0 || ready) $fatal(1,"fault not frozen");
        reset;
        reserve;output_row(0);
        if(debt!=0 || fault) $fatal(1,"reset failed to restore valid flow");
        reset;
        reserve;pv=1;ps=1;pe=1;tick;
        if(!fault) $fatal(1,"early EOL not detected");
        reset;
        queued[11:0]=53;tick;start=1;tick;
        if(!fault) $fatal(1,"illegal row start not detected");
        $display("PASS row credits: capacity, simultaneous events, stripes, frames, faults");
        $finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
