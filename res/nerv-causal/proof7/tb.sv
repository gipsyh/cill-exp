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
	// Mirror key environment constraints from the checker into inductive helpers.
	// These are logically implied by the checker's internal `assume(...)` when
	// `check` is asserted, and help the induction engine.
	always @(posedge clock) begin
		if (!reset) begin
			h_check_implies_reg_nz: assert(!check || (checker_inst.register_index != 0));
			h_check_implies_rvfi_valid: assert(!check || rvfi_valid);
			h_check_implies_rd_match: assert(!check || (checker_inst.register_index == rvfi_rd_addr));
			h_check_implies_order_match: assert(!check || (checker_inst.insn_order == rvfi_order));
		end
	end

	// DUT sanity: rvfi_order never goes backwards post-reset.
	always @(posedge clock) begin
		if (!reset && !$past(reset) && !wrapper.uut.reset_q && !$past(wrapper.uut.reset_q))
			h_rvfi_order_monotonic: assert((rvfi_order >= $past(rvfi_order)) || ($past(rvfi_order) == {64{1'b1}}));
	end

	// If the checker has already detected a "future read" of register_index,
	// we should still be past insn_order (unless we hit rvfi_order loopback).
	// This blocks induction-only states where found_non_causal is 1 while
	// check can later force insn_order == rvfi_order again.
	always @(posedge clock) begin
		if (!reset)
			h_found_non_causal_implies_order_gt: assert(!checker_inst.found_non_causal || (rvfi_order > checker_inst.insn_order) || rvfi_order_loopback);
	end

	// Prove that `found_non_causal` cannot be arbitrarily 1: it must result from
	// the precise update condition in the checker.
	reg h_found_non_causal_model;
	always @(posedge clock) begin
		if (reset) begin
			h_found_non_causal_model <= 0;
		end else begin
			if (!check) begin
				h_found_non_causal_model <= h_found_non_causal_model ||
					(rvfi_valid && (rvfi_order > checker_inst.insn_order) &&
					 ((checker_inst.register_index == rvfi_rs1_addr) || (checker_inst.register_index == rvfi_rs2_addr)));
			end else begin
				h_found_non_causal_model <= h_found_non_causal_model;
			end
		end
	end

	always @(posedge clock) begin
		if (!reset)
			h_found_non_causal_matches_model: assert(checker_inst.found_non_causal == h_found_non_causal_model);
	end

/// Helper Assertion End
endmodule
