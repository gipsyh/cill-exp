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
	// Helper decode for the instruction under check (AUIPC).
	wire h_is_auipc = (rvfi_insn[6:0] == 7'b0010111);
	wire h_dbg_is_auipc = (dut.dbg_insn_opcode[6:0] == 7'b0010111);

	// AUIPC uses a U-immediate: bits [31:12] followed by 12 zeros (treated as signed).
	wire [31:0] h_rvfi_auipc_imm = $signed({rvfi_insn[31:12], 12'b0});
	wire [31:0] h_dbg_auipc_imm  = $signed({dut.dbg_insn_opcode[31:12], 12'b0});

	// Track the most recent AUIPC writeback seen at the datapath.
	reg h_wb_pending;
	reg [31:0] h_wb_data;
	reg [31:0] h_wb_pc;
	reg [31:0] h_wb_imm;
	reg [4:0]  h_wb_rd;

	always @(posedge clock) begin
		if (reset) begin
			h_wb_pending <= 0;
			h_wb_data <= 0;
			h_wb_pc <= 0;
			h_wb_imm <= 0;
			h_wb_rd <= 0;
		end else begin
			if (dut.cpuregs_write && h_dbg_is_auipc) begin
				h_wb_pending <= 1;
				h_wb_data <= (dut.latched_rd != 0) ? dut.cpuregs_wrdata : 0;
				h_wb_pc <= dut.dbg_insn_addr;
				h_wb_imm <= h_dbg_auipc_imm;
				h_wb_rd <= dut.dbg_insn_opcode[11:7];
			end

			if (rvfi_valid[0] && h_is_auipc) begin
				h_wb_pending <= 0;
				// AUIPC is always a normal (non-trapping, non-halting) instruction.
				no_trap: assert(!rvfi_trap[0]);
				no_halt: assert(!rvfi_halt[0]);
				// AUIPC does not read rs1/rs2.
				rs1_unused: assert(rvfi_rs1_addr[4:0] == 5'd0);
				rs2_unused: assert(rvfi_rs2_addr[4:0] == 5'd0);
				rs1_rdata_zero: assert(rvfi_rs1_rdata == 0);
				rs2_rdata_zero: assert(rvfi_rs2_rdata == 0);
				// AUIPC does not perform data memory operations.
				no_mem_rmask: assert(rvfi_mem_rmask == 0);
				no_mem_wmask: assert(rvfi_mem_wmask == 0);

				// Retirement must observe the corresponding datapath writeback.
				wb_seen: assert(h_wb_pending);
				wb_pc_match: assert(rvfi_pc_rdata == h_wb_pc);
				wb_imm_match: assert(h_wb_imm == h_rvfi_auipc_imm);
				wb_rd_match: assert(rvfi_insn[11:7] == h_wb_rd);
				wb_data_match: assert(rvfi_rd_wdata == h_wb_data);

				// AUIPC semantics at retirement.
				auipc_semantics: assert(rvfi_rd_wdata == (rvfi_rd_addr[4:0] ? (rvfi_pc_rdata + h_rvfi_auipc_imm) : 0));
				// Structural AUIPC invariants: low 12 bits of PC are preserved.
				auipc_lo12_preserved: assert((rvfi_rd_addr[4:0] == 0) || (rvfi_rd_wdata[11:0] == rvfi_pc_rdata[11:0]));
				// Equivalent high-part relation (no carry from low 12 bits).
				auipc_hi20_add: assert((rvfi_rd_addr[4:0] == 0) || (rvfi_rd_wdata[31:12] == (rvfi_pc_rdata[31:12] + rvfi_insn[31:12])));

				// Strengthen key checker objectives with explicit equalities.
				rd_wdata_match: assert(chk.spec_rd_wdata == rvfi_rd_wdata);
				rd_addr_match:  assert(rvfi_rd_addr[4:0] == rvfi_insn[11:7]);
				pc_step: assert(rvfi_pc_wdata == rvfi_pc_rdata + 32'd4);
			end

			if (dut.cpuregs_write && h_dbg_is_auipc) begin
				// AUIPC does not capture integer register operands.
				rs1_not_captured: assert(!dut.dbg_rs1val_valid);
				rs2_not_captured: assert(!dut.dbg_rs2val_valid);
				// AUIPC uses the ALU path and is not a control-flow change.
				stalu_set: assert(dut.latched_stalu);
				no_branch: assert(!dut.latched_branch);
				// Operand 2 is the U-immediate.
				op2_match: assert(dut.reg_op2 == h_dbg_auipc_imm);
				// Writeback is PC + imm (with x0 suppressed).
				wrdata_match: assert(dut.cpuregs_wrdata == (dut.dbg_insn_addr + h_dbg_auipc_imm));
			end

			// If the retired instruction has no rd, the reported writeback data must be zero.
			addr0_wdata0: assert(!(rvfi_valid[0] && (rvfi_rd_addr[4:0] == 5'd0)) || (rvfi_rd_wdata == 0));
		end
	end
	/// Helper Assertion End
endmodule
