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

	// Decode sanity: Quadrant-0 compressed instructions (opcode[1:0]==2'b00) are never J/JAL,
	// so picorv32's decoded `instr_jal` must be low after such an instruction is decoded.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if ($past(wrapper.uut.mem_do_rinst && wrapper.uut.mem_done)) begin
				if ($past(wrapper.uut.mem_rdata_latched[1:0]) == 2'b00) begin
					h_no_jal_on_c_q0: assert(!wrapper.uut.instr_jal);
				end
			end
		end
	end

	// State-machine sanity: when an instruction is ready in fetch (decoder_trigger) and it's not a J/JAL,
	// the core must advance to the operand-read state next cycle.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if ($past(wrapper.uut.cpu_state == 8'h40 && wrapper.uut.decoder_trigger && !wrapper.uut.instr_jal)) begin
				h_fetch_advances_nonjal: assert(wrapper.uut.cpu_state == 8'h20);
			end
		end
	end

	// RVFI operand capture sanity for C.ADDI4SPN: this instruction always reads x2 (sp). If we are
	// about to write back a completed C.ADDI4SPN, the debug/RVFI machinery must have captured rs1.
	wire h_is_c_addi4spn =
		(wrapper.uut.dbg_insn_opcode[1:0] == 2'b00) &&
		(wrapper.uut.dbg_insn_opcode[15:13] == 3'b000) &&
		(|wrapper.uut.dbg_insn_opcode[12:5]);
	wire [31:0] h_c_addi4spn_imm =
		{22'b0, wrapper.uut.dbg_insn_opcode[10:7], wrapper.uut.dbg_insn_opcode[12:11],
		 wrapper.uut.dbg_insn_opcode[5], wrapper.uut.dbg_insn_opcode[6], 2'b00};
	wire [4:0] h_c_addi4spn_rd = {2'b01, wrapper.uut.dbg_insn_opcode[4:2]};
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.latched_store && h_is_c_addi4spn) begin
				h_addi4spn_has_rs1_capture: assert(wrapper.uut.dbg_rs1val_valid);
				h_addi4spn_rs1val_matches_op1_wb: assert(wrapper.uut.dbg_rs1val == wrapper.uut.reg_op1);
				h_addi4spn_rd_is_compressed: assert(wrapper.uut.latched_rd == h_c_addi4spn_rd);
			end
		end
	end

	// Track whether we have observed a register writeback since the last instruction-retire boundary.
	// For C.ADDI4SPN a writeback must have occurred by the time we retire (launch_next_insn).
	reg h_wb_seen;
	always @(posedge clock) begin
		if (reset) begin
			h_wb_seen <= 0;
		end else begin
			if (wrapper.uut.launch_next_insn) begin
				h_wb_seen <= 0;
			end else if (wrapper.uut.cpuregs_write && wrapper.uut.latched_rd != 0) begin
				h_wb_seen <= 1;
			end
		end
	end
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn && h_is_c_addi4spn) begin
				h_addi4spn_wb_seen_before_retire: assert(h_wb_seen || (wrapper.uut.cpuregs_write && wrapper.uut.latched_rd != 0));
			end
		end
	end

	// Once the writeback happened for C.ADDI4SPN, the written value must match rs1+imm.
	always @(posedge clock) begin
		if (!reset) begin
			if (h_wb_seen && h_is_c_addi4spn) begin
				h_addi4spn_wdata_matches_calc: assert(rvfi_rd_wdata == wrapper.uut.dbg_rs1val + h_c_addi4spn_imm);
				h_addi4spn_wdata_matches_calc_rvfi: assert(rvfi_rd_wdata == rvfi_rs1_rdata + h_c_addi4spn_imm);
			end
		end
	end

	// Decoder sanity for C.ADDI4SPN: rs1 is fixed to x2 (sp).
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h20 && h_is_c_addi4spn) begin
				h_addi4spn_decoded_rs1_is_sp: assert(wrapper.uut.decoded_rs1 == 5'd2);
				h_addi4spn_decoded_rd: assert(wrapper.uut.decoded_rd == h_c_addi4spn_rd);
				h_addi4spn_decoded_imm: assert(wrapper.uut.decoded_imm == h_c_addi4spn_imm);
			end
		end
	end

	// Execution sanity for C.ADDI4SPN: the ALU result must be rs1 + imm.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h08 && h_is_c_addi4spn) begin
				h_addi4spn_exec_is_addi: assert(wrapper.uut.instr_addi);
				h_addi4spn_exec_add: assert(wrapper.uut.alu_out == wrapper.uut.reg_op1 + wrapper.uut.reg_op2);
				h_addi4spn_exec_imm: assert(wrapper.uut.decoded_imm == h_c_addi4spn_imm);
				h_addi4spn_op2_is_imm: assert(wrapper.uut.reg_op2 == wrapper.uut.decoded_imm);
			end
		end
	end

/// Helper Assertion End
endmodule
