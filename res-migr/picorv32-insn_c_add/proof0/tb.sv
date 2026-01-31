
`default_nettype none
`include "defines.sv"

module testbench (
	input check,
	input clock, reset
);
	// RVFI signals between DUT and checker
	// No worry about macro content - inspect dut.xxx and chk.xxx signals directly instead.
	`RVFI_WIRES

	// Free variables for formal verification (non-deterministic inputs)
	(* keep *) wire trap;
	(* keep *) `rvformal_rand_reg mem_ready;
	(* keep *) `rvformal_rand_reg [31:0] mem_rdata;
	(* keep *) wire mem_valid;
	(* keep *) wire mem_instr;
	(* keep *) wire [31:0] mem_addr;
	(* keep *) wire [31:0] mem_wdata;
	(* keep *) wire [3:0]  mem_wstrb;

	// Instantiate picorv32 core
	picorv32 #(
		.COMPRESSED_ISA(1),
		.ENABLE_FAST_MUL(1), .ENABLE_DIV(1),
		.BARREL_SHIFTER(1)
	) uut (
		.clk(clock), .resetn(!reset), .trap(trap),
		.mem_valid(mem_valid), .mem_instr(mem_instr),
		.mem_ready(mem_ready), .mem_addr(mem_addr),
		.mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
		.mem_rdata(mem_rdata),
		`RVFI_CONN
	);

	// Instantiate the formal property checker
	rvfi_insn_check chk (
		.clock(clock), .reset(reset), .check(check),
		`RVFI_CONN
	);
	
	// Prevent unrealistic loopback: all 1 rvfi_order creates circular dependency.
	reg rvfi_order_loopback;
	always@(posedge clock) begin
		if (reset) begin
			rvfi_order_loopback <= 0;
		end else if (rvfi_valid && rvfi_order == {64{1'b1}}) begin
			rvfi_order_loopback <= 1;
		end
	end
	always_comb assume (!(rvfi_order_loopback && check));

	/// Helper Assertion Begin
	reg prev_launch_next_insn;
	reg prev_trap;
	reg [31:0] prev_dbg_insn_addr;
	reg [31:0] prev_dbg_insn_opcode;
	reg [31:0] prev_next_pc;
	reg [7:0] prev_cpu_state;
	reg prev_decoder_trigger;
	reg prev_latched_branch;
	reg prev_instr_add;
	reg prev_instr_trap;
	reg prev_latched_compr;
	reg prev_dbg_rs1val_valid;
	reg prev_dbg_rs2val_valid;
	reg last_cpuregs_write;
	reg [4:0] last_latched_rd;
	reg [31:0] last_cpuregs_wrdata;
	reg [1:0] last_irq_state;
	reg [31:0] last_dbg_rs1val;
	reg [31:0] last_dbg_rs2val;
	reg last_dbg_rs1val_valid;
	reg last_dbg_rs2val_valid;
	reg add_wb_pending;
	reg [4:0] add_wb_rd;
	reg [31:0] add_wb_data;
	reg [31:0] add_wb_insn;
	reg [31:0] add_wb_rs1;
	reg [31:0] add_wb_rs2;
	reg add_wb_rs1_valid;
	reg add_wb_rs2_valid;

	function automatic bit no_x32(input [31:0] v);
		logic r;
		r = ^v;
		no_x32 = (r === 1'b0) || (r === 1'b1);
	endfunction
	function automatic bit no_x5(input [4:0] v);
		logic r;
		r = ^v;
		no_x5 = (r === 1'b0) || (r === 1'b1);
	endfunction

	// C.ADD (CR-type, 16-bit): opcode[1:0]=10, funct4[15:12]=1001, rs2[6:2]!=0, upper 16 bits are zero.
	// Matches rvfi_insn_c_add.v spec_valid decode.
	wire is_c_add = (rvfi_insn[1:0] == 2'b10) && (rvfi_insn[15:12] == 4'b1001) && (rvfi_insn[6:2] != 5'd0) && (rvfi_insn[31:16] == 16'b0);
	wire dbg_is_c_add = (uut.dbg_insn_opcode[1:0] == 2'b10) && (uut.dbg_insn_opcode[15:12] == 4'b1001) && (uut.dbg_insn_opcode[6:2] != 5'd0) && (uut.dbg_insn_opcode[31:16] == 16'b0);
	wire do_spec_check = check && chk.spec_valid && !chk.spec_trap && !chk.mem_fault;
	wire do_spec_rvfi_check = do_spec_check && (rvfi_valid[0] === 1'b1);
	wire last_rd_is_x0 = (last_latched_rd === 5'd0);

	always @(posedge clock) begin
		prev_launch_next_insn <= uut.launch_next_insn;
		prev_trap <= uut.trap;
		prev_dbg_insn_addr <= uut.dbg_insn_addr;
		prev_dbg_insn_opcode <= uut.dbg_insn_opcode;
		prev_next_pc <= uut.next_pc;
		prev_cpu_state <= uut.cpu_state;
		prev_decoder_trigger <= uut.decoder_trigger;
		prev_latched_branch <= uut.latched_branch;
		prev_instr_add <= uut.instr_add;
		prev_instr_trap <= uut.instr_trap;
		prev_latched_compr <= uut.latched_compr;
		prev_dbg_rs1val_valid <= uut.dbg_rs1val_valid;
		prev_dbg_rs2val_valid <= uut.dbg_rs2val_valid;
		last_cpuregs_write <= uut.cpuregs_write;
		last_latched_rd <= uut.latched_rd;
		last_cpuregs_wrdata <= uut.cpuregs_wrdata;
		last_irq_state <= uut.irq_state;
		last_dbg_rs1val <= uut.dbg_rs1val;
		last_dbg_rs2val <= uut.dbg_rs2val;
		last_dbg_rs1val_valid <= uut.dbg_rs1val_valid;
		last_dbg_rs2val_valid <= uut.dbg_rs2val_valid;

		if (reset) begin
			add_wb_pending <= 0;
			add_wb_rd <= 0;
			add_wb_data <= 0;
			add_wb_insn <= 0;
			add_wb_rs1 <= 0;
			add_wb_rs2 <= 0;
			add_wb_rs1_valid <= 0;
			add_wb_rs2_valid <= 0;
		end else begin
			// Track the (single) register-file writeback corresponding to the current C.ADD.
			// We intentionally do not assume a fixed latency between cpuregs_write and rvfi_valid.
			if (dbg_is_c_add && uut.cpuregs_write && uut.irq_state == 0) begin
				// Deep semantic lemma: C.ADD writeback uses the captured rs1 and rs2 operands.
				// This avoids spurious traces where rvfi_rs* reflect one pair of operands while
				// the core writes back an unrelated value.
				h_c_add_wb_is_compressed: assert(uut.latched_compr);
				h_c_add_wb_rd_matches_insn: assert(uut.latched_rd == uut.dbg_insn_opcode[11:7]);
				h_c_add_wb_insn_is_16b_padded: assert(uut.dbg_insn_opcode[31:16] == 16'b0);
				h_c_add_wb_opcode10: assert(uut.dbg_insn_opcode[1:0] == 2'b10);
				h_c_add_wb_funct4_1001: assert(uut.dbg_insn_opcode[15:12] == 4'b1001);
				h_c_add_wb_rs2_nonzero: assert(uut.dbg_insn_opcode[6:2] != 5'd0);
				if (uut.latched_rd != 0) begin
					h_c_add_wb_rs1_present: assert(uut.dbg_rs1val_valid);
					h_c_add_wb_rs2_present: assert(uut.dbg_rs2val_valid);
					h_c_add_wb_insn_known: assert(no_x32(uut.dbg_insn_opcode));
					h_c_add_wb_rs1_known: assert(no_x32(uut.dbg_rs1val));
					h_c_add_wb_rs2_known: assert(no_x32(uut.dbg_rs2val));
					h_c_add_wb_wrdata_known: assert(no_x32(uut.cpuregs_wrdata));
					if (check) begin
						h_c_add_wb_data_is_sum: assert(uut.cpuregs_wrdata == uut.dbg_rs1val + uut.dbg_rs2val);
					end
				end
				add_wb_pending <= 1;
				add_wb_rd <= uut.latched_rd;
				add_wb_data <= uut.cpuregs_wrdata;
				add_wb_insn <= uut.dbg_insn_opcode;
				add_wb_rs1 <= uut.dbg_rs1val;
				add_wb_rs2 <= uut.dbg_rs2val;
				add_wb_rs1_valid <= uut.dbg_rs1val_valid;
				add_wb_rs2_valid <= uut.dbg_rs2val_valid;
			end
			// Consume the tracked writeback when the checker is actually evaluating a C.ADD retirement.
			// Use chk.spec_rd_addr (not rvfi_rd_addr) so the helper cannot be skipped due to an
			// underconstrained RVFI rd address in hard transitions.
			if (check && rvfi_valid[0] && chk.spec_valid && !chk.spec_trap && !chk.mem_fault && is_c_add && !(chk.spec_rd_addr === 5'd0)) begin
				h_add_wb_pending: assert(add_wb_pending);
				h_add_wb_rd_matches: assert(add_wb_rd == chk.spec_rd_addr);
				h_add_wb_operands_valid: assert(add_wb_rs1_valid && add_wb_rs2_valid);
				h_c_add_wb_insn_matches_retire: assert(rvfi_insn == add_wb_insn);
				h_c_add_wb_rs1_matches_retire: assert(rvfi_rs1_rdata == add_wb_rs1);
				h_c_add_wb_rs2_matches_retire: assert(rvfi_rs2_rdata == add_wb_rs2);
				h_c_add_wb_data_matches_semantics: assert(add_wb_data == (add_wb_rs1 + add_wb_rs2));
				h_add_rvfi_wdata_from_wb: assert(rvfi_rd_wdata == add_wb_data);
				h_add_spec_wdata_from_wb: assert(chk.spec_rd_wdata == add_wb_data);
				add_wb_pending <= 0;
			end
			// For rd=x0, the spec forces rd_wdata=0; PicoRV32 may suppress the regfile write.
			if (check && rvfi_valid[0] && chk.spec_valid && !chk.spec_trap && !chk.mem_fault && is_c_add && (chk.spec_rd_addr === 5'd0)) begin
				h_c_add_x0_rd_addr: assert(rvfi_rd_addr == 5'd0);
				h_c_add_x0_rd_wdata: assert(rvfi_rd_wdata == 32'd0);
				h_c_add_x0_spec_rd_wdata: assert(chk.spec_rd_wdata == 32'd0);
			end
		end

		if (!reset) begin
			// RVFI operand read-data is driven from dbg_rs*val using nonblocking assignments,
			// so the architectural RVFI view naturally matches the previous-cycle dbg capture.
			h_rvfi_rs1_rdata_piped: assert(!(check && rvfi_valid[0] && chk.spec_valid && !chk.spec_trap && !chk.mem_fault) || rvfi_rs1_rdata == (last_dbg_rs1val_valid ? last_dbg_rs1val : 32'd0));
			h_rvfi_rs2_rdata_piped: assert(!(check && rvfi_valid[0] && chk.spec_valid && !chk.spec_trap && !chk.mem_fault) || rvfi_rs2_rdata == (last_dbg_rs2val_valid ? last_dbg_rs2val : 32'd0));

			// If the core wrote the register file in the previous cycle (non-IRQ path), RVFI must
			// reflect that write at the subsequent retirement.
			if (check && rvfi_valid[0] && last_cpuregs_write && last_irq_state == 0) begin
				h_rvfi_rd_matches_last_write_addr: assert(rvfi_rd_addr == last_latched_rd);
				h_rvfi_rd_matches_last_write_data: assert(rvfi_rd_wdata == (last_latched_rd != 0 ? last_cpuregs_wrdata : 32'd0));
			end
			// For a checked, non-trapping retirement, the ISA model's rd_wdata must match the
			// core's concrete register-file writeback (which occurs one cycle earlier in PicoRV32).
			// This is the key strengthening for o_rd_wdata_match: it connects spec_* to the
			// same writeback that already constrains RVFI.
			h_spec_rd_wdata_matches_last_write: assert(!(do_spec_rvfi_check && last_cpuregs_write && last_irq_state == 0) || (chk.spec_rd_wdata == (last_rd_is_x0 ? 32'd0 : last_cpuregs_wrdata)));
			h_spec_rd_addr_matches_last_write: assert(!(do_spec_rvfi_check && last_cpuregs_write && last_irq_state == 0) || (chk.spec_rd_addr == last_latched_rd));
			// C.ADD-specific: the retiring instruction's architectural result must be produced by
			// the previous-cycle core writeback using the captured rs1 and rs2 values.
			// Avoid X-propagation: SVA treats X as failure.
			// When we're actively checking a retirement, RVFI fields must be fully known.
			if (check && rvfi_valid[0]) begin
				h_rvfi_insn_known: assert(no_x32(rvfi_insn));
				h_rvfi_pc_rdata_known: assert(no_x32(rvfi_pc_rdata));
				h_rvfi_pc_wdata_known: assert(no_x32(rvfi_pc_wdata));
				h_rvfi_rs1_rdata_known: assert(no_x32(rvfi_rs1_rdata));
				h_rvfi_rs2_rdata_known: assert(no_x32(rvfi_rs2_rdata));
				h_rvfi_rs1_addr_known: assert(no_x5(rvfi_rs1_addr));
				h_rvfi_rs2_addr_known: assert(no_x5(rvfi_rs2_addr));
				h_rvfi_rd_addr_known: assert(no_x5(rvfi_rd_addr));
			end

			// When we launched an instruction last cycle, dbg_insn_addr is updated from the computed next_pc.
			h_dbg_insn_addr_updates_from_next_pc: assert(!prev_launch_next_insn || uut.dbg_insn_addr == prev_next_pc);

			// RVFI signals are pipelined from the debug signals; expose that pipeline to the solver.
			h_rvfi_pc_rdata_piped: assert(!rvfi_valid[0] || rvfi_pc_rdata == prev_dbg_insn_addr);
			h_rvfi_insn_piped: assert(!rvfi_valid[0] || rvfi_insn == prev_dbg_insn_opcode);
			h_rvfi_insn_matches_q_insn_opcode: assert(!rvfi_valid[0] || rvfi_insn == uut.q_insn_opcode);
			h_rvfi_pc_wdata_matches_dbg_addr: assert(!rvfi_valid[0] || rvfi_pc_wdata == uut.dbg_insn_addr);

			// A non-trap RVFI retirement is triggered by a launch_next_insn in the *previous* cycle,
			// which (by definition) happens in fetch with decoder_trigger.
			h_rvfi_valid_originates_from_launch: assert(!rvfi_valid[0] || rvfi_trap[0] || prev_launch_next_insn);
			h_rvfi_valid_prev_in_fetch: assert(!rvfi_valid[0] || rvfi_trap[0] || prev_cpu_state == 8'h40);
			h_rvfi_valid_prev_decoder_trigger: assert(!rvfi_valid[0] || rvfi_trap[0] || prev_decoder_trigger);
			h_dbg_next_matches_prev_launch: assert(uut.dbg_next == prev_launch_next_insn);

			// C.ADD-specific retirement constraints.
			// Use chk.spec_valid (not raw 4-state compares) so the helper actually fires in the
			// same situations as the real objectives.
			if (check && rvfi_valid[0] && chk.spec_valid && !chk.spec_trap && !chk.mem_fault) begin
				h_c_add_is_16b_padded: assert(rvfi_insn[31:16] == 16'b0);
				h_c_add_opcode10: assert(rvfi_insn[1:0] == 2'b10);
				h_c_add_funct4_1001: assert(rvfi_insn[15:12] == 4'b1001);
				h_c_add_rs2_nonzero: assert(rvfi_insn[6:2] != 5'd0);
				// RVFI rs* address plumbing comes directly from dbg_rs*val_valid + instruction fields.
				// (See picorv32 RISCV_FORMAL assignments: rvfi_rs*_addr <= dbg_rs*val_valid ? dbg_insn_rs* : 0.)
				h_rvfi_rs1_addr_piped: assert(rvfi_rs1_addr == (last_dbg_rs1val_valid ? rvfi_insn[11:7] : 5'd0));
				h_rvfi_rs2_addr_piped: assert(rvfi_rs2_addr == (last_dbg_rs2val_valid ? rvfi_insn[6:2] : 5'd0));
				// C.ADD consumes both rs1 and rs2; rs2 is always nonzero by decode.
				h_c_add_rs2_captured: assert(last_dbg_rs2val_valid);
				// For rs1=x0, allow implicit zero; otherwise it must be captured.
				if (rvfi_insn[11:7] != 5'd0) begin
					h_c_add_rs1_captured: assert(last_dbg_rs1val_valid);
				end
				// x0 destination must observe a zero writeback in RVFI.
				h_c_add_x0_write_suppressed: assert(rvfi_insn[11:7] == 5'd0 ? (rvfi_rd_wdata == 32'd0) : 1'b1);

				// Avoid spurious failure from X-propagation: the check uses 4-state '==' and
				// any X bit on either side makes the assertion evaluate to X (and fail).
				h_c_add_rvfi_rd_wdata_known: assert(no_x32(rvfi_rd_wdata));
				h_c_add_spec_rd_wdata_known: assert(no_x32(chk.spec_rd_wdata));

				// Make the spec model's register addressing explicit and 2-state.
				// If these are left X, the model can produce X outputs even with known operands.
				h_c_add_spec_rs1_addr_known: assert(no_x5(chk.spec_rs1_addr));
				h_c_add_spec_rs2_addr_known: assert(no_x5(chk.spec_rs2_addr));
				h_c_add_spec_rd_addr_known: assert(no_x5(chk.spec_rd_addr));
				h_c_add_spec_rs1_addr_matches_insn: assert(chk.spec_rs1_addr == rvfi_insn[11:7]);
				h_c_add_spec_rs2_addr_matches_insn: assert(chk.spec_rs2_addr == rvfi_insn[6:2]);
				h_c_add_spec_rs2_nonzero: assert(chk.spec_rs2_addr != 5'd0);
				h_c_add_spec_rd_addr_matches_insn: assert(chk.spec_rd_addr == rvfi_insn[11:7]);
				// PC always increments by 2 for 16-bit C.ADD.
				h_c_add_spec_pc_inc2: assert(chk.spec_pc_wdata == rvfi_pc_rdata + 32'd2);

				// Architectural x0 reads are always zero.
				h_c_add_x0_rs1_reads_zero: assert(chk.spec_rs1_addr != 0 ? 1'b1 : (rvfi_rs1_rdata == 32'd0));

			end

			// Bridge the ISA-model's C.ADD decode to PicoRV32's internal state.
			// RVFI signals lag the internal decode by (at least) one cycle; use prev_*.
			if (check && chk.spec_valid && !chk.spec_trap && !chk.mem_fault) begin
				h_spec_c_add_not_trap_decode: assert(!prev_instr_trap);
				h_spec_c_add_is_compressed: assert(prev_latched_compr);
				h_spec_c_add_not_rvfi_trap: assert(!rvfi_trap[0]);
				h_spec_c_add_uses_add_datapath: assert(prev_instr_add);
				// For C.ADD, rs2 is always consumed (nonzero by decode).
				h_spec_c_add_rs2_captured: assert(prev_dbg_rs2val_valid);
				// For rs1=x0, allow implicit zero; otherwise it must be captured.
				if (prev_dbg_insn_opcode[11:7] != 5'd0) begin
					h_spec_c_add_rs1_captured: assert(prev_dbg_rs1val_valid);
				end
			end

			// Strengthen the state space around the *exact* o_rd_wdata_match guard.
			// Use implication-style asserts so the constraints cannot be skipped due to X guards.
			h_spec_implies_rvfi_valid: assert(!do_spec_check || (rvfi_valid[0] === 1'b1));
			h_spec_implies_c_add: assert(!do_spec_rvfi_check || is_c_add);
			h_spec_rvfi_insn_known: assert(!do_spec_rvfi_check || no_x32(rvfi_insn));
			h_spec_rvfi_rs1_rdata_known: assert(!do_spec_rvfi_check || no_x32(rvfi_rs1_rdata));
			h_spec_rvfi_rs2_rdata_known: assert(!do_spec_rvfi_check || no_x32(rvfi_rs2_rdata));
			h_spec_rvfi_rd_wdata_known: assert(!do_spec_rvfi_check || no_x32(rvfi_rd_wdata));
			h_spec_model_addrs_known: assert(!do_spec_rvfi_check || (no_x5(chk.spec_rs1_addr) && no_x5(chk.spec_rs2_addr) && no_x5(chk.spec_rd_addr)));
			h_spec_model_wdata_known: assert(!do_spec_rvfi_check || no_x32(chk.spec_rd_wdata));
			// Spec-level invariants for C.ADD: rd == rs1.
			h_c_add_spec_rd_equals_rs1: assert(!do_spec_rvfi_check || (chk.spec_rd_addr == chk.spec_rs1_addr));
			// ISA semantics for C.ADD on both sides: rd_wdata must be rs1+rs2 (x0 writes suppressed).
			h_c_add_spec_semantic_rd_wdata: assert(!do_spec_rvfi_check || (chk.spec_rd_wdata == ((chk.spec_rd_addr === 5'd0) ? 32'd0 : (rvfi_rs1_rdata + rvfi_rs2_rdata))));
			h_c_add_semantic_rd_wdata: assert(!do_spec_rvfi_check || (rvfi_rd_wdata == ((chk.spec_rd_addr === 5'd0) ? 32'd0 : (rvfi_rs1_rdata + rvfi_rs2_rdata))));
			// For C.ADD (a 16-bit compressed ALU op), architectural next PC is always PC+2.
			h_c_add_pc_plus2: assert(!do_spec_rvfi_check || (rvfi_pc_wdata == rvfi_pc_rdata + 32'd2));
			// Address plumbing: RVFI architectural register indices must match the ISA model.
			h_spec_rvfi_rs_addrs_match: assert(!do_spec_rvfi_check || (rvfi_rs1_addr == chk.spec_rs1_addr && rvfi_rs2_addr == chk.spec_rs2_addr));
			h_spec_rvfi_rd_addr_match: assert(!do_spec_rvfi_check || (rvfi_rd_addr == chk.spec_rd_addr));
		end
	end
	/// Helper Assertion End
endmodule