`timescale 1ns/1ps
// Real encoder test. Full geometry, DDR replay pace (two valid + RAW_IDLE idle),
// two distinct camera frames served successively; reports total service time.
module tb_jpeg_dual_rate #(parameter W=1920,H=1080,FRAMES=2,HOST_STALL=0,RAW_IDLE=1,PAUSE_CYCLES=0,QF_SWITCH=0);
    localparam B=W/4;
    reg cam_clk=0,enc_clk=0,user_clk=0,rst_n=0;
    always #3.75 cam_clk=~cam_clk;
    always #2.5 enc_clk=~enc_clk;
    always #4 user_clk=~user_clk;
    reg [127:0] rgb=0;
    reg valid=0,sof=0,eol=0;
    reg [6:0] requested_quality=85;
    wire [127:0] data[0:2];wire [15:0] keep[0:2];wire [2:0] v,last;
    wire configured,busy,fault,armed,done;wire [6:0] qf;
    wire [31:0] sent[0:2],bytes[0:2],fault_count;
    integer user_cycles=0;
    always @(posedge user_clk) user_cycles<=user_cycles+1;
    wire input_ready;
`ifdef PIPELINE_BACKPRESSURE
    reg [31:0] ready_rng=32'h86421973;
    always @(posedge user_clk) ready_rng<={ready_rng[30:0],
        ready_rng[31]^ready_rng[21]^ready_rng[1]^ready_rng[0]};
    wire long_pause=PAUSE_CYCLES>0 ? user_cycles<PAUSE_CYCLES :
        user_cycles<100000 || (user_cycles>=375000 && user_cycles<625000);
    wire [2:0] dma_ready=long_pause ? 3'b000 :
        {ready_rng[7:0]>80,ready_rng[15:8]>128,ready_rng[23:16]>160};
`else
    wire [2:0] dma_ready=HOST_STALL ?
        {user_cycles%50000>=20000,user_cycles%50000>=25000,user_cycles%50000>=30000} : 3'b111;
`endif
    wire [127:0] encoder_rgb;wire encoder_valid,encoder_sof,encoder_eol;
`ifdef PIPELINE_RATE_TEST
    wire [39:0] raw={rgb[119:112],2'b0,rgb[87:80],2'b0,rgb[55:48],2'b0,rgb[23:16],2'b0};
    wire [39:0] line_data;wire lv,ls,le,line_fault;
    wire source_ready,row_ready,row_started,row_waiting,credit_fault;
    wire [35:0] queued_groups,reserved_groups,peak_groups;
    v2_line_replay #(.BACKPRESSURE(1),.MIN_LINE_GAP(64)) line_replay (.clk(cam_clk),.rst_n(rst_n),.s_data(raw),.s_valid(valid),.s_sof(sof),.s_eol(eol),
        .m_data(line_data),.m_valid(lv),.m_sof(ls),.m_eol(le),.fault(line_fault),
        .s_ready(source_ready),.m_start_ready(row_ready),
        .line_started(row_started),.line_waiting(row_waiting));
    wire [127:0] isp_rgb;wire iv,is,ie,preproc_fault;
    ui_isp_top #(.ENABLE_DSI_BRANCH(0),.COMPACT_FIXED_ISP(1)) isp (
        .I_clk(cam_clk),.I_rst_n(rst_n),.I_tdata(line_data),.I_tvalid(lv),.I_tuser(ls),.I_tlast(le),
        .I_tdest(10'd0),.O_tready(1'b1),.O_tdata(isp_rgb),.O_tvalid(iv),.O_tuser(is),.O_tlast(ie),.I_tready(),
        .I_first_row_odd(1'b0),.I_dsi_control(4'd0),.O_dsi_tdata(),.O_dsi_tvalid(),.O_dsi_tuser(),.O_dsi_tlast(),.O_dsi_phase());
    v2_dual_preprocess preproc (.camera(frame[0]),.clk(cam_clk),.rst_n(rst_n),.s_rgb(isp_rgb),
        .s_valid(iv),.s_sof(is),.s_eol(ie),.mode(frame==0 ? 3'd4 : 3'd5),.strength(frame==0 ? 3'd1 : 3'd4),
        .m_rgb_gray(encoder_rgb),.m_valid(encoder_valid),.m_sof(encoder_sof),.m_eol(encoder_eol),
        .gauss_overrun(preproc_fault),.applied_mode(),.hist_frames_a(),.hist_frames_b(),.hist_errors_a(),.hist_errors_b());
    v2_isp_row_credit #(.WIDTH(W),.HEIGHT(H),.FIFO_GROUPS(4096)) credit (
        .clk(cam_clk),.rst_n(rst_n),.line_started(row_started),
        .processed_valid(encoder_valid),.processed_sof(encoder_sof),.processed_eol(encoder_eol),
        .queued_groups(queued_groups),.line_ready(row_ready),.fault(credit_fault),
        .reserved_groups(reserved_groups),.peak_groups(peak_groups));
    always @(posedge cam_clk) if(rst_n && (line_fault || preproc_fault || credit_fault))
        $fatal(1,"pipeline fault lines=%b preproc=%b credit=%b reserved=%h queued=%h",line_fault,preproc_fault,credit_fault,reserved_groups,queued_groups);
`else
    assign encoder_rgb=rgb;assign encoder_valid=valid;assign encoder_sof=sof;assign encoder_eol=eol;
`endif
    jpeg_triple_tile_branch #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.INPUT_FIFO_ADDR_WIDTH(12),.OUTPUT_FIFO_ADDR_WIDTH(10),.V2_SCHEDULED(1)) jpeg(
        .cam_clk(cam_clk),.cam_rst_n(rst_n),.enc_clk(enc_clk),.enc_pll_lock(1'b1),
        .user_clk(user_clk),.user_rst_n(rst_n),.s_rgb4(encoder_rgb),.s_valid(encoder_valid),.s_sof(encoder_sof),.s_eol(encoder_eol),
        .enable(1'b1),.reset_pulse(1'b0),.link_up(1'b1),.full_rate(1'b1),.quality(requested_quality),
        .a_ready(dma_ready[0]),.b_ready(dma_ready[1]),.c_ready(dma_ready[2]),
        .a_data(data[0]),.b_data(data[1]),.c_data(data[2]),.a_keep(keep[0]),.b_keep(keep[1]),.c_keep(keep[2]),
        .a_valid(v[0]),.b_valid(v[1]),.c_valid(v[2]),.a_last(last[0]),.b_last(last[1]),.c_last(last[2]),
        .status_configured(configured),.status_busy(busy),.status_fault(fault),.status_quality(qf),
        .sent_a(sent[0]),.sent_b(sent[1]),.sent_c(sent[2]),.bytes_a(bytes[0]),.bytes_b(bytes[1]),.bytes_c(bytes[2]),
`ifdef PIPELINE_RATE_TEST
        .input_levels(queued_groups),
`endif
        .enc_performance(),
        .fault_count(fault_count),.debug_status(),.debug_detail(),.input_armed(armed),.input_ready(input_ready),.group_done_cam(done),.fault_cam());
    integer fd[0:2],packets[0:2],counts[0:2],maxfill[0:2];
    wire [11:0] fifo_used[0:2];
    generate for(genvar f=0;f<3;f=f+1) begin:g_used
        assign fifo_used[f]=jpeg.g_tile[f].u_input.u_fifo.wp-jpeg.g_tile[f].u_input.u_fifo.from_gray(jpeg.g_tile[f].u_input.u_fifo.rg2);
    end endgenerate
    integer lane,i,frame,x,y,k,over_budget=0;real started,elapsed;
    reg [2047:0] output_dir;
    initial if(!$value$plusargs("output_dir=%s",output_dir)) output_dir="build/str3_pipeline";
`ifdef PIPELINE_RATE_TEST
    integer raw_seen=0,isp_seen=0,pre_seen=0,pgm_fd=0;
    always @(posedge cam_clk) if(rst_n) begin
        if(valid) raw_seen=raw_seen+1;
        if(iv) isp_seen=isp_seen+1;
        if(encoder_valid) begin
            if(encoder_sof!==(pre_seen%(B*H)==0) || encoder_eol!==(pre_seen%B==B-1))
                $fatal(1,"processed frame geometry mismatch at %0d sof=%b eol=%b",pre_seen,encoder_sof,encoder_eol);
            if(encoder_sof) begin
                pgm_fd=$fopen($sformatf("%0s/expected_%0d.pgm",output_dir,pre_seen/(B*H)),"wb");
                $fwrite(pgm_fd,"P5\n%0d %0d\n255\n",W,H);
            end
            for(integer p=0;p<4;p=p+1) $fwrite(pgm_fd,"%c",encoder_rgb[p*32+:8]);
            pre_seen=pre_seen+1;
            if(pre_seen%(B*H)==0) begin $fclose(pgm_fd);pgm_fd=0;end
        end
    end
    initial begin
        forever begin
            #1000000;
            $display("PROGRESS ns=%0f raw=%0d isp=%0d processed=%0d JPEG=%0d/%0d/%0d",
                     $realtime,raw_seen,isp_seen,pre_seen,packets[0],packets[1],packets[2]);
        end
    end
`endif
    function [7:0] pixel(input integer xx,yy,cam);
        reg [31:0] hash;integer value;
        begin
            hash=(xx+1)*32'h045d9f3b ^ (yy+13)*32'h119de1f3;
            hash=hash^(hash>>16);
`ifdef PIPELINE_BACKPRESSURE
            pixel=hash[7:0];
`else
            value=90+cam*30+((xx/64+yy/64)%6)*5+integer'(hash[3:0]);
            if(xx%317==53 || xx%317==54 || (xx+yy/3)%491==75) value=value-48;
            pixel=value[7:0];
`endif
        end
    endfunction
`ifdef PIPELINE_BACKPRESSURE
    integer encoded_bytes[0:2],dma_bytes[0:2],paused_cycles[0:2];
    reg [7:0] expected_bytes[0:2][0:4194303];
    generate for(genvar c=0;c<3;c=c+1) begin:g_byte_check
        reg held=0;
        reg [8:0] held_byte;
        always @(posedge enc_clk) if(rst_n) begin
            if(held && (!jpeg.g_tile[c].jpg_valid ||
                {jpeg.g_tile[c].jpg_last,jpeg.g_tile[c].jpg_byte}!==held_byte))
                $fatal(1,"encoder changed paused output lane=%0d",c);
            held=jpeg.g_tile[c].jpg_valid && !jpeg.g_tile[c].jpg_ready;
            held_byte={jpeg.g_tile[c].jpg_last,jpeg.g_tile[c].jpg_byte};
            if(held) paused_cycles[c]=paused_cycles[c]+1;
            if(jpeg.g_tile[c].jpg_valid && jpeg.g_tile[c].jpg_ready) begin
                if(encoded_bytes[c]>=4194304) $fatal(1,"test scoreboard capacity");
                expected_bytes[c][encoded_bytes[c]]=jpeg.g_tile[c].jpg_byte;
                encoded_bytes[c]=encoded_bytes[c]+1;
            end
        end
    end endgenerate
`endif
    always @(posedge cam_clk) if(rst_n) begin
        if(fifo_used[0]>maxfill[0]) maxfill[0]=fifo_used[0];
        if(fifo_used[1]>maxfill[1]) maxfill[1]=fifo_used[1];
        if(fifo_used[2]>maxfill[2]) maxfill[2]=fifo_used[2];
    end
    always @(posedge user_clk) if(rst_n) begin
        if(fault) $fatal(1,"JPEG fault bridge=%b packer=%b",jpeg.bridge_fault,jpeg.packer_fault);
        for(lane=0;lane<3;lane=lane+1) if(v[lane] && dma_ready[lane]) begin
            if(counts[lane]==0) begin
`ifdef PIPELINE_RATE_TEST
`ifdef PIPELINE_SMOKE_NS
                fd[lane]=$fopen($sformatf("build/smoke_cam_%0d_tile_%0d.jpg",packets[lane],lane),"wb");
`else
                fd[lane]=$fopen($sformatf("%0s/cam_%0d_tile_%0d.jpg",output_dir,packets[lane],lane),"wb");
`endif
`else
                if(HOST_STALL) fd[lane]=$fopen($sformatf("build/stream_fix/sim_frame_%0d_tile_%0d.jpg",packets[lane],lane),"wb");
                else fd[lane]=$fopen($sformatf("build/cam_%0d_tile_%0d.jpg",packets[lane],lane),"wb");
`endif
            end
            for(i=0;i<16;i=i+1) if(keep[lane][i]) begin
`ifdef PIPELINE_BACKPRESSURE
                if(dma_bytes[lane]>=encoded_bytes[lane] ||
                   data[lane][i*8+:8]!==expected_bytes[lane][dma_bytes[lane]])
                    $fatal(1,"JPEG byte loss/reorder lane=%0d byte=%0d",lane,dma_bytes[lane]);
                dma_bytes[lane]=dma_bytes[lane]+1;
`endif
                $fwrite(fd[lane],"%c",data[lane][i*8+:8]);counts[lane]=counts[lane]+1;
            end
            if(last[lane]) begin
                $fclose(fd[lane]);packets[lane]=packets[lane]+1;
                $display("JPEG camera=%0d tile=%0d bytes=%0d time_ns=%0f",packets[lane]-1,lane,counts[lane],$realtime);
                counts[lane]=0;
            end
        end
    end
    initial begin
        frame=0;
        for(lane=0;lane<3;lane=lane+1) begin packets[lane]=0;counts[lane]=0;maxfill[lane]=0;end
`ifdef PIPELINE_BACKPRESSURE
        for(lane=0;lane<3;lane=lane+1) begin encoded_bytes[lane]=0;dma_bytes[lane]=0;paused_cycles[lane]=0;end
`endif
        repeat(10) @(negedge user_clk);rst_n=1;
        wait(configured && armed);repeat(20) @(negedge cam_clk);
        for(frame=0;frame<FRAMES;frame=frame+1) begin
            if(QF_SWITCH) begin
                case(frame%5)
                    0: requested_quality=85;
                    1: requested_quality=30;
                    2: requested_quality=95;
                    3: requested_quality=1;
                    4: requested_quality=65;
                endcase
            end
            started=$realtime;
            wait(armed && configured && qf==requested_quality);
            for(y=0;y<H;y=y+1) for(x=0;x<B;x=x+1) begin
                @(negedge cam_clk);
`ifdef PIPELINE_RATE_TEST
                while(!source_ready) begin valid=0;sof=0;eol=0;@(negedge cam_clk);end
`else
                // Match the production line-admission gate: once admitted,
                // a complete line is delivered without mid-line stalls.
                if(x==0) while(!input_ready) begin
                    valid=0;sof=0;eol=0;@(negedge cam_clk);
                end
`endif
                valid=1;sof=(x==0 && y==0);eol=(x==B-1);
                for(k=0;k<4;k=k+1) rgb[k*32+:32]={8'd0,{3{pixel(x*4+k,y,frame)}}};
                if(x%2==1) begin
                    @(negedge cam_clk);valid=0;sof=0;eol=0;
                    repeat(RAW_IDLE-1) @(negedge cam_clk);
                end
            end
            @(negedge cam_clk);valid=0;sof=0;eol=0;
            wait(done);elapsed=$realtime-started;
            $display("SERVICE camera=%0d ns=%0f rate_fps=%0f fifo_high=%0d/%0d/%0d",frame,elapsed,1e9/elapsed,maxfill[0],maxfill[1],maxfill[2]);
            if(packets[0]!=frame+1 || packets[1]!=frame+1 || packets[2]!=frame+1) $fatal(1,"incomplete group");
`ifdef PIPELINE_RATE_TEST
            if(raw_seen!=(frame+1)*B*H || isp_seen!=raw_seen || pre_seen!=raw_seen || reserved_groups!=0)
                $fatal(1,"full pipeline count/debt mismatch raw=%0d isp=%0d pre=%0d debt=%h",raw_seen,isp_seen,pre_seen,reserved_groups);
            $display("CREDIT peak=%0d/%0d/%0d",peak_groups[11:0],peak_groups[23:12],peak_groups[35:24]);
`endif
            if(elapsed>8333333.33) begin
                over_budget=over_budget+1;
                $display("BUDGET_MISS camera=%0d service_ns=%0f limit_ns=8333333.33",frame,elapsed);
            end
            repeat(20) @(negedge cam_clk);
        end
        $display("COMPLETE %0d frames %0dx%0d through real shared JPEG pool; host_stalls=%0d",FRAMES,W,H,HOST_STALL);
`ifndef PIPELINE_BACKPRESSURE
        if(over_budget) $fatal(1,"shared JPEG exceeded dual-60 budget on %0d frames",over_budget);
`endif
`ifdef PIPELINE_BACKPRESSURE
        for(lane=0;lane<3;lane=lane+1) begin
            if(encoded_bytes[lane]!=dma_bytes[lane] || paused_cycles[lane]==0)
                $fatal(1,"missing bytes or untested output pause lane=%0d",lane);
            $display("BYTE_CHECK lane=%0d bytes=%0d paused=%0d",lane,dma_bytes[lane],paused_cycles[lane]);
        end
        $display("PASS full source geometry and backpressure recovery; rate budget is informational");
`else
        $display("PASS full source geometry and dual-60 service budget");
`endif
        $finish;
    end
`ifdef PIPELINE_SMOKE_NS
    initial begin
        #`PIPELINE_SMOKE_NS;
        $display("SMOKE ns=%0f raw=%0d isp=%0d processed=%0d",$realtime,raw_seen,isp_seen,pre_seen);
        if(raw_seen==0 || isp_seen==0 || pre_seen==0) $fatal(1,"pipeline did not start");
        $finish;
    end
`endif
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
