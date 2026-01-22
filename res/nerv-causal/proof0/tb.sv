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

	// `found_non_causal` can only be raised when we see a *later* instruction
	// (rvfi_order > insn_order) that reads the tracked register. Therefore, if it
	// is high on a cycle where an instruction retires, the retiring order must be
	// strictly greater than the tracked `insn_order`.
	always @(posedge clock) begin
		if (!reset) begin
			if (!rvfi_order_loopback && checker_inst.rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX]) begin
				h_found_non_causal_implies_order_gt: assert(
					!checker_inst.found_non_causal ||
					checker_inst.rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] > checker_inst.insn_order
				);
			end
		end
	end

	// The checker keeps `insn_order` and `register_index` as persistent tracked
	// state (self-assigned each cycle). Make that explicit to help induction.
	always @(posedge clock) begin
		if (!reset && !$past(reset)) begin
			h_insn_order_stable: assert(checker_inst.insn_order == $past(checker_inst.insn_order));
			h_register_index_stable: assert(checker_inst.register_index == $past(checker_inst.register_index));
		end
	end

	// Define `rvfi_order_loopback` precisely (used to avoid wrap-around corner
	// cases when reasoning about rvfi_order comparisons).
	always @(posedge clock) begin
		if (!reset && !$past(reset)) begin
			h_loopback_sticky: assert($past(rvfi_order_loopback) -> rvfi_order_loopback);
			h_loopback_set_on_max: assert(
				($past(rvfi_valid && rvfi_order == {64{1'b1}})) -> rvfi_order_loopback
			);
		end
	end

	// If `found_non_causal` rises, it must be due to a retiring instruction with
	// order strictly greater than `insn_order` in the *previous* cycle.
	// (Using $past avoids clock-region/scheduling pitfalls.)
	always @(posedge clock) begin
		if (!reset && !$past(reset)) begin
			if (!$past(checker_inst.found_non_causal) && checker_inst.found_non_causal) begin
				h_found_non_causal_rise_cause: assert(
					$past(checker_inst.rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX]) &&
					$past(checker_inst.rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64]) > $past(checker_inst.insn_order)
				);
			end
		end
	end

/// Helper Assertion End
endmodule
