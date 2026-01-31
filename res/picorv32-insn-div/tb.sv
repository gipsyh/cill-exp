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

	// DIV (funct7=0000001, funct3=100, opcode=0110011) in RISCV_FORMAL_ALTOPS mode
	wire h_is_div_dbg =
		wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001 &&
		wrapper.uut.dbg_insn_opcode[14:12] == 3'b100 &&
		wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011;

	wire h_pcpi_insn_is_div =
		wrapper.uut.pcpi_insn[31:25] == 7'b0000001 &&
		wrapper.uut.pcpi_insn[14:12] == 3'b100 &&
		wrapper.uut.pcpi_insn[6:0] == 7'b0110011;

	wire [4:0] h_div_dbg_rd = wrapper.uut.dbg_insn_opcode[11:7];

	// Track the DIV writeback data so we can ensure RVFI keeps reporting it until retirement.
	reg        h_div_wb_seen;
	reg [4:0]  h_div_wb_rd;
	reg [31:0] h_div_wb_wdata;
	reg [31:0] h_div_wb_rs1;
	reg [31:0] h_div_wb_rs2;

	always @(posedge clock) begin
		if (reset) begin
			h_div_wb_seen <= 1'b0;
			h_div_wb_rd <= 5'b0;
			h_div_wb_wdata <= 32'b0;
			h_div_wb_rs1 <= 32'b0;
			h_div_wb_rs2 <= 32'b0;
		end else begin
			// RVFI retirement consumes the tracked writeback.
			if (wrapper.uut.rvfi_valid) begin
				h_div_wb_seen <= 1'b0;
				h_div_wb_rd <= 5'b0;
				h_div_wb_wdata <= 32'b0;
				h_div_wb_rs1 <= 32'b0;
				h_div_wb_rs2 <= 32'b0;
			end

			// Capture a DIV register writeback (destination comes from latched_rd in PicoRV32).
			if (wrapper.uut.cpuregs_write && h_is_div_dbg && (wrapper.uut.latched_rd != 0)) begin
				h_div_wb_seen <= 1'b1;
				h_div_wb_rd <= wrapper.uut.latched_rd;
				h_div_wb_wdata <= wrapper.uut.cpuregs_wrdata;
				h_div_wb_rs1 <= wrapper.uut.pcpi_rs1;
				h_div_wb_rs2 <= wrapper.uut.pcpi_rs2;
			end

			// Once we advance past the DIV (launch_next_insn), clear any pending tracking state.
			if (wrapper.uut.launch_next_insn && h_is_div_dbg && (wrapper.uut.latched_rd != 0)) begin
				h_div_wb_seen <= 1'b0;
				h_div_wb_rd <= 5'b0;
				h_div_wb_wdata <= 32'b0;
				h_div_wb_rs1 <= 32'b0;
				h_div_wb_rs2 <= 32'b0;
			end
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			// While waiting to retire a DIV (after observing its writeback), RVFI must keep
			// reporting that writeback. Allow RVFI to clear rd_wdata on valid cycles.
			h_div_wb_holds_rvfi: assert(!h_div_wb_seen || wrapper.uut.rvfi_valid || $past(reset) ||
			                            $past(wrapper.uut.rvfi_valid) ||
			                            (rvfi_rd_wdata == h_div_wb_wdata));

			// After the DIV writeback is observed, the operand registers must not drift before retirement.
			h_div_wb_operands_stable: assert(!h_div_wb_seen ||
			                                 ((wrapper.uut.reg_op1 == h_div_wb_rs1) &&
			                                  (wrapper.uut.reg_op2 == h_div_wb_rs2)));

			// The captured writeback must match the ALTOPS semantics for DIV.
			h_div_wb_wdata_matches_altops: assert(!h_div_wb_seen ||
			                                      (h_div_wb_wdata ==
			                                       ((h_div_wb_rs1 - h_div_wb_rs2) ^ 32'h7f8529ec)));

			// The writeback tracking state must only be active while DIV is the current instruction.
			h_div_wb_seen_implies_div: assert(!h_div_wb_seen || h_is_div_dbg);

			// A DIV with a non-zero destination must have produced a register writeback
			// before we advance to the next instruction (launch_next_insn).
			h_div_wb_before_launch: assert(!(wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn &&
			                                h_is_div_dbg && (h_div_dbg_rd != 0)) ||
			                               (wrapper.uut.cpuregs_write || h_div_wb_seen));
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			// IRQ logic is disabled in this configuration (ENABLE_IRQ=0), so irq_state must remain 0.
			h_irq_state_zero: assert(wrapper.uut.irq_state == 0);

			// Architectural rule: writes to x0 are discarded; RVFI must report a zero writeback.
			if (rvfi_rd_addr == 0)
				h_rd0_wdata_zero: assert(rvfi_rd_wdata == 0);

			// cpu_state is a one-hot FSM encoding in PicoRV32. Ruling out illegal encodings
			// removes unreachable "X-state" CTIs that can break induction.
			h_cpu_state_valid: assert(
				wrapper.uut.cpu_state == 8'b10000000 || // trap
				wrapper.uut.cpu_state == 8'b01000000 || // fetch
				wrapper.uut.cpu_state == 8'b00100000 || // ld_rs1
				wrapper.uut.cpu_state == 8'b00010000 || // ld_rs2
				wrapper.uut.cpu_state == 8'b00001000 || // exec
				wrapper.uut.cpu_state == 8'b00000100 || // shift
				wrapper.uut.cpu_state == 8'b00000010 || // stmem
				wrapper.uut.cpu_state == 8'b00000001    // ldmem
			);

			// For M-extension ops handled via PCPI, the debug operand snapshots must match
			// the operand registers presented to the PCPI units.
			if (wrapper.uut.cpu_state == 8'h20 /* cpu_state_ld_rs1 */ && wrapper.uut.instr_trap && h_is_div_dbg) begin
				h_div_pcpi_insn_is_div: assert(h_pcpi_insn_is_div);
			end

			// While DIV is the current instruction, operand snapshots must remain consistent with
			// the operand registers that drive the PCPI units.
			if (wrapper.uut.dbg_valid_insn && h_is_div_dbg) begin
				if (wrapper.uut.dbg_rs1val_valid)
					h_div_dbg_rs1_matches_op1: assert(wrapper.uut.dbg_rs1val == wrapper.uut.reg_op1);
				if (wrapper.uut.dbg_rs2val_valid)
					h_div_dbg_rs2_matches_op2: assert(wrapper.uut.dbg_rs2val == wrapper.uut.reg_op2);
			end

			// When the DIV PCPI core reports ready, its output must implement ALTOPS semantics.
			if (wrapper.uut.cpu_state == 8'h20 /* cpu_state_ld_rs1 */ && wrapper.uut.instr_trap &&
					wrapper.uut.pcpi_div_ready && h_pcpi_insn_is_div) begin
				// DIV takes multiple cycles; pcpi_div_ready must not be reachable on the first
				// cycle of ld_rs1 (otherwise reg_op* may still be transitioning).
				if ($past(!reset))
					h_div_pcpi_ready_after_wait: assert($past(wrapper.uut.cpu_state) == 8'h20 /* cpu_state_ld_rs1 */);

				// By the time DIV is ready, the operand registers must already be stable.
				if ($past(!reset)) begin
					h_div_reg_op1_stable_on_ready: assert(wrapper.uut.reg_op1 == $past(wrapper.uut.reg_op1));
					h_div_reg_op2_stable_on_ready: assert(wrapper.uut.reg_op2 == $past(wrapper.uut.reg_op2));
				end

				// Once DIV is ready, both operand snapshots must already be valid.
				h_div_operands_valid_when_ready: assert(wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid);

				// Architectural x0 reads must be zero at the PCPI operand interface.
				if (wrapper.uut.dbg_insn_opcode[19:15] == 0)
					h_div_rs1_x0_zero: assert(wrapper.uut.pcpi_rs1 == 0);
				if (wrapper.uut.dbg_insn_opcode[24:20] == 0)
					h_div_rs2_x0_zero: assert(wrapper.uut.pcpi_rs2 == 0);

				h_div_pcpi_int_rd_match: assert(wrapper.uut.pcpi_int_rd ==
					((wrapper.uut.pcpi_rs1 - wrapper.uut.pcpi_rs2) ^ 32'h7f8529ec));
			end

			// In the DIV writeback cycle, the register-file write must come from the PCPI result path.
			if (wrapper.uut.cpu_state == 8'h40 /* cpu_state_fetch */ &&
					wrapper.uut.latched_store && !wrapper.uut.latched_branch && h_is_div_dbg) begin
				h_div_wb_cycle_cpuregs_write: assert(wrapper.uut.cpuregs_write);
				h_div_wb_not_alu: assert(!wrapper.uut.latched_stalu);
				h_div_wb_wrdata_eq_reg_out: assert(wrapper.uut.cpuregs_wrdata == wrapper.uut.reg_out);

				// This writeback cycle must be the cycle immediately following the PCPI-div ready event.
				if ($past(!reset)) begin
					h_div_wb_prev_state_ld_rs1: assert($past(wrapper.uut.cpu_state) == 8'h20 /* cpu_state_ld_rs1 */);
					h_div_wb_prev_div_ready: assert($past(wrapper.uut.pcpi_div_ready));
					h_div_wb_wrdata_from_prev_pcpi: assert(wrapper.uut.cpuregs_wrdata == $past(wrapper.uut.pcpi_int_rd));
				end
			end

			// The retiring DIV instruction must report the same operand values that drive the PCPI div unit.
			if (checker_inst.spec_valid) begin
				// Architectural x0 reads must be reported as zero over RVFI.
				if (checker_inst.spec_rs1_addr == 0)
					h_div_rvfi_rs1_x0_zero: assert(rvfi_rs1_rdata == 0);
				if (checker_inst.spec_rs2_addr == 0)
					h_div_rvfi_rs2_x0_zero: assert(rvfi_rs2_rdata == 0);

				h_div_rvfi_rs1_matches_op1: assert(rvfi_rs1_rdata == wrapper.uut.reg_op1);
				h_div_rvfi_rs2_matches_op2: assert(rvfi_rs2_rdata == wrapper.uut.reg_op2);
				h_div_rvfi_rd_addr_matches_spec: assert(rvfi_rd_addr == checker_inst.spec_rd_addr);

				// For DIV with a non-zero destination register, RVFI must retire the exact writeback
				// observed on the cpuregs_write interface, with matching operands.
				if (checker_inst.spec_rd_addr != 0 && $past(!reset)) begin
					// Use the writeback observation from the previous cycle; the tracker may be cleared
					// on the same cycle as rvfi_valid is asserted.
					h_div_retire_wb_seen: assert($past(h_div_wb_seen));
					h_div_retire_wb_rd: assert(rvfi_rd_addr == $past(h_div_wb_rd));
					h_div_retire_wb_wdata: assert(rvfi_rd_wdata == $past(h_div_wb_wdata));
					h_div_retire_wb_rs1: assert(rvfi_rs1_rdata == $past(h_div_wb_rs1));
					h_div_retire_wb_rs2: assert(rvfi_rs2_rdata == $past(h_div_wb_rs2));
				end
			end
		end
	end

/// Helper Assertion End
endmodule
