`timescale 1ns/1ps
// Passive gray4 tap. One Y0/Y1 pair per 16 pixels; no stream backpressure.
module v2_feature_observer #(parameter WIDTH=1920, HEIGHT=1080)(
    input wire clk,rst_n,
    input wire [127:0] rgb,metadata,
    input wire valid,sof,eol,
    output reg [511:0] result,
    output reg result_valid,input wire result_ready
);
    localparam GROUPS=WIDTH/4;
    reg [10:0] column,row;
    reg active;
    reg event_start,event_sample,event_end,event_bad;
    reg [7:0] y0,y1;
    reg [60:0] identity;
    wire line_end=sof ? GROUPS==1 : column==GROUPS-1;
    wire last_row=sof ? HEIGHT==1 : row==HEIGHT-1;
    // Geometry checks run independently of the statistics pipeline.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            column<=0;row<=0;active<=0;
            event_start<=0;event_sample<=0;event_end<=0;event_bad<=0;
            y0<=0;y1<=0;identity<=0;
        end else begin
            event_start<=0;event_sample<=0;event_end<=0;event_bad<=0;
            if(valid && (sof || active)) begin
                if(sof && active) event_bad<=1;
                if(eol!=line_end) begin
                    active<=0;column<=0;row<=0;event_bad<=1;
                end else begin
                    event_start<=sof;
                    event_sample<=sof || column[1:0]==0;
                    event_end<=eol && last_row;
                    y0<=rgb[7:0];y1<=rgb[39:32];
                    if(sof) identity<={metadata[95:64],metadata[32],metadata[27:0]};
                    active<=!(eol && last_row);
                    column<=eol ? 0 : sof ? 1 : column+1'b1;
                    row<=sof ? (eol ? 1 : 0) : eol ? row+1'b1 : row;
                end
            end else if((sof || eol) && !valid) begin
                active<=0;event_bad<=1;
            end
        end
    end
    reg [17:0] samples,dark_count,bright_count;
    reg [24:0] luma_sum,gradient_sum;
    reg [17:0] histogram [0:15];
    reg [60:0] frame_identity;
    reg [15:0] sequence_count,error_count;
    reg finalize;
    wire [7:0] delta=y0>=y1 ? y0-y1 : y1-y0;
    wire overrun=finalize && result_valid && !result_ready;
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            samples<=0;dark_count<=0;bright_count<=0;luma_sum<=0;gradient_sum<=0;
            for(i=0;i<16;i=i+1) histogram[i]<=0;
            frame_identity<=0;sequence_count<=0;error_count<=0;finalize<=0;
            result<=0;result_valid<=0;
        end else begin
            finalize<=event_end;
            if(result_valid && result_ready) result_valid<=0;
            if((event_bad || overrun) && error_count!=16'hffff) error_count<=error_count+1'b1;
            if(event_start) frame_identity<=identity;
            if(event_start || event_sample) begin
                samples<=(event_start ? 18'd0 : samples)+1'b1;
                luma_sum<=(event_start ? 25'd0 : luma_sum)+y0;
                dark_count<=(event_start ? 18'd0 : dark_count)+(y0<32);
                bright_count<=(event_start ? 18'd0 : bright_count)+(y0>224);
                gradient_sum<=(event_start ? 25'd0 : gradient_sum)+delta;
            end
            for(i=0;i<16;i=i+1) begin
                if(event_start) histogram[i]<=y0[7:4]==i ? 18'd1 : 18'd0;
                else if(event_sample && y0[7:4]==i) histogram[i]<=histogram[i]+1'b1;
            end
            if(finalize) begin
                sequence_count<=sequence_count+1'b1;
                if(!result_valid || result_ready) begin
                    result<=0;
                    result[27:0]<=frame_identity[27:0];
                    result[28]<=frame_identity[28];result[29]<=1'b1;
                    result[63:32]<=frame_identity[60:29];
                    result[81:64]<=samples;result[106:82]<=luma_sum;
                    result[124:107]<=dark_count;result[142:125]<=bright_count;
                    result[167:143]<=gradient_sum;
                    for(i=0;i<16;i=i+1) result[168+i*18+:18]<=histogram[i];
                    result[471:456]<=sequence_count+1'b1;
                    result[487:472]<=error_count;
                    result_valid<=1;
                end
            end
        end
    end
endmodule
