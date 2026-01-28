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
	) uut (
		.clk(clock), .resetn(!reset), .trap(trap),
		.mem_valid(mem_valid), .mem_instr(mem_instr),
		.mem_ready(mem_ready), .mem_addr(mem_addr),
		.mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
		.mem_rdata(mem_rdata),
		`RVFI_CONN
	);

	// Instantiate the formal property checker
	rvfi_insn_check checker_inst (
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
	// PicoRV32 drives word-aligned addresses on the memory interface.
	// Data byte/halfword selection is done via strobes/shifts, not via mem_addr[1:0].
	always @(posedge clock) begin
		if (!reset && mem_valid) begin
			h_mem_addr_word_aligned: assert(mem_addr[1:0] == 2'b00);
		end
		if (!reset && rvfi_valid[0]) begin
			h_rvfi_mem_addr_word_aligned: assert(rvfi_mem_addr[1:0] == 2'b00);
		end
	end

	// For LW, PicoRV32 uses a word-aligned memory interface address.
	wire h_is_lw = (rvfi_insn[6:0] == 7'b0000011) && (rvfi_insn[14:12] == 3'b010);
	wire signed [31:0] h_lw_imm = $signed(rvfi_insn[31:20]);
	wire [31:0] h_lw_eff_addr = rvfi_rs1_rdata + h_lw_imm;
	wire [31:0] h_lw_eff_addr_aligned = {h_lw_eff_addr[31:2], 2'b00};
	// When PicoRV32 performs the LW data access, its word-aligned `mem_addr` must match
	// the aligned effective address computed from the same decoded instruction and rs1 value.
	wire h_dbg_is_lw = (uut.dbg_insn_opcode[6:0] == 7'b0000011) && (uut.dbg_insn_opcode[14:12] == 3'b010);
	wire signed [31:0] h_dbg_lw_imm = $signed(uut.dbg_insn_opcode[31:20]);
	wire [31:0] h_dbg_lw_eff_addr = uut.dbg_rs1val + h_dbg_lw_imm;
	wire [31:0] h_dbg_lw_eff_addr_aligned = {h_dbg_lw_eff_addr[31:2], 2'b00};

	always @(posedge clock) begin
		if (!reset && uut.mem_valid && uut.mem_ready && !uut.mem_instr && h_dbg_is_lw && uut.dbg_rs1val_valid) begin
			h_lw_mem_addr_matches_dbg_eff_addr: assert(uut.mem_addr == h_dbg_lw_eff_addr_aligned);
		end
		if (!reset && rvfi_valid[0] && h_is_lw && !rvfi_trap[0]) begin
			h_rvfi_lw_mem_addr_is_eff_addr_aligned: assert(rvfi_mem_addr == h_lw_eff_addr_aligned);
		end
	end

	// Bridge: RVFI-reported mem address for LW comes from the last completed data memory access.
	reg [31:0] h_last_dmem_addr;
	reg h_last_dmem_addr_valid;
	always @(posedge clock) begin
		if (reset) begin
			h_last_dmem_addr <= 32'b0;
			h_last_dmem_addr_valid <= 1'b0;
		end else begin
			if (mem_valid && mem_ready && !mem_instr) begin
				h_last_dmem_addr <= mem_addr;
				h_last_dmem_addr_valid <= 1'b1;
			end
			if (rvfi_valid[0] && h_is_lw && !rvfi_trap[0]) begin
				h_lw_rvfi_mem_addr_matches_last_dmem: assert(h_last_dmem_addr_valid);
				h_lw_rvfi_mem_addr_matches_last_dmem2: assert(rvfi_mem_addr == h_last_dmem_addr);
			end
		end
	end
/// Helper Assertion End
endmodule
