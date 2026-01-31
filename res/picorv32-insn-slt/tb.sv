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
	// In PICORV32, `trap` indicates the core entered the terminal trap state. The
	// SLT instruction is not trapping, so a retired SLT (spec_valid) must never
	// coincide with `trap`.
	always @(posedge clock) begin
		if (!reset) begin
			h_no_slt_when_trap: assert(!(wrapper.trap && checker_inst.spec_valid));
		end
	end

	// For SLT, the architectural result is either 0 or 1 (when rd != x0).
	// Constrain unreachable CTIs where the core reports an SLT retirement with
	// non-boolean rd write-back data.
	always @(posedge clock) begin
		if (!reset) begin
			if (checker_inst.spec_valid) begin
				h_slt_rd_wdata_is_bool: assert(rvfi_rd_wdata[31:1] == 0);
			end
		end
	end

	// When a retiring instruction is an SLT, the reported operand values must
	// correspond to the core operands feeding the compare in that cycle. This
	// blocks unreachable traces where rvfi_* fields are misaligned.
	always @(posedge clock) begin
		if (!reset) begin
			if (checker_inst.spec_valid) begin
				h_slt_rs1_matches_op1: assert(rvfi_rs1_rdata == wrapper.uut.reg_op1);
				h_slt_rs2_matches_op2: assert(rvfi_rs2_rdata == wrapper.uut.reg_op2);
			end
		end
	end

	// Decode sanity: only one of the compare-class instruction flags can be set
	// at a time. This blocks unreachable "mixed decode" CTIs.
	wire [4:0] h_compare_flag_count =
		wrapper.uut.instr_beq + wrapper.uut.instr_bne + wrapper.uut.instr_blt +
		wrapper.uut.instr_bge + wrapper.uut.instr_bltu + wrapper.uut.instr_bgeu +
		wrapper.uut.instr_slti + wrapper.uut.instr_sltiu +
		wrapper.uut.instr_slt + wrapper.uut.instr_sltu;
	always @(posedge clock) begin
		if (!reset) begin
			h_compare_decode_onehot0: assert(h_compare_flag_count <= 1);
		end
	end

	// RVFI payload signals are only meaningful when rvfi_valid is asserted.
	// When an instruction is reported, PC addresses must be 2-byte aligned.
	always @(posedge clock) begin
		if (!reset) begin
			if (rvfi_valid[0]) begin
				h_pc_rdata_halfword_aligned: assert(rvfi_pc_rdata[0] == 1'b0);
				h_pc_wdata_halfword_aligned: assert(rvfi_pc_wdata[0] == 1'b0);
			end
		end
	end

	// Internal RVFI alignment: for non-trap retirements, rvfi_valid is driven by
	// launch_next_insn, which is also latched into dbg_next.
	always @(posedge clock) begin
		if (!reset) begin
			if (rvfi_valid[0] && !wrapper.trap) begin
				h_rvfi_valid_implies_dbg_next: assert(wrapper.uut.dbg_next);
			end
		end
	end

	// A retiring SLT (spec_valid) must correspond to a real "next insn launch"
	// event, which is reflected by dbg_next.
	always @(posedge clock) begin
		if (!reset) begin
			if (checker_inst.spec_valid) begin
				h_spec_valid_implies_dbg_next: assert(wrapper.uut.dbg_next);
			end
		end
	end

	// Basic pipeline sanity: dbg_next is the registered version of
	// launch_next_insn from the previous cycle.
	reg h_past_valid;
	always @(posedge clock) begin
		if (reset)
			h_past_valid <= 1'b0;
		else
			h_past_valid <= 1'b1;
	end
	always @(posedge clock) begin
		if (!reset && h_past_valid) begin
			h_dbg_next_tracks_launch: assert(wrapper.uut.dbg_next == $past(wrapper.uut.launch_next_insn));
		end
	end

	// If the instruction targets x0, the architectural write-back data is 0.
	always @(posedge clock) begin
		if (!reset) begin
			if (checker_inst.spec_valid && rvfi_insn[11:7] == 5'd0) begin
				h_slt_rd_x0_wdata_zero: assert(rvfi_rd_wdata == 0);
			end
		end
	end

	// In exec state, the instruction decode flags must match the opcode tracked
	// in q_insn_opcode (stable even with prefetch).
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h08) begin // cpu_state_exec
				if (wrapper.uut.instr_slt) begin
					h_exec_slt_opcode: assert(wrapper.uut.q_insn_opcode[6:0] == 7'b0110011 &&
					                          wrapper.uut.q_insn_opcode[14:12] == 3'b010 &&
					                          wrapper.uut.q_insn_opcode[31:25] == 7'b0000000);
				end
				if (wrapper.uut.instr_sltu) begin
					h_exec_sltu_opcode: assert(wrapper.uut.q_insn_opcode[6:0] == 7'b0110011 &&
					                           wrapper.uut.q_insn_opcode[14:12] == 3'b011 &&
					                           wrapper.uut.q_insn_opcode[31:25] == 7'b0000000);
				end
			end
		end
	end

	// Strengthen SLT write-back alignment for induction:
	// - If an SLT is in fetch state but is not writing back this cycle, the
	//   previously latched RVFI rd_wdata must already equal the compare result.
	// - If we did write back in the previous cycle, the newly latched RVFI
	//   rd_wdata must match the previous cycle's compare result.
	wire h_dbg_is_slt =
		wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011 &&
		wrapper.uut.dbg_insn_opcode[14:12] == 3'b010 &&
		wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000000 &&
		wrapper.uut.dbg_insn_opcode[1:0] == 2'b11;
	wire [4:0] h_dbg_rd = wrapper.uut.dbg_insn_opcode[11:7];
	wire        h_slt_cmp = $signed(wrapper.uut.dbg_rs1val) < $signed(wrapper.uut.dbg_rs2val);
	wire [31:0] h_slt_cmp_wdata = {31'b0, h_slt_cmp};

	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h40 && wrapper.uut.dbg_valid_insn && !wrapper.trap) begin // cpu_state_fetch
				if (h_dbg_is_slt && (h_dbg_rd != 0) &&
				    wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid) begin
					if (!wrapper.uut.cpuregs_write) begin
						h_slt_fetch_wb_held: assert(rvfi_rd_wdata == h_slt_cmp_wdata);
					end
				end
			end
		end
	end

	always @(posedge clock) begin
		if (!reset && h_past_valid) begin
			if ($past(wrapper.uut.cpu_state == 8'h40 && wrapper.uut.dbg_valid_insn && !wrapper.trap) &&
			    $past(h_dbg_is_slt && (h_dbg_rd != 0) &&
			          wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid) &&
			    $past(wrapper.uut.cpuregs_write)) begin
				h_slt_wb_updates_rvfi: assert(rvfi_rd_wdata == $past(h_slt_cmp_wdata));
			end
		end
	end

/// Helper Assertion End
endmodule
