`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////
// Module   : test_mips32
// Author   : Nirman Dey (github.com/nirman2004)
// Desc     : Testbench for pipe_MIPS32
//            - Generates two-phase clock (clk1 / clk2)
//            - Signal probing (aliasing) for internal visibility
//            - Loads factorial program: computes 7! = 5040
//            - Monitors R2 each cycle and dumps VCD waveform
//////////////////////////////////////////////////////////////////

module test_mips32;

    reg  clk1, clk2;
    integer k;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    pipe_MIPS32 mips (clk1, clk2);

    // ================================================================
    // Signal Probing (Aliasing)
    // Forces internal pipeline registers onto the waveform
    // without modifying the RTL — preserves synthesisability
    // ================================================================
    wire [31:0] w_PC           = mips.PC;
    wire [31:0] w_IF_ID_IR     = mips.IF_ID_IR;
    wire [31:0] w_IF_ID_NPC    = mips.IF_ID_NPC;

    wire [31:0] w_ID_EX_IR     = mips.ID_EX_IR;
    wire [31:0] w_ID_EX_A      = mips.ID_EX_A;
    wire [31:0] w_ID_EX_B      = mips.ID_EX_B;
    wire [31:0] w_ID_EX_Imm    = mips.ID_EX_Imm;
    wire  [2:0] w_ID_EX_type   = mips.ID_EX_type;

    wire [31:0] w_EX_MEM_IR    = mips.EX_MEM_IR;
    wire [31:0] w_EX_MEM_ALUOut= mips.EX_MEM_ALUOut;
    wire [31:0] w_EX_MEM_B     = mips.EX_MEM_B;
    wire        w_EX_MEM_cond  = mips.EX_MEM_cond;
    wire  [2:0] w_EX_MEM_type  = mips.EX_MEM_type;

    wire [31:0] w_MEM_WB_IR    = mips.MEM_WB_IR;
    wire [31:0] w_MEM_WB_ALUOut= mips.MEM_WB_ALUOut;
    wire [31:0] w_MEM_WB_LMD   = mips.MEM_WB_LMD;
    wire  [2:0] w_MEM_WB_type  = mips.MEM_WB_type;

    wire        HALTED         = mips.HALTED;
    wire        TAKEN_BRANCH   = mips.TAKEN_BRANCH;

    // ================================================================
    // Two-phase clock generation
    //   clk1: period = 20ns (HIGH 0–10ns, LOW 10–20ns)
    //   clk2: period = 20ns, phase-shifted by 10ns
    // ================================================================
    initial begin
        clk1 = 0; clk2 = 0;
    end

    always #5  clk1 = ~clk1;   // clk1 toggles every 5ns → 10ns half-period
    always #5  clk2 = ~clk2;   // clk2 toggled with initial phase offset below

    initial begin
        // Phase shift clk2 by half a period (5ns) relative to clk1
        #5;
        forever #5 clk2 = ~clk2;
    end

    // ================================================================
    // Load test program — Factorial 7! = 5040
    //
    // Register usage:
    //   R1 = counter  (initialised to 7, decrements to 0)
    //   R2 = accumulator (initialised to 1, holds result)
    //
    // MIPS32 instruction encoding used here:
    //   ADDI  rt, rs, imm  → [opcode|rs|rt|imm]
    //   MUL   rd, rs, rt   → [opcode|rs|rt|rd|0]
    //   SUBI  rt, rs, imm  → [opcode|rs|rt|imm]
    //   BNEQZ rs, offset   → [opcode|rs|00|offset]
    //   HLT                → [opcode|0|0|0]
    //
    // Assembled instruction memory image:
    //   Addr 0 : ADDI  R1, R0, 1      → init R1 = 1 (will count up) 
    //            or use the sequence below which counts DOWN from 7
    // ================================================================
    initial begin
        // Initialise all registers to 0
        for (k = 0; k < 32; k = k + 1)
            mips.Reg[k] = 32'b0;

        // ----------------------------------------------------------------
        // Factorial program (7! = 5040) — counting DOWN
        //
        // Assembly:
        //   [0] ADDI  R1, R0, 7      ; R1 = 7   (loop counter)
        //   [1] ADDI  R2, R0, 1      ; R2 = 1   (accumulator)
        //   [2] MUL   R2, R2, R1     ; R2 = R2 * R1
        //   [3] SUBI  R1, R1, 1      ; R1 = R1 - 1
        //   [4] BNEQZ R1, -3         ; if R1 != 0, branch to addr 2
        //   [5] HLT                  ; stop
        //
        // Instruction encoding  [31:26]=opcode  [25:21]=rs  [20:16]=rt  [15:0]=imm/rd
        //   ADDI  = 6'b001010  SUBI  = 6'b001011
        //   MUL   = 6'b000101  BNEQZ = 6'b001101  HLT = 6'b111111
        // ----------------------------------------------------------------

        // [0] ADDI R1, R0, 7    → opcode=001010 rs=00000 rt=00001 imm=0000000000000111
        mips.Mem[0]  = 32'h2821_0007;
        //  28 = 0010 1000  → [31:26]=001010(ADDI) [25:21]=00000(R0)
        //  21 = 0010 0001  → [20:16]=00001(R1)
        //  0007           → immediate = 7

        // [1] ADDI R2, R0, 1    → opcode=001010 rs=00000 rt=00010 imm=0000000000000001
        mips.Mem[1]  = 32'h2842_0001;

        // [2] MUL R2, R2, R1    → opcode=000101 rs=00010 rt=00001 rd=00010 unused=00000
        //     [31:26]=000101 [25:21]=00010 [20:16]=00001 [15:11]=00010 [10:0]=0
        mips.Mem[2]  = 32'h1441_1000;

        // [3] SUBI R1, R1, 1    → opcode=001011 rs=00001 rt=00001 imm=0000000000000001
        mips.Mem[3]  = 32'h2C21_0001;

        // [4] BNEQZ R1, -3      → opcode=001101 rs=00001 rt=00000 offset=FFFD (-3 in 2's comp)
        //     branch to Mem[2] = current NPC(5) + (-3) = 2  ✓
        mips.Mem[4]  = 32'h3420_FFFD;

        // [5] HLT               → opcode=111111 rest=0
        mips.Mem[5]  = 32'hFC00_0000;

        // Initialise PC and control flags
        mips.PC           = 32'b0;
        mips.HALTED       = 1'b0;
        mips.TAKEN_BRANCH = 1'b0;

        // ----------------------------------------------------------------
        // VCD dump for GTKWave
        // ----------------------------------------------------------------
        $dumpfile("mips32_factorial.vcd");
        $dumpvars(0, test_mips32);

        // ----------------------------------------------------------------
        // Run simulation and monitor R2 each clock edge
        // ----------------------------------------------------------------
        #1000;  // run 1000ns — sufficient for 7! computation
        $finish;
    end

    // Monitor accumulator register R2 every positive clk1 edge
    always @(posedge clk1) begin
        #1;  // small delay to let WB settle
        $display("R2: %4d   | PC=%0d | HALTED=%b", mips.Reg[2], mips.PC, mips.HALTED);
    end

endmodule
