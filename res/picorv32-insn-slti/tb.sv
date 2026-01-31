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

	// For SLTI, the architectural result is always 0 or 1.
	always @(posedge clock) begin
		if (!reset) begin
			h_slti_rd_wdata_is_0_or_1: assert(!check || !checker_inst.spec_valid || rvfi_rd_wdata[31:1] == 0);
		end
	end

	// Track whether we've visited the EXEC state since the last instruction boundary.
	// SLTI always executes via cpu_state_exec before it can retire.
	reg h_saw_exec;
	wire h_dbg_is_slti =
		(&wrapper.uut.dbg_insn_opcode[1:0]) &&
		(wrapper.uut.dbg_insn_opcode[6:0] == 7'b0010011) &&
		(wrapper.uut.dbg_insn_opcode[14:12] == 3'b010);
	wire [31:0] h_dbg_imm_i = {{20{wrapper.uut.dbg_insn_opcode[31]}}, wrapper.uut.dbg_insn_opcode[31:20]};

	always @(posedge clock) begin
		if (reset) begin
			h_saw_exec <= 1'b0;
		end else begin
			if (wrapper.uut.launch_next_insn)
				h_saw_exec <= 1'b0;
			if (wrapper.uut.cpu_state == 8'b00001000)
				h_saw_exec <= 1'b1;
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_slti_retire_requires_exec: assert(!check || !(wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn && h_dbg_is_slti) || h_saw_exec);
			h_dbg_slti_implies_instr_slti: assert(!wrapper.uut.dbg_valid_insn || !h_dbg_is_slti || wrapper.uut.instr_slti);
		end
	end

	// ALU compare plumbing: when the core selects the signed/unsigned-compare path,
	// alu_out_0 must reflect the corresponding comparator output.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'b00001000) begin
			h_alu_out0_matches_lts: assert(!wrapper.uut.is_slti_blt_slt || (wrapper.uut.alu_out_0 == wrapper.uut.alu_lts));
		end
	end

	// For SLTI, reg_op1 is the rs1 value used by the ALU and must match the
	// debug-captured rs1 value that is later exposed via RVFI.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'b00001000 && wrapper.uut.instr_slti) begin
			h_slti_reg_op1_matches_dbg_rs1: assert(wrapper.uut.dbg_rs1val_valid && (wrapper.uut.reg_op1 == wrapper.uut.dbg_rs1val));
			h_slti_reg_op2_matches_dbg_imm: assert(wrapper.uut.reg_op2 == h_dbg_imm_i);
		end
	end

/// Helper Assertion End
endmodule
