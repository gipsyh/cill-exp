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

	wire h_is_sw = (wrapper.uut.dbg_insn_opcode[6:0] == 7'b0100011) && (wrapper.uut.dbg_insn_opcode[14:12] == 3'b010);
	wire [31:0] h_sw_imm = $signed({{20{wrapper.uut.dbg_insn_opcode[31]}}, wrapper.uut.dbg_insn_opcode[31:25], wrapper.uut.dbg_insn_opcode[11:7]});
	wire [31:0] h_sw_addr = wrapper.uut.dbg_rs1val + h_sw_imm;
	wire [31:0] h_sw_addr_aligned = h_sw_addr & 32'hffff_fffc;

	always @(posedge clock) begin
		if (!reset) begin
			// Core control-state is one-hot encoded.
			h_cpu_state_onehot: assert(
				wrapper.uut.cpu_state == 8'b10000000 ||
				wrapper.uut.cpu_state == 8'b01000000 ||
				wrapper.uut.cpu_state == 8'b00100000 ||
				wrapper.uut.cpu_state == 8'b00010000 ||
				wrapper.uut.cpu_state == 8'b00001000 ||
				wrapper.uut.cpu_state == 8'b00000100 ||
				wrapper.uut.cpu_state == 8'b00000010 ||
				wrapper.uut.cpu_state == 8'b00000001
			);
			// A retiring SW implies a data-memory transaction, not an instruction fetch.
			h_sw_not_mem_instr: assert(!(checker_inst.spec_valid && !checker_inst.spec_trap) || !wrapper.uut.mem_instr);
			// A retiring SW implies its store handshake has completed (no outstanding store in-flight).
			h_sw_no_mem_do_wdata: assert(!(checker_inst.spec_valid && !checker_inst.spec_trap) || !wrapper.uut.mem_do_wdata);
			// An outstanding store request only exists while the core is in the store-memory state (or has trapped).
			h_mem_do_wdata_in_stmem: assert(!wrapper.uut.mem_do_wdata || wrapper.uut.cpu_state == 8'b00000010 || wrapper.uut.cpu_state == 8'b10000000);
			if (!$past(reset)) begin
				// Once a data-read request persists beyond one cycle, the memory interface must be in data mode.
				h_mem_do_rdata_not_instr: assert(!(wrapper.uut.mem_do_rdata && $past(wrapper.uut.mem_do_rdata)) || !wrapper.uut.mem_instr);
				h_mem_do_rdata_implies_valid: assert(!(wrapper.uut.mem_do_rdata && $past(wrapper.uut.mem_do_rdata)) || wrapper.uut.mem_valid);
				// rvfi_mem_* is updated from the previous cycle's mem_* handshake.
				h_sw_not_mem_instr_past: assert(!(checker_inst.spec_valid && !checker_inst.spec_trap) || !$past(wrapper.uut.mem_instr));
			end
			// During an SW data-memory handshake, mem_addr matches the architectural address (aligned-memory semantics).
			h_sw_mem_addr_follows_dbg: assert(!(wrapper.uut.mem_valid && wrapper.uut.mem_ready && !wrapper.uut.mem_instr && h_is_sw) ||
				wrapper.uut.mem_addr == h_sw_addr_aligned);
			// With aligned-memory semantics, the reported base address must be word-aligned.
			h_sw_mem_addr_aligned: assert(!(checker_inst.spec_valid && !checker_inst.spec_trap) || checker_inst.rvfi_mem_addr[1:0] == 2'b00);
			h_sw_mem_addr_bit2_match: assert(!(checker_inst.spec_valid && !checker_inst.spec_trap) || checker_inst.rvfi_mem_addr[2] == checker_inst.spec_mem_addr[2]);
			h_sw_mem_addr_bit7_match: assert(!(checker_inst.spec_valid && !checker_inst.spec_trap) || checker_inst.rvfi_mem_addr[7] == checker_inst.spec_mem_addr[7]);
			h_sw_mem_addr_bit31_match: assert(!(checker_inst.spec_valid && !checker_inst.spec_trap && !wrapper.uut.mem_do_wdata) ||
				checker_inst.rvfi_mem_addr[31] == checker_inst.spec_mem_addr[31]);
		end
	end

/// Helper Assertion End
endmodule
