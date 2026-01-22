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
	// Strengthen the proof by characterizing when the checker can possibly
	// have raised its sticky `found_non_causal` flag.
	//
	// In the checker, `found_non_causal` is only set when observing an instruction
	// with rvfi_order > insn_order (i.e. a later-order instruction in time).
	// Therefore, once `found_non_causal` is high, rvfi_order must have already
	// passed insn_order, unless we are in the post-wrap regime guarded by
	// rvfi_order_loopback (where `check` is disallowed by an existing assume).
	always @(posedge clock) begin
		if (!reset) begin
			h_found_non_causal_implies_order_passed: assert(
				!checker_inst.found_non_causal || rvfi_order_loopback || (checker_inst.rvfi_order > checker_inst.insn_order)
			);
		end
	end

/// Helper Assertion End
endmodule
