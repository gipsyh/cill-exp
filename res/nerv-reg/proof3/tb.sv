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
	// The rvfi_reg_check module consumes *registered* RVFI signals on each posedge.
	// In this environment the DUT architectural regfile updates on posedge too, so
	// the checker's shadow value is effectively one cycle behind the regfile.
	// Constrain that relationship to eliminate induction-only CTIs.

	wire [4:0] h_reg_idx = checker_inst.register_index;
	wire [`RISCV_FORMAL_XLEN-1:0] h_regfile_val_now = (h_reg_idx == 0) ? '0 : wrapper.uut.regfile[h_reg_idx];

	reg [`RISCV_FORMAL_XLEN-1:0] h_regfile_val_prev;
	always @(posedge clock) begin
		if (reset)
			h_regfile_val_prev <= '0;
		else
			h_regfile_val_prev <= h_regfile_val_now;
	end

	// RVFI bookkeeping must be self-consistent across cycles: the registered
	// rvfi_valid must equal the previous cycle's computed next_rvfi_valid.
	// This is a pure 1-step inductive relation and eliminates CTIs where the
	// checker shadow cannot track architectural writes.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_rvfi_valid_follows_next: assert(wrapper.uut.rvfi_valid == $past(wrapper.uut.next_rvfi_valid));
		end
	end

	// A late writeback (2nd phase of a memory-read) is not a trap/fault retirement.
	// The DUT does not update rvfi_trap in cycle_late_wr cycles, so reachable states
	// require rvfi_trap to already be 0 when cycle_late_wr occurs.
	always @(posedge clock) begin
		if (!reset) begin
			h_no_trap_on_late_wr: assert(!wrapper.uut.cycle_late_wr || !wrapper.uut.rvfi_trap);
		end
	end

	// When the DUT updates RVFI source fields (cycle_insn/cycle_trap), the captured
	// source data must match the architectural regfile value from the previous cycle.
	// We only constrain the register selected by checker_inst.register_index.
	always @(posedge clock) begin
		if (!reset && $past(!reset) && $past(wrapper.uut.cycle_insn || wrapper.uut.cycle_trap)) begin
			if (wrapper.uut.rvfi_rs1_addr == checker_inst.register_index)
				h_rvfi_rs1_matches_prev_regfile: assert(wrapper.uut.rvfi_rs1_rdata == h_regfile_val_prev);
			if (wrapper.uut.rvfi_rs2_addr == checker_inst.register_index)
				h_rvfi_rs2_matches_prev_regfile: assert(wrapper.uut.rvfi_rs2_rdata == h_regfile_val_prev);
		end
	end

	// For a 2-cycle memory read, the instruction's RVFI source fields were captured
	// in the initiating cycle and are held through the late-writeback cycle.
	// Architectural regfile contents for source registers must therefore still match.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cycle_late_wr && wrapper.uut.rvfi_rs1_addr == checker_inst.register_index)
				h_latewr_rs1_matches_regfile: assert(wrapper.uut.rvfi_rs1_rdata == h_regfile_val_now);
			if (wrapper.uut.cycle_late_wr && wrapper.uut.rvfi_rs2_addr == checker_inst.register_index)
				h_latewr_rs2_matches_regfile: assert(wrapper.uut.rvfi_rs2_rdata == h_regfile_val_now);
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_shadow_matches_prev_regfile: assert(!checker_inst.register_written || checker_inst.register_shadow == h_regfile_val_prev);
		end
	end

/// Helper Assertion End
endmodule
