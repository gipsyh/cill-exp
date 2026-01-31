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
	// Decode MULHU from the internal debug instruction word.
	wire h_is_mulhu_dbg = (wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011) &&
	                      (wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001) &&
	                      (wrapper.uut.dbg_insn_opcode[14:12] == 3'b011);
	wire h_is_divrem_dbg = (wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011) &&
	                       (wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001) &&
	                       (wrapper.uut.dbg_insn_opcode[14:12] inside {3'b100, 3'b101, 3'b110, 3'b111});
	wire [4:0] h_dbg_rd = wrapper.uut.dbg_insn_opcode[11:7];
	wire [31:0] h_dbg_rs1_or_zero = (wrapper.uut.dbg_insn_opcode[19:15] != 0) ? wrapper.uut.dbg_rs1val : 0;
	wire [31:0] h_dbg_rs2_or_zero = (wrapper.uut.dbg_insn_opcode[24:20] != 0) ? wrapper.uut.dbg_rs2val : 0;
	wire [31:0] h_mulhu_exp_wdata = (h_dbg_rs1_or_zero + h_dbg_rs2_or_zero) ^ 32'h949ce5e8;

	// Track the MULHU writeback data across variable memory latency between writeback and launch_next_insn.
	reg h_mulhu_wb_seen;
	reg [4:0] h_mulhu_wb_rd;
	reg [31:0] h_mulhu_wb_wdata;

	always @(posedge clock) begin
		if (reset) begin
			h_mulhu_wb_seen <= 0;
			h_mulhu_wb_rd <= 0;
			h_mulhu_wb_wdata <= 0;
		end else begin
			// RVFI convention: no destination register implies no write data.
			h_rd0_wdata0: assert((wrapper.uut.rvfi_rd_addr != 0) || (wrapper.uut.rvfi_rd_wdata == 0));

			// For MULHU, the reported destination register must match the instruction.
			h_mulhu_rdaddr_match: assert($past(reset) ||
			                             !$past(wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn && h_is_mulhu_dbg) ||
			                             (wrapper.uut.rvfi_rd_addr == $past(h_dbg_rd)));

			// By the time we advance past a MULHU, both operand values must be available.
			h_mulhu_operands_valid: assert(!(wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn && h_is_mulhu_dbg) ||
			                               (wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid));

			// When the PCPI MUL unit reports ready for MULHU, its output must match the spec.
			h_mulhu_pcpi_rd_match: assert(!(wrapper.uut.pcpi_int_ready && wrapper.uut.dbg_valid_insn && h_is_mulhu_dbg) ||
			                              (wrapper.uut.pcpi_int_rd == h_mulhu_exp_wdata));

			// For MULHU, when there is a real destination register, the RVFI writeback data must match the spec.
			h_mulhu_wdata_match: assert(!(wrapper.uut.cpuregs_write && wrapper.uut.dbg_valid_insn && h_is_mulhu_dbg &&
			                              (h_dbg_rd != 0)) ||
			                            (wrapper.uut.cpuregs_wrdata == h_mulhu_exp_wdata));

			// When we advance past a MULHU, its writeback must have occurred already (or occur now).
			// This blocks states where RVFI reports a MULHU retirement without a corresponding writeback.
			h_mulhu_wb_before_launch: assert(!(wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn && h_is_mulhu_dbg &&
			                                   (h_dbg_rd != 0)) ||
			                                 ((wrapper.uut.cpuregs_write && (wrapper.uut.cpuregs_wrdata == h_mulhu_exp_wdata)) ||
			                                  (h_mulhu_wb_seen && (h_mulhu_wb_rd == h_dbg_rd) &&
			                                   (h_mulhu_wb_wdata == h_mulhu_exp_wdata))));

			// While we're waiting to retire a MULHU (after seeing its writeback), RVFI must keep reporting that writeback.
			// Allow RVFI to clear rd_wdata on valid cycles for non-writing retirements.
			h_mulhu_wb_holds_rvfi: assert(!h_mulhu_wb_seen || wrapper.uut.rvfi_valid || $past(reset) ||
			                              $past(wrapper.uut.rvfi_valid) ||
			                              (wrapper.uut.rvfi_rd_wdata == h_mulhu_wb_wdata));

			// The MULHU writeback tracking state must only be active while MULHU is the current instruction.
			h_mulhu_wb_seen_implies_mulhu: assert(!h_mulhu_wb_seen || (wrapper.uut.dbg_valid_insn && h_is_mulhu_dbg));

			// MULHU itself should not lead to a core trap (illegal instruction/misalignment).
			h_mulhu_not_trap: assert(!wrapper.uut.trap || !h_is_mulhu_dbg);

			// PCPI-DIV must only report ready in response to a div/rem instruction.
			// This prevents stale DIV results from being (incorrectly) consumed by unrelated instructions.
			h_divready_matches_divinsn: assert(!wrapper.uut.pcpi_div_ready || h_is_divrem_dbg);

			// IRQ logic is disabled in this configuration (ENABLE_IRQ=0), so irq_state must remain 0.
			h_irq_state_zero: assert(wrapper.uut.irq_state == 0);

			// Capture/consume the MULHU writeback observation.
			if (wrapper.uut.rvfi_valid) begin
				h_mulhu_wb_seen <= 0;
				h_mulhu_wb_rd <= 0;
				h_mulhu_wb_wdata <= 0;
			end
			if (wrapper.uut.cpuregs_write && wrapper.uut.dbg_valid_insn && h_is_mulhu_dbg && (h_dbg_rd != 0)) begin
				h_mulhu_wb_seen <= 1;
				h_mulhu_wb_rd <= h_dbg_rd;
				h_mulhu_wb_wdata <= h_mulhu_exp_wdata;
			end
			if (wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn && h_is_mulhu_dbg && (h_dbg_rd != 0)) begin
				h_mulhu_wb_seen <= 0;
				h_mulhu_wb_rd <= 0;
				h_mulhu_wb_wdata <= 0;
			end
		end
	end

/// Helper Assertion End
endmodule
