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

// The testbench contains an existing assumption that references
// `dut.csr_minstret_value`. In this harness the core instance is
// `wrapper.uut`, so we provide a small named scope `dut` that exposes
// the expected hierarchical name.
generate
	if (1) begin : dut
		wire [31:0] csr_minstret_value = wrapper.uut.csr_minstret_value;
	end
endgenerate

// Inductive strengthening: in all reachable states, the shadowed CSR read data
// is always below the configured no-overflow threshold.
always @(posedge clock) begin
	if (!reset) begin
		h_rdata_shadow_no_overflow: assert(checker_inst.rdata_shadow < 32'hF000_0000);
	end
end

reg h_minstret_prev_valid;
reg [31:0] h_minstret_prev;

always @(posedge clock) begin
	if (reset) begin
		h_minstret_prev_valid = 1'b0;
		h_minstret_prev = '0;
	end else begin
		if (h_minstret_prev_valid) begin
			h_minstret_monotonic: assert(wrapper.uut.csr_minstret_value >= h_minstret_prev);
			h_minstret_step_le_1: assert(wrapper.uut.csr_minstret_value <= h_minstret_prev + 32'd1);
		end
		h_minstret_prev = wrapper.uut.csr_minstret_value;
		h_minstret_prev_valid = 1'b1;
	end
end

reg h_past_valid;
always @(posedge clock) begin
	if (reset) begin
		h_past_valid <= 1'b0;
	end else begin
		h_past_valid <= 1'b1;
	end
end

// Relate CSR read data to the architectural minstret counter.
// For a retiring CSR-read of minstret, the read data is the pre-increment
// value and the counter visible in the same cycle is +1.
always @(posedge clock) begin
	if (!reset) begin
		if (rvfi_valid && checker_inst.csr_read_valid && checker_inst.csr_insn_under_test) begin
			h_minstret_rdata_plus1: assert(wrapper.uut.csr_minstret_value == checker_inst.csr_insn_rdata + 32'd1);
		end
	end
end

// Once the checker has shadowed a CSR read of minstret, the architectural
// counter must already have advanced beyond that shadowed value.
always @(posedge clock) begin
	if (!reset) begin
		if (checker_inst.csr_read_shadowed) begin
			h_shadow_lt_minstret: assert(wrapper.uut.csr_minstret_value >= checker_inst.rdata_shadow + 32'd1);
		end
	end
end

// When an instruction retires (rvfi_valid), minstret must increment by 1.
// (In this core RVFI valid is aligned with the cycle in which the counter
// update becomes visible.)
always @(posedge clock) begin
	if (!reset && h_past_valid) begin
		if (rvfi_valid) begin
			h_minstret_incr_on_retire: assert(wrapper.uut.csr_minstret_value == $past(wrapper.uut.csr_minstret_value) + 32'd1);
		end
	end
end

// If the checker shadow-captures a CSR read (check==0), the next state's
// shadow register must reflect the captured read data.
always @(posedge clock) begin
	if (!reset && h_past_valid) begin
		if ($past(!check && rvfi_valid && checker_inst.csr_read_valid && checker_inst.csr_insn_under_test)) begin
			h_shadow_updates_rdata: assert(checker_inst.rdata_shadow == $past(checker_inst.csr_insn_rdata));
		end
	end
end

/// Helper Assertion End
endmodule
