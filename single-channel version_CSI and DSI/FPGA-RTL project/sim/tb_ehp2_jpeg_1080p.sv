`timescale 1ns/1ps
module tb_ehp2_jpeg_1080p;
    localparam W=1920,H=1080,B=W/4,GAP=675,PERIOD=1500000;
    reg cam_clk=0,enc_clk=0,user_clk=0,rst_n=0;
    always #5.554 cam_clk=~cam_clk;
    always #2.5 enc_clk=~enc_clk;
    always #4 user_clk=~user_clk;
    reg [127:0] rgb=0;
    reg valid=0,sof=0,eol=0;
    reg [2:0] mode=5;
    wire [127:0] processed;
    wire pv,ps,pe,pfault;
    wire [2:0] applied;
    wire [31:0] hist_frames,hist_errors;
    gray_preprocess4 preproc(.clk(cam_clk),.rst_n(rst_n),
        .s_rgb(rgb),.s_valid(valid),.s_sof(sof),.s_eol(eol),.mode(mode),
        .m_rgb_gray(processed),.m_valid(pv),.m_sof(ps),.m_eol(pe),
        .gauss_overrun(pfault),.applied_mode(applied),
        .hist_frames(hist_frames),.hist_errors(hist_errors));
    wire [127:0] data[0:2];
    wire [15:0] keep[0:2];
    wire [2:0] v,last;
    wire configured,busy,fault;
    wire [6:0] qf;
    wire [31:0] sent[0:2],bytes[0:2],fault_count;
    jpeg_triple_tile_branch jpeg(.cam_clk(cam_clk),.cam_rst_n(rst_n),
        .enc_clk(enc_clk),.enc_pll_lock(1'b1),.user_clk(user_clk),.user_rst_n(rst_n),
        .s_rgb4(processed),.s_valid(pv),.s_sof(ps),.s_eol(pe),
        .enable(1'b1),.reset_pulse(1'b0),.link_up(1'b1),.full_rate(1'b1),
        .quality(7'd90),.a_ready(1'b1),.b_ready(1'b1),.c_ready(1'b1),
        .a_data(data[0]),.b_data(data[1]),.c_data(data[2]),
        .a_keep(keep[0]),.b_keep(keep[1]),.c_keep(keep[2]),
        .a_valid(v[0]),.b_valid(v[1]),.c_valid(v[2]),
        .a_last(last[0]),.b_last(last[1]),.c_last(last[2]),
        .status_configured(configured),.status_busy(busy),.status_fault(fault),
        .status_quality(qf),.sent_a(sent[0]),.sent_b(sent[1]),.sent_c(sent[2]),
        .bytes_a(bytes[0]),.bytes_b(bytes[1]),.bytes_c(bytes[2]),.fault_count(fault_count));
    integer fd[0:2],packets[0:2],counts[0:2];
    reg [7:0] previous[0:2];
    reg soi_seen[0:2],eoi_seen[0:2];
    integer lane,i,frame,x,y,k,beats=0;
    integer high_a=0,high_b=0,high_c=0;
    function [7:0] pixel(input integer xx,yy);
        reg [31:0] hash;
        integer value;
        begin
            hash=(xx+1)*32'h045d9f3b ^ (yy+13)*32'h119de1f3;
            hash=hash^(hash>>16);
            value=112+((xx/64+yy/64)%6)*5+integer'(hash[3:0]);
            if(xx%317==53 || xx%317==54 || (xx+yy/3)%491==75) value=value-48;
            pixel=value[7:0];
        end
    endfunction
    always @(posedge cam_clk) if(rst_n) begin
        if(pfault) $fatal(1,"preprocessor fault");
        if(pv) begin
            if(ps !== (beats%(B*H)==0) || pe !== (beats%B==B-1))
                $fatal(1,"output marker beat=%0d",beats);
            beats=beats+1;
            if(pe && (beats/B)%H>=1070)
                $display("tail row=%0d time=%0t learned gaps close/erode/dilate=%0d/%0d/%0d",
                    (beats/B-1)%H,$time,
                    preproc.u_blackhat.u_close_min.u_vertical.line_gap,
                    preproc.u_blackhat.u_direction.u_erode_window.line_gap,
                    preproc.u_blackhat.u_direction.u_dilate_window.line_gap);
        end
        if(jpeg.g_tile[0].u_input.u_fifo.wrusedw>high_a)
            high_a=jpeg.g_tile[0].u_input.u_fifo.wrusedw;
        if(jpeg.g_tile[1].u_input.u_fifo.wrusedw>high_b)
            high_b=jpeg.g_tile[1].u_input.u_fifo.wrusedw;
        if(jpeg.g_tile[2].u_input.u_fifo.wrusedw>high_c)
            high_c=jpeg.g_tile[2].u_input.u_fifo.wrusedw;
    end
    always @(posedge user_clk) if(rst_n) begin
        if(fault) $fatal(1,"JPEG fault bridge=%b packer=%b B=%h/%0d C=%h/%0d",
            jpeg.bridge_fault,jpeg.packer_fault,jpeg.bridge_cause[1],jpeg.bridge_fault_line[1],
            jpeg.bridge_cause[2],jpeg.bridge_fault_line[2]);
        for(lane=0;lane<3;lane=lane+1) if(v[lane]) begin
            if(counts[lane]==0)
                fd[lane]=$fopen($sformatf("frame_%0d_tile_%0d.jpg",packets[lane],lane),"wb");
            for(i=0;i<16;i=i+1) if(keep[lane][i]) begin
                $fwrite(fd[lane],"%c",data[lane][i*8+:8]);
                if(previous[lane]==8'hff && data[lane][i*8+:8]==8'hd8) soi_seen[lane]=1;
                if(previous[lane]==8'hff && data[lane][i*8+:8]==8'hd9) eoi_seen[lane]=1;
                previous[lane]=data[lane][i*8+:8];counts[lane]=counts[lane]+1;
            end
            if(last[lane]) begin
                if(!soi_seen[lane] || !eoi_seen[lane]) $fatal(1,"incomplete JPEG lane=%0d",lane);
                $fclose(fd[lane]);packets[lane]=packets[lane]+1;
                $display("JPEG packet lane=%0d frame=%0d bytes=%0d",lane,packets[lane],counts[lane]);
                counts[lane]=0;previous[lane]=0;soi_seen[lane]=0;eoi_seen[lane]=0;
            end
        end
    end
    initial begin
        for(lane=0;lane<3;lane=lane+1) begin
            packets[lane]=0;counts[lane]=0;previous[lane]=0;soi_seen[lane]=0;eoi_seen[lane]=0;
        end
        repeat(10) @(negedge user_clk);rst_n=1;
        wait(configured);repeat(1100) @(negedge cam_clk);
        for(frame=0;frame<2;frame=frame+1) begin
            mode=frame==0 ? 5 : 7;
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<B;x=x+1) begin
                    @(negedge cam_clk);valid=1;sof=(x==0 && y==0);eol=(x==B-1);
                    for(k=0;k<4;k=k+1) rgb[k*32+:32]={8'd0,{3{pixel(x*4+k,y)}}};
                end
                @(negedge cam_clk);valid=0;sof=0;eol=0;
                repeat(GAP) @(negedge cam_clk);
            end
            repeat(PERIOD-(B+GAP+1)*H) @(negedge cam_clk);
            if(beats!=(frame+1)*B*H || packets[0]!=frame+1 || packets[1]!=frame+1 || packets[2]!=frame+1)
                $fatal(1,"60fps deadline missed mode=%0d beats=%0d packets=%0d/%0d/%0d",mode,beats,packets[0],packets[1],packets[2]);
            if(frame==0 && !preproc.lut_active) $fatal(1,"CLAHE LUT not ready for second frame");
            $display("EHP2 frame mode=%0d complete, FIFO high water A/B/C=%0d/%0d/%0d",mode,high_a,high_b,high_c);
        end
        if(fault_count || hist_errors || sent[0]!=2 || sent[1]!=2 || sent[2]!=2)
            $fatal(1,"completion counters or hist errors");
        $display("PASS EHP2 1080p60 blackhat and blackhat+active CLAHE to three real JPEG encoders, no FIFO overflow");
        $finish;
    end
    initial begin #40000000; $fatal(1,"full pipeline timeout");end
endmodule
