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

	// Under `RISCV_FORMAL_ALIGNED_MEM`, the memory interface must use word-aligned
	// addresses with byte strobes selecting the accessed lanes.
	always @(posedge clock) begin
		if (!reset) begin
			h_mem_addr_word_aligned: assert (!wrapper.mem_valid || wrapper.mem_addr[1:0] == 2'b00);
		end
	end

	// Track whether we have observed a data-memory transfer for the instruction that
	// is about to retire. The RVFI "retire" event can occur multiple cycles after the
	// data transfer completes (e.g. due to internal bookkeeping), so "previous-cycle"
	// constraints are too strong.
	wire h_data_xfer_now = wrapper.mem_valid && wrapper.mem_ready && !wrapper.mem_instr;
	wire h_retire_pulse = !reset && wrapper.uut.dbg_valid_insn && (wrapper.uut.launch_next_insn || wrapper.trap);
	wire [31:0] h_dbg_rs1 = wrapper.uut.dbg_rs1val_valid ? wrapper.uut.dbg_rs1val : 32'b0;
	wire [31:0] h_dbg_insn_simm = $signed({wrapper.uut.dbg_insn_opcode[31:25], wrapper.uut.dbg_insn_opcode[11:7]});
	wire [31:0] h_dbg_eff_addr = h_dbg_rs1 + h_dbg_insn_simm;

	// Once a store has entered the data-memory phase, the debug-captured operands for
	// the retiring instruction must stay stable (they are the source of RVFI rs1/imm).
	reg h_mem_do_wdata_q;
	reg [31:0] h_dbg_insn_opcode_q;
	reg [31:0] h_dbg_insn_imm_q;
	reg [31:0] h_dbg_rs1val_q;
	always @(posedge clock) begin
		if (reset) begin
			h_mem_do_wdata_q <= 1'b0;
			h_dbg_insn_opcode_q <= 32'b0;
			h_dbg_insn_imm_q <= 32'b0;
			h_dbg_rs1val_q <= 32'b0;
		end else begin
			if (wrapper.uut.mem_do_wdata && h_mem_do_wdata_q) begin
				h_dbg_rs1val_stable_in_store: assert (wrapper.uut.dbg_rs1val == h_dbg_rs1val_q);
				h_dbg_insn_opcode_stable_in_store: assert (wrapper.uut.dbg_insn_opcode == h_dbg_insn_opcode_q);
				h_dbg_insn_imm_stable_in_store: assert (wrapper.uut.dbg_insn_imm == h_dbg_insn_imm_q);
			end

			h_mem_do_wdata_q <= wrapper.uut.mem_do_wdata;
			h_dbg_insn_opcode_q <= wrapper.uut.dbg_insn_opcode;
			h_dbg_insn_imm_q <= wrapper.uut.dbg_insn_imm;
			h_dbg_rs1val_q <= wrapper.uut.dbg_rs1val;
		end
	end

	reg h_data_xfer_seen;
	reg h_data_xfer_seen_at_retire;
	reg [31:0] h_last_data_mem_addr;
	reg [31:0] h_last_data_mem_addr_at_retire;
	always @(posedge clock) begin
		if (reset) begin
			h_data_xfer_seen <= 1'b0;
			h_data_xfer_seen_at_retire <= 1'b0;
			h_last_data_mem_addr <= 32'b0;
			h_last_data_mem_addr_at_retire <= 32'b0;
		end else begin
			// Accumulate data transfers until the next retire boundary.
			h_data_xfer_seen <= h_data_xfer_seen || h_data_xfer_now;
			if (h_data_xfer_now)
				h_last_data_mem_addr <= wrapper.mem_addr;

			// For non-compressed stores (insn[1:0] == 2'b11), the bus address must match
			// rs1 + S-imm. (Compressed stores use a different immediate encoding.)
			h_mem_addr_matches_dbg_eff_addr: assert (!h_data_xfer_now || !wrapper.uut.mem_do_wdata ||
					(wrapper.uut.dbg_insn_opcode[1:0] != 2'b11) ||
					(wrapper.mem_addr == (h_dbg_eff_addr & ~32'h3)));

			// On retirement, snapshot whether we have seen a data transfer for the
			// retiring instruction, then clear the accumulator for the next one.
			if (h_retire_pulse) begin
				h_data_xfer_seen_at_retire <= h_data_xfer_seen || h_data_xfer_now;
				h_last_data_mem_addr_at_retire <= h_data_xfer_now ? wrapper.mem_addr : h_last_data_mem_addr;
				h_data_xfer_seen <= 1'b0;
			end

			// If the retiring instruction (per the spec model) performs a memory access
			// that is supposed to reach the bus, we must have seen a corresponding data
			// memory transfer in its execution window.
			h_mem_xfer_for_spec_mem: assert (!(check && checker_inst.spec_valid && !checker_inst.spec_trap &&
					!checker_inst.mem_access_fault && (|checker_inst.spec_mem_wmask || |checker_inst.spec_mem_rmask)) ||
					h_data_xfer_seen_at_retire);

			// Tie the observed data-transfer address to the spec-model address for the
			// retiring instruction. This excludes paths where a data transfer occurs but
			// belongs to a different instruction than the RVFI retirement event.
			h_last_data_addr_matches_spec: assert (!(check && checker_inst.spec_valid && !checker_inst.spec_trap &&
					!checker_inst.mem_access_fault && (|checker_inst.spec_mem_wmask || |checker_inst.spec_mem_rmask)) ||
					(h_last_data_mem_addr_at_retire == checker_inst.spec_mem_addr));

			h_rvfi_mem_addr_matches_last_data: assert (!(check && checker_inst.spec_valid && !checker_inst.spec_trap &&
					!checker_inst.mem_access_fault && (|checker_inst.spec_mem_wmask || |checker_inst.spec_mem_rmask)) ||
					(rvfi_mem_addr == h_last_data_mem_addr_at_retire));
		end
	end

/// Helper Assertion End
endmodule
