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

	reg h_seen_next;
	reg [63:0] h_seen_order;
	reg [`RISCV_FORMAL_XLEN-1:0] h_expect_pc;
	reg h_expect_pc_valid;

	reg h_set_event;
	reg [`RISCV_FORMAL_XLEN-1:0] h_next_pc;
	integer h_i;

	always @* begin
		h_set_event = 0;
		h_next_pc = {`RISCV_FORMAL_XLEN{1'b0}};
		for (h_i = 0; h_i < `RISCV_FORMAL_NRET; h_i = h_i + 1) begin
			if (rvfi_valid[h_i] && rvfi_order[64*h_i +: 64] == checker_inst.insn_order + 1 && rvfi_order != 0) begin
				h_set_event = 1;
				h_next_pc = rvfi_pc_rdata[h_i*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
			end
		end
	end

	always @(posedge clock) begin
		if (reset) begin
			h_seen_next <= 0;
			h_seen_order <= 0;
			h_expect_pc <= {`RISCV_FORMAL_XLEN{1'b0}};
			h_expect_pc_valid <= 0;
		end else begin
			if (h_set_event) begin
				h_seen_next <= 1;
				h_seen_order <= checker_inst.insn_order + 1;
				h_expect_pc <= h_next_pc;
				h_expect_pc_valid <= !rvfi_intr[`RISCV_FORMAL_CHANNEL_IDX];
			end
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_no_spurious_expect_valid: assert(!(checker_inst.expect_pc_valid && !h_seen_next));
			h_no_wrap_expect_valid: assert(!(checker_inst.expect_pc_valid && checker_inst.insn_order == 64'hffff_ffff_ffff_ffff));
			h_expect_valid_matches: assert(checker_inst.expect_pc_valid == h_expect_pc_valid);
			if (checker_inst.expect_pc_valid) begin
				h_expect_pc_matches: assert(checker_inst.expect_pc == h_expect_pc);
			end
			if (h_seen_next) begin
				h_seen_order_matches: assert(h_seen_order == checker_inst.insn_order + 1);
				h_seen_order_nonzero: assert(h_seen_order != 0);
				h_seen_next_implies_not_resetq: assert(!wrapper.uut.reset_q);
				if (check) begin
					h_seen_next_implies_order_ge: assert(rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] >= h_seen_order);
				end
			end
			if ($past(!reset)) begin
				if (h_seen_next) begin
					h_seen_next_has_history: assert($past(h_seen_next) || $past(h_set_event));
				end
				if ($past(h_seen_next)) begin
					h_seen_next_sticky: assert(h_seen_next);
				end
			end
			if ($past(!reset) && !$past(wrapper.uut.reset_q)) begin
				h_resetq_no_reassert: assert(!wrapper.uut.reset_q);
			end

			// Constrain rvfi_order evolution using the DUT's actual update structure.
			if (wrapper.uut.reset_q) begin
				h_rvfi_order_resetq_zero: assert(rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] == 0);
			end
			if (!wrapper.uut.reset_q && $past(!reset) && $past(!wrapper.uut.reset_q)) begin
				if ($past(wrapper.uut.cycle_insn || wrapper.uut.cycle_trap)) begin
					h_rvfi_order_step_inc: assert(rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] == $past(rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64]) + 1);
				end else begin
					h_rvfi_order_step_hold: assert(rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] == $past(rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64]));
				end
			end
		end
	end

/// Helper Assertion End
endmodule
