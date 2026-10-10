`timescale 1ns/1ps

module sim_top;

    reg S_clk;
    reg S_rst;

    reg[7:0]   S_cnt;

    wire[9:0]      S_rom_addr;
    wire[7:0]      S_rom_data;

    wire           S_fetch_trig;

    wire           S_instruction_valid;
    wire[7:0]      S_instruction_data;

    initial begin
        S_clk = 1'b0;
        S_rst = 1'b1;
        S_cnt = 'd0;
        #100
        S_rst = 1'b0;
    end

    glbl glbl();

    always #10 S_clk = ~S_clk;

    always @(posedge S_clk or posedge S_rst) begin
        if(S_rst)
            S_cnt <= 'd0;
        else
            S_cnt <= S_cnt + 1'b1;
    end

    assign S_fetch_trig = S_cnt == 'd250 ? 1'b1 : 1'b0;

    instruction_rom u_instruction_rom(
        .clka  ( S_clk      ),
        .rsta  ( S_rst      ),
        .doa   ( S_rom_data ),
        .addra ( S_rom_addr )
    );


    instruction_fetch u_instruction_fetch(
        .I_clk               ( S_clk               ),
        .I_rst               ( S_rst               ),

        .I_config_start      ( 1'b0                ),
        .I_fetch_trig        ( S_fetch_trig        ),
        .I_config_end        ( 1'b0                ),

        .O_rom_addr          ( S_rom_addr          ),
        .I_rom_data          ( S_rom_data          )

    );




endmodule