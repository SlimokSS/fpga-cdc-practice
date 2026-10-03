`timescale 1ns/1ps

module tb_async_fifo;

localparam int DEPTH = 16;
localparam int WIDTH = 8;

logic clk_wr;
logic clk_rd;

logic rst_n;

logic [WIDTH - 1:0] s_data;
logic s_valid;
logic s_ready;

logic [WIDTH - 1:0] m_data;
logic m_valid;
logic m_ready;

async_fifo #(
    .DEPTH(DEPTH),
    .WIDTH(WIDTH)
) dut (
    .clk_wr(clk_wr),
    .clk_rd(clk_rd),

    .rst_n(rst_n),

    .s_data(s_data),
    .s_valid(s_valid),
    .s_ready(s_ready),

    .m_data(m_data),
    .m_valid(m_valid),
    .m_ready(m_ready)
);

task automatic rst_dut;
    begin
        rst_n = 1'b0;
        repeat (3) @(negedge clk_wr);
        repeat (3) @(negedge clk_rd);
        rst_n = 1'b1;
        repeat (3) @(posedge clk_wr);
        repeat (3) @(posedge clk_rd);
        #1;
    end
endtask

task automatic push(input logic [WIDTH - 1:0] data);

    int timeout;
    logic done;

    begin
        @(negedge clk_wr);
        s_valid = 1'b1;
        s_data = data;
        done = 1'b0;
        timeout = 0;

        while (!done) begin
            @(posedge clk_wr);

            if (s_valid && s_ready) done = 1'b1;

            timeout++;

            if (timeout >= 100) begin
                $fatal(1, "PUSH timeout");
            end

        end

        @(negedge clk_wr);
        s_valid = 1'b0;

    end
endtask


task automatic pop(input logic [WIDTH-1:0] exp_data);
    
    int timeout;
    logic done;

    begin
        @(negedge clk_rd);

        m_ready = 1'b1;
        timeout = 0;
        done = 1'b0;

        while (!done) begin
            @(posedge clk_rd);
            
            if(m_ready && m_valid) begin
                if (m_data !== exp_data) $error("POP error: m_data is equal %h, but must be equal %h", m_data, exp_data);
                done = 1'b1;
            end

            timeout++;

            if (timeout > 100) begin
                $fatal(1, "POP timeout");
            end

        end

        @(negedge clk_rd);

        m_ready = 1'b0;

    end

endtask

task automatic try_write_full(input logic [WIDTH-1:0] data);

    logic [$clog2(DEPTH):0] wr_before;

    begin
        @(negedge clk_wr);

        wr_before = dut.wr_bin;
        s_data = data;
        s_valid = 1'b1;

        @(posedge clk_wr);

        if (s_ready !== 1'b0) $error("s_ready = 1 while FIFO is full");

        if (dut.wr_fire !== 1'b0) $error("Write occurred while FIFO is full");

        #1;

        if (dut.wr_bin !== wr_before) $error("wr_bin changed while FIFO is full");

        @(negedge clk_wr);
        s_valid = 1'b0;

    end
endtask

task automatic try_read_empty;

    logic [$clog2(DEPTH):0] rd_before;

    begin

        @(negedge clk_rd);

        m_ready = 1'b1;
        rd_before = dut.rd_bin;

        @(posedge clk_rd);

        if (m_valid !== 1'b0) $error("m_valid = 1 while FIFO is empty");

        if (dut.rd_fire !== 1'b0) $error("Read occurred while FIFO is empty");

        #1;

        if (dut.rd_bin !== rd_before) $error("rd_bin changed while FIFO is empty");
        
        @(negedge clk_rd);

        m_ready = 1'b0;
    end
    
endtask

task automatic wait_clk_wr(input int n);
    begin
        repeat (n) @(posedge clk_wr);
        #1;
    end
endtask

task automatic wait_clk_rd(input int n);
    begin
        repeat (n) @(posedge clk_rd);
        #1;
    end
endtask

task automatic check_state (input logic exp_empty, input logic exp_full, input logic exp_m_valid, input logic exp_s_ready);
    begin
        if (exp_empty !== dut.empty) $error("Empty is equal %d, but must be equal %d", dut.empty, exp_empty);
        if (exp_full !== dut.full) $error("Full is equal %d, but must be equal %d", dut.full, exp_full);
        if (exp_m_valid !== m_valid) $error("M_valid is equal %d, but must be equal %d", m_valid, exp_m_valid);
        if (exp_s_ready !== s_ready) $error("s_ready is equal %d, but must be equal %d", s_ready, exp_s_ready);
    end
endtask

initial begin
    clk_wr = 1'b1;
    forever #5 clk_wr = ~clk_wr;
end

initial begin
    clk_rd = 1'b1;
    forever #7 clk_rd = ~clk_rd;
end

initial begin
    rst_n = 1'b1;

    s_valid = 1'b0;
    s_data = '0;
    m_ready = 1'b0;

    rst_dut();
    check_state(1'b1,1'b0,1'b0,1'b1);

    push(8'h00);
    wait_clk_rd(3);
    check_state(1'b0,1'b0,1'b1,1'b1);

    push(8'h01);
    push(8'h02);
    push(8'h03);
    push(8'h04);
    push(8'h05);
    push(8'h06);
    push(8'h07);
    push(8'h08);
    push(8'h09);
    push(8'h0A);
    push(8'h0B);
    push(8'h0C);
    push(8'h0D);
    push(8'h0E);
    push(8'h0F);
    wait_clk_rd(3);
    check_state(1'b0,1'b1,1'b1,1'b0);

    pop(8'h00);
    wait_clk_wr(3);
    check_state(1'b0,1'b0,1'b1,1'b1);
    pop(8'h01);
    pop(8'h02);
    pop(8'h03);
    pop(8'h04);
    pop(8'h05);
    pop(8'h06);
    pop(8'h07);
    pop(8'h08);
    pop(8'h09);
    pop(8'h0A);
    pop(8'h0B);
    pop(8'h0C);
    pop(8'h0D);
    pop(8'h0E);
    pop(8'h0F);
    wait_clk_wr(3);
    check_state(1'b1,1'b0,1'b0,1'b1);

    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    push(8'hA5);
    try_write_full(8'hA5);
    wait_clk_rd(3);
    check_state(1'b0,1'b1,1'b1,1'b0);

    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    pop(8'hA5);
    try_read_empty();
    wait_clk_rd(3);
    check_state(1'b1,1'b0,1'b0,1'b1);

    fork

        begin : writer
            for (int i = 0; i < 64; i++) begin
                push(i[WIDTH-1:0]);
            end
        end

        begin : reader
            for (int i = 0; i < 64; i++) begin
                pop(i[WIDTH-1:0]);
            end
        end

    join

    wait_clk_rd(2);
    check_state(1'b1, 1'b0, 1'b0, 1'b1);

    $display("Tb_async_fifo is finished");
    $finish;
end

endmodule