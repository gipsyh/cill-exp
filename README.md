# rIC3 CIll Artifact


### Note
- Historically, riscv-formal mainly targeted bounded checking. As a result, some checks may not be sound under unbounded proofs. For example, `rvfi_order` can overflow and wrap around (loop back), which can interfere with certain checks. We prevent this by adding an `assume` constraint as shown below.
```systemverilog
reg rvfi_order_loopback;
always @(posedge clock) begin
    if (reset) begin
        rvfi_order_loopback <= 0;
    end else if (rvfi_valid && rvfi_order == {64{1'b1}}) begin
        rvfi_order_loopback <= 1;
    end
end
always_comb assume (!(rvfi_order_loopback && check));
```
- Since native Yosys does not support hierarchical references to internal module signals, rIC3 utilizes the slang-plugin with Yosys to parse the RTL.
- For ease of agent analysis and to allow multiple checks to run concurrently, each check includes all RTL files via symbolic links.
