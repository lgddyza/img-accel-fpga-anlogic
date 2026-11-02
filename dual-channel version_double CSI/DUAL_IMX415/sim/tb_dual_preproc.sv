`timescale 1ns/1ps
module tb_dual_preproc;
    localparam W=32,H=16,B=W/4;
    reg clk=0,rst=0,camera=0,v=0,s=0,e=0;always #3.75 clk=~clk;
    reg [127:0] rgb=0;reg [2:0] mode=0;
    wire [127:0] d;wire dv,ds,de,df;
    wire [31:0] hf[0:1],he[0:1];
    v2_dual_preprocess #(.WIDTH(W),.HEIGHT(H)) dut (
        .camera(camera),.clk(clk),.rst_n(rst),.s_rgb(rgb),.s_valid(v),.s_sof(s),.s_eol(e),.mode(mode),
        .m_rgb_gray(d),.m_valid(dv),.m_sof(ds),.m_eol(de),.gauss_overrun(df),.applied_mode(),
        .hist_frames_a(hf[0]),.hist_frames_b(hf[1]),.hist_errors_a(he[0]),.hist_errors_b(he[1]));
    wire [127:0] refdata[0:1];wire [1:0] rv,rs,re,rf;
    generate for(genvar c=0;c<2;c=c+1) begin:g_reference
        localparam integer CAM_ID=c;
        ref_preprocess4_before_timing #(.WIDTH(W),.HEIGHT(H)) refp (
            .clk(clk),.rst_n(rst),.s_rgb(rgb),.s_valid(v && camera==CAM_ID),.s_sof(s && camera==CAM_ID),.s_eol(e && camera==CAM_ID),.mode(mode),
            .m_rgb_gray(refdata[CAM_ID]),.m_valid(rv[CAM_ID]),.m_sof(rs[CAM_ID]),.m_eol(re[CAM_ID]),.gauss_overrun(rf[CAM_ID]),
            .applied_mode(),.hist_frames(),.hist_errors());
    end endgenerate
    // The new luma pipeline adds exactly one cycle. The frozen reference
    // retains both the original luma and the original CLAHE arithmetic.
    reg [127:0] refdata_d[0:1];reg [1:0] rv_d,rs_d,re_d;
    always @(posedge clk) begin
        if(!rst) begin rv_d<=0;rs_d<=0;re_d<=0;refdata_d[0]<=0;refdata_d[1]<=0;end
        else begin
            rv_d<=rv;rs_d<=rs;re_d<=re;
            refdata_d[0]<=refdata[0];refdata_d[1]<=refdata[1];
        end
    end
    integer count[0:1];
    always @(negedge clk) if(rst) begin
        if(df || |rf) $fatal(1,"preprocessing overrun");
        if(dv!==rv_d[camera]) $fatal(1,"shared pipeline latency/valid mismatch");
        if(dv) begin
            if(d!==refdata_d[camera] || ds!==rs_d[camera] || de!==re_d[camera])
                $fatal(1,"cross-camera histogram/window contamination camera=%0d count=%0d",camera,count[camera]);
            count[camera]=count[camera]+1;
        end
    end
    initial begin
        count[0]=0;count[1]=0;repeat(5) @(negedge clk);rst=1;
        repeat(1100) @(negedge clk);
        for(integer f=0;f<16;f=f+1) begin
            camera=f%2;mode=camera ? 3-(f/2)%4 : (f/2)%4;
            for(integer y=0;y<H;y=y+1) for(integer x=0;x<B;x=x+1) begin
                v=1;s=y==0 && x==0;e=x==B-1;
                for(integer k=0;k<4;k=k+1) begin
                    rgb[k*32+:32]={8'd0,8'(30+camera*120+((x*4+k+y*3)%90)),
                        8'(20+camera*70+((x*7+k+y*11)%110)),8'(200-camera*140+((x*13+k+y*5)%60))};
                    if(y==0 && x==0) case(k)
                        0:rgb[k*32+:32]=32'h00ff0000;
                        1:rgb[k*32+:32]=32'h0000ff00;
                        2:rgb[k*32+:32]=32'h000000ff;
                        3:rgb[k*32+:32]=32'h00ffffff;
                    endcase
                end
                @(negedge clk);
                if(x%2==1) begin v=0;s=0;e=0;repeat(2) @(negedge clk);end
            end
            v=0;s=0;e=0;repeat(12000) @(negedge clk);
        end
        if(count[0]!=8*B*H || count[1]!=8*B*H || hf[0]!=8 || hf[1]!=8 || he[0] || he[1]) $fatal(1,"bad dual history counts");
        $display("PASS two-stage luma and retimed CLAHE bit-exact versus frozen pre-change references: colored pixels, four lanes, modes 0..3, A/B history, bubbles, markers and exact +1-cycle latency");$finish;
    end
    initial begin #3000000;$fatal(1,"timeout");end
endmodule
