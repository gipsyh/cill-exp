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

	// Shadow the internal expect_pc_valid update condition of rvfi_pc_bwd_check.
	// This blocks induction-only states where expect_pc_valid is spuriously high.
	reg h_expect_pc_valid_shadow;
	reg [`RISCV_FORMAL_XLEN-1:0] h_expect_pc_shadow;
	always @(posedge clock) begin
		if (reset) begin
			h_expect_pc_valid_shadow <= 1'b0;
			h_expect_pc_shadow <= {`RISCV_FORMAL_XLEN{1'b0}};
		end else begin
			if (rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] &&
				rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] != 64'd0 &&
				rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] == checker_inst.insn_order + 64'd1)
			begin
				h_expect_pc_shadow <= rvfi_pc_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
				h_expect_pc_valid_shadow <= !rvfi_intr[`RISCV_FORMAL_CHANNEL_IDX];
			end
		end
	end

	always @(posedge clock) begin
		if (!reset)
			h_expect_pc_valid_consistent: assert(checker_inst.expect_pc_valid == h_expect_pc_valid_shadow);
	end

	always @(posedge clock) begin
		if (!reset && checker_inst.expect_pc_valid)
			h_expect_pc_consistent: assert(checker_inst.expect_pc == h_expect_pc_shadow);
	end

	// expect_pc_valid can only be asserted when rvfi_order == insn_order+1 and rvfi_order != 0,
	// which is impossible when insn_order == 2^64-1 (because insn_order+1 wraps to 0).
	always @(posedge clock) begin
		if (!reset)
			h_insn_order_not_max_when_expect_valid: assert(!checker_inst.expect_pc_valid || checker_inst.insn_order != 64'hffff_ffff_ffff_ffff);
	end

	// Before rvfi_order wraparound, once order+1 has retired, rvfi_order never goes below it.
	always @(posedge clock) begin
		if (!reset && !rvfi_order_loopback && checker_inst.expect_pc_valid)
			h_rvfi_order_past_insn_order_plus1: assert(rvfi_order >= checker_inst.insn_order + 64'd1);
	end

/// Helper Assertion End
endmodule
