`default_nettype none
`timescale 1ns/1ps

module tb;

    // Clock generation
    reg clk;
    reg rst_n;
    
    // DUT inputs
    reg [7:0] ui_in;
    reg [7:0] uio_in;
    reg ena;
    
    // DUT outputs
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    
    // Instantiate DUT
    tt_um_italu dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );
    
    // Initial values
    initial begin
        clk = 0;
        rst_n = 0;
        ui_in = 0;
        uio_in = 0;
        ena = 1;
    end
    
    // Remove the $finish call - let cocotb control simulation
    // Clock is controlled by cocotb, so remove the always block
    
    // VCD dump
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
    end

endmodule
