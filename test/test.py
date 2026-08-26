import cocotb

from cocotb.triggers import (
    RisingEdge,
    Timer,
    ClockCycles,
)


# ================================================================
# CONSTANTS
# ================================================================

EXPECTED_MISR = 0x93

# ui_in definitions

SERIAL_DATA = 0
SERIAL_SHIFT = 1
EXECUTE = 2
SCAN_CAPTURE = 3
SCAN_SHIFT = 6
BIST_START = 7


# ================================================================
# RESET
# ================================================================

async def reset_dut(dut):
    """Reset the DUT to a known state."""

    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    await ClockCycles(
        dut.clk,
        5
    )

    dut.rst_n.value = 1

    await ClockCycles(
        dut.clk,
        3
    )


# ================================================================
# UIO CONFIGURATION
# ================================================================

def make_uio_config(
    enable=0,
    fault_type=0,
    fault_bit=0,
    status=0
):
    """
    Build uio_in.

    uio_in[0]   = fault enable
    uio_in[2:1] = fault type
    uio_in[5:3] = fault bit
    uio_in[7:6] = status select
    """

    value = 0

    value |= (
        enable & 0x1
    )

    value |= (
        (fault_type & 0x3) << 1
    )

    value |= (
        (fault_bit & 0x7) << 3
    )

    value |= (
        (status & 0x3) << 6
    )

    return value


def set_fault(
    dut,
    enable=0,
    fault_type=0,
    fault_bit=0
):
    """
    Configure the programmable fault injector.

    Fault types:
        0 = stuck-at-0
        1 = stuck-at-1
        2 = inversion
        3 = coupling
    """

    current_status = (
        int(dut.uio_in.value) >> 6
    ) & 0x3

    dut.uio_in.value = make_uio_config(
        enable=enable,
        fault_type=fault_type,
        fault_bit=fault_bit,
        status=current_status
    )


def set_status(dut, status):
    """
    Select uio_out status source.

    0 = normal status
    1 = MISR
    2 = fault counter
    3 = cycle counter
    """

    value = int(
        dut.uio_in.value
    )

    value &= 0x3F

    value |= (
        (status & 0x3) << 6
    )

    dut.uio_in.value = value


# ================================================================
# SERIAL INSTRUCTION LOADER
# ================================================================

async def load_instruction(
    dut,
    opcode,
    operand_a,
    operand_b
):
    """
    Load a 20-bit instruction.

    Format:

        [19:16] = opcode
        [15:8]  = operand B
        [7:0]   = operand A

    Bits are transmitted LSB first.
    """

    instruction = (
        ((opcode & 0xF) << 16)
        |
        ((operand_b & 0xFF) << 8)
        |
        (operand_a & 0xFF)
    )

    for i in range(20):

        bit = (
            instruction >> i
        ) & 0x1

        dut.ui_in.value = (
            (1 << SERIAL_SHIFT)
            |
            bit
        )

        await RisingEdge(
            dut.clk
        )

    dut.ui_in.value = 0

    await ClockCycles(
        dut.clk,
        1
    )


# ================================================================
# ALU EXECUTION
# ================================================================

async def execute_instruction(
    dut,
    opcode,
    operand_a,
    operand_b
):
    """
    Load and execute one ALU instruction.
    """

    await load_instruction(
        dut,
        opcode,
        operand_a,
        operand_b
    )

    dut.ui_in.value = (
        1 << EXECUTE
    )

    await RisingEdge(
        dut.clk
    )

    dut.ui_in.value = 0

    await Timer(
        1,
        unit="ns"
    )

    return int(
        dut.uo_out.value
    )


# ================================================================
# PYTHON REFERENCE ALU
# ================================================================

def reference_alu(
    opcode,
    a,
    b
):
    """
    Software reference model for all 16 ALU operations.
    """

    a &= 0xFF
    b &= 0xFF

    # ------------------------------------------------------------
    # ADD
    # ------------------------------------------------------------

    if opcode == 0x0:
        return (
            a + b
        ) & 0xFF

    # ------------------------------------------------------------
    # SUB
    # ------------------------------------------------------------

    if opcode == 0x1:
        return (
            a - b
        ) & 0xFF

    # ------------------------------------------------------------
    # AND
    # ------------------------------------------------------------

    if opcode == 0x2:
        return a & b

    # ------------------------------------------------------------
    # OR
    # ------------------------------------------------------------

    if opcode == 0x3:
        return a | b

    # ------------------------------------------------------------
    # XOR
    # ------------------------------------------------------------

    if opcode == 0x4:
        return a ^ b

    # ------------------------------------------------------------
    # NOT
    # ------------------------------------------------------------

    if opcode == 0x5:
        return (
            ~a
        ) & 0xFF

    # ------------------------------------------------------------
    # SLL
    # ------------------------------------------------------------

    if opcode == 0x6:
        return (
            a << 1
        ) & 0xFF

    # ------------------------------------------------------------
    # SRL
    # ------------------------------------------------------------

    if opcode == 0x7:
        return a >> 1

    # ------------------------------------------------------------
    # SRA
    # ------------------------------------------------------------

    if opcode == 0x8:

        if a & 0x80:
            return (
                (a >> 1)
                |
                0x80
            )

        return a >> 1

    # ------------------------------------------------------------
    # ROL
    # ------------------------------------------------------------

    if opcode == 0x9:

        return (
            ((a << 1) & 0xFF)
            |
            (a >> 7)
        )

    # ------------------------------------------------------------
    # ROR
    # ------------------------------------------------------------

    if opcode == 0xA:

        return (
            (a >> 1)
            |
            ((a & 0x01) << 7)
        )

    # ------------------------------------------------------------
    # SIGNED LESS THAN
    # ------------------------------------------------------------

    if opcode == 0xB:

        signed_a = (
            a
            if a < 128
            else a - 256
        )

        signed_b = (
            b
            if b < 128
            else b - 256
        )

        return int(
            signed_a < signed_b
        )

    # ------------------------------------------------------------
    # MIN
    # ------------------------------------------------------------

    if opcode == 0xC:

        return min(
            a,
            b
        )

    # ------------------------------------------------------------
    # MAX
    # ------------------------------------------------------------

    if opcode == 0xD:

        return max(
            a,
            b
        )

    # ------------------------------------------------------------
    # SATURATING SIGNED ADD
    # ------------------------------------------------------------

    if opcode == 0xE:

        result = (
            a + b
        ) & 0xFF

        positive_overflow = (
            not (a & 0x80)
            and
            not (b & 0x80)
            and
            (result & 0x80)
        )

        negative_overflow = (
            (a & 0x80)
            and
            (b & 0x80)
            and
            not (result & 0x80)
        )

        if positive_overflow:
            return 0x7F

        if negative_overflow:
            return 0x80

        return result

    # ------------------------------------------------------------
    # SATURATING SIGNED SUB
    # ------------------------------------------------------------

    if opcode == 0xF:

        result = (
            a - b
        ) & 0xFF

        positive_overflow = (
            not (a & 0x80)
            and
            (b & 0x80)
            and
            (result & 0x80)
        )

        negative_overflow = (
            (a & 0x80)
            and
            not (b & 0x80)
            and
            not (result & 0x80)
        )

        if positive_overflow:
            return 0x7F

        if negative_overflow:
            return 0x80

        return result

    return 0


# ================================================================
# BIST CONTROL
# ================================================================

async def start_bist(dut):
    """Start one BIST run."""

    dut.ui_in.value = (
        1 << BIST_START
    )

    await RisingEdge(
        dut.clk
    )

    dut.ui_in.value = 0


async def wait_for_bist(
    dut,
    timeout_cycles=600
):
    """
    Wait until BIST done.

    Normal status:
        bit 4 = BIST done
        bit 5 = PASS
    """

    for _ in range(
        timeout_cycles
    ):

        await RisingEdge(
            dut.clk
        )

        status = int(
            dut.uio_out.value
        )

        if status & 0x10:
            return status

    raise AssertionError(
        "BIST did not complete "
        "within timeout"
    )


# ================================================================
# TEST 1 - ADD
# ================================================================

@cocotb.test()
async def test_add(dut):

    await reset_dut(
        dut
    )

    set_fault(
        dut,
        enable=0
    )

    result = await execute_instruction(
        dut,
        0x0,
        0x0F,
        0x03
    )

    assert result == 0x12, (
        f"ADD failed: "
        f"expected 0x12, "
        f"got 0x{result:02X}"
    )

    cocotb.log.info(
        "ADD PASS: 0x0F + 0x03 = 0x%02X",
        result
    )


# ================================================================
# TEST 2 - SUB
# ================================================================

@cocotb.test()
async def test_sub(dut):

    await reset_dut(
        dut
    )

    set_fault(
        dut,
        enable=0
    )

    result = await execute_instruction(
        dut,
        0x1,
        0x0A,
        0x05
    )

    assert result == 0x05, (
        f"SUB failed: "
        f"expected 0x05, "
        f"got 0x{result:02X}"
    )

    cocotb.log.info(
        "SUB PASS: 0x0A - 0x05 = 0x%02X",
        result
    )


# ================================================================
# TEST 3 - ALL ALU OPERATIONS
# ================================================================

@cocotb.test()
async def test_all_alu_operations(dut):

    await reset_dut(
        dut
    )

    set_fault(
        dut,
        enable=0
    )

    test_vectors = [

        (0x0, 0x15, 0x27),
        (0x1, 0x40, 0x15),
        (0x2, 0xAA, 0x0F),
        (0x3, 0xA0, 0x0F),
        (0x4, 0xAA, 0x55),
        (0x5, 0x55, 0x00),
        (0x6, 0x81, 0x00),
        (0x7, 0x81, 0x00),
        (0x8, 0x81, 0x00),
        (0x9, 0x81, 0x00),
        (0xA, 0x81, 0x00),
        (0xB, 0xF0, 0x10),
        (0xC, 0x10, 0x20),
        (0xD, 0x10, 0x20),
        (0xE, 0x7F, 0x01),
        (0xF, 0x80, 0x01),

    ]

    for opcode, a, b in test_vectors:

        expected = reference_alu(
            opcode,
            a,
            b
        )

        result = await execute_instruction(
            dut,
            opcode,
            a,
            b
        )

        assert result == expected, (
            f"Opcode 0x{opcode:X} failed: "
            f"A=0x{a:02X}, "
            f"B=0x{b:02X}, "
            f"expected=0x{expected:02X}, "
            f"got=0x{result:02X}"
        )

    cocotb.log.info(
        "ALL 16 ALU OPERATIONS PASS"
    )


# ================================================================
# TEST 4 - FLAGS
# ================================================================

@cocotb.test()
async def test_alu_flags(dut):

    await reset_dut(
        dut
    )

    set_fault(
        dut,
        enable=0
    )

    # ------------------------------------------------------------
    # Signed overflow
    #
    # 0x7F + 0x01 = 0x80
    # ------------------------------------------------------------

    result = await execute_instruction(
        dut,
        0x0,
        0x7F,
        0x01
    )

    assert result == 0x80

    status = int(
        dut.uio_out.value
    )

    overflow = (
        status >> 3
    ) & 1

    negative = (
        status >> 2
    ) & 1

    assert overflow == 1, (
        "Overflow flag not asserted"
    )

    assert negative == 1, (
        "Negative flag not asserted"
    )

    # ------------------------------------------------------------
    # Carry + zero
    #
    # 0xFF + 0x01 = 0x00
    # ------------------------------------------------------------

    result = await execute_instruction(
        dut,
        0x0,
        0xFF,
        0x01
    )

    status = int(
        dut.uio_out.value
    )

    zero = (
        status
        & 1
    )

    carry = (
        status >> 1
    ) & 1

    assert result == 0x00

    assert zero == 1, (
        "Zero flag not asserted"
    )

    assert carry == 1, (
        "Carry flag not asserted"
    )

    cocotb.log.info(
        "FLAGS PASS"
    )


# ================================================================
# TEST 5 - NORMAL FAULT INJECTION
# ================================================================

@cocotb.test()
async def test_normal_fault_injection(dut):

    await reset_dut(
        dut
    )

    # ------------------------------------------------------------
    # No fault
    # ------------------------------------------------------------

    set_fault(
        dut,
        enable=0
    )

    result = await execute_instruction(
        dut,
        0x0,
        0x02,
        0x02
    )

    assert result == 0x04

    # ------------------------------------------------------------
    # Stuck-at-1 on result bit 0
    # ------------------------------------------------------------

    set_fault(
        dut,
        enable=1,
        fault_type=1,
        fault_bit=0
    )

    result = await execute_instruction(
        dut,
        0x0,
        0x02,
        0x02
    )

    assert result == 0x05, (
        f"Fault injection failed: "
        f"expected 0x05, "
        f"got 0x{result:02X}"
    )

    cocotb.log.info(
        "FAULT INJECTION PASS"
    )


# ================================================================
# TEST 6 - FAULT-FREE BIST
# ================================================================

@cocotb.test()
async def test_bist_pass(dut):

    await reset_dut(
        dut
    )

    set_fault(
        dut,
        enable=0
    )

    await start_bist(
        dut
    )

    status = await wait_for_bist(
        dut
    )

    assert (
        (status >> 4) & 1
    ) == 1, (
        "BIST did not assert DONE"
    )

    assert (
        (status >> 5) & 1
    ) == 1, (
        "Fault-free BIST did not PASS"
    )

    # ------------------------------------------------------------
    # Read MISR
    # ------------------------------------------------------------

    set_status(
        dut,
        1
    )

    await Timer(
        1,
        unit="ns"
    )

    signature = int(
        dut.uio_out.value
    )

    assert signature == EXPECTED_MISR, (
        f"Incorrect golden MISR: "
        f"expected 0x{EXPECTED_MISR:02X}, "
        f"got 0x{signature:02X}"
    )

    cocotb.log.info(
        "BIST PASS"
    )

    cocotb.log.info(
        "MISR signature = 0x%02X",
        signature
    )


# ================================================================
# TEST 7 - FAULT-INJECTED BIST
# ================================================================

@cocotb.test()
async def test_bist_fault_detection(dut):

    for fault_type in range(4):

        await reset_dut(
            dut
        )

        set_fault(
            dut,
            enable=1,
            fault_type=fault_type,
            fault_bit=3
        )

        set_status(
            dut,
            0
        )

        await start_bist(
            dut
        )

        status = await wait_for_bist(
            dut
        )

        # --------------------------------------------------------
        # BIST must finish.
        # --------------------------------------------------------

        assert (
            (status >> 4) & 1
        ) == 1, (
            f"Fault type {fault_type}: "
            "BIST did not complete"
        )

        # --------------------------------------------------------
        # BIST must detect the injected fault.
        # --------------------------------------------------------

        assert (
            (status >> 5) & 1
        ) == 0, (
            f"Fault type {fault_type}: "
            "fault was not detected"
        )

        # --------------------------------------------------------
        # Read signature for diagnostics.
        #
        # Do NOT require a different MISR signature here.
        # MISR aliasing is possible.
        # The PASS/FAIL bit is the authoritative result.
        # --------------------------------------------------------

        set_status(
            dut,
            1
        )

        await Timer(
            1,
            unit="ns"
        )

        signature = int(
            dut.uio_out.value
        )

        cocotb.log.info(
            "Fault %d detected. "
            "MISR=0x%02X",
            fault_type,
            signature
        )

        # --------------------------------------------------------
        # Return to normal configuration.
        # --------------------------------------------------------

        set_fault(
            dut,
            enable=0
        )

        set_status(
            dut,
            0
        )

        await ClockCycles(
            dut.clk,
            3
        )


# ================================================================
# TEST 8 - FAULT COUNTER
# ================================================================

@cocotb.test()
async def test_fault_counter(dut):

    await reset_dut(
        dut
    )

    # ------------------------------------------------------------
    # Counter starts at zero.
    # ------------------------------------------------------------

    set_fault(
        dut,
        enable=0
    )

    set_status(
        dut,
        2
    )

    await Timer(
        1,
        unit="ns"
    )

    count = int(
        dut.uio_out.value
    )

    assert count == 0, (
        f"Expected initial fault counter = 0, "
        f"got {count}"
    )

    # ------------------------------------------------------------
    # Inject inversion fault.
    # ------------------------------------------------------------

    set_fault(
        dut,
        enable=1,
        fault_type=2,
        fault_bit=3
    )

    set_status(
        dut,
        0
    )

    await start_bist(
        dut
    )

    status = await wait_for_bist(
        dut
    )

    # BIST must fail.
    assert (
        (status >> 5) & 1
    ) == 0, (
        "Injected fault was not detected"
    )

    # ------------------------------------------------------------
    # Read counter.
    # ------------------------------------------------------------

    set_status(
        dut,
        2
    )

    await Timer(
        1,
        unit="ns"
    )

    count = int(
        dut.uio_out.value
    )

    assert count >= 1, (
        f"Expected fault counter >= 1, "
        f"got {count}"
    )

    cocotb.log.info(
        "FAULT COUNTER PASS: %d",
        count
    )


# ================================================================
# TEST 9 - SCAN CHAIN
# ================================================================

@cocotb.test()
async def test_scan_chain(dut):

    await reset_dut(
        dut
    )

    set_fault(
        dut,
        enable=0
    )

    # ------------------------------------------------------------
    # Put known values into operand registers.
    # ------------------------------------------------------------

    await execute_instruction(
        dut,
        0x0,
        0xA5,
        0x3C
    )

    # ------------------------------------------------------------
    # Capture scan state.
    # ------------------------------------------------------------

    dut.ui_in.value = (
        1 << SCAN_CAPTURE
    )

    await RisingEdge(
        dut.clk
    )

    dut.ui_in.value = 0

    # ------------------------------------------------------------
    # Shift out 64 bits.
    # ------------------------------------------------------------

    scanned_bits = []

    for _ in range(64):

        dut.ui_in.value = (
            1 << SCAN_SHIFT
        )

        await RisingEdge(
            dut.clk
        )

        await Timer(
            1,
            unit="ns"
        )

        status = int(
            dut.uio_out.value
        )

        scan_bit = (
            status >> 6
        ) & 1

        scanned_bits.append(
            scan_bit
        )

    dut.ui_in.value = 0

    # ------------------------------------------------------------
    # Reconstruct scanned value.
    # ------------------------------------------------------------

    scanned_value = 0

    for i, bit in enumerate(
        scanned_bits
    ):

        scanned_value |= (
            bit << i
        )

    # ------------------------------------------------------------
    # Check operand A.
    # ------------------------------------------------------------

    scanned_a = (
        scanned_value
        & 0xFF
    )

    # ------------------------------------------------------------
    # Check operand B.
    # ------------------------------------------------------------

    scanned_b = (
        scanned_value >> 8
    ) & 0xFF

    assert scanned_a == 0xA5, (
        f"Scan A failed: "
        f"got 0x{scanned_a:02X}"
    )

    assert scanned_b == 0x3C, (
        f"Scan B failed: "
        f"got 0x{scanned_b:02X}"
    )

    cocotb.log.info(
        "SCAN CHAIN PASS"
    )


# ================================================================
# TEST 10 - CYCLE COUNTER
# ================================================================

@cocotb.test()
async def test_cycle_counter(dut):

    await reset_dut(
        dut
    )

    set_status(
        dut,
        3
    )

    await Timer(
        1,
        unit="ns"
    )

    count_before = int(
        dut.uio_out.value
    )

    await ClockCycles(
        dut.clk,
        10
    )

    count_after = int(
        dut.uio_out.value
    )

    assert count_after != count_before, (
        "Cycle counter did not advance"
    )

    cocotb.log.info(
        "CYCLE COUNTER PASS: "
        "%d -> %d",
        count_before,
        count_after
    )


# ================================================================
# TEST 11 - COMPLETE SYSTEM
# ================================================================

@cocotb.test()
async def test_complete_system(dut):

    await reset_dut(
        dut
    )

    cocotb.log.info(
        "========================================"
    )

    cocotb.log.info(
        "        iTALU COMPLETE TEST"
    )

    cocotb.log.info(
        "========================================"
    )

    # ------------------------------------------------------------
    # Normal ALU
    # ------------------------------------------------------------

    set_fault(
        dut,
        enable=0
    )

    result = await execute_instruction(
        dut,
        0x0,
        0x12,
        0x34
    )

    assert result == 0x46, (
        f"Normal ALU failed: "
        f"expected 0x46, "
        f"got 0x{result:02X}"
    )

    cocotb.log.info(
        "Normal ALU PASS"
    )

    # ------------------------------------------------------------
    # Fault-free BIST
    # ------------------------------------------------------------

    await reset_dut(
        dut
    )

    set_fault(
        dut,
        enable=0
    )

    await start_bist(
        dut
    )

    status = await wait_for_bist(
        dut
    )

    assert (
        (status >> 5) & 1
    ) == 1, (
        "Fault-free BIST failed"
    )

    cocotb.log.info(
        "Fault-free BIST PASS"
    )

    # ------------------------------------------------------------
    # Faulted BIST
    # ------------------------------------------------------------

    await reset_dut(
        dut
    )

    set_fault(
        dut,
        enable=1,
        fault_type=2,
        fault_bit=3
    )

    await start_bist(
        dut
    )

    status = await wait_for_bist(
        dut
    )

    assert (
        (status >> 5) & 1
    ) == 0, (
        "Faulted BIST failed to detect fault"
    )

    cocotb.log.info(
        "Fault detection PASS"
    )

    cocotb.log.info(
        "========================================"
    )

    cocotb.log.info(
        "     iTALU COMPLETE SYSTEM PASS"
    )

    cocotb.log.info(
        "========================================"
    )
