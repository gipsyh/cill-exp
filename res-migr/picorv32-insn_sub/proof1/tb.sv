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
	// Helper decode for the instruction under check (SUB).
	wire h_is_sub = (rvfi_insn[6:0] == 7'b0110011) && (rvfi_insn[14:12] == 3'b000) &&
		(rvfi_insn[31:25] == 7'b0100000);
	wire h_dbg_is_sub = (dut.dbg_insn_opcode[6:0] == 7'b0110011) &&
		(dut.dbg_insn_opcode[14:12] == 3'b000) && (dut.dbg_insn_opcode[31:25] == 7'b0100000);

	// Track the most recent SUB writeback seen at the datapath.
	reg h_wb_pending;
	reg [31:0] h_wb_data;
	reg [31:0] h_wb_rs1;
	reg [31:0] h_wb_rs2;
	reg h_wb_rd_zero;
	reg [4:0] h_wb_rd;
	reg [4:0] h_wb_rs1_addr;
	reg [4:0] h_wb_rs2_addr;

	always @(posedge clock) begin
		if (reset) begin
			h_wb_pending <= 0;
			h_wb_data <= 0;
			h_wb_rs1 <= 0;
			h_wb_rs2 <= 0;
			h_wb_rd_zero <= 0;
			h_wb_rd <= 0;
			h_wb_rs1_addr <= 0;
			h_wb_rs2_addr <= 0;
		end else begin
			if (dut.cpuregs_write && h_dbg_is_sub) begin
				h_wb_pending <= 1;
				h_wb_data <= (dut.latched_rd != 0) ? dut.cpuregs_wrdata : 0;
				h_wb_rs1 <= dut.dbg_rs1val;
				h_wb_rs2 <= dut.dbg_rs2val;
				h_wb_rd_zero <= (dut.latched_rd == 0);
				h_wb_rd <= dut.dbg_insn_opcode[11:7];
				h_wb_rs1_addr <= dut.dbg_insn_opcode[19:15];
				h_wb_rs2_addr <= dut.dbg_insn_opcode[24:20];
			end

			if (rvfi_valid[0] && h_is_sub) begin
				h_wb_pending <= 0;
				// If the instruction decodes as SUB, it must not be reported as a trap/halt.
				no_trap: assert(!rvfi_trap[0]);
				no_halt: assert(!rvfi_halt[0]);
				// SUB retirement must observe its writeback.
				wb_seen: assert(h_wb_pending);
				wb_data_match: assert((rvfi_rd_wdata == h_wb_data));
				wb_rs1_match: assert((rvfi_rs1_rdata == h_wb_rs1));
				wb_rs2_match: assert((rvfi_rs2_rdata == h_wb_rs2));
				wb_rd_match: assert((rvfi_insn[11:7] == h_wb_rd));
				wb_rs1_addr_match: assert((rvfi_insn[19:15] == h_wb_rs1_addr));
				wb_rs2_addr_match: assert((rvfi_insn[24:20] == h_wb_rs2_addr));
				// Stronger (check-independent) form of rd_wdata_match objective.
				rd_wdata_match: assert((chk.spec_rd_wdata == rvfi_rd_wdata));
				// For 32-bit SUB, RVFI addresses must match the instruction fields.
				rd_addr_match:  assert((rvfi_rd_addr[4:0] == rvfi_insn[11:7]));
				rs1_addr_match: assert((rvfi_rs1_addr[4:0] == rvfi_insn[19:15]));
				rs2_addr_match: assert((rvfi_rs2_addr[4:0] == rvfi_insn[24:20]));
				// For SUB, the reported writeback must equal rs1 - rs2 when rd is not x0.
				sub_result_match: assert((rvfi_rd_addr[4:0] == 5'd0) || (rvfi_rd_wdata == (rvfi_rs1_rdata - rvfi_rs2_rdata)));
				// sub_result_0: assert(!(rvfi_rd_addr[4:0] == 5'd0) || (rvfi_rd_wdata == 0));
			end

			if (dut.cpuregs_write && h_dbg_is_sub) begin
				// For SUB, the retiring instruction must have captured both source operands.
				src_captured: assert((dut.dbg_rs1val_valid && dut.dbg_rs2val_valid));
				// For SUB, if a source register is x0 then the captured value must be zero.
				rs1_x0_val: assert((dut.dbg_insn_opcode[19:15] != 5'd0) || (dut.dbg_rs1val == 0));
				rs2_x0_val: assert((dut.dbg_insn_opcode[24:20] != 5'd0) || (dut.dbg_rs2val == 0));
				// SUB must not be executed as ADD.
				not_add: assert(!dut.instr_add);
				// For SUB, the core decode must reflect a SUB.
				instr_flag: assert(dut.instr_sub);
				// For SUB, the retiring writeback data must match the captured operands.
				wrdata_match: assert(dut.cpuregs_wrdata == (dut.dbg_rs1val - dut.dbg_rs2val));
				// SUB must not be treated as a control-flow change at retirement.
				no_branch: assert(!dut.latched_branch);
			end

			wb_consistent: assert(!h_wb_pending ||
				(h_wb_rd_zero ? (h_wb_data == 0) : (h_wb_data == (h_wb_rs1 - h_wb_rs2))));
			// If the retired instruction has no rd, the reported writeback data must be zero.
			addr0_wdata0: assert(!(rvfi_valid[0] && (rvfi_rd_addr[4:0] == 5'd0)) || (rvfi_rd_wdata == 0));
		end
	end
	/// Helper Assertion End
endmodule
