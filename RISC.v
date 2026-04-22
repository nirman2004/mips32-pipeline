`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////
// Module   : pipe_MIPS32
// Author   : Nirman Dey (github.com/nirman2004)
// College  : JGEC — B.Tech ECE 2027
// Desc     : 5-stage pipelined MIPS32 processor (IF/ID/EX/MEM/WB)
//            Two-phase clocking: clk1 drives even stages,
//            clk2 drives odd stages.
//            Supports: ADD, SUB, AND, OR, SLT, MUL, HLT,
//                      LW, SW, ADDI, SUBI, SLTI, BNEQZ, BEQZ
//////////////////////////////////////////////////////////////////

module pipe_MIPS32 (clk1, clk2);

    input clk1, clk2;   // Two-phase clock

    // ----------------------------------------------------------------
    // Pipeline registers
    // ----------------------------------------------------------------
    reg [31:0] PC, IF_ID_IR, IF_ID_NPC;
    reg [31:0] ID_EX_IR, ID_EX_NPC, ID_EX_A, ID_EX_B, ID_EX_Imm;
    reg  [2:0] ID_EX_type, EX_MEM_type, MEM_WB_type;
    reg [31:0] EX_MEM_IR, EX_MEM_ALUOut, EX_MEM_B;
    reg        EX_MEM_cond;
    reg [31:0] MEM_WB_IR, MEM_WB_ALUOut, MEM_WB_LMD;

    // ----------------------------------------------------------------
    // Architectural state
    // ----------------------------------------------------------------
    reg [31:0] Reg  [0:31];    // Register Bank  (32 x 32)
    reg [31:0] Mem  [0:1023];  // Unified Memory (1024 x 32)

    // ----------------------------------------------------------------
    // Opcode parameters  (6-bit opcode field)
    // ----------------------------------------------------------------
    parameter ADD   = 6'b000000,
              SUB   = 6'b000001,
              AND   = 6'b000010,
              OR    = 6'b000011,
              SLT   = 6'b000100,
              MUL   = 6'b000101,
              HLT   = 6'b111111,
              LW    = 6'b001000,
              SW    = 6'b001001,
              ADDI  = 6'b001010,
              SUBI  = 6'b001011,
              SLTI  = 6'b001100,
              BNEQZ = 6'b001101,
              BEQZ  = 6'b001110;

    // ----------------------------------------------------------------
    // Instruction-type encoding  (3-bit type field)
    // ----------------------------------------------------------------
    parameter RR_ALU = 3'b000,   // Register-Register ALU
              RM_ALU = 3'b001,   // Register-Immediate ALU
              LOAD   = 3'b010,
              STORE  = 3'b011,
              BRANCH = 3'b100,
              HALT   = 3'b101;

    // ----------------------------------------------------------------
    // Halt flag
    // ----------------------------------------------------------------
    reg HALTED;          // Set when HLT reaches WB stage
    reg TAKEN_BRANCH;    // Squash flag — asserted on taken branch

    // ================================================================
    // STAGE 1 — IF : Instruction Fetch  (clk1)
    // ================================================================
    always @(posedge clk1) begin
        if (HALTED == 0) begin
            if (((EX_MEM_IR[31:26] == BNEQZ) && (EX_MEM_cond == 1)) ||
                ((EX_MEM_IR[31:26] == BEQZ)  && (EX_MEM_cond == 0))) begin
                // Branch taken — redirect PC; squash IF/ID
                IF_ID_IR    <= #2 32'hxxxxxxxx;  // NOP / bubble
                IF_ID_NPC   <= #2 EX_MEM_ALUOut;
                PC          <= #2 EX_MEM_ALUOut + 1;
                TAKEN_BRANCH <= #2 1'b1;
            end else begin
                IF_ID_IR    <= #2 Mem[PC];
                IF_ID_NPC   <= #2 PC + 1;
                PC          <= #2 PC + 1;
                TAKEN_BRANCH <= #2 1'b0;
            end
        end
    end

    // ================================================================
    // STAGE 2 — ID : Instruction Decode + Register Fetch  (clk2)
    // ================================================================
    always @(posedge clk2) begin
        if (HALTED == 0) begin
            // Register read (before possible WB write — slight RAW risk
            // handled by instruction scheduling in test programs)
            ID_EX_A   <= #2 Reg[IF_ID_IR[25:21]];  // rs
            ID_EX_B   <= #2 Reg[IF_ID_IR[20:16]];  // rt
            ID_EX_NPC <= #2 IF_ID_NPC;
            ID_EX_IR  <= #2 IF_ID_IR;
            // Sign-extend lower 16 bits
            ID_EX_Imm <= #2 {{16{IF_ID_IR[15]}}, IF_ID_IR[15:0]};

            // Decode instruction type
            case (IF_ID_IR[31:26])
                ADD, SUB, AND, OR, SLT, MUL :
                    ID_EX_type <= #2 RR_ALU;
                ADDI, SUBI, SLTI :
                    ID_EX_type <= #2 RM_ALU;
                LW  : ID_EX_type <= #2 LOAD;
                SW  : ID_EX_type <= #2 STORE;
                BNEQZ, BEQZ :
                    ID_EX_type <= #2 BRANCH;
                HLT : ID_EX_type <= #2 HALT;
                default : ID_EX_type <= #2 3'bxxx;
            endcase
        end
    end

    // ================================================================
    // STAGE 3 — EX : Execute  (clk1)
    // ================================================================
    always @(posedge clk1) begin
        if (HALTED == 0) begin
            EX_MEM_type <= #2 ID_EX_type;
            EX_MEM_IR   <= #2 ID_EX_IR;
            TAKEN_BRANCH <= #2 0;   // clear squash after one cycle

            case (ID_EX_type)

                RR_ALU : begin
                    case (ID_EX_IR[31:26])
                        ADD  : EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_B;
                        SUB  : EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_B;
                        AND  : EX_MEM_ALUOut <= #2 ID_EX_A & ID_EX_B;
                        OR   : EX_MEM_ALUOut <= #2 ID_EX_A | ID_EX_B;
                        SLT  : EX_MEM_ALUOut <= #2 (ID_EX_A < ID_EX_B) ? 1 : 0;
                        MUL  : EX_MEM_ALUOut <= #2 ID_EX_A * ID_EX_B;
                        default : EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
                    endcase
                    EX_MEM_cond <= #2 0;
                end

                RM_ALU : begin
                    case (ID_EX_IR[31:26])
                        ADDI : EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
                        SUBI : EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_Imm;
                        SLTI : EX_MEM_ALUOut <= #2 (ID_EX_A < ID_EX_Imm) ? 1 : 0;
                        default : EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
                    endcase
                    EX_MEM_cond <= #2 0;
                end

                LOAD, STORE : begin
                    // Effective address = base + sign-extended offset
                    EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
                    EX_MEM_B      <= #2 ID_EX_B;   // store data
                    EX_MEM_cond   <= #2 0;
                end

                BRANCH : begin
                    // Branch target = NPC + immediate offset
                    EX_MEM_ALUOut <= #2 ID_EX_NPC + ID_EX_Imm;
                    // Condition: rs == 0 ?
                    EX_MEM_cond   <= #2 (ID_EX_A == 0);
                end

            endcase
        end
    end

    // ================================================================
    // STAGE 4 — MEM : Memory Access  (clk2)
    // ================================================================
    always @(posedge clk2) begin
        if (HALTED == 0) begin
            MEM_WB_type <= #2 EX_MEM_type;
            MEM_WB_IR   <= #2 EX_MEM_IR;

            case (EX_MEM_type)

                RR_ALU, RM_ALU : begin
                    MEM_WB_ALUOut <= #2 EX_MEM_ALUOut;
                end

                LOAD : begin
                    MEM_WB_LMD    <= #2 Mem[EX_MEM_ALUOut];
                    MEM_WB_ALUOut <= #2 EX_MEM_ALUOut;
                end

                STORE : begin
                    // Commit store only if branch was NOT taken
                    if (TAKEN_BRANCH == 0)
                        Mem[EX_MEM_ALUOut] <= #2 EX_MEM_B;
                end

            endcase
        end
    end

    // ================================================================
    // STAGE 5 — WB : Write Back  (clk1)
    // ================================================================
    always @(posedge clk1) begin
        if (TAKEN_BRANCH == 0) begin   // Squash WB on mispredicted path
            case (MEM_WB_type)

                RR_ALU : begin
                    // Write to rd  [15:11]
                    Reg[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUOut;
                end

                RM_ALU : begin
                    // Write to rt  [20:16]
                    Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_ALUOut;
                end

                LOAD : begin
                    // Write loaded data to rt  [20:16]
                    Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_LMD;
                end

                HALT : begin
                    HALTED <= #2 1'b1;
                end

            endcase
        end
    end

endmodule
