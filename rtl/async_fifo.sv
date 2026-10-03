`timescale 1ns/1ps

module async_fifo #(
    parameter int DEPTH = 16,
    parameter int WIDTH = 8
) (
    input logic clk_wr,
    input logic clk_rd,

    input logic rst_n,

    input logic [WIDTH - 1:0] s_data,
    input logic s_valid,
    output logic s_ready,

    output logic [WIDTH - 1:0] m_data,
    output logic m_valid,
    input logic m_ready
);

localparam int ADDR_W = $clog2(DEPTH);

logic [WIDTH - 1:0] mem [0:DEPTH-1];

logic [ADDR_W:0] wr_bin;
logic [ADDR_W:0] wr_bin_next;
logic [ADDR_W:0] wr_gray;
logic [ADDR_W:0] wr_gray_next;

logic [ADDR_W:0] rd_bin;
logic [ADDR_W:0] rd_bin_next;
logic [ADDR_W:0] rd_gray;
logic [ADDR_W:0] rd_gray_next;

logic [ADDR_W:0] rd_gray_sync1;
logic [ADDR_W:0] rd_gray_sync2;

logic [ADDR_W:0] wr_gray_sync1;
logic [ADDR_W:0] wr_gray_sync2;

logic full;
logic empty;

logic full_next;
logic empty_next;

logic wr_fire;
logic rd_fire;

logic rst_n_wr1;
logic rst_n_wr;

logic rst_n_rd1;
logic rst_n_rd;

assign wr_bin_next = wr_bin + wr_fire;
assign wr_gray_next = wr_bin_next ^ (wr_bin_next >> 1);

assign rd_bin_next = rd_bin + rd_fire;
assign rd_gray_next = rd_bin_next ^ (rd_bin_next >> 1);

assign empty_next = (rd_gray_next == wr_gray_sync2);
assign full_next = (wr_gray_next == {~rd_gray_sync2[ADDR_W:ADDR_W-1], rd_gray_sync2[ADDR_W-2:0]});

assign s_ready = !full && rst_n_wr;
assign wr_fire = s_valid && s_ready;

assign m_valid = !empty && rst_n_rd;
assign rd_fire = m_valid && m_ready;

assign m_data = mem[rd_bin[ADDR_W-1:0]];

always_ff @(posedge clk_wr or negedge rst_n) begin
    if (!rst_n) begin
        rst_n_wr1 <= 1'b0;
        rst_n_wr <= 1'b0;
    end else begin
        rst_n_wr1 <= 1'b1;
        rst_n_wr <= rst_n_wr1;
    end
end

always_ff @(posedge clk_rd or negedge rst_n) begin
    if (!rst_n) begin
        rst_n_rd1 <= 1'b0;
        rst_n_rd <= 1'b0;
    end else begin
        rst_n_rd1 <= 1'b1;
        rst_n_rd <= rst_n_rd1;
    end
end


always_ff @(posedge clk_wr or negedge rst_n_wr) begin
    if (!rst_n_wr) begin
        wr_bin <= '0;
        wr_gray <= '0;
    end else begin
        wr_bin <= wr_bin_next;
        wr_gray <= wr_gray_next;
    end
end

always_ff @(posedge clk_rd or negedge rst_n_rd) begin
    if (!rst_n_rd) begin
        rd_bin <= '0;
        rd_gray <= '0;
    end else begin
        rd_bin <= rd_bin_next;
        rd_gray <= rd_gray_next;
    end
end

always_ff @(posedge clk_wr or negedge rst_n_wr) begin
    if (!rst_n_wr) begin
        rd_gray_sync1 <= '0;
        rd_gray_sync2 <= '0;
    end else begin
        rd_gray_sync1 <= rd_gray;
        rd_gray_sync2 <= rd_gray_sync1;
    end
end

always_ff @(posedge clk_rd or negedge rst_n_rd) begin
    if (!rst_n_rd) begin
        wr_gray_sync1 <= '0;
        wr_gray_sync2 <= '0;
    end else begin
        wr_gray_sync1 <= wr_gray;
        wr_gray_sync2 <= wr_gray_sync1;
    end
end

always_ff @(posedge clk_wr or negedge rst_n_wr) begin
    if (!rst_n_wr) begin
        full <= 1'b0;
    end else begin
        full <= full_next;
    end
end

always_ff @(posedge clk_rd or negedge rst_n_rd) begin
    if (!rst_n_rd) begin
        empty <= 1'b1;
    end else begin
        empty <= empty_next;
    end
end

always_ff @(posedge clk_wr) begin
    if (wr_fire) begin
        mem[wr_bin[ADDR_W-1:0]] <= s_data;
    end
end

endmodule