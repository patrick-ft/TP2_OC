`timescale 1ns / 1ps

// ===================================================================================================================
// Decodificador Decimal de 7 Segmentos (Apenas números de 0 a 9 - Anodo Comum)
// ===================================================================================================================
module dec7seg_decimal (
    input      [3:0] digito, 
    output reg [6:0] seg    
);
    always @(*) begin
        case (digito)
            4'd0:    seg = 7'b1000000; 
            4'd1:    seg = 7'b1111001; 
            4'd2:    seg = 7'b0100100; 
            4'd3:    seg = 7'b0110000; 
            4'd4:    seg = 7'b0011001; 
            4'd5:    seg = 7'b0010010; 
            4'd6:    seg = 7'b0000010; 
            4'd7:    seg = 7'b1111000; 
            4'd8:    seg = 7'b0000000; 
            4'd9:    seg = 7'b0010000; 
            default: seg = 7'b1111111; 
        endcase
    end
endmodule


// ===================================================================================================================
// Program Counter - Registrador que armazena o endereço da instrução atual (Borda de Descida)
// ===================================================================================================================
module pc (
    input        clk,
    input        reset,
    input        stop,       // Sinal que congela a CPU quando acaba o programa
    input  [31:0] next_pc,
    output reg [31:0] current_pc
);
    always @(negedge clk or negedge reset) begin
        if (!reset)          
            current_pc <= 32'b0;
        else if (!stop)      // Só avança para a próxima instrução se NÃO estiver em Stop
            current_pc <= next_pc;
    end
endmodule


// ===================================================================================================================
// Memória de Instruções - ROM Inicializada Manualmente para Síntese
// ===================================================================================================================
module instr_mem (
    input  [31:0] addr,
    output [31:0] instruction 
);
    reg [31:0] mem [0:63]; // Capacidade mantida em 64 instruções conforme solicitado
    integer i;

    initial begin
        // 1. Zera todas as 64 posições para criar a área de 'stop' segura
        for (i = 0; i < 64; i = i + 1) mem[i] = 32'b0;

        // 2. Insere as instruções de teste do GRUPO 06 (lw, sw, sub, xor, addi, srl, beq)
        mem[0] = 32'b00000000000000000010000010000011; // 00: lw x1, 0(x0)  
        mem[1] = 32'b00000000010000000010000100000011; // 01: lw x2, 4(x0)  
        mem[2] = 32'b01000000001000001000001110110011; // 02: sub x7, x1, x2
        mem[3] = 32'b00000000011100010100010000110011; // 03: xor x8, x2, x7
        mem[4] = 32'b00000000101001000000010010010011; // 04: addi x9, x8, 10
        mem[5] = 32'b00000000001001001101010100110011; // 05: srl x10, x9, x2
        mem[6] = 32'b00000000101000000010100000100011; // 06: sw x10, 16(x0)
        mem[7] = 32'b00000000000100001000010001100011; // 07: beq x1, x1, 8  (Pula 2 instruções)
        
        mem[8] = 32'b00000110001100000000010110010011; // 08: addi x11, x0, 99 (DEVE SER PULADA)
        mem[9] = 32'b00000011011100000000011000010011; // 09: addi x12, x0, 55 (EXECUTADA APÓS O SALTO)
        
        // A partir do índice 10, a memória está preenchida com zeros, ativando o Halt automaticamente.
    end

    assign instruction = mem[addr >> 2];
endmodule


// ===================================================================================================================
// Banco de Registradores 
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
    integer i;

    initial begin
        // Na placa, não lemos txt de registradores. Começamos com zeros perfeitos.
        for (i = 0; i < 32; i = i + 1) regs[i] = 32'b0;
    end

    assign read_data1 = (rs1 == 0) ? 32'b0 : regs[rs1];
    assign read_data2 = (rs2 == 0) ? 32'b0 : regs[rs2];
    
    always @(negedge clk) begin
        if (reg_write && rd != 0)
            regs[rd] <= write_data;
    end
endmodule


// ===================================================================================================================
// Gerador de Imediato
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
            7'b0100011:             imm_ext = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            7'b1100011:             imm_ext = {{19{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
            default:                imm_ext = 32'b0;
        endcase
    end
endmodule


// ===================================================================================================================
// Controle
// ===================================================================================================================
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


// ===================================================================================================================
// ALU Control
// ===================================================================================================================
module alu_control (
    input  [1:0] alu_op,
    input  [2:0] funct3,
    input  [6:0] funct7,
    output reg [3:0] alu_ctrl
);
    always @(*) begin
        case (alu_op)
            2'b00: alu_ctrl = 4'b0010; 
            2'b01: alu_ctrl = 4'b0110; 
            2'b11: alu_ctrl = 4'b0010; 
            2'b10: begin 
                case (funct3)
                    3'b000:  alu_ctrl = (funct7 == 7'b0100000) ? 4'b0110 : 4'b0010;
                    3'b111:  alu_ctrl = 4'b0000;
                    3'b110:  alu_ctrl = 4'b0001;
                    3'b100:  alu_ctrl = 4'b0011;
                    3'b001:  alu_ctrl = 4'b0100;
                    3'b101:  alu_ctrl = 4'b0101;
                    default: alu_ctrl = 4'b0010;
                endcase
            end
            default: alu_ctrl = 4'b0010;
        endcase
    end
endmodule


// ===================================================================================================================
// Mux ALU Src
// ===================================================================================================================
module mux_alu_src (
    input  [31:0] read_data2,
    input  [31:0] imm_ext,
    input         alu_src,
    output [31:0] b
);
    assign b = (alu_src) ? imm_ext : read_data2;
endmodule


// ===================================================================================================================
// ALU
// ===================================================================================================================
module alu (
    input  [31:0] a,
    input  [31:0] b,
    input  [3:0]  alu_ctrl,
    output reg [31:0] result,
    output zero
);
    always @(*) begin
        case (alu_ctrl)
            4'b0000: result = a & b;
            4'b0001: result = a | b;
            4'b0010: result = a + b;
            4'b0011: result = a ^ b;
            4'b0100: result = a << b[4:0];
            4'b0101: result = a >> b[4:0];
            4'b0110: result = a - b;
            default: result = 32'b0;
        endcase
    end

    assign zero = (result == 32'b0);
endmodule


// ===================================================================================================================
// Memória de Dados - RAM Inicializada Manualmente para Síntese
// ===================================================================================================================
module data_mem (
    input        clk,
    input        mem_read,
    input        mem_write,
    input  [31:0] addr,
    input  [31:0] write_data,
    output reg [31:0] read_data
);
    reg [31:0] mem [0:63]; // Capacidade mantida em 64 dados conforme solicitado
    integer i;

    initial begin
        // Zera a memória de dados
        for (i = 0; i < 64; i = i + 1) begin
            mem[i] = 32'b0;
        end
        
        // Inicializações exigidas pelos testes e pelo professor
        mem[0] = 32'd1; // Valor lido pela instrução "lw x1, 0(x0)"
        mem[1] = 32'd2; // Endereço 4 - Lido pela instrução "lw x2, 4(x0)"
        mem[8] = 32'd7; // Endereço 32 (Exigência do documento do professor: "Endereço 32 = 7")
    end

    always @(negedge clk) begin
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


// ===================================================================================================================
// Mux Mem To Reg
// ===================================================================================================================
module mux_mem_to_reg (
    input  [31:0] alu_result,
    input  [31:0] mem_read_data,
    input         mem_to_reg,
    output [31:0] write_data
);
    assign write_data = (mem_to_reg) ? mem_read_data : alu_result;
endmodule


// ===================================================================================================================
// Branch Control
// ===================================================================================================================
module branch_ctrl (
    input  branch,
    input  zero,
    output pcsrc
);
    assign pcsrc = branch & zero;
endmodule


// ===================================================================================================================
// Mux PC Src
// ===================================================================================================================
module mux_pcsrc (
    input  [31:0] pc_plus4,
    input  [31:0] pc_branch,
    input         pcsrc,
    output [31:0] next_pc
);
    assign next_pc = (pcsrc) ? pc_branch : pc_plus4;
endmodule


// ===================================================================================================================
// PC + 4
// ===================================================================================================================
module pc_plus4 (
    input  [31:0] current_pc,
    output [31:0] pc_plus4
);
    assign pc_plus4 = current_pc + 4;
endmodule


// ===================================================================================================================
// PC Branch
// ===================================================================================================================
module pc_branch (
    input  [31:0] current_pc,
    input  [31:0] imm_ext,
    output [31:0] pc_branch
);
    assign pc_branch = current_pc + imm_ext;
endmodule


// ===================================================================================================================
// MÓDULO FILTRO: Debouncer (Filtro Anti-Trepidação)
// ===================================================================================================================
module debouncer (
    input  clk_50M, 
    input  btn_in,  
    output reg btn_out 
);
    reg [19:0] count;
    
    initial begin
        count = 0;
        btn_out = 1; 
    end

    always @(posedge clk_50M) begin
        count <= count + 1;
        if (count == 20'd1_000_000) begin 
            btn_out <= btn_in; 
            count <= 0;
        end
    end
endmodule


// ===================================================================================================================
// MÓDULO TOP-LEVEL INTEGRADO (Para síntese FPGA)
// ===================================================================================================================
module TP2 (
    input        CLOCK_50, // NOVO PINO: O relógio interno da placa 
    input        clk,      // Conectado ao botão de passar o clock 
    input        reset,    // Conectado ao botão de reset 
    output [6:0] HEX0,     // Conectado físico do display da Unidade 
    output [6:0] HEX1      // Conectado físico do display da Dezena 
);
    wire clock_filtrado;
    wire [31:0] pc_atual, prox_pc, pc4, pc_br;
    wire [31:0] instrucao;
    wire [31:0] dado_reg1, dado_reg2, dado_w;
    wire [31:0] imediato;
    wire [31:0] alu_b, alu_res;
    wire [31:0] mem_dado;
    wire [3:0]  alu_comando;
    wire [1:0]  op_alu;
    
    wire        w_reg, r_mem, w_mem, src_alu, m_to_reg, m_branch, zero_flag, sinal_pcsrc;
    
    // 0. Instanciação do Filtro (Debouncer)
    debouncer filtro_inst (
        .clk_50M(CLOCK_50),
        .btn_in(clk),
        .btn_out(clock_filtrado)
    );

    // ===============================================================================================================
    // LÓGICA DINÂMICA DE CONVERSÃO E PARADA (HALT) - ABERTA ATÉ 63
    // ===============================================================================================================
    
    // Índice real da instrução (0, 1, 2, 3...)
    wire [31:0] numero_instrucao = pc_atual >> 2; 

    // O HALT agora trava se sair da memória de 64 posições (> 63) OU se instrução for vazia
    wire stop_sinal = (numero_instrucao > 63) ? 1'b1 : (instrucao == 32'b0);

    reg [3:0] algarismo_unidade;
    reg [3:0] algarismo_dezena;

    always @(*) begin
        algarismo_dezena  = (numero_instrucao / 10) % 10; 
        algarismo_unidade = numero_instrucao % 10;        
    end

    // ===============================================================================================================

    // 1. Registrador PC e Somador
    pc pc_inst (
        .clk(clock_filtrado), 
        .reset(reset), 
        .stop(stop_sinal),
        .next_pc(prox_pc), 
        .current_pc(pc_atual)
    );

    pc_plus4 pc4_inst (
        .current_pc(pc_atual), .pc_plus4(pc4)
    );

    // 2. Memória de Instruções
    instr_mem imem_inst (
        .addr(pc_atual), .instruction(instrucao)
    );

    // 3. Unidade de Controle
    control ctrl_inst (
        .opcode(instrucao[6:0]),
        .reg_write(w_reg), .mem_read(r_mem), .mem_write(w_mem),
        .alu_src(src_alu), .mem_to_reg(m_to_reg), .branch(m_branch), .alu_op(op_alu)
    );

    // 4. Banco de Registradores 
    reg_file regs_inst (
        .clk(clock_filtrado), .reg_write(w_reg),
        .rs1(instrucao[19:15]), .rs2(instrucao[24:20]), .rd(instrucao[11:7]),
        .write_data(dado_w), .read_data1(dado_reg1), .read_data2(dado_reg2)
    );

    // 5. Extensor de Imediato
    imm_gen imm_inst (
        .instruction(instrucao), .imm_ext(imediato)
    );

    // 6. Configuração da ALU
    mux_alu_src mux_alu_inst (
        .read_data2(dado_reg2), .imm_ext(imediato), .alu_src(src_alu), .b(alu_b)
    );

    alu_control aluctrl_inst (
        .alu_op(op_alu), .funct3(instrucao[14:12]), .funct7(instrucao[31:25]), .alu_ctrl(alu_comando)
    );

    alu alu_inst (
        .a(dado_reg1), .b(alu_b), .alu_ctrl(alu_comando), .result(alu_res), .zero(zero_flag)
    );

    // 7. Memória de Dados 
    data_mem dmem_inst (
        .clk(clock_filtrado), .mem_read(r_mem), .mem_write(w_mem),
        .addr(alu_res), .write_data(dado_reg2), .read_data(mem_dado)
    );

    mux_mem_to_reg mux_wdata_inst (
        .alu_result(alu_res), .mem_read_data(mem_dado), .mem_to_reg(m_to_reg), .write_data(dado_w)
    );

    // 8. Controle de Desvios (Branch)
    branch_ctrl brctrl_inst (
        .branch(m_branch), .zero(zero_flag), .pcsrc(sinal_pcsrc)
    );

    pc_branch pcbr_inst (
        .current_pc(pc_atual), .imm_ext(imediato), .pc_branch(pc_br)
    );

    mux_pcsrc mux_pc_inst (
        .pc_plus4(pc4), .pc_branch(pc_br), .pcsrc(sinal_pcsrc), .next_pc(prox_pc)
    );

    // ===============================================================================================================
    
    dec7seg_decimal modulo_unidade (
        .digito(algarismo_unidade),
        .seg(HEX0)
    );

    dec7seg_decimal modulo_dezena (
        .digito(algarismo_dezena),
        .seg(HEX1)
    );

endmodule