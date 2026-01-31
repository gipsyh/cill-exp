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

	// Helper invariants to make the rvfi_pc_wdata property inductive.
	// These only constrain the post-reset behavior of the DUT's debug/RVFI pipeline.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			// dbg_next is a 1-cycle delayed copy of launch_next_insn.
			h_dbg_next_pipeline: assert (wrapper.uut.dbg_next == $past(wrapper.uut.launch_next_insn));
		end
	end

	// PC must remain halfword-aligned when compressed ISA is enabled (PC[0] is always 0).
	always @(posedge clock) begin
		if (!reset) begin
			h_reg_pc_aligned: assert (wrapper.uut.reg_pc[0] == 1'b0);
			h_reg_next_pc_aligned: assert (wrapper.uut.reg_next_pc[0] == 1'b0);
		end
	end

	// For C.JAL the offset is always even (imm[0]=0) and the PC is halfword-aligned (PC[0]=0),
	// so the next PC bit[1] must be PC[1] XOR imm[1] (imm[1] is rvfi_insn[3]).
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid) begin
			h_cjal_pc_bit1: assert (rvfi_pc_wdata[1] == (rvfi_pc_rdata[1] ^ rvfi_insn[3]));
		end
	end

	// Strengthen the C.JAL proof with a small-width PC update check to cover carry interactions.
	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid) begin
			h_cjal_pc_low6: assert (rvfi_pc_wdata[5:0] == checker_inst.spec_pc_wdata[5:0]);
		end
	end

	always @(posedge clock) begin
		if (!reset && checker_inst.spec_valid) begin
			h_cjal_pc_low7: assert (rvfi_pc_wdata[6:0] == checker_inst.spec_pc_wdata[6:0]);
		end
	end

	// Connect the debug/RVFI stream to the core PC pipeline: when we are about to
	// retire a C.JAL (rvfi instruction comes from dbg_insn_opcode/dbg_insn_addr),
	// the core's next_pc must match the CJ-immediate PC update.
	wire h_is_cjal_dbg = (wrapper.uut.dbg_insn_opcode[31:16] == 16'b0) &&
		(wrapper.uut.dbg_insn_opcode[15:13] == 3'b001) &&
		(wrapper.uut.dbg_insn_opcode[1:0] == 2'b01);
	wire signed [31:0] h_cjal_imm_dbg = $signed({
		wrapper.uut.dbg_insn_opcode[12],
		wrapper.uut.dbg_insn_opcode[8],
		wrapper.uut.dbg_insn_opcode[10],
		wrapper.uut.dbg_insn_opcode[9],
		wrapper.uut.dbg_insn_opcode[6],
		wrapper.uut.dbg_insn_opcode[7],
		wrapper.uut.dbg_insn_opcode[2],
		wrapper.uut.dbg_insn_opcode[11],
		wrapper.uut.dbg_insn_opcode[5],
		wrapper.uut.dbg_insn_opcode[4],
		wrapper.uut.dbg_insn_opcode[3],
		1'b0
	});
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn && h_is_cjal_dbg && !wrapper.uut.trap && !wrapper.uut.dbg_irq_call) begin
				h_cjal_next_pc_matches_dbg: assert (wrapper.uut.next_pc == wrapper.uut.dbg_insn_addr + h_cjal_imm_dbg);
			end
		end
	end

	// Keep the decoded jump immediate consistent with the fetched compressed instruction word.
	wire h_is_cjal_fetch = (wrapper.uut.mem_rdata_latched[15:13] == 3'b001) &&
		(wrapper.uut.mem_rdata_latched[1:0] == 2'b01);
	wire signed [31:0] h_cjal_imm_fetch = $signed({
		wrapper.uut.mem_rdata_latched[12],
		wrapper.uut.mem_rdata_latched[8],
		wrapper.uut.mem_rdata_latched[10],
		wrapper.uut.mem_rdata_latched[9],
		wrapper.uut.mem_rdata_latched[6],
		wrapper.uut.mem_rdata_latched[7],
		wrapper.uut.mem_rdata_latched[2],
		wrapper.uut.mem_rdata_latched[11],
		wrapper.uut.mem_rdata_latched[5],
		wrapper.uut.mem_rdata_latched[4],
		wrapper.uut.mem_rdata_latched[3],
		1'b0
	});
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			// decoded_imm_j is loaded from mem_rdata_latched at the clock edge where the fetch completes.
			if ($past(wrapper.uut.mem_do_rinst && wrapper.uut.mem_done && h_is_cjal_fetch)) begin
				h_cjal_decoded_imm_matches: assert (wrapper.uut.decoded_imm_j == $past(h_cjal_imm_fetch));
			end
		end
	end

	// JAL/J (including compressed variants) update reg_next_pc by adding decoded_imm_j to the
	// current PC. The decode happens one cycle before the fetch-stage state machine consumes it,
	// so check the update using $past().
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if ($past(wrapper.uut.cpu_state == 8'b01000000) && $past(wrapper.uut.decoder_trigger) && $past(wrapper.uut.instr_jal)) begin
				h_jal_updates_reg_next_pc: assert (wrapper.uut.reg_next_pc == $past(wrapper.uut.reg_next_pc) + $past(wrapper.uut.decoded_imm_j));
			end
		end
	end

/// Helper Assertion End
endmodule
