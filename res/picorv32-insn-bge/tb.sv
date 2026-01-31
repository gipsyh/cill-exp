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
	// With COMPRESSED_ISA enabled, the core only fetches/executes halfword-aligned PCs.
	// Guard with rvfi_valid to avoid constraining irrelevant/unstable values.
	localparam [7:0] h_cpu_state_exec = 8'h08;
	localparam [7:0] h_cpu_state_fetch = 8'h40;
	localparam [7:0] h_cpu_state_ld_rs1 = 8'h20;
	localparam [7:0] h_cpu_state_ld_rs2 = 8'h10;
	localparam [7:0] h_cpu_state_trap = 8'h80;
	always @(posedge clock) begin
		if (!reset) begin
			// With COMPRESSED_ISA enabled, all architectural PCs remain halfword-aligned.
			h_reg_pc_halfword_aligned: assert (wrapper.uut.reg_pc[0] == 1'b0);
			h_reg_next_pc_halfword_aligned: assert (wrapper.uut.reg_next_pc[0] == 1'b0);

				if (!$past(reset)) begin
					// IRQs are disabled in this configuration (ENABLE_IRQ=0), so the IRQ FSM must stay idle.
					h_irq_state_idle: assert (wrapper.uut.irq_state == 2'b00);

					// dbg_insn_addr is initialized by the first launched instruction; ignore the cycle right after reset.
					if (wrapper.uut.dbg_valid_insn) begin
						h_dbg_insn_addr_halfword_aligned: assert (wrapper.uut.dbg_insn_addr[0] == 1'b0);
					end
					h_dbg_next_tracks_launch_next_insn: assert (wrapper.uut.dbg_next == $past(wrapper.uut.launch_next_insn));

					// When an instruction is launched, dbg_insn_addr and reg_pc are updated to the same PC.
					if ($past(wrapper.uut.launch_next_insn)) begin
						h_dbg_insn_addr_matches_reg_pc_after_launch: assert (wrapper.uut.dbg_insn_addr == wrapper.uut.reg_pc);
					end

					// dbg_rs*val should be stable while its corresponding valid flag stays asserted.
					if (wrapper.uut.dbg_rs1val_valid && $past(wrapper.uut.dbg_rs1val_valid)) begin
						h_dbg_rs1val_stable_while_valid: assert (wrapper.uut.dbg_rs1val == $past(wrapper.uut.dbg_rs1val));
					end
					if (wrapper.uut.dbg_rs2val_valid && $past(wrapper.uut.dbg_rs2val_valid)) begin
						h_dbg_rs2val_stable_while_valid: assert (wrapper.uut.dbg_rs2val == $past(wrapper.uut.dbg_rs2val));
					end

					// In fetch, a non-JAL instruction must transition to LD_RS1 after the decoder triggers.
					if ($past(wrapper.uut.cpu_state == h_cpu_state_fetch &&
					          wrapper.uut.decoder_trigger &&
					          !wrapper.uut.instr_jal)) begin
					h_fetch_progresses_to_ld_rs1: assert (wrapper.uut.cpu_state == h_cpu_state_ld_rs1);
				end

					// When retiring a BGE, both source operands must have been captured for RVFI.
					if (wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn &&
					    wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100011 &&
					    wrapper.uut.dbg_insn_opcode[14:12] == 3'b101) begin
						h_retire_bge_has_rs_operands: assert (wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid);
					end

					// x0 must read as zero for the retired BGE (prevents spurious mismatches in the spec compare).
					if (wrapper.uut.dbg_valid_insn &&
					    wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100011 &&
					    wrapper.uut.dbg_insn_opcode[14:12] == 3'b101) begin
						if (wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_insn_opcode[19:15] == 5'd0) begin
							h_bge_rs1_x0_reads_zero: assert (wrapper.uut.dbg_rs1val == 32'd0);
						end
						if (wrapper.uut.dbg_rs2val_valid && wrapper.uut.dbg_insn_opcode[24:20] == 5'd0) begin
							h_bge_rs2_x0_reads_zero: assert (wrapper.uut.dbg_rs2val == 32'd0);
						end
					end

					// For a retired 32-bit BGE, next_pc is determined by (pc + imm) when the signed compare holds,
					// otherwise it falls through by 4. (Matches the riscv-formal insn_bge spec model.)
					if (wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn &&
					    wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100011 &&
					    wrapper.uut.dbg_insn_opcode[14:12] == 3'b101) begin
						logic signed [31:0] h_bge_imm;
						logic        [31:0] h_bge_expected_next_pc;
						h_bge_imm = $signed({wrapper.uut.dbg_insn_opcode[31],
						                     wrapper.uut.dbg_insn_opcode[7],
						                     wrapper.uut.dbg_insn_opcode[30:25],
						                     wrapper.uut.dbg_insn_opcode[11:8],
						                     1'b0});

						h_bge_expected_next_pc = ($signed(wrapper.uut.dbg_rs1val_valid ? wrapper.uut.dbg_rs1val : 32'd0) >=
						                          $signed(wrapper.uut.dbg_rs2val_valid ? wrapper.uut.dbg_rs2val : 32'd0)) ?
							(wrapper.uut.dbg_insn_addr + h_bge_imm) : (wrapper.uut.dbg_insn_addr + 32'd4);

						// Only constrain the non-trapping case (riscv-formal checks pc_wdata only when !spec_trap).
						if (h_bge_expected_next_pc[0] == 1'b0) begin
							h_retire_bge_next_pc_matches_spec: assert (wrapper.uut.next_pc == h_bge_expected_next_pc);
						end
					end

				// Second-word instruction fetch completes in one transfer; mem_la_secondword must clear.
				if ($past(wrapper.uut.mem_la_secondword && wrapper.uut.mem_xfer)) begin
					h_mem_la_secondword_clears_after_xfer: assert (!wrapper.uut.mem_la_secondword);
				end

				// After completing the second word transfer of an instruction fetch, the memory FSM returns to idle.
				if ($past(wrapper.uut.mem_state == 2'd1 &&
				          wrapper.uut.mem_xfer &&
				          wrapper.uut.mem_la_secondword &&
				          wrapper.uut.mem_do_rinst)) begin
					h_mem_state_exits_after_secondword: assert (wrapper.uut.mem_state == 2'd0);
				end
			end

				// During instruction execution (i.e., non-fetch states), dbg_insn_addr should track reg_pc.
				if (wrapper.uut.cpu_state != h_cpu_state_fetch) begin
					h_dbg_insn_addr_matches_reg_pc: assert (wrapper.uut.dbg_insn_addr == wrapper.uut.reg_pc);
				end

					// While an instruction is in flight (non-fetch/non-trap), reg_next_pc keeps the fall-through PC.
					if (wrapper.uut.cpu_state != h_cpu_state_fetch && wrapper.uut.cpu_state != h_cpu_state_trap) begin
						h_nonfetch_fallthrough_pc: assert (wrapper.uut.reg_next_pc ==
						wrapper.uut.reg_pc + (wrapper.uut.latched_compr ? 32'd2 : 32'd4));

					// latched_compr is the instruction-length bit for the *current* instruction.
					// It must agree with the low bits of the decoded/latched instruction word.
					if (wrapper.uut.dbg_valid_insn) begin
						h_latched_compr_matches_insn_len: assert (wrapper.uut.latched_compr ==
							(wrapper.uut.dbg_insn_opcode[1:0] != 2'b11));
					end
				end

				// For branch instructions, reg_next_pc holds the fall-through PC (pc + 2/4) while executing.
					if (wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu &&
					    (wrapper.uut.cpu_state == h_cpu_state_ld_rs1 ||
					     wrapper.uut.cpu_state == h_cpu_state_ld_rs2 ||
					     wrapper.uut.cpu_state == h_cpu_state_exec)) begin
						h_branch_fallthrough_pc: assert (wrapper.uut.reg_next_pc ==
							wrapper.uut.reg_pc + (wrapper.uut.compressed_instr ? 32'd2 : 32'd4));

						// For 32-bit branches, decoded register indices must match the instruction word (RVFI sees this word).
						// (Compressed branches use a different encoding and have latched_compr=1.)
						if (wrapper.uut.dbg_valid_insn && !wrapper.uut.latched_compr) begin
							h_branch_rs1_matches_insn: assert (wrapper.uut.decoded_rs1 == wrapper.uut.dbg_insn_opcode[19:15]);
							h_branch_rs2_matches_insn: assert (wrapper.uut.decoded_rs2 == wrapper.uut.dbg_insn_opcode[24:20]);
						end

					end

			if (rvfi_valid[0]) begin
				h_pc_rdata_halfword_aligned: assert (rvfi_pc_rdata[0] == 1'b0);
				h_pc_wdata_halfword_aligned: assert (rvfi_pc_wdata[0] == 1'b0);

				// If the instruction is valid per the spec model and not trapping, the core must not raise trap.
				if (checker_inst.spec_valid && !checker_inst.spec_trap) begin
					h_no_unexpected_trap: assert (!wrapper.uut.trap);
				end

			end

				// Branch comparisons in cpu_state_exec require both source operands to have been read.
				if (wrapper.uut.cpu_state == h_cpu_state_exec && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu) begin
					h_exec_branch_has_rs_operands: assert (wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid);
					// The RVFI operand values are sourced from dbg_rs*val; keep them consistent with the core operands.
					h_exec_branch_rs1_matches_op1: assert (wrapper.uut.dbg_rs1val == wrapper.uut.reg_op1);
					h_exec_branch_rs2_matches_op2: assert (wrapper.uut.dbg_rs2val == wrapper.uut.reg_op2);
				end
		end
	end

/// Helper Assertion End
endmodule
