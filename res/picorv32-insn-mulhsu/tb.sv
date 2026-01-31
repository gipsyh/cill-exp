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

	// picoRV32 uses a one-hot encoded main FSM; unreachable encodings often appear
	// in induction CTIs and must be ruled out with an invariant.
		always @(posedge clock) begin
			if (!reset) begin
				h_cpu_state_onehot: assert (wrapper.uut.cpu_state != 0 &&
					(wrapper.uut.cpu_state & (wrapper.uut.cpu_state - 1)) == 0);
			end
		end

		// Once the core is trapped, the "valid instruction" flag is cleared (with a
		// one-cycle delay due to nonblocking assignment ordering).
		always @(posedge clock) begin
			if (!reset && !$past(reset)) begin
				h_trap_clears_dbg_valid_insn: assert (!$past(wrapper.uut.trap) || !wrapper.uut.dbg_valid_insn);
		end
	end

		// latched_stalu is only meaningful when there is a pending register writeback.
		always @(posedge clock) begin
			if (!reset) begin
				h_latched_stalu_implies_store: assert (!wrapper.uut.latched_stalu || wrapper.uut.latched_store);
			end
		end

		// Once operand values are marked valid, they should not change until the
		// next instruction clears the valid flag.
		always @(posedge clock) begin
			if (!reset && !$past(reset)) begin
				if ($past(wrapper.uut.dbg_rs1val_valid) && wrapper.uut.dbg_rs1val_valid)
					h_dbg_rs1val_stable: assert (wrapper.uut.dbg_rs1val == $past(wrapper.uut.dbg_rs1val));
				if ($past(wrapper.uut.dbg_rs2val_valid) && wrapper.uut.dbg_rs2val_valid)
					h_dbg_rs2val_stable: assert (wrapper.uut.dbg_rs2val == $past(wrapper.uut.dbg_rs2val));
			end
		end

		// Expected MULHSU (ALTOPS) result used by the riscv-formal instruction model.
		wire h_is_mulhsu =
			wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011 &&
			wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001 &&
			wrapper.uut.dbg_insn_opcode[14:12] == 3'b010;
		wire [31:0] h_mulhsu_expected =
			(wrapper.uut.dbg_rs1val - wrapper.uut.dbg_rs2val) ^ 32'hecfbe137;

		// When a MULHSU writeback is pending in FETCH, reg_out must already contain
		// the architectural result to be committed to the register file.
		always @(posedge clock) begin
			if (!reset) begin
				h_mulhsu_reg_out_matches_spec: assert (!(
					wrapper.uut.cpu_state == 8'h40 &&
					wrapper.uut.latched_store && !wrapper.uut.latched_branch &&
					wrapper.uut.latched_rd != 0 && h_is_mulhsu
				) || wrapper.uut.reg_out == h_mulhsu_expected);
			end
		end

			// When a MULHSU is launched, the core must enter LD_RS1 (PCPI path),
			// never the normal ALU EXEC state.
				always @(posedge clock) begin
					if (!reset && !$past(reset)) begin
						h_mulhsu_enters_ld_rs1: assert (!(wrapper.uut.dbg_next &&
							wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011 &&
							wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001 &&
							wrapper.uut.dbg_insn_opcode[14:12] == 3'b010) || wrapper.uut.cpu_state == 8'h20);
					end
				end

				// MULHSU is a PCPI (trap) instruction and must not reach the normal EXEC state.
				always @(posedge clock) begin
					if (!reset && !$past(reset)) begin
						h_mulhsu_not_in_exec: assert (!(
							wrapper.uut.cpu_state == 8'h08 &&
							wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011 &&
							wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001 &&
							wrapper.uut.dbg_insn_opcode[14:12] == 3'b010
						));
					end
				end

				// The DIV PCPI unit must only signal "ready" for DIV/REM-class instructions,
				// otherwise the PCPI mux could return the wrong result.
				always @(posedge clock) begin
					if (!reset && !$past(reset)) begin
						h_div_ready_requires_div_insn: assert (!wrapper.uut.pcpi_div_ready || (
							wrapper.uut.pcpi_insn[6:0] == 7'b0110011 &&
							wrapper.uut.pcpi_insn[31:25] == 7'b0000001 &&
						(wrapper.uut.pcpi_insn[14:12] == 3'b100 ||
						 wrapper.uut.pcpi_insn[14:12] == 3'b101 ||
						 wrapper.uut.pcpi_insn[14:12] == 3'b110 ||
						 wrapper.uut.pcpi_insn[14:12] == 3'b111)
					));
					end
				end

				// x0 is hard-wired to zero: if a PCPI instruction uses rs1/rs2=x0 then the
				// corresponding operand presented to PCPI must be zero.
				always @(posedge clock) begin
					if (!reset && !$past(reset)) begin
						if (wrapper.uut.pcpi_valid &&
						    wrapper.uut.pcpi_insn[6:0] == 7'b0110011 &&
						    wrapper.uut.pcpi_insn[31:25] == 7'b0000001 &&
						    wrapper.uut.pcpi_insn[19:15] == 0) begin
							h_pcpi_rs1_x0_is_zero: assert (wrapper.uut.pcpi_rs1 == 0);
						end
						if (wrapper.uut.pcpi_valid &&
						    wrapper.uut.pcpi_insn[6:0] == 7'b0110011 &&
						    wrapper.uut.pcpi_insn[31:25] == 7'b0000001 &&
						    wrapper.uut.pcpi_insn[24:20] == 0) begin
							h_pcpi_rs2_x0_is_zero: assert (wrapper.uut.pcpi_rs2 == 0);
						end
					end
				end

				// For PCPI M-extension ops, the operands presented to PCPI must match the
				// values reported via RVFI (dbg_rs*val).
				always @(posedge clock) begin
					if (!reset && !$past(reset)) begin
						if (wrapper.uut.pcpi_valid &&
						    wrapper.uut.pcpi_insn[6:0] == 7'b0110011 &&
						    wrapper.uut.pcpi_insn[31:25] == 7'b0000001) begin
							if (wrapper.uut.dbg_rs1val_valid)
								h_pcpi_rs1_matches_dbg: assert (wrapper.uut.pcpi_rs1 == wrapper.uut.dbg_rs1val);
							if (wrapper.uut.dbg_rs2val_valid)
								h_pcpi_rs2_matches_dbg: assert (wrapper.uut.pcpi_rs2 == wrapper.uut.dbg_rs2val);
						end
					end
				end

				// For PCPI M-extension ops, the latched destination register must match the
				// decoded rd field from the instruction.
				always @(posedge clock) begin
					if (!reset && !$past(reset)) begin
						if (wrapper.uut.pcpi_valid &&
						    wrapper.uut.pcpi_insn[6:0] == 7'b0110011 &&
						    wrapper.uut.pcpi_insn[31:25] == 7'b0000001) begin
							h_pcpi_rd_matches_insn_rd: assert (wrapper.uut.latched_rd[4:0] == wrapper.uut.pcpi_insn[11:7]);
						end
					end
				end

				// Fast-mul asserts ready for a single cycle; it should not stay high
				// in consecutive cycles (shift register active[1]).
				always @(posedge clock) begin
					if (!reset && !$past(reset)) begin
						h_pcpi_mul_ready_not_consecutive: assert (!($past(wrapper.uut.pcpi_mul_ready) && wrapper.uut.pcpi_mul_ready));
					end
				end

				// PCPI "ready" must only be observed when the core is actively issuing a
				// PCPI request. Otherwise a stale ready/data pulse could be consumed on
				// the first LD_RS1 cycle of a new PCPI instruction.
				always @(posedge clock) begin
					if (!reset) begin
						h_pcpi_ready_implies_valid: assert (!wrapper.uut.pcpi_int_ready || wrapper.uut.pcpi_valid);
					end
				end

				// In the PCPI (trap) path, the 32b instruction presented on the PCPI bus
				// must match the instruction tracked for RVFI reporting.
				always @(posedge clock) begin
					if (!reset && !$past(reset)) begin
							if (wrapper.uut.cpu_state == 8'h20 && wrapper.uut.instr_trap) begin
								if (wrapper.uut.pcpi_insn[1:0] == 2'b11) begin
									h_pcpi_insn_matches_dbg_insn_32: assert (wrapper.uut.pcpi_insn == wrapper.uut.dbg_insn_opcode);
								end
							end
						end
					end

	/// Helper Assertion End
	endmodule
