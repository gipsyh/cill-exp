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
	// Inductive strengthening: mirror the checker shadow state with our own
	// helper state, computed from the RVFI stream.
	//
	// Instead of comparing two sets of regs in the same cycle (which can be
	// sensitive to scheduling across modules), assert the *transition relation*
	// of the checker shadow regs using $past(). This is an inductive invariant.
	wire [4:0] h_regidx = checker_inst.register_index;
	wire h_write_match = rvfi_valid[0] && !rvfi_trap[0] && (h_regidx == rvfi_rd_addr[0 +: 5]);
	wire [4:0] h_rs1_addr = rvfi_rs1_addr[0 +: 5];
	wire [4:0] h_rs2_addr = rvfi_rs2_addr[0 +: 5];

	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if ($past(h_write_match)) begin
				h_shadow_update: assert(checker_inst.register_shadow == $past(rvfi_rd_wdata[0 +: `RISCV_FORMAL_XLEN]));
				h_written_set: assert(checker_inst.register_written == 1'b1);
			end else begin
				h_shadow_hold: assert(checker_inst.register_shadow == $past(checker_inst.register_shadow));
				h_written_hold: assert(checker_inst.register_written == $past(checker_inst.register_written));
			end
		end
	end

	// The checker samples RVFI at the clock edge, so its shadow corresponds to
	// the architectural register value *before* the current instruction's write.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if (checker_inst.register_written) begin
				if (h_regidx == 5'd0)
					h_shadow_matches_rf_x0: assert(checker_inst.register_shadow == {`RISCV_FORMAL_XLEN{1'b0}});
				else
					h_shadow_matches_rf_past: assert(checker_inst.register_shadow == $past(wrapper.uut.regfile[h_regidx]));
			end
		end
	end

	// RVFI read data for the selected register_index must match the architectural
	// value from the previous cycle (before the current instruction's write).
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if (rvfi_valid[0] && (h_rs1_addr == h_regidx) && checker_inst.register_written) begin
				if (h_regidx == 5'd0)
					h_rvfi_rs1_sel_x0: assert(rvfi_rs1_rdata[0 +: `RISCV_FORMAL_XLEN] == {`RISCV_FORMAL_XLEN{1'b0}});
				else
					h_rvfi_rs1_sel_matches_rf_past: assert(rvfi_rs1_rdata[0 +: `RISCV_FORMAL_XLEN] == $past(wrapper.uut.regfile[h_regidx]));
			end
			if (rvfi_valid[0] && (h_rs2_addr == h_regidx) && checker_inst.register_written) begin
				if (h_regidx == 5'd0)
					h_rvfi_rs2_sel_x0: assert(rvfi_rs2_rdata[0 +: `RISCV_FORMAL_XLEN] == {`RISCV_FORMAL_XLEN{1'b0}});
				else
					h_rvfi_rs2_sel_matches_rf_past: assert(rvfi_rs2_rdata[0 +: `RISCV_FORMAL_XLEN] == $past(wrapper.uut.regfile[h_regidx]));
			end
		end
	end

/// Helper Assertion End
endmodule
