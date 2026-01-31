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

	// With the compressed ISA enabled, retired instruction PCs are at least 16-bit aligned.
	always @(posedge clock) begin
		if (!reset) begin
			h_pc_rdata_aligned: assert (!rvfi_valid[0] || rvfi_pc_rdata[0] == 1'b0);
			h_pc_wdata_aligned: assert (!rvfi_valid[0] || rvfi_pc_wdata[0] == 1'b0);
		end
	end

	// The debug/RVFI pipeline advances with `launch_next_insn`.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_dbg_next_follows_launch: assert (wrapper.uut.dbg_next == $past(wrapper.uut.launch_next_insn));
		end
	end

	// RVFI captures the current decoded instruction opcode each cycle.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_rvfi_insn_pipe: assert (rvfi_insn == $past(wrapper.uut.dbg_insn_opcode));
		end
	end

	// Decode the BLTU immediate from the core's debug instruction word (same encoding as the spec model).
	wire [31:0] h_bltu_dbg_imm = $signed({
		wrapper.uut.dbg_insn_opcode[31],
		wrapper.uut.dbg_insn_opcode[7],
		wrapper.uut.dbg_insn_opcode[30:25],
		wrapper.uut.dbg_insn_opcode[11:8],
		1'b0
	});
	// Operand values as observed by RVFI (invalid operands read as x0).
	wire [31:0] h_bltu_dbg_rs1 = wrapper.uut.dbg_rs1val_valid ? wrapper.uut.dbg_rs1val : 32'd0;
	wire [31:0] h_bltu_dbg_rs2 = wrapper.uut.dbg_rs2val_valid ? wrapper.uut.dbg_rs2val : 32'd0;

	// When a BLTU is the retiring instruction in the debug pipeline, the core's next PC must be either the
	// fall-through PC+4 or the branch target PC+imm (we later constrain which case applies).
	always @(posedge clock) begin
		if (!reset && wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn) begin
			if (wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100011 &&
					wrapper.uut.dbg_insn_opcode[14:12] == 3'b110) begin
				if (wrapper.uut.dbg_insn_opcode[19:15] == 5'd0) begin
					h_bltu_rs1_x0_value: assert (h_bltu_dbg_rs1 == 32'd0);
				end
				if (wrapper.uut.dbg_insn_opcode[24:20] == 5'd0) begin
					h_bltu_rs2_x0_value: assert (h_bltu_dbg_rs2 == 32'd0);
				end

				h_bltu_nextpc_is_plus4_or_imm: assert (
					(wrapper.uut.reg_next_pc == wrapper.uut.dbg_insn_addr + 32'd4) ||
					(wrapper.uut.reg_next_pc == wrapper.uut.dbg_insn_addr + h_bltu_dbg_imm)
				);
				// Tie the core's next-PC selection to the unsigned compare result on the operands reported by RVFI.
				// This blocks CTIs where the compare and the chosen next PC disagree.
				h_bltu_nextpc_matches_cmp: assert (
					wrapper.uut.next_pc ==
						(wrapper.uut.dbg_insn_addr + ((h_bltu_dbg_rs1 < h_bltu_dbg_rs2) ? h_bltu_dbg_imm : 32'd4))
				);
			end
		end
	end

	// For BLTU retire events, RVFI must report the same rs1/rs2 register indices as encoded in the instruction.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_bltu_rs1_addr_match: assert (rvfi_rs1_addr == checker_inst.spec_rs1_addr);
			h_bltu_rs2_addr_match: assert (rvfi_rs2_addr == checker_inst.spec_rs2_addr);
		end
	end

	// In the execute state, the ALU operands used for the BLTU compare must match the values captured for RVFI.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'h08 && wrapper.uut.instr_bltu) begin
			h_bltu_regop1_matches_dbg: assert (wrapper.uut.reg_op1 == wrapper.uut.dbg_rs1val);
			h_bltu_regop2_matches_dbg: assert (wrapper.uut.reg_op2 == wrapper.uut.dbg_rs2val);
		end
	end

	// Bit-level consequence of BLTU next-PC computation: under a long carry-chain, PC+4 and PC+imm
	// cannot both keep certain bits high.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (rvfi_insn[8] && &rvfi_pc_rdata[24:1]) begin
				h_bltu_pc_wdata_bits: assert (!(rvfi_pc_wdata[24] && rvfi_pc_wdata[1]));
			end
		end
	end

	// Another small "carry-chain" fact: if rs1 is all-ones, BLTU is never taken, so next PC is PC+4.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (checker_inst.rs1_rdata_or_zero == 32'hffff_ffff && rvfi_pc_rdata[3:2] == 2'b11) begin
				h_bltu_pc_plus4_carry: assert (rvfi_pc_wdata[3:2] == 2'b00);
			end
		end
	end

	// If rs2 is x0, BLTU is never taken (unsigned compare against 0), so next PC is PC+4 (low bits unchanged).
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (checker_inst.spec_rs2_addr == 0) begin
				h_bltu_rs2_zero_pc_bits: assert (rvfi_pc_wdata[1] == rvfi_pc_rdata[1]);
			end
		end
	end

	// If rs1 is x0 and rs2 is nonzero, BLTU is taken; since imm[0]=0, bit 1 just XORs with imm[1] (=insn[8]).
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (checker_inst.spec_rs1_addr == 0 && checker_inst.spec_rs2_addr != 0 && rvfi_rs2_rdata != 0) begin
				h_bltu_rs1_zero_bit1: assert (rvfi_pc_wdata[1] == (rvfi_pc_rdata[1] ^ rvfi_insn[8]));
			end
		end
	end

	// Full bit-1 semantics for BLTU next PC: taken flips bit 1 if imm[1]=1, otherwise bit 1 is preserved.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_bltu_pc_bit1: assert (
				rvfi_pc_wdata[1] ==
					((checker_inst.rs1_rdata_or_zero < checker_inst.rs2_rdata_or_zero) ?
						(rvfi_pc_rdata[1] ^ rvfi_insn[8]) :
						rvfi_pc_rdata[1])
			);
		end
	end

	// Stronger form for the same case: rs2 is x0 => BLTU not taken => pc_wdata = pc_rdata + 4.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (checker_inst.spec_rs2_addr == 0) begin
				h_bltu_rs2_zero_pc_plus4: assert (rvfi_pc_wdata == rvfi_pc_rdata + 32'd4);
			end
		end
	end

	// More PC+4 carry-chain: if pc[4:2] are all 1's, adding 4 clears them to 0's.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (checker_inst.rs1_rdata_or_zero == 32'hffff_ffff && &rvfi_pc_rdata[4:2]) begin
				h_bltu_pc_plus4_carry_hi: assert (rvfi_pc_wdata[4:2] == 3'b000);
			end
		end
	end

	// If the branch immediate is a small positive value (fits below bit 11) and pc[11]=0,
	// then neither PC+4 nor PC+imm can carry into bit 12: upper bits must stay unchanged.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (checker_inst.insn_spec.insn_imm[31:11] == 0 && rvfi_pc_rdata[11] == 1'b0) begin
				h_bltu_no_carry_hi: assert (rvfi_pc_wdata[31:12] == rvfi_pc_rdata[31:12]);
			end
		end
	end

	// Same idea as h_bltu_pc_wdata_bits, but for a carry chain that reaches the sign bit.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (rvfi_insn[8] && &rvfi_pc_rdata[31:1]) begin
				h_bltu_pc_wdata_bits_top: assert (!(rvfi_pc_wdata[31] && rvfi_pc_wdata[1]));
			end
		end
	end

	// Same carry-chain pattern, but stopping at bit 15.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (rvfi_insn[8] && &rvfi_pc_rdata[15:1]) begin
				h_bltu_pc_wdata_bits_15: assert (!(rvfi_pc_wdata[15] && rvfi_pc_wdata[1]));
			end
		end
	end

	// Same carry-chain lemma for additional bit positions (16..30), to avoid iterating one CTI at a time.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap && rvfi_insn[8]) begin
			if (&rvfi_pc_rdata[16:1]) h_bltu_pc_wdata_bits_16: assert (!(rvfi_pc_wdata[16] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[17:1]) h_bltu_pc_wdata_bits_17: assert (!(rvfi_pc_wdata[17] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[18:1]) h_bltu_pc_wdata_bits_18: assert (!(rvfi_pc_wdata[18] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[19:1]) h_bltu_pc_wdata_bits_19: assert (!(rvfi_pc_wdata[19] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[20:1]) h_bltu_pc_wdata_bits_20: assert (!(rvfi_pc_wdata[20] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[21:1]) h_bltu_pc_wdata_bits_21: assert (!(rvfi_pc_wdata[21] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[22:1]) h_bltu_pc_wdata_bits_22: assert (!(rvfi_pc_wdata[22] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[23:1]) h_bltu_pc_wdata_bits_23: assert (!(rvfi_pc_wdata[23] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[25:1]) h_bltu_pc_wdata_bits_25: assert (!(rvfi_pc_wdata[25] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[26:1]) h_bltu_pc_wdata_bits_26: assert (!(rvfi_pc_wdata[26] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[27:1]) h_bltu_pc_wdata_bits_27: assert (!(rvfi_pc_wdata[27] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[28:1]) h_bltu_pc_wdata_bits_28: assert (!(rvfi_pc_wdata[28] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[29:1]) h_bltu_pc_wdata_bits_29: assert (!(rvfi_pc_wdata[29] && rvfi_pc_wdata[1]));
			if (&rvfi_pc_rdata[30:1]) h_bltu_pc_wdata_bits_30: assert (!(rvfi_pc_wdata[30] && rvfi_pc_wdata[1]));
		end
	end

	// When pc is about to wrap (pc[31:2]=1) and the branch offset is negative, either the branch is taken
	// (keeping the sign bit high) or it is not taken (pc+4 wraps to a small value, clearing bit 10).
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (&rvfi_pc_rdata[31:2] && checker_inst.insn_spec.insn_imm[31]) begin
				h_bltu_wrap_or_small: assert (rvfi_pc_wdata[31] || !rvfi_pc_wdata[10]);
			end
		end
	end

	// If imm[2:1]=2'b11 and pc[26:1] are all 1's, then having pc_wdata[26]=1 implies the branch was taken,
	// which forces pc_wdata[2]=1 (due to the carry from bit 1 into bit 2).
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (rvfi_insn[9:8] == 2'b11 && &rvfi_pc_rdata[26:1]) begin
				h_bltu_bit2_carry26: assert (!(rvfi_pc_wdata[26] && !rvfi_pc_wdata[2]));
			end
		end
	end

	// Special-case for a large positive branch offset (imm[11:1]=all 1's). With pc[28:12]=all 1's, taking the
	// branch forces a carry into bit 12 and clears bit 28; not taking adds 4 and clears bit 9 if pc[9:2]=all 1's.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (checker_inst.insn_spec.insn_imm[31:12] == 0 &&
					&checker_inst.insn_spec.insn_imm[11:1] &&
					&rvfi_pc_rdata[28:12] &&
					&rvfi_pc_rdata[9:1]) begin
				h_bltu_immffe_carry: assert (!(rvfi_pc_wdata[28] && rvfi_pc_wdata[9]));
			end
		end
	end

	// If imm[10:1] are all 1's and pc[28:1] are all 1's, then seeing pc_wdata[28]=1 implies the branch was taken,
	// which forces pc_wdata[10]=1 (carry into bit 11 with imm10=1 cannot yield a 0 at bit 10 when pc10=1).
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (&checker_inst.insn_spec.insn_imm[10:1] && &rvfi_pc_rdata[28:1]) begin
				h_bltu_bit10_carry28: assert (!(rvfi_pc_wdata[28] && !rvfi_pc_wdata[10]));
			end
		end
	end

	// Same pattern as h_bltu_bit10_carry28, but with a shorter carry chain (imm[6:1]=all 1's).
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (&checker_inst.insn_spec.insn_imm[6:1] && &rvfi_pc_rdata[20:1]) begin
				h_bltu_bit6_carry20: assert (!(rvfi_pc_wdata[20] && !rvfi_pc_wdata[6]));
			end
		end
	end

	// With imm = -2 and pc[11:1]=all 1's (pc low bits = 0xFFE), pc+4 clears bit 11 while pc-2 keeps the sign bit set.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (checker_inst.insn_spec.insn_imm == 32'hffff_fffe &&
					rvfi_pc_rdata[31] == 1'b1 &&
					&rvfi_pc_rdata[11:1]) begin
				h_bltu_neg2_lowffe: assert (!(rvfi_pc_wdata[11] && !rvfi_pc_wdata[31]));
			end
		end
	end

	// Same as h_bltu_neg2_lowffe, but with a longer low-bit carry chain (pc[14:1]=all 1's).
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (checker_inst.insn_spec.insn_imm == 32'hffff_fffe &&
					rvfi_pc_rdata[31] == 1'b1 &&
					&rvfi_pc_rdata[14:1]) begin
				h_bltu_neg2_low7ffe: assert (!(rvfi_pc_wdata[14] && !rvfi_pc_wdata[31]));
			end
		end
	end

	// Tiny carry-chain: with pc[6:1]=imm[6:1]=all 1's, pc_wdata[5]=1 implies the branch was taken,
	// which forces pc_wdata[6]=1 (taken case keeps bit 6 high, not-taken clears bits 2..6).
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			if (&checker_inst.insn_spec.insn_imm[6:1] && &rvfi_pc_rdata[6:1]) begin
				h_bltu_bit5_carry6: assert (!(rvfi_pc_wdata[5] && !rvfi_pc_wdata[6]));
			end
		end
	end

/// Helper Assertion End
endmodule
