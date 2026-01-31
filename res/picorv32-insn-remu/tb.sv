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

	// Helper: identify the REMU instruction encoding (used by RISCV_FORMAL_INSN_MODEL).
	wire h_is_remu = wrapper.uut.dbg_insn_opcode[6:0]   == 7'b0110011 &&
	                 wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001 &&
	                 wrapper.uut.dbg_insn_opcode[14:12] == 3'b111;
	// PCPI instruction word latched at decode time. This is the actual opcode
	// presented to the PCPI div unit.
	wire h_is_remu_pcpi = wrapper.uut.pcpi_insn[6:0]   == 7'b0110011 &&
	                      wrapper.uut.pcpi_insn[31:25] == 7'b0000001 &&
	                      wrapper.uut.pcpi_insn[14:12] == 3'b111;
	// Expected REMU result under RISCV_FORMAL_ALTOPS (mirrors picorv32_pcpi_div).
	wire [31:0] h_remu_alt_wdata = (wrapper.uut.pcpi_rs1 - wrapper.uut.pcpi_rs2) ^ 32'h3138_d0e1;

	// picorv32 internal one-hot CPU state encodings (mirrors ../picorv32.sv).
	localparam [7:0] h_cpu_state_trap = 8'b1000_0000;
	localparam [7:0] h_cpu_state_fetch = 8'b0100_0000;
	localparam [7:0] h_cpu_state_ld_rs1 = 8'b0010_0000;
	localparam [7:0] h_cpu_state_exec = 8'b0000_1000;

	// REMU is implemented via PCPI (instr_trap path). It should never be in the
	// ALU exec state, nor fall through into the trap state.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.dbg_valid_insn) begin
			h_remu_not_exec: assert (!(h_is_remu && wrapper.uut.cpu_state == h_cpu_state_exec));
			h_remu_not_trap: assert (!(h_is_remu && wrapper.uut.cpu_state == h_cpu_state_trap));
		end
	end

	// Once we are back in fetch state (no pending latched_store/branch), an instruction with rd=x0
	// must not have a non-zero RVFI rd_wdata lingering from another instruction.
	always @(posedge clock) begin
		if (!reset &&
		    wrapper.uut.cpu_state == h_cpu_state_fetch &&
		    !wrapper.uut.decoder_trigger &&
		    h_is_remu &&
		    wrapper.uut.dbg_insn_opcode[11:7] == 0 &&
		    !wrapper.uut.latched_store && !wrapper.uut.latched_branch) begin
			h_remu_x0_no_stale_wdata: assert(wrapper.uut.rvfi_rd_wdata == 0);
		end
	end

	// Any M-extension opcode (funct7=0000001, opcode=0110011) is not part of the base decoder set,
	// and should therefore be classified as instr_trap (PCPI path). We only check this when the
	// decoder is not in the middle of latching a new instruction (decoder_trigger=0) to avoid
	// transient mismatches between dbg_insn_opcode and the decoded instr_* flags.
	wire h_is_mext = &wrapper.uut.dbg_insn_opcode[1:0] &&
	                 wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011 &&
	                 wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001;
	always @(posedge clock) begin
		if (!reset && wrapper.uut.dbg_valid_insn && !wrapper.uut.decoder_trigger) begin
			h_mext_implies_instr_trap: assert(!(h_is_mext && !wrapper.uut.instr_trap));
		end
	end

	// During the PCPI trap path, the instruction presented to PCPI must match the
	// debug instruction opcode fields (otherwise RVFI and PCPI results can get out of sync).
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == h_cpu_state_ld_rs1 && wrapper.uut.instr_trap && &wrapper.uut.pcpi_insn[1:0]) begin
			h_pcpi_insn_fields_match_dbg: assert(wrapper.uut.pcpi_insn == wrapper.uut.dbg_insn_opcode);
		end
	end

	// Register x0 always reads as zero.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.pcpi_valid && &wrapper.uut.pcpi_insn[1:0]) begin
			if (wrapper.uut.pcpi_insn[19:15] == 0)
				h_pcpi_rs1_x0_is_zero: assert(wrapper.uut.pcpi_rs1 == 0);
			if (wrapper.uut.pcpi_insn[24:20] == 0)
				h_pcpi_rs2_x0_is_zero: assert(wrapper.uut.pcpi_rs2 == 0);
		end
	end

	// At REMU writeback time, the PCPI operand wires must still reflect the instruction's source regs.
	// In particular, if rs1/rs2 is x0, the corresponding operand must be zero even after pcpi_valid has dropped.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpuregs_write && h_is_remu) begin
			if (wrapper.uut.dbg_insn_opcode[19:15] == 0)
				h_remu_rs1_x0_writeback: assert(wrapper.uut.pcpi_rs1 == 0);
			if (wrapper.uut.dbg_insn_opcode[24:20] == 0)
				h_remu_rs2_x0_writeback: assert(wrapper.uut.pcpi_rs2 == 0);

			// The operand values reported via the debug/RVFI path must match the PCPI operand wires.
			// Otherwise, the spec computes the REMU result from different inputs than the core used.
			h_remu_dbg_operands_valid: assert(wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid);
			h_remu_operands_match_dbg: assert(wrapper.uut.pcpi_rs1 == wrapper.uut.dbg_rs1val &&
			                                  wrapper.uut.pcpi_rs2 == wrapper.uut.dbg_rs2val);
		end
	end

	// Once a REMU writeback has been recorded in the RVFI rd_* registers (rvfi_rd_addr != 0),
	// the stored rvfi_rd_wdata must be consistent with the captured operand values.
	wire [31:0] h_remu_dbg_result = (wrapper.uut.dbg_rs1val - wrapper.uut.dbg_rs2val) ^ 32'h3138_d0e1;
	always @(posedge clock) begin
		if (!reset && h_is_remu &&
		    wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid &&
		    (|rvfi_rd_addr) && (rvfi_rd_addr == wrapper.uut.dbg_insn_opcode[11:7])) begin
			h_remu_pending_wdata_matches_dbg: assert(rvfi_rd_wdata == h_remu_dbg_result);
		end
	end

	// For REMU (with RISCV_FORMAL_ALTOPS), the PCPI div unit must write back the altops result.
	always @(posedge clock) begin
		// `cpuregs_write` is asserted in fetch state when committing the previous instruction's writeback.
		if (!reset && $past(!reset) && wrapper.uut.dbg_valid_insn && wrapper.uut.cpuregs_write && h_is_remu_pcpi && $past(wrapper.uut.pcpi_valid)) begin
			h_remu_writeback_data: assert(wrapper.uut.cpuregs_wrdata == h_remu_alt_wdata);
		end
	end

	// RVFI retire (rvfi_valid) can be delayed relative to the core writeback due to memory latency.
	// Track that we've observed the REMU writeback (cpuregs_write) before allowing the RVFI retire.
	wire h_is_remu_rvfi = &rvfi_insn[1:0] &&
	                      rvfi_insn[6:0]   == 7'b0110011 &&
	                      rvfi_insn[31:25] == 7'b0000001 &&
	                      rvfi_insn[14:12] == 3'b111;
	reg h_remu_wrote;
	// Detect the writeback that corresponds to the retiring instruction (dbg_insn_opcode), not the
	// next decoded instruction (pcpi_insn can already have advanced when cpuregs_write fires).
	wire h_remu_writeback_now = wrapper.uut.cpuregs_write && h_is_remu && (|wrapper.uut.dbg_insn_opcode[11:7]);
	always @(posedge clock) begin
		if (reset) begin
			h_remu_wrote <= 0;
		end else begin
			// Clear once RVFI reports the retire of that REMU.
			if (rvfi_valid && h_is_remu_rvfi && (|rvfi_insn[11:7]) && !rvfi_trap)
				h_remu_wrote <= 0;
			else if (h_remu_writeback_now)
				h_remu_wrote <= 1;
		end
	end
	always @(posedge clock) begin
		// Require a writeback somewhere before (or in the same cycle as) the RVFI retire for rd != x0.
		if (!reset && rvfi_valid && h_is_remu_rvfi && (|rvfi_insn[11:7]) && !rvfi_trap) begin
			h_remu_retire_implies_writeback: assert(h_remu_wrote || h_remu_writeback_now);
		end
	end
	// If RVFI reports a REMU retire with rd != x0, the RD address must match the instruction's rd field.
	always @(posedge clock) begin
		if (!reset && rvfi_valid && h_is_remu_rvfi && (|rvfi_insn[11:7]) && !rvfi_trap) begin
			h_remu_rd_addr_match: assert(rvfi_rd_addr == rvfi_insn[11:7]);
		end
	end

	// When a writeback happens, the destination register should match the decoded rd field.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.dbg_valid_insn && wrapper.uut.cpuregs_write &&
		    &wrapper.uut.dbg_insn_opcode[1:0] && wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011) begin
			h_latched_rd_matches_dbg_rd: assert(wrapper.uut.latched_rd == wrapper.uut.dbg_insn_opcode[11:7]);
		end
	end

	// A PCPI div "ready" pulse must be causally preceded by a valid request.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_pcpi_div_ready_past_valid: assert(!(
				wrapper.uut.pcpi_div_ready && !$past(wrapper.uut.pcpi_valid)
			));
		end
	end

	// Likewise, the core-level PCPI "ready" (any PCPI unit) must be preceded by a valid request.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_pcpi_int_ready_past_valid: assert(!(
				wrapper.uut.pcpi_int_ready && !$past(wrapper.uut.pcpi_valid)
			));
		end
	end

	// When the core is in the PCPI trap path and observes a PCPI unit ready, it must be driving pcpi_valid.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == h_cpu_state_ld_rs1 && wrapper.uut.instr_trap && wrapper.uut.pcpi_int_ready) begin
			h_pcpi_ready_requires_valid: assert(wrapper.uut.pcpi_valid);
		end
	end

	// The div unit must only assert "wr" together with "ready".
	always @(posedge clock) begin
		if (!reset) begin
			h_pcpi_div_wr_implies_ready: assert(!(wrapper.uut.pcpi_div_wr && !wrapper.uut.pcpi_div_ready));
		end
	end

	// When an instruction has been fetched/decoded in fetch state (decoder_trigger),
	// the FSM must leave fetch on the next cycle for all non-JAL instructions.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_fetch_decoder_progress: assert(!(
				$past(wrapper.uut.cpu_state == h_cpu_state_fetch &&
				      wrapper.uut.decoder_trigger &&
				      !wrapper.uut.instr_jal) &&
				wrapper.uut.cpu_state == h_cpu_state_fetch
			));
		end
	end

/// Helper Assertion End
endmodule
