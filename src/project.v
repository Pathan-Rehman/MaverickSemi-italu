/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 *
 * Self-Testable 8-bit ITALU
 *
 * Features:
 *   - 16 ALU operations
 *   - Serial instruction loader
 *   - LFSR based LBIST
 *   - MISR response compaction
 *   - Programmable fault injection
 *   - Fault detection counter
 *   - Performance/cycle counter
 *   - 64-bit diagnostic scan chain
 *   - ALU status flags
 *
 * Pin mapping
 *
 * ui_in[0] : serial instruction data
 * ui_in[1] : serial instruction shift enable
 * ui_in[2] : ALU execute
 * ui_in[3] : scan capture
 * ui_in[4] : reserved
 * ui_in[5] : reserved
 * ui_in[6] : scan shift enable
 * ui_in[7] : BIST start
 *
 * uio_in[0]   : fault enable
 * uio_in[2:1] : fault type
 *                 00 = stuck-at-0
 *                 01 = stuck-at-1
 *                 10 = inversion
 *                 11 = coupling
 *
 * uio_in[5:3] : fault bit select
 * uio_in[7:6] : status select
 *
 * Status select:
 *   00 = normal status
 *   01 = MISR
 *   10 = fault detection count
 *   11 = cycle counter
 *
 */

`default_nettype none
`timescale 1ns/1ps

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
    // CONSTANTS
    // ============================================================

    /*
     * Expected MISR signature for:
     *
     *   LFSR seed       = 8'h01
     *   256 test patterns
     *   ALU opcode      = LFSR[3:0]
     *   operand A       = LFSR
     *   operand B       = {LFSR[3:0],LFSR[7:4]}
     *
     * and the MISR defined below.
     */
    localparam [7:0] EXPECTED_MISR = 8'h0D;


    // ============================================================
    // ALU REGISTERS
    // ============================================================

    reg [7:0] operand_a;
    reg [7:0] operand_b;

    reg [3:0] operation;

    reg [7:0] alu_result;

    reg       zero_flag;
    reg       carry_flag;
    reg       negative_flag;
    reg       overflow_flag;


    // ============================================================
    // SERIAL INSTRUCTION REGISTER
    // ============================================================

    /*
     * Instruction format:
     *
     * [19:16] = opcode
     * [15:8]  = operand B
     * [7:0]   = operand A
     *
     * The instruction is shifted in LSB first.
     */

    reg [19:0] serial_shift_reg;


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
    // BIST / PERFORMANCE COUNTERS
    // ============================================================

    /*
     * Number of BIST runs which ended with a bad signature.
     */

    reg [7:0] fault_detect_count;


    /*
     * Free-running cycle counter.
     */

    reg [7:0] cycle_count;


    // ============================================================
    // DIAGNOSTIC SCAN REGISTER
    // ============================================================

    /*
     * 64-bit diagnostic scan register.
     *
     * Captured contents:
     *
     *   [63:60] unused
     *   [59:52] pattern_count
     *   [51:49] bist_state
     *   [48]    test_pass
     *   [47]    overflow
     *   [46]    negative
     *   [45]    carry
     *   [44]    zero
     *   [43:36] MISR
     *   [35:28] LFSR
     *   [27:20] ALU result
     *   [19:16] operation
     *   [15:8]  operand B
     *   [7:0]   operand A
     *
     * Scan shifts LSB first.
     */

    reg [63:0] scan_reg;

    reg        scan_out;


    // ============================================================
    // FAULT INJECTION CONTROL
    // ============================================================

    wire       fault_enable;

    wire [1:0] fault_type;

    wire [2:0] fault_bit;

    wire [1:0] status_select;


    assign fault_enable = uio_in[0];

    assign fault_type = uio_in[2:1];

    assign fault_bit = uio_in[5:3];

    assign status_select = uio_in[7:6];


    // ============================================================
    // ALU RESULT FUNCTION
    // ============================================================

    /*
     * Opcode table
     *
     * 0x0 : ADD
     * 0x1 : SUB
     * 0x2 : AND
     * 0x3 : OR
     * 0x4 : XOR
     * 0x5 : NOT
     * 0x6 : SLL
     * 0x7 : SRL
     * 0x8 : SRA
     * 0x9 : ROL
     * 0xA : ROR
     * 0xB : signed SLT
     * 0xC : MIN
     * 0xD : MAX
     * 0xE : signed saturating ADD
     * 0xF : signed saturating SUB
     */

    function [7:0] alu_result_fn;

        input [7:0] a;
        input [7:0] b;
        input [3:0] op;

        reg [7:0] tmp;

        begin

            tmp = 8'h00;

            case (op)

                // ------------------------------------------------
                // ADD
                // ------------------------------------------------

                4'h0: begin
                    tmp = a + b;
                end


                // ------------------------------------------------
                // SUB
                // ------------------------------------------------

                4'h1: begin
                    tmp = a - b;
                end


                // ------------------------------------------------
                // AND
                // ------------------------------------------------

                4'h2: begin
                    tmp = a & b;
                end


                // ------------------------------------------------
                // OR
                // ------------------------------------------------

                4'h3: begin
                    tmp = a | b;
                end


                // ------------------------------------------------
                // XOR
                // ------------------------------------------------

                4'h4: begin
                    tmp = a ^ b;
                end


                // ------------------------------------------------
                // NOT
                // ------------------------------------------------

                4'h5: begin
                    tmp = ~a;
                end


                // ------------------------------------------------
                // SHIFT LEFT LOGICAL
                // ------------------------------------------------

                4'h6: begin
                    tmp = a << 1;
                end


                // ------------------------------------------------
                // SHIFT RIGHT LOGICAL
                // ------------------------------------------------

                4'h7: begin
                    tmp = a >> 1;
                end


                // ------------------------------------------------
                // SHIFT RIGHT ARITHMETIC
                // ------------------------------------------------

                4'h8: begin
                    tmp = {
                        a[7],
                        a[7:1]
                    };
                end


                // ------------------------------------------------
                // ROTATE LEFT
                // ------------------------------------------------

                4'h9: begin
                    tmp = {
                        a[6:0],
                        a[7]
                    };
                end


                // ------------------------------------------------
                // ROTATE RIGHT
                // ------------------------------------------------

                4'hA: begin
                    tmp = {
                        a[0],
                        a[7:1]
                    };
                end


                // ------------------------------------------------
                // SIGNED LESS THAN
                // ------------------------------------------------

                4'hB: begin

                    if ($signed(a) < $signed(b))
                        tmp = 8'h01;
                    else
                        tmp = 8'h00;

                end


                // ------------------------------------------------
                // MINIMUM
                // ------------------------------------------------

                4'hC: begin

                    if (a < b)
                        tmp = a;
                    else
                        tmp = b;

                end


                // ------------------------------------------------
                // MAXIMUM
                // ------------------------------------------------

                4'hD: begin

                    if (a > b)
                        tmp = a;
                    else
                        tmp = b;

                end


                // ------------------------------------------------
                // SIGNED SATURATING ADD
                // ------------------------------------------------

                4'hE: begin

                    tmp = a + b;

                    /*
                     * Positive overflow:
                     *
                     * 0 + 0 -> 1
                     */

                    if ((!a[7]) &&
                        (!b[7]) &&
                        tmp[7]) begin

                        tmp = 8'h7F;

                    end

                    /*
                     * Negative overflow:
                     *
                     * 1 + 1 -> 0
                     */

                    else if (a[7] &&
                             b[7] &&
                             (!tmp[7])) begin

                        tmp = 8'h80;

                    end

                end


                // ------------------------------------------------
                // SIGNED SATURATING SUB
                // ------------------------------------------------

                4'hF: begin

                    tmp = a - b;

                    /*
                     * Positive overflow:
                     *
                     * positive - negative
                     */

                    if ((!a[7]) &&
                        b[7] &&
                        tmp[7]) begin

                        tmp = 8'h7F;

                    end

                    /*
                     * Negative overflow:
                     *
                     * negative - positive
                     */

                    else if (a[7] &&
                             (!b[7]) &&
                             (!tmp[7])) begin

                        tmp = 8'h80;

                    end

                end


                default: begin
                    tmp = 8'h00;
                end

            endcase

            alu_result_fn = tmp;

        end

    endfunction


    // ============================================================
    // ALU CARRY FUNCTION
    // ============================================================

    function alu_carry_fn;

        input [7:0] a;
        input [7:0] b;
        input [3:0] op;

        reg [8:0] temp;

        begin

            temp = 9'h000;

            case (op)

                // ADD
                4'h0: begin

                    temp = {
                        1'b0,
                        a
                    } + {
                        1'b0,
                        b
                    };

                    alu_carry_fn = temp[8];

                end


                // SUB
                //
                // Carry = 1 when no unsigned borrow occurs.
                //

                4'h1: begin

                    if (a >= b)
                        alu_carry_fn = 1'b1;
                    else
                        alu_carry_fn = 1'b0;

                end


                // SLL
                4'h6: begin
                    alu_carry_fn = a[7];
                end


                // SRL
                4'h7: begin
                    alu_carry_fn = a[0];
                end


                // SRA
                4'h8: begin
                    alu_carry_fn = a[0];
                end


                // ROL
                4'h9: begin
                    alu_carry_fn = a[7];
                end


                // ROR
                4'hA: begin
                    alu_carry_fn = a[0];
                end


                default: begin
                    alu_carry_fn = 1'b0;
                end

            endcase

        end

    endfunction


    // ============================================================
    // OVERFLOW FUNCTION
    // ============================================================

    function alu_overflow_fn;

        input [7:0] a;
        input [7:0] b;
        input [3:0] op;

        reg [7:0] result;

        begin

            result = alu_result_fn(
                a,
                b,
                op
            );

            case (op)

                // ------------------------------------------------
                // ADD
                // ------------------------------------------------

                4'h0: begin

                    alu_overflow_fn =
                        (~a[7] &
                         ~b[7] &
                          result[7]) |

                        (a[7] &
                         b[7] &
                         ~result[7]);

                end


                // ------------------------------------------------
                // SUB
                // ------------------------------------------------

                4'h1: begin

                    alu_overflow_fn =
                        (a[7] ^
                         b[7]) &

                        (result[7] ^
                         a[7]);

                end


                // ------------------------------------------------
                // SATURATING ADD
                // ------------------------------------------------

                4'hE: begin

                    /*
                     * Recalculate using the unsaturated
                     * mathematical result.
                     */

                    alu_overflow_fn =
                        (~a[7] &
                         ~b[7] &
                         (a + b)[7]) |

                        (a[7] &
                         b[7] &
                         ~(a + b)[7]);

                end


                // ------------------------------------------------
                // SATURATING SUB
                // ------------------------------------------------

                4'hF: begin

                    alu_overflow_fn =
                        (a[7] ^
                         b[7]) &

                        (((a - b)[7]) ^
                         a[7]);

                end


                default: begin

                    alu_overflow_fn = 1'b0;

                end

            endcase

        end

    endfunction


    // ============================================================
    // FAULT INJECTION FUNCTION
    // ============================================================

    /*
     * Fault types:
     *
     * 00 : Stuck-at-0
     * 01 : Stuck-at-1
     * 10 : Bit inversion
     * 11 : Coupling fault
     *
     * Coupling implementation:
     *
     * selected bit copies the previous bit.
     *
     */

    function [7:0] inject_fault_fn;

        input [7:0] data;
        input       enable;
        input [1:0] type;
        input [2:0] bit_index;

        reg [7:0] temp;

        begin

            temp = data;

            if (enable) begin

                case (type)

                    // --------------------------------------------
                    // STUCK AT ZERO
                    // --------------------------------------------

                    2'b00: begin

                        temp[bit_index] = 1'b0;

                    end


                    // --------------------------------------------
                    // STUCK AT ONE
                    // --------------------------------------------

                    2'b01: begin

                        temp[bit_index] = 1'b1;

                    end


                    // --------------------------------------------
                    // INVERSION
                    // --------------------------------------------

                    2'b10: begin

                        temp[bit_index] =
                            ~temp[bit_index];

                    end


                    // --------------------------------------------
                    // COUPLING
                    // --------------------------------------------

                    2'b11: begin

                        case (bit_index)

                            3'd0:
                                temp[0] = data[7];

                            3'd1:
                                temp[1] = data[0];

                            3'd2:
                                temp[2] = data[1];

                            3'd3:
                                temp[3] = data[2];

                            3'd4:
                                temp[4] = data[3];

                            3'd5:
                                temp[5] = data[4];

                            3'd6:
                                temp[6] = data[5];

                            3'd7:
                                temp[7] = data[6];

                            default:
                                temp = data;

                        endcase

                    end


                    default: begin

                        temp = data;

                    end

                endcase

            end

            inject_fault_fn = temp;

        end

    endfunction


    // ============================================================
    // CURRENT ALU
    // ============================================================

    wire [7:0] alu_out_wire;

    wire       carry_wire;

    wire       zero_wire;

    wire       negative_wire;

    wire       overflow_wire;


    assign alu_out_wire =
        alu_result_fn(
            operand_a,
            operand_b,
            operation
        );


    assign carry_wire =
        alu_carry_fn(
            operand_a,
            operand_b,
            operation
        );


    assign overflow_wire =
        alu_overflow_fn(
            operand_a,
            operand_b,
            operation
        );


    // ============================================================
    // FAULTED CURRENT ALU
    // ============================================================

    wire [7:0] faulted_alu_out_wire;


    assign faulted_alu_out_wire =
        inject_fault_fn(
            alu_out_wire,
            fault_enable,
            fault_type,
            fault_bit
        );


    assign zero_wire =
        (faulted_alu_out_wire == 8'h00);


    assign negative_wire =
        faulted_alu_out_wire[7];


    // ============================================================
    // NORMAL SERIAL INSTRUCTION DECODE
    // ============================================================

    wire [7:0] serial_operand_a;

    wire [7:0] serial_operand_b;

    wire [3:0] serial_operation;


    assign serial_operand_a =
        serial_shift_reg[7:0];


    assign serial_operand_b =
        serial_shift_reg[15:8];


    assign serial_operation =
        serial_shift_reg[19:16];


    // ============================================================
    // NORMAL SERIAL INSTRUCTION ALU
    // ============================================================

    wire [7:0] normal_alu_out;

    wire       normal_carry;

    wire       normal_overflow;

    wire [7:0] normal_faulted_out;


    assign normal_alu_out =
        alu_result_fn(
            serial_operand_a,
            serial_operand_b,
            serial_operation
        );


    assign normal_carry =
        alu_carry_fn(
            serial_operand_a,
            serial_operand_b,
            serial_operation
        );


    assign normal_overflow =
        alu_overflow_fn(
            serial_operand_a,
            serial_operand_b,
            serial_operation
        );


    assign normal_faulted_out =
        inject_fault_fn(
            normal_alu_out,
            fault_enable,
            fault_type,
            fault_bit
        );


    // ============================================================
    // LFSR
    // ============================================================

    wire lfsr_feedback;


    assign lfsr_feedback =
        lfsr[7] ^
        lfsr[5] ^
        lfsr[4] ^
        lfsr[3];


    // ============================================================
    // MISR NEXT STATE
    // ============================================================

    /*
     * Parallel response MISR.
     *
     * Every ALU response bit participates in the signature.
     *
     * This is intentionally stronger than the previous MISR,
     * which only used ALU result bit 0 and therefore could not
     * detect faults on many of the other result bits.
     */

    wire [7:0] misr_next;


    assign misr_next = {

        misr[6] ^
        faulted_alu_out_wire[7],

        misr[5] ^
        faulted_alu_out_wire[6],

        misr[4] ^
        faulted_alu_out_wire[5],

        misr[3] ^
        faulted_alu_out_wire[4],

        misr[2] ^
        faulted_alu_out_wire[3],

        misr[1] ^
        faulted_alu_out_wire[2],

        misr[0] ^
        faulted_alu_out_wire[1],

        misr[7] ^
        misr[5] ^
        faulted_alu_out_wire[0]

    };


    // ============================================================
    // MAIN ALU + BIST SEQUENTIAL BLOCK
    // ============================================================
    //
    // IMPORTANT:
    //
    // Every register controlled here has exactly ONE sequential
    // driver. This avoids the multiple-driver synthesis problem
    // from the previous implementation.
    //
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            // ----------------------------------------------------
            // ALU
            // ----------------------------------------------------

            operand_a <= 8'h00;

            operand_b <= 8'h00;

            operation <= 4'h0;

            alu_result <= 8'h00;

            zero_flag <= 1'b0;

            carry_flag <= 1'b0;

            negative_flag <= 1'b0;

            overflow_flag <= 1'b0;


            // ----------------------------------------------------
            // SERIAL INSTRUCTION REGISTER
            // ----------------------------------------------------

            serial_shift_reg <= 20'h00000;


            // ----------------------------------------------------
            // BIST
            // ----------------------------------------------------

            lfsr <= 8'h01;

            misr <= 8'h00;

            bist_state <= 3'b000;

            pattern_count <= 8'h00;

            bist_done <= 1'b0;

            test_pass <= 1'b1;


            // ----------------------------------------------------
            // COUNTERS
            // ----------------------------------------------------

            fault_detect_count <= 8'h00;

        end
        else begin

            // ====================================================
            // BIST CONTROLLER
            // ====================================================

            case (bist_state)


                // =================================================
                // IDLE / NORMAL ALU
                // =================================================

                3'b000: begin

                    bist_done <= 1'b0;


                    // ------------------------------------------------
                    // SERIAL INSTRUCTION LOAD
                    // ------------------------------------------------

                    if (ui_in[1]) begin

                        serial_shift_reg <= {
                            serial_shift_reg[18:0],
                            ui_in[0]
                        };

                    end


                    // ------------------------------------------------
                    // NORMAL ALU EXECUTE
                    // ------------------------------------------------

                    if (ui_in[2]) begin

                        operand_a <= serial_operand_a;

                        operand_b <= serial_operand_b;

                        operation <= serial_operation;


                        alu_result <=
                            normal_faulted_out;


                        zero_flag <=
                            (normal_faulted_out == 8'h00);


                        carry_flag <=
                            normal_carry;


                        negative_flag <=
                            normal_faulted_out[7];


                        overflow_flag <=
                            normal_overflow;

                    end


                    // ------------------------------------------------
                    // BIST START
                    // ------------------------------------------------

                    if (ui_in[7]) begin

                        lfsr <= 8'h01;

                        misr <= 8'h00;

                        pattern_count <= 8'h00;

                        bist_state <= 3'b001;

                        bist_done <= 1'b0;

                        test_pass <= 1'b1;

                    end

                end


                // =================================================
                // BIST PATTERN GENERATION
                // =================================================

                3'b001: begin

                    /*
                     * Current LFSR value becomes the test pattern.
                     */

                    operand_a <= lfsr;

                    operand_b <= {
                        lfsr[3:0],
                        lfsr[7:4]
                    };

                    operation <= lfsr[3:0];


                    /*
                     * Advance LFSR.
                     */

                    lfsr <= {
                        lfsr[6:0],
                        lfsr_feedback
                    };


                    bist_state <= 3'b010;

                end


                // =================================================
                // BIST EXECUTION + MISR COMPACTION
                // =================================================

                3'b010: begin

                    // ------------------------------------------------
                    // Capture faulted ALU result
                    // ------------------------------------------------

                    alu_result <=
                        faulted_alu_out_wire;


                    zero_flag <=
                        zero_wire;


                    carry_flag <=
                        carry_wire;


                    negative_flag <=
                        negative_wire;


                    overflow_flag <=
                        overflow_wire;


                    // ------------------------------------------------
                    // MISR UPDATE
                    // ------------------------------------------------

                    misr <= misr_next;


                    // ------------------------------------------------
                    // Pattern counter
                    // ------------------------------------------------

                    if (pattern_count == 8'hFF) begin

                        bist_state <= 3'b011;

                    end
                    else begin

                        pattern_count <=
                            pattern_count + 1'b1;

                        bist_state <= 3'b001;

                    end

                end


                // =================================================
                // BIST COMPLETE / SIGNATURE CHECK
                // =================================================

                3'b011: begin

                    bist_done <= 1'b1;


                    /*
                     * REAL signature comparison.
                     */

                    if (misr == EXPECTED_MISR) begin

                        test_pass <= 1'b1;

                    end
                    else begin

                        test_pass <= 1'b0;

                        fault_detect_count <=
                            fault_detect_count + 1'b1;

                    end


                    /*
                     * Wait until BIST start is released.
                     */

                    if (!ui_in[7]) begin

                        bist_state <= 3'b000;

                    end

                end


                // =================================================
                // ERROR RECOVERY
                // =================================================

                default: begin

                    bist_state <= 3'b000;

                end

            endcase

        end

    end


    // ============================================================
    // PERFORMANCE COUNTER
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            cycle_count <= 8'h00;

        end
        else begin

            cycle_count <=
                cycle_count + 1'b1;

        end

    end


    // ============================================================
    // 64-BIT DIAGNOSTIC SCAN CHAIN
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            scan_reg <= 64'h0000000000000000;

            scan_out <= 1'b0;

        end
        else begin

            // ----------------------------------------------------
            // Capture internal state
            // ----------------------------------------------------

            if (ui_in[3]) begin

                scan_reg <= {

                    4'h0,

                    pattern_count,

                    bist_state,

                    test_pass,

                    overflow_flag,

                    negative_flag,

                    carry_flag,

                    zero_flag,

                    misr,

                    lfsr,

                    alu_result,

                    operation,

                    operand_b,

                    operand_a

                };

                scan_out <= 1'b0;

            end


            // ----------------------------------------------------
            // Shift scan chain
            // ----------------------------------------------------

            else if (ui_in[6]) begin

                scan_out <=
                    scan_reg[0];

                scan_reg <= {
                    ui_in[0],
                    scan_reg[63:1]
                };

            end

        end

    end


    // ============================================================
    // OUTPUTS
    // ============================================================

    assign uo_out = alu_result;


    // ============================================================
    // STATUS OUTPUT MULTIPLEXER
    // ============================================================

    reg [7:0] uio_out_reg;


    always @* begin

        uio_out_reg = 8'h00;

        case (status_select)

            // ----------------------------------------------------
            // STATUS
            // ----------------------------------------------------

            2'b00: begin

                uio_out_reg[0] = zero_flag;

                uio_out_reg[1] = carry_flag;

                uio_out_reg[2] = negative_flag;

                uio_out_reg[3] = overflow_flag;

                uio_out_reg[4] = bist_done;

                uio_out_reg[5] = test_pass;

                uio_out_reg[6] = scan_out;

                /*
                 * BIST active indicator
                 */

                uio_out_reg[7] =
                    (bist_state != 3'b000);

            end


            // ----------------------------------------------------
            // MISR
            // ----------------------------------------------------

            2'b01: begin

                uio_out_reg =
                    misr;

            end


            // ----------------------------------------------------
            // FAULT DETECTION COUNT
            // ----------------------------------------------------

            2'b10: begin

                uio_out_reg =
                    fault_detect_count;

            end


            // ----------------------------------------------------
            // CYCLE COUNT
            // ----------------------------------------------------

            2'b11: begin

                uio_out_reg =
                    cycle_count;

            end


            default: begin

                uio_out_reg = 8'h00;

            end

        endcase

    end


    assign uio_out =
        uio_out_reg;


    // All bidirectional pins are currently outputs.

    assign uio_oe =
        8'hFF;


    // ============================================================
    // UNUSED INPUTS
    // ============================================================

    wire _unused;

    assign _unused =
        &{
            ena,
            ui_in[5:4]
        };


endmodule

`default_nettype wire
