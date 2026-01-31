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

	// Track the in-flight ADDI through EXEC so we can relate its operands/result
	// to the eventually reported RVFI retirement (which may be delayed by stalls).
	reg        h_addi_saw_exec;
	reg        h_addi_track_valid;
	reg [31:0] h_addi_track_rs1;
	reg [31:0] h_addi_track_imm;
	reg [ 4:0] h_addi_track_rd;
	reg [31:0] h_addi_track_wdata;
	always @(posedge clock) begin
		if (reset) begin
			h_addi_saw_exec <= 0;
			h_addi_track_valid <= 0;
			h_addi_track_rs1 <= 0;
			h_addi_track_imm <= 0;
			h_addi_track_rd <= 0;
			h_addi_track_wdata <= 0;
		end else begin
			// Clear once a retirement is reported; the next instruction starts after that.
			if (wrapper.uut.rvfi_valid) begin
				h_addi_saw_exec <= 0;
				h_addi_track_valid <= 0;
			end
			// Remember that we saw EXEC for an ADDI.
			else if (wrapper.uut.cpu_state == 8'h08 &&
					wrapper.uut.dbg_insn_opcode[6:0] == 7'b0010011 &&
					wrapper.uut.dbg_insn_opcode[14:12] == 3'b000 &&
					wrapper.uut.dbg_rs1val_valid) begin
				h_addi_saw_exec <= 1;
				h_addi_track_valid <= 1;
				h_addi_track_rs1 <= wrapper.uut.dbg_rs1val;
				h_addi_track_imm <= {{20{wrapper.uut.dbg_insn_opcode[31]}}, wrapper.uut.dbg_insn_opcode[31:20]};
				h_addi_track_rd <= wrapper.uut.dbg_insn_opcode[11:7];
				h_addi_track_wdata <= wrapper.uut.dbg_rs1val + {{20{wrapper.uut.dbg_insn_opcode[31]}}, wrapper.uut.dbg_insn_opcode[31:20]};
			end
		end
	end

	// Helper invariants that tie the current in-flight instruction (as tracked by
	// PicoRV32's debug/RVFI bookkeeping) to the decoder/control signals used by
	// the ALU. These block unreachable CTIs where the instruction opcode and the
	// executed operation become inconsistent.
	always @(posedge clock) begin
		if (!reset) begin
			// In execute stage, an ADDI must not be treated as SUB.
			if (wrapper.uut.cpu_state == 8'h08 && wrapper.uut.dbg_insn_opcode[6:0] == 7'b0010011 &&
					wrapper.uut.dbg_insn_opcode[14:12] == 3'b000) begin
				h_addi_not_sub: assert (!wrapper.uut.instr_sub);
				h_addi_exec_imm_matches_insn: assert (wrapper.uut.dbg_insn_imm ==
					{{20{wrapper.uut.dbg_insn_opcode[31]}}, wrapper.uut.dbg_insn_opcode[31:20]});
			end

			// If rs1 is x0, the captured rs1 value must be 0.
			if (wrapper.uut.dbg_valid_insn &&
					wrapper.uut.dbg_insn_opcode[6:0] == 7'b0010011 &&
					wrapper.uut.dbg_insn_opcode[14:12] == 3'b000 &&
					wrapper.uut.dbg_insn_opcode[19:15] == 5'd0 &&
					wrapper.uut.dbg_rs1val_valid) begin
				h_addi_rs1_x0_is_zero: assert (wrapper.uut.dbg_rs1val == 32'd0);
			end

			// When executing ADDI, the ALU operand reg_op1 must match the captured
			// RVFI/DBG rs1 value.
			if (wrapper.uut.cpu_state == 8'h08 && wrapper.uut.dbg_insn_opcode[6:0] == 7'b0010011 &&
					wrapper.uut.dbg_insn_opcode[14:12] == 3'b000 && wrapper.uut.dbg_rs1val_valid) begin
				h_addi_op1_matches_dbg: assert (wrapper.uut.reg_op1 == wrapper.uut.dbg_rs1val);
			end

			// Architectural x0 is hardwired to zero: writes to rd==0 must have wdata==0.
			if (wrapper.uut.rvfi_valid && !wrapper.uut.trap &&
					wrapper.uut.rvfi_insn[6:0] == 7'b0010011 &&
					wrapper.uut.rvfi_insn[14:12] == 3'b000 &&
					wrapper.uut.rvfi_insn[11:7] == 5'd0) begin
				h_addi_rd0_wdata0: assert (wrapper.uut.rvfi_rd_wdata == 32'd0);
			end

			// While we're tracking an ADDI (post-EXEC, pre-retirement), the live debug
			// fields must stay consistent with the tracked snapshot.
			if (h_addi_track_valid && !wrapper.uut.rvfi_valid && !wrapper.uut.trap && !wrapper.uut.dbg_next) begin
				h_addi_track_matches_dbg_rd: assert (wrapper.uut.dbg_insn_opcode[11:7] == h_addi_track_rd);
				h_addi_track_matches_dbg_imm: assert ({{20{wrapper.uut.dbg_insn_opcode[31]}}, wrapper.uut.dbg_insn_opcode[31:20]} == h_addi_track_imm);
				if (wrapper.uut.dbg_rs1val_valid)
					h_addi_track_matches_dbg_rs1: assert (wrapper.uut.dbg_rs1val == h_addi_track_rs1);
			end

			// When ADDI is being committed (writeback), the writeback data must match
			// the operands/result captured in EXEC.
			if (wrapper.uut.cpuregs_write && h_addi_track_valid && !wrapper.uut.trap &&
					!$past(reset) && $past(wrapper.uut.cpu_state) == 8'h08) begin
				h_addi_commit_rd: assert (wrapper.uut.latched_rd == h_addi_track_rd);
				h_addi_commit_wdata: assert (wrapper.uut.cpuregs_wrdata == h_addi_track_wdata);
			end

			// An ADDI reported via RVFI must have gone through EXEC for the ALU op.
			if (wrapper.uut.rvfi_valid && !wrapper.uut.trap &&
					wrapper.uut.rvfi_insn[6:0] == 7'b0010011 &&
					wrapper.uut.rvfi_insn[14:12] == 3'b000) begin
				h_addi_retire_after_exec: assert (h_addi_saw_exec);

				// Tie the reported retirement back to the operands/result captured in EXEC.
				h_addi_retire_track_valid: assert (h_addi_track_valid);
				h_addi_retire_track_rd: assert (wrapper.uut.rvfi_insn[11:7] == h_addi_track_rd);
				h_addi_retire_track_rs1: assert (wrapper.uut.rvfi_rs1_rdata == h_addi_track_rs1);
				h_addi_retire_track_imm: assert ({{20{wrapper.uut.rvfi_insn[31]}}, wrapper.uut.rvfi_insn[31:20]} == h_addi_track_imm);
				h_addi_retire_track_wdata: assert (wrapper.uut.rvfi_rd_wdata ==
					(wrapper.uut.rvfi_insn[11:7] == 5'd0 ? 32'd0 : h_addi_track_wdata));
			end

		end
	end

/// Helper Assertion End
endmodule
