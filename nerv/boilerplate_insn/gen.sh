#!/bin/bash
set -e
cd $(dirname $0)/../..
if [ $1 = 'rm' ]; then
  exec rm -r riscv-formal/insn/ nerv/insn_*
fi

mkdir -p riscv-formal/insn
B=(
  "insn_add"
  "insn_addi"
  "insn_and"
  "insn_andi"
  "insn_andn"
  "insn_auipc"
  "insn_beq"
  "insn_bext"
  "insn_bexti"
  "insn_bge"
  "insn_bgeu"
  "insn_binv"
  "insn_binvi"
  "insn_bne"
  "insn_bclr"
  "insn_bclri"
  "insn_bset"
  "insn_bseti"
  "insn_clz"
  "insn_cpop"
  "insn_ctz"
  "insn_jal"
  "insn_jalr"
  "insn_lb"
  "insn_lbu"
  "insn_lh"
  "insn_lhu"
  "insn_lui"
  "insn_lw"
  "insn_max"
  "insn_maxu"
  "insn_min"
  "insn_minu"
  "insn_or"
  "insn_ori"
  "insn_orc_b"
  "insn_orn"
  "insn_rol"
  "insn_ror"
  "insn_rori"
  "insn_rev8"
  "insn_sb"
  "insn_sext_b"
  "insn_sext_h"
  "insn_sh"
  "insn_sh1add"
  "insn_sh2add"
  "insn_sh3add"
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
  "insn_xnor"
  "insn_zext_h"
  "insn_srli"
)

for B in "${B[@]}"; do
  echo -e '`default_nettype none
`include "defines.sv"' >riscv-formal/insn/$B.v
  cat deps/riscv-formal/insns/insn_${B#insn_}.v >>riscv-formal/insn/$B.v

  mkdir -p nerv/$B
  ln -sf ../wrapper.sv nerv/$B/wrapper.sv
  ln -sf ../nerv.sv nerv/$B/nerv.sv
  ln -sf ../../riscv-formal/insn/$B.v nerv/$B/$B.v
  ln -sf ../../riscv-formal/rvfi_insn_check.sv nerv/$B/rvfi_insn_check.sv
  ln -sf ../../riscv-formal/rvfi_macros.vh nerv/$B/rvfi_macros.vh
  cp nerv/boilerplate_insn/{ric3.toml,defines.sv,tb.sv} nerv/$B
  sed --in-place "s/xxxx/$B/g" nerv/$B/defines.sv
  sed --in-place "s/xxxx/$B/g" nerv/$B/ric3.toml
done

