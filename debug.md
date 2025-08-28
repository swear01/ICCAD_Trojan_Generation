# Trojan5_alu
### debug:
- operand_a << operand_b[3:0] -> operand_a << operand_b[$clog2(DATA_WIDTH)-1:0]
- acc_reg has assignments in 2 always blocks, change to assignment logic in 1 always block only
### change:
- remove OP_COUNT parameter (unused)
- add INSTR_SEED parameter
- rewrite logic such that the trojan can modify alu_result, instead of just modifying internal acc_reg
### can modify:
- instruction generation method (currently: use lfsr)
- program counter counting method (currently: += opcode each cycle)
- trojan malicious modification condition (currently: acc_reg[1:0] == 2'b11)
- alu operations