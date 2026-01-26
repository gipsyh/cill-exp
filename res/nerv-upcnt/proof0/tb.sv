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

	// Helper state to safely use $past() post-reset.
	reg h_past_valid;
	always @(posedge clock) begin
		if (reset)
			h_past_valid <= 1'b0;
		else
			h_past_valid <= 1'b1;
	end

	// The checker uses internal shadow state to compare two CSR reads.
	// This shadow state is only updated when check==0 (training mode).
	// CTIs typically exploit unconstrained shadow regs (e.g. check stuck high).
	// Constrain the shadow regs to their true, reachable update behavior.

	// Architectural mcycle (low 32 bits) as implemented in the DUT.
	wire [31:0] h_mcycle_val = wrapper.uut.csr_hpm_counter_value[0 +: 32];

	always @(posedge clock) begin
		if (!reset && h_past_valid && !$past(reset)) begin
			// When a valid CSR read of mcycle occurs, the RVFI CSR read-data reflects the CSR state
			// from the start of the instruction (i.e. before this cycle's mcycle increment).
			if (checker_inst.csr_read_valid && checker_inst.csr_insn_under_test)
				h_mcycle_rdata_matches_dut: assert(checker_inst.csr_insn_rdata == $past(h_mcycle_val));

			// If we have a shadowed previous mcycle read, it cannot be greater than the current architectural mcycle.
			// (mcycle never decreases and we disallow overflow in the environment.)
			if (checker_inst.csr_read_shadowed)
				h_rdata_shadow_le_mcycle: assert(checker_inst.rdata_shadow <= h_mcycle_val);

			// csr_read_shadowed is sticky once set (only reset can clear it).
			h_csr_read_shadowed_sticky: assert(!$past(checker_inst.csr_read_shadowed) || checker_inst.csr_read_shadowed);

			// If csr_read_shadowed rises, it must be due to a training CSR read of the CSR under test.
			h_csr_read_shadowed_rise_cause: assert(
				!(checker_inst.csr_read_shadowed && !$past(checker_inst.csr_read_shadowed)) ||
				($past(!check) && $past(checker_inst.csr_read_valid && checker_inst.csr_insn_under_test))
			);

			// Training CSR read captures csr_insn_rdata into rdata_shadow.
			h_rdata_shadow_updates_on_training_read: assert(
				!($past(!check) && $past(checker_inst.csr_read_valid && checker_inst.csr_insn_under_test)) ||
				(checker_inst.csr_read_shadowed && (checker_inst.rdata_shadow == $past(checker_inst.csr_insn_rdata)))
			);

			// Otherwise rdata_shadow must remain stable (it is only assigned on reset and on training reads).
			h_rdata_shadow_stable_without_training_read: assert(
				($past(!check) && $past(checker_inst.csr_read_valid && checker_inst.csr_insn_under_test)) ||
				(checker_inst.rdata_shadow == $past(checker_inst.rdata_shadow))
			);
		end

		// In reachable states, the training phase constrained the captured value to avoid overflow.
		if (!reset && checker_inst.csr_read_shadowed)
			h_rdata_shadow_no_overflow: assert(checker_inst.rdata_shadow < 32'hF000_0000);
	end

/// Helper Assertion End
endmodule
