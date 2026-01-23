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

	// If the arbitrary tracked instruction order is max (wrap-around), then
	// insn_order+1 == 0 and the checker can never latch expect_pc_valid because
	// it requires rvfi_order != 0. After reset this must stay false forever.
	always @(posedge clock) begin
		if (!reset)
			h_no_expect_pc_valid_on_wrap: assert(!(checker_inst.insn_order == 64'hFFFF_FFFF_FFFF_FFFF && checker_inst.expect_pc_valid));
	end

	// Core RVFI invariant: for consecutive retired instructions, the next PC of
	// the earlier instruction equals the current PC of the later instruction.
	reg h_prev_valid;
	reg [63:0] h_prev_order;
	reg [`RISCV_FORMAL_XLEN-1:0] h_prev_pc_wdata;
	wire [63:0] h_cur_order = rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64];
	wire [`RISCV_FORMAL_XLEN-1:0] h_cur_pc_rdata = rvfi_pc_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
	wire [`RISCV_FORMAL_XLEN-1:0] h_cur_pc_wdata = rvfi_pc_wdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];

	always @(posedge clock) begin
		if (reset) begin
			h_prev_valid <= 0;
		end else if (rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] && h_cur_order != 0) begin
			if (h_prev_valid && h_cur_order == h_prev_order + 64'd1) begin
				h_pc_consecutive_link: assert(`rvformal_addr_eq(h_cur_pc_rdata, h_prev_pc_wdata));
			end
			h_prev_valid <= 1;
			h_prev_order <= h_cur_order;
			h_prev_pc_wdata <= h_cur_pc_wdata;
		end
	end

	// RVFI order is a register that updates as: order(t+1) = order(t) + valid(t).
	// This prevents unreachable induction states where order changes without retire.
	always @(posedge clock) begin
		if (!reset && !$past(reset))
			h_order_update: assert(h_cur_order == $past(h_cur_order) + $past(rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX]));
	end

	// Trap can flush/retire at most one more instruction; after trap has been
	// asserted for 2 cycles, rvfi_valid must stay low.
	always @(posedge clock) begin
		if (!reset && !$past(reset, 2) && $past(wrapper.uut.trap) && $past(wrapper.uut.trap, 2))
			h_no_rvfi_valid_after_trap: assert(!rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX]);
	end

	// With compressed ISA enabled, PCs are at least 2-byte aligned.
	always @(posedge clock) begin
		if (!reset && rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] && h_cur_order != 0) begin
			h_pc_rdata_aligned: assert(h_cur_pc_rdata[0] == 1'b0);
			h_pc_wdata_aligned: assert(h_cur_pc_wdata[0] == 1'b0);
		end
	end

	always @(posedge clock) begin
		if (!reset && checker_inst.expect_pc_valid)
			h_expect_pc_aligned: assert(checker_inst.expect_pc[0] == 1'b0);
	end

	// Mirror the existing environment restriction as an inductive helper.
	always @(posedge clock) begin
		if (!reset)
			h_check_not_after_loopback: assert(!(rvfi_order_loopback && check));
	end

	// From picorv32.sv: dbg_valid_insn is cleared when trap was high.
	always @(posedge clock) begin
		if (!reset && !$past(reset) && $past(wrapper.uut.trap))
			h_dbg_valid_insn_clears_after_trap: assert(!wrapper.uut.dbg_valid_insn);
	end

	// Mirror the checker internal latching rule:
	// - The checker can only set expect_pc/expect_pc_valid when it observes the
	//   retirement of (insn_order+1) with rvfi_order != 0.
	// - expect_pc is that instruction's rvfi_pc_rdata.
	// - expect_pc_valid is the negation of rvfi_intr at that retirement.
	reg h_seen_succ;
	reg [`RISCV_FORMAL_XLEN-1:0] h_succ_pc_rdata;
	reg h_succ_intr;
	always @(posedge clock) begin
		if (reset) begin
			h_seen_succ <= 0;
		end else if (rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] && h_cur_order != 0 && h_cur_order == checker_inst.insn_order + 64'd1) begin
			h_seen_succ <= 1;
			h_succ_pc_rdata <= h_cur_pc_rdata;
			h_succ_intr <= rvfi_intr[`RISCV_FORMAL_CHANNEL_IDX];
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_expect_pc_valid_matches_latch: assert(checker_inst.expect_pc_valid == (h_seen_succ && !h_succ_intr));
			if (h_seen_succ)
				h_expect_pc_matches_latch: assert(`rvformal_addr_eq(checker_inst.expect_pc, h_succ_pc_rdata));
		end
	end

	// Key reachability invariant for the backward checker:
	// Once we've observed the successor instruction (insn_order+1), the RVFI order
	// cannot go back below that point (until wrap/loopback).
	always @(posedge clock) begin
		if (!reset && h_seen_succ && !rvfi_order_loopback)
			h_seen_succ_implies_order_ge_succ: assert(h_cur_order >= checker_inst.insn_order + 64'd1);
	end

	// If we've seen the successor (insn_order+1) with rvfi_order!=0, then insn_order
	// cannot be all-ones (because the successor would be 0, which is excluded).
	always @(posedge clock) begin
		if (!reset && h_seen_succ)
			h_seen_succ_implies_no_wrap_target: assert(checker_inst.insn_order != 64'hFFFF_FFFF_FFFF_FFFF);
	end

/// Helper Assertion End
endmodule
