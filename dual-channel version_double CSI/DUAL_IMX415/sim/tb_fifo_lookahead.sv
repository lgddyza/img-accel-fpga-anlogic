`timescale 1ns/1ps
module fifo_checker #(parameter REFILL=0,parameter SEED=1)(output reg done=0);
    reg wclk=0,rclk=0,rst_n=0;
    always #3.5 wclk=~wclk;
    always #5.5 rclk=~rclk;
    reg valid=0,ready=0;
    reg [31:0] data=0,wr_random=SEED,rd_random=SEED+123;
    wire s_ready,m_valid;
    wire [31:0] out_data;
    wire [4:0] sl,ml;
    integer sent=0,received=0,phase=0,full_seen=0,empty_seen=0,epoch=0;
    reg held_valid=0;
    reg [31:0] held_data;
    v2_async_fifo #(.WIDTH(32),.ADDR(4),.WRITE_INCREMENT_LOOKAHEAD(1),
        .READ_INCREMENT_LOOKAHEAD(1),.READ_REFILL_ON_POP(REFILL)) dut(
        .rst_n(rst_n),.wclk(wclk),.s_data(data),.s_valid(valid),.s_ready(s_ready),
        .rclk(rclk),.m_data(out_data),.m_valid(m_valid),.m_ready(ready),
        .s_level(sl),.m_level(ml));
    always @(negedge wclk) begin
        wr_random={wr_random[30:0],wr_random[31]^wr_random[21]^wr_random[1]^wr_random[0]};
        valid=rst_n && phase!=2 && (phase==0 || wr_random[1:0]==0);
        data=sent+epoch*100000;
    end
    always @(negedge rclk) begin
        rd_random={rd_random[30:0],rd_random[31]^rd_random[21]^rd_random[1]^rd_random[0]};
        ready=rst_n && (phase!=0 || rd_random[2:0]==0);
    end
    always @(posedge wclk or negedge rst_n)
        if(!rst_n) sent=0;
        else begin
            if(valid && s_ready) sent=sent+1;
            if(!s_ready && dut.wrst[1]) full_seen=full_seen+1;
            if(sl>16) $fatal(1,"writer occupancy invalid: %0d",sl);
        end
    always @(posedge rclk or negedge rst_n)
        if(!rst_n) begin received=0;held_valid=0;end
        else begin
            if(held_valid && (!m_valid || out_data!==held_data))
                $fatal(1,"FIFO changed under backpressure");
            held_valid=m_valid && !ready;held_data=out_data;
            if(m_valid && ready) begin
                if(out_data!==received+epoch*100000)
                    $fatal(1,"FIFO sequence mismatch refill=%0d got=%0d expected=%0d",
                        REFILL,out_data,received+epoch*100000);
                received=received+1;
            end
            if(!m_valid && dut.rrst[1]) empty_seen=empty_seen+1;
            if(ml>17) $fatal(1,"reader occupancy invalid: %0d",ml);
        end
    task run_epoch;
        begin
            phase=0;#31;rst_n=1;
            #30000;phase=1;
            #30000;phase=2;
            #1000;
            if(received!=sent || received<1000)
                $fatal(1,"FIFO drain mismatch refill=%0d sent=%0d received=%0d",REFILL,sent,received);
        end
    endtask
    initial begin
        #1;rst_n=0;
        run_epoch();
        // Reset while the FIFO contains unread entries, then verify a new epoch.
        phase=0;#2000;rst_n=0;epoch=1;
        #100;run_epoch();
        if(full_seen==0 || empty_seen==0) $fatal(1,"missing full/empty coverage");
        $display("PASS async FIFO refill=%0d wrap/full/empty/stall/occupied-reset sent=%0d",REFILL,sent);
        done=1;
    end
endmodule
module tb_fifo_lookahead;
    wire a,b;
    fifo_checker #(.REFILL(0),.SEED(17)) u_no_refill(.done(a));
    fifo_checker #(.REFILL(1),.SEED(59)) u_refill(.done(b));
    initial begin wait(a && b);$finish;end
    initial begin #200000;$fatal(1,"FIFO simulation timeout");end
endmodule
