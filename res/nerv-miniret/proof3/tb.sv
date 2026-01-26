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

	// Assume no overflow (need billions of cycles to reach that point)
	// rvfi runs only bounded model checking, so this is reasonable.
	always_comb	assume(wrapper.uut.csr_minstret_value < 32'hF000_0000);

	rvfi_wrapper wrapper (
		.clock (clock),
		.reset (reset),
		`RVFI_CONN
		`RVFI_BUS_CONN
	);

/// Helper Assertion Begin
	// The checker captures a previous MINSTRET read into rdata_shadow (during !check).
	// MINSTRET is monotonically non-decreasing and never written (checker assumes no CSR writes),
	// so the captured shadow value can never exceed the current counter value.
	always @(posedge clock) begin
		if (!reset) begin
			h_shadow_le_minstret: assert(checker_inst.rdata_shadow <= wrapper.uut.csr_minstret_value);
			h_minstret_gt_shadow: assert((!checker_inst.csr_read_shadowed) || (wrapper.uut.csr_minstret_value > checker_inst.rdata_shadow));
		end
	end

	// RVFI valid is registered. If the core was stalled in the previous cycle, the
	// current-cycle RVFI valid must be low.
	always @(posedge clock) begin
		if (!reset && !$past(reset)) begin
			h_no_rvfi_after_stall: assert((!$past(wrapper.stall)) || (!wrapper.rvfi_valid));
		end
	end

/// Helper Assertion End
endmodule
