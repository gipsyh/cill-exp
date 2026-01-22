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
	// Shadow the internal state in rvfi_pc_bwd_check so induction cannot invent
	// unreachable combinations of {expect_pc_valid, expect_pc}.
	reg [`RISCV_FORMAL_XLEN-1:0] h_expect_pc_shadow;
	reg h_expect_pc_shadow_valid;

	wire h_rvfi_valid0 = rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX];
	wire [63:0] h_rvfi_order0 = rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64];
	wire [`RISCV_FORMAL_XLEN-1:0] h_rvfi_pc_rdata0 = rvfi_pc_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
	wire h_rvfi_intr0 = rvfi_intr[`RISCV_FORMAL_CHANNEL_IDX];

	always @(posedge clock) begin
		if (reset) begin
			h_expect_pc_shadow_valid <= 0;
		end else begin
			if (h_rvfi_valid0 && h_rvfi_order0 != 0 && h_rvfi_order0 == checker_inst.insn_order + 1) begin
				h_expect_pc_shadow <= h_rvfi_pc_rdata0;
				h_expect_pc_shadow_valid <= !h_rvfi_intr0;
			end
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_expect_pc_valid_requires_shadow: assert(!checker_inst.expect_pc_valid || h_expect_pc_shadow_valid);
			h_expect_pc_matches_shadow: assert(!checker_inst.expect_pc_valid || checker_inst.expect_pc == h_expect_pc_shadow);
			h_expect_pc_aligned: assert(!checker_inst.expect_pc_valid || checker_inst.expect_pc[1:0] == 2'b00);
			h_shadow_pc_aligned: assert(!h_expect_pc_shadow_valid || h_expect_pc_shadow[1:0] == 2'b00);
			h_pc_wdata_aligned: assert(!h_rvfi_valid0 || checker_inst.pc_wdata[1:0] == 2'b00);
			h_no_expect_on_wrap: assert(checker_inst.insn_order != 64'hFFFF_FFFF_FFFF_FFFF || !checker_inst.expect_pc_valid);
			h_expect_pc_valid_implies_order_ahead: assert(rvfi_order_loopback || !checker_inst.expect_pc_valid || (h_rvfi_order0 > checker_inst.insn_order));
		end
	end

/// Helper Assertion End
endmodule
