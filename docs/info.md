# iTALU: Interactive Testable Arithmetic Logic Unit

## Project Overview

iTALU is an 8-bit Arithmetic Logic Unit (ALU) with comprehensive Design-for-Testability (DFT) features, designed for Tiny Tapeout using IHP 180nm technology. The project demonstrates industry-standard testing techniques with user-controlled interaction and visual feedback.

### Key Features

- 8-bit ALU with 8 arithmetic and logical operations
- 4 status flags (Zero, Carry, Negative, Overflow)
- Full scan chain on all internal registers
- Built-In Self-Test (BIST) with LFSR and MISR
- User-controlled fault injection for testing
- Interactive test modes with step-by-step execution
- 7-segment display interface for visual output
- Multiple test modes for comprehensive verification

### Specifications

| Parameter | Value |
|-----------|-------|
| Technology | IHP 180nm (SG13G2) |
| Tile Size | 1x1 (160x100 um) |
| Clock Frequency | Up to 50 MHz |
| Gate Count | ~350-400 gates |
| Power Supply | 1.8V |
| I/O Pins | 8 input, 8 output, 8 bidirectional |

---

## Architecture

### Block Diagram

```
+-----------------------------------------------------------+
|                        iTALU                             |
+-----------------------------------------------------------+
|                                                           |
|  +--------------+     +----------------------------+     |
|  | User         |     |      ALU CORE              |     |
|  | Interface    |---->|  +----------------------+  |     |
|  | Controller   |     |  | 8-bit ALU            |  |     |
|  |              |     |  | (8 operations)       |  |     |
|  +--------------+     |  +----------------------+  |     |
|                       |  +----------------------+  |     |
|  +--------------+     |  | Status Flags         |  |     |
|  | Test Pattern |---->|  | (Z,C,N,O)            |  |     |
|  | Generator    |     |  +----------------------+  |     |
|  +--------------+     +----------------------------+     |
|                                                           |
|  +--------------+     +----------------------------+     |
|  | Fault        |---->|  DFT Infrastructure        |     |
|  | Injector     |     |  +----------------------+  |     |
|  +--------------+     |  | Scan Chain           |  |     |
|                       |  +----------------------+  |     |
|  +--------------+     |  | BIST Controller      |  |     |
|  | Result       |<----|  +----------------------+  |     |
|  | Comparator   |     |  | Boundary Scan        |  |     |
|  +--------------+     |  +----------------------+  |     |
|                       +----------------------------+     |
|                                                           |
|  +--------------------------------------------------+   |
|  |        7-SEGMENT DISPLAY CONTROLLER               |   |
|  |  Shows: Operation, Inputs, Output, Flags          |   |
|  +--------------------------------------------------+   |
+-----------------------------------------------------------+
```

---

## ALU Operations

| Operation | Code | Description | Example |
|-----------|------|-------------|---------|
| ADD | 000 | Addition with carry | A + B |
| SUB | 001 | Subtraction with borrow | A - B |
| AND | 010 | Bitwise AND | A AND B |
| OR | 011 | Bitwise OR | A OR B |
| XOR | 100 | Bitwise XOR | A XOR B |
| NOT | 101 | Bitwise NOT | NOT A |
| SHIFT | 110 | Shift left by 1 | A SHIFT LEFT |
| COMPARE | 111 | Comparison | A EQUAL B |

---

## Status Flags

| Flag | Bit Position | Description |
|------|-------------|-------------|
| Zero (Z) | Bit 3 | Result is 0x00 |
| Carry (C) | Bit 2 | Carry out or borrow |
| Negative (N) | Bit 1 | MSB of result is 1 |
| Overflow (O) | Bit 0 | Signed arithmetic overflow |

---

## Design-for-Testability (DFT) Implementation

### 1. Scan Chain

The scan chain is 32 bits long covering all registers:

```
SCAN_IN -> Operand_A(8) -> Operand_B(8) -> Operation(3) -> Zero(1) -> Carry(1) -> Negative(1) -> Overflow(1) -> ALU_Result(8) -> SCAN_OUT
```

**Features:**
- 32-bit scan chain covering all registers
- Separate scan clock (SCAN_CLK)
- Scan enable control (SCAN_EN)
- Serial input/output for test patterns

### 2. Built-In Self-Test (BIST)

```
+-----------+    +----------------+    +-----------+
|   LFSR    |--->|      ALU       |--->|   MISR    |
|  Pattern  |    |  (Under Test)  |    | Response  |
| Generator |    |                |    | Compactor |
+-----------+    +----------------+    +-----------+
```

**BIST Features:**
- 8-bit LFSR with primitive polynomial
- 256 unique test patterns
- MISR for response compaction
- Automatic pass/fail detection
- Signature comparison

### 3. Fault Injection

| Fault Location | Description | Type |
|----------------|-------------|------|
| 0 | Operand A bit 0 | Stuck-at-0 |
| 1 | Operand A bit 0 | Stuck-at-1 |
| 2 | Operand B bit 7 | Stuck-at-0 |
| 3 | Operand B bit 7 | Stuck-at-1 |
| 4 | ALU Result bit 3 | Stuck-at-0 |
| 5 | ALU Result bit 3 | Stuck-at-1 |
| 6 | Carry Flag | Stuck-at-0 |
| 7 | Carry Flag | Stuck-at-1 |

### 4. Test Modes

| Mode | Code | Description |
|------|------|-------------|
| Functional | 00 | Normal ALU operation |
| Manual Test | 01 | User-controlled testing |
| BIST | 10 | Automatic self-test |
| Fault Inject | 11 | Testing with injected faults |

---

## Pin Configuration

### Input Pins (ui_in)

| Pin | Name | Description |
|-----|------|-------------|
| ui_in[0] | DATA_IN | Serial data input for operands |
| ui_in[1] | CTRL_BTN | Control button |
| ui_in[2] | STEP_BTN | Step button |
| ui_in[3] | MODE_SEL | Mode select MSB |
| ui_in[4] | SCAN_EN | Scan chain enable |
| ui_in[5] | SCAN_CLK | Scan chain clock |
| ui_in[6] | SCAN_IN | Scan chain data input |
| ui_in[7] | BIST_START | BIST start trigger |

### Output Pins (uo_out)

| Pin | Name | Description |
|-----|------|-------------|
| uo_out[0] | SEG_A | 7-segment segment A |
| uo_out[1] | SEG_B | 7-segment segment B |
| uo_out[2] | SEG_C | 7-segment segment C |
| uo_out[3] | SEG_D | 7-segment segment D |
| uo_out[4] | SEG_E | 7-segment segment E |
| uo_out[5] | SEG_F | 7-segment segment F |
| uo_out[6] | SEG_G | 7-segment segment G |
| uo_out[7] | OP_LED | Operation indicator LED |

### Bidirectional Pins (uio)

| Pin | Name | Description |
|-----|------|-------------|
| uio[0] | DIGIT_SEL0 | Digit select bit 0 |
| uio[1] | DIGIT_SEL1 | Digit select bit 1 |
| uio[2] | SCAN_OUT | Scan chain output |
| uio[3] | BIST_DONE | BIST completion flag |
| uio[4] | TEST_PASS | Test pass/fail |
| uio[5] | FAULT_FLAG | Fault injected |
| uio[6] | MODE_OUT0 | Current mode bit 0 |
| uio[7] | MODE_OUT1 | Current mode bit 1 |

---

## Display Interface

### 7-Segment Display Format

```
+-------+-------+-------+-------+
|  D3   |  D2   |  D1   |  D0   |
+-------+-------+-------+-------+
| Result| Result|  Op   | Flags |
| High  | Low   | Code  | ZCNO  |
+-------+-------+-------+-------+
```

### Display Examples

ADD Operation (15 + 3 = 18):

```
+-------+-------+-------+-------+
|   1   |   8   |   0   |   0   |
|       |       |  ADD  | NoFlg |
+-------+-------+-------+-------+
```

---

## How to Test

### Test Setup

Required Hardware:
- Tiny Tapeout board with iTALU chip
- 4-digit 7-segment display (common cathode)
- 2 push buttons
- DIP switches or jumpers
- LED with resistor
- Connecting wires

### Basic ALU Operation Test

Step 1: Initialize
1. Apply power
2. Assert reset (rst_n = 0)
3. Release reset (rst_n = 1)
4. Set MODE_SEL = 0 (Functional Mode)

Step 2: Load Operation
1. Press CTRL_BTN to enter operation selection
2. Serial load 3 bits via DATA_IN
3. Toggle DATA_IN for each bit
4. Press STEP_BTN to advance

Step 3: Load Operand A
1. Serial load 8 bits via DATA_IN
2. Toggle DATA_IN for each bit
3. Press STEP_BTN after each bit

Step 4: Load Operand B
1. Serial load 8 bits via DATA_IN
2. Toggle DATA_IN for each bit
3. Press STEP_BTN after each bit

Step 5: Execute
1. Press CTRL_BTN to execute operation
2. Observe result on 7-segment display
3. Check status flags

### Example Test Cases

Test Case 1: Basic Addition
- Operation: ADD (000)
- Operand A: 0x0F (15)
- Operand B: 0x03 (3)
- Expected Result: 0x12 (18)
- Expected Flags: 0000 (none)

Test Case 2: Overflow Detection
- Operation: ADD (000)
- Operand A: 0x7F (127)
- Operand B: 0x01 (1)
- Expected Result: 0x80 (128)
- Expected Flags: 1001 (Overflow + Negative)

Test Case 3: Subtraction with Borrow
- Operation: SUB (001)
- Operand A: 0x05 (5)
- Operand B: 0x0A (10)
- Expected Result: 0xFB (-5)
- Expected Flags: 0110 (Carry + Negative)

### BIST Testing

1. Cycle to BIST Mode using CTRL_BTN
2. Press CTRL_BTN again or set BIST_START = 1
3. Wait for BIST_DONE = 1
4. Check TEST_PASS for overall result
5. Use STEP_BTN to single-step through patterns

### Fault Injection Testing

1. Cycle to Fault Injection Mode
2. Load operands as in functional mode
3. Execute operation with fault injected
4. Compare result with expected value
5. Check FAULT_FLAG to verify fault detection

### Scan Chain Testing

1. Set SCAN_EN = 1
2. Apply scan clock to SCAN_CLK
3. Shift in test vectors via SCAN_IN
4. Observe SCAN_OUT for response
5. Set SCAN_EN = 0 for normal operation

---

## External Hardware

### Required Components

1. 4-digit 7-segment display (common cathode)
2. 2 push buttons with pull-down resistors (10k ohm)
3. DIP switches or jumpers for mode selection
4. LED with 330 ohm resistor for operation indicator
5. Connecting wires

### Connection Diagram

```
Tiny Tapeout Board          External Hardware
-------------------         -----------------
ui_in[0] DATA_IN     ---->  Push button or GPIO
ui_in[1] CTRL_BTN    ---->  Push button
ui_in[2] STEP_BTN    ---->  Push button
ui_in[3] MODE_SEL    ---->  DIP switch
ui_in[4] SCAN_EN     ---->  DIP switch
ui_in[5] SCAN_CLK    ---->  Clock source
ui_in[6] SCAN_IN     ---->  GPIO
ui_in[7] BIST_START  ---->  Push button

uo_out[0] SEG_A      ---->  7-seg segment A
uo_out[1] SEG_B      ---->  7-seg segment B
uo_out[2] SEG_C      ---->  7-seg segment C
uo_out[3] SEG_D      ---->  7-seg segment D
uo_out[4] SEG_E      ---->  7-seg segment E
uo_out[5] SEG_F      ---->  7-seg segment F
uo_out[6] SEG_G      ---->  7-seg segment G
uo_out[7] OP_LED     ---->  LED with 330 ohm

uio[0] DIGIT_SEL0    ---->  Digit 0 select
uio[1] DIGIT_SEL1    ---->  Digit 1 select
uio[2] SCAN_OUT      ---->  Logic analyzer
uio[3] BIST_DONE     ---->  LED
uio[4] TEST_PASS     ---->  LED
uio[5] FAULT_FLAG    ---->  LED
```

---

## License

This project is licensed under Apache-2.0.

## Author

Your Name

## Acknowledgments

- Tiny Tapeout for providing the platform
- IHP for the 180nm PDK
- Open source EDA community
