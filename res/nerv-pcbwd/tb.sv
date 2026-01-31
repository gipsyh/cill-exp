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
	reg [63:0] h_prev_rvfi_order;
	always @(posedge clock) begin
		if (reset) begin
			h_prev_rvfi_order <= 0;
		end else begin
			h_prev_rvfi_order <= rvfi_order;
		end
	end

	// `checker_inst.expect_pc_valid` is only assigned in the (check==0) branch when
	// `rvfi_order == insn_order + 1` and `rvfi_order != 0`.
	always @(posedge clock) begin
		if (!reset) begin
			h_expect_pc_valid_implies_insn_order_not_max:
				assert(!checker_inst.expect_pc_valid || checker_inst.insn_order != 64'hffff_ffff_ffff_ffff);

			// Before `rvfi_order` has ever reached all-ones, it cannot have wrapped.
			// For proof purposes, we treat `rvfi_order_loopback` as the epoch boundary.
			// Before loopback, the checker can only set `expect_pc_valid` once it has
			// observed `rvfi_order == insn_order+1`.
			h_expect_pc_valid_implies_order_ge_insn_plus1_preloop:
				assert(!(checker_inst.expect_pc_valid && !rvfi_order_loopback && (rvfi_order < checker_inst.insn_order + 1)));

			// Also require that `rvfi_order` does not decrease before loopback.
			h_rvfi_order_no_decrease_before_loopback:
				assert(!( !rvfi_order_loopback && (rvfi_order < h_prev_rvfi_order) ));

		end
	end

/// Helper Assertion End
endmodule
