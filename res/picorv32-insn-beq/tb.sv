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

	// (no direct behavioral helper for BEQ yet; focus on structural invariants)

	// RVFI fields are registered from PicoRV32 debug signals; after the first
	// non-reset cycle they must remain in lock-step.
	reg h_started;
	always @(posedge clock) begin
		if (reset)
			h_started <= 0;
		else
			h_started <= 1;

		if (!reset && h_started) begin
			h_rvfi_insn_stable: assert(rvfi_insn == wrapper.uut.q_insn_opcode);
		end
	end

	always @(posedge clock) begin
		if (!reset && h_started) begin
			h_dbg_next_tracks_launch: assert(wrapper.uut.dbg_next == $past(wrapper.uut.launch_next_insn));
		end
	end

	// When executing a branch in the ALU/compare stage, the debug operand
	// values must be marked valid (otherwise RVFI may report bogus zeros).
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h08 && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu) begin
				h_branch_rs1_valid: assert(wrapper.uut.dbg_rs1val_valid);
				h_branch_rs2_valid: assert(wrapper.uut.dbg_rs2val_valid);
			end
		end
	end

	// In the branch execute stage, the ALU operands must match the captured
	// debug operand values that will later be reported via RVFI.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h08 && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu) begin
				h_branch_regop1_matches_dbg: assert(wrapper.uut.reg_op1 == wrapper.uut.dbg_rs1val);
				h_branch_regop2_matches_dbg: assert(wrapper.uut.reg_op2 == wrapper.uut.dbg_rs2val);
			end
		end
	end

	// If a branch compares the same register to itself, the two captured operand
	// values must be identical.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h08 && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu &&
			    wrapper.uut.decoded_rs1[4:0] == wrapper.uut.decoded_rs2[4:0]) begin
				h_branch_same_rs_dbg_eq: assert(wrapper.uut.dbg_rs1val == wrapper.uut.dbg_rs2val);
			end
		end
	end

	// CPU state is one-hot encoded; rule out illegal encodings.
	always @(posedge clock) begin
		if (!reset) begin
			h_cpu_state_valid: assert(
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

	// With the compressed ISA enabled, instruction addresses are 16-bit aligned.
	always @(posedge clock) begin
		if (!reset && rvfi_valid) begin
			h_pc_rdata_aligned: assert(rvfi_pc_rdata[0] == 1'b0);
			h_pc_wdata_aligned: assert(rvfi_pc_wdata[0] == 1'b0);
		end
	end

	// For 32b branches, RVFI must expose the correct source register addresses.
	always @(posedge clock) begin
		if (!reset && rvfi_valid) begin
			if (&rvfi_insn[1:0] && rvfi_insn[6:0] == 7'b1100011) begin
				h_branch_rs1_addr_match: assert(rvfi_rs1_addr == rvfi_insn[19:15]);
				h_branch_rs2_addr_match: assert(rvfi_rs2_addr == rvfi_insn[24:20]);
			end
		end
	end

	// If RVFI reports both branch operands coming from the same register, the
	// two read-data values must match.
	always @(posedge clock) begin
		if (!reset && rvfi_valid) begin
			if (&rvfi_insn[1:0] && rvfi_insn[6:0] == 7'b1100011 &&
			    rvfi_rs1_addr == rvfi_rs2_addr) begin
				h_branch_same_rs_data_eq: assert(rvfi_rs1_rdata == rvfi_rs2_rdata);
			end
		end
	end

	// Stores should only be in-flight in the dedicated store state.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h40) begin
				h_no_store_in_fetch: assert(!wrapper.uut.mem_do_wdata);
			end
		end
	end

	// If the core is in the store-memory state, the "current instruction" being
	// tracked by the debug/RVFI path must not be a 32b branch opcode (otherwise
	// RVFI could retire a BEQ while the datapath is actually performing a store).
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h02 && &wrapper.uut.dbg_insn_opcode[1:0]) begin
				h_stmem_is_32b_store: assert(wrapper.uut.dbg_insn_opcode[6:0] == 7'b0100011);
			end
		end
	end

	// Decoded register indices must agree with the (debug) instruction word
	// when executing a branch.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h08 && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu && &wrapper.uut.dbg_insn_opcode[1:0]) begin
				h_branch_rs_fields_match: assert(wrapper.uut.dbg_insn_opcode[19:15] == wrapper.uut.decoded_rs1[4:0]);
				h_branch_rs_fields_match2: assert(wrapper.uut.dbg_insn_opcode[24:20] == wrapper.uut.decoded_rs2);
			end
		end
	end

	// A 32-bit instruction must not be treated as compressed (PC+2) by the core.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h08 && &wrapper.uut.dbg_insn_opcode[1:0]) begin
				h_32b_not_compressed: assert(!wrapper.uut.latched_compr);
			end
		end
	end

	// In exec, the core's tracked PC should match the debug PC for this instruction.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h08) begin
				h_regpc_matches_dbg: assert(wrapper.uut.reg_pc == wrapper.uut.dbg_insn_addr);
			end
		end
	end

	// Branch immediate decoding must match the instruction word.
	wire signed [31:0] h_branch_imm_sext =
		$signed({wrapper.uut.dbg_insn_opcode[31], wrapper.uut.dbg_insn_opcode[7], wrapper.uut.dbg_insn_opcode[30:25], wrapper.uut.dbg_insn_opcode[11:8], 1'b0});
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h08 && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu && &wrapper.uut.dbg_insn_opcode[1:0]) begin
				h_branch_imm_match: assert($signed(wrapper.uut.decoded_imm) == h_branch_imm_sext);
			end
		end
	end

	// In fetch, after a 32b branch has executed, the core's next PC must be either
	// the fall-through address (PC+4) or the branch target (PC+imm).
	always @(posedge clock) begin
		if (!reset) begin
			if (h_started && wrapper.uut.dbg_valid_insn && wrapper.uut.dbg_insn_addr[0] == 1'b0 &&
			    wrapper.uut.cpu_state == 8'h40 && &wrapper.uut.dbg_insn_opcode[1:0] &&
			    wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100011) begin
				h_branch_nextpc_form: assert(
					wrapper.uut.reg_next_pc == wrapper.uut.dbg_insn_addr + 32'd4 ||
					wrapper.uut.reg_next_pc == wrapper.uut.dbg_insn_addr + h_branch_imm_sext
				);
			end
		end
	end

	// For BEQ, the selected next PC must match the operand equality condition.
	always @(posedge clock) begin
		if (!reset) begin
			if (h_started && wrapper.uut.dbg_valid_insn && wrapper.uut.dbg_insn_addr[0] == 1'b0 &&
			    wrapper.uut.cpu_state == 8'h40 && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu &&
			    &wrapper.uut.dbg_insn_opcode[1:0] &&
			    wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100011 && wrapper.uut.dbg_insn_opcode[14:12] == 3'b000 &&
			    wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid) begin
				if (wrapper.uut.dbg_rs1val == wrapper.uut.dbg_rs2val) begin
					h_beq_nextpc_taken: assert(wrapper.uut.next_pc == wrapper.uut.dbg_insn_addr + h_branch_imm_sext);
				end else begin
					h_beq_nextpc_fallthrough: assert(wrapper.uut.next_pc == wrapper.uut.dbg_insn_addr + 32'd4);
				end
			end
		end
	end

	// When a (32b) conditional branch is taken, the core must use the branch
	// immediate from the retiring instruction's debug opcode to form the new PC.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.latched_branch && wrapper.uut.latched_store && !wrapper.uut.latched_stalu &&
			    &wrapper.uut.dbg_insn_opcode[1:0] && wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100011) begin
				h_taken_branch_target: assert((wrapper.uut.reg_out & ~32'b1) == (wrapper.uut.dbg_insn_addr + h_branch_imm_sext));
			end
		end
	end

/// Helper Assertion End
endmodule
