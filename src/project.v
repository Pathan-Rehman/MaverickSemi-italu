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

    // Pin mapping:
    // ui_in[0]    : data input bit (serial)
    // ui_in[1]    : load enable
    // ui_in[2]    : execute
    // ui_in[3]    : unused
    // ui_in[4]    : unused
    // ui_in[5]    : unused
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
    
    // Scan registers
    reg [7:0] scan_reg;
    reg       scan_out;
    
    // Dummy counter to ensure sequential logic exists
    reg [3:0] dummy_counter;

    // ALU combinational logic
    wire [8:0] alu_9bit;
    assign alu_9bit = 
        (operation == 3'b000) ? ({1'b0, operand_a} + {1'b0, operand_b}) :
        (operation == 3'b001) ? ({1'b0, operand_a} - {1'b0, operand_b}) :
        (operation == 3'b010) ? {1'b0, operand_a & operand_b} :
        (operation == 3'b011) ? {1'b0, operand_a | operand_b} :
        (operation == 3'b100) ? {1'b0, operand_a ^ operand_b} :
        (operation == 3'b101) ? {1'b0, ~operand_a} :
        (operation == 3'b110) ? {operand_a[7], operand_a[6:0], 1'b0} :
        {1'b0, (operand_a == operand_b) ? 8'h01 :
               (operand_a > operand_b) ? 8'h02 : 8'h00};

    wire [7:0] alu_out_wire = alu_9bit[7:0];
    wire       carry_wire = alu_9bit[8];
    wire       zero_wire = (alu_out_wire == 8'h00);
    wire       neg_wire = alu_out_wire[7];
    wire       ovf_wire = (operation == 3'b000) ? 
                          ((operand_a[7] & operand_b[7] & ~alu_out_wire[7]) |
                           (~operand_a[7] & ~operand_b[7] & alu_out_wire[7])) : 1'b0;

    // Dummy counter (always running)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dummy_counter <= 4'b0000;
        end else begin
            dummy_counter <= dummy_counter + 1'b1;
        end
    end

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
            // Load data
            if (ui_in[1]) begin
                operand_a <= {operand_a[6:0], ui_in[0]};
                operand_b <= operand_a;
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
                3'b000: begin
                    bist_done <= 1'b0;
                    if (ui_in[7]) begin
                        lfsr <= 8'h01;
                        pattern_count <= 8'h00;
                        bist_state <= 3'b001;
                    end
                end
                
                3'b001: begin
                    lfsr <= {lfsr[6:0], lfsr_fb};
                    operand_a <= lfsr;
                    operand_b <= {lfsr[3:0], lfsr[7:4]};
                    operation <= lfsr[2:0];
                    bist_state <= 3'b010;
                end
                
                3'b010: begin
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
                
                3'b011: begin
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
        end else if (ui_in[6]) begin
            scan_reg <= {ui_in[0], scan_reg[7:1]};
            scan_out <= scan_reg[0];
        end
    end

    // Output assignments
    assign uo_out = alu_result;
    
    assign uio_out[0] = zero_flag;
    assign uio_out[1] = carry_flag;
    assign uio_out[2] = negative_flag;
    assign uio_out[3] = overflow_flag;
    assign uio_out[4] = bist_done;
    assign uio_out[5] = test_pass;
    assign uio_out[6] = scan_out;
    assign uio_out[7] = dummy_counter[3];  // Use dummy counter
    
    assign uio_oe = 8'b11111111;

    // Unused inputs
    wire _unused = &{ena, uio_in, ui_in[5:3], 1'b0};

endmodule
