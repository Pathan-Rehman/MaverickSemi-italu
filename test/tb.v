`default_nettype none
`timescale 1ns/1ps

module tb (
    // Testbench doesn't have ports
);

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
    
    // Clock generation (50 MHz)
    always #10 clk = ~clk; // 20ns period = 50 MHz
    
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
        
        // Reset sequence
        #100;
        rst_n = 1;
        
        // Test sequence
        #1000;
        
        // End simulation
        $finish;
    end
    
    // VCD dump
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);
    end

endmodule
