lw x1, 0(x0)      # Carrega valor da memória endereço 0 para x1
lw x2, 4(x0)      # Carrega valor da memória endereço 4 para x2
add x3, x1, x2    # x3 = x1 + x2
sub x4, x1, x2    # x4 = x1 - x2
and x5, x1, x2    # x5 = x1 & x2
or  x6, x1, x2    # x6 = x1 | x2
sw  x3, 8(x0)      # Salva o resultado da soma no endereço 8 da memória
beq x1, x1, 4     # Pula para a próxima instrução (teste de branch)