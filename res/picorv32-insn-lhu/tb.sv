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

	// For LHU retire, the matching data transfer is observed two cycles earlier (RVFI/mem capture latency).
	always @(posedge clock) begin
		if (!reset && !$past(reset) && !$past(reset, 2)) begin
			if (wrapper.uut.cpu_state == 8'b00000001 && &wrapper.uut.dbg_insn_opcode[1:0]) begin
				h_dbg_insn_imm_itype: assert(wrapper.uut.dbg_insn_imm == {{20{wrapper.uut.dbg_insn_opcode[31]}}, wrapper.uut.dbg_insn_opcode[31:20]});
			end
			if (wrapper.uut.cpu_state == 8'b00000001 && wrapper.uut.mem_do_rdata && wrapper.uut.dbg_rs1val_valid) begin
				h_reg_op1_eff_addr: assert(wrapper.uut.reg_op1 == wrapper.uut.dbg_rs1val + wrapper.uut.dbg_insn_imm);
			end
			if (wrapper.uut.mem_valid) begin
				h_mem_addr_word_aligned: assert(wrapper.uut.mem_addr[1:0] == 2'b00);
			end
			if (wrapper.uut.mem_valid && wrapper.uut.mem_do_rdata) begin
				h_mem_addr_from_reg_op1: assert(wrapper.uut.mem_addr[31:2] == wrapper.uut.reg_op1[31:2]);
			end
			if (checker_inst.spec_valid && !checker_inst.spec_trap) begin
				h_lhu_prev_data_xfer: assert($past(wrapper.uut.dbg_mem_valid && wrapper.uut.dbg_mem_ready && !wrapper.uut.dbg_mem_instr, 2));
				h_lhu_mem_addr_from_xfer: assert(checker_inst.spec_mem_addr == $past(wrapper.uut.dbg_mem_addr, 2));
			end
		end
	end

/// Helper Assertion End
endmodule
