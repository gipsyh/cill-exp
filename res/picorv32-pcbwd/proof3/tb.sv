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

	// RVFI order is a retired-instruction counter in picorv32:
	//   rvfi_order_next = (reset ? 0 : rvfi_order + rvfi_valid)
	// (with nonblocking assignments, this is effectively + $past(rvfi_valid)).
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_rvfi_order_progress: assert(rvfi_order == $past(rvfi_order) + {{63{1'b0}}, $past(rvfi_valid[0])});
		end
	end

	// The checker records expect_pc only when it observes rvfi_order == insn_order+1 and rvfi_order != 0.
	// Therefore, if insn_order is 2^64-1 (wraparound makes insn_order+1 == 0), expect_pc_valid can never become 1.
	always @(posedge clock) begin
		if (!reset) begin
			h_no_wrap_expect_valid: assert(!(checker_inst.insn_order == 64'hffff_ffff_ffff_ffff && checker_inst.expect_pc_valid));
		end
	end

	// With COMPRESSED_ISA enabled, the PC is always at least 16-bit aligned (bit 0 is 0).
	// This is a key reachability constraint that rules out CTIs where the checker carries an unaligned expect_pc.
	always @(posedge clock) begin
		if (!reset) begin
			h_pc_bit0_zero: assert(wrapper.uut.reg_pc[0] == 1'b0);
			h_next_pc_bit0_zero: assert(wrapper.uut.next_pc[0] == 1'b0);
			h_rvfi_pc_wdata_bit0_zero: assert(!rvfi_valid[0] || rvfi_pc_wdata[0] == 1'b0);
			h_expect_pc_bit0_zero: assert(!checker_inst.expect_pc_valid || checker_inst.expect_pc[0] == 1'b0);
		end
	end

	// The backward-PC check only makes sense once we've observed the following instruction.
	// When `check` is active and the checker expects a PC, we must have progressed past insn_order.
	always @(posedge clock) begin
		if (!reset && check) begin
			h_expect_valid_implies_order_gt_when_check: assert(!checker_inst.expect_pc_valid || (rvfi_order > checker_inst.insn_order));
		end
	end

/// Helper Assertion End
endmodule
