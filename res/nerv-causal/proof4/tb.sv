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
	// Helper invariants that reflect the *actual* sequential behavior of
	// rvfi_causal_check's internal state. These are intended to eliminate
	// induction-only CTIs where internal state changes "by magic".

	// insn_order and register_index are self-assigned every cycle (no updates).
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_stable_insn_order: assert(checker_inst.insn_order == $past(checker_inst.insn_order));
			h_stable_register_index: assert(checker_inst.register_index == $past(checker_inst.register_index));
		end
	end

	// found_non_causal is sticky: it can only ever go 0->1 (until reset).
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_found_non_causal_sticky: assert($past(checker_inst.found_non_causal) -> checker_inst.found_non_causal);
		end
	end

	// If found_non_causal rises, it must be explained by a matching read of the
	// tracked register in the immediately preceding cycle while check==0.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if (!$past(checker_inst.found_non_causal) && checker_inst.found_non_causal) begin
				h_found_non_causal_rise_reason: assert(
					!$past(check) && $past(rvfi_valid) &&
					($past(rvfi_order) > $past(checker_inst.insn_order)) &&
					(
						($past(checker_inst.register_index) == $past(rvfi_rs1_addr)) ||
						($past(checker_inst.register_index) == $past(rvfi_rs2_addr))
					)
				);
			end
		end
	end

	// Until rvfi_order hits all-ones and the harness marks loopback, rvfi_order
	// never decreases. (After wrap/loopback, check is disabled by an assume.)
	always @(posedge clock) begin
		if (!reset && $past(!reset) && !rvfi_order_loopback && !$past(rvfi_order_loopback)) begin
			h_rvfi_order_nondecreasing_preloop: assert(rvfi_order >= $past(rvfi_order));
		end
	end

	// Pre-loopback, once found_non_causal is set, order must remain strictly past
	// insn_order (it was set only when rvfi_order > insn_order, and order doesn't
	// decrease before loopback).
	always @(posedge clock) begin
		if (!reset && !rvfi_order_loopback) begin
			h_found_non_causal_implies_order_gt_preloop: assert(!checker_inst.found_non_causal || (rvfi_order > checker_inst.insn_order));
		end
	end



/// Helper Assertion End
endmodule
