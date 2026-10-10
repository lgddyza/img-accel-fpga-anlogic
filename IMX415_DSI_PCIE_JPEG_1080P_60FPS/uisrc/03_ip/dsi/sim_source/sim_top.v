`timescale 1ns/1ps

module sim_top;

    reg S_clk;
    reg S_rst;


    initial begin
        S_clk = 1'b0;
        S_rst = 1'b1;
        #100
        S_rst = 1'b0;
    end

    glbl glbl();

    always #10 S_clk = ~S_clk;

    top u_top(
        .I_clk       ( S_clk   ),
        .I_rst_n     ( ~S_rst  ),

        .O_clk_hs_p  (   ),
        .O_clk_lp_p  (   ),
        .O_clk_lp_n  (   ),
        .O_data_hs_p (   ),
        .O_data_lp_p (   ),
        .O_data_lp_n (   )
    );



endmodule

