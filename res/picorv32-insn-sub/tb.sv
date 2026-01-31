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

	// ENABLE_IRQ is 0 in this configuration, so irq_state must stay at 0.
	always @(posedge clock) begin
		if (!reset) begin
			h_irq_state_zero: assert (wrapper.uut.irq_state == 0);
		end
	end

	// Track the most recent writeback source (ALU vs reg_out). This is stable even
	// if the core stalls for several cycles between writeback and retirement.
	reg h_last_wb_stalu;
	reg h_last_wb_seen;
	always @(posedge clock) begin
		if (reset) begin
			h_last_wb_stalu <= 0;
			h_last_wb_seen <= 0;
		end else if (wrapper.uut.cpuregs_write) begin
			h_last_wb_stalu <= wrapper.uut.latched_stalu;
			h_last_wb_seen <= 1;
		end
	end

	// One-cycle delayed copy of launch_next_insn (mirrors uut.dbg_next).
	reg h_launch_next_insn_d1;
	always @(posedge clock) begin
		h_launch_next_insn_d1 <= wrapper.uut.launch_next_insn;
	end

	// Track whether the currently-executing instruction has produced a register
	// writeback yet (and which writeback source was used). The debug interface
	// presents a new instruction when dbg_next is asserted.
	reg h_wb_seen_in_insn;
	reg h_wb_stalu_in_insn;
	wire [31:0] h_sub_op1 = (wrapper.uut.dbg_insn_opcode[19:15] == 0) ? 0 : wrapper.uut.dbg_rs1val;
	wire [31:0] h_sub_op2 = (wrapper.uut.dbg_insn_opcode[24:20] == 0) ? 0 : wrapper.uut.dbg_rs2val;
	wire [31:0] h_sub_expected = h_sub_op1 - h_sub_op2;
	always @(posedge clock) begin
		if (reset) begin
			h_wb_seen_in_insn <= 0;
			h_wb_stalu_in_insn <= 0;
		end else begin
			if (wrapper.uut.dbg_next) begin
				h_wb_seen_in_insn <= 0;
				h_wb_stalu_in_insn <= 0;
			end
			if (wrapper.uut.cpuregs_write) begin
				h_wb_seen_in_insn <= 1;
				h_wb_stalu_in_insn <= wrapper.uut.latched_stalu;
			end
		end
	end

	// SUB writes back via the ALU path.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid) begin
			h_sub_wb_uses_alu: assert (h_last_wb_seen && h_last_wb_stalu);
		end
	end

	// dbg_next is a registered copy of launch_next_insn.
	always @(posedge clock) begin
		if (!reset) begin
			h_dbg_next_matches_launch: assert (wrapper.uut.dbg_next == h_launch_next_insn_d1);
		end
	end

	// When a 32-bit SUB writes back, the written value must match the operand
	// snapshots.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpuregs_write && wrapper.uut.latched_stalu &&
				&wrapper.uut.dbg_insn_opcode[1:0] &&
				wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011 &&
				wrapper.uut.dbg_insn_opcode[14:12] == 3'b000 &&
				wrapper.uut.dbg_insn_opcode[31:25] == 7'b0100000) begin
			h_sub_wb_data_correct: assert (wrapper.uut.cpuregs_wrdata == wrapper.uut.dbg_rs1val - wrapper.uut.dbg_rs2val);
		end
	end

	// By the time a SUB instruction is ready to retire (launch_next_insn), its
	// ALU writeback must have already occurred (possibly in an earlier cycle in
	// cpu_state_fetch while waiting for decoder_trigger).
	always @(posedge clock) begin
		if (!reset && wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn &&
				&wrapper.uut.dbg_insn_opcode[1:0] &&
				wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011 &&
				wrapper.uut.dbg_insn_opcode[14:12] == 3'b000 &&
				wrapper.uut.dbg_insn_opcode[31:25] == 7'b0100000 &&
				wrapper.uut.dbg_insn_opcode[11:7] != 0) begin
			h_sub_retire_has_wb: assert ((h_wb_seen_in_insn && h_wb_stalu_in_insn) ||
				(wrapper.uut.cpuregs_write && wrapper.uut.latched_stalu));
		end
	end

	// At the point where SUB is ready to retire, either the writeback is
	// happening this cycle, or rvfi_rd_wdata already holds the SUB result.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn &&
				wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid &&
				&wrapper.uut.dbg_insn_opcode[1:0] &&
				wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011 &&
				wrapper.uut.dbg_insn_opcode[14:12] == 3'b000 &&
				wrapper.uut.dbg_insn_opcode[31:25] == 7'b0100000 &&
				wrapper.uut.dbg_insn_opcode[11:7] != 0) begin
			h_sub_retire_wdata_ready: assert ((wrapper.uut.cpuregs_write && wrapper.uut.latched_stalu) ||
				(rvfi_rd_wdata == h_sub_expected));
		end
	end

	// When checking SUB, the register addresses in the instruction must match the
	// RVFI operand / destination addresses.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid) begin
			h_sub_rs1_addr_match: assert (rvfi_rs1_addr == checker_inst.spec_rs1_addr);
			h_sub_rs2_addr_match: assert (rvfi_rs2_addr == checker_inst.spec_rs2_addr);
			h_sub_rd_addr_match:  assert (rvfi_rd_addr  == checker_inst.spec_rd_addr);
		end
	end

	// SUB special-case: rs2=x0 -> result equals rs1.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && checker_inst.spec_rs2_addr == 0 && checker_inst.spec_rd_addr != 0) begin
			h_sub_rs2_x0_result: assert (rvfi_rd_wdata == (checker_inst.spec_rs1_addr != 0 ? rvfi_rs1_rdata : 0));
		end
	end

	// If the destination register is x0, RVFI must report a zero writeback value.
	always @(posedge clock) begin
		if (!reset && rvfi_rd_addr == 0) begin
			h_x0_rd_wdata_is_zero: assert (rvfi_rd_wdata == 0);
		end
	end

	// When the core is in the execute state, the debug operand snapshots must
	// match the operand registers used by the ALU.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'h08) begin // cpu_state_exec
			if (wrapper.uut.dbg_rs1val_valid)
				h_dbg_rs1_matches_op1: assert (wrapper.uut.dbg_rs1val == wrapper.uut.reg_op1);
			if (wrapper.uut.dbg_rs2val_valid)
				h_dbg_rs2_matches_op2: assert (wrapper.uut.dbg_rs2val == wrapper.uut.reg_op2);
		end
	end

	// SUB must have valid operand snapshots once it reaches execute.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'h08 && wrapper.uut.instr_sub) begin // cpu_state_exec
			h_sub_rs1_valid: assert (wrapper.uut.dbg_rs1val_valid);
			h_sub_rs2_valid: assert (wrapper.uut.dbg_rs2val_valid);
		end
	end

	// If SUB targets x0 as an input register, the corresponding operand must be 0.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'h08 && wrapper.uut.instr_sub && &wrapper.uut.dbg_insn_opcode[1:0]) begin // cpu_state_exec
			if (wrapper.uut.dbg_insn_opcode[19:15] == 0)
				h_sub_rs1_x0_is_zero: assert (wrapper.uut.reg_op1 == 0);
			if (wrapper.uut.dbg_insn_opcode[24:20] == 0)
				h_sub_rs2_x0_is_zero: assert (wrapper.uut.reg_op2 == 0);
		end
	end

/// Helper Assertion End
endmodule
