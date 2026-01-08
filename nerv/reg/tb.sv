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
	reg [31:0] last_regfile_index;
	// reg past_rvfi_order_loopback;
	always @(posedge clock) begin
		// past_rvfi_order_loopback <= rvfi_order_loopback;
		// if (checker_inst.register_written && )
		// 	assert(rvfi_order_loopback);

		last_regfile_index <= wrapper.uut.regfile[checker_inst.register_index];
		if (!reset && rvfi_order < checker_inst.insn_order && !rvfi_order_loopback) begin
			// The shadow value is updated using RVFI signals that are written with
			// nonblocking assignments, so it naturally aligns with the *previous*
			// architectural wrapper.uut.regfile value for the chosen register.
			h_01_shadow_matches_regfile: assert(!checker_inst.register_written || checker_inst.register_index == 0 || checker_inst.register_shadow == last_regfile_index);
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			// For a retired instruction, if rs1 is not x0 and the instruction does
			// not write back to rs1, then rs1's value is unchanged by the
			// instruction, so the RVFI pre-state read must equal the architectural
			// post-state wrapper.uut.regfile value.
			h_03_rs1_rdata_stable_when_not_written: assert(
				!rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] || rvfi_trap[`RISCV_FORMAL_CHANNEL_IDX] ||
				rvfi_rs1_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5] == 0 ||
				rvfi_rd_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5] == rvfi_rs1_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5] ||
				rvfi_rs1_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN] ==
					wrapper.uut.regfile[rvfi_rs1_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5]]
			);
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			// Symmetric to h_03 for rs2: when the retired instruction does not write
			// back to rs2, then rs2's architectural value is unchanged, so the RVFI
			// pre-state read must equal the architectural post-state wrapper.uut.regfile value.
			h_04_rs2_rdata_stable_when_not_written: assert(
				!rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] || rvfi_trap[`RISCV_FORMAL_CHANNEL_IDX] ||
				rvfi_rs2_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5] == 0 ||
				rvfi_rd_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5] == rvfi_rs2_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5] ||
				rvfi_rs2_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN] ==
					wrapper.uut.regfile[rvfi_rs2_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5]]
			);
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			// In the second cycle of a memory op (`wrapper.uut.cycle_late_wr`), RVFI rs1 fields
			// refer to the in-flight instruction and must match the architectural
			// wrapper.uut.regfile value (no intervening instructions can change rs1).
			h_05_late_wr_rs1_matches_regfile: assert(
				!wrapper.uut.cycle_late_wr ||
				rvfi_rs1_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5] == 0 ||
				rvfi_rs1_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN] ==
					wrapper.uut.regfile[rvfi_rs1_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5]]
			);
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			// Symmetric to h_05 for rs2 in the second cycle of a memory op.
			h_06_late_wr_rs2_matches_regfile: assert(
				!wrapper.uut.cycle_late_wr ||
				rvfi_rs2_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5] == 0 ||
				rvfi_rs2_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN] ==
					wrapper.uut.regfile[rvfi_rs2_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5]]
			);
		end
	end
/// Helper Assertion End
endmodule
