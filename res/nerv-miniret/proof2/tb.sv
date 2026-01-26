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
	// The checker only latches rdata_shadow after assuming it is below the
	// no-overflow bound. Induction can otherwise invent unreachable states with
	// csr_read_shadowed=1 and an arbitrarily large rdata_shadow.
	always @(posedge clock) begin
		if (!reset) begin
			h_shadow_rdata_bounded: assert(!checker_inst.csr_read_shadowed || checker_inst.rdata_shadow[31:0] < 32'hF000_0000);
			// After the first shadowed minstret read, the live minstret counter must
			// be strictly greater than the shadowed old value.
			h_shadow_lt_minstret: assert(!checker_inst.csr_read_shadowed || checker_inst.rdata_shadow[31:0] < wrapper.uut.csr_minstret_value);
		end
	end

	// The minstret CSR is an up-counter.
	// Note: RVFI CSR rdata can be don't-care unless the instruction actually
	// performs a CSR read of minstret.
	always @(posedge clock) begin
		if (!reset) begin
			// When a CSR read of minstret is executed, the RVFI-exposed rdata must
			// reflect the current minstret value.
			if (checker_inst.csr_read_valid && checker_inst.csr_insn_under_test && !$past(reset)) begin
				h_minstret_rdata_matches: assert(checker_inst.csr_insn_rdata[31:0] == $past(wrapper.uut.csr_minstret_value));
			end

			// Each retired instruction increments minstret by 1 (no overflow assumed).
			if (rvfi_valid && !$past(reset)) begin
				h_minstret_increments: assert(wrapper.uut.csr_minstret_value == $past(wrapper.uut.csr_minstret_value) + 32'd1);
			end
		end
	end

/// Helper Assertion End
endmodule
