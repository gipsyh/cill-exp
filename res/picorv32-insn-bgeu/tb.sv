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

	// Track retired PCs to enforce a consistent RVFI PC chain across instructions.
	reg h_have_prev;
	reg [`RISCV_FORMAL_XLEN-1:0] h_prev_pc_wdata;

	// Snapshot select internal decode flags from the previous cycle. This helps rule out
	// unreachable "RVFI says X but the core decoded Y" induction states.
	reg h_prev_instr_bgeu;
	reg h_prev_instr_bltu;

	always @(posedge clock) begin
		if (reset) begin
			h_have_prev <= 1'b0;
			h_prev_pc_wdata <= '0;
			h_prev_instr_bgeu <= 1'b0;
			h_prev_instr_bltu <= 1'b0;
		end else begin
			// RVFI PC values must be at least 16-bit aligned when COMPRESSED_ISA is enabled.
			h_pc_rdata_align: assert(!rvfi_valid || rvfi_pc_rdata[0] == 1'b0);
			h_pc_wdata_align: assert(!rvfi_valid || rvfi_pc_wdata[0] == 1'b0);

			// If the retired instruction is BGEU, the core must have decoded it as such
			// in the previous cycle (before decoding the next instruction overwrites the flags).
			if (rvfi_valid && rvfi_insn[6:0] == 7'b1100011 && rvfi_insn[14:12] == 3'b111) begin
				h_bgeu_decoded: assert(h_prev_instr_bgeu && !h_prev_instr_bltu);
			end

			// The next retired instruction must start at the previous retired instruction's pc_wdata.
			if (rvfi_valid) begin
				if (h_have_prev) begin
					h_pc_chain: assert(rvfi_pc_rdata == h_prev_pc_wdata);
				end
				h_have_prev <= 1'b1;
				h_prev_pc_wdata <= rvfi_pc_wdata;
			end

			// Update snapshots for use in the next cycle's checks.
			h_prev_instr_bgeu <= wrapper.uut.instr_bgeu;
			h_prev_instr_bltu <= wrapper.uut.instr_bltu;
		end
	end

	// After reset deasserts, wait one cycle before using $past() or lock-step checks.
	reg h_started;
	always @(posedge clock) begin
		if (reset)
			h_started <= 1'b0;
		else
			h_started <= 1'b1;
	end

	// RVFI instruction word is sourced from PicoRV32's q_insn_opcode.
	always @(posedge clock) begin
		if (!reset && h_started) begin
			h_rvfi_insn_matches_q: assert(rvfi_insn == wrapper.uut.q_insn_opcode);
		end
	end

	// dbg_next is a registered copy of launch_next_insn (used to select which decoded
	// instruction the debug/RVFI path is currently tracking).
	always @(posedge clock) begin
		if (!reset && h_started && $past(!reset)) begin
			h_dbg_next_tracks_launch: assert(wrapper.uut.dbg_next == $past(wrapper.uut.launch_next_insn));
		end
	end

	// When loading the second source operand for a conditional branch, PicoRV32 must
	// also capture both operands into the debug path that backs RVFI.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h08 && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu) begin
				h_branch_rs1_valid: assert(wrapper.uut.dbg_rs1val_valid);
				h_branch_rs2_valid: assert(wrapper.uut.dbg_rs2val_valid);
				h_branch_regop1_matches_dbg: assert(wrapper.uut.reg_op1 == wrapper.uut.dbg_rs1val);
				h_branch_regop2_matches_dbg: assert(wrapper.uut.reg_op2 == wrapper.uut.dbg_rs2val);
			end
		end
	end

	// If a branch compares the same register to itself, the two captured operand values must match.
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
				wrapper.uut.cpu_state == 8'h20 || // exec
				wrapper.uut.cpu_state == 8'h10 || // ld_rs1
				wrapper.uut.cpu_state == 8'h08 || // ld_rs2
				wrapper.uut.cpu_state == 8'h04 || // shift
				wrapper.uut.cpu_state == 8'h02 || // stmem
				wrapper.uut.cpu_state == 8'h01    // ldmem
			);
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

	// If RVFI reports both branch operands coming from the same register, the two read-data values must match.
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

	// In the store-memory state, the tracked instruction must be a store.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h02 && &wrapper.uut.dbg_insn_opcode[1:0]) begin
				h_stmem_is_32b_store: assert(wrapper.uut.dbg_insn_opcode[6:0] == 7'b0100011);
			end
		end
	end

	// Decoded register indices must agree with the debug instruction word when executing a branch.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h08 && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu &&
			    &wrapper.uut.dbg_insn_opcode[1:0]) begin
				h_branch_rs_fields_match1: assert(wrapper.uut.dbg_insn_opcode[19:15] == wrapper.uut.decoded_rs1[4:0]);
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

	// In the branch/compare stage, the core's tracked PC should match the debug PC for this instruction.
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
			if (wrapper.uut.cpu_state == 8'h08 && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu &&
			    &wrapper.uut.dbg_insn_opcode[1:0]) begin
				h_branch_imm_match: assert($signed(wrapper.uut.decoded_imm) == h_branch_imm_sext);
			end
		end
	end

	// For BGEU, the selected next PC must match the unsigned compare condition.
	always @(posedge clock) begin
		if (!reset) begin
			if (h_started && wrapper.uut.dbg_valid_insn && wrapper.uut.dbg_insn_addr[0] == 1'b0 &&
			    wrapper.uut.cpu_state == 8'h40 && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu &&
			    &wrapper.uut.dbg_insn_opcode[1:0] &&
			    wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100011 && wrapper.uut.dbg_insn_opcode[14:12] == 3'b111 &&
			    wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid) begin
				if (wrapper.uut.dbg_rs1val >= wrapper.uut.dbg_rs2val) begin
					h_bgeu_nextpc_taken: assert(wrapper.uut.next_pc == wrapper.uut.dbg_insn_addr + h_branch_imm_sext);
				end else begin
					h_bgeu_nextpc_fallthrough: assert(wrapper.uut.next_pc == wrapper.uut.dbg_insn_addr + 32'd4);
				end
			end
		end
	end

	// When a (32b) conditional branch is taken, the core must use the retiring instruction's immediate to form the new PC.
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
