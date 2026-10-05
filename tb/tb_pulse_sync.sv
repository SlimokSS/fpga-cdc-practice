`timescale 1ns/1ps

module tb_pulse_sync;

logic clk_src;
logic clk_dst;
logic rst_n;

logic event_src;

logic src_ready;
logic event_dst;

pulse_sync dut (
    .clk_src(clk_src),
    .clk_dst(clk_dst),
    .rst_n(rst_n),

    .event_src(event_src),

    .src_ready(src_ready),
    .event_dst(event_dst)
);

task automatic rst_dut;
    begin
        event_src = 1'b0;
        rst_n = 1'b0;

        repeat(3) @(negedge clk_src);
        repeat(3) @(negedge clk_dst);

        rst_n = 1'b1;

        repeat(3) @(negedge clk_src);
        repeat(3) @(negedge clk_dst);

        #1;
    end
endtask

task automatic check_event_dst(input logic exp_event_dst);
    begin
        if (event_dst !== exp_event_dst)
            $fatal(1, "event_dst = %b, expected = %b", event_dst, exp_event_dst);
    end
endtask

task automatic check_src_ready(input logic exp_src_ready);
    begin
        if (src_ready !== exp_src_ready)
            $fatal(1, "src_ready = %b, expected = %b", src_ready, exp_src_ready);
    end
endtask

task automatic wait_ready;
    int timeout;
    begin
        timeout = 0;

        while (src_ready !== 1'b1) begin
            @(negedge clk_src);

            timeout++;

            if (timeout >= 100)
                $fatal(1, "Timeout waiting for src_ready");
        end
    end
endtask

task automatic wait_event;
    int timeout;
    begin
        timeout = 0;

        while (event_dst !== 1'b1) begin
            @(negedge clk_dst);

            timeout++;

            if (timeout >= 100)
                $fatal(1, "Timeout waiting for event_dst");
        end
    end
endtask

task automatic send_event;
    begin
        wait_ready();

        @(negedge clk_src);
        event_src = 1'b1;

        @(posedge clk_src);
        #1;

        check_src_ready(1'b0);

        @(negedge clk_src);
        event_src = 1'b0;
    end
endtask

task automatic receive_event;
    begin
        wait_event();

        check_event_dst(1'b1);

        @(posedge clk_dst);
        #1;

        check_event_dst(1'b0);
    end
endtask

initial begin
    clk_src = 1'b1;
    forever #7 clk_src = ~clk_src;
end

initial begin
    clk_dst = 1'b1;
    forever #25 clk_dst = ~clk_dst;
end

initial begin
    rst_n = 1'b1;
    event_src = 1'b0;

    rst_dut();

    check_event_dst(1'b0);
    check_src_ready(1'b1);

    fork
        begin
            send_event();
        end

        begin
            receive_event();
        end
    join

    wait_ready();
    check_src_ready(1'b1);

    fork
        begin
            send_event();
        end

        begin
            receive_event();
        end
    join

    wait_ready();
    check_src_ready(1'b1);

    fork
        begin
            send_event();
            send_event();
        end

        begin
            receive_event();
            receive_event();
        end
    join

    wait_ready();

    check_src_ready(1'b1);
    check_event_dst(1'b0);

    rst_dut();

    check_event_dst(1'b0);
    check_src_ready(1'b1);

    fork
        begin
            send_event();
        end

        begin
            receive_event();
        end
    join

    wait_ready();

    check_src_ready(1'b1);
    check_event_dst(1'b0);

    $display("tb_pulse_sync is finished");
    $finish;
end

endmodule