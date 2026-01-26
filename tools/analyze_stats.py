#!/usr/bin/env python3
"""
Analyze CIll statistics from proof folders.
Extracts timing information from stdout.txt files in proof[x] directories.
Also counts assert statements in tb.sv files.
"""

import os
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
    Analyze all proof[x] directories under root_dir.
    """
    root_path = Path(root_dir)
    
    if not root_path.exists():
        print(f"Error: Directory '{root_dir}' does not exist")
        sys.exit(1)
    
    # Find all proof[x] directories
    proof_dirs = []
    for item in root_path.rglob('proof*'):
        if item.is_dir() and re.match(r'proof\d+', item.name):
            proof_dirs.append(item)
    
    if not proof_dirs:
        print(f"No proof directories found in '{root_dir}'")
        return
    
    print(f"Found {len(proof_dirs)} proof directories\n")
    
    stats_list = []
    assert_counts = []
    helper_line_counts = []
    
    # Process each proof directory
    for proof_dir in sorted(proof_dirs):
        stdout_file = proof_dir / 'stdout.txt'
        
        if not stdout_file.exists():
            print(f"Warning: {stdout_file} not found")
            continue
        
        # Read stdout.txt and find the CIll Statistic line
        with open(stdout_file, 'r') as f:
            for line in f:
                if 'CIll Statistic:' in line:
                    stats = parse_cill_statistic_line(line)
                    if stats:
                        stats['proof_dir'] = str(proof_dir.relative_to(root_path))
                        
                        # Count asserts in tb.sv
                        tb_file = proof_dir / 'tb.sv'
                        assert_count = count_asserts_in_file(tb_file)
                        stats['assert_count'] = assert_count
                        if assert_count > 0:
                            assert_counts.append(assert_count)
                        
                        # Count helper assertion lines
                        helper_lines = count_helper_assertion_lines(tb_file)
                        stats['helper_lines'] = helper_lines
                        if helper_lines > 0:
                            helper_line_counts.append(helper_lines)
                        
                        stats_list.append(stats)
                        break
    
    if not stats_list:
        print("No CIll statistics found in any proof directories")
        return
    
    # Calculate statistics
    total_times = [s['total_time'] for s in stats_list]
    percentages = [
        (s['correctness_time'] + s['inductiveness_time']) / s['total_time'] * 100
        for s in stats_list
    ]
    
    min_total_time = min(total_times)
    avg_total_time = sum(total_times) / len(total_times)
    avg_percentage = sum(percentages) / len(percentages)
    avg_assert_count = sum(assert_counts) / len(assert_counts) if assert_counts else 0
    avg_helper_lines = sum(helper_line_counts) / len(helper_line_counts) if helper_line_counts else 0
    
    # Print results
    print("=" * 80)
    print("CIll STATISTICS SUMMARY")
    print("=" * 80)
    print(f"\nTotal proof directories analyzed: {len(stats_list)}")
    print(f"\nMinimum total time: {min_total_time}s")
    print(f"Average total time: {avg_total_time:.2f}s")
    print(f"Average (Correctness + Inductiveness) / Total time: {avg_percentage:.2f}%")
    print(f"Average assert count in tb.sv: {avg_assert_count:.2f}")
    print(f"Average helper assertion lines: {avg_helper_lines:.2f}")
    print("\n" + "=" * 80)
    print("INDIVIDUAL RESULTS")
    print("=" * 80)
    
    for stats in stats_list:
        pct = (stats['correctness_time'] + stats['inductiveness_time']) / stats['total_time'] * 100
        print(f"\n{stats['proof_dir']}:")
        print(f"  Total time: {stats['total_time']}s")
        print(f"  Correctness check: {stats['correctness_time']}s")
        print(f"  Inductiveness check: {stats['inductiveness_time']}s")
        print(f"  Combined percentage: {pct:.2f}%")
        print(f"  Assert count: {stats['assert_count']}")
        print(f"  Helper assertion lines: {stats['helper_lines']}")


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python analyze_cill_stats.py <directory>")
        print("\nExample: python analyze_cill_stats.py res/nerv-reg")
        sys.exit(1)
    
    analyze_directory(sys.argv[1])
