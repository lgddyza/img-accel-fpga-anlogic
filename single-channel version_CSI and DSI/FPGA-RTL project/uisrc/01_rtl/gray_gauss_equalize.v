`timescale 1ns/1ps

// 1288x724 input including halo -> centred 5x5 Gaussian -> 1280x720 HE.
module gray_gauss_equalize (
    input wire clk, rst_n,
    input wire [7:0] s_gray,
    input wire s_valid, s_sof, s_eof, s_abort,
    output wire [7:0] m_gray,
    output wire m_valid, m_sof, m_eof, m_abort,
    output wire [31:0] frame_count,
    output wire lut_ready
);
    localparam INPUT_WIDTH=1288, INPUT_HEIGHT=724;
    reg [10:0] x;
    reg [9:0] y;
    reg active;
    wire [10:0] xn = s_sof ? 11'd0 : x;
    wire [9:0] yn = s_sof ? 10'd0 : y;
    wire take = s_valid && (active || s_sof) && !s_abort;
    reg [31:0] lines [0:INPUT_WIDTH-1]; /* fehdl force_ram=1, ram_style="bram" */
    reg [31:0] rows;
    reg [7:0] gray1;
    reg [10:0] x1;
    reg [9:0] y1;
    reg v1;
    reg [7:0] h0[0:3],h1[0:3],h2[0:3],h3[0:3],h4[0:3];
    reg [11:0] sum0,sum1,sum2,sum3,sum4;
    reg v2,sof2,eof2;
    reg [12:0] pair_outer,pair_inner;
    reg [11:0] centre;
    reg v3,sof3,eof3;
    reg [7:0] gauss;
    reg v4,sof4,eof4;
    reg [3:0] abort_pipe;
    wire [15:0] weighted = {3'd0,pair_outer} + {1'b0,pair_inner,2'b0} +
                           {2'b0,centre,2'b0} + {3'b0,centre,1'b0};
    integer i;
    function [11:0] row_sum;
        input [7:0] a,b,c,d,e;
        begin
            row_sum = {4'd0,a}+{2'd0,b,2'd0}+{2'd0,c,2'd0}+
                      {3'd0,c,1'b0}+{2'd0,d,2'd0}+{4'd0,e};
        end
    endfunction
    // RAM has a synchronous read and a one-cycle delayed write. Halo rows
    // overwrite all old frame data before the first valid output pixel.
    always @(posedge clk) begin
        if (take) rows <= lines[xn];
        if (v1) lines[x1] <= {rows[23:0],gray1};
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x<=0; y<=0; active<=0; gray1<=0; x1<=0; y1<=0; v1<=0;
            v2<=0; sof2<=0; eof2<=0; v3<=0; sof3<=0; eof3<=0;
            v4<=0; sof4<=0; eof4<=0;
            sum0<=0; sum1<=0; sum2<=0; sum3<=0; sum4<=0;
            pair_outer<=0; pair_inner<=0; centre<=0; gauss<=0; abort_pipe<=0;
            for(i=0;i<4;i=i+1) begin h0[i]<=0;h1[i]<=0;h2[i]<=0;h3[i]<=0;h4[i]<=0;end
        end else begin
            abort_pipe <= {abort_pipe[2:0],s_abort};
            v1<=take;
            if (s_abort) active<=0;
            if (take) begin
                gray1<=s_gray; x1<=xn; y1<=yn; active<=!s_eof;
                if(xn==INPUT_WIDTH-1) begin x<=0; y<=yn+1'b1; end
                else begin x<=xn+1'b1; y<=yn; end
            end
            v2<=v1 && x1>=6 && x1<1286 && y1>=4 && y1<INPUT_HEIGHT;
            sof2<=v1 && x1==6 && y1==4;
            eof2<=v1 && x1==1285 && y1==INPUT_HEIGHT-1;
            if(v1) begin
                sum0<=row_sum(gray1,h0[0],h0[1],h0[2],h0[3]);
                sum1<=row_sum(rows[7:0],h1[0],h1[1],h1[2],h1[3]);
                sum2<=row_sum(rows[15:8],h2[0],h2[1],h2[2],h2[3]);
                sum3<=row_sum(rows[23:16],h3[0],h3[1],h3[2],h3[3]);
                sum4<=row_sum(rows[31:24],h4[0],h4[1],h4[2],h4[3]);
                h0[0]<=gray1; h1[0]<=rows[7:0]; h2[0]<=rows[15:8];
                h3[0]<=rows[23:16]; h4[0]<=rows[31:24];
                for(i=1;i<4;i=i+1) begin
                    h0[i]<=h0[i-1];h1[i]<=h1[i-1];h2[i]<=h2[i-1];
                    h3[i]<=h3[i-1];h4[i]<=h4[i-1];
                end
            end
            v3<=v2; sof3<=sof2; eof3<=eof2;
            pair_outer<={1'b0,sum0}+{1'b0,sum4};
            pair_inner<={1'b0,sum1}+{1'b0,sum3}; centre<=sum2;
            v4<=v3; sof4<=sof3; eof4<=eof3; gauss<=weighted[15:8];
        end
    end
    gray_hist_equalize u_equalize (
        .clk(clk), .rst_n(rst_n), .s_gray(gauss),
        .s_valid(v4), .s_sof(sof4), .s_eof(eof4), .s_abort(abort_pipe[3]),
        .m_gray(m_gray), .m_valid(m_valid), .m_sof(m_sof), .m_eof(m_eof),
        .m_abort(m_abort), .frame_count(frame_count), .lut_ready(lut_ready)
    );
endmodule
