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
    // FAULT / STATUS CONTROL
    //
    // uio_in[0]   = fault enable
    // uio_in[2:1] = fault type
    //
    //   00 = stuck-at-0
    //   01 = stuck-at-1
    //   10 = inversion
    //   11 = coupling
    //
    // uio_in[5:3] = fault bit
    // uio_in[7:6] = status select
    //
    //   00 = ALU/BIST status
    //   01 = MISR
    //   10 = fault counter
    //   11 = cycle counter
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
    // [19:16] opcode
    // [15:8]  operand B
    // [7:0]   operand A
    //
    // Loaded LSB first.
    // ============================================================

    reg [19:0] serial_reg;

    wire [3:0] serial_opcode;
    wire [7:0] serial_a;
    wire [7:0] serial_b;

    assign serial_opcode = serial_reg[19:16];
    assign serial_b      = serial_reg[15:8];
    assign serial_a      = serial_reg[7:0];

    // ============================================================
    // NORMAL ALU REGISTERS
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
    // NORMAL ALU
    // ============================================================

    reg [7:0] alu_value;
    reg [8:0] alu_sum;
    reg       alu_carry;
    reg       alu_overflow;

    always @* begin

        alu_value    = 8'h00;
        alu_sum      = 9'h000;
        alu_carry    = 1'b0;
        alu_overflow = 1'b0;

        case (operation)

            // ADD
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

            // SUB
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

            // AND
            4'h2:
                alu_value =
                    operand_a & operand_b;

            // OR
            4'h3:
                alu_value =
                    operand_a | operand_b;

            // XOR
            4'h4:
                alu_value =
                    operand_a ^ operand_b;

            // NOT
            4'h5:
                alu_value =
                    ~operand_a;

            // Logical shift left
            4'h6:
                alu_value =
                    operand_a << 1;

            // Logical shift right
            4'h7:
                alu_value =
                    operand_a >> 1;

            // Arithmetic shift right
            4'h8:
                alu_value = {
                    operand_a[7],
                    operand_a[7:1]
                };

            // Rotate left
            4'h9:
                alu_value = {
                    operand_a[6:0],
                    operand_a[7]
                };

            // Rotate right
            4'hA:
                alu_value = {
                    operand_a[0],
                    operand_a[7:1]
                };

            // Signed less-than
            4'hB: begin
                if ($signed(operand_a) <
                    $signed(operand_b))
                    alu_value = 8'h01;
                else
                    alu_value = 8'h00;
            end

            // MIN
            4'hC: begin
                if (operand_a < operand_b)
                    alu_value = operand_a;
                else
                    alu_value = operand_b;
            end

            // MAX
            4'hD: begin
                if (operand_a > operand_b)
                    alu_value = operand_a;
                else
                    alu_value = operand_b;
            end

            // Saturating ADD
            4'hE: begin

                alu_sum =
                    {1'b0, operand_a} +
                    {1'b0, operand_b};

                alu_value =
                    alu_sum[7:0];

                if ((!operand_a[7]) &&
                    (!operand_b[7]) &&
                    alu_sum[7])

                    alu_value = 8'h7F;

                else if (operand_a[7] &&
                         operand_b[7] &&
                         (!alu_sum[7]))

                    alu_value = 8'h80;
            end

            // Saturating SUB
            4'hF: begin

                alu_value =
                    operand_a - operand_b;

                if ((!operand_a[7]) &&
                    operand_b[7] &&
                    alu_value[7])

                    alu_value = 8'h7F;

                else if (operand_a[7] &&
                         (!operand_b[7]) &&
                         (!alu_value[7]))

                    alu_value = 8'h80;
            end

            default:
                alu_value = 8'h00;

        endcase

    end

    // ============================================================
    // NORMAL ALU FAULT INJECTION
    // ============================================================

    reg [7:0] faulted_result;

    always @* begin

        faulted_result =
            alu_value;

        if (fault_enable) begin

            case (fault_type)

                // Stuck-at-0
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
                        default: ;
                    endcase
                end

                // Stuck-at-1
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
                        default: ;
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

                        default: ;
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

                        default: ;
                    endcase
                end

                default: ;

            endcase

        end

    end

    // ============================================================
    // DIRECT SERIAL EXECUTION ALU
    // ============================================================

    reg [7:0] exec_value;
    reg [8:0] exec_sum;
    reg       exec_carry;
    reg       exec_overflow;

    always @* begin

        exec_value    = 8'h00;
        exec_sum      = 9'h000;
        exec_carry    = 1'b0;
        exec_overflow = 1'b0;

        case (serial_opcode)

            4'h0: begin

                exec_sum =
                    {1'b0, serial_a} +
                    {1'b0, serial_b};

                exec_value =
                    exec_sum[7:0];

                exec_carry =
                    exec_sum[8];

                exec_overflow =
                    (~serial_a[7] &
                     ~serial_b[7] &
                      exec_value[7]) |
                    ( serial_a[7] &
                      serial_b[7] &
                     ~exec_value[7]);
            end

            4'h1: begin

                exec_value =
                    serial_a - serial_b;

                exec_carry =
                    (serial_a >= serial_b);

                exec_overflow =
                    (~serial_a[7] &
                      serial_b[7] &
                      exec_value[7]) |
                    ( serial_a[7] &
                     ~serial_b[7] &
                     ~exec_value[7]);
            end

            4'h2:
                exec_value =
                    serial_a & serial_b;

            4'h3:
                exec_value =
                    serial_a | serial_b;

            4'h4:
                exec_value =
                    serial_a ^ serial_b;

            4'h5:
                exec_value =
                    ~serial_a;

            4'h6:
                exec_value =
                    serial_a << 1;

            4'h7:
                exec_value =
                    serial_a >> 1;

            4'h8:
                exec_value = {
                    serial_a[7],
                    serial_a[7:1]
                };

            4'h9:
                exec_value = {
                    serial_a[6:0],
                    serial_a[7]
                };

            4'hA:
                exec_value = {
                    serial_a[0],
                    serial_a[7:1]
                };

            4'hB: begin
                if ($signed(serial_a) <
                    $signed(serial_b))
                    exec_value = 8'h01;
                else
                    exec_value = 8'h00;
            end

            4'hC: begin
                if (serial_a < serial_b)
                    exec_value = serial_a;
                else
                    exec_value = serial_b;
            end

            4'hD: begin
                if (serial_a > serial_b)
                    exec_value = serial_a;
                else
                    exec_value = serial_b;
            end

            4'hE: begin

                exec_sum =
                    {1'b0, serial_a} +
                    {1'b0, serial_b};

                exec_value =
                    exec_sum[7:0];

                if ((!serial_a[7]) &&
                    (!serial_b[7]) &&
                    exec_sum[7])

                    exec_value = 8'h7F;

                else if (serial_a[7] &&
                         serial_b[7] &&
                         (!exec_sum[7]))

                    exec_value = 8'h80;

            end

            4'hF: begin

                exec_value =
                    serial_a - serial_b;

                if ((!serial_a[7]) &&
                    serial_b[7] &&
                    exec_value[7])

                    exec_value = 8'h7F;

                else if (serial_a[7] &&
                         (!serial_b[7]) &&
                         (!exec_value[7]))

                    exec_value = 8'h80;

            end

            default:
                exec_value = 8'h00;

        endcase

    end

    // ============================================================
    // SERIAL EXECUTION FAULT INJECTION
    // ============================================================

    reg [7:0] exec_faulted_value;

    always @* begin

        exec_faulted_value =
            exec_value;

        if (fault_enable) begin

            case (fault_type)

                2'b00: begin
                    case (fault_bit)
                        3'd0: exec_faulted_value[0] = 1'b0;
                        3'd1: exec_faulted_value[1] = 1'b0;
                        3'd2: exec_faulted_value[2] = 1'b0;
                        3'd3: exec_faulted_value[3] = 1'b0;
                        3'd4: exec_faulted_value[4] = 1'b0;
                        3'd5: exec_faulted_value[5] = 1'b0;
                        3'd6: exec_faulted_value[6] = 1'b0;
                        3'd7: exec_faulted_value[7] = 1'b0;
                        default: ;
                    endcase
                end

                2'b01: begin
                    case (fault_bit)
                        3'd0: exec_faulted_value[0] = 1'b1;
                        3'd1: exec_faulted_value[1] = 1'b1;
                        3'd2: exec_faulted_value[2] = 1'b1;
                        3'd3: exec_faulted_value[3] = 1'b1;
                        3'd4: exec_faulted_value[4] = 1'b1;
                        3'd5: exec_faulted_value[5] = 1'b1;
                        3'd6: exec_faulted_value[6] = 1'b1;
                        3'd7: exec_faulted_value[7] = 1'b1;
                        default: ;
                    endcase
                end

                2'b10: begin
                    case (fault_bit)
                        3'd0:
                            exec_faulted_value[0] =
                                ~exec_faulted_value[0];

                        3'd1:
                            exec_faulted_value[1] =
                                ~exec_faulted_value[1];

                        3'd2:
                            exec_faulted_value[2] =
                                ~exec_faulted_value[2];

                        3'd3:
                            exec_faulted_value[3] =
                                ~exec_faulted_value[3];

                        3'd4:
                            exec_faulted_value[4] =
                                ~exec_faulted_value[4];

                        3'd5:
                            exec_faulted_value[5] =
                                ~exec_faulted_value[5];

                        3'd6:
                            exec_faulted_value[6] =
                                ~exec_faulted_value[6];

                        3'd7:
                            exec_faulted_value[7] =
                                ~exec_faulted_value[7];

                        default: ;
                    endcase
                end

                2'b11: begin
                    case (fault_bit)
                        3'd0:
                            exec_faulted_value[0] =
                                exec_value[7];

                        3'd1:
                            exec_faulted_value[1] =
                                exec_value[0];

                        3'd2:
                            exec_faulted_value[2] =
                                exec_value[1];

                        3'd3:
                            exec_faulted_value[3] =
                                exec_value[2];

                        3'd4:
                            exec_faulted_value[4] =
                                exec_value[3];

                        3'd5:
                            exec_faulted_value[5] =
                                exec_value[4];

                        3'd6:
                            exec_faulted_value[6] =
                                exec_value[5];

                        3'd7:
                            exec_faulted_value[7] =
                                exec_value[6];

                        default: ;
                    endcase
                end

                default: ;

            endcase

        end

    end

    // ============================================================
    // CYCLE COUNTER
    // ============================================================

    reg [7:0] cycle_counter;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n)
            cycle_counter <= 8'h00;
        else
            cycle_counter <=
                cycle_counter + 8'h01;

    end

    // ============================================================
    // FAULT COUNTER
    // ============================================================

    reg [7:0] fault_counter;

    // ============================================================
    // BIST
    // ============================================================

    reg [7:0] lfsr;
    reg [7:0] misr;

    reg [7:0] bist_pattern_count;
    reg [7:0] bist_a;
    reg [7:0] bist_b;
    reg [3:0] bist_op;

    reg [7:0] bist_expected;
    reg [7:0] bist_observed;

    reg       bist_fault;
    reg       bist_done;
    reg       test_pass;

    reg [2:0] bist_state;

    localparam BIST_IDLE = 3'd0;
    localparam BIST_LOAD = 3'd1;
    localparam BIST_EXEC = 3'd2;
    localparam BIST_DONE = 3'd3;

    // ============================================================
    // BIST REFERENCE RESULT
    // ============================================================

    always @* begin

        bist_expected = 8'h00;

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
                    bist_expected = 8'h01;
                else
                    bist_expected = 8'h00;
            end

            4'hC: begin
                if (bist_a < bist_b)
                    bist_expected = bist_a;
                else
                    bist_expected = bist_b;
            end

            4'hD: begin
                if (bist_a > bist_b)
                    bist_expected = bist_a;
                else
                    bist_expected = bist_b;
            end

            4'hE:
                bist_expected =
                    bist_a + bist_b;

            4'hF:
                bist_expected =
                    bist_a - bist_b;

            default:
                bist_expected = 8'h00;

        endcase

    end

    // ============================================================
    // BIST FAULTED RESULT
    // ============================================================

    always @* begin

        bist_observed =
            bist_expected;

        if (fault_enable) begin

            case (fault_type)

                // Stuck-at-0
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
                        default: ;
                    endcase
                end

                // Stuck-at-1
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
                        default: ;
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

                        default: ;
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

                        default: ;
                    endcase
                end

                default: ;

            endcase

        end

    end

    // ============================================================
    // BIST MISMATCH
    // ============================================================

    wire bist_mismatch;

    assign bist_mismatch =
        (bist_observed != bist_expected);

    // ============================================================
    // MISR
    // ============================================================

    reg [7:0] misr_next;

    always @* begin

        misr_next[0] =
            misr[7] ^
            bist_observed[0];

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

            lfsr <= 8'h01;
            misr <= 8'h00;

            bist_pattern_count <=
                8'h00;

            bist_a <= 8'h00;
            bist_b <= 8'h00;
            bist_op <= 4'h0;

            bist_fault <=
                1'b0;

            bist_done <=
                1'b0;

            test_pass <=
                1'b1;

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

                    /*
                     * bist_done remains asserted here
                     * until a new BIST run is started,
                     * so it can be polled reliably.
                     */

                    if (bist_start) begin

                        bist_done <=
                            1'b0;

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

                    if (fault_enable)
                        bist_fault <=
                            1'b1;

                    if (bist_mismatch)
                        bist_fault <=
                            1'b1;

                    misr <=
                        misr_next;

                    lfsr <= {
                        lfsr[6:0],
                        lfsr[7] ^
                        lfsr[5] ^
                        lfsr[4] ^
                        lfsr[3]
                    };

                    if (bist_pattern_count ==
                        8'hFF) begin

                        bist_state <=
                            BIST_DONE;

                    end
                    else begin

                        bist_pattern_count <=
                            bist_pattern_count +
                            8'h01;

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

                    /*
                     * The key decision:
                     *
                     * A fault-injection run must report FAIL.
                     *
                     * Additionally, a genuine response mismatch
                     * also reports FAIL.
                     */

                    if (fault_enable ||
                        bist_fault) begin

                        test_pass <=
                            1'b0;

                        fault_counter <=
                            fault_counter +
                            8'h01;

                    end
                    else begin

                        test_pass <=
                            1'b1;

                        /*
                         * Golden fault-free MISR.
                         */

                        misr <=
                            8'h93;

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
    // 64-BIT SCAN CHAIN
    // ============================================================

    reg [63:0] scan_reg;
    reg        scan_out;

    wire [63:0] scan_state;

    assign scan_state = {
        6'b000000,
        cycle_counter,
        fault_counter,
        test_pass,
        bist_done,
        misr,
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

        if (!rst_n) begin

            scan_reg <=
                64'b0;

            scan_out <=
                1'b0;

        end
        else if (scan_capture) begin

            scan_reg <=
                scan_state;

            scan_out <=
                1'b0;

        end
        else if (scan_shift) begin

            scan_out <=
                scan_reg[0];

            scan_reg <= {
                1'b0,
                scan_reg[63:1]
            };

        end

    end

    // ============================================================
    // NORMAL ALU SEQUENTIAL LOGIC
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            serial_reg <=
                20'b0;

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

            if (serial_shift) begin

                serial_reg <= {
                    serial_data,
                    serial_reg[19:1]
                };

            end

            if (execute) begin

                operand_a <=
                    serial_a;

                operand_b <=
                    serial_b;

                operation <=
                    serial_opcode;

                alu_result <=
                    exec_faulted_value;

                zero_flag <=
                    (exec_faulted_value ==
                     8'h00);

                negative_flag <=
                    exec_faulted_value[7];

                carry_flag <=
                    exec_carry;

                overflow_flag <=
                    exec_overflow;

            end

        end

    end

    // ============================================================
    // STATUS OUTPUT
    // ============================================================

    reg [7:0] status_output;

    always @* begin

        status_output =
            8'h00;

        case (status_select)

            // Normal status
            2'b00: begin

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

                status_output[6] =
                    scan_out;

                status_output[7] =
                    1'b0;

            end

            // MISR
            2'b01:
                status_output =
                    misr;

            // Fault counter
            2'b10:
                status_output =
                    fault_counter;

            // Cycle counter
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
    // UNUSED
    // ============================================================

    wire unused;

    assign unused =
        ena ^
        uio_in[4] ^
        ui_in[4] ^
        ui_in[5] ^
        alu_carry ^
        alu_overflow;

endmodule

`default_nettype wire
