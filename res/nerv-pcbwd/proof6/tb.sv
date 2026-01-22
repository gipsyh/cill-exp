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
	// Helper: `expect_pc_valid` can only become true after observing `insn_order+1`.
	// When no order loopback has happened yet, this implies the global `rvfi_order`
	// must have advanced strictly past `insn_order`.
	always @(posedge clock) begin
		if (!reset) begin
			h_expect_pc_valid_implies_order_gt:
				assert(!checker_inst.expect_pc_valid || rvfi_order_loopback || (checker_inst.rvfi_order > checker_inst.insn_order));
		end
	end

/// Helper Assertion End
endmodule
