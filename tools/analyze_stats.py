#!/usr/bin/env python3
"""
Analyze CIll statistics from a single result folder.
Extracts timing information from stdout.txt and counts assert statements in tb.sv.
"""

import re
import sys
from pathlib import Path


def count_asserts_in_file(file_path):
    """
    Count the number of assert statements in a SystemVerilog file.
    Excludes asserts in comments (both // and /* */ style).
    """
    if not file_path.exists():
        return 0
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Remove multi-line comments /* ... */
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    
    # Remove single-line comments // ...
    lines = content.split('\n')
    code_lines = []
    for line in lines:
        # Remove everything after // on each line
        code_part = line.split('//')[0]
        code_lines.append(code_part)
    
    code_content = '\n'.join(code_lines)
    
    # Count assert statements (word boundary to avoid matching "assertion" etc.)
    assert_pattern = r'\bassert\s*\('
    matches = re.findall(assert_pattern, code_content)
    
    return len(matches)


def count_helper_assertion_lines(file_path):
    """
    Count the number of code lines between "/// Helper Assertion Begin" 
    and "/// Helper Assertion End" markers in a file.
    Returns the total line count, or 0 if markers are not found.
    """
    if not file_path.exists():
        return 0
    
    with open(file_path, 'r') as f:
        lines = f.readlines()
    
    line_count = 0
    inside_helper_block = False
    
    for line in lines:
        stripped = line.strip()
        
        if '/// Helper Assertion Begin' in line:
            inside_helper_block = True
            continue  # Don't count the begin marker line itself
        elif '/// Helper Assertion End' in line:
            inside_helper_block = False
            continue  # Don't count the end marker line itself
        
        if inside_helper_block:
            # Count all lines including blank lines and comments
            line_count += 1
    
    return line_count


def parse_cill_statistic_line(line):
    """
    Parse a line like:
    CIll Statistic: Total time: 956s, Correctness check: 47s, Inductiveness check: 118s
    
    Returns a dict with total_time, correctness_time, inductiveness_time (in seconds)
    """
    pattern = r'CIll Statistic: Total time: (\d+)s, Correctness check: (\d+)s, Inductiveness check: (\d+)s'
    match = re.search(pattern, line)
    
    if match:
        return {
            'total_time': int(match.group(1)),
            'correctness_time': int(match.group(2)),
            'inductiveness_time': int(match.group(3))
        }
    return None


def analyze_directory(root_dir):
    """
    Analyze a single result directory containing stdout.txt and tb.sv.
    """
    root_path = Path(root_dir)
    
    if not root_path.exists():
        print(f"Error: Directory '{root_dir}' does not exist")
        sys.exit(1)

    stdout_file = root_path / 'stdout.txt'
    if not stdout_file.exists():
        print(f"Error: {stdout_file} not found")
        sys.exit(1)

    # Read stdout.txt and find the CIll Statistic line (expects exactly one run per folder).
    stats = None
    with open(stdout_file, 'r') as f:
        for line in f:
            if 'CIll Statistic:' in line:
                stats = parse_cill_statistic_line(line)
                if stats:
                    break

    if not stats:
        print(f"No CIll statistics found in '{stdout_file}'")
        return

    tb_file = root_path / 'tb.sv'
    stats['assert_count'] = count_asserts_in_file(tb_file)
    stats['helper_lines'] = count_helper_assertion_lines(tb_file)

    pct = (
        (stats['correctness_time'] + stats['inductiveness_time']) / stats['total_time'] * 100
        if stats['total_time'] > 0
        else 0.0
    )

    print("=" * 80)
    print("CIll STATISTICS")
    print("=" * 80)
    print(f"\nDirectory: {root_path}")
    print(f"\nTotal time: {stats['total_time']}s")
    print(f"Correctness check: {stats['correctness_time']}s")
    print(f"Inductiveness check: {stats['inductiveness_time']}s")
    print(f"Combined percentage: {pct:.2f}%")
    print(f"Assert count in tb.sv: {stats['assert_count']}")
    print(f"Helper assertion lines: {stats['helper_lines']}")


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 tools/analyze_stats.py <result_dir>")
        print("\nExample: python3 tools/analyze_stats.py res/nerv-reg")
        sys.exit(1)
    
    analyze_directory(sys.argv[1])
