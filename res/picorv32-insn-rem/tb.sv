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

	// Track completed REM operations until they are reported via RVFI.
	reg h_rem_pending;
	reg [31:0] h_rem_rs1;
	reg [31:0] h_rem_rs2;
	reg [31:0] h_rem_wdata;

	// IRQ is disabled (picorv32 default ENABLE_IRQ=0).
	always @(posedge clock) begin
		if (!reset) begin
			h_irq_state_zero: assert (wrapper.uut.irq_state == 0);
		end
	end

	// When debug operand values are marked valid, they must match the operands
	// latched for execution (used by the PCPI interface as well).
	always @(posedge clock) begin
		if (!reset) begin
			// dbg_* signals are not reset; also, reg_op* may be repurposed for
			// non-PCPI instructions (e.g., address calculation). Only relate them
			// while a PCPI instruction is active.
			if (wrapper.uut.dbg_valid_insn && wrapper.uut.pcpi_valid && wrapper.uut.dbg_rs1val_valid)
				h_dbg_rs1_matches_op1: assert (wrapper.uut.dbg_rs1val == wrapper.uut.reg_op1);
			if (wrapper.uut.dbg_valid_insn && wrapper.uut.pcpi_valid && wrapper.uut.dbg_rs2val_valid)
				h_dbg_rs2_matches_op2: assert (wrapper.uut.dbg_rs2val == wrapper.uut.reg_op2);
		end
	end

	always @(posedge clock) begin
		if (reset) begin
			h_rem_pending <= 0;
			h_rem_rs1 <= 0;
			h_rem_rs2 <= 0;
			h_rem_wdata <= 0;
		end else begin
			// Push on PCPI DIV completion for REM.
			if (wrapper.uut.pcpi_div_ready &&
					wrapper.uut.pcpi_insn[6:0] == 7'b0110011 && wrapper.uut.pcpi_insn[31:25] == 7'b0000001 && wrapper.uut.pcpi_insn[14:12] == 3'b110) begin
				h_rem_no_overflow: assert (!h_rem_pending);
				h_rem_pending <= 1;
				h_rem_rs1 <= wrapper.uut.pcpi_rs1;
				h_rem_rs2 <= wrapper.uut.pcpi_rs2;
				h_rem_wdata <= wrapper.uut.pcpi_insn[11:7] != 0 ? wrapper.uut.pcpi_div_rd : 0;
			end

			// Pop on RVFI report of REM.
			if (rvfi_valid[0] &&
					rvfi_insn[6:0] == 7'b0110011 && rvfi_insn[31:25] == 7'b0000001 && rvfi_insn[14:12] == 3'b110) begin
				h_rem_pending_on_report: assert (h_rem_pending);
				h_rem_rs1_match: assert (rvfi_rs1_rdata == h_rem_rs1);
				h_rem_rs2_match: assert (rvfi_rs2_rdata == h_rem_rs2);
				h_rem_wdata_match: assert (rvfi_rd_wdata == h_rem_wdata);
				h_rem_pending <= 0;
			end
		end
	end

	// When checking REM specifically, rd==x0 must imply no architectural writeback.
	always @(posedge clock) begin
		if (!reset) begin
			if (rvfi_valid[0] && !rvfi_trap[0] && !rvfi_intr[0] &&
					rvfi_insn[6:0] == 7'b0110011 && rvfi_insn[31:25] == 7'b0000001 && rvfi_insn[14:12] == 3'b110 &&
					rvfi_insn[11:7] == 5'b00000)
				h_rem_rd_x0_zero: assert (rvfi_rd_wdata == 0);
		end
	end

	// For PCPI operations, the instruction seen by the PCPI cores must match the
	// instruction tracked by the debug/RVFI machinery.
	always @(posedge clock) begin
		if (!reset) begin
			// pcpi_valid is also used to probe unsupported/illegal insns. Restrict
			// this consistency check to the M-extension ops handled by the internal
			// PCPI mul/div cores.
			if (wrapper.uut.pcpi_valid && wrapper.uut.pcpi_insn[6:0] == 7'b0110011 && wrapper.uut.pcpi_insn[31:25] == 7'b0000001)
				h_pcpi_insn_matches_dbg: assert (wrapper.uut.pcpi_insn == wrapper.uut.dbg_insn_opcode);
		end
	end

	// The RVFI stream reports the source register values from the previous cycle's
	// dbg_rs* capture. For REM, both source operands must have been captured.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if (rvfi_valid[0] &&
					rvfi_insn[6:0] == 7'b0110011 && rvfi_insn[31:25] == 7'b0000001 && rvfi_insn[14:12] == 3'b110) begin
				h_past_dbg_rs1_valid_rem: assert ($past(wrapper.uut.dbg_rs1val_valid));
				h_past_dbg_rs2_valid_rem: assert ($past(wrapper.uut.dbg_rs2val_valid));
			end
		end
	end

	// If REM uses x0 as rs2, the captured rs2 data must be zero.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if (rvfi_valid[0] &&
					rvfi_insn[6:0] == 7'b0110011 && rvfi_insn[31:25] == 7'b0000001 && rvfi_insn[14:12] == 3'b110 &&
					rvfi_insn[24:20] == 5'b00000)
				h_rem_rs2_x0_rdata: assert ($past(wrapper.uut.dbg_rs2val) == 0);
		end
	end

	// If REM uses x0 as rs1, the captured rs1 data must be zero.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if (rvfi_valid[0] &&
					rvfi_insn[6:0] == 7'b0110011 && rvfi_insn[31:25] == 7'b0000001 && rvfi_insn[14:12] == 3'b110 &&
					rvfi_insn[19:15] == 5'b00000)
				h_rem_rs1_x0_rdata: assert ($past(wrapper.uut.dbg_rs1val) == 0);
		end
	end

	// When retiring REM, the fast-mul core must not be the source of a PCPI result.
	always @(posedge clock) begin
		if (!reset) begin
			if (checker_inst.spec_valid) begin
				h_rem_no_mul_ready: assert (!wrapper.uut.pcpi_mul_ready);
				h_rem_no_mul_wr: assert (!wrapper.uut.pcpi_mul_wr);
			end
		end
	end

	// Fast-mul PCPI interface produces 1-cycle pulses for ready/wr.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_pcpi_mul_ready_pulse: assert (!(wrapper.uut.pcpi_mul_ready && $past(wrapper.uut.pcpi_mul_ready)));
			h_pcpi_mul_wr_pulse: assert (!(wrapper.uut.pcpi_mul_wr && $past(wrapper.uut.pcpi_mul_wr)));
		end
	end

	// No spurious PCPI completion when the core is not issuing a PCPI operation.
	always @(posedge clock) begin
		if (!reset) begin
			h_pcpi_int_ready_implies_valid: assert (!wrapper.uut.pcpi_int_ready || wrapper.uut.pcpi_valid);
			h_pcpi_int_wr_implies_valid: assert (!wrapper.uut.pcpi_int_wr || wrapper.uut.pcpi_valid);
		end
	end

	// When the div PCPI core reports REM ready, its result must match the ALTOPS
	// function used by the riscv-formal instruction model.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.pcpi_div_ready &&
					wrapper.uut.pcpi_insn[6:0] == 7'b0110011 && wrapper.uut.pcpi_insn[31:25] == 7'b0000001 && wrapper.uut.pcpi_insn[14:12] == 3'b110)
				h_pcpi_div_rem_result: assert (wrapper.uut.pcpi_div_rd == ((wrapper.uut.pcpi_rs1 - wrapper.uut.pcpi_rs2) ^ 32'h8da68fa5));
		end
	end

	// When REM commits a register writeback (latched_store in fetch), the writeback
	// data must match the ALTOPS function of the captured operands.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == wrapper.uut.cpu_state_fetch &&
					wrapper.uut.cpuregs_write && wrapper.uut.latched_store &&
					wrapper.uut.dbg_valid_insn &&
					wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011 && wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001 && wrapper.uut.dbg_insn_opcode[14:12] == 3'b110) begin
				h_rem_wb_rs1_valid: assert (wrapper.uut.dbg_rs1val_valid);
				h_rem_wb_rs2_valid: assert (wrapper.uut.dbg_rs2val_valid);
				h_rem_wbdata_correct: assert (wrapper.uut.cpuregs_wrdata ==
					((((wrapper.uut.dbg_insn_opcode[19:15] != 0) ? wrapper.uut.dbg_rs1val : 0) -
					  ((wrapper.uut.dbg_insn_opcode[24:20] != 0) ? wrapper.uut.dbg_rs2val : 0)) ^ 32'h8da68fa5));
			end
		end
	end

	// After REM has completed and the writeback cycle has passed (latched_store cleared),
	// rvfi_rd_wdata must already hold the REM result until it is reported via RVFI.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == wrapper.uut.cpu_state_fetch &&
					!wrapper.uut.latched_store &&
					!wrapper.uut.pcpi_valid &&
					wrapper.uut.dbg_valid_insn &&
					wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid &&
					wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011 && wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001 && wrapper.uut.dbg_insn_opcode[14:12] == 3'b110) begin
				h_rem_hold_wdata: assert (rvfi_rd_wdata ==
					(wrapper.uut.dbg_insn_opcode[11:7] != 0 ?
						((((wrapper.uut.dbg_insn_opcode[19:15] != 0) ? wrapper.uut.dbg_rs1val : 0) -
						  ((wrapper.uut.dbg_insn_opcode[24:20] != 0) ? wrapper.uut.dbg_rs2val : 0)) ^ 32'h8da68fa5) :
						0));
			end
		end
	end

/// Helper Assertion End
endmodule
