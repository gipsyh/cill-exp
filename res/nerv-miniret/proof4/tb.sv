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

	// Ensure the sampled shadow data always respects the same no-overflow bound
	// that is assumed when the shadow is captured inside the checker.
	always @(posedge clock) begin
		if (!reset) begin
			h_rdata_shadow_no_overflow: assert(!checker_inst.csr_read_shadowed || (checker_inst.rdata_shadow < 32'hF000_0000));
		end
	end

	// The minstret counter is monotonically non-decreasing after reset.
	always @(posedge clock) begin
		if (!reset && !$past(reset)) begin
			h_minstret_monotonic: assert(wrapper.uut.csr_minstret_value >= $past(wrapper.uut.csr_minstret_value));
		end
	end

	// If we have already shadowed a minstret read, that shadow should never be
	// ahead of the architectural minstret value.
	always @(posedge clock) begin
		if (!reset) begin
			h_shadow_le_current: assert(!checker_inst.csr_read_shadowed || (checker_inst.rdata_shadow <= wrapper.uut.csr_minstret_value));
		end
	end


	// Once the checker has successfully shadowed a minstret read, the architectural
	// minstret value must have advanced beyond that shadow.
	always @(posedge clock) begin
		if (!reset) begin
			h_minstret_strictly_ahead_of_shadow: assert(!checker_inst.csr_read_shadowed || (wrapper.uut.csr_minstret_value > checker_inst.rdata_shadow));
		end
	end

/// Helper Assertion End
endmodule
