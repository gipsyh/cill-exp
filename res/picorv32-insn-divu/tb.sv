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

	// DIVU (funct7=0000001, funct3=101, opcode=0110011) in RISCV_FORMAL_ALTOPS mode
	wire h_is_divu_dbg =
		wrapper.uut.dbg_insn_opcode[31:25] == 7'b0000001 &&
		wrapper.uut.dbg_insn_opcode[14:12] == 3'b101 &&
		wrapper.uut.dbg_insn_opcode[6:0] == 7'b0110011;

	wire [31:0] h_divu_rs1_or_zero = wrapper.uut.dbg_insn_opcode[19:15] ? wrapper.uut.dbg_rs1val : 32'b0;
	wire [31:0] h_divu_rs2_or_zero = wrapper.uut.dbg_insn_opcode[24:20] ? wrapper.uut.dbg_rs2val : 32'b0;
	wire [31:0] h_divu_altops_result = (h_divu_rs1_or_zero - h_divu_rs2_or_zero) ^ 32'h10e8fd70;

	always @(posedge clock) begin
		if (!reset) begin
			// cpu_state is a one-hot FSM encoding in PicoRV32. Ruling out illegal encodings
			// removes unreachable "X-state" CTIs that can break induction.
			h_cpu_state_valid: assert(
				wrapper.uut.cpu_state == 8'b10000000 || // trap
				wrapper.uut.cpu_state == 8'b01000000 || // fetch
				wrapper.uut.cpu_state == 8'b00100000 || // ld_rs1
				wrapper.uut.cpu_state == 8'b00010000 || // ld_rs2
				wrapper.uut.cpu_state == 8'b00001000 || // exec
				wrapper.uut.cpu_state == 8'b00000100 || // shift
				wrapper.uut.cpu_state == 8'b00000010 || // stmem
				wrapper.uut.cpu_state == 8'b00000001    // ldmem
			);

			// While executing a PCPI instruction, PicoRV32 must present that same instruction to
			// the internal PCPI cores (pcpi_insn) and to the RVFI debug tracking (dbg_insn_opcode).
			if (wrapper.uut.pcpi_valid && wrapper.uut.pcpi_insn[1:0] == 2'b11) begin
				h_pcpi_insn_matches_dbg: assert(wrapper.uut.pcpi_insn == wrapper.uut.dbg_insn_opcode);
			end

			// For MUL/DIV-class PCPI instructions (R-type with funct7=0000001), the decoded register
			// indices must match the instruction fields used by the RVFI model.
			if (wrapper.uut.pcpi_valid &&
					wrapper.uut.pcpi_insn[6:0] == 7'b0110011 &&
					wrapper.uut.pcpi_insn[31:25] == 7'b0000001) begin
				h_muldiv_decoded_rs1_matches: assert(wrapper.uut.decoded_rs1 == wrapper.uut.pcpi_insn[19:15]);
				h_muldiv_decoded_rs2_matches: assert(wrapper.uut.decoded_rs2 == wrapper.uut.pcpi_insn[24:20]);
			end

			// DIVU is implemented via the PCPI interface. A transition from ld_rs1 back to fetch
			// (PCPI completion) requires that pcpi_valid was asserted during the ld_rs1 cycle.
			if ($past(!reset) &&
					wrapper.uut.cpu_state == 8'b01000000 && // fetch
					$past(wrapper.uut.cpu_state) == 8'b00100000 && // ld_rs1
					$past(h_is_divu_dbg)) begin
				h_divu_exit_ld_rs1_had_pcpi_valid: assert($past(wrapper.uut.pcpi_valid));
			end

			// When the DIVU instruction produces a write-back, PicoRV32 must use the same ALTOPS
			// function as the riscv-formal instruction model.
			if (h_is_divu_dbg && wrapper.uut.cpu_state == 8'b01000000 && wrapper.uut.latched_store) begin
				h_divu_rs1val_valid: assert(wrapper.uut.dbg_rs1val_valid);
				h_divu_rs2val_valid: assert(wrapper.uut.dbg_rs2val_valid);
				h_divu_wb_rd_matches_insn: assert(wrapper.uut.latched_rd == wrapper.uut.dbg_insn_opcode[11:7]);
				h_divu_wb_matches_altops: assert(wrapper.uut.reg_out == h_divu_altops_result);
			end

			// After the DIVU write-back cycle (latched_store cleared), the RVFI RD write-back data
			// must already reflect the completed instruction result (or 0 when rd=x0).
			if (h_is_divu_dbg &&
					wrapper.uut.cpu_state == 8'b01000000 && // fetch
					!wrapper.uut.latched_store &&
					wrapper.uut.dbg_insn_opcode[11:7] == 0) begin
				h_divu_rd0_wdata_zero: assert(rvfi_rd_wdata == 0);
			end

		end
	end

/// Helper Assertion End
endmodule
