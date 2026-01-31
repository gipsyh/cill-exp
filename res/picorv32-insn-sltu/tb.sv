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

	// After an instruction fetch completes (mem_done), the core clears mem_do_rinst
	// on the next cycle unless it explicitly re-issues a fetch (which doesn't
	// happen from cpu_state_fetch).
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_mem_do_rinst_clears_after_done_in_fetch: assert(
				!($past(wrapper.uut.cpu_state) == 8'b0100_0000 && $past(wrapper.uut.mem_done)) ||
				!wrapper.uut.mem_do_rinst
			);
		end
	end

	// Keep the debug pipeline aligned: dbg_next is the registered launch_next_insn.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_dbg_next_tracks_launch_next_insn: assert(wrapper.uut.dbg_next == $past(wrapper.uut.launch_next_insn));
		end
	end

	// For SLTU, the architectural result is a single bit (0/1), so the upper
	// bits of rd_wdata must be zero whenever the SLTU checker is active.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_sltu_rd_wdata_is_1bit: assert(rvfi_rd_wdata[31:1] == 0);
		end
	end

	// During execution of SLTU, the ALU operands must match the debug-captured
	// register values that feed the RVFI operand signals.
	always @(posedge clock) begin
		if (!reset && wrapper.uut.cpu_state == 8'b0000_1000 && wrapper.uut.instr_sltu) begin
			h_sltu_exec_operands_match_dbg: assert(
				(wrapper.uut.reg_op1 == wrapper.uut.dbg_rs1val) &&
				(wrapper.uut.reg_op2 == wrapper.uut.dbg_rs2val)
			);
		end
	end

	// Special case: rs2==x0 implies (rs1 < rs2) is always false for SLTU.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_sltu_rs2_x0_forces_zero: assert((checker_inst.spec_rs2_addr != 0) || (rvfi_rd_wdata == 0));
		end
	end

	// Special case: rs1==x0 implies (rs1 < rs2) is true iff rs2 != 0 for SLTU.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_sltu_rs1_x0_matches_rs2_nonzero: assert(
				(checker_inst.spec_rs1_addr != 0) ||
				(rvfi_rd_addr == 0) ||
				(rvfi_rd_wdata[0] == (rvfi_rs2_rdata != 0))
			);
		end
	end

	// Main SLTU functional relation for bit 0 of rd_wdata (upper bits handled above).
	wire [31:0] h_sltu_rs1_val = (rvfi_insn[19:15] != 0) ? rvfi_rs1_rdata : 0;
	wire [31:0] h_sltu_rs2_val = (rvfi_insn[24:20] != 0) ? rvfi_rs2_rdata : 0;

	// Pre-commit SLTU consistency: when the debug pipeline indicates that an SLTU
	// will be retired on the next cycle (launch_next_insn), then the next-cycle
	// RVFI rd_wdata must already be determined by either the pending writeback
	// (cpuregs_write) or the held rd_wdata register value.
	wire h_sltu_dbg_is_sltu =
		(wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011) &&
		(wrapper.uut.dbg_insn_opcode[14:12] == 3'b011) &&
		(wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000000);

	wire [4:0] h_sltu_dbg_rs1 = wrapper.uut.dbg_insn_opcode[19:15];
	wire [4:0] h_sltu_dbg_rs2 = wrapper.uut.dbg_insn_opcode[24:20];
	wire [4:0] h_sltu_dbg_rd  = wrapper.uut.dbg_insn_opcode[11:7];

	wire [31:0] h_sltu_dbg_rs1_val =
		(h_sltu_dbg_rs1 != 0 && wrapper.uut.dbg_rs1val_valid) ? wrapper.uut.dbg_rs1val : 0;
	wire [31:0] h_sltu_dbg_rs2_val =
		(h_sltu_dbg_rs2 != 0 && wrapper.uut.dbg_rs2val_valid) ? wrapper.uut.dbg_rs2val : 0;

	wire [31:0] h_sltu_expected_wdata =
		(h_sltu_dbg_rd != 0) ? {31'b0, (h_sltu_dbg_rs1_val < h_sltu_dbg_rs2_val)} : 0;

	wire [31:0] h_sltu_next_rvfi_rd_wdata_pred =
		(wrapper.uut.cpuregs_write && !wrapper.uut.irq_state) ? (wrapper.uut.latched_rd ? wrapper.uut.cpuregs_wrdata : 0) :
		(wrapper.uut.rvfi_valid ? 0 : wrapper.uut.rvfi_rd_wdata);

	always @(posedge clock) begin
		if (!reset && !wrapper.uut.trap && wrapper.uut.dbg_valid_insn && wrapper.uut.launch_next_insn && h_sltu_dbg_is_sltu) begin
			h_sltu_precommit_next_rd_wdata_matches_spec: assert(h_sltu_next_rvfi_rd_wdata_pred == h_sltu_expected_wdata);
		end
	end

	// Another easy corner case for unsigned compare: the maximum value is never
	// strictly less than any 32-bit operand.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_sltu_rs1_max_forces_zero: assert(
				(h_sltu_rs1_val != 32'hFFFF_FFFF) ||
				(rvfi_rd_addr == 0) ||
				(rvfi_rd_wdata[0] == 1'b0)
			);
		end
	end

	// Another easy corner case: 0x7FFF_FFFF is the maximum value with MSB==0.
	// If rs2 also has MSB==0, then rs1 < rs2 is impossible.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_sltu_rs1_max_msb0_forces_zero: assert(
				(h_sltu_rs1_val != 32'h7FFF_FFFF) ||
				(h_sltu_rs2_val[31] == 1'b1) ||
				(rvfi_rd_addr == 0) ||
				(rvfi_rd_wdata[0] == 1'b0)
			);
		end
	end

	// Unsigned compare shortcut: if MSBs differ, they fully determine the result.
	always @(posedge clock) begin
		if (!reset && check && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_sltu_msb_shortcuts_compare: assert(
				(h_sltu_rs1_val[31] == h_sltu_rs2_val[31]) ||
				(rvfi_rd_addr == 0) ||
				(rvfi_rd_wdata[0] == (~h_sltu_rs1_val[31] & h_sltu_rs2_val[31]))
			);
		end
	end

	// Unsigned compare shortcut for the next-most-significant bit when MSBs match.
	always @(posedge clock) begin
		if (!reset && check && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_sltu_bit30_shortcuts_compare: assert(
				(h_sltu_rs1_val[31] != h_sltu_rs2_val[31]) ||
				(h_sltu_rs1_val[30] == h_sltu_rs2_val[30]) ||
				(rvfi_rd_addr == 0) ||
				(rvfi_rd_wdata[0] == (~h_sltu_rs1_val[30] & h_sltu_rs2_val[30]))
			);
		end
	end

	// Unsigned compare shortcut for bit 29 when bits [31:30] match.
	always @(posedge clock) begin
		if (!reset && check && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_sltu_bit29_shortcuts_compare: assert(
				(h_sltu_rs1_val[31] != h_sltu_rs2_val[31]) ||
				(h_sltu_rs1_val[30] != h_sltu_rs2_val[30]) ||
				(h_sltu_rs1_val[29] == h_sltu_rs2_val[29]) ||
				(rvfi_rd_addr == 0) ||
				(rvfi_rd_wdata[0] == (~h_sltu_rs1_val[29] & h_sltu_rs2_val[29]))
			);
		end
	end

	// RVFI should report the architectural destination register for SLTU.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_sltu_rd_addr_matches_insn_rd: assert(rvfi_rd_addr == rvfi_insn[11:7]);
		end
	end

	// When rd==x0, RVFI must report a zero write value (writes to x0 are discarded).
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_sltu_rd_x0_forces_zero_wdata: assert((rvfi_rd_addr != 0) || (rvfi_rd_wdata == 0));
		end
	end

	// RVFI source register addresses must match the instruction fields for SLTU.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid && !checker_inst.spec_trap) begin
			h_sltu_rs_addrs_match_insn_fields: assert(
				(rvfi_rs1_addr == rvfi_insn[19:15]) &&
				(rvfi_rs2_addr == rvfi_insn[24:20])
			);
		end
	end

/// Helper Assertion End
endmodule
