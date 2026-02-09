#!/usr/bin/env python3
from pathlib import Path
import re
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parent
coverage_path = root / 'coverage_metrics.txt'
dup_path = root / 'dupliation_metrics.txt'

# Read coverage (single number)
coverage_text = coverage_path.read_text().strip()
match = re.search(r"[-+]?[0-9]*\.?[0-9]+", coverage_text)
if not match:
    raise SystemExit('No numeric coverage found in coverage_metrics.txt')
coverage_val = float(match.group(0))

# Parse duplication metrics
lines = dup_path.read_text().splitlines()
metrics_header = None
metrics_row = None
hist_header = None
hist_rows = []
state = None
for line in lines:
    if line.startswith('## METRICS CLASS'):
        state = 'metrics'
        metrics_header = None
        metrics_row = None
        continue
    if line.startswith('## HISTOGRAM'):
        state = 'hist'
        hist_header = None
        hist_rows = []
        continue
    if line.startswith('#') or not line.strip():
        continue

    if state == 'metrics':
        if metrics_header is None:
            metrics_header = line.split('\t')
        elif metrics_row is None:
            metrics_row = line.split('\t')
    elif state == 'hist':
        if hist_header is None:
            hist_header = line.split('\t')
        else:
            hist_rows.append(line.split('\t'))

metrics = dict(zip(metrics_header, metrics_row)) if metrics_header and metrics_row else {}

# Build histogram data as lists
hist = {}
if hist_header and hist_rows:
    for i, col in enumerate(hist_header):
        vals = []
        for row in hist_rows:
            try:
                vals.append(float(row[i]))
            except ValueError:
                vals.append(row[i])
        hist[col] = vals

# Plot coverage
plt.figure(figsize=(4, 3))
plt.bar(['Mean coverage'], [coverage_val], color='#4C78A8')
plt.ylabel('Coverage')
plt.title('Stage01 Mean Coverage')
plt.tight_layout()
coverage_out = root / 'stage01_coverage.png'
plt.savefig(coverage_out, dpi=150)
plt.close()

# Plot duplication histogram
if 'BIN' in hist:
    y_label = 'all_sets' if 'all_sets' in hist else None
    y = hist.get('all_sets')
    if y is None:
        # fallback: first numeric column after BIN
        for col in hist_header:
            if col == 'BIN':
                continue
            if isinstance(hist[col][0], float):
                y_label = col
                y = hist[col]
                break
    if y is not None:
        plt.figure(figsize=(6, 4))
        plt.plot(hist['BIN'], y, marker='o', linewidth=1.2)
        plt.xlabel('CoverageMult (BIN)')
        plt.ylabel(y_label or '')
        title = 'Duplication Histogram'
        if 'PERCENT_DUPLICATION' in metrics:
            try:
                title += f" (PCT_DUP={float(metrics['PERCENT_DUPLICATION']):.3f})"
            except ValueError:
                pass
        plt.title(title)
        plt.tight_layout()
        dup_out = root / 'stage01_duplication_hist.png'
        plt.savefig(dup_out, dpi=150)
        plt.close()

print('Wrote:', coverage_out)
print('Wrote:', root / 'stage01_duplication_hist.png')
