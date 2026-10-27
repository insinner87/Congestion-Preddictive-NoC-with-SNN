# Full-mesh SNN training and accuracy

## Prediction task

The predictor consumes seven binary time/frequency/buffer events per candidate
mesh output, as defined in [feature_specification.md](feature_specification.md).
It predicts whether a severe congestion event will occur in the next eight
cycles. A severe event is four or more consecutive blocked cycles, or a full
two-entry downstream link FIFO while a request is present. Startup samples and
samples without eight complete future cycles are excluded through explicit
valid bits.

## Data provenance and split policy

`tools/generate_noc_traces.py` compiles and runs `sim/mesh/mesh_trace_tb.sv`
against the actual 4x4 mesh RTL. It records hardware feature signals and the
real outgoing link FIFO counts. Workloads are uniform random, fixed hotspot,
transpose, and bursty hotspot, at 30%, 60%, and 85% offered injection rates.
Training, validation, and test use disjoint traffic seeds. The untouched test
split is evaluated only after candidate parameters are selected on validation.
Raw traces are retained with SHA-256 checksums in
`validation/snn_experiment/manifest.json`.

The output CSV includes every trace row, including feature-invalid startup
rows and incomplete-horizon ending rows, with `feature_valid` and
`target_valid`; metrics mask both. Rows are grouped by run, router, and output,
so recurrent state is reset and advanced in the same order as the RTL.

## Model and training method

The deployed network is four hidden LIF neurons and one output LIF neuron per
router output. Seven binary events feed unsigned two-bit weights. Membranes
are bounded to 0..63, leak by one quarter (with a one-unit minimum decay for a
nonzero state), fire at integer thresholds, and reset by subtracting the
threshold. Routing risk is the RTL's `risk_class >= 2` decision, equivalent to
the output integrated potential reaching four.

`tools/train_noc_snn.py` uses reproducible simulated annealing over the small
quantized LIF parameter space. Each candidate is scored by the exact integer
inference recurrence used by `rtl/congestion/snn_predictor.sv`, avoiding a
surrogate-gradient export mismatch. The training objective balances accuracy,
congestion recall, and precision and penalizes recall below 70% or false
positive rate above 15%. Multiple restarts and a finite experiment limit are
configurable. Among high-scoring training candidates, validation chooses the
final checkpoint. `tools/export_snn_rtl.py` writes the selected parameters to
the synthesizable package.

## Acceptance gate and measured result

Acceptance requires all of: held-out accuracy at least 90%, congestion recall
at least 70%, and false-positive rate at most 15%. The 70% recall and 15% false
alarm limits are project detection targets chosen before final test evaluation.
The test output includes confusion counts, precision, recall, F1, FPR, FNR,
balanced accuracy, ROC-AUC, PR average precision, subgroup metrics by load,
workload, and candidate port, and measured prediction lead time.

The collected set contains 48 runs of 96 cycles each, with 73,728 raw rows.
After excluding invalid startup samples and incomplete eight-cycle horizons,
there are 31,104 training samples, 15,552 validation samples, and 15,552
untouched test samples. The test prevalence is 14.80% (2,302 congestion rows).
Training used seeds 1001 and 1002; validation used 2001; test used 3001. No
seed crosses splits. The reproducible run manifest and raw trace hashes are in
`validation/snn_experiment/manifest.json`.

The measured integer model is:

```text
hidden_weights = [[2,1,1,0,3,2,2], [0,0,0,2,1,2,0],
                  [0,2,2,2,1,0,0], [1,3,3,3,0,3,2]]
output_weights = [1,3,0,0]
hidden_threshold = 3; output_threshold = 1; potential_max = 63
```

It was selected after 1,000 parameter-search experiments and 10 restarts; no
retraining retry was required because validation met all three gates. Training,
validation, and test results are saved in
`validation/snn_experiment/accuracy_results.json`; the exported model is
`models/snn_trained.json` and its SystemVerilog parameters are in
`rtl/congestion/snn_model_parameters_pkg.sv`.

| Split | Samples | Positive rate | Accuracy | Precision | Recall | F1 | FPR | FNR |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Train | 31,104 | 14.69% | 97.90% | 94.22% | 91.33% | 92.75% | 0.96% | 8.67% |
| Validation | 15,552 | 14.80% | 97.22% | 91.66% | 89.35% | 90.49% | 1.41% | 10.65% |
| Held-out test | 15,552 | 14.80% | **96.28%** | 87.15% | **87.79%** | 87.47% | **2.25%** | 12.21% |

Test confusion matrix (rows are actual `[non-congested, congested]`, columns
are predicted `[non-congested, congested]`) is `[[12,952, 298], [281, 2,021]]`.
Test ROC-AUC is 0.9317 and PR average precision is 0.8237. Among measured
congestion episodes, mean lead time is 7.54 cycles and median is 8 cycles.
Episode recall is 90.65% for 1–4-cycle events, 96.00% for 5–8-cycle events,
and 84.62% for events lasting at least 9 cycles. Per-load/per-workload/per-port
metrics are retained in the JSON report. At 85% offered load, test accuracy is
94.85% and congestion recall is 87.30%.

The SNN passes the stated aggregate acceptance gates. Port-specific results
are uneven: North recall is 61.48% and West recall is 60.00%, below the 70%
aggregate recall target. The model is not equally reliable for every direction;
per-port false-alarm rates and sample counts remain in the JSON report.

## Interpretation limits

This task predicts a local candidate link's severe blocked/full-buffer event,
not end-to-end path latency. The traffic distribution is generated by this
repository's Icarus testbench and does not by itself establish generalization
to other topologies, routers, clock ratios, or real application traces. Rows
from one recurrent stream overlap in their forecast windows; all splits are
seed-disjoint, but per-cycle samples are not independent observations. An
accuracy pass is tied to this documented workload set and the hardware-equivalent
model parameters. The 96-cycle runs and single held-out seed also limit claims
about broader random traffic.
