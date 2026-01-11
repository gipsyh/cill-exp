# Agent Documentation for Interactive Hardware Formal Proving

## Overview

This repository contains test cases for **interactive hardware design formal proving** using the `ric3` formal verification tool. The workflow involves iteratively adding helper assertions to block "hard-to-disprove transitions" (CTIs) until original assertions become provable.

## Project Structure

```
/srv/stuff0/cill-exp/
├── ric3-src/              # rIC3 formal verification tool source
│   └── src/cli/          # CLI implementation
│       ├── mod.rs        # CLI structure and commands
│       ├── tryprove.rs   # Stateless proof attempt command
│       ├── cill/         # CTI Guided Interactive Lemma Generation
│       │   ├── mod.rs    # CIll state machine and main logic
│       │   ├── ind.rs    # Induction checking and CTI handling
│       │   └── utils.rs  # Witness saving and VCD generation
│       └── yosys.rs      # Yosys-based BTOR generation
├── tryprove-agent/       # Agent prompts and tools for LLM-assisted proving
│   ├── agent.py          # Main agent implementation
│   ├── cill_prompt.md    # Prompt for `ric3 cill` workflow
│   ├── old_tryprove_prompt.md  # Legacy tryprove prompt
│   └── vcd_utils.py      # VCD analysis utilities
├── nerv/                 # NERV CPU DUT test cases
├── serv/                # SERV CPU DUT test cases
├── picorv32/            # PicoRV32 CPU DUT test cases
├── riscv-formal/        # Shared RISC-V formal verification macros
├── prompt.md            # Main proving prompt (Chinese)
└── results.csv          # Proving results tracking
```

## Test Cases Collection (DUT Directories)

Each DUT directory contains:
- `ric3.toml` - Configuration for ric3 verification
- RTL source files (`.sv`)
- Testbench with assertion checks
- `hard_trans/` - Directory containing CTI waveforms from failed proofs

### Available DUTs

| Directory | DUT | Test Categories |
|-----------|-----|-----------------|
| `nerv/` | NERV RISC-V core | causal, pc_fwd, pc_bwd, reg, insn_add, insn_lb |
| `serv/` | SERV RISC-V core | causal, pc_fwd, pc_bwd, reg, insn_add, insn_lb |
| `picorv32/` | PicoRV32 RISC-V core | causal, pc_fwd, pc_bwd, reg, insn_add, insn_lb |

### Each Test Category Structure

```
DUT_CATEGORY/
├── ric3.toml              # ric3 configuration
├── *.sv                   # RTL and testbench files
├── defines.sv             # Macro definitions
├── rvfi_*.sv              # RISC-V formal checking macros
├── wrapper.sv             # DUT wrapper
└── hard_trans/            # CTI waveforms (generated during proving)
    ├── o_*.vcd           # VCD waveforms for CTIs
    └── o_*.wit          # Witness files
```

## rIC3 Tool Structure

### Main Commands

#### `ric3 cill` - Interactive Lemma Generation

Stateful workflow with subcommands:

```
ric3 cill check    # Run BMC, validate CTI, check induction
ric3 cill select <ID>  # Generate CTI for specific assertion
ric3 cill abort    # Clear current CTI context
```

**Flow** (from `ric3-src/src/cli/cill/mod.rs`):
1. BMC checking for counterexamples
2. CTI validation (is previous CTI blocked?)
3. Induction check with IC3
4. Report non-inductive assertions

#### `ric3 tryprove` - Stateless Proof Attempt

LLM/agent-friendly alternative:

```
ric3 tryprove DUT_DIR [--bmc-timeout 15] [--ic3-timeout 30]
```

**Key Features** (from `ric3-src/src/cli/tryprove.rs`):
- Processes all assertions at once
- Reports status per property
- Tracks CTI state across runs
- Generates VCD waveforms for hard transitions

**Property Statuses**:
- `Proved` - Already proved in previous run
- `ProvedAfterHelper` - Newly proved after helper assertions
- `NewCti` - First time seeing this failure
- `CtiNotBlocked` - Previous CTI not blocked
- `CtiBlockedNewAppeared` - Progress, but new CTI appeared
- `Regressed` - Was proved, now fails again

### CIll State Machine

States defined in `ric3-src/src/cli/cill/mod.rs`:

```rust
enum CIllState {
    Check,           // Ready for new check
    Block(String),   // CTI generated for property
    Select(Vec<bool>),  // Non-inductive properties identified
}
```

### Key Components

#### CIll (`cill/mod.rs`)
- Manages verification state
- Coordinates BMC, CTI checking, and induction proofs
- Handles witness saving and VCD generation

#### Induction Checking (`cill/ind.rs`)
- `check_inductive()` - Runs IC3 on all properties
- `check_cti()` - Validates if CTI is blocked
- `check_cti_from_str()` - Checks CTI from string (used by tryprove)
- `refresh_cti_for_prop()` - Updates CTI when DUT changes

#### Witness Handling (`cill/utils.rs`)
- `save_witness()` - Saves CTI witness and generates VCD
- `print_ind_res()` - Displays induction results table

## Workflow

### Interactive Workflow (`ric3 cill`)

```
1. cd DUT_DIR
2. ric3 cill check
   - BMC checks correctness
   - Validates previous CTI
   - Checks inductiveness
3. ric3 cill select <ID>  # For non-inductive assertion
4. Analyze CTI VCD (ric3proj/cill/cti.vcd)
5. Add helper assertions in tb.sv (between markers)
6. ric3 cill check  # Validate helpers block CTI
7. Repeat steps 3-6 until all inductive
```

### Stateless Workflow (`ric3 tryprove`)

```
1. cd DUT_DIR
2. ric3 tryprove .
3. Analyze hard_trans/*.vcd files
4. Add helper assertions
5. ric3 tryprove .
6. Repeat until all proved
```

## Helper Assertion Syntax

Helpers go in `tb.sv` between markers:

```systemverilog
/// Helper Assertion Begin

// Helper register
reg [7:0] h_cycle_count;
always @(posedge clk) begin
    if (reset) h_cycle_count <= 0;
    else if (h_cycle_count < 255) h_cycle_count <= h_cycle_count + 1;
end

// Helper assertion
h_warmup: assert(h_cycle_count >= 3 || some_condition);

/// Helper Assertion End
```

**Rules**:
- All helpers named `h_*`
- All helper registers named `h_*`
- `$past()` and `$stable()` supported
- No SVA constructs (`|->`, `##`, etc.)
- No `assume` statements
- Only modify between markers

## Key Concepts

### CTI (Counterexample to Induction)
- Trace where assertion holds for steps 0..K-1 but fails at K
- Must be unreachable from initial state
- Blocked by helper assertions that fail earlier in trace

### Induction
- Assertion is inductive if: holds(S) → holds(S')
- Non-inductive assertions have CTIs

### Safety vs Induction
- **Safety**: Assertion holds for all reachable states
- **Induction**: Assertion holds for next state if it holds for current

## Important Files

### ric3 Configuration
- `DUT_DIR/ric3.toml` - DUT files, reset signal, parser settings

### Testbench
- `DUT_DIR/tb.sv` - Contains helper assertion markers
- `DUT_DIR/defines.sv` - Macro definitions for RISC-V formal

### Cache/State
- `ric3proj/` - Cached DUT and verification state
- `ric3proj/cill/state.ron` - CIll state
- `ric3proj/cill/cti` - Current CTI witness
- `ric3proj/cill/cti.vcd` - Current CTI waveform
- `ric3proj/tryprove_state.ron` - Tryprove state (CTIs, proved props)

### Generated Outputs
- `DUT_DIR/hard_trans/*.vcd` - CTI waveforms
- `DUT_DIR/hard_trans/*.wit` - CTI witness files

## Common Patterns

### Analyzing CTI VCDs
1. Look for 'x' values - irrelevant signals
2. Focus on step 3→4 transition
3. Identify why step 0 is unreachable
4. Common invariants:
   - Counters can't jump arbitrarily
   - FSM has valid state transitions
   - Registers need init cycles after reset
   - Signal combinations mutually exclusive

### Writing Effective Helpers
1. Identify the unreachable pattern
2. Write assertion that is TRUE for all reachable states
3. Write assertion that FAILS on CTI step 0-3
4. Make assertion inductive (check with ric3)

## VCD Analysis Tools

Available via `tryprove-agent/vcd_utils.py`:
- `vcd.search_signals(vcd_path, pattern)` - Find signals
- `vcd.signal_values(vcd_path, signals=[...])` - Get signal values

## Notes

1. **Reset Behavior**: Reset is high only at cycle 0, register values may be non-deterministic at step 0
2. **CTI Independence**: Each CTI is independent - values may differ between runs
3. **Parser**: ric3 uses Yosys with slang plugin, no SVA support
4. **Hierarchical Access**: Use '.' notation for submodule signals
5. **Safety Check**: If BMC finds CEX, helpers are incorrect
