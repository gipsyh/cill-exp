`default_nettype none
`include "defines.sv"

module testbench (
	`ifdef RISCV_FORMAL_TRIG_CYCLE
		input trig,
	`endif
	input check,
	input clock, reset
);
	`RVFI_WIRES

	`RISCV_FORMAL_CHECKER checker_inst (
		.clock  (clock),
		.reset  (reset),
	`ifdef RISCV_FORMAL_TRIG_CYCLE
		.trig   (trig),
	`endif
		.check   (check),
		`RVFI_CONN
	);

	rvfi_wrapper wrapper (
		.clock (clock),
		.reset (reset),
		`RVFI_CONN
	);

	/// Helper Assertion Begin

	/// Helper Assertion End

endmodule
