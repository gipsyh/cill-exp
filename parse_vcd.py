import sys
import re
import argparse


def parse_vcd(filename):
    signals = {}  # id -> name
    values = {}  # name -> current value

    # Store the history of states
    steps = []

    with open(filename, "r") as f:
        lines = f.readlines()

    header_done = False

    # Parse header to get signal names
    scope = []
    for line in lines:
        line = line.strip()
        if line.startswith("$enddefinitions"):
            header_done = True
            break

        if line.startswith("$scope"):
            parts = line.split()
            scope.append(parts[2])
        elif line.startswith("$upscope"):
            scope.pop()
        elif line.startswith("$var"):
            parts = line.split()
            # $var type size id name $end
            if len(parts) >= 5:
                id_code = parts[3]
                name = parts[4]
                full_name = ".".join(scope + [name])
                signals[id_code] = full_name
                values[full_name] = "x"

    # Parse values
    current_time = -1
    time_point_count = 0
    time_point_states = {}

    # We need to map id_code back to signal name for quick lookup
    id_to_name = signals

    start_parsing = False
    for line in lines:
        line = line.strip()
        if line.startswith("$enddefinitions"):
            start_parsing = True
            continue

        if not start_parsing:
            continue

        if line.startswith("#"):
            if current_time != -1:
                time_point_states[time_point_count] = values.copy()
                time_point_count += 1

            current_time = int(line[1:])
            continue

        if line.startswith("$dumpvars") or line.startswith("$end"):
            continue

        # Value change
        val = ""
        id_code = ""

        if line.startswith("b"):
            parts = line.split()
            if len(parts) >= 2:
                val = parts[0][1:]
                id_code = parts[1]
        else:
            val = line[0]
            id_code = line[1:]

        # Update value
        if id_code in id_to_name:
            name = id_to_name[id_code]
            values[name] = val

    # Save the last time point's state
    if current_time != -1:
        time_point_states[time_point_count] = values.copy()

    # Capture state every 2 time points (0, 2, 4, 6)
    # We skip the last one if it's the very end of the trace (e.g. #40)
    # to match the 4 steps (0-3) expected for 3 clock edges.
    sorted_keys = sorted(time_point_states.keys())
    for i in range(0, len(sorted_keys) - 1, 2):
        steps.append(time_point_states[sorted_keys[i]])

    return steps, list(values.keys())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Parse VCD and analyze steps.")
    parser.add_argument(
        "filename", nargs="?", default="ric3proj/ctilg/cti.vcd", help="VCD file path"
    )
    parser.add_argument(
        "--list", action="store_true", help="List all signals under uut"
    )
    parser.add_argument(
        "--signals",
        type=str,
        help="Comma-separated list of signals (e.g. 'clk,rst,data')",
    )

    args = parser.parse_args()

    if not args.list and not args.signals:
        parser.print_help()
        sys.exit(0)

    print(f"Parsing {args.filename}...")
    steps, all_signals = parse_vcd(args.filename)

    if args.list:
        print(f"Found {len(all_signals)} signals:")
        for sig in sorted(all_signals):
            print(sig)

    elif args.signals:
        signal_list = args.signals.split(",")
        print(f"Found {len(steps)} steps (clock rising edges).")

        def format_hex(val):
            if val and all(c in '01' for c in val):
                return hex(int(val, 2))
            return val

        for i, step in enumerate(steps):
            print(f"--- Step {i} ---")
            for key in signal_list:
                # Try exact match first
                if key in step:
                    print(f"  {key}: {format_hex(step[key])}")
                else:
                    # Try suffix match
                    matches = [k for k in step.keys() if k.endswith("." + key)]
                    if matches:
                        for m in matches:
                            print(f"  {m}: {format_hex(step[m])}")
                    else:
                        print(f"  {key}: <not found>")
