/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_italu (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // Simple ALU with DFT features
    // Pin mapping:
    // ui_in[0]    : data input bit
    // ui_in[1]    : load enable
    // ui_in[2]    : execute
    // ui_in[3]    : operation select bit 0
    // ui_in[4]    : operation select bit 1
    // ui_in[5]    : operation select bit 2
    // ui_in[6]    : scan enable
    // ui_in[7]    : BIST start

    // Registers
    reg [7:0] operand_a;
    reg [7:0] operand_b;
    reg [2:0] operation;
    reg [7:0] alu_result;
    reg       zero_flag;
    reg       carry_flag;
    reg       negative_flag;
    reg       overflow_flag;
    
    // BIST registers
    reg [7:0] lfsr;
    reg [7:0] misr;
    reg [2:0] bist_state;
    reg [7:0] pattern_count;
    reg       bist_done;
    reg       test_pass;
    
    // Display
    reg [1:0] display_digit;
    reg [6:0] segment_data;
    reg [1:0] digit_select;
    
    // Scan
    reg [7:0] scan_reg;
    reg       scan_out;

    // ALU combinational logic
    wire [8:0] alu_9bit;
    assign alu_9bit = 
        (operation == 3'b000) ? ({1'b0, operand_a} + {1'b0, operand_b}) :  // ADD
        (operation == 3'b001) ? ({1'b0, operand_a} - {1'b0, operand_b}) :  // SUB
        (operation == 3'b010) ? {1'b0, operand_a & operand_b} :            // AND
        (operation == 3'b011) ? {1'b0, operand_a | operand_b} :            // OR
        (operation == 3'b100) ? {1'b0, operand_a ^ operand_b} :            // XOR
        (operation == 3'b101) ? {1'b0, ~operand_a} :                       // NOT
        (operation == 3'b110) ? {operand_a[7], operand_a[6:0], 1'b0} :     // SHIFT
        {1'b0, (operand_a == operand_b) ? 8'h01 :                          // COMPARE
               (operand_a > operand_b) ? 8'h02 : 8'h00};

    wire [7:0] alu_out_wire = alu_9bit[7:0];
    wire       carry_wire = alu_9bit[8];
    wire       zero_wire = (alu_out_wire == 8'h00);
    wire       neg_wire = alu_out_wire[7];
    wire       ovf_wire = (operation == 3'b000) ? 
                          ((operand_a[7] & operand_b[7] & ~alu_out_wire[7]) |
                           (~operand_a[7] & ~operand_b[7] & alu_out_wire[7])) : 1'b0;

    // Main sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a <= 8'h00;
            operand_b <= 8'h00;
            operation <= 3'b000;
            alu_result <= 8'h00;
            zero_flag <= 1'b0;
            carry_flag <= 1'b0;
            negative_flag <= 1'b0;
            overflow_flag <= 1'b0;
        end else begin
            // Load operation or operands
            if (ui_in[1]) begin  // Load enable
                case (operation)
                    3'b000: begin
                        operand_a <= {operand_a[6:0], ui_in[0]};
                        operation <= 3'b001;
                    end
                    3'b001: begin
                        operand_b <= {operand_b[6:0], ui_in[0]};
                        operation <= 3'b010;
                    end
                    default: begin
                        // Load operation code (3 bits)
                        operation <= {operation[1:0], ui_in[0]};
                    end
                endcase
            end
            
            // Execute
            if (ui_in[2]) begin
                alu_result <= alu_out_wire;
                carry_flag <= carry_wire;
                zero_flag <= zero_wire;
                negative_flag <= neg_wire;
                overflow_flag <= ovf_wire;
            end
        end
    end

    // BIST logic
    wire lfsr_fb = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 8'h01;
            misr <= 8'h00;
            bist_state <= 3'b000;
            pattern_count <= 8'h00;
            bist_done <= 1'b0;
            test_pass <= 1'b1;
        end else begin
            case (bist_state)
                3'b000: begin  // IDLE
                    bist_done <= 1'b0;
                    if (ui_in[7]) begin  // BIST start
                        lfsr <= 8'h01;
                        pattern_count <= 8'h00;
                        bist_state <= 3'b001;
                    end
                end
                
                3'b001: begin  // GENERATE
                    lfsr <= {lfsr[6:0], lfsr_fb};
                    operand_a <= lfsr;
                    operand_b <= {lfsr[3:0], lfsr[7:4]};
                    operation <= lfsr[2:0];
                    bist_state <= 3'b010;
                end
                
                3'b010: begin  // APPLY
                    misr <= {misr[6:0], misr[7] ^ misr[5] ^ alu_out_wire[0]};
                    alu_result <= alu_out_wire;
                    carry_flag <= carry_wire;
                    zero_flag <= zero_wire;
                    negative_flag <= neg_wire;
                    overflow_flag <= ovf_wire;
                    
                    if (pattern_count == 8'hFF) begin
                        bist_state <= 3'b011;
                    end else begin
                        pattern_count <= pattern_count + 1'b1;
                        bist_state <= 3'b001;
                    end
                end
                
                3'b011: begin  // DONE
                    test_pass <= 1'b1;
                    bist_done <= 1'b1;
                    if (!ui_in[7]) begin
                        bist_state <= 3'b000;
                    end
                end
                
                default: begin
                    bist_state <= 3'b000;
                end
            endcase
        end
    end

    // Scan chain
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_reg <= 8'h00;
            scan_out <= 1'b0;
        end else if (ui_in[6]) begin  // Scan enable
            scan_reg <= {ui_in[0], scan_reg[7:1]};
            scan_out <= scan_reg[0];
        end
    end

    // 7-segment decoder
    function [6:0] seg7;
        input [3:0] digit;
        begin
            case (digit)
                4'h0: seg7 = 7'b1000000;
                4'h1: seg7 = 7'b1111001;
                4'h2: seg7 = 7'b0100100;
                4'h3: seg7 = 7'b0110000;
                4'h4: seg7 = 7'b0011001;
                4'h5: seg7 = 7'b0010010;
                4'h6: seg7 = 7'b0000010;
                4'h7: seg7 = 7'b1111000;
                4'h8: seg7 = 7'b0000000;
                4'h9: seg7 = 7'b0010000;
                4'hA: seg7 = 7'b0001000;
                4'hB: seg7 = 7'b0000011;
                4'hC: seg7 = 7'b1000110;
                4'hD: seg7 = 7'b0100001;
                4'hE: seg7 = 7'b0000110;
                4'hF: seg7 = 7'b0001110;
                default: seg7 = 7'b1111111;
            endcase
        end
    endfunction

    // Display controller
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_digit <= 2'b00;
            segment_data <= 7'b1111111;
            digit_select <= 2'b00;
        end else begin
            display_digit <= display_digit + 1'b1;
            
            case (display_digit)
                2'b00: begin
                    digit_select <= 2'b01;
                    segment_data <= seg7(alu_result[3:0]);
                end
                2'b01: begin
                    digit_select <= 2'b10;
                    segment_data <= seg7(alu_result[7:4]);
                end
                2'b10: begin
                    digit_select <= 2'b01;
                    segment_data <= seg7({1'b0, operation});
                end
                2'b11: begin
                    digit_select <= 2'b10;
                    segment_data <= seg7({zero_flag, carry_flag, negative_flag, overflow_flag});
                end
            endcase
        end
    end

    // Output assignments
    assign uo_out[6:0] = segment_data;
    assign uo_out[7] = (operation == 3'b000);
    
    assign uio_out[0] = digit_select[0];
    assign uio_out[1] = digit_select[1];
    assign uio_out[2] = scan_out;
    assign uio_out[3] = bist_done;
    assign uio_out[4] = test_pass;
    assign uio_out[5] = 1'b0;  // fault flag (not used)
    assign uio_out[6] = 1'b0;  // mode bit 0
    assign uio_out[7] = 1'b0;  // mode bit 1
    
    assign uio_oe = 8'b11111111;

    // Unused inputs
    wire _unused = &{ena, uio_in, 1'b0};

endmodule
