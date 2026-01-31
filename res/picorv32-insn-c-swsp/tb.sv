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

	// If the instruction model considers the current retired instruction a valid,
	// non-trapping C.SWSP, the core must not be in the terminal trap state.
	always @(posedge clock) begin
		if (!reset) begin
			if (checker_inst.spec_valid && !checker_inst.spec_trap) begin
				h_no_core_trap_on_spec_nontrap: assert(!wrapper.trap);
			end
		end
	end

	// C.SWSP is a store. For a valid, non-trapping instance we must observe a non-zero
	// RVFI write mask (i.e. the core actually performed a data memory write).
	always @(posedge clock) begin
		if (!reset) begin
			if (checker_inst.spec_valid && !checker_inst.spec_trap) begin
				h_store_has_mem_wmask: assert(rvfi_mem_wmask != 0);
			end
		end
	end

	// Once a data write is in progress, the address base register used for the
	// transaction must remain stable until the write completes.
	always @(posedge clock) begin
		if (!reset && $past(!reset)) begin
			if (wrapper.uut.mem_do_wdata && $past(wrapper.uut.mem_do_wdata)) begin
				h_reg_op1_stable_during_wdata: assert(wrapper.uut.reg_op1 == $past(wrapper.uut.reg_op1));
			end
		end
	end

	// The core remains in cpu_state_stmem until a store completes. Therefore it must
	// not be in the fetch state while a data write is still pending/in progress.
	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.cpu_state == 8'h40) begin // cpu_state_fetch
				h_no_wdata_in_fetch: assert(!wrapper.uut.mem_do_wdata);
			end
		end
	end

	// For a C.SWSP store, the effective store address is SP + imm. Ensure that the
	// address presented to the data memory interface matches this calculation when
	// the store is launched.
	wire [15:0] h_cinsn = wrapper.uut.dbg_insn_opcode[15:0];
	wire        h_is_c_swsp = (wrapper.uut.dbg_insn_opcode[31:16] == 16'b0) &&
	                          (h_cinsn[15:13] == 3'b110) &&
	                          (h_cinsn[1:0] == 2'b10);
	wire [31:0] h_c_swsp_imm = {24'b0, h_cinsn[8:7], h_cinsn[12:9], 2'b00};
	wire [31:0] h_c_swsp_addr = wrapper.uut.dbg_rs1val + h_c_swsp_imm;
	wire [31:0] h_c_swsp_mem_addr = h_c_swsp_addr & 32'hffff_fffc;

	always @(posedge clock) begin
		if (!reset) begin
			if (wrapper.uut.mem_la_write && (wrapper.uut.cpu_state == 8'h02) && h_is_c_swsp &&
			    wrapper.uut.dbg_rs1val_valid) begin
				h_c_swsp_mem_la_addr_match: assert(wrapper.uut.mem_la_addr == h_c_swsp_mem_addr);
			end
		end
	end

/// Helper Assertion End
endmodule
