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
	reg h_seen_next;
	reg h_saved_valid;
	reg [`RISCV_FORMAL_XLEN-1:0] h_saved_pc;

	wire [63:0] h_rvfi_order_0 = rvfi_order[64*0 +: 64];
	wire        h_rvfi_valid_0 = rvfi_valid[0];
	wire [`RISCV_FORMAL_XLEN-1:0] h_rvfi_pc_rdata_0 = rvfi_pc_rdata[`RISCV_FORMAL_XLEN*0 +: `RISCV_FORMAL_XLEN];
	wire        h_rvfi_intr_0 = rvfi_intr[0];

	// Mirrors the intended meaning of checker_inst.expect_pc/_valid:
	// they should only become meaningful after we observed the instruction with
	// order == (insn_order+1) and captured its PC rdata.
	wire h_capture_next = h_rvfi_valid_0 && (h_rvfi_order_0 != 0) && (h_rvfi_order_0 == checker_inst.insn_order + 1);
	wire [63:0] h_insn_order_plus1 = checker_inst.insn_order + 64'd1;

	always @(posedge clock) begin
		if (reset) begin
			h_seen_next <= 0;
			h_saved_valid <= 0;
			h_saved_pc <= '0;
		end else begin
			if (h_capture_next) begin
				h_seen_next <= 1;
				h_saved_pc <= h_rvfi_pc_rdata_0;
				h_saved_valid <= !h_rvfi_intr_0;
			end
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_seen_gate: assert(!checker_inst.expect_pc_valid || h_seen_next);
			h_expect_pc_valid_mirror: assert(checker_inst.expect_pc_valid == h_saved_valid);
			if (h_seen_next) begin
				h_expect_pc_mirror: assert(checker_inst.expect_pc == h_saved_pc);
			end
			h_saved_pc_align: assert(h_saved_pc[1:0] == 2'b00);
			h_no_wraparound_capture: assert(!h_seen_next || (checker_inst.insn_order != 64'hFFFF_FFFF_FFFF_FFFF));
			if (check && !rvfi_order_loopback && h_seen_next) begin
				h_seen_implies_order_ge_plus1: assert(h_rvfi_order_0 >= h_insn_order_plus1);
			end
			if ($past(!reset)) begin
				h_no_valid_on_stall: assert(!$past(wrapper.stall) || !h_rvfi_valid_0);
			end
		end
	end
/// Helper Assertion End
endmodule
