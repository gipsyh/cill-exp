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
	// Helper decode for the instruction under check (SLTI).
	// (I-type: opcode=0010011, funct3=010)
	wire h_is_slti = (rvfi_insn[6:0] == 7'b0010011) && (rvfi_insn[14:12] == 3'b010);
	// Use dbg_insn_opcode (full 32b for non-compressed insns) for a matching decode.
	wire h_dbg_is_slti = (dut.dbg_insn_opcode[6:0] == 7'b0010011) && (dut.dbg_insn_opcode[14:12] == 3'b010);

	// SLTI compares rs1 against a sign-extended 12b immediate, using signed compare.
	wire [31:0] h_slti_imm = {{20{rvfi_insn[31]}}, rvfi_insn[31:20]};
	wire [31:0] h_dbg_slti_imm = dut.dbg_insn_imm;
	// Expected SLTI result: rd = (rs1 < imm) ? 1 : 0 (signed compare).
	wire [31:0] h_slti_result = ($signed(rvfi_rs1_rdata) < $signed(h_slti_imm)) ? 32'd1 : 32'd0;
	wire [31:0] h_dbg_slti_result = ($signed(dut.dbg_rs1val) < $signed(h_dbg_slti_imm)) ? 32'd1 : 32'd0;

	// Track the most recent SLTI writeback seen at the datapath.
	reg h_wb_pending;
	reg [31:0] h_wb_data;
	reg [31:0] h_wb_rs1;
	reg [31:0] h_wb_imm;
	reg h_wb_rd_zero;
	reg [4:0] h_wb_rd;
	reg [4:0] h_wb_rs1_addr;

	// When the checker is enabled and the instruction model matches (i.e. SLTI retires),
	// the architectural writeback data must be a 0/1 value (upper bits zero).
	// This blocks spurious X-bit rd_wdata hard transitions and helps o_rd_wdata_match.
	always @* begin
		if (!reset && check && chk.spec_valid) begin
			slti_wdata_hi0: assert(rvfi_rd_wdata[31:1] == 0);
			slti_wdata_bit0: assert(rvfi_rd_wdata[0] == chk.spec_rd_wdata[0]);
		end
	end

	always @(posedge clock) begin
		if (reset) begin
			h_wb_pending <= 0;
			h_wb_data <= 0;
			h_wb_rs1 <= 0;
			h_wb_imm <= 0;
			h_wb_rd_zero <= 0;
			h_wb_rd <= 0;
			h_wb_rs1_addr <= 0;
		end else begin
			if (dut.cpuregs_write && h_dbg_is_slti) begin
				h_wb_pending <= 1;
				h_wb_data <= (dut.latched_rd != 0) ? dut.cpuregs_wrdata : 0;
				h_wb_rs1 <= dut.dbg_rs1val;
				h_wb_imm <= dut.dbg_insn_imm;
				h_wb_rd_zero <= (dut.latched_rd == 0);
				h_wb_rd <= dut.dbg_insn_opcode[11:7];
				h_wb_rs1_addr <= dut.dbg_insn_opcode[19:15];
			end

			if (rvfi_valid[0] && h_is_slti) begin
				h_wb_pending <= 0;
				// If the instruction decodes as SLTI, it must not be reported as a trap/halt.
				no_trap: assert(!rvfi_trap[0]);
				no_halt: assert(!rvfi_halt[0]);
				// SLTI retirement must observe its writeback.
				wb_seen: assert(h_wb_pending);
				wb_data_match: assert((rvfi_rd_wdata == h_wb_data));
				wb_rs1_match: assert((rvfi_rs1_rdata == h_wb_rs1));
				wb_rd_match: assert((rvfi_insn[11:7] == h_wb_rd));
				wb_rs1_addr_match: assert((rvfi_insn[19:15] == h_wb_rs1_addr));
				wb_imm_match: assert((h_slti_imm == h_wb_imm));
				// Helper to make rd_wdata matching easier: SLTI result is always 0/1.
				slti_result_match: assert(rvfi_rd_wdata[31:1] == 0);
				// When check is enabled, also require full match to the spec model.
				if (check) begin
					rd_wdata_match: assert((chk.spec_rd_wdata == rvfi_rd_wdata));
				end
				// For 32-bit SLTI, RVFI rd/rs1 addresses must match the instruction fields.
				rd_addr_match:  assert((rvfi_rd_addr[4:0] == rvfi_insn[11:7]));
				rs1_addr_match: assert((rvfi_rs1_addr[4:0] == rvfi_insn[19:15]));
			end

			if (dut.cpuregs_write && h_dbg_is_slti) begin
				// For SLTI, the retiring instruction must have captured rs1 (no rs2 operand).
				src_captured: assert(dut.dbg_rs1val_valid);
				no_rs2_capture: assert(!dut.dbg_rs2val_valid);
				// For SLTI, if rs1 is x0 then the captured value must be zero.
				rs1_x0_val: assert((dut.dbg_insn_opcode[19:15] != 5'd0) || (dut.dbg_rs1val == 0));
				// For SLTI, the core decode must reflect SLTI (not SLTIU).
				instr_flag: assert(dut.instr_slti);
				not_sltiu: assert(!dut.instr_sltiu);
				// SLTI is a compare: for non-x0 rd the writeback must be 0/1 (upper bits zero).
				hi0: assert(dut.cpuregs_wrdata[31:1] == 0 && h_dbg_slti_result[31:1] == 0);
				// The retiring writeback data must match the captured operand and immediate.
				// For SLTI, only low 1 bit of result can be set.
				wrdata_match: assert(dut.cpuregs_wrdata[0] == h_dbg_slti_result[0]);
				// SLTI must not be treated as a control-flow change at retirement.
				no_branch: assert(!dut.latched_branch);
			end

			wb_consistent: assert(!h_wb_pending ||
				(h_wb_rd_zero ? (h_wb_data == 0) : (h_wb_data == (($signed(h_wb_rs1) < $signed(h_wb_imm)) ? 32'd1 : 32'd0))));
			// If the retired instruction has no rd, the reported writeback data must be zero.
			addr0_wdata0: assert(!(rvfi_valid[0] && (rvfi_rd_addr[4:0] == 5'd0)) || (rvfi_rd_wdata == 0));
		end
	end
	/// Helper Assertion End
endmodule
