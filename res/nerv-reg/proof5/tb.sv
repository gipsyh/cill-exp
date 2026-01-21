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
	initial h_past_valid = 0;

	always @(posedge clock) begin
		if (reset) begin
			h_past_valid <= 0;
		end else begin
			h_past_valid <= 1;
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			if (checker_inst.register_written && checker_inst.register_index == 0) begin
				h_x0_shadow_zero: assert(checker_inst.register_shadow == 0);
			end
			if (wrapper.uut.rvfi_valid) begin
				if (wrapper.uut.rvfi_rs1_addr == 0)
					h_rvfi_rs1_x0_zero: assert(wrapper.uut.rvfi_rs1_rdata == 0);
				if (wrapper.uut.rvfi_rs2_addr == 0)
					h_rvfi_rs2_x0_zero: assert(wrapper.uut.rvfi_rs2_rdata == 0);
			end
		end
	end

	always @(posedge clock) begin
		if (!reset && h_past_valid && wrapper.uut.rvfi_valid) begin
			case (wrapper.uut.rvfi_rs1_addr)
				5'd0: ;
				5'd1:  h_rvfi_rs1_matches_regfile_past_1:  assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[1]));
				5'd2:  h_rvfi_rs1_matches_regfile_past_2:  assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[2]));
				5'd3:  h_rvfi_rs1_matches_regfile_past_3:  assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[3]));
				5'd4:  h_rvfi_rs1_matches_regfile_past_4:  assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[4]));
				5'd5:  h_rvfi_rs1_matches_regfile_past_5:  assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[5]));
				5'd6:  h_rvfi_rs1_matches_regfile_past_6:  assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[6]));
				5'd7:  h_rvfi_rs1_matches_regfile_past_7:  assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[7]));
				5'd8:  h_rvfi_rs1_matches_regfile_past_8:  assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[8]));
				5'd9:  h_rvfi_rs1_matches_regfile_past_9:  assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[9]));
				5'd10: h_rvfi_rs1_matches_regfile_past_10: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[10]));
				5'd11: h_rvfi_rs1_matches_regfile_past_11: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[11]));
				5'd12: h_rvfi_rs1_matches_regfile_past_12: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[12]));
				5'd13: h_rvfi_rs1_matches_regfile_past_13: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[13]));
				5'd14: h_rvfi_rs1_matches_regfile_past_14: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[14]));
				5'd15: h_rvfi_rs1_matches_regfile_past_15: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[15]));
				5'd16: h_rvfi_rs1_matches_regfile_past_16: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[16]));
				5'd17: h_rvfi_rs1_matches_regfile_past_17: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[17]));
				5'd18: h_rvfi_rs1_matches_regfile_past_18: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[18]));
				5'd19: h_rvfi_rs1_matches_regfile_past_19: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[19]));
				5'd20: h_rvfi_rs1_matches_regfile_past_20: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[20]));
				5'd21: h_rvfi_rs1_matches_regfile_past_21: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[21]));
				5'd22: h_rvfi_rs1_matches_regfile_past_22: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[22]));
				5'd23: h_rvfi_rs1_matches_regfile_past_23: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[23]));
				5'd24: h_rvfi_rs1_matches_regfile_past_24: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[24]));
				5'd25: h_rvfi_rs1_matches_regfile_past_25: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[25]));
				5'd26: h_rvfi_rs1_matches_regfile_past_26: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[26]));
				5'd27: h_rvfi_rs1_matches_regfile_past_27: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[27]));
				5'd28: h_rvfi_rs1_matches_regfile_past_28: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[28]));
				5'd29: h_rvfi_rs1_matches_regfile_past_29: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[29]));
				5'd30: h_rvfi_rs1_matches_regfile_past_30: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[30]));
				5'd31: h_rvfi_rs1_matches_regfile_past_31: assert(wrapper.uut.rvfi_rs1_rdata == $past(wrapper.uut.regfile[31]));
				default: ;
			endcase

			case (wrapper.uut.rvfi_rs2_addr)
				5'd0: ;
				5'd1:  h_rvfi_rs2_matches_regfile_past_1:  assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[1]));
				5'd2:  h_rvfi_rs2_matches_regfile_past_2:  assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[2]));
				5'd3:  h_rvfi_rs2_matches_regfile_past_3:  assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[3]));
				5'd4:  h_rvfi_rs2_matches_regfile_past_4:  assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[4]));
				5'd5:  h_rvfi_rs2_matches_regfile_past_5:  assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[5]));
				5'd6:  h_rvfi_rs2_matches_regfile_past_6:  assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[6]));
				5'd7:  h_rvfi_rs2_matches_regfile_past_7:  assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[7]));
				5'd8:  h_rvfi_rs2_matches_regfile_past_8:  assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[8]));
				5'd9:  h_rvfi_rs2_matches_regfile_past_9:  assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[9]));
				5'd10: h_rvfi_rs2_matches_regfile_past_10: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[10]));
				5'd11: h_rvfi_rs2_matches_regfile_past_11: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[11]));
				5'd12: h_rvfi_rs2_matches_regfile_past_12: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[12]));
				5'd13: h_rvfi_rs2_matches_regfile_past_13: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[13]));
				5'd14: h_rvfi_rs2_matches_regfile_past_14: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[14]));
				5'd15: h_rvfi_rs2_matches_regfile_past_15: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[15]));
				5'd16: h_rvfi_rs2_matches_regfile_past_16: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[16]));
				5'd17: h_rvfi_rs2_matches_regfile_past_17: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[17]));
				5'd18: h_rvfi_rs2_matches_regfile_past_18: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[18]));
				5'd19: h_rvfi_rs2_matches_regfile_past_19: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[19]));
				5'd20: h_rvfi_rs2_matches_regfile_past_20: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[20]));
				5'd21: h_rvfi_rs2_matches_regfile_past_21: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[21]));
				5'd22: h_rvfi_rs2_matches_regfile_past_22: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[22]));
				5'd23: h_rvfi_rs2_matches_regfile_past_23: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[23]));
				5'd24: h_rvfi_rs2_matches_regfile_past_24: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[24]));
				5'd25: h_rvfi_rs2_matches_regfile_past_25: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[25]));
				5'd26: h_rvfi_rs2_matches_regfile_past_26: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[26]));
				5'd27: h_rvfi_rs2_matches_regfile_past_27: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[27]));
				5'd28: h_rvfi_rs2_matches_regfile_past_28: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[28]));
				5'd29: h_rvfi_rs2_matches_regfile_past_29: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[29]));
				5'd30: h_rvfi_rs2_matches_regfile_past_30: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[30]));
				5'd31: h_rvfi_rs2_matches_regfile_past_31: assert(wrapper.uut.rvfi_rs2_rdata == $past(wrapper.uut.regfile[31]));
				default: ;
			endcase
		end
	end

	always @(posedge clock) begin
		if (!reset && h_past_valid) begin
			if (checker_inst.register_written && checker_inst.register_index != 0) begin
				h_shadow_matches_regfile_past: assert(checker_inst.register_shadow == $past(wrapper.uut.regfile[checker_inst.register_index]));
			end
		end
	end

/// Helper Assertion End
endmodule
