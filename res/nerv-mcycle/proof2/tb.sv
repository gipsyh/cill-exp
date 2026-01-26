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
	// Inductive strengthening: the checker can only have a valid shadow value
	// if we have spent at least one cycle in the sampling phase (check==0)
	// since reset.
	reg h_ever_check_low;
	always @(posedge clock) begin
		if (reset) begin
			h_ever_check_low <= 1'b0;
		end else if (!check) begin
			h_ever_check_low <= 1'b1;
		end
	end

	// Track the most recent sampling-phase (check==0) CSR read of mcycle.
	reg h_have_sample;
	reg [`RISCV_FORMAL_XLEN-1:0] h_last_sample_rdata;
	always @(posedge clock) begin
		if (reset) begin
			h_have_sample <= 1'b0;
			h_last_sample_rdata <= '0;
		end else if (!check && checker_inst.csr_read_valid && checker_inst.csr_insn_under_test) begin
			h_have_sample <= 1'b1;
			h_last_sample_rdata <= checker_inst.csr_insn_rdata;
		end
	end

	always @(posedge clock) begin
		if (!reset)
			h_shadow_requires_sample_phase: assert(!checker_inst.csr_read_shadowed || h_ever_check_low);
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_shadowed_requires_sample_read: assert(!checker_inst.csr_read_shadowed || h_have_sample);
			if (h_have_sample)
				h_shadow_matches_last_sample: assert(checker_inst.rdata_shadow == h_last_sample_rdata);
		end
	end

	// The checker constrains sampled CSR reads to avoid overflow; therefore the
	// stored shadow value must always stay within that range once shadowed.
	always @(posedge clock) begin
		if (!reset)
			h_shadow_no_overflow: assert(!checker_inst.csr_read_shadowed || (checker_inst.rdata_shadow[31:0] < 32'hF000_0000));
	end

	// Shadowed value must be a past mcycle read, so it cannot exceed the current
	// mcycle counter value.
	always @(posedge clock) begin
		if (!reset && !wrapper.uut.reset_q)
			h_shadow_le_current_mcycle: assert(!checker_inst.csr_read_shadowed || (wrapper.uut.csr_mcycle_value >= checker_inst.rdata_shadow));
	end

	// mcycle counter semantics (low 32b): once the DUT's internal reset is fully
	// deasserted, the register takes last cycle's computed next.
	always @(posedge clock) begin
		if (!reset && !wrapper.uut.reset_q && $past(!reset && !wrapper.uut.reset_q))
			h_mcycle_value_follows_next: assert(wrapper.uut.csr_mcycle_value == $past(wrapper.uut.csr_mcycle_next));
	end

	// Next-state should always be one more than the post-CSR-write value.
	always @(posedge clock) begin
		if (!reset)
			h_mcycle_next_is_wdata_plus_one: assert(wrapper.uut.csr_mcycle_next == wrapper.uut.csr_mcycle_wdata + 32'd1);
	end

	// Timing: RVFI CSR read data is captured on the clock edge, using the
	// pre-edge CSR value; meanwhile, the counter value itself updates on the
	// same edge. So post-edge, the observed CSR rdata corresponds to the
	// previous cycle's mcycle value.
	always @(posedge clock) begin
		if (!reset && !wrapper.uut.reset_q && $past(!reset && !wrapper.uut.reset_q) &&
				checker_inst.csr_read_valid && checker_inst.csr_insn_under_test)
			h_csr_read_matches_mcycle: assert(checker_inst.csr_insn_rdata == $past(wrapper.uut.csr_mcycle_value));
	end

	// When a sample read happens (in the previous cycle), the checker must have
	// set its shadow flag and captured that rdata.
	always @(posedge clock) begin
		if (!reset && $past(!reset) &&
				$past(!check && checker_inst.csr_read_valid && checker_inst.csr_insn_under_test)) begin
			h_shadow_sets_on_sample: assert(checker_inst.csr_read_shadowed);
			h_shadow_equals_prev_read: assert(checker_inst.rdata_shadow == $past(checker_inst.csr_insn_rdata));
		end
	end

/// Helper Assertion End
endmodule
