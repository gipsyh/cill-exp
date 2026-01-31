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
	// PC is always at least 16-bit aligned (COMPRESSED_ISA enabled in wrapper).
	always @(posedge clock) begin
		if (!reset) begin
			if (rvfi_valid) begin
				h_pc_rdata_aligned: assert(rvfi_pc_rdata[0] == 1'b0);
				h_pc_wdata_aligned: assert(rvfi_pc_wdata[0] == 1'b0);
			end
		end
	end

	// mem_la_secondword is only asserted in the memory state machine "state 1"
	// (it is set/cleared only there and is reset on trap/reset).
	always @(posedge clock) begin
		if (!reset) begin
			h_secondword_in_state1: assert(!wrapper.uut.mem_la_secondword || wrapper.uut.mem_state == 2'd1);
		end
	end

	// picorv32 drives RVFI pc_rdata from the previous cycle's dbg_insn_addr, and
	// pc_wdata from the current dbg_insn_addr. With IRQs disabled, this means:
	//   pc_rdata(t) == pc_wdata(t-1)
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_pc_rdata_is_past_wdata: assert(rvfi_pc_rdata == $past(rvfi_pc_wdata));
		end
	end

	// Memory state machine: in mem_state==1, a completed transfer (mem_xfer) must
	// advance the state unless we explicitly request the compressed "second word"
	// read (mem_la_read).
	always @(posedge clock) begin
		if (!reset && $past(!reset) && !$past(wrapper.uut.trap)) begin
			if ($past(wrapper.uut.mem_state == 2'd1) && $past(wrapper.uut.mem_xfer) && !$past(wrapper.uut.mem_la_read)) begin
				h_mem_state1_progress: assert(wrapper.uut.mem_state != 2'd1);
			end
		end
	end

	// In the picorv32 memory interface, mem_valid is only asserted in mem_state 1/2.
	// When not trapped, mem_state==0 means the interface is idle and mem_valid must be low.
	always @(posedge clock) begin
		if (!reset && !wrapper.uut.trap) begin
			h_mem_state0_no_valid: assert(!(wrapper.uut.mem_state == 2'd0 && wrapper.uut.mem_valid));
		end
	end

	// Similarly, in the write state (mem_state==2) the interface must be driving mem_valid.
	always @(posedge clock) begin
		if (!reset && !wrapper.uut.trap) begin
			h_mem_state2_needs_valid: assert(wrapper.uut.mem_state != 2'd2 || wrapper.uut.mem_valid);
		end
	end

	// cpu_state is one-hot encoded (see localparams in picorv32).
	always @(posedge clock) begin
		if (!reset) begin
			h_cpu_state_onehot: assert(
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

	// When executing a 32-bit instruction (insn[1:0] == 2'b11), latched_compr must be 0.
	// (Compressed branches like C.BNEZ can set instr_bne too, but they have insn[1:0] != 2'b11.)
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'h08 && wrapper.uut.instr_bne && wrapper.uut.dbg_insn_opcode[1:0] == 2'b11) begin
			h_bne_not_compressed: assert(!wrapper.uut.latched_compr);
		end
	end

	// For a 32-bit branch instruction, the decoded branch-type flags must match funct3.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'h08 && wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100011 && wrapper.uut.dbg_insn_opcode[1:0] == 2'b11) begin
			if (wrapper.uut.dbg_insn_opcode[14:12] == 3'b001) begin
				h_bne_funct3_matches: assert(wrapper.uut.instr_bne);
				h_bne_not_blt: assert(!wrapper.uut.instr_blt);
			end
		end
	end

	// Coherence between operand registers used by the CPU and the values exported via RVFI.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'h08 && wrapper.uut.is_beq_bne_blt_bge_bltu_bgeu) begin
			h_branch_dbg_rs1_valid: assert(wrapper.uut.dbg_rs1val_valid);
			h_branch_dbg_rs2_valid: assert(wrapper.uut.dbg_rs2val_valid);
			h_branch_dbg_rs1_eq_op1: assert(wrapper.uut.dbg_rs1val == wrapper.uut.reg_op1);
			h_branch_dbg_rs2_eq_op2: assert(wrapper.uut.dbg_rs2val == wrapper.uut.reg_op2);
		end
	end

	// For 32-bit branches, decoded source register indices must match the instruction fields.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'h08 && wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100011 && wrapper.uut.dbg_insn_opcode[1:0] == 2'b11) begin
			h_branch_rs1_field_matches_decode: assert(wrapper.uut.decoded_rs1 == wrapper.uut.dbg_insn_opcode[19:15]);
			h_branch_rs2_field_matches_decode: assert(wrapper.uut.decoded_rs2 == wrapper.uut.dbg_insn_opcode[24:20]);
		end
	end

	// Outside of FETCH the core is executing the instruction referenced by dbg_insn_*.
	// In that phase, reg_pc must match dbg_insn_addr and reg_next_pc must be the
	// sequential fall-through PC (pc + 2 for compressed, pc + 4 otherwise).
	always @(posedge clock) begin
		if (!reset && !wrapper.uut.trap && wrapper.uut.cpu_state != 8'h40) begin
			h_reg_pc_matches_dbg_insn_addr: assert(wrapper.uut.reg_pc == wrapper.uut.dbg_insn_addr);
			h_reg_next_pc_fallthrough: assert(wrapper.uut.reg_next_pc == wrapper.uut.reg_pc + (wrapper.uut.latched_compr ? 32'd2 : 32'd4));
		end
	end

	// decoder_pseudo_trigger_q is only raised for one cycle after finishing a load/store
	// (i.e. when the previous cpu_state was LDMEM or STMEM).
	always @(posedge clock) begin
		// The core sets decoder_pseudo_trigger in LDMEM/STMEM while also transitioning
		// cpu_state back to FETCH in the same cycle, so decoder_pseudo_trigger_q implies
		// cpu_state was LDMEM/STMEM two cycles ago.
		if (!reset && $past(!reset) && $past(!reset, 2) && wrapper.uut.decoder_pseudo_trigger_q) begin
			h_pseudo_trigger_prev_mem_state: assert($past(wrapper.uut.cpu_state == 8'h01 || wrapper.uut.cpu_state == 8'h02, 2));
		end
	end

	// BNE retirement: when the core is about to launch the next instruction (launch_next_insn),
	// dbg_insn_* still refer to the retiring instruction. The next_pc chosen by the core must
	// match the architectural BNE semantics for those operands.
	wire [31:0] h_bne_imm = $signed({wrapper.uut.dbg_insn_opcode[31], wrapper.uut.dbg_insn_opcode[7], wrapper.uut.dbg_insn_opcode[30:25], wrapper.uut.dbg_insn_opcode[11:8], 1'b0});
	wire [31:0] h_bne_rs1 = wrapper.uut.dbg_rs1val_valid ? wrapper.uut.dbg_rs1val : 32'd0;
	wire [31:0] h_bne_rs2 = wrapper.uut.dbg_rs2val_valid ? wrapper.uut.dbg_rs2val : 32'd0;
	wire        h_bne_cond = h_bne_rs1 != h_bne_rs2;
	wire [31:0] h_bne_expected_next_pc = h_bne_cond ? (wrapper.uut.dbg_insn_addr + h_bne_imm) : (wrapper.uut.dbg_insn_addr + 32'd4);

	always @(posedge clock) begin
		// If we're still in the middle of a second-word fetch for an unaligned 32-bit instruction,
		// we cannot yet be launching the next instruction. Guard against that unreachable CTI shape.
		if (!reset && !wrapper.uut.trap && wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn && !wrapper.uut.mem_la_secondword && wrapper.uut.mem_state == 2'd0) begin
			if (wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100011 && wrapper.uut.dbg_insn_opcode[14:12] == 3'b001 && wrapper.uut.dbg_insn_opcode[1:0] == 2'b11) begin
				h_bne_operands_valid: assert(wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid);
				if (wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid) begin
					// If either source register is x0, the corresponding operand value must be 0.
					h_bne_rs1_x0_val: assert((wrapper.uut.dbg_insn_opcode[19:15] != 5'd0) || (h_bne_rs1 == 0));
					h_bne_rs2_x0_val: assert((wrapper.uut.dbg_insn_opcode[24:20] != 5'd0) || (h_bne_rs2 == 0));
					h_bne_next_pc_matches_spec: assert(wrapper.uut.next_pc == h_bne_expected_next_pc);
				end
			end
		end
	end

/// Helper Assertion End
endmodule
