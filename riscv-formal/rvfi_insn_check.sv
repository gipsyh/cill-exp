`default_nettype none
`include "defines.sv"

module rvfi_insn_check (
	input clock, reset, check,
	`RVFI_INPUTS
);
	localparam integer channel_idx = `RISCV_FORMAL_CHANNEL_IDX;
	(* keep *) wire valid = !reset && rvfi_valid[channel_idx];

`ifdef RISCV_FORMAL_CSR_MISA
	(* keep *) wire [`RISCV_FORMAL_XLEN   - 1 : 0] spec_csr_misa_rmask;
`endif

	(* keep *) wire                                spec_valid;
	(* keep *) wire                                spec_trap;
	(* keep *) wire [                       4 : 0] spec_rs1_addr;
	(* keep *) wire [                       4 : 0] spec_rs2_addr;
	(* keep *) wire [                       4 : 0] spec_rd_addr;
	(* keep *) wire [`RISCV_FORMAL_XLEN   - 1 : 0] spec_rd_wdata;
	(* keep *) wire [`RISCV_FORMAL_XLEN   - 1 : 0] spec_pc_wdata;
	(* keep *) wire [`RISCV_FORMAL_XLEN   - 1 : 0] spec_mem_addr;
	(* keep *) wire [`RISCV_FORMAL_XLEN/8 - 1 : 0] spec_mem_rmask;
	(* keep *) wire [`RISCV_FORMAL_XLEN/8 - 1 : 0] spec_mem_wmask;
	(* keep *) wire [`RISCV_FORMAL_XLEN   - 1 : 0] spec_mem_wdata;

	(* keep *) wire [`RISCV_FORMAL_XLEN   - 1 : 0] rs1_rdata_or_zero = spec_rs1_addr != 0 ? rvfi_rs1_rdata : 0;
	(* keep *) wire [`RISCV_FORMAL_XLEN   - 1 : 0] rs2_rdata_or_zero = spec_rs2_addr != 0 ? rvfi_rs2_rdata : 0;

	`RISCV_FORMAL_INSN_MODEL insn_spec (
		.rvfi_valid          (valid              ),
		.rvfi_insn           (rvfi_insn          ),
		.rvfi_pc_rdata       (rvfi_pc_rdata      ),
		.rvfi_rs1_rdata      (rs1_rdata_or_zero  ),
		.rvfi_rs2_rdata      (rs2_rdata_or_zero  ),
		.rvfi_mem_rdata      (rvfi_mem_rdata     ),

`ifdef RISCV_FORMAL_CSR_MISA
		.rvfi_csr_misa_rdata (rvfi_csr_misa_rdata),
		.spec_csr_misa_rmask (spec_csr_misa_rmask),
`endif

		.spec_valid          (spec_valid         ),
		.spec_trap           (spec_trap          ),
		.spec_rs1_addr       (spec_rs1_addr      ),
		.spec_rs2_addr       (spec_rs2_addr      ),
		.spec_rd_addr        (spec_rd_addr       ),
		.spec_rd_wdata       (spec_rd_wdata      ),
		.spec_pc_wdata       (spec_pc_wdata      ),
		.spec_mem_addr       (spec_mem_addr      ),
		.spec_mem_rmask      (spec_mem_rmask     ),
		.spec_mem_wmask      (spec_mem_wmask     ),
		.spec_mem_wdata      (spec_mem_wdata     )
	);

`ifdef RISCV_FORMAL_MEM_FAULT
	wire mem_access_fault = mem_fault ||
`else
	wire mem_access_fault =
`endif
			((spec_mem_rmask || spec_mem_wmask) && !`rvformal_addr_valid(spec_mem_addr));

	always @(posedge clock) begin
		if (!reset && check && spec_valid) begin
			if (`rvformal_addr_valid(rvfi_pc_rdata) && !mem_access_fault) begin
				if (!spec_trap) begin
					o_rd_wdata_match: assert(spec_rd_wdata == rvfi_rd_wdata);
					o_pc_wdata_match: assert(`rvformal_addr_eq(spec_pc_wdata, rvfi_pc_wdata));
				end
			end
		end
	end
endmodule
