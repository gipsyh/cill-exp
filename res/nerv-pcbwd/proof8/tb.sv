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
	// The CTI for o_pc_rdata comes from unreachable checker states where
	// checker_inst.expect_pc_valid is spuriously high without having observed
	// an instruction with rvfi_order == insn_order+1.
	//
	// We mirror the checker internal update semantics for expect_pc/expect_pc_valid
	// and assert the checker regs match the mirrored regs. This restricts
	// induction to reachable states, making o_pc_rdata inductive.

	wire [63:0] h_rvfi_order0 = rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64];
	wire [`RISCV_FORMAL_XLEN-1:0] h_rvfi_pc_rdata0 = rvfi_pc_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];

	wire h_cur_order_match = check && rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] &&
			(h_rvfi_order0 == checker_inst.insn_order);
	wire h_next_order_match = rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] &&
			(h_rvfi_order0 == checker_inst.insn_order + 64'd1) && (h_rvfi_order0 != 0);

	reg h_expect_pc_valid;
	reg [`RISCV_FORMAL_XLEN-1:0] h_expect_pc;
	reg h_seen_next_order;

	wire [`RISCV_FORMAL_XLEN-1:0] h_rvfi_pc_wdata0 = rvfi_pc_wdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];

	always @(posedge clock) begin
		if (reset) begin
			h_expect_pc_valid <= 1'b0;
			h_expect_pc <= '0;
		end else if (!h_cur_order_match) begin
			if (h_next_order_match) begin
				h_expect_pc <= h_rvfi_pc_rdata0;
				h_expect_pc_valid <= !rvfi_intr[`RISCV_FORMAL_CHANNEL_IDX];
			end
		end
	end

	// If the checker says it has a valid expect_pc, it must have observed the
	// (insn_order+1) retirement at some point since reset.
	// Make this sticky so it continues to hold after the observation.
	wire h_seen_next_order_next = h_seen_next_order || h_next_order_match;
	always @(posedge clock) begin
		if (reset) begin
			h_seen_next_order <= 1'b0;
		end else begin
			h_seen_next_order <= h_seen_next_order_next;
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_expect_pc_valid_mirror: assert(checker_inst.expect_pc_valid == h_expect_pc_valid);
			h_expect_pc_mirror: assert(!checker_inst.expect_pc_valid || checker_inst.expect_pc == h_expect_pc);
			h_expect_pc_valid_requires_seen_next: assert(!checker_inst.expect_pc_valid || h_seen_next_order_next);
			// Before rvfi_order has advanced past insn_order (and before order loopback),
			// it is impossible to have observed the (insn_order+1) retirement.
			h_expect_pc_valid_not_before_insn_order: assert(
				rvfi_order_loopback || (h_rvfi_order0 > checker_inst.insn_order) || !checker_inst.expect_pc_valid
			);
			// PC is always at least 4-byte aligned in NERV (npc masks low bits).
			// Enforcing this blocks induction-only states where expect_pc becomes unaligned.
			h_expect_pc_aligned: assert(!checker_inst.expect_pc_valid || checker_inst.expect_pc[1:0] == 2'b00);
			if (rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX]) begin
				h_rvfi_pc_rdata_aligned: assert(h_rvfi_pc_rdata0[1:0] == 2'b00);
				h_rvfi_pc_wdata_aligned: assert(h_rvfi_pc_wdata0[1:0] == 2'b00);
			end
		end
	end

/// Helper Assertion End
endmodule
