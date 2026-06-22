lw x1, 0(x0)
lw x2, 4(x0)     
sub x7, x1, x2  
xor x8, x2, x7
addi x9, x8, 10
srl x10, x9, x2
sw x10, 16(x0)
beq x1, x1, 8