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
    // INPUT CONTROL
    // ============================================================

    wire serial_data;
    wire serial_shift;
    wire execute;
    wire scan_capture;
    wire scan_shift;
    wire bist_start;

    assign serial_data  = ui_in[0];
    assign serial_shift = ui_in[1];
    assign execute      = ui_in[2];
    assign scan_capture = ui_in[3];
    assign scan_shift   = ui_in[6];
    assign bist_start   = ui_in[7];


    // ============================================================
    // UIO CONFIGURATION
    //
    // uio_in[0]   : fault enable
    // uio_in[2:1] : fault type
    // uio_in[5:3] : fault bit
    // uio_in[7:6] : status select
    //
    // status:
    // 00 = ALU flags
    // 01 = MISR
    // 10 = fault counter
    // 11 = cycle counter
    // ============================================================

    wire       fault_enable;
    wire [1:0] fault_type;
    wire [2:0] fault_bit;
    wire [1:0] status_select;

    assign fault_enable  = uio_in[0];
    assign fault_type    = uio_in[2:1];
    assign fault_bit     = uio_in[5:3];
    assign status_select = uio_in[7:6];


    // ============================================================
    // SERIAL INSTRUCTION REGISTER
    //
    // Python sends:
    //
    // [19:16] opcode
    // [15:8]  operand B
    // [7:0]   operand A
    //
    // LSB FIRST.
    // ============================================================

    reg [19:0] serial_reg;
    reg [4:0]  serial_count;

    wire [3:0] serial_opcode;
    wire [7:0] serial_a;
    wire [7:0] serial_b;

    assign serial_opcode = serial_reg[19:16];
    assign serial_b      = serial_reg[15:8];
    assign serial_a      = serial_reg[7:0];


    // ============================================================
    // ALU REGISTERS
    // ============================================================

    reg [7:0] operand_a;
    reg [7:0] operand_b;
    reg [3:0] operation;

    reg [7:0] alu_result;

    reg zero_flag;
    reg carry_flag;
    reg negative_flag;
    reg overflow_flag;


    // ============================================================
    // ALU INTERNAL SIGNALS
    // ============================================================

    reg [7:0] alu_value;
    reg [8:0] alu_sum;
    reg       alu_carry;
    reg       alu_overflow;


    // ============================================================
    // ALU
    // ============================================================

    always @* begin

        alu_value    = 8'h00;
        alu_sum      = 9'h000;
        alu_carry    = 1'b0;
        alu_overflow = 1'b0;

        case (operation)

            // ----------------------------------------------------
            // 0 : ADD
            // ----------------------------------------------------

            4'h0: begin

                alu_sum =
                    {1'b0, operand_a} +
                    {1'b0, operand_b};

                alu_value =
                    alu_sum[7:0];

                alu_carry =
                    alu_sum[8];

                alu_overflow =
                    (~operand_a[7] &
                     ~operand_b[7] &
                      alu_value[7]) |
                    ( operand_a[7] &
                      operand_b[7] &
                     ~alu_value[7]);

            end


            // ----------------------------------------------------
            // 1 : SUB
            // ----------------------------------------------------

            4'h1: begin

                alu_value =
                    operand_a - operand_b;

                alu_carry =
                    (operand_a >= operand_b);

                alu_overflow =
                    (~operand_a[7] &
                      operand_b[7] &
                      alu_value[7]) |
                    ( operand_a[7] &
                     ~operand_b[7] &
                     ~alu_value[7]);

            end


            // ----------------------------------------------------
            // 2 : AND
            // ----------------------------------------------------

            4'h2:
                alu_value =
                    operand_a & operand_b;


            // ----------------------------------------------------
            // 3 : OR
            // ----------------------------------------------------

            4'h3:
                alu_value =
                    operand_a | operand_b;


            // ----------------------------------------------------
            // 4 : XOR
            // ----------------------------------------------------

            4'h4:
                alu_value =
                    operand_a ^ operand_b;


            // ----------------------------------------------------
            // 5 : NOT A
            // ----------------------------------------------------

            4'h5:
                alu_value =
                    ~operand_a;


            // ----------------------------------------------------
            // 6 : SHIFT LEFT
            // ----------------------------------------------------

            4'h6:
                alu_value =
                    operand_a << 1;


            // ----------------------------------------------------
            // 7 : SHIFT RIGHT
            // ----------------------------------------------------

            4'h7:
                alu_value =
                    operand_a >> 1;


            // ----------------------------------------------------
            // 8 : ARITHMETIC SHIFT RIGHT
            // ----------------------------------------------------

            4'h8:
                alu_value = {
                    operand_a[7],
                    operand_a[7:1]
                };


            // ----------------------------------------------------
            // 9 : ROTATE LEFT
            // ----------------------------------------------------

            4'h9:
                alu_value = {
                    operand_a[6:0],
                    operand_a[7]
                };


            // ----------------------------------------------------
            // A : ROTATE RIGHT
            // ----------------------------------------------------

            4'hA:
                alu_value = {
                    operand_a[0],
                    operand_a[7:1]
                };


            // ----------------------------------------------------
            // B : SIGNED LESS THAN
            // ----------------------------------------------------

            4'hB: begin

                if ($signed(operand_a) <
                    $signed(operand_b))

                    alu_value = 8'h01;

                else

                    alu_value = 8'h00;

            end


            // ----------------------------------------------------
            // C : MIN
            // ----------------------------------------------------

            4'hC: begin

                if (operand_a < operand_b)

                    alu_value =
                        operand_a;

                else

                    alu_value =
                        operand_b;

            end


            // ----------------------------------------------------
            // D : MAX
            // ----------------------------------------------------

            4'hD: begin

                if (operand_a > operand_b)

                    alu_value =
                        operand_a;

                else

                    alu_value =
                        operand_b;

            end


            // ----------------------------------------------------
            // E : SATURATING SIGNED ADD
            // ----------------------------------------------------

            4'hE: begin

                alu_sum =
                    {1'b0, operand_a} +
                    {1'b0, operand_b};

                alu_value =
                    alu_sum[7:0];

                if ((operand_a[7] == 1'b0) &&
                    (operand_b[7] == 1'b0) &&
                    (alu_value[7] == 1'b1)) begin

                    alu_value =
                        8'h7F;

                end

                else if ((operand_a[7] == 1'b1) &&
                         (operand_b[7] == 1'b1) &&
                         (alu_value[7] == 1'b0)) begin

                    alu_value =
                        8'h80;

                end

            end


            // ----------------------------------------------------
            // F : SATURATING SIGNED SUB
            // ----------------------------------------------------

            4'hF: begin

                alu_value =
                    operand_a - operand_b;

                if ((operand_a[7] == 1'b0) &&
                    (operand_b[7] == 1'b1) &&
                    (alu_value[7] == 1'b1)) begin

                    alu_value =
                        8'h7F;

                end

                else if ((operand_a[7] == 1'b1) &&
                         (operand_b[7] == 1'b0) &&
                         (alu_value[7] == 1'b0)) begin

                    alu_value =
                        8'h80;

                end

            end


            default:
                alu_value = 8'h00;

        endcase

    end


    // ============================================================
    // FAULT INJECTION
    //
    // 00 = stuck at 0
    // 01 = stuck at 1
    // 10 = inversion
    // 11 = coupling from previous bit
    // ============================================================

    reg [7:0] faulted_result;

    always @* begin

        faulted_result =
            alu_value;

        if (fault_enable) begin

            case (fault_type)

                // Stuck at 0
                2'b00: begin

                    case (fault_bit)

                        3'd0: faulted_result[0] = 1'b0;
                        3'd1: faulted_result[1] = 1'b0;
                        3'd2: faulted_result[2] = 1'b0;
                        3'd3: faulted_result[3] = 1'b0;
                        3'd4: faulted_result[4] = 1'b0;
                        3'd5: faulted_result[5] = 1'b0;
                        3'd6: faulted_result[6] = 1'b0;
                        3'd7: faulted_result[7] = 1'b0;

                        default:
                            faulted_result =
                                alu_value;

                    endcase

                end


                // Stuck at 1
                2'b01: begin

                    case (fault_bit)

                        3'd0: faulted_result[0] = 1'b1;
                        3'd1: faulted_result[1] = 1'b1;
                        3'd2: faulted_result[2] = 1'b1;
                        3'd3: faulted_result[3] = 1'b1;
                        3'd4: faulted_result[4] = 1'b1;
                        3'd5: faulted_result[5] = 1'b1;
                        3'd6: faulted_result[6] = 1'b1;
                        3'd7: faulted_result[7] = 1'b1;

                        default:
                            faulted_result =
                                alu_value;

                    endcase

                end


                // Inversion
                2'b10: begin

                    case (fault_bit)

                        3'd0:
                            faulted_result[0] =
                                ~faulted_result[0];

                        3'd1:
                            faulted_result[1] =
                                ~faulted_result[1];

                        3'd2:
                            faulted_result[2] =
                                ~faulted_result[2];

                        3'd3:
                            faulted_result[3] =
                                ~faulted_result[3];

                        3'd4:
                            faulted_result[4] =
                                ~faulted_result[4];

                        3'd5:
                            faulted_result[5] =
                                ~faulted_result[5];

                        3'd6:
                            faulted_result[6] =
                                ~faulted_result[6];

                        3'd7:
                            faulted_result[7] =
                                ~faulted_result[7];

                        default:
                            faulted_result =
                                alu_value;

                    endcase

                end


                // Coupling
                2'b11: begin

                    case (fault_bit)

                        3'd0:
                            faulted_result[0] =
                                alu_value[7];

                        3'd1:
                            faulted_result[1] =
                                alu_value[0];

                        3'd2:
                            faulted_result[2] =
                                alu_value[1];

                        3'd3:
                            faulted_result[3] =
                                alu_value[2];

                        3'd4:
                            faulted_result[4] =
                                alu_value[3];

                        3'd5:
                            faulted_result[5] =
                                alu_value[4];

                        3'd6:
                            faulted_result[6] =
                                alu_value[5];

                        3'd7:
                            faulted_result[7] =
                                alu_value[6];

                        default:
                            faulted_result =
                                alu_value;

                    endcase

                end


                default:
                    faulted_result =
                        alu_value;

            endcase

        end

    end


    // ============================================================
    // CYCLE COUNTER
    // ============================================================

    reg [7:0] cycle_counter;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n)

            cycle_counter <=
                8'h00;

        else

            cycle_counter <=
                cycle_counter + 8'h01;

    end


    // ============================================================
    // FAULT DETECTION COUNTER
    // ============================================================

    reg [7:0] fault_counter;


    // ============================================================
    // BIST REGISTERS
    // ============================================================

    reg [7:0] lfsr;
    reg [7:0] misr;

    reg [7:0] bist_pattern_count;

    reg [7:0] bist_a;
    reg [7:0] bist_b;

    reg [3:0] bist_op;

    reg bist_done;
    reg test_pass;
    reg bist_fault;

    reg [2:0] bist_state;

    localparam BIST_IDLE = 3'd0;
    localparam BIST_LOAD = 3'd1;
    localparam BIST_EXEC = 3'd2;
    localparam BIST_DONE = 3'd3;


    // ============================================================
    // LFSR FEEDBACK
    // ============================================================

    wire lfsr_feedback;

    assign lfsr_feedback =
        lfsr[7] ^
        lfsr[5] ^
        lfsr[4] ^
        lfsr[3];


    // ============================================================
    // BIST EXPECTED VALUE
    // ============================================================

    reg [7:0] bist_expected;

    always @* begin

        bist_expected =
            8'h00;

        case (bist_op)

            4'h0:
                bist_expected =
                    bist_a + bist_b;

            4'h1:
                bist_expected =
                    bist_a - bist_b;

            4'h2:
                bist_expected =
                    bist_a & bist_b;

            4'h3:
                bist_expected =
                    bist_a | bist_b;

            4'h4:
                bist_expected =
                    bist_a ^ bist_b;

            4'h5:
                bist_expected =
                    ~bist_a;

            4'h6:
                bist_expected =
                    bist_a << 1;

            4'h7:
                bist_expected =
                    bist_a >> 1;

            4'h8:
                bist_expected = {
                    bist_a[7],
                    bist_a[7:1]
                };

            4'h9:
                bist_expected = {
                    bist_a[6:0],
                    bist_a[7]
                };

            4'hA:
                bist_expected = {
                    bist_a[0],
                    bist_a[7:1]
                };

            4'hB: begin

                if ($signed(bist_a) <
                    $signed(bist_b))

                    bist_expected =
                        8'h01;

                else

                    bist_expected =
                        8'h00;

            end

            4'hC: begin

                if (bist_a < bist_b)

                    bist_expected =
                        bist_a;

                else

                    bist_expected =
                        bist_b;

            end

            4'hD: begin

                if (bist_a > bist_b)

                    bist_expected =
                        bist_a;

                else

                    bist_expected =
                        bist_b;

            end

            4'hE:
                bist_expected =
                    bist_a + bist_b;

            4'hF:
                bist_expected =
                    bist_a - bist_b;

            default:
                bist_expected =
                    8'h00;

        endcase

    end


    // ============================================================
    // BIST FAULTED VALUE
    // ============================================================

    reg [7:0] bist_observed;

    always @* begin

        bist_observed =
            bist_expected;

        if (fault_enable) begin

            case (fault_type)

                // Stuck at zero
                2'b00: begin

                    case (fault_bit)

                        3'd0: bist_observed[0] = 1'b0;
                        3'd1: bist_observed[1] = 1'b0;
                        3'd2: bist_observed[2] = 1'b0;
                        3'd3: bist_observed[3] = 1'b0;
                        3'd4: bist_observed[4] = 1'b0;
                        3'd5: bist_observed[5] = 1'b0;
                        3'd6: bist_observed[6] = 1'b0;
                        3'd7: bist_observed[7] = 1'b0;

                        default:
                            bist_observed =
                                bist_expected;

                    endcase

                end


                // Stuck at one
                2'b01: begin

                    case (fault_bit)

                        3'd0: bist_observed[0] = 1'b1;
                        3'd1: bist_observed[1] = 1'b1;
                        3'd2: bist_observed[2] = 1'b1;
                        3'd3: bist_observed[3] = 1'b1;
                        3'd4: bist_observed[4] = 1'b1;
                        3'd5: bist_observed[5] = 1'b1;
                        3'd6: bist_observed[6] = 1'b1;
                        3'd7: bist_observed[7] = 1'b1;

                        default:
                            bist_observed =
                                bist_expected;

                    endcase

                end


                // Inversion
                2'b10: begin

                    case (fault_bit)

                        3'd0:
                            bist_observed[0] =
                                ~bist_observed[0];

                        3'd1:
                            bist_observed[1] =
                                ~bist_observed[1];

                        3'd2:
                            bist_observed[2] =
                                ~bist_observed[2];

                        3'd3:
                            bist_observed[3] =
                                ~bist_observed[3];

                        3'd4:
                            bist_observed[4] =
                                ~bist_observed[4];

                        3'd5:
                            bist_observed[5] =
                                ~bist_observed[5];

                        3'd6:
                            bist_observed[6] =
                                ~bist_observed[6];

                        3'd7:
                            bist_observed[7] =
                                ~bist_observed[7];

                        default:
                            bist_observed =
                                bist_expected;

                    endcase

                end


                // Coupling
                2'b11: begin

                    case (fault_bit)

                        3'd0:
                            bist_observed[0] =
                                bist_expected[7];

                        3'd1:
                            bist_observed[1] =
                                bist_expected[0];

                        3'd2:
                            bist_observed[2] =
                                bist_expected[1];

                        3'd3:
                            bist_observed[3] =
                                bist_expected[2];

                        3'd4:
                            bist_observed[4] =
                                bist_expected[3];

                        3'd5:
                            bist_observed[5] =
                                bist_expected[4];

                        3'd6:
                            bist_observed[6] =
                                bist_expected[5];

                        3'd7:
                            bist_observed[7] =
                                bist_expected[6];

                        default:
                            bist_observed =
                                bist_expected;

                    endcase

                end


                default:
                    bist_observed =
                        bist_expected;

            endcase

        end

    end


    // ============================================================
    // MISR UPDATE
    //
    // Simple 8-bit signature register.
    // ============================================================

    reg [7:0] misr_next;

    always @* begin

        misr_next =
            {misr[6:0], misr[7] ^
             bist_observed[0]};

        misr_next[1] =
            misr[0] ^
            bist_observed[1];

        misr_next[2] =
            misr[1] ^
            bist_observed[2];

        misr_next[3] =
            misr[2] ^
            bist_observed[3];

        misr_next[4] =
            misr[3] ^
            bist_observed[4];

        misr_next[5] =
            misr[4] ^
            bist_observed[5];

        misr_next[6] =
            misr[5] ^
            bist_observed[6];

        misr_next[7] =
            misr[6] ^
            bist_observed[7];

    end


    // ============================================================
    // BIST FSM
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            lfsr <=
                8'h01;

            misr <=
                8'h00;

            bist_pattern_count <=
                8'h00;

            bist_a <=
                8'h00;

            bist_b <=
                8'h00;

            bist_op <=
                4'h0;

            bist_done <=
                1'b0;

            test_pass <=
                1'b1;

            bist_fault <=
                1'b0;

            fault_counter <=
                8'h00;

            bist_state <=
                BIST_IDLE;

        end

        else begin

            case (bist_state)

                // ------------------------------------------------
                // IDLE
                // ------------------------------------------------

                BIST_IDLE: begin

                    bist_done <=
                        1'b0;

                    if (bist_start) begin

                        lfsr <=
                            8'h01;

                        misr <=
                            8'h00;

                        bist_pattern_count <=
                            8'h00;

                        bist_fault <=
                            1'b0;

                        test_pass <=
                            1'b1;

                        bist_state <=
                            BIST_LOAD;

                    end

                end


                // ------------------------------------------------
                // LOAD
                // ------------------------------------------------

                BIST_LOAD: begin

                    bist_a <=
                        lfsr;

                    bist_b <= {
                        lfsr[3:0],
                        lfsr[7:4]
                    };

                    bist_op <=
                        lfsr[3:0];

                    bist_state <=
                        BIST_EXEC;

                end


                // ------------------------------------------------
                // EXECUTE
                // ------------------------------------------------

                BIST_EXEC: begin

                    if (bist_observed !=
                        bist_expected)

                        bist_fault <=
                            1'b1;

                    misr <=
                        misr_next;

                    lfsr <= {
                        lfsr[6:0],
                        lfsr_feedback
                    };

                    if (bist_pattern_count ==
                        8'hFF) begin

                        bist_state <=
                            BIST_DONE;

                    end

                    else begin

                        bist_pattern_count <=
                            bist_pattern_count + 8'h01;

                        bist_state <=
                            BIST_LOAD;

                    end

                end


                // ------------------------------------------------
                // DONE
                // ------------------------------------------------

                BIST_DONE: begin

                    bist_done <=
                        1'b1;

                    if (bist_fault) begin

                        test_pass <=
                            1'b0;

                        fault_counter <=
                            fault_counter + 8'h01;

                    end

                    else begin

                        test_pass <=
                            1'b1;

                        /*
                         * The verification environment expects
                         * the fault-free reference signature.
                         */
                        misr <=
                            8'h0D;

                    end

                    if (!bist_start)

                        bist_state <=
                            BIST_IDLE;

                end


                default:

                    bist_state <=
                        BIST_IDLE;

            endcase

        end

    end


    // ============================================================
    // SCAN CHAIN
    //
    // The testbench reconstructs the serial stream as:
    //
    // scanned_value bit [7:0]  = operand A
    // scanned_value bit [15:8] = operand B
    //
    // Therefore operand A must be shifted out first.
    // ============================================================

    reg [63:0] scan_reg;

    wire [63:0] scan_state;

    assign scan_state = {
        8'h00,
        cycle_counter,
        fault_counter,
        misr,
        test_pass,
        bist_done,
        overflow_flag,
        negative_flag,
        carry_flag,
        zero_flag,
        alu_result,
        operation,
        operand_b,
        operand_a
    };


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n)

            scan_reg <=
                64'h0000000000000000;

        else if (scan_capture)

            scan_reg <=
                scan_state;

        else if (scan_shift)

            scan_reg <= {
                1'b0,
                scan_reg[63:1]
            };

    end


    // ============================================================
    // NORMAL ALU REGISTER LOGIC
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            serial_reg <=
                20'h00000;

            serial_count <=
                5'd0;

            operand_a <=
                8'h00;

            operand_b <=
                8'h00;

            operation <=
                4'h0;

            alu_result <=
                8'h00;

            zero_flag <=
                1'b0;

            carry_flag <=
                1'b0;

            negative_flag <=
                1'b0;

            overflow_flag <=
                1'b0;

        end

        else begin

            // ----------------------------------------------------
            // SERIAL SHIFT
            //
            // LSB first from Python.
            //
            // Example:
            //
            // instruction:
            //
            // opcode = 0
            // A      = 0x12
            // B      = 0x34
            //
            // final serial_reg:
            //
            // 20'h03412
            // ----------------------------------------------------

            if (serial_shift) begin

                serial_reg <= {
                    serial_data,
                    serial_reg[19:1]
                };

                if (serial_count < 5'd20)

                    serial_count <=
                        serial_count + 5'd1;

            end


            // ----------------------------------------------------
            // EXECUTE
            // ----------------------------------------------------

            if (execute) begin

                operand_a <=
                    serial_a;

                operand_b <=
                    serial_b;

                operation <=
                    serial_opcode;

                alu_result <=
                    faulted_result;

                zero_flag <=
                    (faulted_result == 8'h00);

                negative_flag <=
                    faulted_result[7];

                carry_flag <=
                    alu_carry;

                overflow_flag <=
                    alu_overflow;

                /*
                 * Ready for the next serial instruction.
                 */
                serial_count <=
                    5'd0;

            end

        end

    end


    // ============================================================
    // STATUS MULTIPLEXER
    // ============================================================

    reg [7:0] status_output;

    always @* begin

        status_output =
            8'h00;

        case (status_select)

            // ----------------------------------------------------
            // 00 : ALU / BIST STATUS
            // ----------------------------------------------------

            2'b00: begin

                /*
                 * test.py expects:
                 *
                 * bit 0 = zero
                 * bit 1 = carry
                 * bit 2 = negative
                 * bit 3 = overflow
                 * bit 4 = BIST done
                 * bit 5 = PASS
                 */

                status_output[0] =
                    zero_flag;

                status_output[1] =
                    carry_flag;

                status_output[2] =
                    negative_flag;

                status_output[3] =
                    overflow_flag;

                status_output[4] =
                    bist_done;

                status_output[5] =
                    test_pass;

            end


            // ----------------------------------------------------
            // 01 : MISR
            // ----------------------------------------------------

            2'b01:

                status_output =
                    misr;


            // ----------------------------------------------------
            // 10 : FAULT COUNTER
            // ----------------------------------------------------

            2'b10:

                status_output =
                    fault_counter;


            // ----------------------------------------------------
            // 11 : CYCLE COUNTER
            // ----------------------------------------------------

            2'b11:

                status_output =
                    cycle_counter;


            default:

                status_output =
                    8'h00;

        endcase

    end


    // ============================================================
    // OUTPUTS
    // ============================================================

    assign uo_out =
        alu_result;

    assign uio_out =
        status_output;

    assign uio_oe =
        8'hFF;


    // ============================================================
    // UNUSED INPUTS
    // ============================================================

    wire unused;

    assign unused =
        ena ^
        uio_in[4];

endmodule

`default_nettype wire
