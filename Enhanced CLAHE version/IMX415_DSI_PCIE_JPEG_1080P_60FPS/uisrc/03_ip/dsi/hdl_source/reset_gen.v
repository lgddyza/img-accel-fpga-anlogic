
module reset_gen #(
    parameter [31:0] RESET_CYCLES        = 32'd1000000, // 20 ms at 50 MHz
    parameter [31:0] CONFIG_START_CYCLES = 32'd2500000, // 50 ms at 50 MHz
    parameter [31:0] CONFIG_PULSE_CYCLES = 32'd50000    // 1 ms at 50 MHz
) (
    input wire     I_clk,
    input wire     I_pll_lock,
	input wire     I_rst,

    output wire    O_rst_n,
    output wire    O_rst,

    output wire    O_config_start
);


    reg[31:0]  S_cnt;
    wire [31:0] S_config_end = CONFIG_START_CYCLES + CONFIG_PULSE_CYCLES;
    wire S_reset = I_rst || !I_pll_lock;

    always @(posedge I_clk or posedge S_reset) begin
		if(S_reset)
			S_cnt <= 'd0;
        else
            if(S_cnt >= S_config_end)
                S_cnt <= S_cnt;
            else
                S_cnt <= S_cnt + 1'b1;
    end

    assign O_rst = S_reset || (S_cnt < RESET_CYCLES);
    assign O_rst_n = ~O_rst;
    assign O_config_start = I_pll_lock && !I_rst &&
                            (S_cnt >= CONFIG_START_CYCLES) &&
                            (S_cnt < S_config_end);
    
endmodule
