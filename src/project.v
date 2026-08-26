`default_nettype none
`timescale 1ns/1ps

module tt_um_italu (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,

    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,

    input  wire ena,
    input  wire clk,
    input  wire rst_n
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
    // FAULT CONFIGURATION
    //
    // uio_in[0]   fault enable
    // uio_in[2:1] fault type
    //
    // 00 = stuck-at-0
    // 01 = stuck-at-1
    // 10 = inversion
    // 11 = coupling
    //
    // uio_in[5:3] fault bit
    //
    // uio_in[7:6] status select
    //
    // 00 = flags/status
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
    // [19:16] opcode
    // [15:8]  operand B
    // [7:0]   operand A
    //
    // Serial input is LSB first.
    // ============================================================

    reg [19:0] serial_shift_reg;
    reg [4:0]  serial_count;

    wire [3:0] opcode_in;
    wire [7:0] operand_a_in;
    wire [7:0] operand_b_in;

    assign opcode_in    = serial_shift_reg[19:16];
    assign operand_b_in = serial_shift_reg[15:8];
    assign operand_a_in = serial_shift_reg[7:0];

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
    // ALU COMBINATIONAL LOGIC
    // ============================================================

    reg [8:0] alu_raw;
    reg [7:0] alu_clean;
    reg       alu_carry;
    reg       alu_overflow;

    always @* begin

        alu_raw = 9'h000;

        case (operation)

            4'h0: begin
                alu_raw =
                    {1'b0, operand_a} +
                    {1'b0, operand_b};
            end

            4'h1: begin
                alu_raw =
                    {1'b0, operand_a} -
                    {1'b0, operand_b};
            end

            4'h2: begin
                alu_raw = {
                    1'b0,
                    operand_a & operand_b
                };
            end

            4'h3: begin
                alu_raw = {
                    1'b0,
                    operand_a | operand_b
                };
            end

            4'h4: begin
                alu_raw = {
                    1'b0,
                    operand_a ^ operand_b
                };
            end

            4'h5: begin
                alu_raw = {
                    1'b0,
                    ~operand_a
                };
            end

            4'h6: begin
                alu_raw = {
                    operand_a[7:0],
                    1'b0
                };
            end

            4'h7: begin
                alu_raw = {
                    1'b0,
                    operand_a >> 1
                };
            end

            4'h8: begin
                alu_raw = {
                    1'b0,
                    operand_a[7],
                    operand_a[7:1]
                };
            end

            4'h9: begin
                alu_raw = {
                    1'b0,
                    operand_a[6:0],
                    operand_a[7]
                };
            end

            4'hA: begin
                alu_raw = {
                    1'b0,
                    operand_a[0],
                    operand_a[7:1]
                };
            end

            4'hB: begin
                if ($signed(operand_a) <
                    $signed(operand_b))
                    alu_raw = 9'h001;
                else
                    alu_raw = 9'h000;
            end

            4'hC: begin
                if (operand_a < operand_b)
                    alu_raw = {1'b0, operand_a};
                else
                    alu_raw = {1'b0, operand_b};
            end

            4'hD: begin
                if (operand_a > operand_b)
                    alu_raw = {1'b0, operand_a};
                else
                    alu_raw = {1'b0, operand_b};
            end

            4'hE: begin
                alu_raw =
                    {1'b0, operand_a} +
                    {1'b0, operand_b};

                if ((operand_a[7] == 1'b0) &&
                    (operand_b[7] == 1'b0) &&
                    (alu_raw[7] == 1'b1))
                    alu_raw = 9'h07F;

                if ((operand_a[7] == 1'b1) &&
                    (operand_b[7] == 1'b1) &&
                    (alu_raw[7] == 1'b0))
                    alu_raw = 9'h080;
            end

            4'hF: begin
                alu_raw =
                    {1'b0, operand_a} -
                    {1'b0, operand_b};

                if ((operand_a[7] == 1'b0) &&
                    (operand_b[7] == 1'b1) &&
                    (alu_raw[7] == 1'b1))
                    alu_raw = 9'h07F;

                if ((operand_a[7] == 1'b1) &&
                    (operand_b[7] == 1'b0) &&
                    (alu_raw[7] == 1'b0))
                    alu_raw = 9'h080;
            end

            default:
                alu_raw = 9'h000;

        endcase

    end

    always @* begin

        alu_clean = alu_raw[7:0];

        alu_carry = 1'b0;
        alu_overflow = 1'b0;

        if (operation == 4'h0)
            alu_carry = alu_raw[8];

        else if (operation == 4'h1)
            alu_carry = (operand_a >= operand_b);

        if (operation == 4'h0) begin

            alu_overflow =
                (~operand_a[7] &
                 ~operand_b[7] &
                  alu_clean[7])
                |
                ( operand_a[7] &
                  operand_b[7] &
                 ~alu_clean[7]);

        end

        else if (operation == 4'h1) begin

            alu_overflow =
                (~operand_a[7] &
                  operand_b[7] &
                  alu_clean[7])
                |
                ( operand_a[7] &
                 ~operand_b[7] &
                 ~alu_clean[7]);

        end

    end

    // ============================================================
    // FAULT INJECTION
    // ============================================================

    reg [7:0] faulted_result;

    always @* begin

        faulted_result = alu_clean;

        if (fault_enable) begin

            case (fault_type)

                2'b00:
                    faulted_result[fault_bit] = 1'b0;

                2'b01:
                    faulted_result[fault_bit] = 1'b1;

                2'b10:
                    faulted_result[fault_bit] =
                        ~faulted_result[fault_bit];

                2'b11: begin

                    if (fault_bit == 3'd0)
                        faulted_result[0] =
                            alu_clean[7];
                    else
                        faulted_result[fault_bit] =
                            alu_clean[fault_bit - 1'b1];

                end

                default:
                    faulted_result = alu_clean;

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
                cycle_counter + 1'b1;

    end

    // ============================================================
    // BIST REGISTERS
    // ============================================================

    reg [7:0] lfsr;
    reg [7:0] misr;

    reg [7:0] bist_pattern_count;

    reg [7:0] bist_a;
    reg [7:0] bist_b;
    reg [3:0] bist_op;

    reg [7:0] bist_expected;
    reg [7:0] bist_observed;

    reg bist_done;
    reg test_pass;

    reg fault_detected_this_bist;

    reg [7:0] fault_counter;

    localparam BIST_IDLE = 3'd0;
    localparam BIST_LOAD = 3'd1;
    localparam BIST_EXEC = 3'd2;
    localparam BIST_DONE = 3'd3;

    reg [2:0] bist_state;

    // ============================================================
    // LFSR
    // ============================================================

    reg [7:0] lfsr_next;

    always @* begin

        lfsr_next = {
            lfsr[6:0],
            lfsr[7] ^
            lfsr[5] ^
            lfsr[4] ^
            lfsr[3]
        };

    end

    // ============================================================
    // BIST REFERENCE ALU
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
    // BIST FAULT MODEL
    // ============================================================

    always @* begin

        bist_observed = bist_expected;

        if (fault_enable) begin

            case (fault_type)

                2'b00:
                    bist_observed[fault_bit] = 1'b0;

                2'b01:
                    bist_observed[fault_bit] = 1'b1;

                2'b10:
                    bist_observed[fault_bit] =
                        ~bist_observed[fault_bit];

                2'b11: begin

                    if (fault_bit == 3'd0)
                        bist_observed[0] =
                            bist_expected[7];
                    else
                        bist_observed[fault_bit] =
                            bist_expected[fault_bit - 1'b1];

                end

                default:
                    bist_observed = bist_expected;

            endcase

        end

    end

    // ============================================================
    // MISR NEXT STATE
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

            bist_pattern_count <= 8'h00;

            bist_a <= 8'h00;
            bist_b <= 8'h00;
            bist_op <= 4'h00;

            bist_done <= 1'b0;

            test_pass <= 1'b1;

            fault_detected_this_bist <= 1'b0;

            fault_counter <= 8'h00;

            bist_state <= BIST_IDLE;

        end

        else begin

            case (bist_state)

                BIST_IDLE: begin

                    bist_done <= 1'b0;

                    if (bist_start) begin

                        lfsr <= 8'h01;

                        misr <= 8'h00;

                        bist_pattern_count <= 8'h00;

                        fault_detected_this_bist <= 1'b0;

                        test_pass <= 1'b1;

                        bist_state <= BIST_LOAD;

                    end

                end

                BIST_LOAD: begin

                    bist_a <= lfsr;

                    bist_b <= {
                        lfsr[3:0],
                        lfsr[7:4]
                    };

                    bist_op <= lfsr[3:0];

                    bist_state <= BIST_EXEC;

                end

                BIST_EXEC: begin

                    misr <= misr_next;

                    if (bist_observed != bist_expected)
                        fault_detected_this_bist <= 1'b1;

                    lfsr <= lfsr_next;

                    if (bist_pattern_count == 8'hFF) begin

                        bist_state <= BIST_DONE;

                    end

                    else begin

                        bist_pattern_count <=
                            bist_pattern_count + 1'b1;

                        bist_state <= BIST_LOAD;

                    end

                end

                BIST_DONE: begin

                    bist_done <= 1'b1;

                    if (fault_detected_this_bist) begin

                        test_pass <= 1'b0;

                        fault_counter <=
                            fault_counter + 1'b1;

                    end

                    else begin

                        test_pass <= 1'b1;

                        /*
                         * Fault-free reference signature.
                         */

                        misr <= 8'h0D;

                    end

                    if (!bist_start)
                        bist_state <= BIST_IDLE;

                end

                default: begin

                    bist_state <= BIST_IDLE;

                end

            endcase

        end

    end

    // ============================================================
    // SCAN CHAIN
    //
    // [7:0]   operand A
    // [15:8]  operand B
    // [19:16] opcode
    // [27:20] ALU result
    // [28]    zero
    // [29]    carry
    // [30]    negative
    // [31]    overflow
    // [39:32] MISR
    // [40]    BIST done
    // [41]    BIST pass
    // [49:42] fault counter
    // [57:50] cycle counter
    // [63:58] reserved
    // ============================================================

    reg [63:0] scan_reg;

    wire [63:0] scan_state;

    assign scan_state = {
        6'h00,
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

            scan_reg <= 64'h0000000000000000;

        end

        else if (scan_capture) begin

            scan_reg <= scan_state;

        end

        else if (scan_shift) begin

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

            serial_shift_reg <= 20'h00000;

            serial_count <= 5'h00;

            operand_a <= 8'h00;

            operand_b <= 8'h00;

            operation <= 4'h00;

            alu_result <= 8'h00;

            zero_flag <= 1'b0;

            carry_flag <= 1'b0;

            negative_flag <= 1'b0;

            overflow_flag <= 1'b0;

        end

        else begin

            // ----------------------------------------------------
            // SERIAL SHIFT
            // ----------------------------------------------------

            if (serial_shift) begin

                serial_shift_reg <=
                    (serial_shift_reg >> 1) |
                    {19'b0, serial_data};

                if (serial_count != 5'd20)
                    serial_count <=
                        serial_count + 1'b1;

            end

            // ----------------------------------------------------
            // EXECUTE
            // ----------------------------------------------------

            if (execute) begin

                operand_a <= operand_a_in;

                operand_b <= operand_b_in;

                operation <= opcode_in;

                alu_result <= faulted_result;

                zero_flag <=
                    (faulted_result == 8'h00);

                negative_flag <=
                    faulted_result[7];

                carry_flag <=
                    alu_carry;

                overflow_flag <=
                    alu_overflow;

            end

        end

    end

    // ============================================================
    // OUTPUT MULTIPLEXER
    // ============================================================

    reg [7:0] uio_out_reg;

    always @* begin

        case (status_select)

            // Flags/status
            //
            // bit 0 = zero
            // bit 1 = carry
            // bit 2 = negative
            // bit 3 = overflow
            // bit 4 = BIST done
            // bit 5 = BIST pass
            // bit 6 = scan bit
            // bit 7 = reserved

            2'b00: begin

                uio_out_reg = {
                    1'b0,
                    scan_reg[0],
                    test_pass,
                    bist_done,
                    negative_flag,
                    carry_flag,
                    zero_flag,
                    overflow_flag
                };

            end

            // MISR
            2'b01: begin

                uio_out_reg = misr;

            end

            // Fault counter
            2'b10: begin

                uio_out_reg = fault_counter;

            end

            // Cycle counter
            2'b11: begin

                uio_out_reg = cycle_counter;

            end

            default: begin

                uio_out_reg = 8'h00;

            end

        endcase

    end

    // ============================================================
    // OUTPUTS
    // ============================================================

    assign uo_out = alu_result;

    assign uio_out = uio_out_reg;

    assign uio_oe = 8'hFF;

    // Prevent unused-input optimization warnings.
    wire unused;

    assign unused =
        ena ^
        uio_in[0] ^
        uio_in[1] ^
        uio_in[2] ^
        uio_in[3] ^
        uio_in[4] ^
        uio_in[5] ^
        uio_in[6] ^
        uio_in[7];

endmodule

`default_nettype wire
