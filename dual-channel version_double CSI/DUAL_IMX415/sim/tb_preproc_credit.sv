`timescale 1ns/1ps
module tb_preproc_credit;
    localparam W=64,H=48,B=W/4,CAPACITY=160;
    reg clk=0,rst_n=0,start=0,s_valid=0,s_sof=0,s_eol=0;
    always #3.75 clk=~clk;
    reg [127:0] s_rgb=0;
    wire [127:0] m_rgb_gray;
    wire m_valid,m_sof,m_eol,preproc_fault,ready,credit_fault;
    wire [35:0] reserved,peak;
    reg [35:0] queued=0;
    integer occupancy[0:2];
    integer cycle=0,outputs=0,row=0,out_row=0,waits=0,drained=0;
    wire [1:0] lane=(out_row/8)%3;
    v2_dual_preprocess #(.WIDTH(W),.HEIGHT(H)) dut (
        .clk(clk),.rst_n(rst_n),.camera(1'b0),.mode(3'd5),.strength(3'd4),
        .s_rgb(s_rgb),.s_valid(s_valid),.s_sof(s_sof),.s_eol(s_eol),
        .m_rgb_gray(m_rgb_gray),.m_valid(m_valid),.m_sof(m_sof),.m_eol(m_eol),
        .gauss_overrun(preproc_fault));
    v2_isp_row_credit #(.WIDTH(W),.HEIGHT(H),.FIFO_GROUPS(CAPACITY)) credit (
        .clk(clk),.rst_n(rst_n),.line_started(start),
        .processed_valid(m_valid),.processed_sof(m_sof),.processed_eol(m_eol),
        .queued_groups(queued),.line_ready(ready),.fault(credit_fault),
        .reserved_groups(reserved),.peak_groups(peak));
    always @(posedge clk) begin
        if(!rst_n) begin
            for(integer k=0;k<3;k=k+1) occupancy[k]=0;
            cycle=0;outputs=0;out_row=0;drained=0;
        end else begin
            cycle=cycle+1;
            if(preproc_fault || credit_fault) $fatal(1,"pipeline/credit fault");
            if(m_valid) begin
                occupancy[lane]=occupancy[lane]+1;
                if(m_sof!==(outputs%(W*H/4)==0) || m_eol!==(outputs%B==B-1))
                    $fatal(1,"processed frame geometry");
                outputs=outputs+1;
                if(m_eol) out_row=(out_row==H-1) ? 0 : out_row+1;
            end
            for(integer k=0;k<3;k=k+1) begin
                if(occupancy[k]>CAPACITY) $fatal(1,"input FIFO overrun");
                // Stall all decoders long enough to fill queues and stop replay.
                if((cycle>3000 && cycle<4500 || cycle>6500) && cycle%4==k && occupancy[k]!=0) begin
                    occupancy[k]=occupancy[k]-1;drained=drained+1;
                end
            end
        end
    end
    always @(negedge clk)
        for(integer k=0;k<3;k=k+1) queued[k*12+:12]=occupancy[k];
    initial begin
        repeat(8) @(negedge clk);rst_n=1;repeat(8) @(negedge clk);
        for(integer frame=0;frame<2;frame=frame+1) begin
            for(row=0;row<H;row=row+1) begin
                while(!ready) begin @(negedge clk);waits=waits+1;end
                #1;start=1;@(negedge clk);#1;start=0;
                for(integer x=0;x<B;x=x+1) begin
                    s_valid=1;s_sof=row==0 && x==0;s_eol=x==B-1;
                    s_rgb={4{32'h00808080}};
                    @(negedge clk);#1;
                end
                s_valid=0;s_sof=0;s_eol=0;repeat(8) @(negedge clk);
            end
            wait(outputs==(frame+1)*W*H/4);repeat(20) @(negedge clk);
        end
        wait(drained==2*W*H/4);repeat(10) @(negedge clk);
        if(!waits || reserved!=0 || preproc_fault || credit_fault) $fatal(1,"invalid recovery");
        $display("PASS blackhat lookahead + row credit: decoder stalls, two frames, no overflow/deadlock; wait=%0d",waits);
        $finish;
    end
    initial begin #2000000;$fatal(1,"credit/lookahead deadlock outputs=%0d row=%0d",outputs,row);end
endmodule
