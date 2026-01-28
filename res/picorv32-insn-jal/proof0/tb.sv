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

	// `mem_la_secondword` is only asserted while the memory FSM is actively
	// performing the second read of an unaligned 32-bit instruction fetch.
	always @(posedge clock) begin
		if (!reset) begin
			h_mem_la_secondword_state: assert(!wrapper.uut.mem_la_secondword || wrapper.uut.mem_state == 2'd1);
		end
	end

	// A JAL (opcode 1101111) uses `reg_next_pc` as the jump target; the reg_out/ALU
	// based target path is used for other control-flow instructions (e.g. JALR/branches).
	always @(posedge clock) begin
		if (!reset) begin
			h_jal_no_regout_target: assert(!(wrapper.uut.dbg_insn_opcode[6:0] == 7'b1101111 &&
			                                 wrapper.uut.latched_branch && wrapper.uut.latched_store));
		end
	end

	// If a JAL is reported on the RVFI interface, it must be a 32-bit instruction.
	// `latched_compr` for that instruction is tracked alongside `dbg_insn_opcode`,
	// so check it one cycle earlier to match the RVFI pipeline.
	always @(posedge clock) begin
		if (!reset && !$past(reset)) begin
			h_rvfi_jal_not_compressed: assert(!(rvfi_valid[0] && rvfi_insn[6:0] == 7'b1101111) ||
			                                  !$past(wrapper.uut.latched_compr));
		end
	end

	// For JAL, insn_imm[1] is rvfi_insn[21] and insn_imm[0] is 0.
	// If both PC[1:0] and imm[1:0] are 0, then the target must have PC[1]=0.
	always @(posedge clock) begin
		if (!reset) begin
			if (rvfi_valid[0] && rvfi_insn[6:0] == 7'b1101111 && rvfi_pc_rdata[1:0] == 2'b00 && rvfi_insn[21] == 1'b0) begin
				h_jal_bit1_stays_zero: assert(rvfi_pc_wdata[1] == 1'b0);
			end
		end
	end

	// Bit1 of PC+imm for JAL: with imm[0]=0 and PC[0]=0, sum[1] is PC[1] ^ imm[1].
	always @(posedge clock) begin
		if (!reset) begin
			if (rvfi_valid[0] && rvfi_insn[6:0] == 7'b1101111 && rvfi_pc_rdata[0] == 1'b0) begin
				h_jal_bit1_add: assert(rvfi_pc_wdata[1] == (rvfi_pc_rdata[1] ^ rvfi_insn[21]));
			end
		end
	end

	// Bit-level consequence of PC+imm for JAL: with imm[0]=0, carry into bit2 is (PC[1] & imm[1]).
	always @(posedge clock) begin
		if (!reset) begin
			if (rvfi_valid[0] && rvfi_insn[6:0] == 7'b1101111 && rvfi_pc_rdata[0] == 1'b0) begin
				h_jal_bit2_add: assert(rvfi_pc_wdata[2] ==
				                       (rvfi_pc_rdata[2] ^ rvfi_insn[22] ^ (rvfi_pc_rdata[1] & rvfi_insn[21])));
			end
		end
	end

	// Bit3 of PC+imm for JAL (imm[3:1] = rvfi_insn[23:21], imm[0]=0).
	always @(posedge clock) begin
		if (!reset) begin
			if (rvfi_valid[0] && rvfi_insn[6:0] == 7'b1101111 && rvfi_pc_rdata[0] == 1'b0) begin
				logic h_carry1, h_carry2;
				h_carry1 = rvfi_pc_rdata[1] & rvfi_insn[21];
				h_carry2 = (rvfi_pc_rdata[2] & rvfi_insn[22]) | (rvfi_pc_rdata[2] & h_carry1) | (rvfi_insn[22] & h_carry1);
				h_jal_bit3_add: assert(rvfi_pc_wdata[3] == (rvfi_pc_rdata[3] ^ rvfi_insn[23] ^ h_carry2));
			end
		end
	end

	// Pipeline-aligned PC check for JAL:
	// When PicoRV32 "launches" the next instruction, `next_pc` becomes the next
	// architectural PC for the instruction that will retire on the RVFI bus in
	// the *next* cycle (`rvfi_insn` is sourced from `dbg_insn_opcode`).
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn &&
			    wrapper.uut.dbg_insn_opcode[6:0] == 7'b1101111) begin
				logic signed [31:0] h_imm;
				h_imm = $signed({wrapper.uut.dbg_insn_opcode[31],
				                 wrapper.uut.dbg_insn_opcode[19:12],
				                 wrapper.uut.dbg_insn_opcode[20],
				                 wrapper.uut.dbg_insn_opcode[30:21],
				                 1'b0});
				h_jal_nextpc_match: assert(wrapper.uut.next_pc == wrapper.uut.dbg_insn_addr + h_imm);
			end
		end
	end

	// PicoRV32 may suppress the writeback datapath for `jal x0, imm` (no register
	// file write). In that case, the RVFI bus must not leak a stale `rd_wdata`.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn &&
			    wrapper.uut.dbg_insn_opcode[6:0] == 7'b1101111 &&
			    wrapper.uut.dbg_insn_opcode[11:7] == 5'd0) begin
				h_jal_x0_rd_wdata_zero: assert(rvfi_rd_wdata == 0);
			end
		end
	end

	// For a non-zero rd JAL, the link value (PC+4) must already be present on
	// the RVFI bus in the cycle before retirement (PicoRV32 may latch it early).
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn &&
			    wrapper.uut.dbg_insn_opcode[6:0] == 7'b1101111 &&
			    wrapper.uut.dbg_insn_opcode[11:7] != 5'd0) begin
				h_jal_rd_wdata_pcplus4: assert(rvfi_rd_wdata == wrapper.uut.dbg_insn_addr + 32'd4);
			end
		end
	end

	// RISC-V PC is always 2-byte aligned (including RV32IC).
	always @(posedge clock) begin
		if (!reset) begin
			if (rvfi_valid[0]) begin
				h_pc_wdata_bit0: assert(rvfi_pc_wdata[0] == 1'b0);
			end
		end
	end

/// Helper Assertion End
endmodule
