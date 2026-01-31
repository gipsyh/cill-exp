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

	// Post-reset the core always maintains halfword-aligned PCs (COMPRESSED_ISA=1).
	always @(posedge clock) begin
		if (!reset) begin
			h_reg_pc_aligned: assert (wrapper.uut.reg_pc[0] == 1'b0);
			h_reg_next_pc_aligned: assert (wrapper.uut.reg_next_pc[0] == 1'b0);
		end
	end

	// Structural invariants for PicoRV32's memory interface/control signals.
	// These mirror the core's own (commented) FORMAL checks and help rule out
	// unreachable control-state combinations that can create spurious CTIs.
	always @(posedge clock) begin
		if (!reset && !wrapper.uut.trap) begin
			if (wrapper.uut.mem_do_prefetch || wrapper.uut.mem_do_rinst || wrapper.uut.mem_do_rdata)
				h_mem_no_wdata: assert (!wrapper.uut.mem_do_wdata);

			if (wrapper.uut.mem_do_prefetch || wrapper.uut.mem_do_rinst)
				h_mem_no_rdata: assert (!wrapper.uut.mem_do_rdata);

			if (wrapper.uut.mem_do_rdata)
				h_mem_rdata_exclusive: assert (!wrapper.uut.mem_do_prefetch && !wrapper.uut.mem_do_rinst);

			if (wrapper.uut.mem_do_wdata)
				h_mem_wdata_exclusive: assert (!(wrapper.uut.mem_do_prefetch || wrapper.uut.mem_do_rinst || wrapper.uut.mem_do_rdata));

			if (wrapper.uut.mem_state == 2 || wrapper.uut.mem_state == 3)
				h_mem_state_valid_gate: assert (wrapper.uut.mem_valid || wrapper.uut.mem_do_prefetch);
		end
	end

	always @(posedge clock) begin
		if (!reset && wrapper.uut.mem_valid && wrapper.uut.mem_instr) begin
			h_mem_instr_readonly: assert (wrapper.uut.mem_wstrb == 0);
		end
	end

	reg h_last_mem_la_read = 0;
	reg h_last_mem_la_write = 0;
	reg [31:0] h_last_mem_la_addr = 0;
	reg [31:0] h_last_mem_la_wdata = 0;
	reg [3:0] h_last_mem_la_wstrb = 0;
	reg h_past_valid = 0;

	always @(posedge clock) begin
		if (reset) begin
			h_last_mem_la_read <= 0;
			h_last_mem_la_write <= 0;
			h_last_mem_la_addr <= 0;
			h_last_mem_la_wdata <= 0;
			h_last_mem_la_wstrb <= 0;
			h_past_valid <= 0;
		end else begin
			h_past_valid <= 1;
			// Sample the look-ahead request (if any) and ensure the core drives the
			// corresponding memory transaction in the following cycle.
			if (h_last_mem_la_read) begin
				h_mem_la_read_valid: assert (wrapper.uut.mem_valid);
				h_mem_la_read_addr: assert (wrapper.uut.mem_addr == h_last_mem_la_addr);
				h_mem_la_read_wstrb: assert (wrapper.uut.mem_wstrb == 0);
			end
			if (h_last_mem_la_write) begin
				h_mem_la_write_valid: assert (wrapper.uut.mem_valid);
				h_mem_la_write_addr: assert (wrapper.uut.mem_addr == h_last_mem_la_addr);
				h_mem_la_write_wdata: assert (wrapper.uut.mem_wdata == h_last_mem_la_wdata);
				h_mem_la_write_wstrb: assert (wrapper.uut.mem_wstrb == h_last_mem_la_wstrb);
			end
			if (wrapper.uut.mem_la_read || wrapper.uut.mem_la_write) begin
				h_mem_la_no_overlap: assert (!wrapper.uut.mem_valid || wrapper.uut.mem_ready);
			end

			h_last_mem_la_read <= wrapper.uut.mem_la_read;
			h_last_mem_la_write <= wrapper.uut.mem_la_write;
			h_last_mem_la_addr <= wrapper.uut.mem_la_addr;
			h_last_mem_la_wdata <= wrapper.uut.mem_la_wdata;
			h_last_mem_la_wstrb <= wrapper.uut.mem_la_wstrb;
		end
	end

	// When the retired instruction is C.J, the spec immediate should match the
	// core's debug immediate for the same instruction. The RVFI stream is a
	// 1-cycle delayed view of the debug stream, hence the $past().
	always @(posedge clock) begin
		if (!reset && h_past_valid && check && checker_inst.spec_valid) begin
			if (`rvformal_addr_valid(rvfi_pc_rdata) && !checker_inst.mem_access_fault) begin
				if (!checker_inst.spec_trap) begin
					h_dbg_imm_matches_spec: assert ($past(wrapper.uut.dbg_insn_imm) == checker_inst.insn_spec.insn_imm);
				end
			end
		end
	end

	// Ensure the debug pipeline's opcode/imm pair is coherent for C.J even when
	// the instruction is not being "checked" (rvfi_valid may be low). This helps
	// eliminate unreachable CTIs where the immediate lags the opcode.
	wire [31:0] h_q_cj_imm = $signed({wrapper.uut.q_insn_opcode[12], wrapper.uut.q_insn_opcode[8], wrapper.uut.q_insn_opcode[10], wrapper.uut.q_insn_opcode[9],
		wrapper.uut.q_insn_opcode[6], wrapper.uut.q_insn_opcode[7], wrapper.uut.q_insn_opcode[2], wrapper.uut.q_insn_opcode[11],
		wrapper.uut.q_insn_opcode[5], wrapper.uut.q_insn_opcode[4], wrapper.uut.q_insn_opcode[3], 1'b0});
	always @(posedge clock) begin
		if (!reset && h_past_valid && wrapper.uut.dbg_valid_insn && $past(wrapper.uut.dbg_valid_insn)) begin
			if (wrapper.uut.q_insn_opcode[31:16] == 0 && wrapper.uut.q_insn_opcode[15:13] == 3'b101 && wrapper.uut.q_insn_opcode[1:0] == 2'b01) begin
				h_q_insn_imm_matches_cj: assert (wrapper.uut.q_insn_imm == h_q_cj_imm);
			end
		end
	end

	// When C.J is the instruction being retired (launch_next_insn asserted),
	// next_pc must match PC+imm.
	wire [31:0] h_dbg_cj_imm = $signed({wrapper.uut.dbg_insn_opcode[12], wrapper.uut.dbg_insn_opcode[8], wrapper.uut.dbg_insn_opcode[10], wrapper.uut.dbg_insn_opcode[9],
		wrapper.uut.dbg_insn_opcode[6], wrapper.uut.dbg_insn_opcode[7], wrapper.uut.dbg_insn_opcode[2], wrapper.uut.dbg_insn_opcode[11],
		wrapper.uut.dbg_insn_opcode[5], wrapper.uut.dbg_insn_opcode[4], wrapper.uut.dbg_insn_opcode[3], 1'b0});
	always @(posedge clock) begin
		if (!reset && h_past_valid && wrapper.uut.dbg_valid_insn && $past(wrapper.uut.dbg_valid_insn)) begin
			if (wrapper.uut.launch_next_insn && !wrapper.uut.trap) begin
				if (wrapper.uut.dbg_insn_opcode[31:16] == 0 && wrapper.uut.dbg_insn_opcode[15:13] == 3'b101 && wrapper.uut.dbg_insn_opcode[1:0] == 2'b01) begin
					h_next_pc_matches_cj: assert (wrapper.uut.next_pc == wrapper.uut.dbg_insn_addr + h_dbg_cj_imm);
				end
			end
		end
	end

	// Decoder invariants: when an instruction fetch completes, instr_jal must
	// reflect the opcode that was fetched/latched (including compressed C.J/C.JAL).
	always @(posedge clock) begin
		if (!reset && h_past_valid) begin
			if ($past(wrapper.uut.mem_do_rinst && wrapper.uut.mem_done)) begin
				h_instr_jal_matches_fetched_opcode: assert (wrapper.uut.instr_jal ==
					($past(wrapper.uut.mem_rdata_latched[6:0]) == 7'b1101111 ||
					($past(wrapper.uut.mem_rdata_latched[1:0]) == 2'b01 &&
						($past(wrapper.uut.mem_rdata_latched[15:13]) == 3'b001 ||
						 $past(wrapper.uut.mem_rdata_latched[15:13]) == 3'b101))));
			end
		end
	end

	// In PicoRV32, a taken JAL/J must raise latched_branch in the following cycle.
	// This blocks unreachable traces where the jump is decoded but not treated as a branch.
	always @(posedge clock) begin
		if (!reset && h_past_valid) begin
			if ($past(wrapper.uut.cpu_state == 8'h40 && wrapper.uut.decoder_trigger && wrapper.uut.instr_jal && !wrapper.uut.trap)) begin
				h_latched_branch_follows_jal: assert (wrapper.uut.latched_branch);
			end
		end
	end

	// After a JAL/J is taken, the core immediately starts fetching the next
	// instruction (mem_do_rinst asserted in the following cycle).
	always @(posedge clock) begin
		if (!reset && h_past_valid) begin
			if ($past(wrapper.uut.cpu_state == 8'h40 && wrapper.uut.decoder_trigger && wrapper.uut.instr_jal && !wrapper.uut.trap)) begin
				h_mem_do_rinst_after_jal: assert (wrapper.uut.mem_do_rinst);
			end
		end
	end

	// dbg_next is the registered version of launch_next_insn used by the debug/RVFI stream.
	always @(posedge clock) begin
		if (!reset && h_past_valid) begin
			h_dbg_next_tracks_launch: assert (wrapper.uut.dbg_next == $past(wrapper.uut.launch_next_insn));
		end
	end

	// RVFI/debug stream bookkeeping (1-cycle registered relationships).
	always @(posedge clock) begin
		if (!reset && h_past_valid) begin
			h_rvfi_pc_rdata_tracks_dbg_addr: assert (wrapper.uut.rvfi_pc_rdata == $past(wrapper.uut.dbg_insn_addr));
			h_rvfi_insn_tracks_dbg_opcode: assert (wrapper.uut.rvfi_insn == $past(wrapper.uut.dbg_insn_opcode));
			h_q_insn_opcode_tracks_dbg_opcode: assert (wrapper.uut.q_insn_opcode == $past(wrapper.uut.dbg_insn_opcode));
			h_q_insn_imm_tracks_dbg_imm: assert (wrapper.uut.q_insn_imm == $past(wrapper.uut.dbg_insn_imm));
		end
	end

	// Once the debug stream is "live", the debug PC should only advance on retired instructions.
	always @(posedge clock) begin
		if (!reset && h_past_valid && wrapper.uut.dbg_valid_insn && $past(wrapper.uut.dbg_valid_insn)) begin
			if (!rvfi_valid) begin
				h_dbg_pc_stable_when_no_rvfi: assert (wrapper.uut.dbg_insn_addr == $past(wrapper.uut.dbg_insn_addr));
			end
		end
	end

/// Helper Assertion End
endmodule
