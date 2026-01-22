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
	// Channel-0 views (NRET=1 in this configuration)
	wire h_rvfi_valid0 = rvfi_valid[0];
	wire h_rvfi_trap0  = rvfi_trap[0];
	wire [4:0]  h_rvfi_rs1_addr0  = rvfi_rs1_addr[0*5 +: 5];
	wire [4:0]  h_rvfi_rs2_addr0  = rvfi_rs2_addr[0*5 +: 5];
	wire [31:0] h_rvfi_rs1_rdata0 = rvfi_rs1_rdata[0*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
	wire [31:0] h_rvfi_rs2_rdata0 = rvfi_rs2_rdata[0*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];
	wire [4:0]  h_rvfi_rd_addr0   = rvfi_rd_addr[0*5 +: 5];
	wire [31:0] h_rvfi_rd_wdata0  = rvfi_rd_wdata[0*`RISCV_FORMAL_XLEN +: `RISCV_FORMAL_XLEN];

	// Architectural register-file model driven by RVFI retire stream.
	reg [31:0] h_rf [0:31];
	reg [31:0] h_rf_valid;

	integer h_i;
	always @(posedge clock) begin
		if (reset) begin
			for (h_i = 0; h_i < 32; h_i = h_i + 1) begin
				h_rf[h_i] <= 32'd0;
			end
			h_rf_valid <= 32'd0;
		end else begin
			// x0 is always 0 architecturally.
			h_rf[0] <= 32'd0;
			h_rf_valid[0] <= 1'b1;

			if (h_rvfi_valid0 && !h_rvfi_trap0) begin
				if (h_rvfi_rd_addr0 != 5'd0) begin
					h_rf[h_rvfi_rd_addr0] <= h_rvfi_rd_wdata0;
					h_rf_valid[h_rvfi_rd_addr0] <= 1'b1;
				end
			end
		end
	end

	// When a register has been written at least once since reset, RVFI must report
	// its current architectural value on subsequent reads.
	always @(posedge clock) begin
		if (!reset) begin
			if (h_rvfi_valid0 && (h_rvfi_rs1_addr0 != 5'd0) && h_rf_valid[h_rvfi_rs1_addr0]) begin
				h_rvfi_rs1_matches_model: assert(h_rvfi_rs1_rdata0 == h_rf[h_rvfi_rs1_addr0]);
			end
			if (h_rvfi_valid0 && (h_rvfi_rs2_addr0 != 5'd0) && h_rf_valid[h_rvfi_rs2_addr0]) begin
				h_rvfi_rs2_matches_model: assert(h_rvfi_rs2_rdata0 == h_rf[h_rvfi_rs2_addr0]);
			end

			// Tie the checker-internal shadow to the same architectural model.
			if (checker_inst.register_written) begin
				if (checker_inst.register_index != 5'd0) begin
					h_checker_written_implies_valid: assert(h_rf_valid[checker_inst.register_index]);
					h_checker_shadow_matches_model: assert(checker_inst.register_shadow == h_rf[checker_inst.register_index]);
				end else begin
					h_checker_x0_is_zero: assert(checker_inst.register_shadow == 32'd0);
				end
			end
		end
	end

/// Helper Assertion End
endmodule
