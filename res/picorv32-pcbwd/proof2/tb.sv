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

	// Constrain induction to post-reset behavior and tie the checker state to
	// its update conditions (no spontaneous state).
	reg h_after_reset;
	reg h_past_valid;
	reg h_seen_insn_order_p1;

	always @(posedge clock) begin
		if (reset) begin
			h_after_reset <= 1'b1;
			h_past_valid <= 1'b0;
			h_seen_insn_order_p1 <= 1'b0;
		end else begin
			h_after_reset <= h_after_reset;
			h_past_valid <= h_after_reset;
			if (rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] &&
				rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] == checker_inst.insn_order + 64'd1 &&
				rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] != 0) begin
				h_seen_insn_order_p1 <= 1'b1;
			end else begin
				h_seen_insn_order_p1 <= h_seen_insn_order_p1;
			end
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_post_reset: assert(h_after_reset);
		end
	end

	// If we haven't wrapped and the current rvfi_order is still <= insn_order,
	// then we cannot have seen (insn_order+1) yet.
	always @(posedge clock) begin
		if (!reset && h_after_reset && !rvfi_order_loopback) begin
			if (rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] <= checker_inst.insn_order) begin
				h_seen_p1_only_after_passing_order: assert(!h_seen_insn_order_p1);
			end
		end
	end

	// If the checker's `expect_pc_valid` is high, it must correspond to a real
	// observation of (insn_order+1) since reset.
	always @(posedge clock) begin
		if (!reset && h_after_reset) begin
			h_expect_pc_valid_requires_seen_p1: assert(
				!checker_inst.expect_pc_valid || h_seen_insn_order_p1
			);
		end
	end

	// In the checker, `expect_pc_valid` is only set in the "else" branch when
	// an instruction with order (insn_order + 1) is observed (and order != 0).
	// This blocks unreachable CTIs that start with `expect_pc_valid==1`.
	always @(posedge clock) begin
		if (!reset && h_after_reset && h_past_valid) begin
			if (checker_inst.expect_pc_valid && !$past(checker_inst.expect_pc_valid)) begin
				h_expect_pc_valid_rise_has_cause: assert(
					$past(rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX]) &&
					$past(rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64]) == checker_inst.insn_order + 64'd1 &&
					$past(rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64]) != 0
				);
			end
		end
	end

	// If insn_order would wrap insn_order+1 to 0, the checker update condition
	// (which requires rvfi_order != 0) can never fire. Post-reset, that means
	// expect_pc_valid must stay low forever.
	always @(posedge clock) begin
		if (!reset && h_after_reset) begin
			h_expect_pc_valid_not_wrap_order: assert(
				!checker_inst.expect_pc_valid || checker_inst.insn_order != 64'hffff_ffff_ffff_ffff
			);
		end
	end

	// At the moment we check instruction order `insn_order`, we cannot already
	// have latched the next instruction (order `insn_order+1`) without a wrap.
	always @(posedge clock) begin
		if (!reset && h_after_reset) begin
			if (check && rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] &&
				rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] == checker_inst.insn_order) begin
				h_no_expect_pc_valid_at_check_order: assert(!checker_inst.expect_pc_valid);
			end
		end
	end

	// Lemmas about `rvfi_order` evolution (helps prove ordering-based helpers).
	always @(posedge clock) begin
		if (!reset && h_after_reset && h_past_valid) begin
			h_rvfi_order_updates_by_valid: assert(
				rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] ==
					$past(rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64]) +
					{{63{1'b0}}, $past(rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX])}
			);
			if (!rvfi_order_loopback) begin
				h_rvfi_order_monotonic_no_wrap: assert(
					rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] >=
					$past(rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64])
				);
			end
		end
	end

/// Helper Assertion End
endmodule
