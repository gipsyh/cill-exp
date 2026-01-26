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
	reg h_past_valid;
	reg [31:0] h_shadow_age;

	wire h_shadow_capture = !check && checker_inst.csr_read_valid && checker_inst.csr_insn_under_test;

	always @(posedge clock) begin
		if (reset) begin
			h_past_valid <= 0;
			h_shadow_age <= 0;
		end else begin
			h_past_valid <= 1;
			if (!checker_inst.csr_read_shadowed) begin
				h_shadow_age <= 0;
			end else if (h_shadow_capture) begin
				h_shadow_age <= 0;
			end else begin
				if (&h_shadow_age)
					h_shadow_age <= h_shadow_age;
				else
					h_shadow_age <= h_shadow_age + 1;
			end
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			if (h_past_valid && !wrapper.uut.reset_q && !$past(wrapper.uut.reset_q)) begin
				h_mcycle_incr: assert(wrapper.uut.csr_mcycle_value == $past(wrapper.uut.csr_mcycle_value) + 1);
			end

			if (h_past_valid && $past(h_shadow_capture)) begin
				h_shadow_follows_capture: assert(checker_inst.rdata_shadow == $past(checker_inst.csr_insn_rdata));
			end

			if (checker_inst.csr_read_shadowed) begin
				h_shadow_le_mcycle: assert(checker_inst.rdata_shadow <= wrapper.uut.csr_mcycle_value);
			end
		end
	end

/// Helper Assertion End
endmodule
