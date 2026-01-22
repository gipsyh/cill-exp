`default_nettype none
`include "defines.sv"

// free input variables, can take any value each cycle as long as the `assume` are satisfied
module testbench (
	input check,
	input clock, reset
);
	`RVFI_WIRES
	`RVFI_BUS_WIRES

	`RISCV_FORMAL_CHECKER checker_inst (
		.clock  (clock),
		.reset  (reset),
		.check   (check),
		`RVFI_CONN
		`RVFI_BUS_CONN
	);

	// Ignore rvfi_order loopback, otherwise the check might be invalid.
	reg rvfi_order_loopback;
	always @(posedge clock) begin
		if (reset) begin
			rvfi_order_loopback <= 0;
		end else if (rvfi_valid && rvfi_order == {64{1'b1}}) begin
			rvfi_order_loopback <= 1;
		end
	end
	always_comb assume (!(rvfi_order_loopback && check));

	rvfi_wrapper wrapper (
		.clock (clock),
		.reset (reset),
		`RVFI_CONN
		`RVFI_BUS_CONN
	);

/// Helper Assertion Begin
	reg h_seen_reset;

	always @(posedge clock) begin
		if (reset)
			h_seen_reset <= 1'b1;
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_seen_reset_post_reset: assert(h_seen_reset);
			if (h_seen_reset && checker_inst.check && checker_inst.register_written && (checker_inst.register_index != 0) &&
					checker_inst.rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] &&
					checker_inst.insn_order == checker_inst.rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64]) begin
				// If the tracked register is read as rs2, and it isn't being written in the same RVFI record,
				// then its RVFI read-data must match the architectural register state.
				if ((checker_inst.register_index == checker_inst.rvfi_rs2_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5]) &&
						(checker_inst.rvfi_rd_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5] != checker_inst.register_index)) begin
					if (checker_inst.register_index == 0) begin
						h_rs2_rdata_x0: assert(checker_inst.rvfi_rs2_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN] == 0);
					end else begin
						h_rs2_rdata_matches_regfile: assert(checker_inst.rvfi_rs2_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN] == wrapper.uut.regfile[checker_inst.register_index]);
					end
				end

				if (checker_inst.register_index == checker_inst.rvfi_rs1_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5]) begin
					if (wrapper.uut.regfile[checker_inst.register_index] == checker_inst.rvfi_rs1_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN]) begin
						h_shadow_matches_regfile_rs1: assert(checker_inst.register_shadow == wrapper.uut.regfile[checker_inst.register_index]);
					end
				end
				if (checker_inst.register_index == checker_inst.rvfi_rs2_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5]) begin
					if (wrapper.uut.regfile[checker_inst.register_index] == checker_inst.rvfi_rs2_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN]) begin
						h_shadow_matches_regfile_rs2: assert(checker_inst.register_shadow == wrapper.uut.regfile[checker_inst.register_index]);
					end
				end
			end
		end
	end

/// Helper Assertion End
endmodule
