## Core Concepts
- Correctness: An assertion is correct if it holds for all states reachable from the initial state. A correct assertion is referred to as an invariant. If an assertion is incorrect, a Counterexample (CEX) exists.
- Induction: An assertion is inductive if, assuming it holds for state $S$, it implies it holds for state $S'$.
- K-Induction: If it holds for steps $0$ to $K-1$, it implies it holds for step $K$.
- CTI (Counterexample to Induction): A trace segment where the assertion holds for the first $K$ steps (from $0$ to $K-1$) but fails at step $K$. If an invariant is not inductive, its CTIs must be unreachable from the initial state.

## Objective
Your goal is to prove the correctness of the original assertions. You may introduce helper assertions to make a non-inductive assertion provable. Specifically, you can eliminate its CTIs by strengthening the proof with helper assertions such that any CTI violates at least one helper assertion.

**注意**：请整体的思考DUT和可能的CTI，选择比较泛化的helper assertions来尽量让更多的CTI失效，会更加高效的prove。请不要纠结某一个状态，而是根据这个CTI泛化到一个较强的最关键的invariant（使用高阶逻辑能可能更快的达到目的，如，某两个信号的等价关系`a == b` or `a < b`），因为如果写的不是最核心重要的invariant，可能会导致CTI永远block不完。If all helper assertions are inductive, and they enable the original assertion to become inductive as well, then the proof is successful.

## `ric3 cill`
You can use it to check whether the assertions are inductive and generate CTI.
- `ric3 cill check`: Performs the following steps automatically:
  1. Bounded Model Checking: Checks the correctness of helper assertions. If a CEX is found, it is saved to `ric3proj/cill/cex.vcd`, and the violated assertion is reported. You should analyze the CEX and fix the incorrect assertion.
  2. CTI Validation: If a CTI was generated previously, this step checks whether the new helper assertions successfully block it. If the CTI is not blocked, the command returns immediately, indicating that the assertion may need further refinement.
  3. Induction Check: Each assertion is assigned a temporary `<ID>`, and its inductiveness result is printed.

- `ric3 cill select <ID>`: Selects a non-inductive assertion to generate CTI. It must be used immediately after `ric3 cill check` reports non-inductive assertions. After each `ric3 cill check`, the `select` command can be invoked only once; otherwise, you need to rerun `ric3 cill check`.
  * Output: Generates a CTI to `ric3proj/cill/cti.vcd`. The CTI contains only the signals relevant to the induction failure; irrelevant signals are either omitted or marked with `'x'`/`'X'`. The CTI trace consists of 5 steps: the first 4 steps satisfy all assertions, while the final step violates the selected assertion.

- `ric3 cill abort`: Discards the current CTI context. Use this if the tool crashes, if you delete the assertion that generated the CTI, or if you decide not to block the current CTI.

## `vcd-tools` (MCP):
- `vcd.search_signals(vcd_path, pattern)`: Return signals matching the regex `pattern`. It is not recommended to list all signals at once, as this may produce many irrelevant results. Instead, search for the signals you need.
- `vcd.signal_values(vcd_path, signals=[...])`: Inspect signal values. signal names must match exactly (no fuzzy matching / regex).

## Operational Constraints (CRITICAL)
- **Editing Limits**: strictly **ONLY** add, modify, or delete code between `/// Helper Assertion Begin` and `/// Helper Assertion End`.
- All helper assertions and auxiliary registers must be named `h_*`.
- **Prohibitions**:
  * **NO** `assume` statements allowed.
  * **NO** modifying the original DUT logic or `o_*` assertions.
  * **NO** creating new `/// Helper Assertion Begin/End` blocks.
- Do not read files in `ric3proj/` other than the specified `.vcd` files.
- You can only use the three `ric3 cill` commands listed above; no other `ric3` commands are permitted.

## NOTE
- `ric3` restricts the reset signal to be high only at cycle 0 (step 0 in CEX (NOT CTI)), with no resets afterward. During cycle 0, register values may be non-deterministic. Therefore, make sure invariants are checked post-reset: `if (!reset) h_*: assert`.
- Variable assignments in each new CTI/CEX are independent of those in previous ones; signal values may be completely different from earlier cases and must be re-examined each time.
- The generated VCD for CTI includes only the signals pertinent to the current non-induction failure. If a DUT signal is absent from the VCD, or if specific bits of a signal are marked as 'x'/'X', it indicates that these elements are irrelevant to the non-inductive transition. It is highly recommended to derive helper assertions based solely on the relevant (non-'x') signals.
- `ric3` uses Yosys as the DUT parser and does not include a Verific frontend. Please avoid using SVA constructs (e.g., `|->`), but `$past` is supported. It is recommended to write assertions in the following format:
    ```systemverilog
    always @(posedge clk) begin
        if (!reset) 
            h_*: assert();
    end
    ```
- Submodule signals can be accessed using '.' notation.
