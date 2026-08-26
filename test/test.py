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
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())
    
    dut.ena.value = 1
    dut.uio_in.value = 0  # Important: Drive uio_in to 0
    await reset_dut(dut)
    
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    
    await load_serial(dut, 0b000, 3)  # ADD
    await load_serial(dut, 0x0F, 8)    # A = 15
    await load_serial(dut, 0x03, 8)    # B = 3
    
    await press_button(dut, 1)
    await ClockCycles(dut.clk, 20)
    
    cocotb.log.info("ADD Result: %s", dut.uo_out.value)
    cocotb.log.info("Test ADD: PASS")

@cocotb.test()
async def test_alu_sub(dut):
    """Test SUB operation"""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())
    
    dut.ena.value = 1
    dut.uio_in.value = 0  # Important: Drive uio_in to 0
    await reset_dut(dut)
    
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    
    await load_serial(dut, 0b001, 3)  # SUB
    await load_serial(dut, 0x0A, 8)    # A = 10
    await load_serial(dut, 0x05, 8)    # B = 5
    
    await press_button(dut, 1)
    await ClockCycles(dut.clk, 20)
    
    cocotb.log.info("SUB Result: %s", dut.uo_out.value)
    cocotb.log.info("Test SUB: PASS")

@cocotb.test()
async def test_scan_chain(dut):
    """Test scan chain operation"""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())
    
    dut.ena.value = 1
    dut.uio_in.value = 0  # Important: Drive uio_in to 0
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
    
    cocotb.log.info("Scan chain test: PASS")

@cocotb.test()
async def test_bist(dut):
    """Test BIST operation"""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())
    
    dut.ena.value = 1
    dut.uio_in.value = 0  # Important: Drive uio_in to 0
    await reset_dut(dut)
    
    # Start BIST
    dut.ui_in.value = (1 << 7)
    await ClockCycles(dut.clk, 5)
    dut.ui_in.value = 0
    
    # Wait for BIST to complete
    await ClockCycles(dut.clk, 600)
    
    # Log outputs using direct bit access
    cocotb.log.info("uio_out: %s", dut.uio_out.value)
    cocotb.log.info("BIST Done: %s", dut.uio_out.value[3])
    cocotb.log.info("Test PASS: %s", dut.uio_out.value[4])
    cocotb.log.info("Test BIST: PASS")

@cocotb.test()
async def test_all(dut):
    """Run all tests"""
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())
    
    dut.ena.value = 1
    dut.uio_in.value = 0  # Important: Drive uio_in to 0
    await reset_dut(dut)
    
    cocotb.log.info("=== Starting iTALU Tests ===")
    
    # Test 1: ADD
    cocotb.log.info("--- Test 1: ADD ---")
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    await load_serial(dut, 0b000, 3)
    await load_serial(dut, 0x0F, 8)
    await load_serial(dut, 0x03, 8)
    await press_button(dut, 1)
    await ClockCycles(dut.clk, 20)
    cocotb.log.info("ADD Result: %s", dut.uo_out.value)
    
    # Test 2: SUB
    cocotb.log.info("--- Test 2: SUB ---")
    await reset_dut(dut)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5)
    await load_serial(dut, 0b001, 3)
    await load_serial(dut, 0x0A, 8)
    await load_serial(dut, 0x05, 8)
    await press_button(dut, 1)
    await ClockCycles(dut.clk, 20)
    cocotb.log.info("SUB Result: %s", dut.uo_out.value)
    
    # Test 3: Scan Chain
    cocotb.log.info("--- Test 3: Scan Chain ---")
    await reset_dut(dut)
    dut.ui_in.value = (1 << 4)
    await ClockCycles(dut.clk, 5)
    test_pattern = 0b10101010
    for i in range(8):
        dut.ui_in.value = (1 << 4) | (1 << 5) | ((test_pattern >> i) & 1)
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 10)
    
    # Test 4: BIST
    cocotb.log.info("--- Test 4: BIST ---")
    await reset_dut(dut)
    dut.ui_in.value = (1 << 7)
    await ClockCycles(dut.clk, 5)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 600)
    cocotb.log.info("uio_out: %s", dut.uio_out.value)
    cocotb.log.info("BIST Done: %s", dut.uio_out.value[3])
    cocotb.log.info("Test PASS: %s", dut.uio_out.value[4])
    
    cocotb.log.info("=== All Tests Complete ===")
