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
	reg h_past_valid;
	reg [1:0] h_hist;
	always @(posedge clock) begin
		if (reset) begin
			h_past_valid <= 1'b0;
			h_hist <= 2'b00;
		end else begin
			h_past_valid <= 1'b1;
			h_hist <= {h_hist[0], 1'b1};
		end
	end

	// RVFI signals are registered snapshots of internal signals.
	// Make this explicit to eliminate spurious induction predecessors.
	always @(posedge clock) begin
		if (!reset && h_past_valid) begin
			h_rvfi_valid_def: assert(wrapper.uut.rvfi_valid == $past(wrapper.uut.next_rvfi_valid));

			if (checker_inst.register_written && checker_inst.register_index != 0) begin
				// The checker samples RVFI (registered) writeback information, so its shadow is
				// naturally one-cycle behind the DUT's architectural regfile.
				h_shadow_lags_regfile: assert(checker_inst.register_shadow == $past(wrapper.uut.regfile[checker_inst.register_index]));
			end

			if ($past(wrapper.uut.cycle_insn || wrapper.uut.cycle_trap)) begin
				h_rvfi_order_incr: assert(wrapper.uut.rvfi_order == $past(wrapper.uut.rvfi_order) + 1);
				h_rvfi_rs1_capture: assert(wrapper.uut.rvfi_rs1_addr == $past(wrapper.uut.insn_rs1));
				h_rvfi_rs2_capture: assert(wrapper.uut.rvfi_rs2_addr == $past(wrapper.uut.insn_rs2));
				h_rvfi_rs1_rdata_capture: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.rs1_value));
				h_rvfi_rs2_rdata_capture: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.rs2_value));
			end

			// When RVFI is valid, the rs1/rs2 snapshot must match the architectural regfile
			// value at the time the snapshot was taken. For normal instructions, RVFI becomes
			// valid 1 cycle after capture; for mem transactions, it becomes valid 2 cycles after.
			if (wrapper.uut.rvfi_valid) begin
				reg [31:0] h_exp_rs1;
				reg [31:0] h_exp_rs2;

				if (h_hist[1] && $past(wrapper.uut.cycle_late_wr)) begin
					unique case (wrapper.uut.rvfi_rs1_addr)
						5'd0:  h_exp_rs1 = 32'd0;
						5'd1:  h_exp_rs1 = $past(wrapper.uut.regfile[1], 2);
						5'd2:  h_exp_rs1 = $past(wrapper.uut.regfile[2], 2);
						5'd3:  h_exp_rs1 = $past(wrapper.uut.regfile[3], 2);
						5'd4:  h_exp_rs1 = $past(wrapper.uut.regfile[4], 2);
						5'd5:  h_exp_rs1 = $past(wrapper.uut.regfile[5], 2);
						5'd6:  h_exp_rs1 = $past(wrapper.uut.regfile[6], 2);
						5'd7:  h_exp_rs1 = $past(wrapper.uut.regfile[7], 2);
						5'd8:  h_exp_rs1 = $past(wrapper.uut.regfile[8], 2);
						5'd9:  h_exp_rs1 = $past(wrapper.uut.regfile[9], 2);
						5'd10: h_exp_rs1 = $past(wrapper.uut.regfile[10], 2);
						5'd11: h_exp_rs1 = $past(wrapper.uut.regfile[11], 2);
						5'd12: h_exp_rs1 = $past(wrapper.uut.regfile[12], 2);
						5'd13: h_exp_rs1 = $past(wrapper.uut.regfile[13], 2);
						5'd14: h_exp_rs1 = $past(wrapper.uut.regfile[14], 2);
						5'd15: h_exp_rs1 = $past(wrapper.uut.regfile[15], 2);
						5'd16: h_exp_rs1 = $past(wrapper.uut.regfile[16], 2);
						5'd17: h_exp_rs1 = $past(wrapper.uut.regfile[17], 2);
						5'd18: h_exp_rs1 = $past(wrapper.uut.regfile[18], 2);
						5'd19: h_exp_rs1 = $past(wrapper.uut.regfile[19], 2);
						5'd20: h_exp_rs1 = $past(wrapper.uut.regfile[20], 2);
						5'd21: h_exp_rs1 = $past(wrapper.uut.regfile[21], 2);
						5'd22: h_exp_rs1 = $past(wrapper.uut.regfile[22], 2);
						5'd23: h_exp_rs1 = $past(wrapper.uut.regfile[23], 2);
						5'd24: h_exp_rs1 = $past(wrapper.uut.regfile[24], 2);
						5'd25: h_exp_rs1 = $past(wrapper.uut.regfile[25], 2);
						5'd26: h_exp_rs1 = $past(wrapper.uut.regfile[26], 2);
						5'd27: h_exp_rs1 = $past(wrapper.uut.regfile[27], 2);
						5'd28: h_exp_rs1 = $past(wrapper.uut.regfile[28], 2);
						5'd29: h_exp_rs1 = $past(wrapper.uut.regfile[29], 2);
						5'd30: h_exp_rs1 = $past(wrapper.uut.regfile[30], 2);
						5'd31: h_exp_rs1 = $past(wrapper.uut.regfile[31], 2);
					endcase

					unique case (wrapper.uut.rvfi_rs2_addr)
						5'd0:  h_exp_rs2 = 32'd0;
						5'd1:  h_exp_rs2 = $past(wrapper.uut.regfile[1], 2);
						5'd2:  h_exp_rs2 = $past(wrapper.uut.regfile[2], 2);
						5'd3:  h_exp_rs2 = $past(wrapper.uut.regfile[3], 2);
						5'd4:  h_exp_rs2 = $past(wrapper.uut.regfile[4], 2);
						5'd5:  h_exp_rs2 = $past(wrapper.uut.regfile[5], 2);
						5'd6:  h_exp_rs2 = $past(wrapper.uut.regfile[6], 2);
						5'd7:  h_exp_rs2 = $past(wrapper.uut.regfile[7], 2);
						5'd8:  h_exp_rs2 = $past(wrapper.uut.regfile[8], 2);
						5'd9:  h_exp_rs2 = $past(wrapper.uut.regfile[9], 2);
						5'd10: h_exp_rs2 = $past(wrapper.uut.regfile[10], 2);
						5'd11: h_exp_rs2 = $past(wrapper.uut.regfile[11], 2);
						5'd12: h_exp_rs2 = $past(wrapper.uut.regfile[12], 2);
						5'd13: h_exp_rs2 = $past(wrapper.uut.regfile[13], 2);
						5'd14: h_exp_rs2 = $past(wrapper.uut.regfile[14], 2);
						5'd15: h_exp_rs2 = $past(wrapper.uut.regfile[15], 2);
						5'd16: h_exp_rs2 = $past(wrapper.uut.regfile[16], 2);
						5'd17: h_exp_rs2 = $past(wrapper.uut.regfile[17], 2);
						5'd18: h_exp_rs2 = $past(wrapper.uut.regfile[18], 2);
						5'd19: h_exp_rs2 = $past(wrapper.uut.regfile[19], 2);
						5'd20: h_exp_rs2 = $past(wrapper.uut.regfile[20], 2);
						5'd21: h_exp_rs2 = $past(wrapper.uut.regfile[21], 2);
						5'd22: h_exp_rs2 = $past(wrapper.uut.regfile[22], 2);
						5'd23: h_exp_rs2 = $past(wrapper.uut.regfile[23], 2);
						5'd24: h_exp_rs2 = $past(wrapper.uut.regfile[24], 2);
						5'd25: h_exp_rs2 = $past(wrapper.uut.regfile[25], 2);
						5'd26: h_exp_rs2 = $past(wrapper.uut.regfile[26], 2);
						5'd27: h_exp_rs2 = $past(wrapper.uut.regfile[27], 2);
						5'd28: h_exp_rs2 = $past(wrapper.uut.regfile[28], 2);
						5'd29: h_exp_rs2 = $past(wrapper.uut.regfile[29], 2);
						5'd30: h_exp_rs2 = $past(wrapper.uut.regfile[30], 2);
						5'd31: h_exp_rs2 = $past(wrapper.uut.regfile[31], 2);
					endcase

					h_rvfi_rs1_rdata_matches_regfile_2cy: assert(wrapper.uut.rvfi_rs1_rdata == h_exp_rs1);
					h_rvfi_rs2_rdata_matches_regfile_2cy: assert(wrapper.uut.rvfi_rs2_rdata == h_exp_rs2);
				end

				if (h_hist[0] && !$past(wrapper.uut.cycle_late_wr)) begin
					unique case (wrapper.uut.rvfi_rs1_addr)
						5'd0:  h_exp_rs1 = 32'd0;
						5'd1:  h_exp_rs1 = $past(wrapper.uut.regfile[1], 1);
						5'd2:  h_exp_rs1 = $past(wrapper.uut.regfile[2], 1);
						5'd3:  h_exp_rs1 = $past(wrapper.uut.regfile[3], 1);
						5'd4:  h_exp_rs1 = $past(wrapper.uut.regfile[4], 1);
						5'd5:  h_exp_rs1 = $past(wrapper.uut.regfile[5], 1);
						5'd6:  h_exp_rs1 = $past(wrapper.uut.regfile[6], 1);
						5'd7:  h_exp_rs1 = $past(wrapper.uut.regfile[7], 1);
						5'd8:  h_exp_rs1 = $past(wrapper.uut.regfile[8], 1);
						5'd9:  h_exp_rs1 = $past(wrapper.uut.regfile[9], 1);
						5'd10: h_exp_rs1 = $past(wrapper.uut.regfile[10], 1);
						5'd11: h_exp_rs1 = $past(wrapper.uut.regfile[11], 1);
						5'd12: h_exp_rs1 = $past(wrapper.uut.regfile[12], 1);
						5'd13: h_exp_rs1 = $past(wrapper.uut.regfile[13], 1);
						5'd14: h_exp_rs1 = $past(wrapper.uut.regfile[14], 1);
						5'd15: h_exp_rs1 = $past(wrapper.uut.regfile[15], 1);
						5'd16: h_exp_rs1 = $past(wrapper.uut.regfile[16], 1);
						5'd17: h_exp_rs1 = $past(wrapper.uut.regfile[17], 1);
						5'd18: h_exp_rs1 = $past(wrapper.uut.regfile[18], 1);
						5'd19: h_exp_rs1 = $past(wrapper.uut.regfile[19], 1);
						5'd20: h_exp_rs1 = $past(wrapper.uut.regfile[20], 1);
						5'd21: h_exp_rs1 = $past(wrapper.uut.regfile[21], 1);
						5'd22: h_exp_rs1 = $past(wrapper.uut.regfile[22], 1);
						5'd23: h_exp_rs1 = $past(wrapper.uut.regfile[23], 1);
						5'd24: h_exp_rs1 = $past(wrapper.uut.regfile[24], 1);
						5'd25: h_exp_rs1 = $past(wrapper.uut.regfile[25], 1);
						5'd26: h_exp_rs1 = $past(wrapper.uut.regfile[26], 1);
						5'd27: h_exp_rs1 = $past(wrapper.uut.regfile[27], 1);
						5'd28: h_exp_rs1 = $past(wrapper.uut.regfile[28], 1);
						5'd29: h_exp_rs1 = $past(wrapper.uut.regfile[29], 1);
						5'd30: h_exp_rs1 = $past(wrapper.uut.regfile[30], 1);
						5'd31: h_exp_rs1 = $past(wrapper.uut.regfile[31], 1);
					endcase

					unique case (wrapper.uut.rvfi_rs2_addr)
						5'd0:  h_exp_rs2 = 32'd0;
						5'd1:  h_exp_rs2 = $past(wrapper.uut.regfile[1], 1);
						5'd2:  h_exp_rs2 = $past(wrapper.uut.regfile[2], 1);
						5'd3:  h_exp_rs2 = $past(wrapper.uut.regfile[3], 1);
						5'd4:  h_exp_rs2 = $past(wrapper.uut.regfile[4], 1);
						5'd5:  h_exp_rs2 = $past(wrapper.uut.regfile[5], 1);
						5'd6:  h_exp_rs2 = $past(wrapper.uut.regfile[6], 1);
						5'd7:  h_exp_rs2 = $past(wrapper.uut.regfile[7], 1);
						5'd8:  h_exp_rs2 = $past(wrapper.uut.regfile[8], 1);
						5'd9:  h_exp_rs2 = $past(wrapper.uut.regfile[9], 1);
						5'd10: h_exp_rs2 = $past(wrapper.uut.regfile[10], 1);
						5'd11: h_exp_rs2 = $past(wrapper.uut.regfile[11], 1);
						5'd12: h_exp_rs2 = $past(wrapper.uut.regfile[12], 1);
						5'd13: h_exp_rs2 = $past(wrapper.uut.regfile[13], 1);
						5'd14: h_exp_rs2 = $past(wrapper.uut.regfile[14], 1);
						5'd15: h_exp_rs2 = $past(wrapper.uut.regfile[15], 1);
						5'd16: h_exp_rs2 = $past(wrapper.uut.regfile[16], 1);
						5'd17: h_exp_rs2 = $past(wrapper.uut.regfile[17], 1);
						5'd18: h_exp_rs2 = $past(wrapper.uut.regfile[18], 1);
						5'd19: h_exp_rs2 = $past(wrapper.uut.regfile[19], 1);
						5'd20: h_exp_rs2 = $past(wrapper.uut.regfile[20], 1);
						5'd21: h_exp_rs2 = $past(wrapper.uut.regfile[21], 1);
						5'd22: h_exp_rs2 = $past(wrapper.uut.regfile[22], 1);
						5'd23: h_exp_rs2 = $past(wrapper.uut.regfile[23], 1);
						5'd24: h_exp_rs2 = $past(wrapper.uut.regfile[24], 1);
						5'd25: h_exp_rs2 = $past(wrapper.uut.regfile[25], 1);
						5'd26: h_exp_rs2 = $past(wrapper.uut.regfile[26], 1);
						5'd27: h_exp_rs2 = $past(wrapper.uut.regfile[27], 1);
						5'd28: h_exp_rs2 = $past(wrapper.uut.regfile[28], 1);
						5'd29: h_exp_rs2 = $past(wrapper.uut.regfile[29], 1);
						5'd30: h_exp_rs2 = $past(wrapper.uut.regfile[30], 1);
						5'd31: h_exp_rs2 = $past(wrapper.uut.regfile[31], 1);
					endcase

					h_rvfi_rs1_rdata_matches_regfile_1cy: assert(wrapper.uut.rvfi_rs1_rdata == h_exp_rs1);
					h_rvfi_rs2_rdata_matches_regfile_1cy: assert(wrapper.uut.rvfi_rs2_rdata == h_exp_rs2);
				end
			end

			if ($past(wrapper.uut.cycle_insn || wrapper.uut.cycle_late_wr || wrapper.uut.cycle_trap)) begin
				h_rvfi_rd_addr_capture: assert(wrapper.uut.rvfi_rd_addr == $past(wrapper.uut.next_wr ? wrapper.uut.wr_rd : 5'd0));
				h_rvfi_rd_wdata_capture: assert(wrapper.uut.rvfi_rd_wdata == $past((wrapper.uut.next_wr && (wrapper.uut.wr_rd != 0)) ? wrapper.uut.next_rd : 32'd0));
			end
		end
	end

/// Helper Assertion End
endmodule
