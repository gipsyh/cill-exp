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

	// If the selected `insn_order` is all-ones, then `insn_order+1` wraps to zero.
	// The checker only latches `expect_pc` when it sees `rvfi_order == insn_order+1` AND `rvfi_order != 0`.
	// Therefore, when `insn_order` is all-ones, `expect_pc_valid` can never become 1 after reset.
	always @(posedge clock) begin
		if (!reset) begin
			h_no_wrap_expect_pc_valid: assert(!(checker_inst.expect_pc_valid && checker_inst.insn_order == 64'hffff_ffff_ffff_ffff));
		end
	end

	// Before rvfi_order wraparound, once `expect_pc_valid` has been set (at `rvfi_order == insn_order+1`),
	// the retirement order counter can only stay the same or increase. Therefore, while `expect_pc_valid`
	// is high, `rvfi_order` must remain strictly greater than `insn_order`.
	always @(posedge clock) begin
		if (!reset && !rvfi_order_loopback && checker_inst.expect_pc_valid) begin
			h_expect_pc_valid_implies_order_gt: assert(checker_inst.rvfi_order > checker_inst.insn_order);
		end
	end



/// Helper Assertion End
endmodule
