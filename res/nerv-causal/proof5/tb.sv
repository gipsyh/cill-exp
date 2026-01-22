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
	reg h_past_valid;
	always @(posedge clock) begin
		if (reset)
			h_past_valid <= 0;
		else
			h_past_valid <= 1;
	end

	// RVFI order updates by staying constant or incrementing by 1.
	// We only enforce this before the loopback point (rvfi_order == '1), since
	// afterwards the counter can wrap and the environment forbids `check` anyway.
	always @(posedge clock) begin
		if (!reset && h_past_valid && !rvfi_order_loopback && !$past(rvfi_order_loopback) &&
				!wrapper.uut.reset_q && !$past(wrapper.uut.reset_q)) begin
			h_rvfi_order_step: assert((rvfi_order == $past(rvfi_order)) || (rvfi_order == $past(rvfi_order) + 64'd1));
		end
	end

	// If the checker has latched a non-causal condition, we must have already
	// advanced past the chosen insn_order (the latch condition itself requires
	// rvfi_order > insn_order, and rvfi_order is monotonic in the DUT).
	always @(posedge clock) begin
		if (!reset && !rvfi_order_loopback) begin
			h_found_implies_order_gt: assert(!checker_inst.found_non_causal || (rvfi_order > checker_inst.insn_order));
		end
	end

/// Helper Assertion End
endmodule
