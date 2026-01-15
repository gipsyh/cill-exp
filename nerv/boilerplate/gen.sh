#!/bin/bash
set -e
cd $(dirname $0)/../..

# populate DIRNAME RVFI_CHECKNAME DEFINES_SV_DIFF
populate() {
  mkdir -p nerv/$1
  ln -sf ../wrapper.sv nerv/$1/wrapper.sv
  ln -sf ../nerv.sv nerv/$1/nerv.sv
  ln -sf ../../riscv-formal/rvfi_${2}_check.sv nerv/$1/rvfi_${2}_check.sv
  ln -sf ../../riscv-formal/rvfi_macros.vh nerv/$1/rvfi_macros.vh
  cp nerv/boilerplate/{ric3.toml,defines.sv} nerv/$1/
  cp riscv-formal/tb.sv nerv/$1/
  echo -e "$3" '\n`include "rvfi_macros.vh"\n`endif' >>nerv/$1/defines.sv
  sed --in-place "s/xxxx/$2/g" nerv/$1/defines.sv
  sed --in-place "s/xxxx/$2/g" nerv/$1/ric3.toml
}

BUS='`define RISCV_FORMAL_BUS\n`define RISCV_FORMAL_NBUS 2\n`define RISCV_FORMAL_BUSLEN 32'
populate bus_imem bus_imem "$BUS"
populate bus_dmem bus_dmem "$BUS"
populate bus_imem_fault bus_imem_fault "$BUS"
populate bus_dmem_fault bus_dmem_fault "$BUS"
populate causal causal ''
populate pc_bwd pc_bwd ''
populate pc_fwd pc_fwd ''
populate reg reg ''
populate ill ill ''
populate unique unique ''

populate csrc_const_custom_ro csrc_const \
  "\`define RISCV_FORMAL_CSRC_CONSTVAL 32'h dead_beef\n\`define RISCV_FORMAL_CSRC_NAME custom_ro"
populate csrc_inc_mhpmcounter5 csrc_inc \
  "\`define RISCV_FORMAL_CSRC_NAME mhpmcounter5"
populate csr_ill_f11 csr_ill \
  "\`define RISCV_FORMAL_ILL_CSR_ADDR 12'hF11\n\`define RISCV_FORMAL_ILL_MMODE\n\`define RISCV_FORMAL_ILL_WRITE"
populate csr_ill_fff csr_ill \
  "\`define RISCV_FORMAL_ILL_CSR_ADDR 12'hFFF\n\`define RISCV_FORMAL_ILL_MMODE\n\`define RISCV_FORMAL_ILL_SMODE\n\`define RISCV_FORMAL_ILL_UMODE\n\`define RISCV_FORMAL_ILL_READ\n\`define RISCV_FORMAL_ILL_WRITE"
populate csrw_custom csrw \
  "\`define RISCV_FORMAL_CSRW_NAME custom"
populate csrw_custom_ro csrw \
  "\`define RISCV_FORMAL_CSRW_NAME custom_ro"
populate csrc_upcnt_mcycle csrc_upcnt \
  "\`define RISCV_FORMAL_CSRC_NAME mcycle"
populate csrc_upcnt_minstret csrc_upcnt \
  "\`define RISCV_FORMAL_CSRC_NAME minstret"
populate csrw_mcycle csrw \
  "\`define RISCV_FORMAL_CSRWH\n\`define RISCV_FORMAL_CSRW_NAME mcycle"
populate csrw_mhpmcounter5 csrw \
  "\`define RISCV_FORMAL_CSRW_NAME mhpmcounter5"
populate csrw_mhpmevent3 csrw \
  "\`define RISCV_FORMAL_CSRW_NAME mhpmevent3"
populate csrw_mhpmevent5 csrw \
  "\`define RISCV_FORMAL_CSRW_NAME mhpmevent5"
populate csrw_mhpmevent9 csrw \
  "\`define RISCV_FORMAL_CSRW_NAME mhpmevent9"
populate csrw_minstret csrw \
  "\`define RISCV_FORMAL_CSRWH\n\`define RISCV_FORMAL_CSRW_NAME minstret"
populate csrw_mstatus csrw \
  "\`define RISCV_FORMAL_CSRW_NAME mstatus"

