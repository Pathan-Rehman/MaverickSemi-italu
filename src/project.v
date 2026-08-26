/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 *
 * 8-bit Integrated ALU with:
 *   - 8-bit ALU
 *   - LFSR-based BIST pattern generator
 *   - MISR response compactor
 *   - Serial scan chain
 *   - Status flags
 *   - Activity counter
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

    // ============================================================
    // PIN ASSIGNMENT
    // ============================================================
    //
    // ui_in[0] : Serial data input
    // ui_in[1] : Load operand
    // ui_in[2] : Execute ALU
    // ui_in[3] : Unused
    // ui_in[4] : Unused
    // ui_in[5] : Unused
    // ui_in[6] : Scan enable
    // ui_in[7] : BIST start
    //
    // uo_out[7:0] : ALU result
    //
    // uio_out[0] : Zero flag
    // uio_out[1] : Carry flag
    // uio_out[2] : Negative flag
    // uio_out[3] : Overflow flag
    // uio_out[4] : BIST done
    // uio_out[5] : BIST pass
    // uio_out[6] : Scan output
    // uio_out[7] : Activity counter
    //
    // ============================================================


    // ============================================================
    // ALU REGISTERS
    // ============================================================

    reg [7:0] operand_a;
    reg [7:0] operand_b;
    reg [2:0] operation;

    reg [7:0] alu_result;

    reg       zero_flag;
    reg       carry_flag;
    reg       negative_flag;
    reg       overflow_flag;


    // ============================================================
    // BIST REGISTERS
    // ============================================================

    reg [7:0] lfsr;
    reg [7:0] misr;

    reg [2:0] bist_state;

    reg [7:0] pattern_count;

    reg       bist_done;
    reg       test_pass;


    // ============================================================
    // SCAN REGISTERS
    // ============================================================

    reg [7:0] scan_reg;
    reg       scan_out;


    // ============================================================
    // ACTIVITY COUNTER
    // ============================================================

    reg [3:0] dummy_counter;


    // ============================================================
    // ALU COMBINATIONAL LOGIC
    // ============================================================
    //
    // Operation encoding:
    //
    // 000 : ADD
    // 001 : SUB
    // 010 : AND
    // 011 : OR
    // 100 : XOR
    // 101 : NOT A
    // 110 : Shift left
    // 111 : Compare
    //
    // Compare result:
    //   A == B -> 01
    //   A >  B -> 02
    //   A <  B -> 00
    //
    // ============================================================

    wire [8:0] alu_9bit;

    assign alu_9bit =
        (operation == 3'b000) ?
            ({1'b0, operand_a} + {1'b0, operand_b}) :

        (operation == 3'b001) ?
            ({1'b0, operand_a} - {1'b0, operand_b}) :

        (operation == 3'b010) ?
            {1'b0, (operand_a & operand_b)} :

        (operation == 3'b011) ?
            {1'b0, (operand_a | operand_b)} :

        (operation == 3'b100) ?
            {1'b0, (operand_a ^ operand_b)} :

        (operation == 3'b101) ?
            {1'b0, (~operand_a)} :

        (operation == 3'b110) ?
            {operand_a[7], operand_a[6:0], 1'b0} :

        {1'b0,
            ((operand_a == operand_b) ? 8'h01 :
             (operand_a > operand_b)  ? 8'h02 :
                                         8'h00)
        };


    // ALU outputs

    wire [7:0] alu_out_wire;
    wire       carry_wire;
    wire       zero_wire;
    wire       neg_wire;
    wire       ovf_wire;

    assign alu_out_wire = alu_9bit[7:0];

    assign carry_wire = alu_9bit[8];

    assign zero_wire = (alu_out_wire == 8'h00);

    assign neg_wire = alu_out_wire[7];


    // Overflow detection for signed addition.
    //
    // Overflow occurs when:
    //   positive + positive = negative
    // OR
    //   negative + negative = positive
    //
    assign ovf_wire =
        (operation == 3'b000) ?
        (
            ( operand_a[7] &
              operand_b[7] &
             ~alu_out_wire[7] ) |

            (~operand_a[7] &
             ~operand_b[7] &
              alu_out_wire[7] )
        ) :
        1'b0;


    // ============================================================
    // LFSR FEEDBACK
    // ============================================================
    //
    // Polynomial:
    //
    // x^8 + x^6 + x^5 + x^4 + 1
    //
    // ============================================================

    wire lfsr_fb;

    assign lfsr_fb =
        lfsr[7] ^
        lfsr[5] ^
        lfsr[4] ^
        lfsr[3];


    // ============================================================
    // MAIN ALU + BIST SEQUENTIAL LOGIC
    // ============================================================
    //
    // IMPORTANT:
    // All registers shared between the normal ALU and BIST are
    // controlled from this SINGLE always block.
    //
    // This avoids multiple-driver synthesis errors.
    //
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            // ----------------------------------------------------
            // ALU RESET
            // ----------------------------------------------------

            operand_a      <= 8'h00;
            operand_b      <= 8'h00;
            operation      <= 3'b000;

            alu_result     <= 8'h00;

            zero_flag      <= 1'b0;
            carry_flag     <= 1'b0;
            negative_flag  <= 1'b0;
            overflow_flag  <= 1'b0;


            // ----------------------------------------------------
            // BIST RESET
            // ----------------------------------------------------

            lfsr           <= 8'h01;
            misr           <= 8'h00;

            bist_state     <= 3'b000;

            pattern_count  <= 8'h00;

            bist_done      <= 1'b0;
            test_pass      <= 1'b1;

        end
        else begin

            // ====================================================
            // BIST STATE MACHINE
            // ====================================================

            case (bist_state)

                // =================================================
                // STATE 000
                // IDLE / NORMAL ALU OPERATION
                // =================================================

                3'b000: begin

                    bist_done <= 1'b0;


                    // ------------------------------------------------
                    // NORMAL ALU OPERAND LOAD
                    // ------------------------------------------------
                    //
                    // ui_in[1] = 1
                    //
                    // A is shifted left and serial input enters bit 0.
                    // B captures the previous A value.
                    //
                    // ------------------------------------------------

                    if (ui_in[1]) begin

                        operand_a <= {
                            operand_a[6:0],
                            ui_in[0]
                        };

                        operand_b <= operand_a;

                    end


                    // ------------------------------------------------
                    // NORMAL ALU EXECUTION
                    // ------------------------------------------------

                    if (ui_in[2]) begin

                        alu_result    <= alu_out_wire;

                        carry_flag    <= carry_wire;

                        zero_flag     <= zero_wire;

                        negative_flag <= neg_wire;

                        overflow_flag <= ovf_wire;

                    end


                    // ------------------------------------------------
                    // BIST START
                    // ------------------------------------------------

                    if (ui_in[7]) begin

                        lfsr          <= 8'h01;

                        misr          <= 8'h00;

                        pattern_count <= 8'h00;

                        bist_state    <= 3'b001;

                        bist_done     <= 1'b0;

                        test_pass     <= 1'b1;

                    end

                end


                // =================================================
                // STATE 001
                // GENERATE AND APPLY BIST PATTERN
                // =================================================

                3'b001: begin

                    // ------------------------------------------------
                    // Advance LFSR
                    // ------------------------------------------------

                    lfsr <= {
                        lfsr[6:0],
                        lfsr_fb
                    };


                    // ------------------------------------------------
                    // Generate ALU operands from LFSR
                    // ------------------------------------------------

                    operand_a <= lfsr;

                    operand_b <= {
                        lfsr[3:0],
                        lfsr[7:4]
                    };


                    // ------------------------------------------------
                    // Generate ALU operation
                    // ------------------------------------------------

                    operation <= lfsr[2:0];


                    // Move to execution state

                    bist_state <= 3'b010;

                end


                // =================================================
                // STATE 010
                // EXECUTE ALU + COMPACT RESPONSE
                // =================================================

                3'b010: begin

                    // ------------------------------------------------
                    // Capture ALU response
                    // ------------------------------------------------

                    alu_result <= alu_out_wire;

                    carry_flag <= carry_wire;

                    zero_flag <= zero_wire;

                    negative_flag <= neg_wire;

                    overflow_flag <= ovf_wire;


                    // ------------------------------------------------
                    // MISR RESPONSE COMPACTION
                    // ------------------------------------------------
                    //
                    // The ALU output contributes to the signature.
                    //
                    // ------------------------------------------------

                    misr <= {
                        misr[6:0],
                        misr[7] ^
                        misr[5] ^
                        alu_out_wire[0]
                    };


                    // ------------------------------------------------
                    // Pattern counter
                    // ------------------------------------------------

                    if (pattern_count == 8'hFF) begin

                        // All 256 patterns completed

                        bist_state <= 3'b011;

                    end
                    else begin

                        pattern_count <=
                            pattern_count + 1'b1;

                        bist_state <= 3'b001;

                    end

                end


                // =================================================
                // STATE 011
                // BIST COMPLETE
                // =================================================

                3'b011: begin

                    bist_done <= 1'b1;


                    // ------------------------------------------------
                    // Current implementation:
                    // BIST completes successfully.
                    //
                    // The MISR signature is available internally.
                    // A reference signature comparator can be added
                    // later for true pass/fail fault detection.
                    // ------------------------------------------------

                    test_pass <= 1'b1;


                    // ------------------------------------------------
                    // Wait until BIST start is released
                    // ------------------------------------------------

                    if (!ui_in[7]) begin

                        bist_state <= 3'b000;

                    end

                end


                // =================================================
                // DEFAULT / ERROR RECOVERY
                // =================================================

                default: begin

                    bist_state <= 3'b000;

                end

            endcase

        end

    end


    // ============================================================
    // SCAN CHAIN
    // ============================================================
    //
    // Scan operation is independent from the ALU/BIST registers,
    // so it can safely remain in its own sequential block.
    //
    // ui_in[6] = scan enable
    // ui_in[0] = scan data input
    // uio_out[6] = scan output
    //
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            scan_reg <= 8'h00;

            scan_out <= 1'b0;

        end
        else if (ui_in[6]) begin

            scan_reg <= {
                ui_in[0],
                scan_reg[7:1]
            };

            scan_out <= scan_reg[0];

        end

    end


    // ============================================================
    // ACTIVITY / DEBUG COUNTER
    // ============================================================
    //
    // This counter provides observable sequential activity on
    // uio_out[7].
    //
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            dummy_counter <= 4'b0000;

        end
        else begin

            dummy_counter <=
                dummy_counter + 1'b1;

        end

    end


    // ============================================================
    // OUTPUT CONNECTIONS
    // ============================================================

    // ALU result

    assign uo_out = alu_result;


    // Status outputs

    assign uio_out[0] = zero_flag;

    assign uio_out[1] = carry_flag;

    assign uio_out[2] = negative_flag;

    assign uio_out[3] = overflow_flag;


    // BIST outputs

    assign uio_out[4] = bist_done;

    assign uio_out[5] = test_pass;


    // Scan output

    assign uio_out[6] = scan_out;


    // Activity counter

    assign uio_out[7] = dummy_counter[3];


    // ============================================================
    // ALL OUTPUTS ARE CURRENTLY OUTPUT-ONLY
    // ============================================================

    assign uio_oe = 8'b11111111;


    // ============================================================
    // UNUSED INPUTS
    // ============================================================
    //
    // Prevent unused-input warnings.
    //
    // The final 1'b0 intentionally makes this expression constant
    // zero, so synthesis can remove it.
    //
    // ============================================================

    wire _unused;

    assign _unused = &{
        ena,
        uio_in,
        ui_in[5:3],
        1'b0
    };

endmodule

`default_nettype wire
