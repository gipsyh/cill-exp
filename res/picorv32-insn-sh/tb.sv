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

	// When the SH instruction retires without a trap, the core must be reporting a
	// data (not instruction-fetch) memory transfer for that instruction. Otherwise
	// the RVFI mem_* fields can be clobbered by instruction fetches, creating
	// unreachable CTIs for o_mem_addr_match.
	always @(posedge clock) begin
		if (!reset) begin
			if (checker_inst.spec_valid && !checker_inst.spec_trap) begin
				h_sh_mem_is_data: assert (!wrapper.mem_instr);
				h_sh_no_core_trap: assert (!wrapper.trap);
			end
		end
	end

	// The core only supports byte/halfword/word accesses. `mem_wordsize` must not
	// take the unused 2'b11 encoding while a data memory operation is active.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.mem_do_wdata || wrapper.uut.mem_do_rdata) begin
				h_mem_wordsize_valid: assert (wrapper.uut.mem_wordsize != 2'b11);
			end
		end
	end

	// When the core launches a new instruction, no data memory operation may
	// still be in-flight.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.launch_next_insn) begin
				h_no_dmem_on_launch: assert (!wrapper.uut.mem_do_wdata && !wrapper.uut.mem_do_rdata);
			end
		end
	end

	// For halfword stores, the data bus address must match rs1 + imm (word-aligned),
	// where imm is the S-type immediate from the (decompressed) instruction word.
	wire signed [31:0] h_sh_imm =
		$signed({{20{wrapper.uut.dbg_insn_opcode[31]}}, wrapper.uut.dbg_insn_opcode[31:25], wrapper.uut.dbg_insn_opcode[11:7]});
	wire [31:0] h_sh_addr = wrapper.uut.dbg_rs1val + h_sh_imm;
	wire [31:0] h_sh_base = h_sh_addr & 32'hffff_fffc;
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.dbg_rs1val_valid &&
					wrapper.uut.mem_do_wdata && (wrapper.uut.mem_wordsize == 2'd1) &&
					!wrapper.mem_instr && wrapper.mem_valid && wrapper.mem_ready) begin
				h_sh_dmem_addr_calc: assert (wrapper.mem_addr == h_sh_base);
			end
		end
	end

/// Helper Assertion End
endmodule
