## Objective
Your goal is to prove the correctness of the original assertions in the DUT. You can achieve this by generating invariants (helper assertions). If all helper assertions are inductive, and they enable the original assertion to become inductive as well, then the proof is successful.

## Core Concepts
1.  **Correctness**: An assertion is correct if it holds for all states reachable from the initial state. A correct assertion is referred to as an **invariant**. If an assertion is incorrect, a **Counterexample (CEX)** exists.
2.  **Inductiveness**: An assertion is inductive if, assuming it holds for state $S$, it implies it holds for state $S'$.
    * **K-Induction**: If it holds for steps $0$ to $K-1$, it implies it holds for step $K$.
    * **CTI (Counterexample to Induction)**: A trace segment where the assertion holds for the first $K$ steps (from $0$ to $K-1$) but fails at step $K$. If an invariant is not inductive, its CTIs must be unreachable from the initial state.

## Environment and File Structure
* **Configuration**: `ric3.toml` contains DUT information.
* **Assertions**:
  * `o_*`: Original assertions (Read-only, assumed correct but hard to prove).
  * `h_*`: Helper assertions (Created/Modified by you to block CTIs).

## `ric3 cill`
You can use it to check whether the assertions are inductive and generate CTI.

Run `ric3 cill <subcommand>` in the directory containing `ric3.toml`.

- `ric3 cill check`: Performs the following steps automatically:
  1.  **Bounded Model Checking**: Checks the correctness of helper assertions. If a CEX is found, it is saved to `ric3proj/cill/cex.vcd`, and the violated assertion is reported. You should analyze the CEX and fix the incorrect assertion.
  2.  **CTI Validation**: If a CTI was generated previously, this step checks whether the new helper assertions successfully block it. If the CTI is not blocked, the command returns immediately, indicating that the assertion may need further refinement.
  3.  **Induction Check**: Checks the inductiveness of the assertions. Each assertion is assigned a temporary `<ID>`, and its inductiveness result is printed.

- `ric3 cill select <ID>`: Selects a non-inductive assertion to generate CTI. It must be used immediately after `ric3 cill check` reports non-inductive assertions. After each `ric3 cill check`, the `select` command can be invoked only once; otherwise, you need to rerun `ric3 cill check`.
  * **Output**: Generates a **CTI** and saves it to `ric3proj/cill/cti.vcd`. The generated VCD file contains only the signals relevant to the induction failure; irrelevant signals are either omitted or marked with `'x'`/`'X'` (don’t care). A CTI trace typically consists of 5 steps: the first 4 steps satisfy all assertions, while the final step violates the selected assertion.
  * **Goal**: Analyze this CTI and write a new h_* assertion that is valid on all reachable states but is violated at one of the first 4 steps of this CTI (thus "blocking" it), and is inductive.

- 3. `ric3 cill abort`: Discards the current CTI context. Use this if the tool crashes, if you delete the assertion that generated the CTI, or if you decide not to block the current CTI.

## `vcd-tools` (MCP): Inspects VCD files.
- List signals: `vcd.list_signals(vcd_path)`
- Inspect values: `vcd.signal_values(vcd_path, signals=[...])`, Signal names must match exactly (no fuzzy matching / regex).

## Operational Constraints (CRITICAL)
- **Editing Limits**: strictly **ONLY** add, modify, or delete code between `/// Helper Assertion Begin` and `/// Helper Assertion End`.
- **Naming Convention**: All new assertions must use `assert` and be named `h_*` (e.g., `h_01: assert(cond);`). Auxiliary registers must be named `reg h_*`.
- **Prohibitions**:
  * **NO** `assume` statements allowed.
  * **NO** modifying the original DUT logic or `o_*` assertions.
  * **NO** creating new `/// Helper Assertion Begin/End` blocks.
- **File Access**: Do not read files in `ric3proj/` other than the specified `.vcd` files.

## NOTE
- In CEX (NOT CTI), Step 0 typically represents the cycle in which the reset signal is asserted. During this cycle, register values may be non-deterministic.
- Variable assignments in each new CTI/CEX are independent of those in previous ones; signal values may be completely different from earlier cases and must be re-examined each time.
- The generated VCD for CTI includes only the signals pertinent to the current non-induction failure. If a DUT signal is absent from the VCD, or if specific bits of a signal are marked as 'x'/'X', it indicates that these elements are irrelevant to the non-inductive transition. It is highly recommended to derive helper assertions based solely on the relevant (non-'x') signals.
- `ric3` uses Yosys as the DUT parser and does not include a Verific frontend; therefore, please avoid writing SVA constructs (e.g., `assert property @(posedge clk)`, `|->`, `$past`, etc.). It is recommended to write assertions in the following form:
    ```systemverilog
    always @(posedge clk) begin
        h_*: assert();
    end
    ```
- Submodule signals can be accessed using '.' notation.
