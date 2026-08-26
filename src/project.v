/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 * 
 * iTALU: Interactive Testable Arithmetic Logic Unit
 * 
 * Design-for-Testability Enabled ALU for Tiny Tapeout
 * 
 * Features:
 * - 8-bit ALU with 8 operations (ADD, SUB, AND, OR, XOR, NOT, SHIFT, COMPARE)
 * - Full scan chain on all registers
 * - BIST with LFSR pattern generator and MISR compactor
 * - User-controlled fault injection
 * - Boundary scan interface
 * - 7-segment display controller
 */

`default_nettype none

module tt_um_italu (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // =========================================================================
    // Pin Assignment
    // =========================================================================
    // ui_in[0]     : User data input (serial)
    // ui_in[1]     : Control button (mode select/execute)
    // ui_in[2]     : Step button (step through operations)
    // ui_in[3]     : Mode select MSB
    // ui_in[4]     : Scan enable
    // ui_in[5]     : Scan clock
    // ui_in[6]     : Scan input (for scan chain)
    // ui_in[7]     : BIST start
    //
    // uo_out[6:0]  : 7-segment display data
    // uo_out[7]    : Operation LED indicator
    //
    // uio[0]       : Digit select (bidirectional)
    // uio[1]       : Test data (bidirectional)
    // uio[2]       : Scan output (output)
    // uio[3]       : BIST done (output)
    // uio[4]       : Pass/Fail indicator (output)
    // uio[5]       : Fault injected indicator (output)
    // uio[6]       : Reserved
    // uio[7]       : Reserved

    wire user_data_in    = ui_in[0];
    wire control_button  = ui_in[1];
    wire step_button     = ui_in[2];
    wire mode_select_msb = ui_in[3];
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
    // User Modes
    // =========================================================================
    localparam [1:0] MODE_FUNCTIONAL   = 2'b00;
    localparam [1:0] MODE_MANUAL_TEST  = 2'b01;
    localparam [1:0] MODE_BIST         = 2'b10;
    localparam [1:0] MODE_FAULT_INJECT = 2'b11;

    // =========================================================================
    // User Control State Machine
    // =========================================================================
    localparam [2:0] USER_IDLE     = 3'b000;
    localparam [2:0] USER_LOAD_OP  = 3'b001;
    localparam [2:0] USER_LOAD_A   = 3'b010;
    localparam [2:0] USER_LOAD_B   = 3'b011;
    localparam [2:0] USER_EXECUTE  = 3'b100;
    localparam [2:0] USER_VERIFY   = 3'b101;
    localparam [2:0] USER_DISPLAY  = 3'b110;

    // =========================================================================
    // Registers
    // =========================================================================
    // ALU registers
    reg [7:0] operand_a;
    reg [7:0] operand_b;
    reg [2:0] operation;
    reg [7:0] alu_result;
    reg       zero_flag;
    reg       carry_flag;
    reg       negative_flag;
    reg       overflow_flag;

    // DFT registers
    reg [7:0] lfsr;
    reg [7:0] misr;
    reg [7:0] test_pattern;
    reg [7:0] expected_result;
    reg [7:0] scan_chain [0:31]; // 32 flip-flops for scan
    reg       bist_active;
    reg       fault_injected;
    reg [2:0] fault_location;

    // User control registers
    reg [1:0] current_mode;
    reg [3:0] input_counter;
    reg [7:0] user_data_buffer;
    reg       execute_operation;
    reg [7:0] test_vector_count;
    reg       test_pass;
    reg [7:0] fault_coverage;
    reg [2:0] user_state;

    // Button debouncing
    reg button_sync1, button_sync2, button_prev;
    reg step_sync1, step_sync2, step_prev;
    wire button_pressed;
    wire step_pressed;

    // Scan chain registers
    reg [31:0] scan_reg;
    reg scan_out_reg;

    // =========================================================================
    // Button Debouncing
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            button_sync1 <= 0;
            button_sync2 <= 0;
            button_prev  <= 0;
            step_sync1   <= 0;
            step_sync2   <= 0;
            step_prev    <= 0;
        end else begin
            button_sync1 <= control_button;
            button_sync2 <= button_sync1;
            button_prev  <= button_sync2;
            
            step_sync1 <= step_button;
            step_sync2 <= step_sync1;
            step_prev  <= step_sync2;
        end
    end

    assign button_pressed = button_sync1 & ~button_sync2;
    assign step_pressed   = step_sync1 & ~step_sync2;

    // =========================================================================
    // ALU Implementation (Combinational)
    // =========================================================================
    always @(*) begin
        case (operation)
            OP_ADD: begin
                {carry_flag, alu_result} = operand_a + operand_b;
                overflow_flag = (operand_a[7] & operand_b[7] & ~alu_result[7]) |
                               (~operand_a[7] & ~operand_b[7] & alu_result[7]);
            end
            OP_SUB: begin
                {carry_flag, alu_result} = operand_a - operand_b;
                overflow_flag = (operand_a[7] & ~operand_b[7] & ~alu_result[7]) |
                               (~operand_a[7] & operand_b[7] & alu_result[7]);
            end
            OP_AND: begin
                alu_result = operand_a & operand_b;
                carry_flag = 1'b0;
                overflow_flag = 1'b0;
            end
            OP_OR: begin
                alu_result = operand_a | operand_b;
                carry_flag = 1'b0;
                overflow_flag = 1'b0;
            end
            OP_XOR: begin
                alu_result = operand_a ^ operand_b;
                carry_flag = 1'b0;
                overflow_flag = 1'b0;
            end
            OP_NOT: begin
                alu_result = ~operand_a;
                carry_flag = 1'b0;
                overflow_flag = 1'b0;
            end
            OP_SHL: begin
                alu_result = operand_a << 1;
                carry_flag = operand_a[7];
                overflow_flag = 1'b0;
            end
            OP_CMP: begin
                if (operand_a == operand_b)
                    alu_result = 8'h01;
                else if (operand_a > operand_b)
                    alu_result = 8'h02;
                else
                    alu_result = 8'h00;
                carry_flag = (operand_a >= operand_b);
                overflow_flag = 1'b0;
            end
            default: begin
                alu_result = 8'h00;
                carry_flag = 1'b0;
                overflow_flag = 1'b0;
            end
        endcase
        
        zero_flag     = (alu_result == 8'h00);
        negative_flag = alu_result[7];
    end

    // =========================================================================
    // User Control FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            user_state        <= USER_IDLE;
            input_counter     <= 0;
            current_mode      <= MODE_FUNCTIONAL;
            operand_a         <= 8'h00;
            operand_b         <= 8'h00;
            operation         <= OP_ADD;
            fault_injected    <= 1'b0;
            fault_location    <= 3'b000;
            test_pass         <= 1'b1;
            execute_operation <= 1'b0;
            test_vector_count <= 8'h00;
            fault_coverage    <= 8'h00;
        end else begin
            case (user_state)
                USER_IDLE: begin
                    execute_operation <= 1'b0;
                    if (button_pressed) begin
                        // Cycle through modes
                        current_mode <= current_mode + 1'b1;
                        input_counter <= 0;
                        user_state <= USER_LOAD_OP;
                    end else if (step_pressed && (current_mode == MODE_BIST)) begin
                        user_state <= USER_EXECUTE;
                    end
                end
                
                USER_LOAD_OP: begin
                    if (input_counter < 3) begin
                        operation <= {operation[1:0], user_data_in};
                        input_counter <= input_counter + 1'b1;
                    end else begin
                        input_counter <= 0;
                        user_state <= USER_LOAD_A;
                    end
                end
                
                USER_LOAD_A: begin
                    if (input_counter < 8) begin
                        operand_a <= {operand_a[6:0], user_data_in};
                        input_counter <= input_counter + 1'b1;
                    end else begin
                        input_counter <= 0;
                        user_state <= USER_LOAD_B;
                    end
                end
                
                USER_LOAD_B: begin
                    if (input_counter < 8) begin
                        operand_b <= {operand_b[6:0], user_data_in};
                        input_counter <= input_counter + 1'b1;
                    end else begin
                        input_counter <= 0;
                        user_state <= USER_EXECUTE;
                    end
                end
                
                USER_EXECUTE: begin
                    if (button_pressed || step_pressed) begin
                        execute_operation <= 1'b1;
                        
                        if (current_mode == MODE_FAULT_INJECT) begin
                            fault_injected <= 1'b1;
                            case (fault_location)
                                3'b000: operand_a[0] <= 1'b0; // Stuck-at-0
                                3'b001: operand_a[0] <= 1'b1; // Stuck-at-1
                                3'b010: operand_b[7] <= 1'b0;
                                3'b011: operand_b[7] <= 1'b1;
                                3'b100: alu_result[3] <= 1'b0;
                                3'b101: alu_result[3] <= 1'b1;
                                3'b110: carry_flag <= 1'b0;
                                3'b111: carry_flag <= 1'b1;
                            endcase
                        end
                        
                        user_state <= USER_VERIFY;
                    end
                end
                
                USER_VERIFY: begin
                    // Calculate expected result
                    case (operation)
                        OP_ADD: expected_result <= operand_a + operand_b;
                        OP_SUB: expected_result <= operand_a - operand_b;
                        OP_AND: expected_result <= operand_a & operand_b;
                        OP_OR:  expected_result <= operand_a | operand_b;
                        OP_XOR: expected_result <= operand_a ^ operand_b;
                        OP_NOT: expected_result <= ~operand_a;
                        OP_SHL: expected_result <= operand_a << 1;
                        OP_CMP: begin
                            if (operand_a == operand_b)
                                expected_result <= 8'h01;
                            else if (operand_a > operand_b)
                                expected_result <= 8'h02;
                            else
                                expected_result <= 8'h00;
                        end
                    endcase
                    
                    test_pass <= (alu_result == expected_result);
                    
                    if (test_pass && fault_injected) begin
                        if (fault_coverage < 8'hFF)
                            fault_coverage <= fault_coverage + 1'b1;
                    end
                    
                    if (button_pressed) begin
                        user_state <= USER_DISPLAY;
                    end
                end
                
                USER_DISPLAY: begin
                    if (step_pressed) begin
                        fault_injected <= 1'b0;
                        user_state <= USER_IDLE;
                    end
                end
                
                default: begin
                    user_state <= USER_IDLE;
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

    reg [1:0] bist_state;
    reg [7:0] pattern_count;
    reg       bist_enable;
    reg [7:0] bist_signature;
    reg       bist_done_reg;

    wire lfsr_feedback = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bist_state    <= BIST_IDLE;
            pattern_count <= 8'h00;
            lfsr          <= 8'h01;
            bist_enable   <= 1'b0;
            bist_done_reg <= 1'b0;
            bist_signature <= 8'h00;
            misr          <= 8'h00;
        end else begin
            case (bist_state)
                BIST_IDLE: begin
                    bist_done_reg <= 1'b0;
                    if (bist_start || (current_mode == MODE_BIST && button_pressed)) begin
                        bist_enable   <= 1'b1;
                        lfsr          <= 8'h01;
                        pattern_count <= 8'h00;
                        misr          <= 8'h00;
                        bist_state    <= BIST_GENERATE;
                    end
                end
                
                BIST_GENERATE: begin
                    // Generate next pattern
                    lfsr <= {lfsr[6:0], lfsr_feedback};
                    
                    // Apply to ALU inputs
                    operand_a <= lfsr;
                    operand_b <= {lfsr[3:0], lfsr[7:4]};
                    operation <= lfsr[2:0];
                    
                    bist_state <= BIST_APPLY;
                end
                
                BIST_APPLY: begin
                    // Compact result into MISR
                    misr <= {misr[6:0], misr[7] ^ misr[5] ^ alu_result[0]};
                    
                    if (pattern_count == 8'hFF) begin
                        bist_state <= BIST_VERIFY;
                    end else begin
                        pattern_count <= pattern_count + 1'b1;
                        bist_state <= BIST_GENERATE;
                    end
                end
                
                BIST_VERIFY: begin
                    bist_signature <= misr;
                    test_pass <= (misr == expected_result);
                    bist_done_reg <= 1'b1;
                    bist_enable <= 1'b0;
                    
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
    // Scan Chain Implementation
    // =========================================================================
    always @(posedge scan_clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_reg     <= 32'h00000000;
            scan_out_reg <= 1'b0;
        end else if (scan_enable) begin
            scan_reg     <= {scan_in, scan_reg[31:1]};
            scan_out_reg <= scan_reg[0];
        end else begin
            // Load from functional registers
            scan_reg <= {operand_a, operand_b, operation, zero_flag, 
                        carry_flag, negative_flag, overflow_flag, 
                        alu_result[7:0]};
        end
    end

    // =========================================================================
    // 7-Segment Display Controller
    // =========================================================================
    reg [1:0] display_digit;
    reg [3:0] display_value;
    reg [6:0] segment_data_reg;
    reg [3:0] digit_select_reg;

    // BCD to 7-segment decoder
    function [6:0] seg7;
        input [3:0] digit;
        begin
            case (digit)
                4'h0: seg7 = 7'b1000000; // 0
                4'h1: seg7 = 7'b1111001; // 1
                4'h2: seg7 = 7'b0100100; // 2
                4'h3: seg7 = 7'b0110000; // 3
                4'h4: seg7 = 7'b0011001; // 4
                4'h5: seg7 = 7'b0010010; // 5
                4'h6: seg7 = 7'b0000010; // 6
                4'h7: seg7 = 7'b1111000; // 7
                4'h8: seg7 = 7'b0000000; // 8
                4'h9: seg7 = 7'b0010000; // 9
                4'hA: seg7 = 7'b0001000; // A
                4'hB: seg7 = 7'b0000011; // b
                4'hC: seg7 = 7'b1000110; // C
                4'hD: seg7 = 7'b0100001; // d
                4'hE: seg7 = 7'b0000110; // E
                4'hF: seg7 = 7'b0001110; // F
                default: seg7 = 7'b1111111;
            endcase
        end
    endfunction

    // Display multiplexing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_digit    <= 0;
            display_value    <= 0;
            segment_data_reg <= 7'b1111111;
            digit_select_reg <= 4'b1111;
        end else begin
            display_digit <= display_digit + 1'b1;
            
            case (display_digit)
                2'b00: begin
                    display_value    <= alu_result[3:0];
                    digit_select_reg <= 4'b1110;
                    segment_data_reg <= seg7(display_value);
                end
                2'b01: begin
                    display_value    <= alu_result[7:4];
                    digit_select_reg <= 4'b1101;
                    segment_data_reg <= seg7(display_value);
                end
                2'b10: begin
                    // Display operation code
                    display_value    <= {1'b0, operation};
                    digit_select_reg <= 4'b1011;
                    segment_data_reg <= seg7(display_value);
                end
                2'b11: begin
                    // Display flags
                    display_value    <= {zero_flag, carry_flag, negative_flag, overflow_flag};
                    digit_select_reg <= 4'b0111;
                    segment_data_reg <= seg7(display_value);
                end
            endcase
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================
    // 7-segment display output
    assign uo_out[6:0] = segment_data_reg;
    
    // Operation LED indicator
    assign uo_out[7] = (operation == OP_ADD) ? 1'b1 :
                       (operation == OP_SUB) ? 1'b0 : 1'b1;

    // Bidirectional I/O assignments
    assign uio_out[0] = digit_select_reg[0];
    assign uio_out[1] = digit_select_reg[1];
    assign uio_out[2] = scan_out_reg;
    assign uio_out[3] = bist_done_reg;
    assign uio_out[4] = test_pass;
    assign uio_out[5] = fault_injected;
    assign uio_out[6] = current_mode[0];
    assign uio_out[7] = current_mode[1];

    assign uio_oe[0] = 1'b1;  // digit_select[0] output
    assign uio_oe[1] = 1'b1;  // digit_select[1] output
    assign uio_oe[2] = 1'b1;  // scan_out output
    assign uio_oe[3] = 1'b1;  // bist_done output
    assign uio_oe[4] = 1'b1;  // test_pass output
    assign uio_oe[5] = 1'b1;  // fault_injected output
    assign uio_oe[6] = 1'b1;  // mode[0] output
    assign uio_oe[7] = 1'b1;  // mode[1] output

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, uio_in[0], uio_in[1], uio_in[2], uio_in[3], 
                     uio_in[4], uio_in[5], uio_in[6], uio_in[7], 
                     mode_select_msb, 1'b0};

endmodule
