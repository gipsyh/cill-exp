`default_nettype none
`include "defines.sv"

module rvfi_reg_check (
	input clock, reset, check,
	`RVFI_INPUTS
);
	reg [63:0] insn_order;
	reg [4:0] register_index;
	reg [`RISCV_FORMAL_XLEN-1:0] register_shadow = 0;
	reg register_written = 0;

	integer channel_idx;
	always @(posedge clock) begin
		if (reset) begin
			register_shadow = 0;
			register_written = 0;
		end else begin
			insn_order <= insn_order;
			register_index <= register_index;
			if (check) begin
				if (rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] && insn_order == rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64]) begin
					if (register_written && register_index == rvfi_rs1_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5])
						o_shadow_rs1r: assert(register_shadow == rvfi_rs1_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN]);
					if (register_written && register_index == rvfi_rs2_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5])
						o_shadow_rs2r: assert(register_shadow == rvfi_rs2_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN]);
				end
			end
			for (channel_idx = 0; channel_idx < `RISCV_FORMAL_NRET; channel_idx=channel_idx+1) begin
				if (rvfi_valid[channel_idx] && !rvfi_trap[channel_idx] && register_index == rvfi_rd_addr[channel_idx*5 +: 5]) begin
					register_shadow = rvfi_rd_wdata[channel_idx*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
					register_written = 1;
				end
			end
		end
	end
endmodule
