#!/bin/bash
set -e
cd $(dirname $0)/../..

if [ "$1" = 'rm' ]; then
  exec rm -r picorv32/{causal,csr*,pc_bwd,pc_fwd,reg,unique}
fi

# populate DIRNAME RVFI_CHECKNAME DEFINES_SV_DIFF
populate() {
  mkdir -p picorv32/$1
  ln -sf ../picorv32.sv picorv32/$1/picorv32.sv
  ln -sf ../wrapper.sv picorv32/$1/wrapper.sv
  ln -sf ../../riscv-formal/rvfi_${2}_check.sv picorv32/$1/rvfi_${2}_check.sv
  ln -sf ../../riscv-formal/rvfi_macros.vh picorv32/$1/rvfi_macros.vh
  cp picorv32/boilerplate/{ric3.toml,defines.sv,tb.sv} picorv32/$1/
  echo -e "$3" '\n`include "rvfi_macros.vh"' >>picorv32/$1/defines.sv
  sed --in-place "s/XXXX/$2/g" picorv32/$1/defines.sv
  sed --in-place "s/XXXX/$2/g" picorv32/$1/ric3.toml
}

# CSRC tests
populate csrc_inc_mcycle csrc_inc \
  "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_CSRC_NAME mcycle"

populate csrc_inc_minstret csrc_inc \
  "\`define RISCV_FORMAL_CHECK_CYCLE 15\n\`define RISCV_FORMAL_CSRC_NAME minstret"

populate csrc_upcnt_mcycle csrc_upcnt \
  "\`define RISCV_FORMAL_CSRC_NAME mcycle"

populate csrc_upcnt_minstret csrc_upcnt \
  "\`define RISCV_FORMAL_CSRC_NAME minstret"

# CSR ill tests
populate csr_ill_c00 csr_ill \
  "\`define RISCV_FORMAL_ILL_CSR_ADDR 12'hC00\n\`define RISCV_FORMAL_ILL_UMODE\n\`define RISCV_FORMAL_ILL_WRITE"

populate csr_ill_c02 csr_ill \
  "\`define RISCV_FORMAL_ILL_CSR_ADDR 12'hC02\n\`define RISCV_FORMAL_ILL_UMODE\n\`define RISCV_FORMAL_ILL_WRITE"

populate csr_ill_c80 csr_ill \
  "\`define RISCV_FORMAL_ILL_CSR_ADDR 12'hC80\n\`define RISCV_FORMAL_ILL_UMODE\n\`define RISCV_FORMAL_ILL_WRITE"

populate csr_ill_c82 csr_ill \
  "\`define RISCV_FORMAL_ILL_CSR_ADDR 12'hC82\n\`define RISCV_FORMAL_ILL_UMODE\n\`define RISCV_FORMAL_ILL_WRITE"

# CSRW tests
populate csrw_mcycle csrw \
  "\`define RISCV_FORMAL_CSRW_NAME mcycle"

populate csrw_minstret csrw \
  "\`define RISCV_FORMAL_CSRW_NAME minstret"

# Other tests
populate causal causal ''
populate pc_fwd pc_fwd ''
populate pc_bwd pc_bwd ''
populate reg reg ''
populate unique unique ''
