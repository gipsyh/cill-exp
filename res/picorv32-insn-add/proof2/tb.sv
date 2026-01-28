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
	reg past_valid;
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

	// RV32I ADD (R-type): funct7=0000000, funct3=000, opcode=0110011.
	wire [6:0] rvfi_opcode = rvfi_insn[6:0];
	wire [2:0] rvfi_funct3 = rvfi_insn[14:12];
	wire [6:0] rvfi_funct7 = rvfi_insn[31:25];
	wire [4:0] rvfi_rs1 = rvfi_insn[19:15];
	wire [4:0] rvfi_rs2 = rvfi_insn[24:20];
	wire [4:0] rvfi_rd  = rvfi_insn[11:7];

	wire [6:0] dbg_opcode = uut.dbg_insn_opcode[6:0];
	wire [2:0] dbg_funct3 = uut.dbg_insn_opcode[14:12];
	wire [6:0] dbg_funct7 = uut.dbg_insn_opcode[31:25];
	wire [4:0] dbg_rs1 = uut.dbg_insn_opcode[19:15];
	wire [4:0] dbg_rs2 = uut.dbg_insn_opcode[24:20];
	wire [4:0] dbg_rd  = uut.dbg_insn_opcode[11:7];

	wire is_add = (rvfi_opcode == 7'b0110011) && (rvfi_funct3 == 3'b000) && (rvfi_funct7 == 7'b0000000);
	wire dbg_is_add = (dbg_opcode == 7'b0110011) && (dbg_funct3 == 3'b000) && (dbg_funct7 == 7'b0000000);

	wire do_spec_check = check && (chk.spec_valid === 1'b1) && (chk.spec_trap === 1'b0);
	wire do_spec_rvfi_check = do_spec_check && (rvfi_valid[0] === 1'b1);
	wire last_rd_is_x0 = (last_latched_rd === 5'd0);

	always @(posedge clock) begin
		if (reset) begin
			prev_launch_next_insn <= 0;
			past_valid <= 0;
			prev_trap <= 0;
			prev_dbg_insn_addr <= 0;
			prev_dbg_insn_opcode <= 0;
			prev_next_pc <= 0;
			prev_cpu_state <= 0;
			prev_decoder_trigger <= 0;
			prev_latched_branch <= 0;
			prev_instr_add <= 0;
			prev_instr_trap <= 0;
			prev_latched_compr <= 0;
			prev_dbg_rs1val_valid <= 0;
			prev_dbg_rs2val_valid <= 0;
			last_cpuregs_write <= 0;
			last_latched_rd <= 0;
			last_cpuregs_wrdata <= 0;
			last_irq_state <= 0;
			last_dbg_rs1val <= 0;
			last_dbg_rs2val <= 0;
			last_dbg_rs1val_valid <= 0;
			last_dbg_rs2val_valid <= 0;
			add_wb_pending <= 0;
			add_wb_rd <= 0;
			add_wb_data <= 0;
			add_wb_insn <= 0;
			add_wb_rs1 <= 0;
			add_wb_rs2 <= 0;
			add_wb_rs1_valid <= 0;
			add_wb_rs2_valid <= 0;
		end else begin
			prev_launch_next_insn <= uut.launch_next_insn;
			past_valid <= 1;
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
		end

		if (!reset) begin
			// Ensure the checker model signals are always 2-state when we're using them.
			if (check) begin
				h_chk_spec_valid_2state: assert((chk.spec_valid === 1'b0) || (chk.spec_valid === 1'b1));
				h_chk_spec_trap_2state: assert((chk.spec_trap === 1'b0) || (chk.spec_trap === 1'b1));
			end

			// Track the (single) register-file writeback corresponding to an ADD.
			// Intentionally do not assume a fixed latency between cpuregs_write and rvfi_valid.
			if (dbg_is_add && uut.cpuregs_write && uut.irq_state == 0) begin
				if (uut.latched_rd != 0) begin
					h_wb_operands_present: assert(uut.dbg_rs1val_valid && uut.dbg_rs2val_valid);
					h_wb_not_compressed: assert(!uut.latched_compr);
					h_wb_rd_matches_insn: assert(uut.latched_rd == dbg_rd);
					h_wb_insn_known: assert(no_x32(uut.dbg_insn_opcode));
					h_wb_rs1_known: assert(no_x32(uut.dbg_rs1val));
					h_wb_rs2_known: assert(no_x32(uut.dbg_rs2val));
					h_wb_data_known: assert(no_x32(uut.cpuregs_wrdata));
					h_wb_data_is_add: assert(uut.cpuregs_wrdata == uut.dbg_rs1val + uut.dbg_rs2val);
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

			// Consume the tracked writeback when the checker is evaluating an ADD retirement.
			// Use chk.spec_rd_addr (not rvfi_rd_addr) so the helper can't be skipped if RVFI rd is underconstrained.
			if (check && rvfi_valid[0] && (chk.spec_valid === 1'b1) && (chk.spec_trap === 1'b0) && is_add && !(chk.spec_rd_addr === 5'd0)) begin
				h_wb_pending: assert(add_wb_pending);
				h_wb_rd_matches: assert(add_wb_rd == chk.spec_rd_addr);
				h_wb_operands_valid: assert(add_wb_rs1_valid && add_wb_rs2_valid);
				h_wb_insn_matches_retire: assert(rvfi_insn == add_wb_insn);
				h_wb_rs1_matches_retire: assert(rvfi_rs1_rdata == add_wb_rs1);
				h_wb_rs2_matches_retire: assert(rvfi_rs2_rdata == add_wb_rs2);
				h_wb_data_matches_semantics: assert(add_wb_data == (add_wb_rs1 + add_wb_rs2));
				h_rvfi_wdata_from_wb: assert(rvfi_rd_wdata == add_wb_data);
				h_spec_wdata_from_wb: assert(chk.spec_rd_wdata == add_wb_data);
				add_wb_pending <= 0;
			end
		end

		if (!reset) begin
			// RVFI operand read-data is driven from dbg_rs*val using nonblocking assignments,
			// so the architectural RVFI view naturally matches the previous-cycle dbg capture.
			h_rvfi_rs1_rdata_piped: assert(!(check && rvfi_valid[0] && chk.spec_valid && !chk.spec_trap) || rvfi_rs1_rdata == (last_dbg_rs1val_valid ? last_dbg_rs1val : 32'd0));
			h_rvfi_rs2_rdata_piped: assert(!(check && rvfi_valid[0] && chk.spec_valid && !chk.spec_trap) || rvfi_rs2_rdata == (last_dbg_rs2val_valid ? last_dbg_rs2val : 32'd0));

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
			// Spec-level invariants for RV32I ADD.
			h_add_spec_is_add: assert(!do_spec_rvfi_check || is_add);
			h_add_spec_pc_plus4: assert(!do_spec_rvfi_check || (rvfi_pc_wdata == rvfi_pc_rdata + 32'd4));
			h_add_spec_not_compressed: assert(!do_spec_rvfi_check || (rvfi_insn[1:0] == 2'b11));
			h_spec_rd_wdata_matches_last_write: assert(!(do_spec_rvfi_check && last_cpuregs_write && last_irq_state == 0) || (chk.spec_rd_wdata == (last_rd_is_x0 ? 32'd0 : last_cpuregs_wrdata)));
			h_spec_rd_addr_matches_last_write: assert(!(do_spec_rvfi_check && last_cpuregs_write && last_irq_state == 0) || (chk.spec_rd_addr == last_latched_rd));
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
			h_dbg_next_matches_prev_launch: assert(!past_valid || (uut.dbg_next == prev_launch_next_insn));

			// ADD-specific retirement constraints.
			if (check && rvfi_valid[0] && (chk.spec_valid === 1'b1) && (chk.spec_trap === 1'b0)) begin
				h_add_is_32bit: assert(rvfi_insn[1:0] == 2'b11);
				h_add_is_add: assert(is_add);
				h_add_not_compressed: assert(!prev_latched_compr);
				// ADD consumes both rs1 and rs2.
				h_add_rs1_captured: assert(last_dbg_rs1val_valid);
				h_add_rs2_captured: assert(last_dbg_rs2val_valid);
				// Register addressing must match instruction fields.
				h_add_rvfi_rs1_addr_matches_insn: assert(rvfi_rs1_addr == rvfi_rs1);
				h_add_rvfi_rs2_addr_matches_insn: assert(rvfi_rs2_addr == rvfi_rs2);
				h_add_rvfi_rd_addr_matches_insn: assert(rvfi_rd_addr == rvfi_rd);
				// No memory side-effects.
				h_add_mem_rmask_zero: assert(rvfi_mem_rmask == 0);
				h_add_mem_wmask_zero: assert(rvfi_mem_wmask == 0);
				// Avoid spurious failure from X-propagation.
				h_add_rvfi_rd_wdata_known: assert(no_x32(rvfi_rd_wdata));
				h_add_spec_rd_wdata_known: assert(no_x32(chk.spec_rd_wdata));
			end

			// Bridge the ISA-model decode to PicoRV32's internal decode flags.
			// RVFI retirement lags internal decode by (at least) one cycle; use prev_*.
			if (check && (chk.spec_valid === 1'b1) && (chk.spec_trap === 1'b0)) begin
				h_spec_add_matches_core_decode: assert(prev_instr_add);
				h_spec_add_not_trap_decode: assert(!prev_instr_trap);
				h_spec_add_not_compressed: assert(!prev_latched_compr);
				h_spec_add_not_rvfi_trap: assert(!rvfi_trap[0]);
				h_spec_add_rs1_captured: assert(prev_dbg_rs1val_valid);
				h_spec_add_rs2_captured: assert(prev_dbg_rs2val_valid);
			end

			// Strengthen the state space around the *exact* o_rd_wdata_match guard.
			// Use implication-style asserts so the constraints cannot be skipped due to X guards.
			h_spec_implies_rvfi_valid: assert(!do_spec_check || (rvfi_valid[0] === 1'b1));
			if (do_spec_rvfi_check) begin
				h_spec_implies_add: assert(is_add);
				h_add_pc_plus4: assert((rvfi_pc_wdata == rvfi_pc_rdata + 32'd4));
				h_spec_rvfi_insn_known: assert(no_x32(rvfi_insn));
				h_spec_rvfi_rs1_rdata_known: assert(no_x32(rvfi_rs1_rdata));
				h_spec_rvfi_rs2_rdata_known: assert(no_x32(rvfi_rs2_rdata));
				h_spec_rvfi_rd_wdata_known: assert(no_x32(rvfi_rd_wdata));
				h_spec_model_addrs_known: assert((no_x5(chk.spec_rs1_addr) && no_x5(chk.spec_rs2_addr) && no_x5(chk.spec_rd_addr)));
				h_spec_model_wdata_known: assert(no_x32(chk.spec_rd_wdata));
				// RVFI-level ISA semantics for ADD:
				// rd_wdata = rs1 + rs2 (x0 write suppressed by spec model).
				h_spec_semantic_rd_wdata: assert(chk.spec_rd_wdata == ((chk.spec_rd_addr === 5'd0) ? 32'd0 : (rvfi_rs1_rdata + rvfi_rs2_rdata)));
				h_semantic_rd_wdata: assert(rvfi_rd_wdata == ((chk.spec_rd_addr === 5'd0) ? 32'd0 : (rvfi_rs1_rdata + rvfi_rs2_rdata)));
				h_add_spec_rs1_matches_insn: assert(chk.spec_rs1_addr == rvfi_rs1);
				h_add_spec_rs2_matches_insn: assert(chk.spec_rs2_addr == rvfi_rs2);
				h_add_spec_rd_matches_insn: assert(chk.spec_rd_addr == rvfi_rd);
				// Address plumbing: RVFI architectural register indices must match the ISA model.
				h_spec_rvfi_rs_addrs_match: assert((rvfi_rs1_addr == chk.spec_rs1_addr && rvfi_rs2_addr == chk.spec_rs2_addr));
				h_spec_rvfi_rd_addr_match: assert((rvfi_rd_addr == chk.spec_rd_addr));
			end
		end
	end

	// Combinational strengthening for the exact checker guard.
	// Motivation (from hard traces): `check` can rise in a state where RVFI fields are still X,
	// and the checker evaluates combinationally. Mirror the checker's guard so these X-heavy
	// states are blocked.
	always @* begin
		if (!reset && check && (chk.spec_valid === 1'b1) && (chk.spec_trap === 1'b0)) begin
			h_comb_spec_implies_rvfi_valid: assert(rvfi_valid[0] === 1'b1);
			h_comb_rvfi_insn_known: assert(no_x32(rvfi_insn));
			h_comb_rvfi_rs1_known: assert(no_x32(rvfi_rs1_rdata));
			h_comb_rvfi_rs2_known: assert(no_x32(rvfi_rs2_rdata));
			h_comb_rvfi_rd_addr_known: assert(no_x5(rvfi_rd_addr));
			h_comb_rvfi_rd_wdata_known: assert(no_x32(rvfi_rd_wdata));
			// RVFI architectural writeback to x0 must be zero.
			if (rvfi_rd_addr === 5'd0) begin
				h_comb_x0_write_suppressed: assert(rvfi_rd_wdata == 32'd0);
			end
		end
	end
	/// Helper Assertion End
endmodule
