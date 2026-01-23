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
	// If insn_order is all-ones then insn_order+1 wraps to 0, but the checker
	// only latches expect_pc when rvfi_order == insn_order+1 && rvfi_order != 0.
	// Therefore expect_pc_valid can never become 1 in this case.
	always @(posedge clock) begin
		if (!reset)
			h_insn_order_wrap_blocks_expect: assert(!(checker_inst.insn_order == 64'hffff_ffff_ffff_ffff && checker_inst.expect_pc_valid));
	end

	// With COMPRESSED_ISA enabled, instruction fetch PCs are at least 2-byte aligned.
	// This is a strong, general invariant that eliminates many spurious CTIs where
	// the checker-latched PC can take an impossible odd value.
	always @(posedge clock) begin
		if (!reset) begin
			h_rvfi_pc_rdata_aligned: assert(!rvfi_valid[0] || (rvfi_pc_rdata[0] == 1'b0));
			h_rvfi_pc_wdata_aligned: assert(!rvfi_valid[0] || (rvfi_pc_wdata[0] == 1'b0));
			h_expect_pc_aligned: assert(!checker_inst.expect_pc_valid || (checker_inst.expect_pc[0] == 1'b0));
		end
	end

	reg h_seen_retire;
	reg [63:0] h_last_order;

	always @(posedge clock) begin
		if (reset) begin
			h_seen_retire <= 1'b0;
			h_last_order <= 64'd0;
		end else begin
			if (rvfi_valid[0]) begin
				if (h_seen_retire)
					h_rvfi_order_increments: assert(rvfi_order[0 +: 64] == h_last_order + 64'd1);
				h_seen_retire <= 1'b1;
				h_last_order <= rvfi_order[0 +: 64];
			end
		end
	end

	// If the checker has already latched expect_pc (i.e. it saw insn_order+1 at some point),
	// then the global rvfi_order stream must have progressed to at least insn_order+1.
	// This rules out spurious induction states where expect_pc_valid is 1 while we're still
	// observing rvfi_order == insn_order (before any loopback).
	always @(posedge clock) begin
		if (!reset && !rvfi_order_loopback && checker_inst.expect_pc_valid && h_seen_retire)
			h_expect_implies_order_progress: assert(h_last_order >= checker_inst.insn_order + 64'd1);
	end

/// Helper Assertion End
endmodule
