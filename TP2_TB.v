`timescale 1ns / 1ps
module cpu_tb;

    // ---- Clock e Reset ----
    reg clk, reset;

    // ---- Fios do PC ----
    wire [31:0] current_pc, next_pc, pc_plus4_out, pc_branch_out;

    // ---- Fios da Instrução ----
    wire [31:0] instruction; 

    // ---- Fios de Controle ----
    wire reg_write, mem_read, mem_write, alu_src, mem_to_reg, branch;
    wire [1:0] alu_op; 

    // ---- Fios do Banco de Registradores ----
    wire [31:0] read_data1, read_data2, write_data; 

    // ---- Fios do Imediato ----
    wire [31:0] imm_ext; 

    // ---- Fios da ALU ----
    wire [3:0]  alu_ctrl; 
    wire [31:0] alu_b, alu_result; 
    wire        zero;

    // ---- Fios da Memória de Dados ----
    wire [31:0] mem_read_data;

    // ---- Fios do Branch ----
    wire pcsrc;

    // ------------------------------------Program Counter-------------------------------------
    pc PC (
        .clk(clk),
        .reset(reset),
        .next_pc(next_pc),
        .current_pc(current_pc)
    ); 

    // ------------------------------------Busca da Instrução------------------------------------
    instr_mem INSTR_MEM (
        .addr(current_pc),
        .instruction(instruction)
    ); 

    // ------------------------------------Decodificação------------------------------------
    control CONTROL (
        .opcode(instruction[6:0]),
        .reg_write(reg_write),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .alu_src(alu_src),
        .mem_to_reg(mem_to_reg),
        .branch(branch),
        .alu_op(alu_op)
    ); 

    reg_file REG_FILE (
        .clk(clk),
        .reg_write(reg_write),
        .rs1(instruction[19:15]),
        .rs2(instruction[24:20]),
        .rd(instruction[11:7]),
        .write_data(write_data),
        .read_data1(read_data1),
        .read_data2(read_data2)
    );

    imm_gen IMM_GEN (
        .instruction(instruction),
        .imm_ext(imm_ext)
    ); 

    // ------------------------------------Execução------------------------------------
    alu_control ALU_CONTROL (
        .alu_op(alu_op),
        .funct3(instruction[14:12]),
        .funct7(instruction[31:25]),
        .alu_ctrl(alu_ctrl)
    ); 

    mux_alu_src MUX_ALU_SRC (
        .read_data2(read_data2),
        .imm_ext(imm_ext),
        .alu_src(alu_src),
        .b(alu_b)
    ); 

    alu ALU (
        .a(read_data1),
        .b(alu_b),
        .alu_ctrl(alu_ctrl),
        .result(alu_result),
        .zero(zero)
    ); 

    //------------------------------------ Memória de Dados------------------------------------
    data_mem DATA_MEM (
        .clk(clk),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .addr(alu_result),
        .write_data(read_data2),
        .read_data(mem_read_data)
    ); 

    mux_mem_to_reg MUX_MEM_TO_REG (
        .alu_result(alu_result),
        .mem_read_data(mem_read_data),
        .mem_to_reg(mem_to_reg),
        .write_data(write_data)
    );

    // ------------------------------------Próximo PC------------------------------------
    pc_plus4 PC_PLUS4 (
        .current_pc(current_pc),
        .pc_plus4(pc_plus4_out)
    ); 

    pc_branch PC_BRANCH (
        .current_pc(current_pc),
        .imm_ext(imm_ext),
        .pc_branch(pc_branch_out)
    );

    branch_ctrl BRANCH_CTRL (
        .branch(branch),
        .zero(zero),
        .pcsrc(pcsrc)
    );

    mux_pcsrc MUX_PCSRC (
        .pc_plus4(pc_plus4_out),
        .pc_branch(pc_branch_out),
        .pcsrc(pcsrc),
        .next_pc(next_pc)
    ); 

    // ------------------------------------Clock e Simulação------------------------------------
    initial clk = 0; 
    always #5 clk = ~clk; 

    initial begin
        reset = 1; #15 reset = 0; 
        
        // Exibe valores iniciais carregados do TXT
        $display("Valores iniciais lidos do arquivo valores.txt:"); 
        for (integer j = 0; j < 32; j = j + 1)
            $display("Reg [%2d]: %d", j, REG_FILE.regs[j]); 

        #200; 
        
        $display("\nResultado Final dos Registradores: "); 
        for (integer i = 0; i < 32; i = i + 1)
            $display("Register [%2d]: %15d", i, REG_FILE.regs[i]); 
            
        $finish;
    end

endmodule