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
	// Helper: eliminate spurious induction states for insn_order wrap-around.
	// If insn_order == 2^64-1 then (insn_order+1)==0, but the checker only
	// latches expect_pc when rvfi_order == insn_order+1 AND rvfi_order != 0.
	// Therefore in reachable states expect_pc_valid can never become 1.
	always @(posedge clock) begin
		if (!reset)
			h_no_insn_order_wrap_expect_valid: assert(!(checker_inst.insn_order == 64'hFFFF_FFFF_FFFF_FFFF && checker_inst.expect_pc_valid));
	end

	// Helper: `expect_pc_valid` is only raised by the checker when it observes
	// rvfi_order == insn_order+1 (and rvfi_order != 0) while not in the check
	// branch. Track that event and require it before `expect_pc_valid` can be 1.
	wire h_in_check_cycle = checker_inst.check && rvfi_valid[0] && (rvfi_order == checker_inst.insn_order);
	wire h_expect_latch_event = (!h_in_check_cycle) && rvfi_valid[0] && (rvfi_order == checker_inst.insn_order + 64'd1) && (rvfi_order != 64'd0);
	wire [`RISCV_FORMAL_XLEN-1:0] h_pc_rdata0 = rvfi_pc_rdata[0*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];

	reg h_seen_expect_latch_event;
	always @(posedge clock) begin
		if (reset) begin
			h_seen_expect_latch_event <= 1'b0;
		end else if (h_expect_latch_event) begin
			h_seen_expect_latch_event <= 1'b1;
		end
	end

	reg [`RISCV_FORMAL_XLEN-1:0] h_expect_pc_shadow;
	always @(posedge clock) begin
		if (reset) begin
			h_expect_pc_shadow <= '0;
		end else if (h_expect_latch_event) begin
			h_expect_pc_shadow <= h_pc_rdata0;
		end
	end

	reg h_seen_rvfi_order_all_ones;
	always @(posedge clock) begin
		if (reset) begin
			h_seen_rvfi_order_all_ones <= 1'b0;
		end else if (rvfi_valid[0] && rvfi_order == 64'hFFFF_FFFF_FFFF_FFFF) begin
			h_seen_rvfi_order_all_ones <= 1'b1;
		end
	end

	always @(posedge clock) begin
		if (!reset)
			h_expect_pc_valid_requires_latch: assert(!checker_inst.expect_pc_valid || h_seen_expect_latch_event || h_expect_latch_event);
	end

	// Helper: whenever the checker claims expect_pc_valid, its expect_pc must
	// equal the value captured from rvfi_pc_rdata at the most recent latch event.
	always @(posedge clock) begin
		if (!reset)
			h_expect_pc_matches_shadow: assert(!checker_inst.expect_pc_valid || (checker_inst.expect_pc == h_expect_pc_shadow));
	end

	// Helper: rvfi_order_loopback is a sticky flag that tracks whether we ever
	// observed rvfi_order==all-ones with rvfi_valid. Mirror it to help induction.
	always @(posedge clock) begin
		if (!reset)
			h_loopback_matches_seen_all_ones: assert(rvfi_order_loopback == h_seen_rvfi_order_all_ones);
	end

	// Helper: if insn_order is 2^64-2 then the latch event for expect_pc_valid
	// would require observing rvfi_order==2^64-1 with rvfi_valid, which sets the
	// loopback flag. This blocks spurious induction states near wrap-around.
	always @(posedge clock) begin
		if (!reset)
			h_no_expect_valid_near_wrap_without_loopback: assert(!(checker_inst.insn_order == 64'hFFFF_FFFF_FFFF_FFFE && checker_inst.expect_pc_valid && !rvfi_order_loopback));
	end

	// Helper: before the first rvfi_order wrap event (loopback==0), rvfi_order is
	// monotonically non-decreasing from 0 and cannot revisit a previous value.
	// Therefore if we have already observed the latch event (expect_pc_valid==1),
	// rvfi_order cannot still be equal to insn_order.
	always @(posedge clock) begin
		if (!reset)
			h_no_check_state_pre_wrap: assert(!(checker_inst.expect_pc_valid && !rvfi_order_loopback && (rvfi_order == checker_inst.insn_order)));
	end

	// Helper: rvfi_order increments by the previous cycle's rvfi_valid.
	// (This matches picorv32's nonblocking assignment ordering.)
	always @(posedge clock) begin
		if (!reset && !$past(reset)) begin
			h_rvfi_order_update: assert(rvfi_order == ($past(rvfi_order) + {{63{1'b0}}, $past(rvfi_valid[0])}));
		end
	end

	// Helper: if we've seen the latch event already, then before the first wrap
	// (loopback==0) the rvfi_order counter cannot still be below insn_order+1.
	always @(posedge clock) begin
		if (!reset)
			h_pre_wrap_order_after_latch: assert(!(h_seen_expect_latch_event && !rvfi_order_loopback && (rvfi_order < (checker_inst.insn_order + 64'd1))));
	end

/// Helper Assertion End
endmodule
