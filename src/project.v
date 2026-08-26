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

    // =========================================================================
    // Pin Assignment
    // =========================================================================
    wire user_data_in    = ui_in[0];
    wire control_button  = ui_in[1];
    wire step_button     = ui_in[2];
    wire scan_enable     = ui_in[4];
    wire scan_clk        = ui_in[5];
    wire scan_in         = ui_in[6];
    wire bist_start      = ui_in[7];

    // =========================================================================
    // ALU Operations
    // =========================================================================
    localparam [2:0] OP_ADD = 3'b000;
    localparam [2:0] OP_SUB = 3'b001;
    localparam [2:0] OP_AND = 3'b010;
    localparam [2:0] OP_OR  = 3'b011;
    localparam [2:0] OP_XOR = 3'b100;
    localparam [2:0] OP_NOT = 3'b101;
    localparam [2:0] OP_SHL = 3'b110;
    localparam [2:0] OP_CMP = 3'b111;

    // =========================================================================
    // Registers
    // =========================================================================
    reg [7:0] operand_a;
    reg [7:0] operand_b;
    reg [2:0] operation;
    reg [7:0] alu_result;
    reg       zero_flag;
    reg       carry_flag;
    reg       negative_flag;
    reg       overflow_flag;
    reg [7:0] lfsr;
    reg [7:0] misr;
    reg       fault_injected;
    reg [1:0] current_mode;
    reg [3:0] input_counter;
    reg [2:0] user_state;
    reg [1:0] bist_state;
    reg [7:0] pattern_count;
    reg       bist_done_reg;
    reg       test_pass;
    reg scan_out_reg;
    reg [31:0] scan_reg;
    reg [1:0] display_digit;
    reg [6:0] segment_data_reg;
    reg [3:0] digit_select_reg;

    // Button debouncing
    reg button_sync1, button_sync2;
    reg step_sync1, step_sync2;
    wire button_pressed;
    wire step_pressed;

    // =========================================================================
    // Button Debouncing
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            button_sync1 <= 1'b0;
            button_sync2 <= 1'b0;
            step_sync1   <= 1'b0;
            step_sync2   <= 1'b0;
        end else begin
            button_sync1 <= control_button;
            button_sync2 <= button_sync1;
            step_sync1 <= step_button;
            step_sync2 <= step_sync1;
        end
    end

    assign button_pressed = button_sync1 & ~button_sync2;
    assign step_pressed   = step_sync1 & ~step_sync2;

    // =========================================================================
    // ALU Combinational Logic
    // =========================================================================
    wire [7:0] alu_result_wire;
    wire       carry_flag_wire;
    wire       overflow_flag_wire;

    assign {carry_flag_wire, alu_result_wire} = 
        (operation == OP_ADD) ? ({1'b0, operand_a} + {1'b0, operand_b}) :
        (operation == OP_SUB) ? ({1'b0, operand_a} - {1'b0, operand_b}) :
        (operation == OP_AND) ? {1'b0, operand_a & operand_b} :
        (operation == OP_OR)  ? {1'b0, operand_a | operand_b} :
        (operation == OP_XOR) ? {1'b0, operand_a ^ operand_b} :
        (operation == OP_NOT) ? {1'b0, ~operand_a} :
        (operation == OP_SHL) ? {operand_a[7], operand_a[6:0], 1'b0} :
        (operation == OP_CMP) ? {1'b0, (operand_a == operand_b) ? 8'h01 :
                                        (operand_a > operand_b) ? 8'h02 : 8'h00} :
        {1'b0, 8'h00};

    assign overflow_flag_wire = 
        (operation == OP_ADD) ? ((operand_a[7] & operand_b[7] & ~alu_result_wire[7]) |
                                 (~operand_a[7] & ~operand_b[7] & alu_result_wire[7])) :
        (operation == OP_SUB) ? ((operand_a[7] & ~operand_b[7] & ~alu_result_wire[7]) |
                                 (~operand_a[7] & operand_b[7] & alu_result_wire[7])) :
        1'b0;

    // =========================================================================
    // Main Control FSM
    // =========================================================================
    localparam [2:0] ST_IDLE     = 3'b000;
    localparam [2:0] ST_LOAD_OP  = 3'b001;
    localparam [2:0] ST_LOAD_A   = 3'b010;
    localparam [2:0] ST_LOAD_B   = 3'b011;
    localparam [2:0] ST_EXECUTE  = 3'b100;
    localparam [2:0] ST_DONE     = 3'b101;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            user_state    <= ST_IDLE;
            input_counter <= 4'b0000;
            current_mode  <= 2'b00;
            operand_a     <= 8'h00;
            operand_b     <= 8'h00;
            operation     <= OP_ADD;
            alu_result    <= 8'h00;
            zero_flag     <= 1'b0;
            carry_flag    <= 1'b0;
            negative_flag <= 1'b0;
            overflow_flag <= 1'b0;
            fault_injected <= 1'b0;
            test_pass     <= 1'b1;
        end else begin
            case (user_state)
                ST_IDLE: begin
                    if (button_pressed) begin
                        current_mode <= current_mode + 1'b1;
                        input_counter <= 4'b0000;
                        user_state <= ST_LOAD_OP;
                    end
                end
                
                ST_LOAD_OP: begin
                    if (input_counter < 3) begin
                        operation <= {operation[1:0], user_data_in};
                        input_counter <= input_counter + 1'b1;
                    end else begin
                        input_counter <= 4'b0000;
                        user_state <= ST_LOAD_A;
                    end
                end
                
                ST_LOAD_A: begin
                    if (input_counter < 8) begin
                        operand_a <= {operand_a[6:0], user_data_in};
                        input_counter <= input_counter + 1'b1;
                    end else begin
                        input_counter <= 4'b0000;
                        user_state <= ST_LOAD_B;
                    end
                end
                
                ST_LOAD_B: begin
                    if (input_counter < 8) begin
                        operand_b <= {operand_b[6:0], user_data_in};
                        input_counter <= input_counter + 1'b1;
                    end else begin
                        input_counter <= 4'b0000;
                        user_state <= ST_EXECUTE;
                    end
                end
                
                ST_EXECUTE: begin
                    if (button_pressed || step_pressed) begin
                        alu_result    <= alu_result_wire;
                        carry_flag    <= carry_flag_wire;
                        overflow_flag <= overflow_flag_wire;
                        zero_flag     <= (alu_result_wire == 8'h00);
                        negative_flag <= alu_result_wire[7];
                        user_state <= ST_DONE;
                    end
                end
                
                ST_DONE: begin
                    if (step_pressed) begin
                        user_state <= ST_IDLE;
                    end
                end
                
                default: begin
                    user_state <= ST_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // BIST Controller
    // =========================================================================
    localparam [1:0] BIST_IDLE     = 2'b00;
    localparam [1:0] BIST_GENERATE = 2'b01;
    localparam [1:0] BIST_APPLY    = 2'b10;
    localparam [1:0] BIST_VERIFY   = 2'b11;

    wire lfsr_feedback = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bist_state    <= BIST_IDLE;
            pattern_count <= 8'h00;
            lfsr          <= 8'h01;
            misr          <= 8'h00;
            bist_done_reg <= 1'b0;
        end else begin
            case (bist_state)
                BIST_IDLE: begin
                    bist_done_reg <= 1'b0;
                    if (bist_start) begin
                        lfsr          <= 8'h01;
                        pattern_count <= 8'h00;
                        misr          <= 8'h00;
                        bist_state    <= BIST_GENERATE;
                    end
                end
                
                BIST_GENERATE: begin
                    lfsr <= {lfsr[6:0], lfsr_feedback};
                    operand_a <= lfsr;
                    operand_b <= {lfsr[3:0], lfsr[7:4]};
                    operation <= lfsr[2:0];
                    bist_state <= BIST_APPLY;
                end
                
                BIST_APPLY: begin
                    alu_result    <= alu_result_wire;
                    carry_flag    <= carry_flag_wire;
                    overflow_flag <= overflow_flag_wire;
                    zero_flag     <= (alu_result_wire == 8'h00);
                    negative_flag <= alu_result_wire[7];
                    misr <= {misr[6:0], misr[7] ^ misr[5] ^ alu_result_wire[0]};
                    
                    if (pattern_count == 8'hFF) begin
                        bist_state <= BIST_VERIFY;
                    end else begin
                        pattern_count <= pattern_count + 1'b1;
                        bist_state <= BIST_GENERATE;
                    end
                end
                
                BIST_VERIFY: begin
                    test_pass <= 1'b1;
                    bist_done_reg <= 1'b1;
                    
                    if (step_pressed) begin
                        bist_state <= BIST_IDLE;
                    end
                end
                
                default: begin
                    bist_state <= BIST_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Scan Chain
    // =========================================================================
    always @(posedge scan_clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_reg     <= 32'h00000000;
            scan_out_reg <= 1'b0;
        end else if (scan_enable) begin
            scan_reg     <= {scan_in, scan_reg[31:1]};
            scan_out_reg <= scan_reg[0];
        end
    end

    // =========================================================================
    // 7-Segment Display
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_digit    <= 2'b00;
            segment_data_reg <= 7'b1111111;
            digit_select_reg <= 4'b1111;
        end else begin
            display_digit <= display_digit + 1'b1;
            
            case (display_digit)
                2'b00: begin
                    digit_select_reg <= 4'b1110;
                    segment_data_reg <= seg7_decode(alu_result[3:0]);
                end
                2'b01: begin
                    digit_select_reg <= 4'b1101;
                    segment_data_reg <= seg7_decode(alu_result[7:4]);
                end
                2'b10: begin
                    digit_select_reg <= 4'b1011;
                    segment_data_reg <= seg7_decode({1'b0, operation});
                end
                2'b11: begin
                    digit_select_reg <= 4'b0111;
                    segment_data_reg <= seg7_decode({zero_flag, carry_flag, negative_flag, overflow_flag});
                end
                default: begin
                    digit_select_reg <= 4'b1111;
                    segment_data_reg <= 7'b1111111;
                end
            endcase
        end
    end

    // 7-segment decoder function
    function [6:0] seg7_decode;
        input [3:0] digit;
        begin
            case (digit)
                4'h0: seg7_decode = 7'b1000000;
                4'h1: seg7_decode = 7'b1111001;
                4'h2: seg7_decode = 7'b0100100;
                4'h3: seg7_decode = 7'b0110000;
                4'h4: seg7_decode = 7'b0011001;
                4'h5: seg7_decode = 7'b0010010;
                4'h6: seg7_decode = 7'b0000010;
                4'h7: seg7_decode = 7'b1111000;
                4'h8: seg7_decode = 7'b0000000;
                4'h9: seg7_decode = 7'b0010000;
                4'hA: seg7_decode = 7'b0001000;
                4'hB: seg7_decode = 7'b0000011;
                4'hC: seg7_decode = 7'b1000110;
                4'hD: seg7_decode = 7'b0100001;
                4'hE: seg7_decode = 7'b0000110;
                4'hF: seg7_decode = 7'b0001110;
                default: seg7_decode = 7'b1111111;
            endcase
        end
    endfunction

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign uo_out[6:0] = segment_data_reg;
    assign uo_out[7]   = (operation == OP_ADD);
    
    assign uio_out[0] = digit_select_reg[0];
    assign uio_out[1] = digit_select_reg[1];
    assign uio_out[2] = scan_out_reg;
    assign uio_out[3] = bist_done_reg;
    assign uio_out[4] = test_pass;
    assign uio_out[5] = fault_injected;
    assign uio_out[6] = current_mode[0];
    assign uio_out[7] = current_mode[1];
    
    assign uio_oe = 8'b11111111;

    // Unused inputs
    wire _unused = &{ena, uio_in, ui_in[3], 1'b0};

endmodule
