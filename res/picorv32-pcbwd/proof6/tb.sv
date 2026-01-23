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
	// If insn_order is max, the checker can never observe insn_order+1 with rvfi_order!=0,
	// so expect_pc_valid can never become 1 in reachable states.
	always @(posedge clock) begin
		if (!reset)
			h_no_wrap_expect_pc_valid: assert(!(checker_inst.insn_order == 64'hffff_ffff_ffff_ffff && checker_inst.expect_pc_valid));
	end

	// Shadow the internal bookkeeping in rvfi_pc_bwd_check to prevent spurious induction states.
	reg [`RISCV_FORMAL_XLEN-1:0] h_expect_pc_shadow;
	reg h_expect_pc_shadow_valid;
	reg h_after_capture;
	reg [63:0] h_capture_order;

	always @(posedge clock) begin
		if (reset) begin
			h_expect_pc_shadow <= '0;
			h_expect_pc_shadow_valid <= 1'b0;
			h_after_capture <= 1'b0;
			h_capture_order <= 64'd0;
		end else begin
			if (checker_inst.rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] &&
					checker_inst.rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] == checker_inst.insn_order + 64'd1 &&
					checker_inst.rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] != 64'd0) begin
				h_expect_pc_shadow <= checker_inst.rvfi_pc_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
				h_expect_pc_shadow_valid <= !checker_inst.rvfi_intr[`RISCV_FORMAL_CHANNEL_IDX];
				h_after_capture <= 1'b1;
				h_capture_order <= checker_inst.rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64];
			end
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_shadow_matches_valid: assert(checker_inst.expect_pc_valid == h_expect_pc_shadow_valid);
			h_shadow_matches_data: assert(!checker_inst.expect_pc_valid || checker_inst.expect_pc == h_expect_pc_shadow);

			// If the checker believes it has a valid expected PC, then it must have captured it
			// from the (insn_order+1) instruction.
			h_expect_valid_implies_captured: assert(!checker_inst.expect_pc_valid || h_after_capture);
			h_capture_order_matches_insn_order: assert(!h_after_capture || h_capture_order == checker_inst.insn_order + 64'd1);

			// Before rvfi_order wraps (rvfi_order_loopback==0), rvfi_order is monotone and cannot
			// return to insn_order after capturing insn_order+1.
			if (h_after_capture && !rvfi_order_loopback) begin
				h_order_ge_capture: assert(checker_inst.rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64] >= h_capture_order);
			end
		end
	end

/// Helper Assertion End
endmodule
