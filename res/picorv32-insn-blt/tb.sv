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

	// Strengthen induction by checking BLT next-PC calculation at the point where
	// the core is about to advance dbg_insn_addr (i.e., when next_pc is consumed).
	//
	// This aligns the check with the internal timing of PicoRV32's RVFI signals:
	// rvfi_* at cycle t+1 are derived from dbg_* at cycle t, while rvfi_pc_wdata at
	// cycle t+1 comes from next_pc computed at cycle t.
	wire        h_blt_is_insn =
			(wrapper.uut.dbg_insn_opcode[6:0]  == 7'b1100011) &&
			(wrapper.uut.dbg_insn_opcode[14:12] == 3'b100);

	wire [31:0] h_blt_rs1 = wrapper.uut.dbg_rs1val_valid ? wrapper.uut.dbg_rs1val : 32'd0;
	wire [31:0] h_blt_rs2 = wrapper.uut.dbg_rs2val_valid ? wrapper.uut.dbg_rs2val : 32'd0;

	wire [31:0] h_blt_imm = $signed({
		wrapper.uut.dbg_insn_opcode[31],
		wrapper.uut.dbg_insn_opcode[7],
		wrapper.uut.dbg_insn_opcode[30:25],
		wrapper.uut.dbg_insn_opcode[11:8],
		1'b0
	});

	wire        h_blt_cond = $signed(h_blt_rs1) < $signed(h_blt_rs2);
	wire [31:0] h_blt_spec_next_pc = h_blt_cond ? (wrapper.uut.dbg_insn_addr + h_blt_imm)
	                                            : (wrapper.uut.dbg_insn_addr + 32'd4);
	wire        h_blt_spec_trap = h_blt_spec_next_pc[0]; // IALIGN=16 (COMPRESSED), misa_ok is always true here.

	// Track whether we were in FETCH on the previous cycle (used to express simple
	// one-cycle temporal invariants without heavy $past usage).
	reg h_prev_fetch;
	always @(posedge clock) begin
		if (reset)
			h_prev_fetch <= 1'b0;
		else
			h_prev_fetch <= (wrapper.uut.cpu_state == 8'h40); // cpu_state_fetch
	end

	always @(posedge clock) begin
		if (!reset) begin
			// PicoRV32 keeps PCs halfword-aligned when COMPRESSED_ISA is enabled.
			h_reg_pc_aligned: assert (wrapper.uut.reg_pc[0] == 1'b0);
			h_reg_next_pc_aligned: assert (wrapper.uut.reg_next_pc[0] == 1'b0);

			// In steady FETCH (i.e., not just entering FETCH), the writeback latch must
			// already have been cleared.
			if (h_prev_fetch && wrapper.uut.cpu_state == 8'h40) begin // cpu_state_fetch
				h_fetch_clears_latched_store: assert (!wrapper.uut.latched_store);
			end

			// During instruction execution (i.e., not in fetch), the debug instruction
			// address matches the core PC.
			if (wrapper.uut.dbg_valid_insn && wrapper.uut.cpu_state != 8'h40) begin // cpu_state_fetch
				h_dbg_insn_addr_matches_reg_pc: assert (wrapper.uut.dbg_insn_addr == wrapper.uut.reg_pc);
			end

			// When the instruction uses x0 as a source register, the captured operand
			// value must be zero as well.
			if (wrapper.uut.dbg_valid_insn && wrapper.uut.dbg_rs1val_valid &&
			    wrapper.uut.dbg_insn_opcode[1:0] == 2'b11 &&
			    wrapper.uut.dbg_insn_opcode[19:15] == 5'd0) begin
				h_dbg_rs1_x0_zero: assert (wrapper.uut.dbg_rs1val == 32'd0);
			end
			if (wrapper.uut.dbg_valid_insn && wrapper.uut.dbg_rs2val_valid &&
			    wrapper.uut.dbg_insn_opcode[1:0] == 2'b11 &&
			    wrapper.uut.dbg_insn_opcode[24:20] == 5'd0) begin
				h_dbg_rs2_x0_zero: assert (wrapper.uut.dbg_rs2val == 32'd0);
			end

			// A BLT instruction must never be "in flight" while the core is in the
			// store-memory state. This rules out spurious (unreachable) mismatches
			// between dbg_insn_* and the microarchitectural state machine.
			if (h_blt_is_insn) begin
				h_blt_not_in_stmem: assert (wrapper.uut.cpu_state != 8'h02); // cpu_state_stmem
			end

			// When executing BLT, the internal compare result must match the spec
			// condition computed from the captured operands.
			if (h_blt_is_insn && wrapper.uut.cpu_state == 8'h08 && // cpu_state_exec
			    wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid) begin
				h_blt_decoded_imm_match: assert (wrapper.uut.decoded_imm == h_blt_imm);
				h_blt_cond_matches_alu: assert (wrapper.uut.alu_out_0 == h_blt_cond);
				h_blt_exec_fallthrough_pc: assert (wrapper.uut.reg_next_pc == wrapper.uut.reg_pc + 32'd4);
			end

			// At the point where the core is about to advance dbg_insn_addr, next_pc
			// must match the architectural BLT next-PC.
			if (wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn && h_blt_is_insn && !h_blt_spec_trap) begin
				// BLT uses the branch datapath; it cannot look like a JAL-style update.
				h_blt_branch_latch_consistent: assert (!wrapper.uut.latched_branch || wrapper.uut.latched_store);
				// Small arithmetic lemma: with PC[2:0]=3'b100, both fallthrough (+4) and
				// branch targets with imm[2]=1 force next_pc[2]=0 due to carry.
				if (wrapper.uut.dbg_insn_addr[2:0] == 3'b100 && h_blt_imm[2] == 1'b1) begin
					h_blt_nextpc_bit2_carry: assert (wrapper.uut.next_pc[2] == 1'b0);
				end
				// Another carry lemma for the not-taken path: PC[3:2]=2'b11 plus 4 wraps to
				// PC'[3:2]=2'b00.
				if (wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid &&
				    !h_blt_cond && wrapper.uut.dbg_insn_addr[3:2] == 2'b11) begin
					h_blt_fallthrough_carry32: assert (wrapper.uut.next_pc[3:2] == 2'b00);
				end
				// If the branch offset is a multiple of 4, both taken and not-taken paths
				// preserve PC[1:0] (BLT is always 32-bit, so fallthrough is +4).
				if (h_blt_imm[1] == 1'b0) begin
					h_blt_nextpc_preserve_low2: assert (wrapper.uut.next_pc[1:0] == wrapper.uut.dbg_insn_addr[1:0]);
				end
				// Matching the low bits eliminates many spurious CTIs caused by unreachable
				// debug/PC combinations (especially around 16-bit alignment boundaries).
				h_blt_nextpc_match_low5: assert (wrapper.uut.next_pc[4:0] == h_blt_spec_next_pc[4:0]);
				// Full architectural next-PC for BLT (used to prove the original property).
				h_blt_next_pc_match: assert (wrapper.uut.next_pc == h_blt_spec_next_pc);
			end

			// BLT itself must not drive the core into the trap state unless the spec
			// also predicts a trap (e.g., misaligned target).
			if (wrapper.uut.dbg_valid_insn && h_blt_is_insn && !h_blt_spec_trap) begin
				h_blt_no_unexpected_trap: assert (!wrapper.trap);
			end

			// (no direct assertion of h_blt_spec_next_pc here)
		end
	end

/// Helper Assertion End
endmodule
