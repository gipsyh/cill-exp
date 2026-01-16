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

	wire [1:0] mem_log2len =
		((spec_mem_rmask | spec_mem_wmask) & 8'b 1111_0000) ? 3 :
		((spec_mem_rmask | spec_mem_wmask) & 8'b 0000_1100) ? 2 :
		((spec_mem_rmask | spec_mem_wmask) & 8'b 0000_0010) ? 1 : 0;

`ifdef RISCV_FORMAL_MEM_FAULT
	wire mem_access_fault = mem_fault ||
`else
	wire mem_access_fault =
`endif
			((spec_mem_rmask || spec_mem_wmask) && !`rvformal_addr_valid(spec_mem_addr));

	reg [1:0] i;
	always@(posedge clock) begin
		i <= i;
	end

	always @* begin
		if (!reset && check) begin
			assume(spec_valid);

			if (!`rvformal_addr_valid(rvfi_pc_rdata) || mem_access_fault) begin
				o_pc_rdata: assert(rvfi_trap && rvfi_rd_addr == 0 && rvfi_rd_wdata == 0 && rvfi_mem_wmask == 0);
`ifdef RISCV_FORMAL_MEM_FAULT
				if (mem_fault) begin
					o_mem_fault0: assert(rvfi_mem_rmask == 0 && (spec_mem_wmask || spec_mem_rmask));
					o_mem_fault1: assert(`rvformal_addr_eq(spec_mem_addr, rvfi_mem_addr));
					o_mem_fault2: assert(rvfi_mem_fault_wmask == spec_mem_wmask);
					o_mem_fault3: assert((rvfi_mem_fault_rmask & spec_mem_rmask) == spec_mem_rmask);
				end
`endif
			end else begin
`ifdef RISCV_FORMAL_CSR_MISA
				o_scr_misa: assert((spec_csr_misa_rmask & rvfi_csr_misa_rmask) == spec_csr_misa_rmask);
`endif

				if (rvfi_rs1_addr == 0)
					o_rs1_rdata_zero: assert(rvfi_rs1_rdata == 0);

				if (rvfi_rs2_addr == 0)
					o_rs2_rdata_zero: assert(rvfi_rs2_rdata == 0);

				if (!spec_trap) begin
					if (spec_rs1_addr != 0)
						o_rs1_addr_match: assert(spec_rs1_addr == rvfi_rs1_addr);

					if (spec_rs2_addr != 0)
						o_rs2_addr_match: assert(spec_rs2_addr == rvfi_rs2_addr);

					o_rd_addr_match: assert(spec_rd_addr == rvfi_rd_addr);
					o_rd_wdata_match: assert(spec_rd_wdata == rvfi_rd_wdata);
					o_pc_wdata_match: assert(`rvformal_addr_eq(spec_pc_wdata, rvfi_pc_wdata));

					if (spec_mem_wmask || spec_mem_rmask) begin
						o_mem_addr_match: assert(`rvformal_addr_eq(spec_mem_addr, rvfi_mem_addr));
					end

					if (spec_mem_wmask[i]) begin
						o_mem_wmask_set_i: assert(rvfi_mem_wmask[i]);
						o_mem_wdata_match_i: assert(spec_mem_wdata[i*8 +: 8] == rvfi_mem_wdata[i*8 +: 8]);
					end else if (rvfi_mem_wmask[i]) begin
						o_mem_wmask_implies_rmask_i: assert(rvfi_mem_rmask[i]);
						o_mem_rdata_eq_wdata_i: assert(rvfi_mem_rdata[i*8 +: 8] == rvfi_mem_wdata[i*8 +: 8]);
					end
					if (spec_mem_rmask[i]) begin
						o_mem_rmask_set_i: assert(rvfi_mem_rmask[i]);
					end
				end

				o_trap_match: assert(spec_trap == rvfi_trap);
			end
		end
	end
endmodule
