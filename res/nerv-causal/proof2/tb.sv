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
	// Helper state: track whether we've ever observed any retired instruction
	// with an order greater than the tracked insn_order.
	// This must be true before checker_inst.found_non_causal can legitimately be 1.
	reg h_seen_later_order;

	always @(posedge clock) begin
		if (reset) begin
			h_seen_later_order <= 1'b0;
		end else begin
			h_seen_later_order <= h_seen_later_order ||
				(checker_inst.rvfi_valid && (checker_inst.rvfi_order > checker_inst.insn_order));
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_found_non_causal_has_cause: assert(!checker_inst.found_non_causal || h_seen_later_order);
		end
	end

	always @(posedge clock) begin
		if (!reset && !rvfi_order_loopback) begin
			h_found_non_causal_implies_order_gt: assert(!checker_inst.found_non_causal || (checker_inst.rvfi_order > checker_inst.insn_order));
		end
	end

/// Helper Assertion End
endmodule
