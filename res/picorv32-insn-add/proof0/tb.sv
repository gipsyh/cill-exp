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

	reg h_trap_d;
	always @(posedge clock) begin
		if (reset)
			h_trap_d <= 1'b0;
		else
			h_trap_d <= wrapper.uut.trap;
	end

	always @(posedge clock) begin
		if (!reset)
			h_dbg_valid_insn_clears_after_trap: assert(!h_trap_d || !wrapper.uut.dbg_valid_insn);
	end

	always @(posedge clock) begin
		if (!reset)
			h_no_spec_valid_during_trap: assert(!(wrapper.uut.trap && checker_inst.spec_valid));
	end

	always @(posedge clock) begin
		if (!reset)
			h_no_dbg_irq_call: assert(!wrapper.uut.dbg_irq_call);
	end

	always @(posedge clock) begin
		if (!reset)
			h_no_add_and_sub: assert(!(wrapper.uut.instr_add && wrapper.uut.instr_sub));
	end

	wire h_dbg_is_add =
		(wrapper.uut.dbg_insn_opcode[6:0]   === 7'b0110011) &&
		(wrapper.uut.dbg_insn_opcode[14:12] === 3'b000) &&
		(wrapper.uut.dbg_insn_opcode[31:25] === 7'b0000000);

	always @(posedge clock) begin
		if (!reset)
			h_dbg_add_implies_instr_add: assert(!(wrapper.uut.cpuregs_write && h_dbg_is_add) || wrapper.uut.instr_add);
	end

	always @(posedge clock) begin
		if (!reset)
			h_rd_addr_matches_insn: assert(!checker_inst.spec_valid || (rvfi_rd_addr == rvfi_insn[11:7]));
	end

	reg h_add_wb_valid;
	reg [31:0] h_add_wb_rs1;
	reg [31:0] h_add_wb_rs2;
	reg [31:0] h_add_wb_wdata;
	reg [4:0] h_add_wb_rd;

	always @(posedge clock) begin
		if (reset) begin
			h_add_wb_valid <= 1'b0;
			h_add_wb_rs1 <= 32'b0;
			h_add_wb_rs2 <= 32'b0;
			h_add_wb_wdata <= 32'b0;
			h_add_wb_rd <= 5'b0;
		end else if (wrapper.uut.cpuregs_write && h_dbg_is_add &&
			     wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid) begin
			h_add_wb_valid <= 1'b1;
			h_add_wb_rs1 <= wrapper.uut.dbg_rs1val;
			h_add_wb_rs2 <= wrapper.uut.dbg_rs2val;
			h_add_wb_wdata <= wrapper.uut.cpuregs_wrdata;
			h_add_wb_rd <= wrapper.uut.latched_rd;
		end
	end

	always @(posedge clock) begin
		if (!reset)
			h_add_writeback_data_match: assert(!(wrapper.uut.cpuregs_write && h_dbg_is_add) || (
				wrapper.uut.dbg_rs1val_valid &&
				wrapper.uut.dbg_rs2val_valid &&
				wrapper.uut.cpuregs_wrdata == wrapper.uut.dbg_rs1val + wrapper.uut.dbg_rs2val
			));
	end

	always @(posedge clock) begin
		if (!reset)
			h_add_wb_aligns_with_retire: assert(!checker_inst.spec_valid || (
				h_add_wb_valid &&
				h_add_wb_rd == rvfi_insn[11:7] &&
				rvfi_rd_wdata == (h_add_wb_rd ? h_add_wb_wdata : 32'b0) &&
				checker_inst.insn_spec.rvfi_rs1_rdata == h_add_wb_rs1 &&
				checker_inst.insn_spec.rvfi_rs2_rdata == h_add_wb_rs2
			));
	end

	always @(posedge clock) begin
		if (!reset)
			h_add_wb_consistent: assert(!h_add_wb_valid || (h_add_wb_wdata == h_add_wb_rs1 + h_add_wb_rs2));
	end

/// Helper Assertion End
endmodule
