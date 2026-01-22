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
	// The DUT has an internal reset stretch (`reset_q`) that can stay high while
	// stalled. While it is high, RVFI outputs are forced to their reset values.
	always @(posedge clock) begin
		if (!reset) begin
			h_resetq_forces_rvfi: assert(!wrapper.uut.reset_q || ((rvfi_order == 0) && (rvfi_valid == 0)));
		end
	end

	// found_non_causal can only become 1 after observing an instruction with
	// rvfi_order > insn_order that uses register_index. On steps where rvfi_order
	// did not decrease (i.e. no wrap/decrease this step), that implies we've
	// already advanced past insn_order.
	always @(posedge clock) begin
		if (!reset && !rvfi_order_loopback && !wrapper.uut.reset_q && $past(!reset && !wrapper.uut.reset_q)) begin
			if (rvfi_order >= $past(rvfi_order)) begin
				h_found_implies_past_insn_order: assert(!checker_inst.found_non_causal || (rvfi_order > checker_inst.insn_order));
			end
		end
	end

/// Helper Assertion End
endmodule
