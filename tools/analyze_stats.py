#!/usr/bin/env python3
"""
Analyze CIll statistics from proof folders.
Extracts timing information from stdout.txt files in proof[x] directories.
"""

import os
import re
import sys
from pathlib import Path


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
    
    # Print results
    print("=" * 80)
    print("CIll STATISTICS SUMMARY")
    print("=" * 80)
    print(f"\nTotal proof directories analyzed: {len(stats_list)}")
    print(f"\nMinimum total time: {min_total_time}s")
    print(f"Average total time: {avg_total_time:.2f}s")
    print(f"Average (Correctness + Inductiveness) / Total time: {avg_percentage:.2f}%")
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


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python analyze_cill_stats.py <directory>")
        print("\nExample: python analyze_cill_stats.py res/nerv-reg")
        sys.exit(1)
    
    analyze_directory(sys.argv[1])
