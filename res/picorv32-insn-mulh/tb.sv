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

	// If the core reports a trap, the retired instruction must either be outside the
	// modeled instruction (spec_valid==0) or be a modeled trapping instruction.
	// This blocks unreachable states where the core "traps" while reporting a
	// non-trapping modeled instruction such as MULH.
	always @(posedge clock) begin
		if (!reset) begin
			h_trap_implies_spec_trap: assert (!wrapper.trap || !checker_inst.spec_valid || checker_inst.spec_trap);
		end
	end

	// latched_stalu is only asserted for ALU write-backs, which also assert latched_store.
	// Unreachable states can otherwise "remember" latched_stalu without an active store.
	always @(posedge clock) begin
		if (!reset) begin
			h_stalu_implies_store: assert (!wrapper.uut.latched_stalu || wrapper.uut.latched_store);
		end
	end

	// MULH is handled via the PCPI fast multiplier and writes back via reg_out (not alu_out_q).
	wire h_is_mulh = (wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011) &&
	                 (wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001) &&
	                 (wrapper.uut.dbg_insn_opcode[14:12] == 3'b001);
	wire h_pcpi_insn_is_mulh = (wrapper.uut.pcpi_insn[6:0] == 7'b0110011) &&
	                          (wrapper.uut.pcpi_insn[31:25] == 7'b0000001) &&
	                          (wrapper.uut.pcpi_insn[14:12] == 3'b001);
	always @(posedge clock) begin
		if (!reset) begin
			h_mulh_writeback_not_stalu: assert (!(wrapper.uut.cpuregs_write && h_is_mulh) || !wrapper.uut.latched_stalu);
		end
	end

	// For a MULH write-back, the operands reported via RVFI (dbg_rs*val) must match the
	// operands presented to the PCPI multiplier (pcpi_rs*), otherwise the result can
	// be computed from a different operand pair.
	always @(posedge clock) begin
		if (!reset) begin
			h_mulh_operands_match_pcpi: assert (!(wrapper.uut.cpuregs_write && h_is_mulh) ||
				((wrapper.uut.pcpi_rs1 == wrapper.uut.dbg_rs1val) && (wrapper.uut.pcpi_rs2 == wrapper.uut.dbg_rs2val)));
		end
	end

	// Expected MULH result under RISCV_FORMAL_ALTOPS (see riscv-formal insn model).
	wire [31:0] h_mulh_expected_wdata = (wrapper.uut.dbg_rs1val + wrapper.uut.dbg_rs2val) ^ 32'hf6583fb7;

	// When writing back a MULH result, the data presented to the register file must
	// already equal the modeled result (otherwise RVFI can report a stale/incorrect
	// value at retirement).
	always @(posedge clock) begin
		if (!reset) begin
			h_mulh_wdata_matches_model: assert (!(wrapper.uut.cpuregs_write && h_is_mulh) ||
				(wrapper.uut.cpuregs_wrdata == h_mulh_expected_wdata));
		end
	end

	// While executing MULH via PCPI, the multiplier operands must already match the
	// captured debug operands; otherwise the multiplier can compute a result that
	// disagrees with RVFI.
	always @(posedge clock) begin
		if (!reset) begin
			h_mulh_operands_match_pcpi_exec: assert (!(wrapper.uut.pcpi_valid && h_pcpi_insn_is_mulh) ||
				((wrapper.uut.pcpi_rs1 == wrapper.uut.dbg_rs1val) && (wrapper.uut.pcpi_rs2 == wrapper.uut.dbg_rs2val)));
		end
	end

	// MULH needs both source operands; by the time it writes back, the debug operand
	// capture must be marked valid.
	always @(posedge clock) begin
		if (!reset) begin
			h_mulh_dbg_operands_valid: assert (!(wrapper.uut.cpuregs_write && h_is_mulh) ||
				(wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid));
		end
	end

	// If the PCPI multiplier is executing MULH with an x0 source, the corresponding
	// operand must be zero (even if some debug/RVFI nets carry arbitrary values for x0).
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.pcpi_valid && h_pcpi_insn_is_mulh) begin
				if (wrapper.uut.pcpi_insn[19:15] == 0)
					h_pcpi_mulh_rs1_x0_is_zero: assert (wrapper.uut.pcpi_rs1 == 0);
				if (wrapper.uut.pcpi_insn[24:20] == 0)
					h_pcpi_mulh_rs2_x0_is_zero: assert (wrapper.uut.pcpi_rs2 == 0);
			end
		end
	end

	// Keep the instruction word consistent between the debug/RVFI stream and the
	// PCPI path while a MULH is in flight. This ensures the checker and the PCPI
	// multiplier agree on rs1/rs2/rd fields (including x0 handling).
	always @(posedge clock) begin
		if (!reset) begin
			h_mulh_pcpi_insn_equals_dbg: assert (!(h_is_mulh && (wrapper.uut.pcpi_valid || wrapper.uut.cpuregs_write)) ||
				(wrapper.uut.pcpi_insn == wrapper.uut.dbg_insn_opcode));
		end
	end

	// The PCPI result "ready" handshake is only meaningful while the core is in the
	// PCPI execution state. This excludes unreachable states with a permanently-high
	// ready signal that can desynchronize the RVFI write-back.
	always @(posedge clock) begin
		if (!reset) begin
			h_pcpi_ready_in_ld_rs1: assert (!wrapper.uut.pcpi_int_ready || wrapper.uut.cpu_state == 8'b0010_0000);
		end
	end

	// PCPI "ready" must only occur in response to an active PCPI transaction.
	always @(posedge clock) begin
		if (!reset) begin
			h_pcpi_ready_implies_valid: assert (!wrapper.uut.pcpi_int_ready || wrapper.uut.pcpi_valid);
			h_pcpi_valid_implies_trap: assert (!wrapper.uut.pcpi_valid || wrapper.uut.instr_trap);
		end
	end

	// When completing a MULH instruction via PCPI, the PCPI instruction must also be MULH.
	always @(posedge clock) begin
		if (!reset) begin
			h_mulh_pcpi_insn_match: assert (!h_is_mulh || !wrapper.uut.pcpi_int_ready || h_pcpi_insn_is_mulh);
		end
	end

	// Keep the debug pipeline aligned: dbg_next is the registered launch_next_insn.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_dbg_next_follows_launch: assert (wrapper.uut.dbg_next == $past(wrapper.uut.launch_next_insn));
		end
	end

	// Launching a MULH must enter the PCPI execution path (ld_rs1) in the next state.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.dbg_valid_insn) begin
			h_mulh_launch_in_ld_rs1: assert (!wrapper.uut.dbg_next || !h_is_mulh || wrapper.uut.cpu_state == 8'b0010_0000);
		end
	end

	// In fetch, a pending write-back (latched_store) must drive cpuregs_write.
	always @(posedge clock) begin
		if (!reset) begin
			h_store_implies_cpuregs_write: assert (!(wrapper.uut.cpu_state == 8'b0100_0000 && wrapper.uut.latched_store) || wrapper.uut.cpuregs_write);
		end
	end

	// Keep the architectural destination register aligned with the debug/RVFI instruction
	// stream. For a MULH in flight, the latched destination register must match the rd
	// field of the current instruction.
	always @(posedge clock) begin
		if (!reset) begin
			h_mulh_latched_rd_matches_dbg: assert (
				!(h_is_mulh && (wrapper.uut.pcpi_valid || wrapper.uut.cpuregs_write)) ||
				(wrapper.uut.latched_rd == wrapper.uut.dbg_insn_opcode[11:7])
			);
		end
	end

	// For MULH with rd=x0, the core must report a zero write-back value once the
	// instruction has completed (back in fetch with no pending store/writeback).
	always @(posedge clock) begin
		if (!reset) begin
			h_mulh_rd0_wdata_zero: assert (
				!(h_is_mulh &&
				  (wrapper.uut.dbg_insn_opcode[11:7] == 0) &&
				  (wrapper.uut.cpu_state == 8'b0100_0000) &&
				  !wrapper.uut.pcpi_valid &&
				  !wrapper.uut.latched_store &&
				  !wrapper.uut.cpuregs_write) ||
				(wrapper.uut.rvfi_rd_wdata == 0)
			);
		end
	end

	// Once the debug operand capture is marked valid, it must remain stable until the
	// next instruction is launched (launch_next_insn), otherwise RVFI operands can
	// become desynchronized from the computed result.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if ($past(wrapper.uut.dbg_rs1val_valid) && $past(wrapper.uut.dbg_rs2val_valid) && !$past(wrapper.uut.launch_next_insn)) begin
				h_dbg_rs_stable_no_launch: assert (
					(wrapper.uut.dbg_rs1val == $past(wrapper.uut.dbg_rs1val)) &&
					(wrapper.uut.dbg_rs2val == $past(wrapper.uut.dbg_rs2val))
				);
			end
		end
	end

/// Helper Assertion End
endmodule
