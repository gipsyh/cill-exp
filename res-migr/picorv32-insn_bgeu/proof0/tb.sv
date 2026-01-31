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
	) dut (
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
	// Helper decode for the instruction under check (BGEU).
	wire h_is_bgeu = (rvfi_insn[1:0] == 2'b11) && (rvfi_insn[6:0] == 7'b1100011) && (rvfi_insn[14:12] == 3'b111);
	wire h_dbg_is_bgeu = (dut.dbg_insn_opcode[1:0] == 2'b11) && (dut.dbg_insn_opcode[6:0] == 7'b1100011) && (dut.dbg_insn_opcode[14:12] == 3'b111);
	// PicoRV32 FSM encodings (from picorv32.sv localparams).
	localparam [7:0] H_CPU_STATE_TRAP  = 8'h80;
	localparam [7:0] H_CPU_STATE_FETCH = 8'h40;
	localparam [7:0] H_CPU_STATE_LD_RS1 = 8'h20;
	localparam [7:0] H_CPU_STATE_EXEC   = 8'h08;

	// BGEU immediate and derived PC candidates.
	// Explicit 32b sign-extension as an *unsigned* vector (mod-2^32 arithmetic).
	wire [31:0] h_bgeu_imm_u = {{19{rvfi_insn[31]}}, rvfi_insn[31], rvfi_insn[7], rvfi_insn[30:25], rvfi_insn[11:8], 1'b0};
	wire [31:0] h_bgeu_pc_plus4 = rvfi_pc_rdata + 32'd4;
	wire [31:0] h_bgeu_pc_plusimm = rvfi_pc_rdata + h_bgeu_imm_u;
	// Same immediates/PC candidates but using the core's debug-retirement view.
	wire [31:0] h_dbg_bgeu_imm_u = {{19{dut.dbg_insn_opcode[31]}}, dut.dbg_insn_opcode[31], dut.dbg_insn_opcode[7], dut.dbg_insn_opcode[30:25], dut.dbg_insn_opcode[11:8], 1'b0};
	wire [31:0] h_dbg_bgeu_pc_plus4 = dut.dbg_insn_addr + 32'd4;
	wire [31:0] h_dbg_bgeu_pc_plusimm = dut.dbg_insn_addr + h_dbg_bgeu_imm_u;

	// Track the exec->fetch boundary for BGEU so we can assert the core PC update is consistent.
	reg h_prev_exec_bgeu;
	reg h_expect_pc_update;
	reg [31:0] h_expect_pc_update_pc;

	// Scoreboard: remember the architecturally-relevant BGEU inputs/decision from EXEC
	// until the instruction retires (rvfi_valid).
	reg h_bgeu_inflight;
	reg [31:0] h_bgeu_pc_rdata;
	reg [31:0] h_bgeu_imm_u_hold;
	reg [31:0] h_bgeu_rs1_hold;
	reg [31:0] h_bgeu_rs2_hold;
	reg        h_bgeu_taken_hold;

	// PicoRV32 with compressed ISA must keep PC halfword-aligned (bit0==0).
	always @(posedge clock) begin
		// Record when we are in the first FETCH cycle after executing a BLTU.
		// In that cycle, reg_pc is updated at the clock edge to dut.next_pc.
		if (reset) begin
				h_prev_exec_bgeu <= 0;
			h_expect_pc_update <= 0;
			h_expect_pc_update_pc <= 0;
				h_bgeu_inflight <= 0;
				h_bgeu_pc_rdata <= 0;
				h_bgeu_imm_u_hold <= 0;
				h_bgeu_rs1_hold <= 0;
				h_bgeu_rs2_hold <= 0;
				h_bgeu_taken_hold <= 0;
		end else begin
				h_prev_exec_bgeu <= (dut.cpu_state == H_CPU_STATE_EXEC) && h_dbg_is_bgeu;
				h_expect_pc_update <= (dut.cpu_state == H_CPU_STATE_FETCH) && h_prev_exec_bgeu;
			h_expect_pc_update_pc <= dut.next_pc;

				// Capture the BGEU operands/imm/decision during EXEC and hold until retirement.
				if (dut.cpu_state == H_CPU_STATE_EXEC && h_dbg_is_bgeu) begin
					h_bgeu_inflight <= 1'b1;
					h_bgeu_pc_rdata <= dut.reg_pc;
					h_bgeu_imm_u_hold <= h_dbg_bgeu_imm_u;
					h_bgeu_rs1_hold <= dut.dbg_rs1val;
					h_bgeu_rs2_hold <= dut.dbg_rs2val;
					h_bgeu_taken_hold <= (dut.dbg_rs1val >= dut.dbg_rs2val);
			end
				if (rvfi_valid[0] && h_is_bgeu) begin
					h_bgeu_inflight <= 1'b0;
			end
		end

		if (!reset && h_expect_pc_update) begin
			dbg_bltu_pc_update: assert(dut.reg_pc == h_expect_pc_update_pc);
		end

		if (!reset) begin
			// IRQ is disabled in this configuration; the debug IRQ plumbing must stay inactive.
			irq_state_zero: assert(dut.irq_state == 2'b00);
			no_dbg_irq_call: assert(dut.dbg_irq_call == 1'b0);

			// dbg_insn_addr tracks the current instruction address while the core is executing it.
			if (dut.cpu_state != H_CPU_STATE_FETCH && dut.cpu_state != H_CPU_STATE_TRAP) begin
				dbg_addr_matches_pc: assert(dut.dbg_insn_addr == dut.reg_pc);
				// reg_next_pc is the sequential next PC for the current instruction (2B for C, 4B for normal).
				if (dut.latched_compr)
					reg_next_pc_compr: assert(dut.reg_next_pc == dut.reg_pc + 32'd2);
				else
					reg_next_pc_uncompr: assert(dut.reg_next_pc == dut.reg_pc + 32'd4);
			end

			// At the instruction boundary where the next instruction is launched, dbg_insn_addr/opcode
			// refer to the retiring instruction in the *current* cycle, while reg_pc is updated at
			// the clock edge. Therefore check the new reg_pc value one cycle later.
			if (!reset && $past(!reset) && $past(dut.dbg_valid_insn && dut.launch_next_insn && h_dbg_is_bgeu)) begin
				// dbg_insn_addr is updated from next_pc when an instruction is launched.
				dbg_bgeu_pc_wdata_oneof: assert(dut.dbg_insn_addr == $past(dut.next_pc));
			end

			// A BLTU cannot retire unless we have previously observed it in EXEC (scoreboard hit).
			if (!reset && dut.dbg_valid_insn && dut.launch_next_insn && h_dbg_is_bgeu) begin
				bgeu_inflight_pre_retire: assert(h_bgeu_inflight);
			end

			// Next-PC semantics for the retiring BLTU (same cycle as launch_next_insn).
			if (!reset && h_bgeu_inflight && dut.dbg_valid_insn && dut.launch_next_insn && h_dbg_is_bgeu) begin
				bgeu_operands_valid_at_retire: assert(dut.dbg_rs1val_valid && dut.dbg_rs2val_valid);
				bgeu_next_pc_oneof: assert((dut.next_pc == h_dbg_bgeu_pc_plus4) || (dut.next_pc == h_dbg_bgeu_pc_plusimm));
				bgeu_next_pc_matches_spec: assert(dut.next_pc == ((dut.dbg_rs1val >= dut.dbg_rs2val) ? h_dbg_bgeu_pc_plusimm : h_dbg_bgeu_pc_plus4));
			end

			// BLTU semantics inside the core datapath: operands and immediate must line up with
			// what will be reported via RVFI/debug signals.
			if (dut.cpu_state == H_CPU_STATE_EXEC && h_dbg_is_bgeu) begin
				dbg_bgeu_not_compressed: assert(!dut.latched_compr);
				dbg_bgeu_decoded_imm: assert(dut.decoded_imm == h_dbg_bgeu_imm_u);

				// BLTU reads both source registers; the core should have captured them and
				// the ALU compare must be using the same values.
				dbg_bgeu_rs1_valid: assert(dut.dbg_rs1val_valid);
				dbg_bgeu_rs2_valid: assert(dut.dbg_rs2val_valid);
				dbg_bgeu_rs1_match: assert(dut.reg_op1 == dut.dbg_rs1val);
				dbg_bgeu_rs2_match: assert(dut.reg_op2 == dut.dbg_rs2val);
				dbg_bgeu_cond_match: assert(dut.alu_out_0 == (dut.dbg_rs1val >= dut.dbg_rs2val));
			end

			// One cycle after executing BLTU, the core enters FETCH with the branch outcome latched.
			// At this point reg_pc is still the BLTU PC; reg_next_pc and reg_out must already hold
			// PC+4 and PC+imm respectively.
			if ($past(!reset) && dut.cpu_state == H_CPU_STATE_FETCH && $past(dut.cpu_state == H_CPU_STATE_EXEC && h_dbg_is_bgeu)) begin
				dbg_bgeu_fetch_dbg_addr_match: assert(dut.dbg_insn_addr == dut.reg_pc);
				dbg_bgeu_latched_branch: assert(dut.latched_branch == $past(dut.alu_out_0));
				dbg_bgeu_latched_store: assert(dut.latched_store == $past(dut.alu_out_0));
				dbg_bgeu_fetch_reg_next_pc: assert(dut.reg_next_pc == dut.reg_pc + 32'd4);
				dbg_bgeu_fetch_reg_out: assert(dut.reg_out == dut.reg_pc + h_dbg_bgeu_imm_u);
			end

			pc_aligned_core: assert(dut.reg_pc[0] == 1'b0);
			pc_aligned_core_next: assert(dut.reg_next_pc[0] == 1'b0);
			if (rvfi_valid[0]) begin
				pc_aligned_rvfi_r: assert(rvfi_pc_rdata[0] == 1'b0);
				pc_aligned_rvfi_w: assert(rvfi_pc_wdata[0] == 1'b0);

					// RVFI captures the retiring instruction from the debug interface one cycle earlier.
				if ($past(!reset)) begin
					rvfi_insn_matches_dbg: assert(rvfi_insn == $past(dut.dbg_insn_opcode));
					rvfi_pc_rdata_matches_dbg: assert(rvfi_pc_rdata == $past(dut.dbg_insn_addr));
				end
			end
		end
	
		if (!reset && rvfi_valid[0] && h_is_bgeu) begin
			// The retiring BGEU must correspond to a previously-executed BGEU (scoreboard hit).
			bgeu_inflight_hit: assert(h_bgeu_inflight);
			bgeu_pc_rdata_hold_match: assert(rvfi_pc_rdata == h_bgeu_pc_rdata);
			bgeu_rs1_hold_match: assert(rvfi_rs1_rdata == h_bgeu_rs1_hold);
			bgeu_rs2_hold_match: assert(rvfi_rs2_rdata == h_bgeu_rs2_hold);
			bgeu_taken_match: assert((rvfi_rs1_rdata >= rvfi_rs2_rdata) == h_bgeu_taken_hold);

			// During a BLTU retirement the core is already executing the *next* instruction,
			// so dut.reg_pc must match the reported PC writeback.
			bgeu_pc_wdata_is_core_pc: assert(rvfi_pc_wdata == dut.reg_pc);
			if ($past(!reset)) begin
				// Operand values reported via RVFI must match what the core captured for the retiring insn.
				bgeu_rs1_matches_dbg: assert(rvfi_rs1_rdata == $past(dut.dbg_rs1val));
				bgeu_rs2_matches_dbg: assert(rvfi_rs2_rdata == $past(dut.dbg_rs2val));
			end

			// If the instruction decodes as BLTU, it must not be reported as a trap/halt.
			no_trap: assert(!rvfi_trap[0]);
			no_halt: assert(!rvfi_halt[0]);

			// BLTU has no architectural register writeback.
			rd_addr_zero: assert(rvfi_rd_addr[4:0] == 5'd0);
			rd_wdata_zero: assert(rvfi_rd_wdata == 0);

			// For 32-bit branches, RVFI addresses must match the instruction fields.
			rs1_addr_match: assert((rvfi_rs1_addr[4:0] == rvfi_insn[19:15]));
			rs2_addr_match: assert((rvfi_rs2_addr[4:0] == rvfi_insn[24:20]));

			// If a source register is x0 then the captured value must be zero.
			rs1_x0_val: assert((rvfi_insn[19:15] != 5'd0) || (rvfi_rs1_rdata == 0));
			rs2_x0_val: assert((rvfi_insn[24:20] != 5'd0) || (rvfi_rs2_rdata == 0));

			// Structural lemma: BGEU can only jump to PC+4 or PC+imm.
			pc_wdata_oneof: assert((rvfi_pc_wdata == h_bgeu_pc_plus4) || (rvfi_pc_wdata == h_bgeu_pc_plusimm));
			spec_pc_oneof: assert((chk.spec_pc_wdata == h_bgeu_pc_plus4) || (chk.spec_pc_wdata == h_bgeu_pc_plusimm));
		end
	end
	/// Helper Assertion End
endmodule
