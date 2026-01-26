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

	// Assume no overflow (need billions of cycles to reach that point)
	// rvfi runs only bounded model checking, so this is reasonable.
	always_comb	assume(wrapper.uut.csr_minstret_value < 32'hF000_0000);

	rvfi_wrapper wrapper (
		.clock (clock),
		.reset (reset),
		`RVFI_CONN
		`RVFI_BUS_CONN
	);

/// Helper Assertion Begin

	// Helper invariants to make the original o_check property inductive.
	// Keep them post-reset to avoid cycle-0 nondeterminism.
	always @(posedge clock) begin
		if (!reset) begin
			// When an instruction retires and reads minstret, the RVFI-exposed CSR read data
			// matches the core minstret value from the previous cycle (pipeline timing).
			h_rvfi_minstret_matches_core: assert(!(checker_inst.csr_read_valid && checker_inst.csr_insn_under_test) ||
				(checker_inst.csr_insn_rdata == $past(wrapper.uut.csr_minstret_value)));

			// After we have successfully shadowed a minstret read, the core minstret counter
			// must be strictly greater than the shadowed read data.
			h_shadow_lt_core_minstret: assert(!checker_inst.csr_read_shadowed ||
				(checker_inst.rdata_shadow < wrapper.uut.csr_minstret_value));
		end
	end

/// Helper Assertion End
endmodule
