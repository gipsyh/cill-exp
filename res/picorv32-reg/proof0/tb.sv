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

	wire [4:0] h_reg_idx = checker_inst.register_index;
	wire [`RISCV_FORMAL_XLEN-1:0] h_regfile_val =
		(h_reg_idx == 0) ? '0 : wrapper.uut.cpuregs[h_reg_idx];

	wire [4:0] h_rs1_idx = rvfi_rs1_addr;
	wire [4:0] h_rs2_idx = rvfi_rs2_addr;
	wire [`RISCV_FORMAL_XLEN-1:0] h_rs1_regfile_val =
		(h_rs1_idx == 0) ? '0 : wrapper.uut.cpuregs[h_rs1_idx];
	wire [`RISCV_FORMAL_XLEN-1:0] h_rs2_regfile_val =
		(h_rs2_idx == 0) ? '0 : wrapper.uut.cpuregs[h_rs2_idx];
	wire [7:0] h_cpu_state = wrapper.uut.cpu_state;
	wire [`RISCV_FORMAL_XLEN-1:0] h_idx_regfile_val =
		(h_reg_idx == 0) ? '0 : wrapper.uut.cpuregs[h_reg_idx];

		always @(posedge clock) begin
			if (!reset) begin
				h_cpu_state_onehot: assert((h_cpu_state != 0) && ((h_cpu_state & (h_cpu_state - 1)) == 0));
				if ($past(!reset)) begin
					h_pseudo_trigger_has_decoder_trigger_q: assert(!wrapper.uut.decoder_pseudo_trigger_q || wrapper.uut.decoder_trigger_q);
					h_dbg_next_clears_rs1val_valid: assert(!wrapper.uut.dbg_next || !wrapper.uut.dbg_rs1val_valid);
					h_dbg_next_clears_rs2val_valid: assert(!wrapper.uut.dbg_next || !wrapper.uut.dbg_rs2val_valid);
				end
				h_dbg_next_only_after_fetch: assert(!wrapper.uut.dbg_next || (h_cpu_state == 8'b01000000) || (h_cpu_state == 8'b00100000));
				h_pseudo_trigger_only_in_fetch: assert(!wrapper.uut.decoder_pseudo_trigger || (h_cpu_state == 8'b01000000));
				h_ld_rs1_no_mem_data: assert((h_cpu_state != 8'b00100000) || (!wrapper.uut.mem_do_rdata && !wrapper.uut.mem_do_wdata));
				h_shadow_zero_until_written: assert(checker_inst.register_written || checker_inst.register_shadow == '0);
				h_x0_shadow_zero: assert((h_reg_idx != 0) || (checker_inst.register_shadow == '0));
				if (checker_inst.register_written && (h_reg_idx != 0) && (rvfi_rd_addr != h_reg_idx)) begin
					h_shadow_matches_regfile_when_not_pending: assert(checker_inst.register_shadow == h_idx_regfile_val);
				end
			if (checker_inst.register_written && wrapper.uut.dbg_rs1val_valid && (wrapper.uut.dbg_insn_rs1 == checker_inst.register_index)) begin
				h_dbg_rs1val_matches_shadow: assert(wrapper.uut.dbg_rs1val == checker_inst.register_shadow);
			end
			if (checker_inst.register_written && wrapper.uut.dbg_rs2val_valid && (wrapper.uut.dbg_insn_rs2 == checker_inst.register_index)) begin
				h_dbg_rs2val_matches_shadow: assert(wrapper.uut.dbg_rs2val == checker_inst.register_shadow);
			end

			if ($past(!reset) && $past(wrapper.uut.cpuregs_write) && ($past(wrapper.uut.irq_state) == 0)) begin
				h_rvfi_rdaddr_tracks_cpuregs_write: assert(rvfi_rd_addr == $past(wrapper.uut.latched_rd));
				h_rvfi_rdwdata_tracks_cpuregs_write: assert(rvfi_rd_wdata ==
					($past(wrapper.uut.latched_rd) ? $past(wrapper.uut.cpuregs_wrdata) : '0));
			end
			if ($past(!reset)) begin
				h_trap_follows_cpu_state: assert(wrapper.uut.trap == (($past(wrapper.uut.cpu_state) == 8'b10000000) ? 1'b1 : 1'b0));
				h_rvfi_trap_follows_trap: assert(rvfi_trap == $past(wrapper.uut.trap));
			end
			if ($past(!reset) && $past(!reset, 2) && ($past(wrapper.uut.cpu_state, 2) == 8'b10000000)) begin
				h_rvfi_trap_after_trap_state: assert(rvfi_trap);
			end
			if ($past(!reset) && ($past(wrapper.uut.dbg_insn_opcode[6:0]) != 7'b0001011)) begin
				h_rvfi_rs1addr_tracks_dbg: assert(rvfi_rs1_addr ==
					($past(wrapper.uut.dbg_rs1val_valid) ? $past(wrapper.uut.dbg_insn_rs1) : 5'd0));
				h_rvfi_rs1rdata_tracks_dbg: assert(rvfi_rs1_rdata ==
					($past(wrapper.uut.dbg_rs1val_valid) ? $past(wrapper.uut.dbg_rs1val) : '0));
				h_rvfi_rs2addr_tracks_dbg: assert(rvfi_rs2_addr ==
					($past(wrapper.uut.dbg_rs2val_valid) ? $past(wrapper.uut.dbg_insn_rs2) : 5'd0));
				h_rvfi_rs2rdata_tracks_dbg: assert(rvfi_rs2_rdata ==
					($past(wrapper.uut.dbg_rs2val_valid) ? $past(wrapper.uut.dbg_rs2val) : '0));
			end
			if (rvfi_valid && wrapper.uut.trap) begin
				h_rvfi_trap_when_trap_and_valid: assert(rvfi_trap);
			end

			if ($past(!reset) && $past(rvfi_valid) && !$past(rvfi_trap) && $past(rvfi_rd_addr) == $past(h_reg_idx)) begin
				h_shadow_matches_regfile_on_write: assert(checker_inst.register_shadow == $past(h_regfile_val));
			end
		end
	end

/// Helper Assertion End
endmodule
