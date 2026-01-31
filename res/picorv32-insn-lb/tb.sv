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

	// Track that we've observed the (single) reset pulse. This is a common
	// strengthening for induction: it excludes arbitrary "post-reset" states
	// that are not reachable from the actual reset sequence.
	reg h_seen_reset;
	always @(posedge clock) begin
		if (reset)
			h_seen_reset <= 1'b1;
	end

	// Delay flag to safely use $past() (reset is high only in cycle 0).
	reg h_past_valid;
	always @(posedge clock) begin
		if (reset)
			h_past_valid <= 1'b0;
		else
			h_past_valid <= 1'b1;
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_post_reset_only: assert(h_seen_reset);
		end
	end

	// PicoRV32 memory-interface invariants (mirrors the core's own commented
	// formal checks). These help rule out unreachable CTIs where the RVFI
	// memory address can become decoupled from the core's memory protocol.
	always @(posedge clock) begin
		if (!reset && !wrapper.uut.trap) begin
			if (wrapper.uut.mem_do_prefetch || wrapper.uut.mem_do_rinst || wrapper.uut.mem_do_rdata)
				h_no_wdata_with_reads: assert(!wrapper.uut.mem_do_wdata);
			if (wrapper.uut.mem_do_prefetch || wrapper.uut.mem_do_rinst)
				h_no_rdata_with_rinst: assert(!wrapper.uut.mem_do_rdata);
			if (wrapper.uut.mem_do_rdata)
				h_rdata_exclusive: assert(!wrapper.uut.mem_do_prefetch && !wrapper.uut.mem_do_rinst);
			if (wrapper.uut.mem_do_wdata)
				h_wdata_exclusive: assert(!(wrapper.uut.mem_do_prefetch || wrapper.uut.mem_do_rinst || wrapper.uut.mem_do_rdata));

			// Instruction fetches must be read-only.
			if (wrapper.uut.mem_valid && wrapper.uut.mem_instr)
				h_ifetch_readonly: assert(wrapper.uut.mem_wstrb == 0);
		end
	end

	// Look-ahead interface consistency: mem_addr/mem_w* must reflect the
	// last mem_la_* request when it was issued.
	reg        h_last_mem_la_read;
	reg        h_last_mem_la_write;
	reg [31:0] h_last_mem_la_addr;
	reg [31:0] h_last_mem_la_wdata;
	reg [ 3:0] h_last_mem_la_wstrb;

	always @(posedge clock) begin
		if (reset) begin
			h_last_mem_la_read  <= 1'b0;
			h_last_mem_la_write <= 1'b0;
			h_last_mem_la_addr  <= 32'b0;
			h_last_mem_la_wdata <= 32'b0;
			h_last_mem_la_wstrb <= 4'b0;
		end else begin
			h_last_mem_la_read  <= wrapper.uut.mem_la_read;
			h_last_mem_la_write <= wrapper.uut.mem_la_write;
			h_last_mem_la_addr  <= wrapper.uut.mem_la_addr;
			h_last_mem_la_wdata <= wrapper.uut.mem_la_wdata;
			h_last_mem_la_wstrb <= wrapper.uut.mem_la_wstrb;
		end
	end

	always @(posedge clock) begin
		if (!reset && !wrapper.uut.trap) begin
			if (h_last_mem_la_read) begin
				h_la_read_implies_mem_valid: assert(wrapper.uut.mem_valid);
				h_la_read_addr_match: assert(wrapper.uut.mem_addr == h_last_mem_la_addr);
				h_la_read_no_wstrb: assert(wrapper.uut.mem_wstrb == 0);
			end
			if (h_last_mem_la_write) begin
				h_la_write_implies_mem_valid: assert(wrapper.uut.mem_valid);
				h_la_write_addr_match: assert(wrapper.uut.mem_addr == h_last_mem_la_addr);
				h_la_write_wdata_match: assert(wrapper.uut.mem_wdata == h_last_mem_la_wdata);
				h_la_write_wstrb_match: assert(wrapper.uut.mem_wstrb == h_last_mem_la_wstrb);
			end
			if (wrapper.uut.mem_la_read || wrapper.uut.mem_la_write) begin
				h_la_req_no_stall: assert(!wrapper.uut.mem_valid || wrapper.uut.mem_ready);
			end
		end
	end

	// RVFI memory address is aligned when a data access is reported.
	always @(posedge clock) begin
		if (!reset && rvfi_valid && (rvfi_mem_rmask || rvfi_mem_wmask)) begin
			h_rvfi_mem_addr_aligned: assert(rvfi_mem_addr[1:0] == 2'b00);
		end
	end

	// For an LB retirement, RVFI must report the data-access address. PicoRV32
	// clears RVFI mem signals whenever the core indicates an instruction fetch
	// on the memory port (mem_instr=1). In reachable executions, the cycle that
	// triggers an RVFI commit for an LB must therefore not be an instruction
	// fetch cycle; otherwise RVFI would lose the data-access address.
	wire h_dbg_is_lb = (wrapper.uut.dbg_insn_opcode[6:0] == 7'b0000011) &&
	                   (wrapper.uut.dbg_insn_opcode[14:12] == 3'b000);
	always @(posedge clock) begin
		if (!reset && check && wrapper.uut.dbg_valid_insn && wrapper.uut.launch_next_insn && h_dbg_is_lb) begin
			h_lb_commit_not_ifetch: assert(!wrapper.uut.dbg_mem_instr);
		end
	end

	// cpu_state must always be one of the one-hot encoded states.
	localparam [7:0] h_cpu_state_trap   = 8'b1000_0000;
	localparam [7:0] h_cpu_state_fetch  = 8'b0100_0000;
	localparam [7:0] h_cpu_state_ld_rs1 = 8'b0010_0000;
	localparam [7:0] h_cpu_state_ld_rs2 = 8'b0001_0000;
	localparam [7:0] h_cpu_state_exec   = 8'b0000_1000;
	localparam [7:0] h_cpu_state_shift  = 8'b0000_0100;
	localparam [7:0] h_cpu_state_stmem  = 8'b0000_0010;
	localparam [7:0] h_cpu_state_ldmem  = 8'b0000_0001;

	reg h_cpu_state_ok;
	always @(posedge clock) begin
		if (!reset) begin
			h_cpu_state_ok = 1'b0;
			if (wrapper.uut.cpu_state == h_cpu_state_trap)   h_cpu_state_ok = 1'b1;
			if (wrapper.uut.cpu_state == h_cpu_state_fetch)  h_cpu_state_ok = 1'b1;
			if (wrapper.uut.cpu_state == h_cpu_state_ld_rs1) h_cpu_state_ok = 1'b1;
			if (wrapper.uut.cpu_state == h_cpu_state_ld_rs2) h_cpu_state_ok = 1'b1;
			if (wrapper.uut.cpu_state == h_cpu_state_exec)   h_cpu_state_ok = 1'b1;
			if (wrapper.uut.cpu_state == h_cpu_state_shift)  h_cpu_state_ok = 1'b1;
			if (wrapper.uut.cpu_state == h_cpu_state_stmem)  h_cpu_state_ok = 1'b1;
			if (wrapper.uut.cpu_state == h_cpu_state_ldmem)  h_cpu_state_ok = 1'b1;

			h_cpu_state_valid: assert(h_cpu_state_ok);
		end
	end

	// If the next-cycle RVFI event will report an LB instruction, ensure the
	// RVFI data-memory address that will be visible then is already consistent
	// with the LB base+imm address (aligned) computed from the core's debug
	// snapshot in this cycle.
	wire [31:0] h_dbg_rs1_base = wrapper.uut.dbg_rs1val_valid ? wrapper.uut.dbg_rs1val : 32'b0;
	wire signed [31:0] h_lb_imm = $signed(wrapper.uut.dbg_insn_opcode[31:20]);
	wire [31:0] h_lb_mem_addr = ($signed(h_dbg_rs1_base) + h_lb_imm) & 32'hffff_fffc;

	wire h_next_rvfi_lb = !reset && check && wrapper.uut.dbg_valid_insn &&
	                      (wrapper.uut.launch_next_insn || wrapper.uut.trap) &&
	                      h_dbg_is_lb;

	always @(posedge clock) begin
		if (h_next_rvfi_lb) begin
			// Must not clear RVFI mem signals on an instruction fetch in the
			// same cycle that produces the RVFI report for LB.
			h_lb_report_not_cleared: assert(!wrapper.uut.dbg_mem_instr);

			// If a data xfer happens this cycle, RVFI will latch its address.
			// Otherwise RVFI must already hold the correct LB address.
			if (wrapper.uut.dbg_mem_valid && wrapper.uut.dbg_mem_ready)
				h_lb_report_mem_addr_xfer: assert(wrapper.uut.dbg_mem_addr == h_lb_mem_addr);
			else
				h_lb_report_mem_addr_hold: assert(rvfi_mem_addr == h_lb_mem_addr);
		end
	end

/// Helper Assertion End
endmodule
