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

	always @(posedge clock) begin
		// Only constrain the RVFI memory address when the checker is actively
		// validating a retiring, non-trapping instruction with a memory access.
		if (!reset && check && checker_inst.valid && checker_inst.spec_valid &&
				!checker_inst.spec_trap && !checker_inst.mem_access_fault) begin
			h_no_rvfi_trap_on_spec_notrap: assert (!rvfi_trap);
			h_rvfi_mem_addr_word_aligned: assert (rvfi_mem_addr[1:0] == 2'b00);
			// For retiring LH, PicoRV32 should not be performing an instruction fetch
			// (single-ported memory interface); the memory interface is used for data.
			h_no_mem_instr_on_lh_retire: assert (!wrapper.mem_instr);
			// The RVFI rs1 value is sourced from dbg_rs1val (captured earlier in the
			// pipeline). dbg_rs1val_valid may already be cleared on the retirement
			// cycle, so check the previous cycle.
			h_lh_rs1val_valid: assert (rvfi_insn[19:15] == 0 || $past(wrapper.uut.dbg_rs1val_valid));
		end
	end

	// Constrain the data bus address for LH at the actual memory transfer cycle.
	always @(posedge clock) begin
		if (!reset && check &&
				wrapper.uut.cpu_state == 8'h01 && // ldmem
				wrapper.mem_valid && wrapper.mem_ready && !wrapper.mem_instr &&
				(wrapper.uut.dbg_insn_opcode[6:0] == 7'b0000011) &&
				(wrapper.uut.dbg_insn_opcode[14:12] == 3'b001)) begin
			h_lh_dbg_rs1val_zero_for_x0: assert (
				(wrapper.uut.dbg_insn_opcode[19:15] != 0) || (wrapper.uut.dbg_rs1val == 32'd0)
			);
			h_lh_bus_addr_matches_spec: assert (
				wrapper.mem_addr == ((wrapper.uut.dbg_rs1val +
					{{20{wrapper.uut.dbg_insn_opcode[31]}}, wrapper.uut.dbg_insn_opcode[31:20]}) & 32'hffff_fffc)
			);
		end
	end

	// When an instruction retires normally, it was launched from fetch state in the
	// previous cycle. (cpu_state may advance on the retirement edge.)
	always @(posedge clock) begin
		if (!reset && rvfi_valid && !rvfi_trap) begin
			h_rvfi_valid_nontrap_in_fetch: assert ($past(wrapper.uut.cpu_state) == 8'h40);
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			// cpu_state is one-hot encoded.
			h_cpu_state_valid: assert (
				wrapper.uut.cpu_state == 8'h80 || // trap
				wrapper.uut.cpu_state == 8'h40 || // fetch
				wrapper.uut.cpu_state == 8'h20 || // ld_rs1
				wrapper.uut.cpu_state == 8'h10 || // ld_rs2
				wrapper.uut.cpu_state == 8'h08 || // exec
				wrapper.uut.cpu_state == 8'h04 || // shift
				wrapper.uut.cpu_state == 8'h02 || // stmem
				wrapper.uut.cpu_state == 8'h01    // ldmem
			);
		end
	end

/// Helper Assertion End
endmodule
