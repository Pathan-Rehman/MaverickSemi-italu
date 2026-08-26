![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# iTALU: Interactive Testable Arithmetic Logic Unit

An 8-bit ALU for Tiny Tapeout with comprehensive Design-for-Testability (DFT):
a full scan chain, a LFSR/MISR-based Built-In Self-Test (BIST) with fault
detection, and user-controlled fault injection — all drivable through a simple
serial interface.

- [Detailed documentation](docs/info.md)
- [Testbench documentation](test/README.md)

## Features

- **8-bit ALU** with 16 operations (`0x0`–`0xF`): ADD, SUB, AND, OR, XOR, NOT,
  SHL, SHR, SAR, ROL, ROR, signed less-than, MIN, MAX, saturating ADD and
  saturating SUB
- **4 status flags**: Zero, Carry, Negative, Overflow
- **20-bit serial instruction port** (opcode + operand A + operand B,
  loaded LSB-first)
- **64-bit scan chain** over all internal state with capture and shift modes
- **BIST** using an 8-bit LFSR pattern generator and an 8-bit MISR response
  compactor; runs 256 patterns automatically and reports DONE/PASS/FAIL
- **Programmable fault injection** into the ALU result: stuck-at-0,
  stuck-at-1, inversion, and coupling faults on any result bit
- **Status readback multiplexer**: flags/BIST status, MISR signature,
  fault counter, or free-running cycle counter

## Pinout

### Inputs (`ui_in`)

| Pin | Name | Description |
|-----|------|-------------|
| `ui_in[0]` | `DATA_IN` | Serial data input for instruction loading |
| `ui_in[1]` | `LOAD_EN` | Shift one bit into the instruction register |
| `ui_in[2]` | `EXECUTE` | Execute the loaded instruction |
| `ui_in[3]` | `SCAN_CAPTURE` | Capture internal state into the scan chain |
| `ui_in[4]` | — | Unused |
| `ui_in[5]` | — | Unused |
| `ui_in[6]` | `SCAN_SHIFT` | Shift the scan chain one bit per clock |
| `ui_in[7]` | `BIST_START` | Start a BIST run |

### Outputs (`uo_out`)

| Pin | Name | Description |
|-----|------|-------------|
| `uo_out[7:0]` | `RESULT` | 8-bit ALU result |

### Bidirectional pins (`uio`)

Inputs while `uio_oe` drives the status output:

| Pin | Name | Description |
|-----|------|-------------|
| `uio_in[0]` | `FAULT_ENABLE` | Enable fault injection |
| `uio_in[2:1]` | `FAULT_TYPE` | 00 = stuck-at-0, 01 = stuck-at-1, 10 = inversion, 11 = coupling |
| `uio_in[5:3]` | `FAULT_BIT` | Result bit the fault applies to |
| `uio_in[7:6]` | `STATUS_SEL` | Status output select (see below) |

Outputs (`uio_out`, selected by `STATUS_SEL`):

| Select | Output |
|--------|--------|
| `00` | `[3:0]` = Zero/Carry/Negative/Overflow flags, `[4]` = BIST done, `[5]` = BIST pass, `[6]` = scan out |
| `01` | MISR signature (8-bit) |
| `10` | Fault counter (8-bit) |
| `11` | Free-running cycle counter (8-bit) |

## How It Works

### Loading and executing an instruction

The instruction register is 20 bits, shifted in **LSB first** while
`ui_in[1]` (LOAD_EN) is high:

```
[19:16] opcode
[15:8]  operand B
[7:0]   operand A
```

1. Hold `DATA_IN` = bit value and pulse `LOAD_EN` for exactly one clock per
   bit, repeating 20 times (LSB first).
2. Pulse `EXECUTE` (`ui_in[2]`) for one clock.
3. Read the result on `uo_out` and the flags on `uio_out[3:0]`
   (with `STATUS_SEL = 00`).

Example: `ADD(0x0F, 0x03)` → result `0x12`.

### Running the BIST

1. Pulse `BIST_START` (`ui_in[7]`) for one clock.
2. The FSM (IDLE → LOAD → EXEC → DONE) runs 256 LFSR-generated patterns
   through the ALU and compacts responses into the MISR.
3. When finished, `BIST_DONE` (`uio_out[4]`) goes high and **stays asserted**
   until the next BIST start, so it can be polled reliably.
4. `TEST_PASS` (`uio_out[5]`) is high if no fault was detected; the golden
   fault-free MISR signature is `0x93` (readable via `STATUS_SEL = 01`).
5. Any detected mismatch or active fault injection sets `TEST_PASS` low and
   increments the fault counter (readable via `STATUS_SEL = 10`).

### Fault injection

Set `FAULT_ENABLE` and choose a fault type and result bit via `uio_in`.
The injected fault affects the normal ALU result, the serial-execution path,
and the BIST comparison simultaneously, so a faulted chip fails its own
self-test — the core demonstration of the DFT flow.

### Scan chain

A 64-bit chain captures `{operand_a, operand_b, operation, alu_result, flags,
misr, bist_done, test_pass, fault_counter, cycle_counter}`:

1. Pulse `SCAN_CAPTURE` (`ui_in[3]`) for one clock to load internal state.
2. Toggle `SCAN_SHIFT` (`ui_in[6]`) — each clock shifts one bit out onto
   `SCAN_OUT` (`uio_out[6]`), LSB first.

## How to Test

### RTL simulation (cocotb + Icarus Verilog)

```sh
cd test
make -B
```

This runs the full regression (11 tests) and produces `results.xml` plus an
FST waveform (`tb.fst`). View it with `gtkwave tb.fst tb.gtkw` or
`surfer tb.fst`. Gate-level simulation after hardening:

```sh
make -B GATES=yes
```

### Regression coverage

The cocotb suite (`test/test.py`) verifies every feature of the design:

| # | Test | What it verifies |
|---|------|------------------|
| 1 | `test_add` | Basic ADD instruction: 0x0F + 0x03 = 0x12 |
| 2 | `test_sub` | Basic SUB instruction: 0x0A - 0x05 = 0x05 |
| 3 | `test_all_alu_operations` | All 16 opcodes against a Python reference model |
| 4 | `test_alu_flags` | Zero, Carry, Negative and Overflow flag generation |
| 5 | `test_normal_fault_injection` | Stuck-at fault changes the normal ALU result |
| 6 | `test_bist_pass` | Fault-free BIST completes, passes, and yields MISR signature 0x93 |
| 7 | `test_bist_fault_detection` | All 4 fault types are detected by the BIST |
| 8 | `test_fault_counter` | Fault counter increments on detected faults |
| 9 | `test_scan_chain` | Capture + shift returns operands correctly |
| 10 | `test_cycle_counter` | Cycle counter advances with the clock |
| 11 | `test_complete_system` | End-to-end: ALU, fault-free BIST, and fault detection together |

Current status: **11/11 tests passing** in RTL simulation, and the design has
been hardened successfully with LibreLane (GDS generated).

## External Hardware

No external hardware is strictly required — all I/O can be driven from a
microcontroller or FPGA over the serial interface. For standalone use:

- Push buttons / DIP switches for `ui_in` control lines
- LEDs or a logic analyzer on `uio_out` for flags, BIST status and scan out
- An LED bus or MCU on `uo_out` to display the ALU result

## Resources

- [Tiny Tapeout FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## License

This project is licensed under Apache-2.0.

## Acknowledgments

- [Tiny Tapeout](https://tinytapeout.com) for the platform
- IHP for the SG13G2 PDK
- The open source EDA community
