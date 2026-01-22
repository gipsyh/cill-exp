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

	// If the checker has already flagged a non-causal situation, then we must have
	// observed (since reset) at least one retired instruction with rvfi_order > insn_order.
	// In particular, on any cycle where we retire an instruction with rvfi_order <= insn_order,
	// found_non_causal must still be 0. This blocks induction-only states where
	// found_non_causal is spuriously 1.
	always @(posedge clock) begin
		if (!reset) begin
			if (rvfi_valid && !rvfi_order_loopback && (rvfi_order <= checker_inst.insn_order)) begin
				h_no_noncausal_before_target: assert(!checker_inst.found_non_causal);
			end
		end
	end

/// Helper Assertion End
endmodule
