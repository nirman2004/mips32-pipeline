# MIPS32 5-Stage Pipelined Processor

> A fully functional 32-bit MIPS processor implementing a classic 5-stage pipeline in Verilog, with resolved control hazards and cycle-accurate verification

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Pipeline Stages](#pipeline-stages)
- [Hazard Handling](#hazard-handling)
- [Project Structure](#project-structure)
- [Simulation & Verification](#simulation--verification)
- [Tools Used](#tools-used)
- [Results](#results)
- [How to Run](#how-to-run)
- [Author](#author)

---

## Overview

This project implements a **5-stage MIPS32 pipelined processor** in synthesisable Verilog RTL. The processor supports a subset of the MIPS32 ISA and demonstrates key micro-architectural concepts including:

- Instruction-level parallelism via pipelining
- Control hazard resolution through branch penalty squashing
- Cycle-accurate testbench validation with internal signal probing

The design was validated by successfully executing a **Factorial Loop (7! = 5040)**, confirming correct data flow and control logic across all pipeline stages.

---

## Architecture

```
       ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
 PC ──►│    IF    │──►│    ID    │──►│    EX    │──►│   MEM    │──►│    WB    │
       │  Fetch   │   │  Decode  │   │ Execute  │   │ Memory   │   │ Write    │
       │          │   │          │   │          │   │ Access   │   │ Back     │
       └──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘
            │              │              │               │               │
         IF/ID          ID/EX          EX/MEM          MEM/WB
        Pipeline       Pipeline       Pipeline         Pipeline
        Register       Register       Register         Register
```

Each pipeline stage communicates through **interstage registers** (IF/ID, ID/EX, EX/MEM, MEM/WB), preserving instruction state across clock cycles.

---

## Pipeline Stages

| Stage | Module | Responsibility |
|-------|--------|----------------|
| **IF** — Instruction Fetch | `if_stage.v` | Fetch instruction from instruction memory using PC |
| **ID** — Instruction Decode | `id_stage.v` | Decode opcode, read register file, generate control signals |
| **EX** — Execute | `ex_stage.v` | ALU operations, branch target computation |
| **MEM** — Memory Access | `mem_stage.v` | Load/store operations on data memory |
| **WB** — Write Back | `wb_stage.v` | Write ALU result or memory data back to register file |

---

## Hazard Handling

### Control Hazards — BNEQZ Branch Resolution

The processor implements a **2-cycle branch penalty** to handle control hazards arising from the `BNEQZ` instruction. Branch outcome is determined in the EX stage, meaning two instructions fetched after a branch must be squashed if the branch is taken.

**Squashing Mechanism:**

```
Cycle N   : BNEQZ instruction enters EX stage — branch resolved as TAKEN
Cycle N+1 : IF/ID  pipeline register → cleared (NOP injected)
Cycle N+2 : ID/EX  pipeline register → cleared (NOP injected)
Cycle N+3 : Correct branch target instruction enters IF stage
```

Both **register writes** and **memory writes** are disabled on squashed instructions, preventing architectural state corruption from mispredicted paths.

```verilog
// Squash logic — disable WB on mispredicted instructions
always @(posedge clk) begin
  if (branch_taken) begin
    IF_ID_reg  <= 32'b0;  // NOP
    ID_EX_reg  <= 32'b0;  // NOP
  end
end
```

### Data Hazards

Data hazards are managed through **careful instruction scheduling** in the test programs. Full forwarding/bypassing can be added as a future enhancement.

---

## Project Structure

```
mips32-pipeline/
│
├── rtl/                        # Synthesisable Verilog source
│   ├── mips32_top.v            # Top-level processor module
│   ├── if_stage.v              # Instruction Fetch
│   ├── id_stage.v              # Instruction Decode & Register File
│   ├── ex_stage.v              # Execute (ALU)
│   ├── mem_stage.v             # Memory Access
│   ├── wb_stage.v              # Write Back
│   ├── pipeline_regs.v         # IF/ID, ID/EX, EX/MEM, MEM/WB registers
│   ├── alu.v                   # 32-bit ALU
│   ├── register_file.v         # 32×32 Register File
│   ├── instr_memory.v          # Instruction Memory (ROM)
│   └── data_memory.v           # Data Memory (RAM)
│
├── tb/                         # Testbenches
│   ├── tb_mips32_top.v         # Top-level simulation testbench
│   └── test_programs/
│       └── factorial.mem       # Factorial loop (7! = 5040) machine code
│
├── sim/                        # Simulation outputs
│   └── waveform_factorial.vcd  # GTKWave dump — factorial test
│
├── docs/
│   └── pipeline_diagram.png    # Architecture diagram
│
└── README.md
```

---

## Simulation & Verification

### Testbench Strategy — Signal Probing (Aliasing)

A key verification challenge was the limited visibility of internal pipeline registers in the waveform viewer. This was resolved using **Signal Aliasing** in the testbench:

```verilog
// Force internal pipeline register signals onto waveform
// by aliasing them to top-level wire probes
wire [31:0] probe_IFID_IR  = uut.IF_ID_IR;
wire [31:0] probe_IDEX_IR  = uut.ID_EX_IR;
wire [31:0] probe_EXMEM_IR = uut.EX_MEM_IR;
wire [31:0] probe_MEMWB_IR = uut.MEM_WB_IR;
wire [31:0] probe_IDEX_A   = uut.ID_EX_A;
wire [31:0] probe_IDEX_B   = uut.ID_EX_B;
```

This technique exposes internal register values in GTKWave without modifying the RTL, preserving synthesisability of the design.

### Factorial Loop Validation

The primary verification test executes the following algorithm in MIPS32 assembly:

```asm
# Computes 7! = 5040
# R1 = counter (7 down to 1), R2 = accumulator (result)

ADDI  R1, R0, 7       # R1 = 7
ADDI  R2, R0, 1       # R2 = 1 (accumulator seed)

LOOP:
  MUL   R2, R2, R1   # R2 = R2 * R1
  SUBI  R1, R1, 1    # R1 = R1 - 1
  BNEQZ R1, LOOP     # if R1 != 0, branch back to LOOP

# After loop: R2 = 7! = 5040
```

**Expected result:** `R2 = 0x000013B0` (5040 decimal) — confirmed cycle-accurate in simulation.

---

## Tools Used

| Tool | Purpose |
|------|---------|
| **Vivado 2023.x** | RTL simulation, synthesis, waveform analysis |
| **Verilog HDL** | Hardware description language |
| **GTKWave** | Waveform inspection (`.vcd` dump) |
| **MIPS32 ISA Reference** | Instruction set specification |

---

## Results

| Metric | Value |
|--------|-------|
| Pipeline stages | 5 (IF → ID → EX → MEM → WB) |
| Branch penalty | 2 cycles (BNEQZ TAKEN) |
| Verified test | Factorial 7! = 5040 ✓ |
| Register file | 32 × 32-bit general purpose registers |
| Instruction memory | 256 × 32-bit words |
| Data memory | 256 × 32-bit words |
| Simulation tool | Xilinx Vivado |

---

## How to Run

### Prerequisites
- Xilinx Vivado (2020.x or later) — [Download here](https://www.xilinx.com/support/download.html)
- Or: Icarus Verilog + GTKWave (free, open-source alternative)

### Using Vivado

```bash
# 1. Clone the repository
git clone https://github.com/nirman2004/mips32-pipeline.git
cd mips32-pipeline

# 2. Open Vivado and create a new project
#    Add all .v files from rtl/ as design sources
#    Add tb/tb_mips32_top.v as simulation source

# 3. Run Behavioral Simulation
#    Vivado → Flow → Run Simulation → Run Behavioral Simulation

# 4. In the Tcl console, run:
run 500ns

# 5. Observe R2 = 0x000013B0 (5040) after the loop completes
```

### Using Icarus Verilog (open-source)

```bash
# Compile
iverilog -o mips32_sim rtl/*.v tb/tb_mips32_top.v

# Run simulation
vvp mips32_sim

# View waveform
gtkwave sim/waveform_factorial.vcd
```

---

## Future Enhancements

- [ ] Full data forwarding / bypassing unit (eliminate data hazard stalls)
- [ ] Branch prediction unit (static or 2-bit saturating counter)
- [ ] Extended ISA support (LW, SW, JAL, JR)
- [ ] FPGA synthesis and hardware demo on Basys 3 / Nexys A7
- [ ] Cache memory integration (direct-mapped instruction cache)

---

## Author

**Nirman Dey**
B.Tech Electronics & Communication Engineering, JGEC (2027)
Research Intern — NIT Durgapur | Samsung ISWDP Shortlist (Cohort 6)

[![LinkedIn](https://img.shields.io/badge/LinkedIn-nirman--dey-blue)](https://linkedin.com/in/nirman-dey-554140238)
[![GitHub](https://img.shields.io/badge/GitHub-nirman2004-black)](https://github.com/nirman2004)

---

*If you find this project useful, please consider giving it a ⭐ — it helps with visibility!*
