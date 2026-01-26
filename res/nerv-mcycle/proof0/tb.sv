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
	always_comb assume(wrapper.uut.csr_mcycle_value != 32'hFFFFFFFF);

/// Helper Assertion Begin

	reg h_shadowed_seen;
	reg [`RISCV_FORMAL_XLEN-1:0] h_rdata_shadow;
	reg h_past_valid;

	always @(posedge clock) begin
		if (reset) begin
			h_shadowed_seen <= 1'b0;
			h_rdata_shadow <= {`RISCV_FORMAL_XLEN{1'b0}};
			h_past_valid <= 1'b0;
		end else begin
			h_past_valid <= 1'b1;
			if (!check && checker_inst.csr_read_valid && checker_inst.csr_insn_under_test) begin
				h_shadowed_seen <= 1'b1;
				h_rdata_shadow <= checker_inst.csr_insn_rdata;
			end

			if (checker_inst.csr_read_valid && checker_inst.csr_insn_under_test) begin
				if (h_past_valid) begin
					h_mcycle_sel_on_read: assert($past(wrapper.uut.csr_mcycle_sel));
					h_mcycle_rdata_matches_past: assert(checker_inst.csr_insn_rdata == $past(wrapper.uut.csr_mcycle_value));
				end
			end
			// Mirror the internal sticky bookkeeping in rvfi_csrc_upcnt_check.
			h_shadowed_seen_inv: assert(checker_inst.csr_read_shadowed == h_shadowed_seen);
			h_rdata_shadow_inv: assert(checker_inst.rdata_shadow == h_rdata_shadow);
			if (checker_inst.csr_read_shadowed)
				h_shadow_lt_mcycle: assert(wrapper.uut.csr_mcycle_value > checker_inst.rdata_shadow);
		end
	end

/// Helper Assertion End
endmodule
