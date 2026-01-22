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

reg [31:0] h_rs1_regfile_prev;
reg [31:0] h_rs2_regfile_prev;
reg [31:0] h_shadow_regfile_prev;

// RVFI read-data must reflect regfile contents for the addressed register.
always @(posedge clock) begin
	if (!reset && $past(!reset) && rvfi_valid) begin
		case (rvfi_rs1_addr)
			5'd0:  h_rs1_regfile_prev = $past(wrapper.uut.regfile[0]);
			5'd1:  h_rs1_regfile_prev = $past(wrapper.uut.regfile[1]);
			5'd2:  h_rs1_regfile_prev = $past(wrapper.uut.regfile[2]);
			5'd3:  h_rs1_regfile_prev = $past(wrapper.uut.regfile[3]);
			5'd4:  h_rs1_regfile_prev = $past(wrapper.uut.regfile[4]);
			5'd5:  h_rs1_regfile_prev = $past(wrapper.uut.regfile[5]);
			5'd6:  h_rs1_regfile_prev = $past(wrapper.uut.regfile[6]);
			5'd7:  h_rs1_regfile_prev = $past(wrapper.uut.regfile[7]);
			5'd8:  h_rs1_regfile_prev = $past(wrapper.uut.regfile[8]);
			5'd9:  h_rs1_regfile_prev = $past(wrapper.uut.regfile[9]);
			5'd10: h_rs1_regfile_prev = $past(wrapper.uut.regfile[10]);
			5'd11: h_rs1_regfile_prev = $past(wrapper.uut.regfile[11]);
			5'd12: h_rs1_regfile_prev = $past(wrapper.uut.regfile[12]);
			5'd13: h_rs1_regfile_prev = $past(wrapper.uut.regfile[13]);
			5'd14: h_rs1_regfile_prev = $past(wrapper.uut.regfile[14]);
			5'd15: h_rs1_regfile_prev = $past(wrapper.uut.regfile[15]);
			5'd16: h_rs1_regfile_prev = $past(wrapper.uut.regfile[16]);
			5'd17: h_rs1_regfile_prev = $past(wrapper.uut.regfile[17]);
			5'd18: h_rs1_regfile_prev = $past(wrapper.uut.regfile[18]);
			5'd19: h_rs1_regfile_prev = $past(wrapper.uut.regfile[19]);
			5'd20: h_rs1_regfile_prev = $past(wrapper.uut.regfile[20]);
			5'd21: h_rs1_regfile_prev = $past(wrapper.uut.regfile[21]);
			5'd22: h_rs1_regfile_prev = $past(wrapper.uut.regfile[22]);
			5'd23: h_rs1_regfile_prev = $past(wrapper.uut.regfile[23]);
			5'd24: h_rs1_regfile_prev = $past(wrapper.uut.regfile[24]);
			5'd25: h_rs1_regfile_prev = $past(wrapper.uut.regfile[25]);
			5'd26: h_rs1_regfile_prev = $past(wrapper.uut.regfile[26]);
			5'd27: h_rs1_regfile_prev = $past(wrapper.uut.regfile[27]);
			5'd28: h_rs1_regfile_prev = $past(wrapper.uut.regfile[28]);
			5'd29: h_rs1_regfile_prev = $past(wrapper.uut.regfile[29]);
			5'd30: h_rs1_regfile_prev = $past(wrapper.uut.regfile[30]);
			5'd31: h_rs1_regfile_prev = $past(wrapper.uut.regfile[31]);
			default: h_rs1_regfile_prev = $past(wrapper.uut.regfile[0]);
		endcase

		case (rvfi_rs2_addr)
			5'd0:  h_rs2_regfile_prev = $past(wrapper.uut.regfile[0]);
			5'd1:  h_rs2_regfile_prev = $past(wrapper.uut.regfile[1]);
			5'd2:  h_rs2_regfile_prev = $past(wrapper.uut.regfile[2]);
			5'd3:  h_rs2_regfile_prev = $past(wrapper.uut.regfile[3]);
			5'd4:  h_rs2_regfile_prev = $past(wrapper.uut.regfile[4]);
			5'd5:  h_rs2_regfile_prev = $past(wrapper.uut.regfile[5]);
			5'd6:  h_rs2_regfile_prev = $past(wrapper.uut.regfile[6]);
			5'd7:  h_rs2_regfile_prev = $past(wrapper.uut.regfile[7]);
			5'd8:  h_rs2_regfile_prev = $past(wrapper.uut.regfile[8]);
			5'd9:  h_rs2_regfile_prev = $past(wrapper.uut.regfile[9]);
			5'd10: h_rs2_regfile_prev = $past(wrapper.uut.regfile[10]);
			5'd11: h_rs2_regfile_prev = $past(wrapper.uut.regfile[11]);
			5'd12: h_rs2_regfile_prev = $past(wrapper.uut.regfile[12]);
			5'd13: h_rs2_regfile_prev = $past(wrapper.uut.regfile[13]);
			5'd14: h_rs2_regfile_prev = $past(wrapper.uut.regfile[14]);
			5'd15: h_rs2_regfile_prev = $past(wrapper.uut.regfile[15]);
			5'd16: h_rs2_regfile_prev = $past(wrapper.uut.regfile[16]);
			5'd17: h_rs2_regfile_prev = $past(wrapper.uut.regfile[17]);
			5'd18: h_rs2_regfile_prev = $past(wrapper.uut.regfile[18]);
			5'd19: h_rs2_regfile_prev = $past(wrapper.uut.regfile[19]);
			5'd20: h_rs2_regfile_prev = $past(wrapper.uut.regfile[20]);
			5'd21: h_rs2_regfile_prev = $past(wrapper.uut.regfile[21]);
			5'd22: h_rs2_regfile_prev = $past(wrapper.uut.regfile[22]);
			5'd23: h_rs2_regfile_prev = $past(wrapper.uut.regfile[23]);
			5'd24: h_rs2_regfile_prev = $past(wrapper.uut.regfile[24]);
			5'd25: h_rs2_regfile_prev = $past(wrapper.uut.regfile[25]);
			5'd26: h_rs2_regfile_prev = $past(wrapper.uut.regfile[26]);
			5'd27: h_rs2_regfile_prev = $past(wrapper.uut.regfile[27]);
			5'd28: h_rs2_regfile_prev = $past(wrapper.uut.regfile[28]);
			5'd29: h_rs2_regfile_prev = $past(wrapper.uut.regfile[29]);
			5'd30: h_rs2_regfile_prev = $past(wrapper.uut.regfile[30]);
			5'd31: h_rs2_regfile_prev = $past(wrapper.uut.regfile[31]);
			default: h_rs2_regfile_prev = $past(wrapper.uut.regfile[0]);
		endcase

		if (rvfi_rs1_addr == 0)
			h_rs1_rdata_x0: assert(rvfi_rs1_rdata == 0);
		else
			h_rs1_rdata_regfile: assert(rvfi_rs1_rdata == h_rs1_regfile_prev);

		if (rvfi_rs2_addr == 0)
			h_rs2_rdata_x0: assert(rvfi_rs2_rdata == 0);
		else
			h_rs2_rdata_regfile: assert(rvfi_rs2_rdata == h_rs2_regfile_prev);
	end
end

// RVFI writeback data must match the regfile value after writeback (x0 writes return 0).
always @(posedge clock) begin
	if (!reset && rvfi_valid) begin
		if (rvfi_rd_addr == 0)
			h_rd_wdata_x0: assert(rvfi_rd_wdata == 0);
		else
			h_rd_wdata_regfile: assert(rvfi_rd_wdata == wrapper.uut.regfile[rvfi_rd_addr]);
	end
end

// Shadow register should correspond to the prior-cycle regfile value for the tracked index.
always @(posedge clock) begin
	if (!reset && $past(!reset) && checker_inst.register_written) begin
		case (checker_inst.register_index)
			5'd0:  h_shadow_regfile_prev = $past(wrapper.uut.regfile[0]);
			5'd1:  h_shadow_regfile_prev = $past(wrapper.uut.regfile[1]);
			5'd2:  h_shadow_regfile_prev = $past(wrapper.uut.regfile[2]);
			5'd3:  h_shadow_regfile_prev = $past(wrapper.uut.regfile[3]);
			5'd4:  h_shadow_regfile_prev = $past(wrapper.uut.regfile[4]);
			5'd5:  h_shadow_regfile_prev = $past(wrapper.uut.regfile[5]);
			5'd6:  h_shadow_regfile_prev = $past(wrapper.uut.regfile[6]);
			5'd7:  h_shadow_regfile_prev = $past(wrapper.uut.regfile[7]);
			5'd8:  h_shadow_regfile_prev = $past(wrapper.uut.regfile[8]);
			5'd9:  h_shadow_regfile_prev = $past(wrapper.uut.regfile[9]);
			5'd10: h_shadow_regfile_prev = $past(wrapper.uut.regfile[10]);
			5'd11: h_shadow_regfile_prev = $past(wrapper.uut.regfile[11]);
			5'd12: h_shadow_regfile_prev = $past(wrapper.uut.regfile[12]);
			5'd13: h_shadow_regfile_prev = $past(wrapper.uut.regfile[13]);
			5'd14: h_shadow_regfile_prev = $past(wrapper.uut.regfile[14]);
			5'd15: h_shadow_regfile_prev = $past(wrapper.uut.regfile[15]);
			5'd16: h_shadow_regfile_prev = $past(wrapper.uut.regfile[16]);
			5'd17: h_shadow_regfile_prev = $past(wrapper.uut.regfile[17]);
			5'd18: h_shadow_regfile_prev = $past(wrapper.uut.regfile[18]);
			5'd19: h_shadow_regfile_prev = $past(wrapper.uut.regfile[19]);
			5'd20: h_shadow_regfile_prev = $past(wrapper.uut.regfile[20]);
			5'd21: h_shadow_regfile_prev = $past(wrapper.uut.regfile[21]);
			5'd22: h_shadow_regfile_prev = $past(wrapper.uut.regfile[22]);
			5'd23: h_shadow_regfile_prev = $past(wrapper.uut.regfile[23]);
			5'd24: h_shadow_regfile_prev = $past(wrapper.uut.regfile[24]);
			5'd25: h_shadow_regfile_prev = $past(wrapper.uut.regfile[25]);
			5'd26: h_shadow_regfile_prev = $past(wrapper.uut.regfile[26]);
			5'd27: h_shadow_regfile_prev = $past(wrapper.uut.regfile[27]);
			5'd28: h_shadow_regfile_prev = $past(wrapper.uut.regfile[28]);
			5'd29: h_shadow_regfile_prev = $past(wrapper.uut.regfile[29]);
			5'd30: h_shadow_regfile_prev = $past(wrapper.uut.regfile[30]);
			5'd31: h_shadow_regfile_prev = $past(wrapper.uut.regfile[31]);
			default: h_shadow_regfile_prev = $past(wrapper.uut.regfile[0]);
		endcase

		if (checker_inst.register_index == 0)
			h_shadow_x0_prev: assert(checker_inst.register_shadow == 0);
		else
			h_shadow_regfile_prev_assert: assert(checker_inst.register_shadow == h_shadow_regfile_prev);
	end
end

// Shadow register should follow RVFI writeback for the selected index.
always @(posedge clock) begin
	if (!reset && $past(!reset)) begin
		if ($past(rvfi_valid && !rvfi_trap && (checker_inst.register_index == rvfi_rd_addr))) begin
			if (checker_inst.register_index == 0)
				h_shadow_x0: assert(checker_inst.register_shadow == 0);
			else
				h_shadow_update: assert(checker_inst.register_shadow == $past(rvfi_rd_wdata));
		end else if ($past(checker_inst.register_written)) begin
			h_shadow_hold: assert(checker_inst.register_shadow == $past(checker_inst.register_shadow));
		end
	end
end

/// Helper Assertion End
endmodule
