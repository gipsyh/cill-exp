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

	// AUIPC is a U-type instruction; its immediate is always 12-bit aligned.
	// Block unreachable induction states where the core's decoded immediate is
	// inconsistent with the retired RVFI instruction word.
	wire h_is_auipc = rvfi_valid[0] && (rvfi_insn[6:0] == 7'b0010111);
	wire [31:0] h_auipc_imm = {rvfi_insn[31:12], 12'b0};
	wire [4:0] h_auipc_rd = rvfi_insn[11:7];
	wire h_q_is_auipc = wrapper.uut.q_insn_opcode[6:0] == 7'b0010111;

	always @(posedge clock) begin
		if (!reset) begin
			h_auipc_imm_matches_insn: assert(!h_is_auipc || (wrapper.uut.q_insn_imm == h_auipc_imm));
		end
	end

	// When retiring AUIPC, the reported destination register must match the instruction encoding.
	always @(posedge clock) begin
		if (!reset) begin
			h_auipc_rd_addr_matches_insn: assert(!h_is_auipc || (rvfi_rd_addr[4:0] == h_auipc_rd));
		end
	end

	// RVFI signals are registered one cycle after the core performs the write-back in cpu_state_fetch.
	// Capture the latest register write-back information from the core. There can be
	// multiple fetch/wait cycles between write-back and RVFI retirement.
	reg        h_wb_valid;
	reg [ 4:0] h_wb_rd;
	reg [31:0] h_wb_wdata;
	reg [31:0] h_wb_pc;

	always @(posedge clock) begin
		if (reset) begin
			h_wb_valid <= 0;
			h_wb_rd <= 0;
			h_wb_wdata <= 0;
			h_wb_pc <= 0;
		end else if (wrapper.uut.cpuregs_write) begin
			h_wb_valid <= 1;
			h_wb_rd <= wrapper.uut.latched_rd[4:0];
			h_wb_wdata <= wrapper.uut.cpuregs_wrdata;
			h_wb_pc <= wrapper.uut.reg_pc;
		end
	end

	always @(posedge clock) begin
		if (!reset && h_is_auipc) begin
			h_auipc_has_captured_wb: assert(h_wb_valid);
			h_auipc_wb_rd_matches_insn: assert(h_wb_rd == h_auipc_rd);
			h_auipc_wb_wdata_matches: assert(h_auipc_rd ? (rvfi_rd_wdata == h_wb_wdata) : (rvfi_rd_wdata == 0));
		end
	end

	// For AUIPC, the immediate is always 12-bit aligned, so the low 12 bits of the write-back
	// data must match the instruction PC low 12 bits.
		always @(posedge clock) begin
			if (!reset && wrapper.uut.dbg_valid_insn && (wrapper.uut.cpu_state == 8'h40) && h_q_is_auipc &&
			    !wrapper.uut.cpuregs_write && h_wb_valid && (h_wb_rd == wrapper.uut.q_insn_opcode[11:7]) &&
			    (h_wb_pc == wrapper.uut.dbg_insn_addr)) begin
				h_auipc_wb_lowbits_match_pc: assert(h_wb_wdata[11:0] == h_wb_pc[11:0]);
				h_auipc_wb_wdata_matches_pc_plus_imm: assert(h_wb_wdata == h_wb_pc + {wrapper.uut.q_insn_opcode[31:12], 12'b0});
			end
		end

		// Once AUIPC has completed its register write-back, the captured write-back PC must match
		// the in-flight instruction address until retirement.
		always @(posedge clock) begin
			if (!reset && wrapper.uut.dbg_valid_insn && (wrapper.uut.cpu_state == 8'h40) && h_q_is_auipc &&
			    !wrapper.uut.cpuregs_write && h_wb_valid) begin
				h_auipc_wb_pc_matches_dbg_addr: assert(h_wb_pc == wrapper.uut.dbg_insn_addr);
			end
		end

		// Keep the core's internal PC consistent with the debug/rvfi PC bookkeeping.
		// This blocks unreachable induction states where AUIPC uses a different PC than RVFI reports.
		wire h_state_ld_rs1 = wrapper.uut.cpu_state == 8'h20;
	wire h_state_exec = wrapper.uut.cpu_state == 8'h08;
	always @(posedge clock) begin
		if (!reset) begin
			h_pc_matches_dbg_addr_in_ld_rs1: assert(!(wrapper.uut.dbg_valid_insn && h_state_ld_rs1) ||
				(wrapper.uut.reg_pc == wrapper.uut.dbg_insn_addr));
		end
	end

	// Decoder outputs for LUI and AUIPC must be mutually exclusive once an instruction is in-flight.
	always @(posedge clock) begin
		if (!reset) begin
			h_no_lui_auipc_overlap: assert(!((h_state_ld_rs1 || h_state_exec) &&
				wrapper.uut.dbg_valid_insn && wrapper.uut.instr_lui && wrapper.uut.instr_auipc));
		end
	end

	// AUIPC must retire with the correct captured write-back register.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.dbg_valid_insn && wrapper.uut.launch_next_insn && h_q_is_auipc) begin
			h_auipc_retire_wb_rd_matches: assert(wrapper.uut.cpuregs_write ?
				(wrapper.uut.latched_rd[4:0] == wrapper.uut.q_insn_opcode[11:7]) :
				(h_wb_valid && (h_wb_rd == wrapper.uut.q_insn_opcode[11:7])));
		end
	end

	// AUIPC uses a U-type immediate; by the time we are in exec, reg_op2 must be 4k aligned
	// and reg_op1 must hold the current PC (not zero as in LUI).
	always @(posedge clock) begin
		if (!reset && wrapper.uut.dbg_valid_insn && h_state_exec && wrapper.uut.instr_auipc) begin
			h_auipc_op2_uimm_aligned: assert(wrapper.uut.reg_op2[11:0] == 12'b0);
			h_auipc_op1_is_pc: assert(wrapper.uut.reg_op1 == wrapper.uut.reg_pc);
		end
	end

	// In ld_rs1/exec (and for 32-bit instructions), the LUI/AUIPC decode flags must match the opcode.
		wire h_dbg_is_32 = wrapper.uut.dbg_insn_opcode[1:0] == 2'b11;
		wire h_dbg_is_lui = wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110111;
		wire h_dbg_is_auipc = wrapper.uut.dbg_insn_opcode[6:0] == 7'b0010111;
		wire [31:0] h_dbg_uimm = {wrapper.uut.dbg_insn_opcode[31:12], 12'b0};
		always @(posedge clock) begin
			if (!reset && wrapper.uut.dbg_valid_insn && h_dbg_is_32 && (h_state_ld_rs1 || h_state_exec)) begin
				h_lui_flag_matches_dbg_opcode: assert(wrapper.uut.instr_lui == h_dbg_is_lui);
				h_auipc_flag_matches_dbg_opcode: assert(wrapper.uut.instr_auipc == h_dbg_is_auipc);
			end
		end

		// For AUIPC, the internal decoded immediate must match the U-type immediate in the instruction word.
		// This blocks unreachable induction states where the opcode bits and decoded immediate diverge.
		always @(posedge clock) begin
			if (!reset && wrapper.uut.dbg_valid_insn && h_dbg_is_32 && h_dbg_is_auipc &&
			    (h_state_ld_rs1 || h_state_exec || (wrapper.uut.cpu_state == 8'h40))) begin
				h_auipc_decoded_imm_matches_dbg_opcode: assert(wrapper.uut.decoded_imm == h_dbg_uimm);
				h_auipc_not_sub: assert(!wrapper.uut.instr_sub);
			end
		end

	/// Helper Assertion End
	endmodule
