#!/bin/bash
set -e
cd $(dirname $0)/../..

# populate DIRNAME RVFI_CHECKNAME DEFINES_SV_DIFF
populate() {
  mkdir -p picorv32/$1
  ln -sf ../picorv32.sv picorv32/$1/picorv32.sv
  ln -sf ../wrapper.sv picorv32/$1/wrapper.sv
  ln -sf ../../riscv-formal/rvfi_${2}_check.sv picorv32/$1/rvfi_${2}_check.sv
  ln -sf ../../riscv-formal/rvfi_macros.vh picorv32/$1/rvfi_macros.vh
  cp picorv32/boilerplate/{ric3.toml,defines.sv} picorv32/$1/
  cp riscv-formal/tb.sv picorv32/$1/
  echo 'ric3proj/' > picorv32/$1/.gitignore
  echo -e "$3" '\n`include "rvfi_macros.vh"' >>picorv32/$1/defines.sv
  sed --in-place "s/XXXX/$2/g" picorv32/$1/defines.sv
  sed --in-place "s/XXXX/$2/g" picorv32/$1/ric3.toml
}

# Somehow CSRC / CSRW fails with `sby`??
# populate csrc_inc_mcycle csrc_inc \
#   "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_CSRC_NAME mcycle"
# populate csrc_inc_minstret csrc_inc \
#   "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_CSRC_NAME minstret"
# populate csrc_upcnt_mcycle csrc_upcnt \
#   "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_CSRC_NAME mcycle"
# populate csrc_upcnt_minstret csrc_upcnt \
#   "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_CSRC_NAME minstret"
# populate csrw_mcycle csrw \
#   "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_CSRWH\n\`define RISCV_FORMAL_CSRW_NAME mcycle\n\`define RISCV_FORMAL_COMPRESSED"
# populate csrw_minstret csrw \
#   "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_CSRWH\n\`define RISCV_FORMAL_CSRW_NAME minstret\n\`define RISCV_FORMAL_COMPRESSED"

# CSR ill tests
populate csr_ill_c00 csr_ill \
  "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_ILL_CSR_ADDR 12'hC00\n\`define RISCV_FORMAL_ILL_UMODE\n\`define RISCV_FORMAL_ILL_WRITE\n\`define RISCV_FORMAL_COMPRESSED"
populate csr_ill_c02 csr_ill \
  "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_ILL_CSR_ADDR 12'hC02\n\`define RISCV_FORMAL_ILL_UMODE\n\`define RISCV_FORMAL_ILL_WRITE\n\`define RISCV_FORMAL_COMPRESSED"
populate csr_ill_c80 csr_ill \
  "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_ILL_CSR_ADDR 12'hC80\n\`define RISCV_FORMAL_ILL_UMODE\n\`define RISCV_FORMAL_ILL_WRITE\n\`define RISCV_FORMAL_COMPRESSED"
populate csr_ill_c82 csr_ill \
  "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_ILL_CSR_ADDR 12'hC82\n\`define RISCV_FORMAL_ILL_UMODE\n\`define RISCV_FORMAL_ILL_WRITE\n\`define RISCV_FORMAL_COMPRESSED"

# Other tests
populate causal causal \
  "\`define RISCV_FORMAL_RESET_CYCLES 10\n\`define RISCV_FORMAL_CHECK_CYCLE 30"
populate pc_fwd pc_fwd \
  "\`define RISCV_FORMAL_RESET_CYCLES 10\n\`define RISCV_FORMAL_CHECK_CYCLE 30"
populate pc_bwd pc_bwd \
  "\`define RISCV_FORMAL_RESET_CYCLES 10\n\`define RISCV_FORMAL_CHECK_CYCLE 30"
populate reg reg \
  "\`define RISCV_FORMAL_RESET_CYCLES 15\n\`define RISCV_FORMAL_CHECK_CYCLE 25"
populate unique unique \
  "\`define RISCV_FORMAL_CHECK_CYCLE 30\n\`define RISCV_FORMAL_TRIG_CYCLE 10"
