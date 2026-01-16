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
	// Mirror the internal shadow tracking logic with reset initialization.
	// This blocks unreachable induction states where the checker internal regs
	// take arbitrary values despite no matching prior write being observed.
	reg h_register_written;
	reg [`RISCV_FORMAL_XLEN-1:0] h_register_shadow;

	always @(posedge clock) begin
		if (reset) begin
			h_register_written <= 0;
			h_register_shadow <= 0;
		end else if (!check) begin
			if (rvfi_valid && !rvfi_trap && rvfi_order < checker_inst.insn_order &&
					(rvfi_rd_addr == checker_inst.register_index)) begin
				h_register_shadow <= rvfi_rd_wdata;
				h_register_written <= 1;
			end
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_shadow_written_match: assert(checker_inst.register_written == h_register_written);
			h_shadow_value_match: assert(checker_inst.register_shadow == h_register_shadow);
		end
	end

	// Tie the checker shadow to the DUT architectural register value for the selected register index.
	// Note: RVFI rs*_rdata is a *pre-state* value; the DUT regfile is *post-state* for the current
	// retired instruction. Therefore we use $past(reg) at the target order.
	reg h_past_valid;
	reg h_seen_reset;
	always @(posedge clock) begin
		if (reset)
			h_past_valid <= 0;
		else
			h_past_valid <= 1;
	end

	always @(posedge clock) begin
		if (reset)
			h_seen_reset <= 1;
		else
			h_seen_reset <= h_seen_reset;
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_seen_reset_post: assert(h_seen_reset);
		end
	end

	wire [`RISCV_FORMAL_XLEN-1:0] h_arch_reg_now =
		(checker_inst.register_index == 0) ? {`RISCV_FORMAL_XLEN{1'b0}} : wrapper.uut.regfile[checker_inst.register_index];

	always @(posedge clock) begin
		if (!reset && h_past_valid) begin
			// Trapped instructions must not commit integer register writes.
			if (rvfi_valid && rvfi_trap) begin
				h_no_write_on_trap: assert(rvfi_rd_addr == 0);
			end

			// If the target order is zero, there cannot have been any prior instruction with order < insn_order.
			// Therefore the checker shadow must still be at its reset value.
			if (h_seen_reset && (checker_inst.insn_order == 0)) begin
				h_no_shadow_when_order0: assert(!checker_inst.register_written);
				h_no_shadow_value_when_order0: assert(checker_inst.register_shadow == 0);
			end

			// Shadow must agree with RVFI register read data at the targeted order.
			// Include trap retirements, but only when the RVFI rs*_rdata fields are updated in the DUT.
			if (!rvfi_order_loopback && rvfi_valid && (wrapper.uut.cycle_insn || wrapper.uut.cycle_trap) && checker_inst.register_written &&
					(rvfi_order == checker_inst.insn_order)) begin
				if (rvfi_rs1_addr == checker_inst.register_index)
					h_shadow_agrees_with_rvfi_rs1_at_target_order: assert(checker_inst.register_shadow == rvfi_rs1_rdata);
				if (rvfi_rs2_addr == checker_inst.register_index)
					h_shadow_agrees_with_rvfi_rs2_at_target_order: assert(checker_inst.register_shadow == rvfi_rs2_rdata);
			end

			// RVFI rs*_rdata should reflect the architectural pre-state of that source register.
			// Guard with the internal retirement kind so we don't constrain cycles where rvfi_valid is set
			// for late writes or fault bookkeeping (which do not update rs*_rdata).
			if (rvfi_valid && h_past_valid && (wrapper.uut.cycle_insn || wrapper.uut.cycle_trap)) begin
				if (rvfi_rs1_addr == checker_inst.register_index)
					h_rs1_rdata_matches_arch: assert(rvfi_rs1_rdata == $past(h_arch_reg_now));
				if (rvfi_rs2_addr == checker_inst.register_index)
					h_rs2_rdata_matches_arch: assert(rvfi_rs2_rdata == $past(h_arch_reg_now));
			end

			// Architectural state should not change in cycles with no retired instruction.
			if (!rvfi_valid) begin
				h_reg_stable_when_not_valid: assert(h_arch_reg_now == $past(h_arch_reg_now));
			end

			// While we're still before the target insn_order, the checker shadow lags the DUT architectural
			// register by one cycle. This relation should hold in *all* cycles (including bubbles), as long
			// as the architectural register is stable when rvfi_valid==0.
			if (!rvfi_order_loopback && checker_inst.register_written && (rvfi_order < checker_inst.insn_order)) begin
				h_shadow_tracks_arch_before_target: assert(checker_inst.register_shadow == $past(h_arch_reg_now));
			end

			// At the targeted order, the checker shadow corresponds to the architectural *pre-state* value.
			if (!rvfi_order_loopback && rvfi_valid && (rvfi_order == checker_inst.insn_order) && checker_inst.register_written) begin
				h_shadow_matches_arch_prestate_at_target: assert(checker_inst.register_shadow == $past(h_arch_reg_now));
			end
		end
	end

/// Helper Assertion End
endmodule
