`timescale 1ns/1ps
module pulse_sync (
    input logic clk_src,
    input logic clk_dst,
    input logic rst_n,

    input logic event_src,

    output logic src_ready,
    output logic event_dst
);

logic req_toggle;

logic req_toggle_sync1;
logic req_toggle_sync2;

logic ack_toggle;

logic ack_toggle_sync1;
logic ack_toggle_sync2;

logic rst_n_src1;
logic rst_n_src;

logic rst_n_dst1;
logic rst_n_dst;

assign event_dst = rst_n_dst && (req_toggle_sync2 != ack_toggle); 

assign src_ready = rst_n_src && (req_toggle == ack_toggle_sync2);

always_ff @(posedge clk_src or negedge rst_n) begin
    if (!rst_n) begin
        rst_n_src1 <= 1'b0;
        rst_n_src <= 1'b0;
    end else begin
        rst_n_src1 <= 1'b1;
        rst_n_src <= rst_n_src1;
    end
end

always_ff @(posedge clk_dst or negedge rst_n) begin
    if (!rst_n) begin
        rst_n_dst1 <= 1'b0;
        rst_n_dst <= 1'b0;
    end else begin
        rst_n_dst1 <= 1'b1;
        rst_n_dst <= rst_n_dst1;
    end
end

always_ff @(posedge clk_src or negedge rst_n_src) begin
    if (!rst_n_src) begin
        req_toggle <= 1'b0;
    end else begin
        if (event_src && src_ready) req_toggle <= ~req_toggle;
    end
end

always_ff @(posedge clk_dst or negedge rst_n_dst) begin
    if (!rst_n_dst) begin
        req_toggle_sync1 <= 1'b0;
        req_toggle_sync2 <= 1'b0;
    end else begin
        req_toggle_sync1 <= req_toggle;
        req_toggle_sync2 <= req_toggle_sync1;
    end
end

always_ff @(posedge clk_dst or negedge rst_n_dst) begin
    if (!rst_n_dst) begin
        ack_toggle <= 1'b0;
    end else begin
        if (req_toggle_sync2 != ack_toggle) ack_toggle <= req_toggle_sync2;
    end
end

always_ff @(posedge clk_src or negedge rst_n_src) begin
    if (!rst_n_src) begin
        ack_toggle_sync1 <= 1'b0;
        ack_toggle_sync2 <= 1'b0;
    end else begin
        ack_toggle_sync1 <= ack_toggle;
        ack_toggle_sync2 <= ack_toggle_sync1;
    end
end

endmodule