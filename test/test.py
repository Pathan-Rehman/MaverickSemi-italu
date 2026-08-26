import cocotb
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ClockCycles
from cocotb.clock import Clock
import random

async def reset_dut(dut):
    """Reset the DUT"""
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

async def load_serial(dut, value, bits):
    """Load a value serially"""
    for i in range(bits):
        dut.ui_in.value = (value >> i) & 1
        await RisingEdge(dut.clk)
    await ClockCycles(dut.clk, 2)

async def press_button(dut, button_bit):
    """Press and release a button"""
    current = int(dut.ui_in.value)
    dut.ui_in.value = current | (1 << button_bit)
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = current & ~(1 << button_bit)
    await ClockCycles(dut.clk, 2)

@cocotb.test()
async def test_alu_add(dut):
    """Test ADD operation"""
    # Start clock
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Set functional mode
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    
    # Load operation (ADD = 000)
    await load_serial(dut, 0b000, 3)
    
    # Load operand A = 15 (0x0F)
    await load_serial(dut, 0x0F, 8)
    
    # Load operand B = 3 (0x03)
    await load_serial(dut, 0x03, 8)
    
    # Press execute button (CTRL_BTN = bit 1)
    await press_button(dut, 1)
    
    # Wait for operation to complete
    await ClockCycles(dut.clk, 20)
    
    cocotb.log.info("ADD Result segments: %s", dut.uo_out.value)
    cocotb.log.info("Test ADD: COMPLETE")

@cocotb.test()
async def test_alu_sub(dut):
    """Test SUB operation"""
    # Start clock
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Set functional mode
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    
    # Load operation (SUB = 001)
    await load_serial(dut, 0b001, 3)
    
    # Load operand A = 10 (0x0A)
    await load_serial(dut, 0x0A, 8)
    
    # Load operand B = 5 (0x05)
    await load_serial(dut, 0x05, 8)
    
    # Press execute button
    await press_button(dut, 1)
    
    # Wait for operation
    await ClockCycles(dut.clk, 20)
    
    cocotb.log.info("SUB Result segments: %s", dut.uo_out.value)
    cocotb.log.info("Test SUB: COMPLETE")

@cocotb.test()
async def test_scan_chain(dut):
    """Test scan chain operation"""
    # Start clock
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Enable scan mode (SCAN_EN = bit 4)
    dut.ui_in.value = (1 << 4)
    await ClockCycles(dut.clk, 5)
    
    # Shift in test pattern
    test_pattern = 0b10101010
    for i in range(8):
        # Set SCAN_EN, SCAN_CLK, and SCAN_IN
        dut.ui_in.value = (1 << 4) | (1 << 5) | ((test_pattern >> i) & 1)
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
    
    # Disable scan
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 10)
    
    cocotb.log.info("Scan chain test: COMPLETE")

@cocotb.test()
async def test_bist(dut):
    """Test BIST operation"""
    # Start clock
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    # Start BIST (BIST_START = bit 7)
    dut.ui_in.value = (1 << 7)
    await ClockCycles(dut.clk, 5)
    dut.ui_in.value = 0
    
    # Wait for BIST to complete (256 patterns)
    await ClockCycles(dut.clk, 600)
    
    # Check outputs (convert to int first)
    uio_val = int(dut.uio_out.value)
    bist_done = (uio_val >> 3) & 1
    test_pass = (uio_val >> 4) & 1
    
    cocotb.log.info("BIST Done: %d", bist_done)
    cocotb.log.info("Test PASS: %d", test_pass)
    cocotb.log.info("Test BIST: COMPLETE")

@cocotb.test()
async def test_all(dut):
    """Run all tests"""
    # Start clock
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize
    dut.ena.value = 1
    await reset_dut(dut)
    
    cocotb.log.info("=== Starting iTALU Tests ===")
    
    # Test 1: ADD
    cocotb.log.info("--- Test 1: ADD Operation ---")
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    await load_serial(dut, 0b000, 3)  # ADD
    await load_serial(dut, 0x0F, 8)    # A = 15
    await load_serial(dut, 0x03, 8)    # B = 3
    await press_button(dut, 1)
    await ClockCycles(dut.clk, 20)
    cocotb.log.info("ADD Result: %s", dut.uo_out.value)
    
    # Test 2: SUB
    cocotb.log.info("--- Test 2: SUB Operation ---")
    await reset_dut(dut)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    await load_serial(dut, 0b001, 3)  # SUB
    await load_serial(dut, 0x0A, 8)    # A = 10
    await load_serial(dut, 0x05, 8)    # B = 5
    await press_button(dut, 1)
    await ClockCycles(dut.clk, 20)
    cocotb.log.info("SUB Result: %s", dut.uo_out.value)
    
    # Test 3: Scan Chain
    cocotb.log.info("--- Test 3: Scan Chain ---")
    await reset_dut(dut)
    dut.ui_in.value = (1 << 4)  # SCAN_EN
    await ClockCycles(dut.clk, 5)
    test_pattern = 0b10101010
    for i in range(8):
        dut.ui_in.value = (1 << 4) | (1 << 5) | ((test_pattern >> i) & 1)
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 10)
    cocotb.log.info("Scan chain test complete")
    
    # Test 4: BIST
    cocotb.log.info("--- Test 4: BIST ---")
    await reset_dut(dut)
    dut.ui_in.value = (1 << 7)  # BIST_START
    await ClockCycles(dut.clk, 5)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 600)
    uio_val = int(dut.uio_out.value)
    bist_done = (uio_val >> 3) & 1
    test_pass = (uio_val >> 4) & 1
    cocotb.log.info("BIST Done: %d", bist_done)
    cocotb.log.info("Test PASS: %d", test_pass)
    
    cocotb.log.info("=== All Tests Complete ===")
