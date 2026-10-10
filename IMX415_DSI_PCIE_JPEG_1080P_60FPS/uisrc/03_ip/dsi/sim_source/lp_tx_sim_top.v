`timescale 1ns/1ps

module lp_tx_sim_top;

    reg      S_clk;
    reg      S_rst;

    reg      S_lp_tx_valid;
    reg[7:0] S_lp_tx_data;
    wire     S_lp_tx_last;
    reg      S_lp_tx_trig;
    reg[3:0] S_lp_tx_cnt;
    wire     S_lp_tx_ready;
    reg      S_lp_tx_ready_1d;
    wire     S_lp_tx_ready_p_edge;

    initial begin
        S_clk         = 1'b0;
        S_rst         = 1'b1;
        S_lp_tx_data  = 'd0;
        S_lp_tx_valid = 1'b0;
        S_lp_tx_trig  = 1'b0;
        S_lp_tx_cnt   = 'd0;
        #1000
        S_rst         = 1'b0;
        S_lp_tx_trig  = 1'b1;
        #400
        S_lp_tx_trig  = 1'b0;
    end

    always #100 S_clk = ~S_clk;

    glbl glbl();

    always @(posedge S_clk) begin
        if(S_lp_tx_trig || S_lp_tx_ready_p_edge)
            S_lp_tx_valid <= 1'b1;
        else if(S_lp_tx_cnt == 'd7)
            S_lp_tx_valid <= 1'b0;
        else
            S_lp_tx_valid <= S_lp_tx_valid;
    end

    always @(posedge S_clk) begin
        if(S_lp_tx_valid)   
            S_lp_tx_cnt <= S_lp_tx_cnt + 1'b1;
        else
            S_lp_tx_cnt <= 'd0;
    end

    assign S_lp_tx_last = S_lp_tx_valid && S_lp_tx_cnt == 'd7 ? 1'b1 : 1'b0;

    always @(posedge S_clk) begin
        if(S_lp_tx_valid)
            S_lp_tx_data <= S_lp_tx_data + 1'b1;
        else
            S_lp_tx_data <= 'd0;
    end

    always @(posedge S_clk) begin
        S_lp_tx_ready_1d <= S_lp_tx_ready;
    end

    assign S_lp_tx_ready_p_edge = ~S_lp_tx_ready_1d & S_lp_tx_ready;

    lp_tx_wrapper u_lp_tx_wrapper(
        .I_clk         ( S_clk         ),
        .I_rst         ( S_rst         ),

        .I_lp_tx_valid ( S_lp_tx_valid ),
        .I_lp_tx_data  ( S_lp_tx_data  ),
        .I_lp_tx_last  ( S_lp_tx_last  ),
        .O_lp_tx_ready ( S_lp_tx_ready ),

        .O_lp_tx_p     (      ),
        .O_lp_tx_n     (      )
    );

    
endmodule