#!/bin/bash
set -e
cd $(dirname $0)/../..

mkdir -p riscv-formal/insn
B=(
  "insn_add"
  "insn_addi"
  "insn_and"
  "insn_andi"
  "insn_auipc"
  "insn_div"
  "insn_divu"
  "insn_mul"
  "insn_mulh"
  "insn_mulhsu"
  "insn_mulhu"
  "insn_or"
  "insn_ori"
  "insn_rem"
  "insn_remu"
  "insn_lui"
  "insn_sll"
  "insn_slli"
  "insn_slt"
  "insn_slti"
  "insn_sltiu"
  "insn_sltu"
  "insn_sra"
  "insn_srai"
  "insn_srl"
  "insn_srli"
  "insn_sub"
  "insn_xor"
  "insn_xori"
  "insn_c_add"
  "insn_c_addi"
  "insn_c_addi16sp"
  "insn_c_addi4spn"
  "insn_c_and"
  "insn_c_andi"
  "insn_c_beqz"
  "insn_c_bnez"
  "insn_c_j"
  "insn_c_jr"
  "insn_c_li"
  "insn_c_lui"
  "insn_c_lw"
  "insn_c_lwsp"
  "insn_c_mv"
  "insn_c_or"
  "insn_c_slli"
  "insn_c_srai"
  "insn_c_srli"
  "insn_c_sub"
  "insn_c_sw"
  "insn_c_swsp"
  "insn_c_xor"
)

C=(
  "insn_bgeu"
  "insn_beq"
  "insn_bge"
  "insn_blt"
  "insn_bltu"
  "insn_bne"
  "insn_c_jal"
  "insn_c_jalr"
  "insn_jal"
  "insn_jalr"
)

D=(
  "insn_lb"
  "insn_lbu"
  "insn_lh"
  "insn_lhu"
  "insn_lw"
  "insn_sb"
  "insn_sh"
  "insn_sw"
)

for B in "${B[@]}"; do
  echo -e '`default_nettype none\n`include "defines.sv"' >riscv-formal/insn/$B.v
  cat deps/riscv-formal/insns/${B}.v >>riscv-formal/insn/$B.v
  mkdir -p picorv32/$B
  ln -sf ../picorv32.sv picorv32/$B/picorv32.sv
  ln -sf ../wrapper.sv picorv32/$B/wrapper.sv
  ln -sf ../../riscv-formal/insn/$B.v picorv32/$B/$B.v
  ln -sf ../../riscv-formal/rvfi_insn_check.sv picorv32/$B/rvfi_insn_check.sv
  ln -sf ../../riscv-formal/rvfi_macros.vh picorv32/$B/rvfi_macros.vh
  cp picorv32/boilerplate_insn/{ric3.toml,defines.sv} picorv32/$B
  cp riscv-formal/tb.sv picorv32/$B
  echo 'ric3proj/' > picorv32/$B/.gitignore
  sed --in-place "s/xxxx/$B/g" picorv32/$B/defines.sv
  sed --in-place "s/xxxx/$B/g" picorv32/$B/ric3.toml
done

for B in "${C[@]}"; do
  echo -e '`default_nettype none\n`include "defines.sv"' >riscv-formal/insn/$B.v
  cat deps/riscv-formal/insns/${B}.v >>riscv-formal/insn/$B.v
  mkdir -p picorv32/$B
  ln -sf ../picorv32.sv picorv32/$B/picorv32.sv
  ln -sf ../wrapper.sv picorv32/$B/wrapper.sv
  ln -sf ../../riscv-formal/insn/$B.v picorv32/$B/$B.v
  ln -sf ../../riscv-formal/rvfi_insn_check.sv picorv32/$B/rvfi_insn_check.sv
  ln -sf ../../riscv-formal/rvfi_macros.vh picorv32/$B/rvfi_macros.vh
  cp picorv32/boilerplate_insn/ric3.toml picorv32/$B
  cp riscv-formal/tb.sv picorv32/$B
  echo 'ric3proj/' > picorv32/$B/.gitignore
  cp picorv32/boilerplate_insn/defines_jump.sv picorv32/$B/defines.sv
  sed --in-place "s/xxxx/$B/g" picorv32/$B/defines.sv
  sed --in-place "s/xxxx/$B/g" picorv32/$B/ric3.toml
done

for B in "${D[@]}"; do
  echo -e '`default_nettype none\n`include "defines.sv"' >riscv-formal/insn/$B.v
  cat deps/riscv-formal/insns/${B}.v >>riscv-formal/insn/$B.v
  mkdir -p picorv32/$B
  ln -sf ../picorv32.sv picorv32/$B/picorv32.sv
  ln -sf ../wrapper.sv picorv32/$B/wrapper.sv
  ln -sf ../../riscv-formal/insn/$B.v picorv32/$B/$B.v
  ln -sf ../../riscv-formal/rvfi_insn_check_mem.sv picorv32/$B/rvfi_insn_check.sv
  ln -sf ../../riscv-formal/rvfi_macros.vh picorv32/$B/rvfi_macros.vh
  cp picorv32/boilerplate_insn/{ric3.toml,defines.sv} picorv32/$B
  cp riscv-formal/tb.sv picorv32/$B
  echo 'ric3proj/' > picorv32/$B/.gitignore
  sed --in-place "s/xxxx/$B/g" picorv32/$B/defines.sv
  sed --in-place "s/xxxx/$B/g" picorv32/$B/ric3.toml
done
