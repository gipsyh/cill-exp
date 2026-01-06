`include "defines.sv"
`include "rvfi_channel.sv"

module rvfi_wrapper (
	input         clock,
	input         reset,
	`RVFI_OUTPUTS
);
	(* keep *) wire trap;

	(* keep *) `rvformal_rand_reg mem_ready;
	(* keep *) `rvformal_rand_reg [31:0] mem_rdata;

	(* keep *) wire        mem_valid;
	(* keep *) wire        mem_instr;
	(* keep *) wire [31:0] mem_addr;
	(* keep *) wire [31:0] mem_wdata;
	(* keep *) wire [3:0]  mem_wstrb;

	picorv32 #(
		.COMPRESSED_ISA(1),
		.ENABLE_FAST_MUL(1),
		.ENABLE_DIV(1),
		.BARREL_SHIFTER(1)
	) uut (
		.clk       (clock    ),
		.resetn    (!reset   ),
		.trap      (trap     ),

		.mem_valid (mem_valid),
		.mem_instr (mem_instr),
		.mem_ready (mem_ready),
		.mem_addr  (mem_addr ),
		.mem_wdata (mem_wdata),
		.mem_wstrb (mem_wstrb),
		.mem_rdata (mem_rdata),

		`RVFI_CONN
	);

`ifdef PICORV32_FAIRNESS
	reg [2:0] mem_wait = 0;
	always @(posedge clock) begin
		mem_wait <= {mem_wait, mem_valid && !mem_ready};
		assume (~mem_wait || trap);
	end
`endif

`ifdef PICORV32_CSR_RESTRICT
	always @* begin
		if (rvfi_valid && rvfi_insn[6:0] == 7'b1110011) begin
			if (rvfi_insn[14:12] == 3'b010) begin
				assume (rvfi_insn[31:20] == 12'hC00 || rvfi_insn[31:20] == 12'hC01 || rvfi_insn[31:20] == 12'hC02 ||
						rvfi_insn[31:20] == 12'hC80 || rvfi_insn[31:20] == 12'hC81 || rvfi_insn[31:20] == 12'hC82);
				assume (rvfi_insn[19:15] == 0);
			end
			assume (rvfi_insn[14:12] != 3'b001);
			assume (rvfi_insn[14:12] != 3'b011);
			assume (rvfi_insn[14:12] != 3'b101);
			assume (rvfi_insn[14:12] != 3'b110);
			assume (rvfi_insn[14:12] != 3'b111);
		end
	end
`endif
endmodule

module testbench (
	`ifdef RISCV_FORMAL_TRIG_CYCLE
		input trig,
	`endif
	input check,
	input clock, reset
);
	`RVFI_WIRES
	`RVFI_BUS_WIRES

	always_comb assume (reset == $initstate);

	// Prevent rvfi_order from wrapping around from {64{1'b1}} to 0.
	// Also set the initial value of rvfi_order to 1 in the DUT.
	always_comb assume(rvfi_order != 0);

	reg [7:0] cycle_reg = 0;
	wire [7:0] cycle = reset ? 8'd 0 : cycle_reg;

	always @(posedge clock) begin
		cycle_reg <= reset ? 8'd 1 : cycle_reg + (cycle_reg != 8'h ff);
	end

	`RISCV_FORMAL_CHECKER checker_inst (
		.clock  (clock),
		.reset  (cycle < `RISCV_FORMAL_RESET_CYCLES),
`ifdef RISCV_FORMAL_TRIG_CYCLE
`ifdef RISCV_FORMAL_UNBOUNDED
		.trig   (trig),
`else
		.trig   (cycle == `RISCV_FORMAL_TRIG_CYCLE),
`endif
`endif
`ifdef RISCV_FORMAL_CHECK_CYCLE
`ifdef RISCV_FORMAL_UNBOUNDED
		.check   (check),
`else
		.check  (cycle == `RISCV_FORMAL_CHECK_CYCLE),
`endif
`endif
		`RVFI_CONN
		`RVFI_BUS_CONN
	);

	rvfi_wrapper wrapper (
		.clock (clock),
		.reset (reset),
		`RVFI_CONN
		`RVFI_BUS_CONN
	);
endmodule
