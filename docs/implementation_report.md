# Implementation and measured results

**Status date:** 2026-10-25  
**Scope:** Full-mesh feature capture, quantized SNN training/evaluation, equation distillation, RTL integration, directed rerouting, and project regression.

## Result summary

The SNN was trained on actual 4x4 mesh RTL traces, not the older synthetic
signal generator. On 15,552 untouched test samples it achieved 96.28% accuracy,
87.79% congestion recall, 87.15% precision, and 2.25% false-positive rate.
This passes the 90% accuracy, 70% recall, and 15% false-alarm limits. Its test
class prevalence was 14.80%; a majority-only classifier would score 85.20%
accuracy and zero congestion recall.

The distilled equation achieved 96.70% held-out accuracy, 85.84% recall, 1.41%
false-positive rate, and 98.997% agreement with the trained SNN. The fixed-point
RTL matches the Python equation on randomized vectors. Both predictors are
connected to the actual West-First route-selection path. Directed simulation
observes downstream occupancy and blocked requests, predicts East risk, sends
a packet over the legal/ready North alternate, and verifies fallback when
North is unavailable.

The final 19-run Icarus regression passed with empty compile logs. The
equation-enabled 4x4 mesh delivered all 796 scored packets without drops,
duplicates, or corruption. On that one fixed-seed traffic scenario, equation
mode averaged 8.195 cycles and 0.3324 packets/cycle; the West-First baseline
averaged 8.196 cycles and the same throughput. This difference is too small
and too narrowly sampled to claim a performance improvement.

## Training and model artifacts

The trace set has 48 runs × 96 cycles, with 73,728 raw rows. Training uses
seeds 1001 and 1002; validation uses 2001; final testing uses 3001. Each split
covers 30%, 60%, and 85% offered injection rates with uniform, hotspot,
transpose, and bursty-hotspot traffic. Startup samples and incomplete H=8
future windows carry explicit invalid flags. Raw hashes, workload configuration,
simulator version, seed groups, and dataset hash are in
`validation/snn_experiment/manifest.json`.

The SNN has four hidden LIF neurons, one output LIF neuron, seven event inputs,
two-bit nonnegative weights, 0..63 membrane saturation, and integer leak and
threshold updates matching the synthesizable RTL. A bounded 1,000-candidate,
10-restart simulated-annealing search selected the model on validation; no
retry was needed. The exact learned weights are in `models/snn_trained.json`
and `rtl/congestion/snn_model_parameters_pkg.sv`. The accuracy JSON reports
train, validation, and test metrics, confusion matrices, ROC/PR area, load,
workload, direction, and congestion-duration breakdowns.

The fitted equation is:

```text
R = -15 + 3*x0 + x1 + 2*x2 + 4*x3 + 2*x4 + 16*x5 + 3*x6
predict congestion when R >= 0
```

`x0..x6` are the same binary features consumed by the SNN. The score uses
coefficients rounded at scale 4 and signed fixed-point RTL. See
`models/distilled_equation.json` and
`rtl/congestion/distilled_congestion_model_pkg.sv` for the generated constants.

## Main code and documentation changes

- Added `sim/mesh/mesh_trace_tb.sv` and `tools/generate_noc_traces.py` to capture real mesh requests, transfers, downstream link FIFO occupancy, temporal history, and frequency counts.
- Added `tools/train_noc_snn.py`, `tools/distill_noc_snn.py`, and SNN/equation RTL exporters; model checkpoints, the dataset, manifest, logs, and machine-readable metrics are under `models/` and `validation/snn_experiment/`.
- Extended `tf_feature_extractor.sv`, `snn_predictor.sv`, `noc_router_wrapper.sv`, `noc_mesh_4x4.sv`, and `mesh_link_fifo.sv` for seven feature events, actual link occupancy, independent feature-capture/routing enables, equation selection, and current-output readiness checks.
- Added `rtl/congestion/distilled_congestion_predictor.sv` and a generated coefficient package. `ENABLE_EQUATION_ROUTING` enables the distilled predictor; `validation/run-mesh.ps1 -EnableEquationRouting` runs it in the mesh.
- Added model-reference, randomized equation, directed equation-routing, and unavailable-alternate checks. Expanded `validation/run-all.ps1` and `run-project.ps1` to 19 runs.
- Updated feature, model, training, distillation, routing, verification, benchmark, and user documentation.

## Tests run

The final regression command was:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\validation\run-all.ps1 -OutputDirectory .\audit_report\snn-final-20261025-rerun
```

All 19 tests passed: feature extraction; adaptive-buffer pressure; offload
control; SNN behavior and 1,000-sample recurrence parity; 2,000 randomized
equation vectors; router and priority checks; 256 XY and 256 West-First route
pairs; directed SNN/equation rerouting; XY and West-First full-mesh packet
scoreboards; priority, baseline, SNN, and equation mesh configurations. All
compile logs are empty. Detailed logs are in
`audit_report/snn-final-20261025-rerun/` and the runner transcript is
`audit_report/snn-final-run.log`.

## Known limits

- Test-set North and West congestion recall is lower than the aggregate: SNN 61.48%/60.00%; equation 60.00%/38.95%. The overall gates pass, but the predictor is not equally reliable for every direction.
- The test split contains one unseen traffic seed, and the 96-cycle samples overlap in their H=8 windows. Seed-level separation prevents train/test leakage, but the samples are not independent evidence and broader multi-seed evaluation is needed.
- The recorded one-seed baseline/equation throughput and latency are effectively unchanged. No multi-seed ablation demonstrates a statistically meaningful network-level benefit.
- Adaptive-buffer control provides hysteretic pressure notification; it does not resize or change FIFO admission. The event-driven SNN state-update enable reduces idle state updates; no switching-activity proxy or measured power comparison was run.
- Verilator, Yosys, and Quartus were not available. There is no Cyclone IV EP4CE10 synthesis, resource, timing/Fmax, or physical power report.
- Simulations and the West-First legal-turn checks are not a formal proof of deadlock freedom, starvation freedom, or timing closure.

The accuracy gates and functional route demonstrations pass for the documented
feature and traffic domain. Broader hardware and statistical claims remain
unverified.
