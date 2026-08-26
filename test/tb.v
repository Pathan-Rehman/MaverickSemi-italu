`default_nettype none
`timescale 1ns/1ps

module tb;

    reg clk;
    reg rst_n;

    reg [7:0] ui_in;
    reg [7:0] uio_in;
    reg ena;

    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_italu dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),

        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),

        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    initial begin

        clk = 1'b0;

        rst_n = 1'b0;

        ui_in = 8'h00;

        uio_in = 8'h00;

        ena = 1'b1;

    end

    // 50 MHz clock
    always #10 clk = ~clk;

    // VCD
    initial begin

        $dumpfile("tb.vcd");

        $dumpvars(0, tb);

    end

endmodule

`default_nettype wire
