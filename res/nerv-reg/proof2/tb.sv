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
	// Helper invariants to make the shadow-register checker inductive.
	// These only constrain post-reset states.
	always @(posedge clock) begin
		if (!reset) begin
			// Pipeline flop consistency (matches the DUT's sequential logic).
			if (!$past(reset) && !$past(wrapper.uut.stall)) begin
				h_mem_rd_enable_q_updates: assert(wrapper.uut.mem_rd_enable_q == $past(wrapper.uut.mem_rd_enable));
				h_mem_rd_reg_q_updates: assert(wrapper.uut.mem_rd_reg_q == $past(wrapper.uut.mem_rd_reg));
				h_mem_rd_func_q_updates: assert(wrapper.uut.mem_rd_func_q == $past(wrapper.uut.mem_rd_func));
				h_mem_wr_enable_q_updates: assert(wrapper.uut.mem_wr_enable_q == $past(wrapper.uut.mem_wr_enable));
			end

			if (!$past(reset) && !$past(wrapper.uut.reset_q)) begin
				h_rvfi_valid_updates: assert(rvfi_valid == $past(wrapper.uut.next_rvfi_valid));
			end
			if (wrapper.uut.reset_q) begin
				h_rvfi_valid_low_in_resetq: assert(rvfi_valid == 0);
			end

			// During the second cycle of a load (pending memory read), the core is not
			// executing a new instruction, and the architectural register file is stable
			// up to the eventual load writeback. RVFI source operand snapshots must match
			// the architectural regfile contents at the recorded source addresses.
			if (wrapper.uut.mem_rd_enable_q) begin
				if (rvfi_rs1_addr == 0)
					h_load_pending_rs1_x0_is_zero: assert(rvfi_rs1_rdata == 0);
				else
					h_load_pending_rs1_matches_regfile: assert(rvfi_rs1_rdata == wrapper.uut.regfile[rvfi_rs1_addr]);

				if (rvfi_rs2_addr == 0)
					h_load_pending_rs2_x0_is_zero: assert(rvfi_rs2_rdata == 0);
				else
					h_load_pending_rs2_matches_regfile: assert(rvfi_rs2_rdata == wrapper.uut.regfile[rvfi_rs2_addr]);
			end

			// During the second cycle of a store (late cycle for a pending memory write),
			// the RVFI rs* snapshots must match the architectural regfile at the recorded
			// addresses. Guard with cycle_late_wr to avoid constraining unrelated stall
			// cycles.
			if (wrapper.uut.cycle_late_wr && wrapper.uut.mem_wr_enable_q) begin
				if (rvfi_rs1_addr == 0)
					h_store_pending_rs1_x0_is_zero: assert(rvfi_rs1_rdata == 0);
				else
					h_store_pending_rs1_matches_regfile: assert(rvfi_rs1_rdata == wrapper.uut.regfile[rvfi_rs1_addr]);

				if (rvfi_rs2_addr == 0)
					h_store_pending_rs2_x0_is_zero: assert(rvfi_rs2_rdata == 0);
				else
					h_store_pending_rs2_matches_regfile: assert(rvfi_rs2_rdata == wrapper.uut.regfile[rvfi_rs2_addr]);
			end

			if (!$past(reset) && rvfi_order == $past(rvfi_order)) begin
				h_rvfi_rs1_addr_stable_without_order: assert(rvfi_rs1_addr == $past(rvfi_rs1_addr));
				h_rvfi_rs1_rdata_stable_without_order: assert(rvfi_rs1_rdata == $past(rvfi_rs1_rdata));
				h_rvfi_rs2_addr_stable_without_order: assert(rvfi_rs2_addr == $past(rvfi_rs2_addr));
				h_rvfi_rs2_rdata_stable_without_order: assert(rvfi_rs2_rdata == $past(rvfi_rs2_rdata));
			end

			if (!$past(reset) && rvfi_order != $past(rvfi_order)) begin
				h_rvfi_rs1_matches_past_rs1_value: assert(rvfi_rs1_rdata == $past(wrapper.uut.rs1_value));
				h_rvfi_rs2_matches_past_rs2_value: assert(rvfi_rs2_rdata == $past(wrapper.uut.rs2_value));
			end

			if (checker_inst.register_written) begin
				if (checker_inst.register_index == 0) begin
					h_shadow_x0_is_zero: assert(checker_inst.register_shadow == 0);
				end else if (!$past(reset)) begin
					h_shadow_is_prev_regfile: assert(checker_inst.register_shadow == $past(wrapper.uut.regfile[checker_inst.register_index]));
				end
			end else begin
				h_shadow_zero_when_unwritten: assert(checker_inst.register_shadow == 0);
			end

			// Late-writeback and dmem-fault cycles do not recompute RVFI rs* fields.
			// If we are at the tracked order, then any shadowed register that is used
			// as a source operand must already agree with the RVFI snapshot.
			if ((wrapper.uut.cycle_late_wr || wrapper.uut.cycle_dmem_fault) && checker_inst.insn_order == rvfi_order) begin
				if (checker_inst.register_written && checker_inst.register_index == rvfi_rs1_addr)
					h_shadow_rs1_on_late_or_fault: assert(checker_inst.register_shadow == rvfi_rs1_rdata);
				if (checker_inst.register_written && checker_inst.register_index == rvfi_rs2_addr)
					h_shadow_rs2_on_late_or_fault: assert(checker_inst.register_shadow == rvfi_rs2_rdata);
			end

			// Stronger (check-independent) versions of the original assertions.
			// If these are invariant, then the original o_* (which are additionally gated by `check`) are invariant too.
			if (rvfi_valid && checker_inst.insn_order == rvfi_order) begin
				if (checker_inst.register_written && checker_inst.register_index == rvfi_rs1_addr)
					h_shadow_rs1_nocheck: assert(checker_inst.register_shadow == rvfi_rs1_rdata);
				if (checker_inst.register_written && checker_inst.register_index == rvfi_rs2_addr)
					h_shadow_rs2_nocheck: assert(checker_inst.register_shadow == rvfi_rs2_rdata);
			end
		end
	end

/// Helper Assertion End
endmodule
