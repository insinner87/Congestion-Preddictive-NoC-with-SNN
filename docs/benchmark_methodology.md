# Benchmark methodology

## Baseline and fixed experimental conditions

The current baseline uses a 4x4 mesh, router FIFO depth 4, link FIFO depth 2, one-flit 64-bit mesh packets, and testbench seed `0x4f1bc2d7`. The 2026-10-25 fresh run delivered 796 packets per mesh configuration with mean latency 8.196 cycles and throughput 0.3324 packets/cycle. It used one serialized all-pairs phase, directed concurrency/hotspot/backpressure phases, and one deterministic random traffic sequence. These measurements are a baseline record, not a statistical comparison.

Future ablations must use matched source/destination sequence, packet count, injection pattern, seed group, warm-up interval, and measurement window. Separate tuning seeds from held-out evaluation seeds. Record offered load, burst shape, packet length (currently one flit), topology, FIFO depths, mode parameters, and simulator version in each CSV row. Use the same drain condition and discard any declared warm-up cycles consistently.

## Required configuration matrix

| ID | Configuration |
|---|---|
| A | Original deterministic XY. |
| B | Existing West-First with current TF-PCR disabled/enabled baseline recorded separately. |
| C | New time/history features only. |
| D | New event-rate features only. |
| E | Combined features without SNN. |
| F | Combined features with SNN. |
| G | F plus adaptive buffer pressure/control. |
| H | F plus predictor activity-update enable. |
| I | F plus persistent offloading and priority-aware arbitration. |
| J | Final integrated supported configuration. |
| K | Distilled equation with West-First legal-path selection, priority, and adaptive buffer pressure enabled. |

`validation/results/baseline_metrics.csv` contains the measured one-seed baseline configurations. `integration_metrics.csv` records the priority-only and integrated SNN + adaptive buffer notification + offload + priority runs from `audit_report/phase6-20261025/`. Both deliver 796 packets; priority-only averages 8.195 cycles and the integrated run 8.195 cycles, with throughput 0.3324 packets/cycle in both. These fixed-seed tests check integrity and legal routing, not SNN prediction accuracy or statistically meaningful performance differences. The `snn-routing` wrapper test demonstrates route influence but is not a traffic benchmark or prediction-quality evaluation.

## Full-mesh predictor and equation measurements

The actual-RTL training/validation/test traces use 48 configurations of 96
cycles, seeds 1001/1002 for training, 2001 for validation, and 3001 for held-out
testing, at 30%, 60%, and 85% offered load under uniform, hotspot, transpose,
and bursty-hotspot traffic. Prediction quality is reported separately from the
mesh throughput scoreboard because forecast samples overlap. Held-out SNN
accuracy is 96.28%, with 87.79% recall and 2.25% FPR; the equation is 96.70%
accurate with 85.84% recall, 1.41% FPR, and 98.997% agreement with the SNN.
North/West recall is lower and is documented in the model reports.

In the same fixed-seed 796-packet mesh scoreboard, West-First baseline mean
latency is 8.196 cycles at 0.3324 packets/cycle; trained-SNN and distilled-
equation configurations each measure 8.195 cycles at 0.3324 packets/cycle.
This single-seed difference does not demonstrate a useful performance gain.
The broad matched multi-seed ablation matrix remains to be run. No value is
reported as a physical power or FPGA timing estimate.

## Metrics and definitions

- Packet latency: cycles from accepted local injection to accepted local ejection; report mean and a documented tail percentile (start with p95).
- Throughput: delivered packets divided by measured mesh cycles; also report offered load and packet loss/timeout count.
- Congestion duration: blocked output-cycles under the explicit `request && !transfer` definition.
- Prediction: confusion matrix, precision, recall, FPR, FNR, and lead cycles for the sustained-block label. Count event-level onset detection separately from per-cycle samples.
- Offloading: alternate legal-hop selections divided by accepted ingress flits, plus trigger and recovery counts.
- Fairness: service count and maximum wait by priority class/input under stated downstream-ready assumptions.
- Power: report measured power only with a reproducible device/tool flow; otherwise report an exact RTL/simulation activity proxy such as predictor enabled updates and changed state bits, clearly labeled as a proxy.
- Hardware: report logic cells, registers, memory, and maximum clock frequency against EP4CE10 limits only from a device-specific synthesis/timing report.

## Repetition and output

Use multiple independent seeds per offered-load point and report mean plus confidence intervals or per-seed samples. Freeze model weights and thresholds before final evaluation. Store machine-readable results with the actual configuration, tool versions, seed, packet count, and log path. Do not fill missing values with estimates and do not claim a gain when confidence and scope are insufficient.
