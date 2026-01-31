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

	// If the core reports a trap while the retired instruction matches this instruction model,
	// the spec must also indicate a trap (otherwise the RVFI payload is inconsistent/unreachable).
	always @(posedge clock) begin
		if (!reset && check && wrapper.trap && checker_inst.spec_valid) begin
			h_trap_implies_spec_trap: assert(checker_inst.spec_trap);
		end
	end

	// We use $past(..., 2) below; gate it so it's never sampled too early.
	reg [1:0] h_past_valid;
	always @(posedge clock) begin
		if (reset)
			h_past_valid <= 0;
		else
			h_past_valid <= {h_past_valid[0], 1'b1};
	end

	// A non-trapping LW must have come from the ldmem state two cycles earlier.
	// This blocks unreachable traces where RVFI claims LW without ever performing a data read.
	always @(posedge clock) begin
		if (!reset && h_past_valid[1] && check && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_lw_retires_from_ldmem: assert($past(wrapper.uut.cpu_state, 2) == 8'b00000001);
		end
	end

	// The data-memory address used by the core during ldmem must match the ISA-level spec address.
	always @(posedge clock) begin
		if (!reset && h_past_valid[1] && check && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_lw_bus_addr_matches_spec: assert(`rvformal_addr_eq($past(wrapper.uut.mem_addr, 2), checker_inst.spec_mem_addr));
		end
	end

	// In the ldmem state, a data read uses the computed effective address (rs1 + imm) in reg_op1.
	always @(posedge clock) begin
		if (!reset && (wrapper.uut.cpu_state == 8'b00000001) && wrapper.uut.mem_do_rdata && wrapper.uut.dbg_rs1val_valid) begin
			h_reg_op1_is_eff_addr: assert(wrapper.uut.reg_op1 == (wrapper.uut.dbg_rs1val + wrapper.uut.dbg_insn_imm));
		end
	end

	// Once the memory FSM is in the read-transfer state for a data read, it must not be flagged as an instr fetch.
	always @(posedge clock) begin
		if (!reset) begin
			h_dmem_read_not_imem: assert(!(wrapper.uut.mem_do_rdata && (wrapper.uut.mem_state == 2'd1) && wrapper.uut.mem_instr));
		end
	end

/// Helper Assertion End
endmodule
