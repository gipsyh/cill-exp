`default_nettype none
`include "defines.sv"

module testbench (
	input check,
	input clock, reset
);
	// RVFI signals between DUT and checker
	// No worry about macro content - inspect dut.xxx and chk.xxx signals directly instead.
	`RVFI_WIRES

	// Free variables for formal verification (non-deterministic inputs)
	(* keep *) wire trap;
	(* keep *) `rvformal_rand_reg mem_ready;
	(* keep *) `rvformal_rand_reg [31:0] mem_rdata;
	(* keep *) wire mem_valid;
	(* keep *) wire mem_instr;
	(* keep *) wire [31:0] mem_addr;
	(* keep *) wire [31:0] mem_wdata;
	(* keep *) wire [3:0]  mem_wstrb;

	// Instantiate picorv32 core
	picorv32 #(
		.COMPRESSED_ISA(1),
		.ENABLE_FAST_MUL(1), .ENABLE_DIV(1),
		.BARREL_SHIFTER(1)
	) uut (
		.clk(clock), .resetn(!reset), .trap(trap),
		.mem_valid(mem_valid), .mem_instr(mem_instr),
		.mem_ready(mem_ready), .mem_addr(mem_addr),
		.mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
		.mem_rdata(mem_rdata),
		`RVFI_CONN
	);

	// Instantiate the formal property checker
	rvfi_insn_check chk (
		.clock(clock), .reset(reset), .check(check),
		`RVFI_CONN
	);
	
	// Prevent unrealistic loopback: all 1 rvfi_order creates circular dependency.
	reg rvfi_order_loopback;
	always@(posedge clock) begin
		if (reset) begin
			rvfi_order_loopback <= 0;
		end else if (rvfi_valid && rvfi_order == {64{1'b1}}) begin
			rvfi_order_loopback <= 1;
		end
	end
	always_comb assume (!(rvfi_order_loopback && check));

/// Helper Assertion Begin

	// Helper invariant for JAL: when a JAL instruction retires, the next PC
	// must be PC + imm (UJ-type immediate, sign-extended).
	always @(posedge clock) begin
		if (!reset && !trap && uut.launch_next_insn && uut.dbg_valid_insn &&
				uut.dbg_insn_opcode[6:0] == 7'b1101111) begin
			// UJ immediate with explicit 32b sign-extension to avoid signedness surprises.
			logic [31:0] jal_imm;
			jal_imm = {{11{uut.dbg_insn_opcode[31]}}, uut.dbg_insn_opcode[31],
				uut.dbg_insn_opcode[19:12], uut.dbg_insn_opcode[20], uut.dbg_insn_opcode[30:21], 1'b0};
			h_jal_nextpc: assert(uut.next_pc ==
				(uut.dbg_insn_addr + jal_imm));
		end
	end

/// Helper Assertion End
endmodule
