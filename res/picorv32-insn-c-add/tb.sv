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

	// Helper invariants for proving the C.ADD RVFI checks inductively.
	// We relate the retired instruction (checker_inst.spec_*) to the internal
	// debug bookkeeping that feeds the RVFI signals in the previous cycle.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if (checker_inst.spec_valid) begin
				// If we are retiring a valid C.ADD, the RVFI event must not come from a trap.
				// (PicoRV32 asserts rvfi_valid on trap as well, but C.ADD should never trap.)
				h_c_add_not_from_trap: assert(!$past(wrapper.uut.trap));

				// When C.ADD consumes register operands, the core must have captured
				// the corresponding operand values for RVFI in the prior cycle.
				if (checker_inst.spec_rs1_addr != 0)
					h_c_add_rs1_captured: assert($past(wrapper.uut.dbg_rs1val_valid));
				if (checker_inst.spec_rs2_addr != 0)
					h_c_add_rs2_captured: assert($past(wrapper.uut.dbg_rs2val_valid));
			end
		end
	end

	// Basic PC alignment invariant: once the core has launched an instruction, the
	// tracked instruction address must remain 2-byte aligned (COMPRESSED_ISA=1).
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.dbg_valid_insn)
				h_pc_2byte_aligned: assert(wrapper.uut.dbg_insn_addr[0] == 1'b0);
		end
	end

	// While executing C.ADD (not in fetch), reg_next_pc must already be the
	// sequential next PC for the current instruction.
	wire h_is_c_add =
		(wrapper.uut.dbg_insn_opcode[31:16] == 16'b0) &&
		(wrapper.uut.dbg_insn_opcode[15:12] == 4'b1001) &&
		(wrapper.uut.dbg_insn_opcode[6:2] != 5'b0) &&
		(wrapper.uut.dbg_insn_opcode[1:0] == 2'b10);

	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.dbg_valid_insn && !wrapper.uut.trap && h_is_c_add) begin
				// During execution (non-fetch), reg_next_pc must be the sequential next PC.
				if (wrapper.uut.cpu_state != 8'h40)
					h_c_add_next_pc_seq: assert(wrapper.uut.reg_next_pc == wrapper.uut.dbg_insn_addr + 32'd2);

				// When launching the next instruction (retiring C.ADD), reg_next_pc must already
				// point to the sequential next instruction address.
				if (wrapper.uut.launch_next_insn)
					h_c_add_next_pc_at_launch: assert(wrapper.uut.reg_next_pc == wrapper.uut.dbg_insn_addr + 32'd2);

				// While executing C.ADD, the latched destination register must match the encoding.
				if (wrapper.uut.cpu_state != 8'h40)
					h_c_add_rd_matches_insn: assert(wrapper.uut.latched_rd == wrapper.uut.dbg_insn_opcode[11:7]);
			end
		end
	end

	// When C.ADD writes back, the write data must be the sum of captured operands.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpuregs_write && !wrapper.uut.trap && h_is_c_add &&
			    wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid) begin
				h_c_add_wdata_is_sum: assert(wrapper.uut.cpuregs_wrdata == wrapper.uut.dbg_rs1val + wrapper.uut.dbg_rs2val);
			end
		end
	end

/// Helper Assertion End
endmodule
