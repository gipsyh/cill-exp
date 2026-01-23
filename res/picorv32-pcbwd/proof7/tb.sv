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

	// If insn_order is all-1s, then insn_order+1 wraps to 0 and the checker logic
	// can never set expect_pc_valid (it additionally requires rvfi_order != 0).
	// Therefore, in all reachable post-reset states, expect_pc_valid must be 0.
	always @(posedge clock) begin
		if (!reset) begin
			h_no_expect_pc_valid_on_wrap: assert(!(checker_inst.insn_order == 64'hffff_ffff_ffff_ffff && checker_inst.expect_pc_valid));
		end
	end

	// The DUT increments rvfi_order monotonically (mod 2^64). The checker only sets
	// expect_pc_valid when it observes rvfi_order == insn_order+1 (and rvfi_order != 0).
	// Therefore, before rvfi_order ever reaches all-1s (loopback), expect_pc_valid
	// implies rvfi_order has already advanced past insn_order.
	always @(posedge clock) begin
		if (!reset && !rvfi_order_loopback) begin
			h_no_expect_pc_valid_when_order_matches: assert(!checker_inst.expect_pc_valid || (checker_inst.rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] > checker_inst.insn_order));
		end
	end

/// Helper Assertion End
endmodule
