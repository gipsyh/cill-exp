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
  "insn_beq"
  "insn_bge"
  "insn_bgeu"
  "insn_bne"
  "insn_jal"
  "insn_jalr"
  "insn_lb"
  "insn_lbu"
  "insn_lh"
  "insn_lhu"
  "insn_lui"
  "insn_lw"
  "insn_or"
  "insn_ori"
  "insn_sb"
  "insn_sh"
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
  "insn_sw"
  "insn_xor"
  "insn_xori"
)

for B in "${B[@]}"; do
  echo -e '`default_nettype none `include "defines.sv"' >riscv-formal/insn/$B.v
  cat deps/riscv-formal/insns/insn_${B#insn_}.v >>riscv-formal/insn/$B.v

  mkdir -p serv/$B
  ln -sf ../rtl serv/$B/rtl
  ln -sf ../wrapper.sv serv/$B/wrapper.sv
  ln -sf ../../riscv-formal/insn/$B.v serv/$B/$B.v
  ln -sf ../../riscv-formal/rvfi_insn_check.sv serv/$B/rvfi_insn_check.sv
  ln -sf ../../riscv-formal/rvfi_macros.vh serv/$B/rvfi_macros.vh
  cp serv/boilerplate_insn/{ric3.toml,defines.sv} serv/$B
  cp riscv-formal/tb.sv serv/$B
  echo 'ric3proj/' > serv/$B/.gitignore
  sed --in-place "s/xxxx/$B/g" serv/$B/defines.sv
  sed --in-place "s/xxxx/$B/g" serv/$B/ric3.toml
done
