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
	// Helper state: track whether we have ever observed the “next instruction”
	// (order == checker_inst.insn_order+1) and latched its rvfi_pc_rdata.
	// This blocks induction CTIs where checker_inst.expect_pc_valid is spuriously high.
	reg h_seen_next_order_nointr;
	reg [`RISCV_FORMAL_XLEN-1:0] h_next_order_pc_rdata;

	wire h_ch0_valid = rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX];
	wire [63:0] h_ch0_order = rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64];
	wire [`RISCV_FORMAL_XLEN-1:0] h_ch0_pc_rdata = rvfi_pc_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
	wire h_ch0_intr = rvfi_intr[`RISCV_FORMAL_CHANNEL_IDX];

	always @(posedge clock) begin
		if (reset) begin
			h_seen_next_order_nointr <= 1'b0;
			h_next_order_pc_rdata <= '0;
		end else begin
			if (h_ch0_valid && (h_ch0_order != 64'd0) && (h_ch0_order == checker_inst.insn_order + 64'd1)) begin
				h_next_order_pc_rdata <= h_ch0_pc_rdata;
				if (!h_ch0_intr)
					h_seen_next_order_nointr <= 1'b1;
			end

			h_expect_pc_valid_has_cause: assert(!checker_inst.expect_pc_valid || h_seen_next_order_nointr);
			h_expect_pc_matches_capture: assert(!checker_inst.expect_pc_valid || (checker_inst.expect_pc == h_next_order_pc_rdata));
			// When expect_pc_valid is high, the checker claims it has already observed
			// the instruction at (insn_order+1). Before rvfi_order loopback, this implies
			// the current rvfi_order must be strictly past insn_order.
			// After loopback we don't constrain this (check is assumed disabled there).
			h_expect_pc_valid_implies_past_order: assert(rvfi_order_loopback || !(checker_inst.expect_pc_valid && (h_ch0_order != 64'd0)) || (h_ch0_order > checker_inst.insn_order));

			// Ensure the tb's loopback flag is set when rvfi_order wraps.
			if ($past(!reset)) begin
				h_loopback_set_on_wrap: assert(!($past(h_ch0_order) == 64'hffff_ffff_ffff_ffff && h_ch0_order == 64'd0) || rvfi_order_loopback);
			end
		end
	end

/// Helper Assertion End
endmodule
