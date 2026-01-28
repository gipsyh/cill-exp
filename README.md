# CIll Artifact

### Setup
- Install Yosys-Slang globally by following `./deps/yosys-slang/README.md`, then run `make install`.
- Install rIC3 globally by following `./rIC3/README.md`: `cargo install --path .`.
- Install Yosys globally by following `./deps/yosys/README.md`
- Go to the `boilerplate` directory under `nerv/serv/picorv32` and use `gen.sh` to generate the checks.
- Enter the generated check directory, use `PROMPT.md` in Codex, and run it using `GPT5.2-xhigh`.

### Note
- Cover and liveness cases are ignored.
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
- For ease of agent analysis and to allow multiple checks to run concurrently, each check includes all RTL files via symbolic links.
