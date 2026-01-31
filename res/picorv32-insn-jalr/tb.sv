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

	// Local history for simple 1-cycle relations (avoid relying on $past initial semantics).
	reg h_launch_next_insn_d;
	reg h_post_reset;
	reg [31:0] h_next_pc_d;

	// Decode for the committed instruction as seen via the debug/RVFI path.
	wire h_is_jalr = (wrapper.uut.dbg_insn_opcode[6:0] == 7'b1100111) &&
	                 (wrapper.uut.dbg_insn_opcode[14:12] == 3'b000);
	wire signed [31:0] h_jalr_imm = $signed(wrapper.uut.dbg_insn_opcode[31:20]);
	wire [31:0] h_jalr_target = (wrapper.uut.dbg_rs1val + h_jalr_imm) & ~32'd1;

	always @(posedge clock) begin
		if (reset)
			h_launch_next_insn_d <= 1'b0;
		else
			h_launch_next_insn_d <= wrapper.uut.launch_next_insn;

		if (reset)
			h_post_reset <= 1'b0;
		else
			h_post_reset <= 1'b1;

		if (reset)
			h_next_pc_d <= 32'b0;
		else
			h_next_pc_d <= wrapper.uut.next_pc;
	end

	// RVFI bookkeeping: if a committed instruction is reported (rvfi_valid) and
	// it is not a trap, the core must have launched the next instruction in the
	// prior cycle. In PicoRV32 this is tracked by dbg_next <= launch_next_insn.
	always @(posedge clock) begin
		if (!reset) begin
			h_rvfi_valid_implies_dbg_next: assert(!rvfi_valid[0] || rvfi_trap[0] || wrapper.uut.dbg_next);
			h_pc_wdata_aligned: assert(!rvfi_valid[0] || rvfi_trap[0] || rvfi_pc_wdata[0] == 1'b0);
			if (wrapper.uut.launch_next_insn && !wrapper.uut.trap) begin
				h_next_pc_aligned_on_launch: assert(wrapper.uut.next_pc[0] == 1'b0);
			end
			if (h_post_reset) begin
				h_dbg_next_matches_launch: assert(wrapper.uut.dbg_next == h_launch_next_insn_d);
			end
			if (h_post_reset && h_launch_next_insn_d) begin
				h_dbg_insn_addr_matches_next_pc: assert(wrapper.uut.dbg_insn_addr == h_next_pc_d);
			end

			// When the spec says the instruction does not trap, the implementation
			// must not report a trap on RVFI either.
			if (check && checker_inst.spec_valid && !checker_inst.spec_trap && !checker_inst.mem_access_fault) begin
				h_spec_notrap_impl_notrap: assert(rvfi_trap[0] == 1'b0);
			end

			// For a committed JALR, the post-state PC (next_pc used when launching
			// the next instruction) must match rs1 + imm with bit 0 cleared.
			if (wrapper.uut.launch_next_insn && wrapper.uut.dbg_valid_insn && !wrapper.uut.trap &&
			    wrapper.uut.dbg_rs1val_valid && h_is_jalr) begin
				h_jalr_next_pc_matches_rs1_plus_imm: assert(wrapper.uut.next_pc == h_jalr_target);
			end

		end
	end

/// Helper Assertion End
endmodule
