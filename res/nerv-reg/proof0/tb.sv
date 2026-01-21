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

	reg h_seen_write;
	reg [`RISCV_FORMAL_XLEN-1:0] h_shadow_value;

	// Mirror the checker shadow model in helper state:
	// - h_seen_write becomes 1 once a matching RVFI write to register_index occurs.
	// - h_shadow_value holds the last matching rvfi_rd_wdata.
	always @(posedge clock) begin
		if (reset) begin
			h_seen_write <= 0;
			h_shadow_value <= 0;
		end else begin
			if (rvfi_valid[0] && !rvfi_trap[0] && checker_inst.register_index == rvfi_rd_addr[0*5 +: 5]) begin
				h_seen_write <= 1;
				h_shadow_value <= rvfi_rd_wdata[0*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
			end
		end
	end

	// Constrain the checker internal state to be consistent with the observed RVFI
	// stream for the selected register_index.
	always @(posedge clock) begin
		if (!reset) begin
			h_shadow_written_consistent: assert(checker_inst.register_written == h_seen_write);
			h_shadow_value_consistent: assert(!h_seen_write || (checker_inst.register_shadow == h_shadow_value));
		end
	end

	// In cycles with no RVFI retirement, the architectural state should be stable.
	// For a non-zero tracked register that has been written, the checker shadow
	// should agree with the DUT regfile during such idle cycles.
	always @(posedge clock) begin
		if (!reset && !rvfi_valid[0] && checker_inst.register_written && (checker_inst.register_index != 0)) begin
			h_shadow_matches_regfile_when_idle: assert(checker_inst.register_shadow == wrapper.uut.regfile[checker_inst.register_index]);
		end
	end

	// x0 is hardwired to zero architecturally. For NERV, RVFI also reports
	// rd_wdata=0 when rd_addr=0, so the checker shadow for register_index==0
	// must remain 0.
	always @(posedge clock) begin
		if (!reset && (checker_inst.register_index == 0)) begin
			h_x0_shadow_zero: assert(checker_inst.register_shadow == 0);
		end
	end

	// NERV-specific RVFI consistency: rvfi_rs*_rdata is registered from the
	// combinational regfile read (pre-state), so it must equal the *previous*
	// cycle's regfile value at the reported rs* address (with x0 hardwired to 0).
	function automatic [`RISCV_FORMAL_XLEN-1:0] h_past_regfile(input [4:0] h_addr);
		case (h_addr)
			5'd0:  h_past_regfile = 0;
			5'd1:  h_past_regfile = $past(wrapper.uut.regfile[1]);
			5'd2:  h_past_regfile = $past(wrapper.uut.regfile[2]);
			5'd3:  h_past_regfile = $past(wrapper.uut.regfile[3]);
			5'd4:  h_past_regfile = $past(wrapper.uut.regfile[4]);
			5'd5:  h_past_regfile = $past(wrapper.uut.regfile[5]);
			5'd6:  h_past_regfile = $past(wrapper.uut.regfile[6]);
			5'd7:  h_past_regfile = $past(wrapper.uut.regfile[7]);
			5'd8:  h_past_regfile = $past(wrapper.uut.regfile[8]);
			5'd9:  h_past_regfile = $past(wrapper.uut.regfile[9]);
			5'd10: h_past_regfile = $past(wrapper.uut.regfile[10]);
			5'd11: h_past_regfile = $past(wrapper.uut.regfile[11]);
			5'd12: h_past_regfile = $past(wrapper.uut.regfile[12]);
			5'd13: h_past_regfile = $past(wrapper.uut.regfile[13]);
			5'd14: h_past_regfile = $past(wrapper.uut.regfile[14]);
			5'd15: h_past_regfile = $past(wrapper.uut.regfile[15]);
			5'd16: h_past_regfile = $past(wrapper.uut.regfile[16]);
			5'd17: h_past_regfile = $past(wrapper.uut.regfile[17]);
			5'd18: h_past_regfile = $past(wrapper.uut.regfile[18]);
			5'd19: h_past_regfile = $past(wrapper.uut.regfile[19]);
			5'd20: h_past_regfile = $past(wrapper.uut.regfile[20]);
			5'd21: h_past_regfile = $past(wrapper.uut.regfile[21]);
			5'd22: h_past_regfile = $past(wrapper.uut.regfile[22]);
			5'd23: h_past_regfile = $past(wrapper.uut.regfile[23]);
			5'd24: h_past_regfile = $past(wrapper.uut.regfile[24]);
			5'd25: h_past_regfile = $past(wrapper.uut.regfile[25]);
			5'd26: h_past_regfile = $past(wrapper.uut.regfile[26]);
			5'd27: h_past_regfile = $past(wrapper.uut.regfile[27]);
			5'd28: h_past_regfile = $past(wrapper.uut.regfile[28]);
			5'd29: h_past_regfile = $past(wrapper.uut.regfile[29]);
			5'd30: h_past_regfile = $past(wrapper.uut.regfile[30]);
			5'd31: h_past_regfile = $past(wrapper.uut.regfile[31]);
			default: h_past_regfile = 0;
		endcase
	endfunction

	always @(posedge clock) begin
		if (!reset && rvfi_valid[0]) begin
			h_rs1_rdata_matches_regfile: assert(rvfi_rs1_rdata[0*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN] == h_past_regfile(rvfi_rs1_addr[0*5 +: 5]));
			h_rs2_rdata_matches_regfile: assert(rvfi_rs2_rdata[0*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN] == h_past_regfile(rvfi_rs2_addr[0*5 +: 5]));
		end
	end

/// Helper Assertion End
endmodule
