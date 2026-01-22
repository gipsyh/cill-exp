// Copyright (C) 2017  Claire Xenia Wolf <claire@yosyshq.com>
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

`default_nettype none
`include "defines.sv"

module testbench (
	`ifdef RISCV_FORMAL_TRIG_CYCLE
		input trig,
	`endif
	input check,
	input clock, reset
);
	`RVFI_WIRES
	`RVFI_BUS_WIRES

	`RISCV_FORMAL_CHECKER checker_inst (
		.clock  (clock),
		.reset  (reset),
	`ifdef RISCV_FORMAL_TRIG_CYCLE
		.trig   (trig),
	`endif
		.check   (check),
		`RVFI_CONN
		`RVFI_BUS_CONN
	);

	// Ignore rvfi_order loopback, otherwise the check might be invalid.
	reg rvfi_order_loopback;
	always@(posedge clock) begin
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

// Invariants that connect the checker-internal state to actual RVFI observations.
// These block induction-only states where `expect_pc_valid` is arbitrarily high
// without ever having seen the (insn_order+1) retirement that should define it.

reg h_seen_order_plus1;
reg [`RISCV_FORMAL_XLEN-1:0] h_expect_pc_shadow;
reg [63:0] h_order_plus1;
reg [63:0] h_prev_rvfi_order;
reg h_wrapped_after_seen_plus1;
reg h_prev_retire;
reg [`RISCV_FORMAL_XLEN-1:0] h_prev_pc_wdata;
reg h_prev_cycle_dmem_fault;

always @(posedge clock) begin
	if (reset || wrapper.uut.reset_q) begin
		h_seen_order_plus1 <= 0;
		h_expect_pc_shadow <= '0;
		h_order_plus1 <= 0;
		h_prev_rvfi_order <= 0;
		h_wrapped_after_seen_plus1 <= 0;
		h_prev_retire <= 0;
		h_prev_pc_wdata <= '0;
		h_prev_cycle_dmem_fault <= 0;
	end else begin
		h_prev_cycle_dmem_fault <= wrapper.uut.cycle_dmem_fault;
		h_prev_rvfi_order <= wrapper.rvfi_order;
		if (h_seen_order_plus1 && (h_prev_rvfi_order == {64{1'b1}}) && (wrapper.rvfi_order == 0))
			h_wrapped_after_seen_plus1 <= 1;

		// Mirror the only place `checker_inst.expect_pc_valid/expect_pc` can be set
		// for `RISCV_FORMAL_CHANNEL_IDX == 0` (the check==0 branch).
		if (!check && wrapper.rvfi_valid && (wrapper.rvfi_order == checker_inst.insn_order + 1) && (wrapper.rvfi_order != 0) && !wrapper.rvfi_intr[0]) begin
			h_seen_order_plus1 <= 1;
			h_order_plus1 <= wrapper.rvfi_order;
			h_expect_pc_shadow <= wrapper.rvfi_pc_rdata;
		end

		// Track the previous retiring instruction's PC write-data.
		if (wrapper.uut.rvfi_valid) begin
			// If RVFI-valid is due to a dmem_fault (cycle_dmem_fault in the previous cycle),
			// PC fields may be stale; break the chaining invariant across this event.
			if (h_prev_cycle_dmem_fault || wrapper.uut.rvfi_intr) begin
				h_prev_retire <= 0;
			end else begin
				h_prev_retire <= 1;
				h_prev_pc_wdata <= wrapper.uut.rvfi_pc_wdata;
			end
		end
	end
end

always @(posedge clock) begin
	if (!reset && !wrapper.uut.reset_q) begin
		h_expect_pc_valid_has_witness: assert(!checker_inst.expect_pc_valid || h_seen_order_plus1);
		// The checker never sets expect_pc_valid when insn_order==64'hFFFF..FFFF
		// because it requires (rvfi_order == insn_order+1) AND (rvfi_order != 0).
		// For insn_order==max, insn_order+1 wraps to 0, making the condition impossible.
		h_expect_valid_implies_insn_not_max: assert(!checker_inst.expect_pc_valid || (checker_inst.insn_order != {64{1'b1}}));
		// If we've detected a 64-bit rvfi_order wrap after observing (insn_order+1),
		// the testbench loopback flag must be set. (The existing assume then forbids check.)
		h_wrap_after_seen_implies_loopback: assert(!h_wrapped_after_seen_plus1 || rvfi_order_loopback);
		if (checker_inst.expect_pc_valid) begin
			h_expect_pc_matches_witness: assert(checker_inst.expect_pc == h_expect_pc_shadow);
		end

		// Fundamental PC sequencing invariant across retirements:
		// for any two consecutive RVFI-valid retirements, the later pc_rdata equals the earlier pc_wdata.
		if (wrapper.uut.rvfi_valid && !h_prev_cycle_dmem_fault && !wrapper.uut.rvfi_intr && h_prev_retire) begin
			h_pc_retire_chain: assert(`rvformal_addr_eq(wrapper.uut.rvfi_pc_rdata, h_prev_pc_wdata));
		end

		// Once we've seen the (insn_order+1) retirement, the RVFI order counter must not
		// go backwards below that value (except after the explicit loopback point).
		if (!rvfi_order_loopback && h_seen_order_plus1) begin
			// Once we've seen the (insn_order+1) retirement, rvfi_order must not go below that value
			// unless the 64-bit counter wraps (all-ones -> 0). After wrap, disable this constraint.
			if (!h_wrapped_after_seen_plus1) begin
				if (!(h_prev_rvfi_order == {64{1'b1}} && wrapper.rvfi_order == 0)) begin
					h_seen_plus1_implies_order_ge: assert(wrapper.rvfi_order >= h_order_plus1);
				end
			end
			h_order_plus1_matches_insn: assert(h_order_plus1 == checker_inst.insn_order + 1);
		end

		// Basic RVFI order monotonicity (excluding the wrap-around after all-ones).
		if ($past(!reset && !wrapper.uut.reset_q) && !$past(rvfi_order_loopback) && !rvfi_order_loopback) begin
			if ($past(wrapper.rvfi_order) != {64{1'b1}}) begin
				h_rvfi_order_monotone: assert(wrapper.rvfi_order >= $past(wrapper.rvfi_order));
			end
		end
	end
end

/// Helper Assertion End
endmodule
