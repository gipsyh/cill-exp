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
	reg h_written;
	reg [`RISCV_FORMAL_XLEN-1:0] h_shadow;

	always @(posedge clock) begin
		if (reset) begin
			h_written <= 1'b0;
			h_shadow <= {`RISCV_FORMAL_XLEN{1'b0}};
		end else begin
			if (rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] &&
					!rvfi_trap[`RISCV_FORMAL_CHANNEL_IDX] &&
					rvfi_rd_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5] == checker_inst.register_index) begin
				h_written <= 1'b1;
				h_shadow <= rvfi_rd_wdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
			end
		end
	end

	always @(posedge clock) begin
		if (!reset) begin
			h_checker_written_equiv: assert(checker_inst.register_written == h_written);
			if (h_written) begin
				h_checker_shadow_consistent: assert(checker_inst.register_shadow == h_shadow);
			end
			if ($past(!reset) && checker_inst.register_written) begin
				reg [`RISCV_FORMAL_XLEN-1:0] h_reg_expect;
				case (checker_inst.register_index)
					5'd0: h_reg_expect = {`RISCV_FORMAL_XLEN{1'b0}};
					5'd1: h_reg_expect = $past(wrapper.uut.regfile[1]);
					5'd2: h_reg_expect = $past(wrapper.uut.regfile[2]);
					5'd3: h_reg_expect = $past(wrapper.uut.regfile[3]);
					5'd4: h_reg_expect = $past(wrapper.uut.regfile[4]);
					5'd5: h_reg_expect = $past(wrapper.uut.regfile[5]);
					5'd6: h_reg_expect = $past(wrapper.uut.regfile[6]);
					5'd7: h_reg_expect = $past(wrapper.uut.regfile[7]);
					5'd8: h_reg_expect = $past(wrapper.uut.regfile[8]);
					5'd9: h_reg_expect = $past(wrapper.uut.regfile[9]);
					5'd10: h_reg_expect = $past(wrapper.uut.regfile[10]);
					5'd11: h_reg_expect = $past(wrapper.uut.regfile[11]);
					5'd12: h_reg_expect = $past(wrapper.uut.regfile[12]);
					5'd13: h_reg_expect = $past(wrapper.uut.regfile[13]);
					5'd14: h_reg_expect = $past(wrapper.uut.regfile[14]);
					5'd15: h_reg_expect = $past(wrapper.uut.regfile[15]);
					5'd16: h_reg_expect = $past(wrapper.uut.regfile[16]);
					5'd17: h_reg_expect = $past(wrapper.uut.regfile[17]);
					5'd18: h_reg_expect = $past(wrapper.uut.regfile[18]);
					5'd19: h_reg_expect = $past(wrapper.uut.regfile[19]);
					5'd20: h_reg_expect = $past(wrapper.uut.regfile[20]);
					5'd21: h_reg_expect = $past(wrapper.uut.regfile[21]);
					5'd22: h_reg_expect = $past(wrapper.uut.regfile[22]);
					5'd23: h_reg_expect = $past(wrapper.uut.regfile[23]);
					5'd24: h_reg_expect = $past(wrapper.uut.regfile[24]);
					5'd25: h_reg_expect = $past(wrapper.uut.regfile[25]);
					5'd26: h_reg_expect = $past(wrapper.uut.regfile[26]);
					5'd27: h_reg_expect = $past(wrapper.uut.regfile[27]);
					5'd28: h_reg_expect = $past(wrapper.uut.regfile[28]);
					5'd29: h_reg_expect = $past(wrapper.uut.regfile[29]);
					5'd30: h_reg_expect = $past(wrapper.uut.regfile[30]);
					default: h_reg_expect = $past(wrapper.uut.regfile[31]);
				endcase
				h_shadow_lags_regfile: assert(checker_inst.register_shadow == h_reg_expect);
			end
			if ($past(!reset) && rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX]) begin
				reg [`RISCV_FORMAL_XLEN-1:0] h_rs1_expect;
				reg [`RISCV_FORMAL_XLEN-1:0] h_rs2_expect;
				case (rvfi_rs1_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5])
					5'd0: h_rs1_expect = {`RISCV_FORMAL_XLEN{1'b0}};
					5'd1: h_rs1_expect = $past(wrapper.uut.regfile[1]);
					5'd2: h_rs1_expect = $past(wrapper.uut.regfile[2]);
					5'd3: h_rs1_expect = $past(wrapper.uut.regfile[3]);
					5'd4: h_rs1_expect = $past(wrapper.uut.regfile[4]);
					5'd5: h_rs1_expect = $past(wrapper.uut.regfile[5]);
					5'd6: h_rs1_expect = $past(wrapper.uut.regfile[6]);
					5'd7: h_rs1_expect = $past(wrapper.uut.regfile[7]);
					5'd8: h_rs1_expect = $past(wrapper.uut.regfile[8]);
					5'd9: h_rs1_expect = $past(wrapper.uut.regfile[9]);
					5'd10: h_rs1_expect = $past(wrapper.uut.regfile[10]);
					5'd11: h_rs1_expect = $past(wrapper.uut.regfile[11]);
					5'd12: h_rs1_expect = $past(wrapper.uut.regfile[12]);
					5'd13: h_rs1_expect = $past(wrapper.uut.regfile[13]);
					5'd14: h_rs1_expect = $past(wrapper.uut.regfile[14]);
					5'd15: h_rs1_expect = $past(wrapper.uut.regfile[15]);
					5'd16: h_rs1_expect = $past(wrapper.uut.regfile[16]);
					5'd17: h_rs1_expect = $past(wrapper.uut.regfile[17]);
					5'd18: h_rs1_expect = $past(wrapper.uut.regfile[18]);
					5'd19: h_rs1_expect = $past(wrapper.uut.regfile[19]);
					5'd20: h_rs1_expect = $past(wrapper.uut.regfile[20]);
					5'd21: h_rs1_expect = $past(wrapper.uut.regfile[21]);
					5'd22: h_rs1_expect = $past(wrapper.uut.regfile[22]);
					5'd23: h_rs1_expect = $past(wrapper.uut.regfile[23]);
					5'd24: h_rs1_expect = $past(wrapper.uut.regfile[24]);
					5'd25: h_rs1_expect = $past(wrapper.uut.regfile[25]);
					5'd26: h_rs1_expect = $past(wrapper.uut.regfile[26]);
					5'd27: h_rs1_expect = $past(wrapper.uut.regfile[27]);
					5'd28: h_rs1_expect = $past(wrapper.uut.regfile[28]);
					5'd29: h_rs1_expect = $past(wrapper.uut.regfile[29]);
					5'd30: h_rs1_expect = $past(wrapper.uut.regfile[30]);
					default: h_rs1_expect = $past(wrapper.uut.regfile[31]);
				endcase
				case (rvfi_rs2_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5])
					5'd0: h_rs2_expect = {`RISCV_FORMAL_XLEN{1'b0}};
					5'd1: h_rs2_expect = $past(wrapper.uut.regfile[1]);
					5'd2: h_rs2_expect = $past(wrapper.uut.regfile[2]);
					5'd3: h_rs2_expect = $past(wrapper.uut.regfile[3]);
					5'd4: h_rs2_expect = $past(wrapper.uut.regfile[4]);
					5'd5: h_rs2_expect = $past(wrapper.uut.regfile[5]);
					5'd6: h_rs2_expect = $past(wrapper.uut.regfile[6]);
					5'd7: h_rs2_expect = $past(wrapper.uut.regfile[7]);
					5'd8: h_rs2_expect = $past(wrapper.uut.regfile[8]);
					5'd9: h_rs2_expect = $past(wrapper.uut.regfile[9]);
					5'd10: h_rs2_expect = $past(wrapper.uut.regfile[10]);
					5'd11: h_rs2_expect = $past(wrapper.uut.regfile[11]);
					5'd12: h_rs2_expect = $past(wrapper.uut.regfile[12]);
					5'd13: h_rs2_expect = $past(wrapper.uut.regfile[13]);
					5'd14: h_rs2_expect = $past(wrapper.uut.regfile[14]);
					5'd15: h_rs2_expect = $past(wrapper.uut.regfile[15]);
					5'd16: h_rs2_expect = $past(wrapper.uut.regfile[16]);
					5'd17: h_rs2_expect = $past(wrapper.uut.regfile[17]);
					5'd18: h_rs2_expect = $past(wrapper.uut.regfile[18]);
					5'd19: h_rs2_expect = $past(wrapper.uut.regfile[19]);
					5'd20: h_rs2_expect = $past(wrapper.uut.regfile[20]);
					5'd21: h_rs2_expect = $past(wrapper.uut.regfile[21]);
					5'd22: h_rs2_expect = $past(wrapper.uut.regfile[22]);
					5'd23: h_rs2_expect = $past(wrapper.uut.regfile[23]);
					5'd24: h_rs2_expect = $past(wrapper.uut.regfile[24]);
					5'd25: h_rs2_expect = $past(wrapper.uut.regfile[25]);
					5'd26: h_rs2_expect = $past(wrapper.uut.regfile[26]);
					5'd27: h_rs2_expect = $past(wrapper.uut.regfile[27]);
					5'd28: h_rs2_expect = $past(wrapper.uut.regfile[28]);
					5'd29: h_rs2_expect = $past(wrapper.uut.regfile[29]);
					5'd30: h_rs2_expect = $past(wrapper.uut.regfile[30]);
					default: h_rs2_expect = $past(wrapper.uut.regfile[31]);
				endcase

				h_rvfi_rs1_matches_regfile_past: assert(rvfi_rs1_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN] == h_rs1_expect);
				h_rvfi_rs2_matches_regfile_past: assert(rvfi_rs2_rdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN] == h_rs2_expect);
			end
			if ($past(!reset) && rvfi_valid[`RISCV_FORMAL_CHANNEL_IDX] && rvfi_trap[`RISCV_FORMAL_CHANNEL_IDX]) begin
				h_trap_no_rd_write: assert(rvfi_rd_addr[`RISCV_FORMAL_CHANNEL_IDX*5 +: 5] == 0);
				h_trap_no_rd_wdata: assert(rvfi_rd_wdata[`RISCV_FORMAL_CHANNEL_IDX*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN] == 0);
			end
		end
	end

/// Helper Assertion End
endmodule
