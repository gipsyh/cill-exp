`default_nettype none
`include "defines.sv"

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
	always@(posedge clock) begin
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

	// Helper invariants for MUL retire.
	// These should hold for all reachable states and help eliminate CTIs where
	// internal bookkeeping is inconsistent with the retiring MUL instruction.
	wire h_mul_retire = checker_inst.spec_valid;

	// When a new instruction is launched (launch_next_insn) while dbg_valid_insn is high,
	// the previous instruction is about to retire on the next cycle (rvfi_valid will assert).
	// For MUL, the writeback data must already match the ALTOPS result computed from the
	// captured operand values (dbg_rs*val).
	wire h_is_mul_insn =
			(wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011) &&
			(wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001) &&
			(wrapper.uut.dbg_insn_opcode[14:12] == 3'b000);
	wire [4:0]  h_mul_dbg_rd = wrapper.uut.dbg_insn_opcode[11:7];
	wire [31:0] h_mul_altops_result = (wrapper.uut.dbg_rs1val + wrapper.uut.dbg_rs2val) ^ 32'h5876063e;
	wire h_pcpi_insn_is_mul =
			(wrapper.uut.pcpi_insn[6:0] == 7'b0110011) &&
			(wrapper.uut.pcpi_insn[31:25] == 7'b0000001) &&
			(wrapper.uut.pcpi_insn[14:12] == 3'b000);

	// When the MUL PCPI core is ready, its output must implement the ALTOPS semantics.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'h20 /* cpu_state_ld_rs1 */ &&
				wrapper.uut.instr_trap && wrapper.uut.pcpi_mul_ready && h_pcpi_insn_is_mul) begin
			h_mul_pcpi_int_rd_match: assert(wrapper.uut.pcpi_int_rd ==
					((wrapper.uut.pcpi_rs1 + wrapper.uut.pcpi_rs2) ^ 32'h5876063e));
		end
	end

	// For M-extension ops handled via PCPI, pcpi_insn must match the decoded instruction.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'h20 /* cpu_state_ld_rs1 */ && wrapper.uut.instr_trap && h_is_mul_insn) begin
			h_mul_pcpi_insn_is_mul: assert(h_pcpi_insn_is_mul);
			// The div core must not spuriously claim readiness for a MUL instruction.
			h_mul_pcpi_div_not_ready: assert(!wrapper.uut.pcpi_div_ready);
		end
	end

	always @(posedge clock) begin
		if (!reset && wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn && h_is_mul_insn) begin
			// For a retiring MUL, both source operands must have been captured.
			h_mul_pre_retire_operands_valid: assert(wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid);

			// Architectural x0 reads must return zero.
			if (wrapper.uut.dbg_insn_opcode[19:15] == 0) begin
				h_mul_rs1_x0_zero: assert(wrapper.uut.dbg_rs1val == 0);
			end
			if (wrapper.uut.dbg_insn_opcode[24:20] == 0) begin
				h_mul_rs2_x0_zero: assert(wrapper.uut.dbg_rs2val == 0);
			end
		end

		if (!reset && wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn &&
				h_is_mul_insn && wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid &&
				(h_mul_dbg_rd == 0)) begin
			h_mul_pre_retire_rd0_wdata_zero: assert(wrapper.uut.rvfi_rd_wdata == 0);
		end
	end

	// In fetch, after the MUL writeback cycle has completed (latched_store cleared),
	// rvfi_rd_wdata must already contain the correct result for the retiring MUL.
	always @(posedge clock) begin
		// The MUL writeback cycle uses the latched_store path, which must assert cpuregs_write.
		if (!reset && wrapper.uut.cpu_state == 8'h40 /* cpu_state_fetch */ &&
				wrapper.uut.dbg_valid_insn && h_is_mul_insn &&
				wrapper.uut.latched_store) begin
			// MUL is not a control-flow instruction; latched_branch must be clear during writeback.
			h_mul_wb_not_branch: assert(!wrapper.uut.latched_branch);
			// MUL writeback comes from reg_out (PCPI), not the ALU.
			h_mul_wb_not_alu: assert(!wrapper.uut.latched_stalu);
			h_mul_wb_cycle_cpuregs_write: assert(wrapper.uut.cpuregs_write);
		end

		// When we are in the writeback cycle for a MUL, the written data must come from the
		// PCPI result computed in the previous ld_rs1 cycle.
		if (!reset && $past(!reset) &&
				wrapper.uut.cpu_state == 8'h40 /* cpu_state_fetch */ &&
				wrapper.uut.dbg_valid_insn && h_is_mul_insn &&
				wrapper.uut.latched_store && !wrapper.uut.latched_branch) begin
			h_mul_wb_prev_state_ld_rs1: assert($past(wrapper.uut.cpu_state) == 8'h20 /* cpu_state_ld_rs1 */);
			h_mul_wb_prev_pcpi_ready: assert($past(wrapper.uut.pcpi_mul_ready));
			h_mul_wb_wrdata_from_pcpi: assert(wrapper.uut.cpuregs_wrdata == $past(wrapper.uut.pcpi_int_rd));
		end

		if (!reset && wrapper.uut.cpu_state == 8'h40 /* cpu_state_fetch */ &&
				wrapper.uut.dbg_valid_insn && h_is_mul_insn &&
				wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid &&
				!wrapper.uut.latched_store && !wrapper.uut.cpuregs_write) begin
			if (h_mul_dbg_rd != 0) begin
				h_mul_fetch_holds_rd_wdata: assert(wrapper.uut.rvfi_rd_wdata == h_mul_altops_result);
			end else begin
				h_mul_fetch_rd0_wdata_zero: assert(wrapper.uut.rvfi_rd_wdata == 0);
			end
		end
	end

	always @(posedge clock) begin
		if (!reset && h_mul_retire) begin
			// If the destination is non-zero, the result is architecturally visible and
			// the implementation must provide the correct operands to the spec model.
			if (checker_inst.spec_rd_addr != 0 && $past(!reset, 2)) begin
				// RVFI samples operand values from the previous cycle's debug capture.
				h_mul_src_operands_valid: assert($past(wrapper.uut.dbg_rs1val_valid) && $past(wrapper.uut.dbg_rs2val_valid));

				// MUL writeback comes from the PCPI result path (reg_out), not the ALU.
				h_mul_writeback_not_alu: assert(!wrapper.uut.latched_stalu);
			end
		end
	end

	// Track whether we've observed a register-file writeback since the last RVFI retirement.
	// For MUL, a writeback event must occur before the instruction is reported via rvfi_valid.
	reg h_wb_seen;
	always @(posedge clock) begin
		if (reset) begin
			h_wb_seen <= 0;
		end else begin
			if (wrapper.uut.rvfi_valid) begin
				h_wb_seen <= 0;
			end else if (wrapper.uut.cpuregs_write) begin
				h_wb_seen <= 1;
			end
		end
	end

	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid) begin
			h_mul_requires_wb_seen: assert(h_wb_seen);
		end
	end

	// Special-case: MUL writing to x0 must report rd_wdata==0.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && (wrapper.uut.rvfi_insn[11:7] == 0)) begin
			h_mul_rd0_wdata_zero: assert(wrapper.uut.rvfi_rd_wdata == 0);
		end
	end

	// Structural invariant: latched_stalu is only asserted by the ALU execute state.
	// This blocks CTIs where latched_stalu spuriously persists into consecutive fetch states.
	always @(posedge clock) begin
		if (!reset && $past(!reset) && wrapper.uut.latched_stalu) begin
			h_latched_stalu_from_exec: assert($past(wrapper.uut.cpu_state) == 8'h08 /* cpu_state_exec */);
		end
	end

	// Decode consistency for M-extension ops: when the current instruction (as reported to RVFI)
	// is an M-extension opcode, it must be handled via the PCPI/illegal-insn path.
	wire h_is_mext_op = (wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011) &&
			(wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001);

	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'h20 /* cpu_state_ld_rs1 */ && h_is_mext_op) begin
			h_mext_traps_into_pcpi: assert(wrapper.uut.instr_trap);
		end
	end

	// If the *previous* cycle decoded a JAL in fetch, then latched_branch must be set in the
	// current cycle (this is required for the JAL writeback mechanism).
	always @(posedge clock) begin
		if (!reset && $past(!reset) &&
				$past(wrapper.uut.cpu_state) == 8'h40 /* cpu_state_fetch */ &&
				$past(wrapper.uut.decoder_trigger) &&
				$past(wrapper.uut.instr_jal)) begin
			h_jal_sets_latched_branch: assert(wrapper.uut.latched_branch);
		end
	end

	// Structural invariants for the debug/RVFI pipeline.
	// Use explicit helper registers (instead of $past) so the invariants constrain
	// the state space directly during local proof.
	reg        h_launch_next_q;
	reg [31:0] h_dbg_insn_opcode_q;
	reg [31:0] h_next_pc_q;
	reg        h_pipe_ready;

	always @(posedge clock) begin
		if (reset) begin
			h_launch_next_q <= 0;
			h_dbg_insn_opcode_q <= 0;
			h_next_pc_q <= 0;
			h_pipe_ready <= 0;
		end else begin
			h_launch_next_q <= wrapper.uut.launch_next_insn;
			h_dbg_insn_opcode_q <= wrapper.uut.dbg_insn_opcode;
			h_next_pc_q <= wrapper.uut.next_pc;
			h_pipe_ready <= 1;
		end
	end

	always @(posedge clock) begin
		if (!reset && h_pipe_ready) begin
			h_dbg_next_tracks_launch: assert(wrapper.uut.dbg_next == h_launch_next_q);
			h_q_insn_tracks_dbg: assert(wrapper.uut.q_insn_opcode == h_dbg_insn_opcode_q);
			if (h_launch_next_q) begin
				h_dbg_addr_updates_on_launch: assert(wrapper.uut.dbg_insn_addr == h_next_pc_q);
			end
		end
	end

/// Helper Assertion End
endmodule
