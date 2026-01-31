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

	// RVFI structural consistency checks for this instruction model (C.SUB).
	// These are helpers for inductiveness: they rule out unreachable states where
	// the checker is asked to validate C.SUB but the RVFI address fields don't
	// match the spec's decoded register numbers.
	wire h_fire = !reset && check && checker_inst.spec_valid &&
		!checker_inst.spec_trap && !checker_inst.mem_access_fault;
	wire h_dbg_is_csub = (wrapper.uut.dbg_insn_opcode[31:16] == 0) &&
		(wrapper.uut.dbg_insn_opcode[15:10] == 6'b100011) &&
		(wrapper.uut.dbg_insn_opcode[6:5] == 2'b00) &&
		(wrapper.uut.dbg_insn_opcode[1:0] == 2'b01);
	reg h_last_csub_valid;
	reg [`RISCV_FORMAL_XLEN-1:0] h_last_csub_rs1;
	reg [`RISCV_FORMAL_XLEN-1:0] h_last_csub_rs2;
	reg [`RISCV_FORMAL_XLEN-1:0] h_last_csub_wdata;

	always @(posedge clock) begin
		if (h_fire) begin
			h_rs1_addr_match: assert (rvfi_rs1_addr == checker_inst.spec_rs1_addr);
			h_rs2_addr_match: assert (rvfi_rs2_addr == checker_inst.spec_rs2_addr);
			h_rd_addr_match:  assert (rvfi_rd_addr  == checker_inst.spec_rd_addr);
			// Start by constraining a small slice of the datapath to eliminate
			// unreachable induction states; widen if needed.
			h_csub_lo3_ok:    assert (rvfi_rd_wdata[2:0] == (rvfi_rs1_rdata[2:0] - rvfi_rs2_rdata[2:0]));
			h_csub_have_capture: assert (h_last_csub_valid);
			h_csub_cap_rs1:      assert (rvfi_rs1_rdata == h_last_csub_rs1);
			h_csub_cap_rs2:      assert (rvfi_rs2_rdata == h_last_csub_rs2);
			h_csub_cap_wdata:    assert (rvfi_rd_wdata == h_last_csub_wdata);
			h_csub_cap_sem:      assert (h_last_csub_wdata == (h_last_csub_rs1 - h_last_csub_rs2));
		end
	end

	// Capture the last reg-reg ALU operand pair and the value actually written back.
	// For C.SUB these must line up with the RVFI operands and rd_wdata at check time.
	always @(posedge clock) begin
		if (reset) begin
			h_last_csub_valid <= 0;
			h_last_csub_rs1 <= 0;
			h_last_csub_rs2 <= 0;
			h_last_csub_wdata <= 0;
		end else if (wrapper.uut.cpuregs_write && h_dbg_is_csub &&
			wrapper.uut.dbg_rs1val_valid && wrapper.uut.dbg_rs2val_valid) begin
			h_csub_wdata_sem: assert (wrapper.uut.cpuregs_wrdata == (wrapper.uut.dbg_rs1val - wrapper.uut.dbg_rs2val));
			h_last_csub_valid <= 1;
			h_last_csub_rs1 <= wrapper.uut.dbg_rs1val;
			h_last_csub_rs2 <= wrapper.uut.dbg_rs2val;
			h_last_csub_wdata <= wrapper.uut.cpuregs_wrdata;
		end
	end

	// RVFI/debug pipeline bookkeeping inside picoRV32: dbg_next is a 1-cycle
	// delayed copy of launch_next_insn.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			h_dbg_next_pipeline: assert (wrapper.uut.dbg_next == $past(wrapper.uut.launch_next_insn));
		end
	end

	// RVFI opcode is captured into the q_* bookkeeping register each cycle.
	always @(posedge clock) begin
		if (!reset) begin
			h_rvfi_insn_matches_q: assert (rvfi_insn == wrapper.uut.q_insn_opcode);
		end
	end

/// Helper Assertion End
endmodule
