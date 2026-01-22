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

	// Architectural GPR shadow model driven by RVFI.
	// Important: NERV does not necessarily reset GPR contents. Therefore we only
	// constrain reads for registers that have been written since reset.
	reg [`RISCV_FORMAL_XLEN-1:0] h_gpr [0:31];
	reg [31:0] h_gpr_written;

	// Once we've observed a write to a GPR (via RVFI), our shadow must match the
	// DUT regfile for that GPR forever after. This blocks unreachable induction
	// states where the helper shadow is inconsistent.
	genvar h_g;
	generate
		for (h_g = 1; h_g < 32; h_g = h_g + 1) begin : h_gpr_inv
			always @(posedge clock) begin
				if (!reset) begin
					if (h_gpr_written[h_g]) begin
						assert(h_gpr[h_g] == wrapper.uut.regfile[h_g]);
					end
				end
			end
		end
	endgenerate

	// Use DUT internal writeback intent (synchronous with regfile update).
	wire h_uut_next_wr = wrapper.uut.next_wr;
	wire [4:0] h_uut_wr_rd = wrapper.uut.wr_rd;
	wire [`RISCV_FORMAL_XLEN-1:0] h_uut_next_rd = wrapper.uut.next_rd;

	// RVFI timing note:
	// - The checker samples RVFI signals one cycle delayed (due to NBA updates).
	// - Snapshot the DUT regfile state from the prior cycle so we can relate
	//   `rvfi_*_rdata` to the architectural state used to compute it.
	reg [31:0] h_regfile_q [0:31];
	integer h_j;

	// RVFI signals as observed by the checker (previous-cycle values from the DUT's RVFI flops).
	wire h_c_rvfi_valid = rvfi_valid[0];
	wire h_c_rvfi_trap  = rvfi_trap[0];
	wire [4:0] h_c_rs1_addr = rvfi_rs1_addr[0*5 +: 5];
	wire [4:0] h_c_rs2_addr = rvfi_rs2_addr[0*5 +: 5];
	wire [`RISCV_FORMAL_XLEN-1:0] h_c_rs1_rdata = rvfi_rs1_rdata[0*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
	wire [`RISCV_FORMAL_XLEN-1:0] h_c_rs2_rdata = rvfi_rs2_rdata[0*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
	wire [4:0] h_c_rd_addr = rvfi_rd_addr[0*5 +: 5];
	wire [`RISCV_FORMAL_XLEN-1:0] h_c_rd_wdata = rvfi_rd_wdata[0*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];

	always @(posedge clock) begin
		if (!reset) begin
			// Snapshot must always reflect the prior-cycle regfile values.
			for (h_j = 0; h_j < 32; h_j = h_j + 1)
				assert(h_regfile_q[h_j] == $past(wrapper.uut.regfile[h_j]));

			if (h_c_rvfi_valid) begin
				// The rvfi_reg_check shadow is meant to represent the architectural value
				// of the tracked register at the beginning of the retired instruction.
				if (check && checker_inst.register_written) begin
					if (checker_inst.register_index == 0)
						h_checker_shadow_x0_again: assert(checker_inst.register_shadow == '0);
					else
						h_checker_shadow_match: assert(checker_inst.register_shadow == h_regfile_q[checker_inst.register_index]);
				end

				// Source reads match the architectural regfile state at the beginning of
				// the retired instruction.
				if (h_c_rs1_addr == 0)
					h_rvfi_rs1_x0: assert(h_c_rs1_rdata == '0);
				else
					h_rvfi_rs1_match: assert(h_c_rs1_rdata == h_regfile_q[h_c_rs1_addr]);

				if (h_c_rs2_addr == 0)
					h_rvfi_rs2_x0: assert(h_c_rs2_rdata == '0);
				else
					h_rvfi_rs2_match: assert(h_c_rs2_rdata == h_regfile_q[h_c_rs2_addr]);

				// For non-trapping instructions with rd!=0, the committed regfile value
				// equals RVFI's rd_wdata.
				if (!h_c_rvfi_trap && (h_c_rd_addr != 0)) begin
					h_rvfi_rd_commit: assert(wrapper.uut.regfile[h_c_rd_addr] == h_c_rd_wdata);
				end
			end
		end

		// Update snapshot for the next cycle (including during reset).
		for (h_j = 0; h_j < 32; h_j = h_j + 1)
			h_regfile_q[h_j] <= wrapper.uut.regfile[h_j];
	end

	// If a GPR changes value, RVFI must report a matching committed write.
	genvar h_w;
	generate
		for (h_w = 1; h_w < 32; h_w = h_w + 1) begin : h_regfile_writeback
			always @(posedge clock) begin
				if (!reset) begin
					if (wrapper.uut.regfile[h_w] != h_regfile_q[h_w]) begin
						assert(h_c_rvfi_valid);
						assert(!h_c_rvfi_trap);
						assert(h_c_rd_addr == h_w[4:0]);
						assert(h_c_rd_wdata == wrapper.uut.regfile[h_w]);
					end
				end
			end
		end
	endgenerate

	always @(posedge clock) begin
		if (reset) begin
			h_gpr_written <= '0;
			h_gpr[0] <= '0;
		end else begin
			// x0 is always 0.
			h_gpr[0] <= '0;
			h_x0_const: assert(h_gpr[0] == '0);

			// If the rvfi_reg_check instance is tracking x0, its shadow must be 0.
			// (In NERV's RVFI, rd_wdata is forced 0 when rd_addr==0.)
			if (checker_inst.register_written && (checker_inst.register_index == 0)) begin
				h_checker_x0_shadow: assert(checker_inst.register_shadow == '0);
			end
			if (!reset && checker_inst.register_written && (checker_inst.register_index != 0)) begin
				h_checker_shadow_prev_regfile: assert(checker_inst.register_shadow == h_regfile_q[checker_inst.register_index]);
			end

			// Track architectural state for all written registers.
			if (h_uut_next_wr && (h_uut_wr_rd != 0)) begin
				h_gpr[h_uut_wr_rd] <= h_uut_next_rd;
				h_gpr_written[h_uut_wr_rd] <= 1'b1;
			end
		end
	end

/// Helper Assertion End
endmodule
