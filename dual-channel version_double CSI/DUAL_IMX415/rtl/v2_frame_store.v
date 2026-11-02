`timescale 1ns/1ps
// Six DDR frame slots, three per camera. Only a successful final AXI B
// response publishes READY. READING storage is never reclaimed by capture.
// Complete frames alternate between cameras when both queues are nonempty.
module v2_frame_store #(
    parameter WIDTH=1920,HEIGHT=1080,ADDR_WIDTH=28,
    parameter SLOT_STRIDE=4194304, RAW_IDLE_CYCLES=2,
    parameter READ_OUTSTANDING=2
)(
    input wire clk,rst_n,
    input wire [127:0] a_data,b_data,input wire a_valid,b_valid,
    input wire [15:0] a_level,b_level,
    output wire a_ready,b_ready,
    output wire [ADDR_WIDTH-1:0] awaddr,output wire [7:0] awlen,
    output wire awvalid,input wire awready,
    output wire [127:0] wdata,output wire wlast,wvalid,input wire wready,
    input wire [1:0] bresp,input wire bvalid,output wire bready,
    output wire [ADDR_WIDTH-1:0] araddr,output wire [7:0] arlen,
    output wire arvalid,input wire arready,
    input wire [127:0] rdata,input wire [1:0] rresp,
    input wire rlast,rvalid,output wire rready,
    input wire enable,input wire [2:0] mode_a,mode_b,
    input wire [2:0] strength_a,strength_b,
    input wire [6:0] quality,quality_b,jpeg_quality,input wire independent_qf,input wire [31:0] config_epoch,
    input wire jpeg_armed,jpeg_done,jpeg_fault,
    output reg [127:0] metadata,output wire metadata_valid,
    input wire metadata_ready,
    output reg camera,output wire [2:0] frame_mode,
    output wire [39:0] raw,output wire raw_valid,raw_sof,raw_eol,
    output wire raw_first_row_odd,
    input wire raw_ready,
    output reg [31:0] captured_a,captured_b,dropped_a,dropped_b,
    output reg [31:0] delivered_a,delivered_b,axi_errors,
    output wire [11:0] slot_debug,output reg read_fault,
    output reg [127:0] first_fault,
    output wire [1535:0] diagnostics
);
    localparam WORDS=WIDTH*HEIGHT/8, LINE_WORDS=WIDTH/8;
    localparam FREE=0,WRITING=1,READY=2,READING=3;
    localparam WI=0,WF=1,WA=2,WD=3,WB=4;
    localparam TI=0,TA=1,TD=2,TB=3;
    localparam RI=0,RM=1,RACK=2,RADDR=3,RDATA=4,RWAIT=5,RDONE=6,RFAIL=7;
    reg [1:0] slots [0:5];
    reg [27:0] ids [0:5];
    reg [2:0] write_slot [0:1];
    reg [17:0] expected [0:1];
    reg [27:0] write_id [0:1];
    reg [1:0] writing;
    reg [2:0] ws,rs,read_slot;
    reg wc,write_turn,read_turn;
    reg [4:0] fill;
    reg [3:0] wb,rb;
    reg [17:0] burst_start,read_index,issue_index;
    // Two complete burst banks: capture fills one while AXI drains the other.
    reg [127:0] staging [0:31];
    reg write_bank,send_bank;
    reg [1:0] bank_full,tx_state;
    reg [2:0] bank_slot [0:1];
    reg [17:0] bank_start [0:1];
    reg [1:0] bank_camera,bank_last;
    reg [1:0] pending [0:5];
    reg [5:0] discarded;
    reg [31:0] tick;
    reg [6:0] prepare_count;
    reg [8:0] input_wait;
    reg ar_pending;
    reg [2:0] read_outstanding;
    reg [9:0] read_reserved,read_buffered;
    reg [31:0] ar_tick [0:1];
    reg ar_head,ar_tail;
    reg [31:0] diag [0:47];
    reg [31:0] b_tick,tail_tick,job_tick;
    reg job_seen,tail_seen;
    wire ar_take=arvalid && arready;
    wire r_take=rvalid && rready;
    wire r_finish=r_take && rlast;
    // Reserve the offered AR as well as accepted requests. Occupancy includes
    // the FIFO output register; leave 16 words of conservative headroom.
    wire ar_offer=rs==RDATA && !read_fault && !ar_pending && issue_index<WORDS &&
                  read_outstanding<READ_OUTSTANDING && read_buffered+read_reserved<=224;
    wire [31:0] first_latency=tick-ar_tick[ar_head];
    wire [31:0] b_latency=tick-b_tick;
    wire [31:0] tail_latency=tick-tail_tick;
    wire [31:0] job_interval=tick-job_tick;
    integer j,k;
    reg [2:0] free_slot;
    reg free_found;
    reg [2:0] oldest_a,oldest_b;
    reg have_a,have_b;
    wire [2:0] ready_a={2'd0,slots[0]==READY}+{2'd0,slots[1]==READY}+{2'd0,slots[2]==READY};
    wire [2:0] ready_b={2'd0,slots[3]==READY}+{2'd0,slots[4]==READY}+{2'd0,slots[5]==READY};
    always @* begin
        free_found=0;free_slot=0;
        for(k=0;k<3;k=k+1)
            if(slots[(wc?3:0)+k]==FREE && !free_found) begin
                free_found=1;free_slot=(wc?3:0)+k;
            end
        have_a=0;have_b=0;oldest_a=0;oldest_b=3;
        for(k=0;k<3;k=k+1) begin
            if(slots[k]==READY && (!have_a || $signed(ids[k]-ids[oldest_a])<0)) begin
                have_a=1;oldest_a=k;
            end
            if(slots[k+3]==READY && (!have_b || $signed(ids[k+3]-ids[oldest_b])<0)) begin
                have_b=1;oldest_b=k+3;
            end
        end
    end
    // Independent one-word elastic input stages isolate the capture FIFO
    // RAM outputs from arbitration, frame checks and staging RAM control.
    reg [127:0] a_stage,b_stage;
    reg a_stage_valid,b_stage_valid;
    wire take_a=ws==WF && !wc && !read_fault && a_stage_valid;
    wire take_b=ws==WF && wc && !read_fault && b_stage_valid;
    assign a_ready=!read_fault && (!a_stage_valid || take_a);
    assign b_ready=!read_fault && (!b_stage_valid || take_b);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            a_stage<=0;b_stage<=0;a_stage_valid<=0;b_stage_valid<=0;
        end else begin
            if(a_ready) begin
                a_stage_valid<=a_valid;
                if(a_valid) a_stage<=a_data;
            end
            if(b_ready) begin
                b_stage_valid<=b_valid;
                if(b_valid) b_stage<=b_data;
            end
        end
    end
    wire [127:0] sd=wc?b_stage:a_stage;
    wire sv=wc?b_stage_valid:a_stage_valid;
    wire [17:0] si=sd[97:80];
    wire [27:0] sf=sd[125:98];
    assign awaddr=bank_slot[send_bank]*SLOT_STRIDE+bank_start[send_bank]*16;
    assign awlen=15;
    assign awvalid=tx_state==TA && !read_fault;
    assign wdata=staging[{send_bank,wb}];
    assign wlast=wb==15;
    assign wvalid=tx_state==TD && !read_fault;
    assign bready=tx_state==TB && !read_fault;
    wire queue_push=ws==WF && sv && !read_fault && fill==15 && writing[wc] &&
                    !sd[127] && sf==write_id[wc] && si==expected[wc];
    wire queue_pop=bvalid && bready;
    wire write_error=queue_pop && bresp!=0;
    wire start_job=rs==RI && enable && jpeg_armed && !jpeg_fault && (have_a || have_b);
    wire timeout_drop=!read_fault && ws==WF && !sv && &input_wait && writing[wc];
    wire new_sof=!read_fault && ws==WF && sv && si==0 && fill==0 && !sd[127];
    wire bad_word=!read_fault && ws==WF && sv && !new_sof && writing[wc] &&
                  (sd[127] || sf!=write_id[wc] || si!=expected[wc]);
    wire [6:0] drop_events={write_error,new_sof && writing[wc],bad_word && sd[127],
                           bad_word && !sd[127] && sf==write_id[wc] && si!=expected[wc],
                           bad_word && !sd[127] && sf!=write_id[wc],timeout_drop,
                           new_sof && !free_found};
    wire read_error=r_take && (rresp!=0 || rlast!=(rb==15));
    wire [2:0] fault_reason=write_error ? 3'd1 : read_error ? (rresp!=0 ? 3'd2 : 3'd3) : 3'd4;
    assign araddr=read_slot*SLOT_STRIDE+issue_index*16;
    assign arlen=15;
    assign arvalid=ar_pending;
    wire rf_ready,rf_valid,rf_take;
    wire [127:0] rf_word;
    assign rready=read_outstanding!=0 && (read_fault || rf_ready);
    wire rf_push=rvalid && rready && !read_fault;
    // The consumer needs one word per two clocks; decouple admission/reset
    // control from the RAM read enable and read-pointer carry chain.
    v2_async_fifo #(.WIDTH(128),.ADDR(8),.READ_INCREMENT_LOOKAHEAD(1),.READ_REFILL_ON_POP(0)) u_read_fifo (
        .rst_n(rst_n),.wclk(clk),.s_data(rdata),.s_valid(rf_push),.s_ready(rf_ready),
        .rclk(clk),.m_data(rf_word),.m_valid(rf_valid),.m_ready(rf_take));
    reg [7:0] pace;
    reg [17:0] output_index;
    reg [10:0] line_word;
    wire sending=(rs==RADDR || rs==RDATA || rs==RWAIT) && !read_fault;
    assign raw_valid=sending && rf_valid && pace<2 && raw_ready;
    assign raw=pace==0 ? rf_word[39:0] : rf_word[79:40];
    assign raw_sof=raw_valid && pace==0 && output_index==0;
    assign raw_eol=raw_valid && pace==1 && line_word==LINE_WORDS-1;
    assign raw_first_row_odd=rf_word[126];
    assign rf_take=raw_valid && pace==1;
    assign frame_mode=metadata[42:40];
    assign metadata_valid=rs==RM;
    generate for(genvar g=0;g<6;g=g+1) begin: g_debug
        assign slot_debug[g*2+:2]=slots[g];
    end endgenerate
    generate for(genvar d=0;d<48;d=d+1) begin:g_diagnostics
        assign diagnostics[d*32+:32]=diag[d];
    end endgenerate
    initial begin
        if(WORDS%16 || WIDTH%8 || WORDS*16>SLOT_STRIDE)
            $error("v2_frame_store: geometry must align to 16-word bursts and slot stride");
        if(READ_OUTSTANDING<1 || READ_OUTSTANDING>2 || SLOT_STRIDE%4096)
            $error("v2_frame_store: support 1/2 ordered reads and 4KiB aligned slots");
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(j=0;j<6;j=j+1) begin slots[j]<=FREE;ids[j]<=0;pending[j]<=0;end
            for(j=0;j<2;j=j+1) begin write_slot[j]<=0;expected[j]<=0;write_id[j]<=0;end
            writing<=0;ws<=WI;rs<=RI;wc<=0;write_turn<=0;read_turn<=0;
            fill<=0;wb<=0;burst_start<=0;read_index<=0;issue_index<=0;read_slot<=0;
            captured_a<=0;captured_b<=0;dropped_a<=0;dropped_b<=0;
            delivered_a<=0;delivered_b<=0;axi_errors<=0;tick<=0;
            metadata<=0;camera<=0;pace<=0;output_index<=0;line_word<=0;rb<=0;
            read_fault<=0;prepare_count<=0;input_wait<=0;first_fault<=0;
            write_bank<=0;send_bank<=0;bank_full<=0;tx_state<=TI;
            bank_camera<=0;bank_last<=0;discarded<=0;
            for(j=0;j<2;j=j+1) begin bank_slot[j]<=0;bank_start[j]<=0;end
            ar_pending<=0;read_outstanding<=0;read_reserved<=0;read_buffered<=0;
            ar_head<=0;ar_tail<=0;ar_tick[0]<=0;ar_tick[1]<=0;
            b_tick<=0;tail_tick<=0;job_tick<=0;job_seen<=0;tail_seen<=0;
            for(j=0;j<48;j=j+1) diag[j]<=0;
        end else begin
            tick<=tick+1'b1;
            diag[0]<=32'h44353031; // D501: frozen 48-word diagnostic ABI
            diag[1]<=READ_OUTSTANDING;diag[2]<=tick;
            for(j=0;j<7;j=j+1) begin
                if(drop_events[j] && (j==6 ? !bank_camera[send_bank] : !wc)) diag[3+j*2]<=diag[3+j*2]+1'b1;
                if(drop_events[j] && (j==6 ? bank_camera[send_bank] : wc)) diag[4+j*2]<=diag[4+j*2]+1'b1;
            end
            if(ar_take) diag[17]<=diag[17]+1'b1;
            if(r_take) diag[18]<=diag[18]+1'b1;
            if(read_outstanding!=0 && !rvalid) diag[19]<=diag[19]+1'b1;
            if(r_take && rb==0) begin
                diag[20]<=diag[20]+first_latency;
                if(first_latency>diag[21]) diag[21]<=first_latency;
            end
            if({29'd0,read_outstanding}>diag[22]) diag[22]<={29'd0,read_outstanding};
            if({22'd0,read_buffered}>diag[23]) diag[23]<={22'd0,read_buffered};
            if(awvalid && awready) begin diag[24]<=diag[24]+1'b1;b_tick<=tick;end
            if(wvalid && wready) diag[25]<=diag[25]+1'b1;
            if(queue_pop) begin
                diag[26]<=diag[26]+1'b1;diag[27]<=diag[27]+b_latency;
                if(b_latency>diag[28]) diag[28]<=b_latency;
            end
            if(&bank_full) diag[29]<=diag[29]+1'b1;
            if(enable && rs==RI && !have_a && !have_b) diag[30]<=diag[30]+1'b1;
            if(enable && (rs==RI || rs==RACK) && !jpeg_armed) diag[31]<=diag[31]+1'b1;
            if(rs==RDONE && jpeg_done && tail_seen) begin
                diag[32]<=diag[32]+tail_latency;
                if(tail_latency>diag[33]) diag[33]<=tail_latency;
            end
            if(start_job) begin
                diag[34]<=diag[34]+1'b1;job_tick<=tick;job_seen<=1;tail_seen<=0;
                if(job_seen) begin
                    diag[35]<=diag[35]+job_interval;
                    if(job_interval>diag[36]) diag[36]<=job_interval;
                end
            end
            // SOF interruption and no-free may both happen in the same cycle.
            // Record the complete cause mask and write owner, not the reader.
            if(!diag[37][0] && |drop_events) begin
                diag[37]<={12'd0,ws,tx_state,(write_error?bank_slot[send_bank]:write_slot[wc]),
                           (write_error?bank_camera[send_bank]:wc),1'b0,drop_events,1'b1};
                diag[38]<=write_error ? {4'd0,ids[bank_slot[send_bank]]} : {4'd0,sf};
                diag[39]<={14'd0,si};diag[40]<=tick;
            end
            diag[41]<={9'd0,read_outstanding,read_reserved,read_buffered};
            if({30'd0,bank_full[0]}+bank_full[1]>diag[42]) diag[42]<={30'd0,bank_full[0]}+bank_full[1];
            if(ready_a>diag[43][2:0]) diag[43][2:0]<=ready_a;
            if(ready_b>diag[43][18:16]) diag[43][18:16]<=ready_b;
            if(sending && raw_valid && pace==1 && output_index+1==WORDS) begin
                tail_tick<=tick;tail_seen<=1;diag[44]<=diag[44]+1'b1;
            end
            if(read_outstanding!=0 && !rvalid && rb!=0) diag[45]<=diag[45]+1'b1;
            if(arvalid && !arready) diag[46]<=diag[46]+1'b1;
            if(rvalid && !rready) diag[47]<=diag[47]+1'b1;
            if(ar_offer) ar_pending<=1;
            if(ar_take) begin
                ar_pending<=0;issue_index<=issue_index+16;
                ar_tick[ar_tail]<=tick;ar_tail<=~ar_tail;
            end
            if(r_finish) begin
                ar_head<=~ar_head;
                if(read_index+16<WORDS) read_index<=read_index+16;
            end
            case({ar_take,r_finish})
                2'b10: read_outstanding<=read_outstanding+1'b1;
                2'b01: read_outstanding<=read_outstanding-1'b1;
            endcase
            case({ar_offer,r_take})
                2'b10: read_reserved<=read_reserved+16;
                2'b01: read_reserved<=read_reserved-1'b1;
                2'b11: read_reserved<=read_reserved+15;
            endcase
            case({rf_push,rf_take})
                2'b10: read_buffered<=read_buffered+1'b1;
                2'b01: read_buffered<=read_buffered-1'b1;
            endcase
            if(r_take) rb<=rlast ? 4'd0 : rb+1'b1;
            if(!first_fault[0] && (write_error || read_error || (jpeg_fault && rs!=RI)))
                first_fault<={4'd0,metadata[27:0],14'd0,output_index,14'd0,read_index,
                    10'd0,bresp,rlast,rresp,rb,read_slot,camera,tx_state,rs,fault_reason,1'b1};
            if(!read_fault) case(ws)
                WI: begin
                    fill<=0;input_wait<=0;
                    if(!bank_full[write_bank] && (a_stage_valid || b_stage_valid)) begin
                        // A fixed burst alternation can strand the faster
                        // source behind a nearly empty slower source. Prefer
                        // the larger reader-domain backlog, alternate ties.
                        if(a_stage_valid && b_stage_valid) begin
                            if({1'b0,a_level}+a_stage_valid>{1'b0,b_level}+b_stage_valid+17'd16) wc<=0;
                            else if({1'b0,b_level}+b_stage_valid>{1'b0,a_level}+a_stage_valid+17'd16) wc<=1;
                            else wc<=write_turn;
                        end else wc<=b_stage_valid;
                        ws<=WF;
                    end
                end
                WF: if(!sv) begin
                    if(&input_wait) begin
                        ws<=WI;write_turn<=~wc;
                        if(writing[wc]) begin
                            discarded[write_slot[wc]]<=1;writing[wc]<=0;
                            if(wc) dropped_b<=dropped_b+1'b1;else dropped_a<=dropped_a+1'b1;
                        end
                    end else input_wait<=input_wait+1'b1;
                end else begin
                    input_wait<=0;
                    if(si==0 && fill==0 && !sd[127]) begin
                        // A new SOF also releases an incomplete preceding source frame.
                        if(writing[wc]) begin
                            discarded[write_slot[wc]]<=1;
                            if(wc) dropped_b<=dropped_b+1'b1;else dropped_a<=dropped_a+1'b1;
                        end
                        if(free_found) begin
                            write_slot[wc]<=free_slot;slots[free_slot]<=WRITING;
                            ids[free_slot]<=sf;write_id[wc]<=sf;expected[wc]<=1;
                            writing[wc]<=1;staging[{write_bank,4'd0}]<=sd;fill<=1;burst_start<=0;
                            discarded[free_slot]<=0;
                        end else begin
                            writing[wc]<=0;ws<=WI;write_turn<=~wc;
                            if(wc) dropped_b<=dropped_b+1'b1;else dropped_a<=dropped_a+1'b1;
                        end
                    end else if(!writing[wc]) begin ws<=WI;write_turn<=~wc;end
                    else if(sd[127] || sf!=write_id[wc] || si!=expected[wc]) begin
                        discarded[write_slot[wc]]<=1;writing[wc]<=0;ws<=WI;fill<=0;write_turn<=~wc;
                        if(wc) dropped_b<=dropped_b+1'b1;else dropped_a<=dropped_a+1'b1;
                    end else begin
                        staging[{write_bank,fill[3:0]}]<=sd;expected[wc]<=expected[wc]+1'b1;
                        if(fill==0) burst_start<=si;
                        if(fill==15) begin
                            bank_slot[write_bank]<=write_slot[wc];bank_start[write_bank]<=burst_start;
                            bank_camera[write_bank]<=wc;bank_last[write_bank]<=expected[wc]+1==WORDS;
                            bank_full[write_bank]<=1;write_bank<=~write_bank;
                            ws<=WI;fill<=0;write_turn<=~wc;
                            if(expected[wc]+1==WORDS) writing[wc]<=0;
                        end else fill<=fill+1'b1;
                    end
                end
            endcase
            if(!read_fault) case(tx_state)
                TI: if(bank_full[send_bank]) tx_state<=TA;
                TA: if(awready) begin tx_state<=TD;wb<=0;end
                TD: if(wready) begin
                    if(wb==15) tx_state<=TB;else wb<=wb+1'b1;
                end
                TB: if(bvalid) begin
                    bank_full[send_bank]<=0;send_bank<=~send_bank;tx_state<=TI;
                    if(bresp!=0) begin
                        // Stop the complete stream on write errors. Queued old
                        // bursts must never overwrite a newly reallocated slot.
                        read_fault<=1;
                        if(bank_camera[send_bank]) dropped_b<=dropped_b+1'b1;
                        else dropped_a<=dropped_a+1'b1;
                    end else if(bank_last[send_bank] && !discarded[bank_slot[send_bank]]) begin
                        slots[bank_slot[send_bank]]<=READY;
                        if(bank_camera[send_bank]) captured_b<=captured_b+1'b1;
                        else captured_a<=captured_a+1'b1;
                    end
                end
            endcase
            for(j=0;j<6;j=j+1) begin
                case({queue_push && write_slot[wc]==j,queue_pop && bank_slot[send_bank]==j})
                    2'b10: pending[j]<=pending[j]+1'b1;
                    2'b01: pending[j]<=pending[j]-1'b1;
                endcase
                // Reclaim aborted frames only once every previously queued
                // write has completed; READING/READY slots are never reused.
                if(discarded[j] && pending[j]==0) begin slots[j]<=FREE;discarded[j]<=0;end
            end
            case(rs)
                RI: if(enable && jpeg_armed && !jpeg_fault && (have_a || have_b)) begin
                    camera<=have_a && have_b ? read_turn : have_b;
                    read_slot<=have_a && have_b ? (read_turn?oldest_b:oldest_a) : (have_b?oldest_b:oldest_a);
                    if(have_a && (!have_b || !read_turn)) begin
                        slots[oldest_a]<=READING;
                        metadata<={tick,config_epoch,5'd0,strength_a,1'b0,quality,5'd0,mode_a,8'd0,4'd0,ids[oldest_a]};
                    end else begin
                        slots[oldest_b]<=READING;
                        metadata<={tick,config_epoch,5'd0,strength_b,1'b0,(independent_qf ? quality_b : quality),5'd0,mode_b,8'd1,4'd0,ids[oldest_b]};
                    end
                    rs<=RM;read_index<=0;issue_index<=0;output_index<=0;line_word<=0;pace<=0;
                end
                RM: if(metadata_ready) begin rs<=RACK;prepare_count<=127;end
                RACK: begin
                    if(prepare_count!=0) prepare_count<=prepare_count-1'b1;
                    else if(metadata_ready && jpeg_armed && jpeg_quality==metadata[54:48]) rs<=RDATA;
                end
                RDATA: if(issue_index==WORDS && !ar_pending && read_outstanding==0) rs<=RWAIT;
                RWAIT: if(output_index==WORDS) rs<=RDONE;
                RDONE: if(jpeg_done) begin
                    slots[read_slot]<=FREE;rs<=RI;read_turn<=~camera;
                    if(camera) delivered_b<=delivered_b+1'b1;else delivered_a<=delivered_a+1'b1;
                end
                RFAIL: rs<=RFAIL; // Host must reset the complete stream, not publish corrupt JPEG.
            endcase
            if(sending) begin
                if(pace>=2) begin
                    if(pace==RAW_IDLE_CYCLES+1) pace<=0;else pace<=pace+1'b1;
                end else if(raw_valid) begin
                    if(pace==1) begin
                        output_index<=output_index+1'b1;
                        line_word<=line_word==LINE_WORDS-1 ? 11'd0 : line_word+1'b1;
                        pace<=RAW_IDLE_CYCLES==0 ? 0 : 2;
                    end else pace<=1;
                end
            end
            if(jpeg_fault && rs!=RI) begin read_fault<=1;rs<=RFAIL;end
            if(read_error) begin read_fault<=1;rs<=RFAIL;end
            if(write_error || read_error) begin
                axi_errors<=axi_errors+1'b1;
            end
        end
    end
endmodule
