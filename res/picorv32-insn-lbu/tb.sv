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

	// PicoRV32 internal memory-control invariants.
	// These block unreachable "mix-and-match" states that can appear as CTIs under induction,
	// and help align the RVFI memory sideband (`rvfi_mem_*`) with the retiring instruction.
	wire h_mem_do_prefetch = wrapper.uut.mem_do_prefetch;
	wire h_mem_do_rinst    = wrapper.uut.mem_do_rinst;
	wire h_mem_do_rdata    = wrapper.uut.mem_do_rdata;
	wire h_mem_do_wdata    = wrapper.uut.mem_do_wdata;

	wire h_mem_busy    = h_mem_do_prefetch || h_mem_do_rinst || h_mem_do_rdata || h_mem_do_wdata;
	wire h_mem_do_imem = h_mem_do_prefetch || h_mem_do_rinst;

	// PicoRV32 CPU state encodings (from picorv32.sv localparams).
	localparam [7:0] h_cpu_state_trap   = 8'b1000_0000;
	localparam [7:0] h_cpu_state_fetch  = 8'b0100_0000;
	localparam [7:0] h_cpu_state_ld_rs1 = 8'b0010_0000;
	localparam [7:0] h_cpu_state_ld_rs2 = 8'b0001_0000;
	localparam [7:0] h_cpu_state_exec   = 8'b0000_1000;
	localparam [7:0] h_cpu_state_shift  = 8'b0000_0100;
	localparam [7:0] h_cpu_state_stmem  = 8'b0000_0010;
	localparam [7:0] h_cpu_state_ldmem  = 8'b0000_0001;

	wire [7:0] h_cpu_state = wrapper.uut.cpu_state;
	wire h_cpu_state_is_valid =
		(h_cpu_state == h_cpu_state_trap)   ||
		(h_cpu_state == h_cpu_state_fetch)  ||
		(h_cpu_state == h_cpu_state_ld_rs1) ||
		(h_cpu_state == h_cpu_state_ld_rs2) ||
		(h_cpu_state == h_cpu_state_exec)   ||
		(h_cpu_state == h_cpu_state_shift)  ||
		(h_cpu_state == h_cpu_state_stmem)  ||
		(h_cpu_state == h_cpu_state_ldmem);

	// Instruction decode (this proof instance targets LBU specifically).
	wire h_is_lbu = (rvfi_insn[6:0] == 7'b0000011) && (rvfi_insn[14:12] == 3'b100) && (&rvfi_insn[1:0]);

	// Load effective-address reconstruction from the core's debug/retirement view.
	wire [31:0] h_ld_imm = {{20{wrapper.uut.dbg_insn_opcode[31]}}, wrapper.uut.dbg_insn_opcode[31:20]};
	wire [31:0] h_ld_eaddr = wrapper.uut.dbg_rs1val + h_ld_imm;

	always @(posedge clock) begin
		if (!reset) begin
			// The core uses one-hot state encodings; rule out unreachable CTI states
			// that fall outside the enumerated encodings (e.g., due to full_case).
			h_cpu_state_onehot: assert(h_cpu_state_is_valid);

			// With C extension enabled, architecturally visible PCs are 16b aligned.
			h_pc_halfword_aligned:      assert(wrapper.uut.reg_pc[0] == 1'b0);
			h_next_pc_halfword_aligned: assert(wrapper.uut.reg_next_pc[0] == 1'b0);

			// Mutually exclusive memory "intent" signals.
			h_mem_no_read_and_write: assert(!(h_mem_do_rdata && h_mem_do_wdata));
			h_mem_no_imem_and_dmem:  assert(!(h_mem_do_imem && (h_mem_do_rdata || h_mem_do_wdata)));

			// When the external bus is driving a transaction, some memory intent must be active.
			// (In reachable states, mem_valid is only asserted as part of an active mem_do_* op.)
			h_mem_valid_implies_busy: assert(!wrapper.mem_valid || h_mem_busy);

			// For an active bus transaction, mem_instr must accurately reflect whether this is
			// an instruction-side access (fetch/prefetch) vs. a data access.
			h_mem_instr_matches_intent: assert(!wrapper.mem_valid || (wrapper.mem_instr == h_mem_do_imem));

			// PicoRV32 drives a word-aligned address on the external memory bus; subword
			// accesses are encoded via mem_wstrb/mem_wordsize.
			h_mem_addr_word_aligned: assert(!wrapper.mem_valid || (wrapper.mem_addr[1:0] == 2'b00));

			// LBU always performs a data memory read; by the time it retires, the memory
			// interface must not be reporting an instruction-side access.
			h_lbu_retire_not_imem: assert(!(rvfi_valid && h_is_lbu) || !wrapper.mem_instr);

			// In the load-memory state, the core must have latched rs1 and computed the
			// effective address as rs1 + I-imm (the address then drives mem_addr[31:2]).
			if (wrapper.uut.cpu_state == h_cpu_state_ldmem && wrapper.uut.mem_do_rdata && (&wrapper.uut.dbg_insn_opcode[1:0])) begin
				h_ldmem_dbg_rs1_valid: assert(wrapper.uut.dbg_rs1val_valid);
				h_ldmem_reg_op1_is_eaddr: assert(wrapper.uut.reg_op1 == h_ld_eaddr);
			end
		end
	end

/// Helper Assertion End
endmodule
