`timescale 1ns / 1ps

// =====================================================================================================
// Program Counter - registrador que armazena o endereço da instrução atual
// =====================================================================================================
module pc (
    input        clk,
    input        reset,
    input  [31:0] next_pc,
    output reg [31:0] current_pc
);
    always @(posedge clk or posedge reset) begin
        if (reset)
            current_pc <= 32'b0;
        else
            current_pc <= next_pc;
    end
endmodule

// ============================================================
// Memória de Instruções - Lê o ficheiro de texto binário
// ============================================================
module instr_mem (
    input  [31:0] addr,
    output [31:0] instruction
);
    reg [31:0] mem [0:63]; // Capacidade para 64 instruções

    initial begin
        // Carrega o ficheiro instrucoes.bin para a memória
        $readmemb("instrucoes.bin", mem);
    end

    // Converte endereço de byte para índice da memória (divisão por 4)
    assign instruction = mem[addr >> 2];
endmodule

// ===================================================================================================================
// Banco de Registradores - recebem o os valores dos registradores, e o registrador onde guardar uma informação 
// ===================================================================================================================

module reg_file (
    input        clk,
    input        reg_write,
    input  [4:0] rs1, rs2, rd,
    input  [31:0] write_data,
    output [31:0] read_data1,
    output [31:0] read_data2
);
    reg [31:0] regs [0:31];
    integer i, file, status;

    initial begin
        for (i = 0; i < 32; i = i + 1) regs[i] = 0;

        file = $fopen("valores.txt", "r");
        if (file != 0) begin
            for (i = 1; i < 32; i = i + 1) begin
                if (!$feof(file)) begin
                    status = $fscanf(file, "%d\n", regs[i]);
                end
            end
            $fclose(file);
        end
    end

    assign read_data1 = (rs1 == 0) ? 32'b0 : regs[rs1];
    assign read_data2 = (rs2 == 0) ? 32'b0 : regs[rs2];

    always @(posedge clk) begin
        if (reg_write && rd != 0)
            regs[rd] <= write_data;
    end
endmodule

// ===================================================================================================================
// Função que adquire o imediato da operação e expende ele para 64 bits
// ===================================================================================================================

module imm_gen (
    input  [31:0] instruction,
    output reg [31:0] imm_ext
);
    wire [6:0] opcode;
    assign opcode = instruction[6:0];
    always @(*) begin
        case (opcode)
            7'b0000011, 7'b0010011: imm_ext = {{20{instruction[31]}}, instruction[31:20]};
            7'b0100011: imm_ext = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            7'b1100011: imm_ext = {{19{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
            default:    imm_ext = 32'b0;
        endcase
    end
endmodule

// =====================================================================================================
// Controle - apartir da leitura do opcode da intrução, o programa gera sinais de controle
// =====================================================================================================

module control (
    input  [6:0] opcode,
    output reg   reg_write, mem_read, mem_write, alu_src, mem_to_reg, branch,
    output reg [1:0] alu_op
);
    always @(*) begin
        case (opcode)
            7'b0000011: {reg_write, mem_read, mem_write, alu_src, mem_to_reg, branch, alu_op} = 8'b1_1_0_1_1_0_00; // lw
            7'b0100011: {reg_write, mem_read, mem_write, alu_src, mem_to_reg, branch, alu_op} = 8'b0_0_1_1_0_0_00; // sw
            7'b0110011: {reg_write, mem_read, mem_write, alu_src, mem_to_reg, branch, alu_op} = 8'b1_0_0_0_0_0_10; // R-type
            7'b0010011: {reg_write, mem_read, mem_write, alu_src, mem_to_reg, branch, alu_op} = 8'b1_0_0_1_0_0_11; // addi
            7'b1100011: {reg_write, mem_read, mem_write, alu_src, mem_to_reg, branch, alu_op} = 8'b0_0_0_0_0_1_01; // beq
            default:    {reg_write, mem_read, mem_write, alu_src, mem_to_reg, branch, alu_op} = 8'b0_0_0_0_0_0_00;
        endcase
    end
endmodule

// =====================================================================================================
// ALU Control - a partir do alu_op, funct3 e funct7 gera o sinal de controle da ALU
// =====================================================================================================
module alu_control (
    input  [1:0] alu_op,
    input  [2:0] funct3,
    input  [6:0] funct7,
    output reg [3:0] alu_ctrl
);
    always @(*) begin
        case (alu_op)
            2'b00: alu_ctrl = 4'b0010; // soma (lw/sw)
            2'b01: alu_ctrl = 4'b0110; // subtração (beq)
            2'b11: alu_ctrl = 4'b0010; // soma (addi)
            2'b10: begin // R-type — olha funct3/funct7
                case (funct3)
                    3'b000: alu_ctrl = (funct7 == 7'b0100000) ? 4'b0110 : 4'b0010; // sub : add
                    3'b111: alu_ctrl = 4'b0000; // and
                    3'b110: alu_ctrl = 4'b0001; // or
                    3'b100: alu_ctrl = 4'b0011; // xor
                    3'b001: alu_ctrl = 4'b0100; // sll
                    3'b101: alu_ctrl = 4'b0101; // srl
                    default: alu_ctrl = 4'b0010;
                endcase
            end
            default: alu_ctrl = 4'b0010;
        endcase
    end
endmodule

// =====================================================================================================
// Mux ALU Src - seleciona entre read_data2 e imm_ext como segunda entrada da ALU
// =====================================================================================================
module mux_alu_src (
    input  [31:0] read_data2,
    input  [31:0] imm_ext,
    input         alu_src,
    output [31:0] b
);
    assign b = (alu_src) ? imm_ext : read_data2;
endmodule

// =====================================================================================================
// ALU - executa a operação determinada pelo alu_ctrl
// =====================================================================================================
module alu (
    input  [31:0] a,
    input  [31:0] b,
    input  [3:0]  alu_ctrl,
    output reg [31:0] result,
    output zero
);
    always @(*) begin
        case (alu_ctrl)
            4'b0000: result = a & b;       // and
            4'b0001: result = a | b;       // or
            4'b0010: result = a + b;       // add
            4'b0011: result = a ^ b;       // xor
            4'b0100: result = a << b[4:0]; // sll
            4'b0101: result = a >> b[4:0]; // srl
            4'b0110: result = a - b;       // sub
            default: result = 32'b0;
        endcase
    end

    assign zero = (result == 32'b0);
endmodule

// =====================================================================================================
// Memória de Dados - lê e escreve dados conforme mem_read e mem_write
// =====================================================================================================
module data_mem (
    input        clk,
    input        mem_read,
    input        mem_write,
    input  [31:0] addr,
    input  [31:0] write_data,
    output reg [31:0] read_data
);
    reg [31:0] mem [0:63];
    always @(posedge clk) begin
        if (mem_write)
            mem[addr >> 2] <= write_data;
    end
    always @(*) begin
        if (mem_read)
            read_data = mem[addr >> 2];
        else
            read_data = 32'b0;
    end
endmodule

// =====================================================================================================
// Mux Mem To Reg - seleciona entre resultado da ALU ou dado lido da memória para escrever no registrador
// =====================================================================================================
module mux_mem_to_reg (
    input  [31:0] alu_result,
    input  [31:0] mem_read_data,
    input         mem_to_reg,
    output [31:0] write_data
);
    assign write_data = (mem_to_reg) ? mem_read_data : alu_result;
endmodule

// =====================================================================================================
// Branch Control - gera o sinal pcsrc a partir de branch AND zero
// =====================================================================================================
module branch_ctrl (
    input  branch,
    input  zero,
    output pcsrc
);
    assign pcsrc = branch & zero;
endmodule

// =====================================================================================================
// Mux PC Src - seleciona entre PC+4 ou PC+imm_ext (branch)
// =====================================================================================================
module mux_pcsrc (
    input  [31:0] pc_plus4,
    input  [31:0] pc_branch,
    input         pcsrc,
    output [31:0] next_pc
);
    assign next_pc = (pcsrc) ? pc_branch : pc_plus4;
endmodule

// =====================================================================================================
// PC + 4 - incrementa o PC em 4 para a próxima instrução
// =====================================================================================================
module pc_plus4 (
    input  [31:0] current_pc,
    output [31:0] pc_plus4
);
    assign pc_plus4 = current_pc + 4;
endmodule

// =====================================================================================================AV
// PC Branch - calcula o endereço de desvio PC + imm_ext
// =====================================================================================================
module pc_branch (
    input  [31:0] current_pc,
    input  [31:0] imm_ext,
    output [31:0] pc_branch
);
    assign pc_branch = current_pc + imm_ext;
endmodule
