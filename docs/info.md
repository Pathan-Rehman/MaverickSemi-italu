Here's the updated `README.md` for your iTALU project:

```markdown
<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

# iTALU: Interactive Testable Arithmetic Logic Unit

## How it works

iTALU is an 8-bit Arithmetic Logic Unit (ALU) with comprehensive Design-for-Testability (DFT) features, designed for educational demonstration and practical testing applications.

### Functional Overview

The ALU supports 8 operations:
- **ADD** (000): Addition with carry and overflow detection
- **SUB** (001): Subtraction with borrow and overflow detection
- **AND** (010): Bitwise AND
- **OR** (011): Bitwise OR
- **XOR** (100): Bitwise XOR
- **NOT** (101): Bitwise NOT (1's complement)
- **SHIFT** (110): Shift left by 1 bit
- **COMPARE** (111): Comparison (equal, greater, less)

The ALU generates 4 status flags:
- **Zero Flag (Z)**: Set when result is 0x00
- **Carry Flag (C)**: Set on carry out or borrow
- **Negative Flag (N)**: Set when MSB of result is 1
- **Overflow Flag (O)**: Set on signed arithmetic overflow

### DFT Features

The design integrates multiple DFT techniques:

1. **Scan Chain**: 
   - 32-bit scan chain covering all registers
   - Controlled by SCAN_EN and SCAN_CLK
   - Serial input/output for test vectors

2. **Built-In Self-Test (BIST)**:
   - 8-bit LFSR pattern generator
   - 8-bit MISR response compactor
   - 256 test patterns
   - Automatic pass/fail detection

3. **Fault Injection**:
   - 8 programmable fault locations
   - Stuck-at-0 and stuck-at-1 fault models
   - User-controlled fault activation

4. **Boundary Scan**:
   - Test access to all I/O pins
   - Mode selection for functional/test operation

### User Interaction Modes

The design operates in 4 user-selectable modes:

1. **Functional Mode** (00): Normal ALU operation
2. **Manual Test Mode** (01): User-controlled testing with specific vectors
3. **BIST Mode** (10): Automatic self-test with LFSR/MISR
4. **Fault Injection Mode** (11): Testing with injected faults

### Display System

The design outputs to a 4-digit 7-segment display:
- **Digits 0-1**: ALU result (hexadecimal)
- **Digit 2**: Operation code (0-7)
- **Digit 3**: Status flags (ZCNO)

## How to test

### Basic ALU Operation

1. Apply power and reset (rst_n low then high)
2. Set MODE_SEL = 0 (Functional Mode)
3. Press CTRL_BTN to cycle to operation selection
4. Serial load 3-bit operation code via DATA_IN
5. Serial load 8-bit operand A via DATA_IN
6. Serial load 8-bit operand B via DATA_IN
7. Press CTRL_BTN to execute
8. Observe result on 7-segment display

### Manual Test Mode

1. Set MODE_SEL = 1, then press CTRL_BTN to select Manual Test Mode
2. Load specific test vectors using DATA_IN
3. Execute and compare with expected results
4. Use STEP_BTN to step through operations
5. Check TEST_PASS output for pass/fail status

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
6. Monitor fault coverage via test vector count

### Scan Chain Testing

1. Set SCAN_EN = 1
2. Apply scan clock to SCAN_CLK
3. Shift in test vectors via SCAN_IN
4. Observe SCAN_OUT for response
5. Set SCAN_EN = 0 for normal operation

### Example Test Sequence

```
1. Reset: rst_n = 0, then 1
2. Mode: Functional (MODE_SEL = 0)
3. Load operation: 000 (ADD)
4. Load operand A: 0x0F (15)
5. Load operand B: 0x03 (3)
6. Execute: Press CTRL_BTN
7. Expected display: 0x12 (18)
8. Flags: 0000 (no flags set)
```

### Fault Injection Example

```
1. Mode: Fault Injection (cycle with CTRL_BTN)
2. Load operation: 000 (ADD)
3. Load operand A: 0x05 (5)
4. Load operand B: 0x03 (3)
5. Execute with fault at bit 0
6. Expected: 0x08 (8), but gets 0x09 (9)
7. FAULT_FLAG = 1 indicates fault detected
```

## External hardware

### Required Hardware

1. **7-Segment Display** (4-digit common cathode)
   - Connected to uo_out[6:0] for segments A-G
   - Connected to uio[1:0] for digit selection
   - Current limiting resistors (330Ω) recommended

2. **Push Buttons** (2x)
   - Control button connected to ui_in[1]
   - Step button connected to ui_in[2]
   - Pull-down resistors (10kΩ)

3. **DIP Switch or Jumpers** (8x)
   - Mode selection to ui_in[3]
   - Scan control to ui_in[4:6]
   - BIST start to ui_in[7]
   - Optional: Data input to ui_in[0]

4. **LED** (1x)
   - Operation indicator to uo_out[7]
   - Current limiting resistor (330Ω)

### Optional Hardware

1. **Logic Analyzer**
   - Monitor scan chain outputs
   - Verify timing
   - Debug test sequences

2. **Function Generator**
   - Provide test clock signals
   - Generate input patterns

3. **Arduino/Raspberry Pi**
   - Automate test sequences
   - Serial data input
   - Read test results

### Connection Diagram

```
Tiny Tapeout Board     External Hardware
─────────────────     ─────────────────
ui_in[0] (DATA_IN) ── Push button or GPIO
ui_in[1] (CTRL_BTN)── Push button
ui_in[2] (STEP_BTN)── Push button
ui_in[3] (MODE_SEL)── DIP switch
ui_in[4] (SCAN_EN) ── DIP switch
ui_in[5] (SCAN_CLK)── Clock source or GPIO
ui_in[6] (SCAN_IN) ── GPIO
ui_in[7] (BIST_START)─ Push button or GPIO

uo_out[0] (SEG_A) ── 7-segment display segment A
uo_out[1] (SEG_B) ── 7-segment display segment B
uo_out[2] (SEG_C) ── 7-segment display segment C
uo_out[3] (SEG_D) ── 7-segment display segment D
uo_out[4] (SEG_E) ── 7-segment display segment E
uo_out[5] (SEG_F) ── 7-segment display segment F
uo_out[6] (SEG_G) ── 7-segment display segment G
uo_out[7] (OP_LED)── LED with resistor

uio[0] (DIGIT_SEL0)─ 7-segment digit 0 select
uio[1] (DIGIT_SEL1)─ 7-segment digit 1 select
uio[2] (SCAN_OUT) ── Logic analyzer or GPIO
uio[3] (BIST_DONE)── LED or GPIO
uio[4] (TEST_PASS)── LED or GPIO
uio[5] (FAULT_FLAG)─ LED or GPIO
uio[6] (MODE_OUT0)── LED or GPIO
uio[7] (MODE_OUT1)── LED or GPIO
```

### Power Requirements

- VDD: 1.8V (IHP 180nm)
- Maximum current: < 10 mA (excluding external components)
- External pull-up/pull-down resistors as needed
```

This README provides comprehensive documentation for your iTALU project including:
- Detailed functional description
- Complete testing instructions
- Hardware requirements
- Connection diagrams
- Example test sequences
