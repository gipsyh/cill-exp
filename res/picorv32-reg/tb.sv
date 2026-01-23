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
	// Committed architectural register model updated only on RVFI retirement.
	// This avoids tying invariants to the DUT's internal `cpuregs[]` timing,
	// which may change before `rvfi_valid` for multi-cycle instructions.
	wire h_rvfi_valid = rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX];
	wire h_rvfi_trap  = rvfi_trap[`RISCV_FORMAL_CHANNEL_IDX];
	wire [63:0] h_rvfi_order = rvfi_order[64*`RISCV_FORMAL_CHANNEL_IDX +: 64];
	wire [4:0] h_rs1_addr = rvfi_rs1_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5];
	wire [4:0] h_rs2_addr = rvfi_rs2_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5];
	wire [4:0] h_rd_addr  = rvfi_rd_addr [`RISCV_FORMAL_CHANNEL_IDX*5 +: 5];
	wire [`RISCV_FORMAL_XLEN-1:0] h_rs1_rdata = rvfi_rs1_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
	wire [`RISCV_FORMAL_XLEN-1:0] h_rs2_rdata = rvfi_rs2_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
	wire [`RISCV_FORMAL_XLEN-1:0] h_rd_wdata  = rvfi_rd_wdata [`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];

	// PicoRV32 internal debug view of operand reads (used to define RVFI rs*_rdata).
	wire h_dbg_valid_insn = wrapper.uut.dbg_valid_insn;
	wire [4:0] h_dbg_rs1_addr = wrapper.uut.dbg_insn_rs1;
	wire [4:0] h_dbg_rs2_addr = wrapper.uut.dbg_insn_rs2;
	wire h_dbg_rs1val_valid = wrapper.uut.dbg_rs1val_valid;
	wire h_dbg_rs2val_valid = wrapper.uut.dbg_rs2val_valid;
	wire [`RISCV_FORMAL_XLEN-1:0] h_dbg_rs1val = wrapper.uut.dbg_rs1val;
	wire [`RISCV_FORMAL_XLEN-1:0] h_dbg_rs2val = wrapper.uut.dbg_rs2val;

	reg [`RISCV_FORMAL_XLEN-1:0] h_commit_val;
	reg h_commit_written;
	reg [`RISCV_FORMAL_XLEN-1:0] h_gpr [0:31];
	reg [31:0] h_gpr_written;
	reg [31:0] h_gpr_setmask;



	always @(posedge clock) begin
		if (reset) begin
			h_commit_val <= '0;
			h_commit_written <= 1'b0;
			h_gpr_written <= 32'b0;
		end else begin
			h_gpr_setmask = 32'b0;
			if ($past(!reset) && $past(h_rvfi_valid && !h_rvfi_trap && h_rd_addr != 0)) begin
				h_gpr_setmask[$past(h_rd_addr)] = 1'b1;
			end

			h_gpr[0] <= '0;
			h_gpr_written[0] <= 1'b1;
			if (h_rvfi_valid && !h_rvfi_trap && h_rd_addr != 0) begin
				h_gpr[h_rd_addr] <= h_rd_wdata;
				h_gpr_written[h_rd_addr] <= 1'b1;
			end
			if ($past(!reset)) begin
				h_gpr_written_step: assert(h_gpr_written == ($past(h_gpr_written) | 32'b1 | h_gpr_setmask));
			end

			// RVFI protocol/consistency helpers (proven facts about PicoRV32 RVFI).
			if ($past(!reset)) begin
				h_order_progress: assert(h_rvfi_order == $past(h_rvfi_order) + $past(h_rvfi_valid));
			end

			// Trap/halts: once trap is high, the core clears dbg_valid_insn on the
			// next cycle, preventing further rvfi_valid pulses in the trapped state.
			if ($past(!reset)) begin
				h_trap_clears_dbg_valid: assert(!($past(wrapper.uut.trap) && wrapper.uut.dbg_valid_insn));
			end

			// Operand reads must be consistent with the checker’s tracked shadow value
			// for the selected register (when it is known to be written).
			//
			// This is strong enough to eliminate the o_shadow_* CTIs, while avoiding
			// non-inductive obligations about arbitrary registers unrelated to the
			// checker’s chosen index.
			if (h_dbg_valid_insn && h_dbg_rs1val_valid) begin
				if (h_dbg_rs1_addr == 0) begin
					h_dbg_rs1_x0: assert(h_dbg_rs1val == '0);
				end
			end
			if (h_dbg_valid_insn && h_dbg_rs2val_valid) begin
				if (h_dbg_rs2_addr == 0) begin
					h_dbg_rs2_x0: assert(h_dbg_rs2val == '0);
				end
			end

			if ($past(!reset) &&
					h_dbg_valid_insn && h_dbg_rs1val_valid &&
					checker_inst.register_written &&
					checker_inst.register_index != 0 &&
					h_dbg_rs1_addr == checker_inst.register_index &&
					!(h_rvfi_valid && !h_rvfi_trap && h_rd_addr == checker_inst.register_index)) begin
				h_dbg_rs1_tracked_shadow: assert(h_dbg_rs1val == checker_inst.register_shadow);
			end
			if ($past(!reset) &&
					h_dbg_valid_insn && h_dbg_rs2val_valid &&
					checker_inst.register_written &&
					checker_inst.register_index != 0 &&
					h_dbg_rs2_addr == checker_inst.register_index &&
					!(h_rvfi_valid && !h_rvfi_trap && h_rd_addr == checker_inst.register_index)) begin
				h_dbg_rs2_tracked_shadow: assert(h_dbg_rs2val == checker_inst.register_shadow);
			end

			// Trap can only coincide with rvfi_valid on the *first* cycle of trap.
			// After trap is asserted, the core clears dbg_valid_insn, which forces
			// rvfi_valid low on subsequent trap cycles.
			if ($past(!reset)) begin
				h_trap_onecycle_valid: assert(!(h_rvfi_trap && $past(h_rvfi_trap) && h_rvfi_valid));
			end

			// Track the committed value of the *checker-selected* register index.
			// Use $past(..) to avoid cross-module same-cycle update races.
			if ($past(!reset) && $past(h_rvfi_valid && !h_rvfi_trap && h_rd_addr == checker_inst.register_index)) begin
				if ($past(h_rd_addr) == 0) begin
					h_commit_x0_shadow: assert(checker_inst.register_shadow == '0);
				end else begin
					h_commit_capture: assert(checker_inst.register_shadow == $past(h_rd_wdata));
					h_commit_val_capture: begin h_commit_val <= $past(h_rd_wdata); end
					h_commit_written_capture: begin h_commit_written <= 1'b1; end
				end
			end

			// x0 read semantics (only constrain at the checked-instruction boundary).
			if (check && h_rvfi_valid && checker_inst.insn_order == h_rvfi_order) begin
				if (h_rs1_addr == 0) h_rs1_x0: assert(h_rs1_rdata == '0);
				if (h_rs2_addr == 0) h_rs2_x0: assert(h_rs2_rdata == '0);
			end

			// When the checker claims it has observed a write to its selected index,
			// the stored shadow must match the tracked committed value.
			if (checker_inst.register_written) begin
				// `h_commit_*` is updated with NBAs, so on the cycle we *capture* a new
				// writeback, `h_commit_val` still holds the previous value inside this
				// always block. Account for that by comparing against the writeback
				// data directly in capture cycles.
				if ($past(!reset) && $past(checker_inst.register_written)) begin
					h_checker_written: assert(
						checker_inst.register_index == 0 ||
						h_commit_written ||
						$past(h_rvfi_valid && !h_rvfi_trap && h_rd_addr == checker_inst.register_index)
					);
				end
				if (checker_inst.register_index == 0) begin
					h_checker_x0: assert(checker_inst.register_shadow == '0);
				end else if ($past(!reset) && $past(h_rvfi_valid && !h_rvfi_trap && h_rd_addr == checker_inst.register_index)) begin
					h_checker_shadow: assert(checker_inst.register_shadow == $past(h_rd_wdata));
				end else if (h_commit_written) begin
					h_checker_shadow_hold: assert(checker_inst.register_shadow == h_commit_val);
				end
			end

			// RVFI rs* signals are registered in PicoRV32 and effectively reflect
			// the previous cycle's debug operand capture (1-cycle delay).
			// Only constrain this relationship on checked retirement cycles to avoid
			// reset/initialization artifacts where debug/RVFI regs may start as X.
			if ($past(!reset) && check && h_rvfi_valid) begin
				// PicoRV32 may override RVFI rs1/rs2 for certain internal/custom opcodes.
				// Only constrain the RVFI<->dbg pipeline when RVFI indicates a non-x0
				// source register.
				if (h_rs1_addr != 0) begin
					h_rvfi_rs1_addr_pipe: assert($past(h_dbg_rs1val_valid) && $past(h_dbg_rs1_addr) == h_rs1_addr);
					h_rvfi_rs1_pipe: assert(h_rs1_rdata == $past(h_dbg_rs1val));
				end
				if (h_rs2_addr != 0) begin
					h_rvfi_rs2_addr_pipe: assert($past(h_dbg_rs2val_valid) && $past(h_dbg_rs2_addr) == h_rs2_addr);
					h_rvfi_rs2_pipe: assert(h_rs2_rdata == $past(h_dbg_rs2val));
				end
			end


			// Structural step invariants for the checker instance.
			// The checker’s `register_shadow` / `register_written` may only change
			// when the (registered) RVFI interface reports a non-trap writeback to
			// the tracked index. Use $past(..) to match the RVFI timing seen by the
			// checker (RVFI outputs are registered in PicoRV32).
			if ($past(!reset)) begin
				if ($past(checker_inst.register_written) === 1'b0 && checker_inst.register_written === 1'b1) begin
					h_checker_written_rise: assert($past(h_rvfi_valid && !h_rvfi_trap && h_rd_addr == checker_inst.register_index));
				end
				if ($past(checker_inst.register_written) === 1'b1 && checker_inst.register_written === 1'b1 &&
						checker_inst.register_shadow !== $past(checker_inst.register_shadow)) begin
					h_checker_shadow_change_en: assert($past(h_rvfi_valid && !h_rvfi_trap && h_rd_addr == checker_inst.register_index));
					h_checker_shadow_change_data: assert(checker_inst.register_shadow == $past(h_rd_wdata));
				end

				// Full-step characterization (stronger than the change detectors above).
				h_checker_written_step: assert(
					checker_inst.register_written === (
						$past(checker_inst.register_written) |
						$past(h_rvfi_valid && !h_rvfi_trap && h_rd_addr == checker_inst.register_index)
					)
				);
				if ($past(h_rvfi_valid && !h_rvfi_trap && h_rd_addr == checker_inst.register_index)) begin
					h_checker_shadow_updates_on_write: assert(checker_inst.register_shadow == $past(h_rd_wdata));
				end else if ($past(checker_inst.register_written) === 1'b1 && checker_inst.register_written === 1'b1) begin
					h_checker_shadow_stable_no_write: assert(checker_inst.register_shadow === $past(checker_inst.register_shadow));
				end
			end

			// (Intentionally no direct bridge lemma between checker shadow and RVFI
			// rs*_rdata here; this relationship is the goal of o_shadow_* itself.)

			// Tie the checker’s tracked shadow to the same architectural model.
			if (checker_inst.register_index == 0) begin
				if (checker_inst.register_written) h_checker_x0_gpr: assert(checker_inst.register_shadow == '0);
			end else if (checker_inst.register_written) begin
				h_checker_gpr_written: assert(h_gpr_written[checker_inst.register_index]);
				h_checker_gpr_shadow: assert(checker_inst.register_shadow == h_gpr[checker_inst.register_index]);
			end

			// Operand reads of the tracked register must match the tracked value.
			// Allow a one-cycle exception when the retiring instruction writes back
			// to the same register, since the debug operand read can reflect either
			// side of that writeback depending on internal timing.
			// Debug operand values are not necessarily phase-aligned with RVFI
			// rs*_rdata (which is registered), so only use dbg for x0 semantics above.
		end
	end

/// Helper Assertion End
endmodule
