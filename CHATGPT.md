# CHATGPT — Complete Project Context and Teaching Guide

> **Purpose:** Give a future AI assistant enough context to explain this
> repository, teach its owner, help reproduce experiments, and avoid making
> inaccurate claims. This is a guide to the project, not a replacement for the
> RTL, scripts, test logs, or detailed specifications. When they disagree,
> current source and the newest reproducible result take precedence.
>
> **Context updated:** 2026-10-27. The most recent training and validation
> actions described below happened in this session. Keep this file current when
> a later experiment changes results or repairs the trace-generation failure.

## 1. Instructions for an AI using this guide

The user is learning this project and may ask for explanations, commands,
debugging, or implementation help. Teach in clear steps; define technical
terms before using them heavily. Explain what each command does, what success
looks like, where outputs are saved, and what to do on failure. Do not promise
that a script or model works just because documentation says it should.

Important accuracy rules:

1. This is a SystemVerilog/Icarus Verilog NoC project with Python scripts for
   trace generation and model training/evaluation. It is not a software-only
   SNN demo.
2. The SNN predicts **local candidate output-link congestion**, not end-to-end
   packet latency, routing success, or all network failures.
3. Keep model classification accuracy, packet-integrity simulation, routing
   performance, and hardware implementation cost as separate claims.
4. Do not describe a normal regression pass as a fresh model accuracy run.
   `run-project.ps1` verifies RTL; `run-complete.ps1` generates traces and
   evaluates the checked-in model but does not train a new one.
5. A partial trace-generation run is a failure, even if it created some CSVs.
   Do not treat partial output as a valid new dataset.
6. Preserve held-out test seeds when tuning or retraining. Select a model on
   validation; evaluate the test split after selection.
7. Prefer a small focused validation first, but the currently observed
   full-suite command is `validation/run-project.ps1`.
8. Explain limitations: finite simulation, one held-out traffic seed in the
   documented dataset, overlapping prediction windows, weaker direction-wise
   recall, and no synthesis/area/power/timing or formal deadlock proof.
9. Several audit documents describe earlier project stages. Their results are
   dated evidence, not automatically the current state.

## 2. Quick identity card

- **Project name:** TF-PCR 4x4 NoC with time/frequency congestion features,
  an integer spiking neural network, an equation baseline, and optional
  adaptive predictor selection.
- **Hardware description:** SystemVerilog (`.sv`) RTL, simulated by Icarus
  Verilog (`iverilog` compiler and `vvp` runtime).
- **Mesh:** 4 by 4, sixteen router wrappers, five ports per router
  (North/South/East/West/Local).
- **Existing router:** Five input buffers/FIFOs, switch allocation,
  round-robin arbitration, crossbar, and ready/valid transfers.
- **Mesh flit:** 64 bits. The top three bits carry the mutable next hop;
  destination X/Y occupy the following four bits; remaining payload is
  otherwise opaque to the mesh routing logic.
- **Mesh routing:** XY deterministic reference and minimal West-First adaptive
  routing. Predictor risk can affect a legal choice in supported modes; it
  does not decide which turns are legal.
- **Learned model:** Four hidden LIF neurons and one output LIF neuron per
  candidate output; seven binary features; quantized integer inference.
- **Training implementation:** Python, NumPy, scikit-learn. Training uses
  reproducible bounded simulated annealing over integer LIF parameters.
- **Main user entry points:** `README.md`, `validation/run-project.ps1`,
  `validation/run-complete.ps1`, and the detailed documents in `docs/`.
- **Workspace path used in the latest run:**
  `C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp`.

## 3. What the project is trying to do

The project preserves a conventional input-buffered five-port router and
builds a 4x4 mesh out of sixteen routers. It adds several ways to observe or
respond to congestion:

1. **TF-PCR (time/frequency congestion reporting):** counts how long requests
   wait or outputs are blocked, and compares request-cycle demand with
   successful transfer service over a fixed window.
2. **Feature extraction:** turns recent request, service, blocked-time,
   downstream occupancy, and buffer-pressure observations into seven binary
   inputs.
3. **SNN prediction:** estimates whether a local candidate output will
   experience a defined severe congestion event during the next eight cycles.
4. **Distilled equation:** a compact fixed-point linear model fitted to mimic
   the SNN's decision.
5. **Adaptive selection (optional):** uses exact offline validation counts and
   delayed online labels to select the SNN only while it clears accuracy gates;
   otherwise it uses the equation.
6. **Route integration:** in West-First mode, a selected congestion risk can
   make the wrapper choose a lower-risk, legal, ready minimal next hop.
7. **Supporting controls:** optional adaptive-buffer pressure notification,
   congestion offload control, and priority arbitration.

The predictor is one signal in the route-choice path. It does not replace the
router's FIFOs, arbiter, crossbar, valid/ready protocol, destination routing,
or packet scoreboard.

## 4. Architecture: follow one flit through the design

### 4.1 RTL hierarchy

```text
noc_mesh_4x4
  16 x noc_router_wrapper (one per coordinate in the 4x4 grid)
    route candidate generation and next-hop field update
    TF-PCR monitor/estimator and feature extraction
    SNN and/or distilled equation, according to enabled parameters
    optional adaptive predictor selector / pressure / offload controls
    1 x router_5port
      5 x input_buffer / FIFO
      switch_allocator
        one output arbiter per output (round robin or optional priority)
      crossbar
  registered mesh_link_fifo instances between neighboring routers
```

### 4.2 Ready/valid movement

- An input flit is accepted on a clock edge when `in_valid && in_ready`.
- A router output transfer succeeds only when `out_valid && out_ready`.
- An asserted output/grant alone is **not** a completed transfer.
- Each input FIFO holds arriving flits. The allocator decodes the route
  request at each FIFO head.
- An arbiter grants no more than one input to an output. It holds a selected
  grant stable if downstream `ready` is low; the fairness pointer advances
  only after a successful transfer.
- The crossbar selects the granted FIFO head and pops that FIFO only when the
  output handshake succeeds.
- Independent outputs can transfer concurrently.
- Invalid standalone-router destination codes are dropped to avoid a bad FIFO
  head permanently blocking later traffic.

### 4.3 Flit formats and boundaries

- The standalone five-port router's default flit is 48 bits. Bits `[47:45]`
  encode one of five output ports; `[44:0]` are payload.
- The 4x4 mesh uses a 64-bit flit. Bits `[63:61]` encode the next-hop port and
  are rewritten at each router. Destination X/Y are bits `[60:57]` (two bits
  each); `[56:0]` are carried as opaque payload by routing.
- The current testbench uses payload bits as tags for scoreboarding; the RTL
  does not make those bits a network-wide application protocol.
- Mesh priority is a separate two-bit sideband aligned with each flit, not a
  change to the 64-bit payload.
- Each directed inter-router link uses a registered two-flit FIFO. Boundary
  links are not real links; the mesh ties boundary inputs/outputs off so they
  cannot be used as paths.

### 4.4 Routing rules

- **XY (`ROUTING_MODE=0`):** deterministic minimal route; horizontal movement
  occurs before vertical movement.
- **West-First (`ROUTING_MODE=1`):** minimal adaptive route subject to the
  standard West-First turn restriction. Westward progress must happen before
  turning North/South/East; when West is the destination direction, West is
  the only legal candidate.
- Route computation makes the legal candidate mask separately from
  congestion scoring. Prediction may rank only legal candidates.
- Deterministic preferred-hop ordering resolves equal scores. Invalid/reset
  predictor state falls back safely; it must not create an illegal turn.
- A route offered at an ingress is locked while that input transfer is
  stalled, so fluctuating scores cannot change the contents of a stalled
  valid/ready transaction.
- Congestion-based offloading means selecting a different legal next hop for
  an incoming flit. It does not move a packet already queued in a router,
  duplicate traffic, or create a new network port.

## 5. Congestion measurement and seven model inputs

### 5.1 TF-PCR measurement

For each output and input requester, the monitor records eligible
request-cycles. A request-cycle is not a unique packet arrival. Successful
service is counted only on an output handshake. Within the default 16-cycle
window:

```text
request_count = sum of asserted requester bits over the window
service_count = count of successful output transfers
deficit = max(request_count - service_count, 0)
```

Per-requester wait and per-output blocked cycles saturate instead of wrapping.
The estimator normalizes a time score and the most recently completed service
deficit to 0..255:

```text
time_score = max(normalized maximum requester wait,
                 normalized output blocked cycles)
deficit_score = normalized service deficit
score = floor((3*time_score + deficit_score) / 4)
predicted = score >= 128
```

Defaults weight time 3:1 over service deficit. This is a current/history
heuristic; it is not itself a self-contained eight-cycle forecast. The future
label used for SNN accuracy is separately defined by the experiment.

### 5.2 Features and their order

Each row is one interior router's physical output link at one sampled cycle.
Trace sampling focuses on routers 5, 6, 9, and 10 (the interior routers), and
the four directional outputs North through West. The downstream occupancy
comes from the actual two-flit link FIFO.

Feature index is the bit index, with feature 0 least significant:

| Bit | Feature | Meaning |
|---:|---|---|
| 0 | `blocked_streak_ge_2` | At least two consecutive cycles with a request but no successful output transfer. |
| 1 | `blocked_streak_ge_5` | At least five consecutive locally blocked cycles. |
| 2 | `request_cycles_ge_16` | At least 16 requester-cycles in the eight-cycle feature window (max 40). |
| 3 | `low_service_during_demand` | At least four demand-active cycles and at most two successful transfers in that window. |
| 4 | `downstream_occupancy_ge_depth_minus_1` | Current outgoing link occupancy is at least depth minus one; with depth two this means occupancy >= 1. |
| 5 | `recent_max_occupancy_ge_depth` | Link occupancy was full in the current/recent four-sample history. |
| 6 | `occupancy_rising_or_requester_buffer_pressure` | Occupancy rose from prior sample OR a currently requesting input has adaptive-buffer pressure. |

Feature validity remains false until the required event windows/history are
initialized. Invalid features reset/disable recurrent model state; they are
not treated as valid zero observations.

### 5.3 Prediction target and leakage prevention

For candidate output at sample `t`, the observed severe event is:

```text
event(t) = blocked_streak(t) >= 4
           OR (downstream_link_occupancy(t) >= 2 AND request_nonempty(t))
```

The target for `t` is positive if this event occurs at any point in `t+1`
through `t+8`. The prediction inputs at `t` do not contain future labels.
Training masks out feature-invalid startup rows and targets without a full
eight-cycle lookahead. Dataset splits are by disjoint traffic seeds; samples
inside one stream still have overlapping future windows and are not
statistically independent.

This is a local candidate-link risk label. It is not end-to-end packet latency
or a general guarantee of network congestion.

## 6. SNN, equation, and adaptive selection

### 6.1 SNN recurrence

The deployed network has four hidden leaky integrate-and-fire (LIF) neurons
and one output LIF neuron for each candidate output. The seven binary inputs
use unsigned two-bit weights (0..3). Membrane potentials are clamped to
0..63. For nonzero potential `v`, leak is `max(1, floor(v/4))`.

```text
v_leaked = v - leak(v)
v_sum = min(63, v_leaked + weighted binary inputs)
spike = (v_sum >= threshold)
v_next = spike ? v_sum - threshold : v_sum
```

Hidden spikes feed the output neuron in the same model evaluation. Output risk
classes are 0 below integrated potential 2, 1 from 2, 2 from 4, and 3 from 6.
Routing classifies risk 2 or 3 as congestion. The integer recurrence is the
same in the Python evaluator and synthesizable RTL; `snn-model-parity` checks
this correspondence.

The current trained model is in `models/snn_trained.json`; the generated RTL
weights and thresholds are in
`rtl/congestion/snn_model_parameters_pkg.sv`.

```text
hidden_weights =
  [[2,1,1,0,3,2,2],
   [0,0,0,2,1,2,0],
   [0,2,2,2,1,0,0],
   [1,3,3,3,0,3,2]]
output_weights = [1,3,0,0]
hidden_threshold = 3
output_threshold = 1
potential_max = 63
```

### 6.2 Training

`tools/train_noc_snn.py` loads CSV rows in recurrent groups keyed by split,
run, router, and output. It applies the exact integer inference recurrence,
searches quantized model parameters with reproducible simulated annealing,
selects candidates using validation, and evaluates the untouched test split
after selection. Defaults in the checked-in training script include seed
72631, 1,000 candidate experiments, 10 restarts, and up to two bounded
validation-driven retries.

The training objective balances accuracy, congestion recall, and precision;
it penalizes recall below 70% and false-positive rate above 15%. The documented
acceptance gate requires:

- test accuracy >= 90%;
- test congestion recall >= 70%;
- test false-positive rate <= 15%.

Do not silently change test seeds, scoring thresholds, or the target definition
when reporting comparable accuracy.

### 6.3 Distilled equation

`tools/distill_noc_snn.py` fits a compact equation to the exact SNN decisions,
selecting on validation; it is not an independent neural model. Current
documented equation:

```text
R = -15 + 3*x0 + 1*x1 + 2*x2 + 4*x3 + 2*x4 + 16*x5 + 3*x6
predict congestion when R >= 0
```

`models/distilled_equation.json` stores the equation and
`rtl/congestion/distilled_congestion_model_pkg.sv` stores generated constants.
`distilled-predictor` compares fixed-point RTL against randomized reference
vectors.

### 6.4 Runtime adaptive selection

The optional selector compares both SNN and equation on the same features.
It waits until the SNN's eight-cycle label matures before scoring it; future
ground truth is not provided as an input to the prediction. It requires at
least 32 online samples and maintains a rolling 64-sample window per output.
The SNN is selected only when offline validation accuracy and online rolling
accuracy are both **strictly greater than 90%**. Otherwise it falls back to
the equation.

When exact validation counts are provided, the comparison is integer exact:
`correct * 100 > total * 90`. An integer display of 90% is not sufficient.
Reason codes in documented selector behavior:

- `1`: SNN selected;
- `2`: offline validation accuracy at or below threshold;
- `3`: too few online matured samples;
- `4`: online rolling accuracy at or below threshold.

Selection events include initial selection and actual switches. The
standalone percentage parameter is a compatibility fallback when exact
counts are not supplied.

## 7. Additional controls

- **Adaptive buffer controller:** early pressure notification and hysteresis
  based on input FIFO occupancy. It does not resize FIFOs or change FIFO
  full/empty semantics.
- **Congestion offload controller:** asserts after persistent risk and releases
  after recovery according to its thresholds. Invalid/reset predictor state
  safely falls back. It does not migrate packets already inside a FIFO.
- **Priority arbitration:** optional two-bit class sideband (0 lowest, 3
  highest). With priority enabled, higher classes are considered first;
  round-robin breaks ties. Requests aged to the configured default threshold
  (16 cycles) get promoted. A stalled grant remains locked. Priority is
  disabled by default to preserve baseline behavior. The sideband stays
  aligned with the flit through router/link storage.
- These are simulation-tested policy mechanisms, not measured power savings,
  formal liveness proofs, or guarantees of bounded starvation under arbitrary
  downstream behavior.

## 8. Repository map

### Root files

- `README.md`: installation, standard commands, regressions, training, and
  directory map.
- `RUN_TURTORIAL.md`: prior run-specific step-by-step account. Its spelling is
  the existing filename; check dates and prefer this guide for the complete
  latest context.
- `CHATGPT.md`: this AI/learning guide.

### `rtl/`

- `common/noc_pkg.sv`: shared types, widths, port encoding, and constants.
- `router/`: `router_5port.sv`, `input_buffer.sv`, `fifo.sv`,
  `switch_allocator.sv`, `round_robin_arbiter.sv`, and `crossbar.sv`.
- `congestion/`: `congestion_monitor.sv` and `congestion_estimator.sv`
  implement TF-PCR; `tf_feature_extractor.sv` prepares events;
  `snn_predictor.sv` performs integer LIF inference;
  `snn_model_parameters_pkg.sv` contains generated learned constants;
  `distilled_congestion_predictor.sv` and
  `distilled_congestion_model_pkg.sv` implement the fixed-point equation;
  `adaptive_predictor_selector.sv`, `adaptive_buffer_controller.sv`, and
  `congestion_offload_controller.sv` implement optional controls.
- `mesh/`: `noc_mesh_4x4.sv` integrates the topology;
  `noc_router_wrapper.sv` connects route selection, predictors, and router;
  `mesh_route_compute.sv` produces legal route candidates;
  `mesh_link_fifo.sv` registers inter-router traffic.

### `sim/`

- `router/`: original router and priority arbiter testbenches, with
  `.svh` driver/checker/scenario fragments.
- `congestion/`: testbenches for TF-PCR, features, SNN, SNN parity,
  equation, adaptive selection, pressure, and offload control.
- `mesh/`: mesh and route-compute tests, directed SNN/equation routing tests,
  and trace-capture testbench. Mesh scoreboard/helper/scenario/watchdog and
  detector-evaluation fragments are split into `.svh` files.
- A passing simulation should exit zero and print its named `PASSED` marker.
  `$finish` alone is not sufficient evidence; `$fatal` means a check failed.

### `tools/`

- `generate_noc_traces.py`: compiles/runs the actual RTL trace testbench,
  records per-cycle feature/target observations and route decisions, checks
  accepted/delivered flit integrity, writes traces, dataset, and manifest.
- `train_noc_snn.py`: train, validate, and held-out test integer SNN models.
- `export_snn_rtl.py`: write selected model weights into SystemVerilog package.
- `distill_noc_snn.py`: fit equation to SNN decisions and report gates.
- `export_equation_rtl.py`: write equation constants into RTL package.
- `evaluate_noc_models.py`: evaluate frozen SNN/equation, subgroup metrics,
  optionally parse regression results, and write JSON/Markdown.
- `predictor_eval.py`: separate detector/benchmark evaluation helper; consult
  its CLI help and documentation before assuming it is the main training flow.
- `requirements-noc-snn.txt`: Python package requirements (NumPy and
  scikit-learn).

### `models/`

- `snn_trained.json`: machine-readable integer SNN weights/model parameters.
- `distilled_equation.json`: equation coefficients and threshold.

### `validation/`

- `run-router.ps1`: run one five-port router configuration.
- `run-mesh.ps1`: run an individual mesh configuration.
- `run-all.ps1`: low-level compile/simulate suite.
- `run-project.ps1`: full RTL regression with a pass/fail report.
- `run-complete.ps1`: full RTL + new trace generation + frozen-model evaluation
  workflow; it does not retrain.
- `snn_experiment/`: saved historical training dataset, manifest, and metrics.
- `results/`, `run/`: preserved logs and generated run directories; do not
  assume all old artifacts represent the same code revision.

### `docs/`

- `TF-PCR-VALIDATION.md`: score equations, routing, output-level baseline
  experiment, and results.
- `feature_specification.md`, `feature_and_signal_specification.md`:
  feature names, timing, valid flags, and signal sources.
- `snn_model_specification.md`, `snn_training_and_accuracy.md`,
  `snn_distillation.md`: SNN, training, metrics, and equation.
- `adaptive_predictor_selection.md`: delayed-label selector policy.
- `research_architecture.md`, `routing_and_offloading_policy.md`,
  `predictive_routing_integration.md`: architectural rationale and policy.
- `benchmark_methodology.md`, `verification_plan.md`: experimental design and
  verification intentions.
- `implementation_report.md`, `current_architecture_audit.md`: dated states.
- `README.md`: index.

### `audit_report/`

This contains multiple *dated* audit/verification reports and historical run
folders (`phase0` through later phases, old VVP binaries, logs, audit
summaries). Useful documents include `EXECUTIVE_SUMMARY.md`,
`SOURCE_CODE_AUDIT.md`, `CURRENT_IMPLEMENTATION_AUDIT.md`,
`END_TO_END_VERIFICATION.md`, `VERIFICATION_AUDIT.md`,
`NOVELTY_AND_PRIOR_ART.md`, `ATTRIBUTION_AND_PROVENANCE.md`,
`GO_NO_GO_ASSESSMENT.md`, and `ARTIFACT_INDEX.md`. Reports describing seven
or nineteen tests are older snapshots; check the current script/log before
using their count as the latest result.

## 9. How to run it on Windows

### 9.1 Requirements

- Windows PowerShell.
- Python 3.11 or newer (`py -3.11` launcher is convenient).
- Icarus Verilog compiler `iverilog` and runtime `vvp` on `PATH`.
- Python packages from `tools/requirements-noc-snn.txt`.

Observed in the latest session: Python 3.11.9, NumPy 2.4.6,
scikit-learn 1.9.1, Icarus 12.0 development build. These versions describe
that machine at that time, not an unconditional requirement.

### 9.2 First-time setup (PowerShell)

```powershell
Set-Location "C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp"
py -3.11 --version
Get-Command iverilog, vvp
py -3.11 -m venv "$env:TEMP\capstone-snn-venv"
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" -m pip install -r .\tools\requirements-noc-snn.txt
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" -c "import numpy, sklearn; print(numpy.__version__, sklearn.__version__)"
```

Create the virtual environment only once. If PowerShell cannot find
`iverilog`/`vvp`, install Icarus Verilog and reopen PowerShell so PATH updates.
Do not reinstall packages unless the environment is missing them.

### 9.3 Reproduce the full model-training and export sequence

Run each command in order and stop if any exits nonzero:

```powershell
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\generate_noc_traces.py
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\train_noc_snn.py
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\export_snn_rtl.py
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\distill_noc_snn.py
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\export_equation_rtl.py
```

This pipeline writes generated data under `validation/snn_experiment/`,
updates `models/snn_trained.json` and `models/distilled_equation.json`, and
exports constants under `rtl/congestion/`. Back up or version-control desired
model artifacts before rerunning training if you need to preserve them.

**Important current blocker:** on 2026-10-27, the fresh trace-generation
command failed during `train_s1001_l50_random`: the trace testbench reported
`flit 825 was corrupted or misrouted` at
`sim/mesh/mesh_trace_tb.sv:208`. Trace files had already been generated and
some raw files overwritten. Do not call a rerun of the full fresh-training
sequence successful until this integrity bug is understood and a complete
generation run exits zero with a coherent manifest/dataset.

### 9.4 Run all RTL regressions

From the project root:

```powershell
.\validation\run-project.ps1
```

By default the detailed report is
`validation/run/PROJECT-RESULTS.txt`; generated test directories are under
`validation/run/`. For a preserved named run:

```powershell
.\validation\run-project.ps1 `
  -OutputDirectory "validation\run\project-my-run" `
  -ReportPath "validation\run\PROJECT-RESULTS-my-run.txt"
```

The current script runs 21 compile/simulation configurations, stops on a
failure, and verifies a pass marker in every test log. The 21 names are:

1. `tfpcr-monitor`
2. `tf-feature-extractor`
3. `adaptive-buffer-controller`
4. `congestion-offload-controller`
5. `snn-predictor`
6. `adaptive-predictor-selector`
7. `snn-model-parity`
8. `distilled-predictor`
9. `router-enabled`
10. `router-disabled`
11. `priority-arbiter`
12. `mesh-routes`
13. `snn-routing`
14. `equation-routing`
15. `mesh-xy`
16. `mesh-west-first`
17. `mesh-west-first-priority`
18. `mesh-west-first-baseline`
19. `mesh-west-first-snn`
20. `mesh-west-first-equation`
21. `mesh-west-first-adaptive`

To pass measured exact SNN validation counts to the adaptive-selector test,
use `-SnnValidationAccuracyPercent`, `-SnnValidationCorrectSamples`, and
`-SnnValidationTotalSamples`. The exact counts are preferable to an integer
percentage.

### 9.5 Full trace-and-evaluation workflow

```powershell
.\validation\run-complete.ps1 `
  -PythonExecutable "$env:TEMP\capstone-snn-venv\Scripts\python.exe"
```

This script runs the 21 RTL tests, then generates a new seeded trace matrix,
evaluates the frozen models, derives the exact validation gate, reruns RTL
with those counts, and writes final reports into a timestamped
`validation/run/complete-*` directory. Defaults are 256 cycles, loads 5/50/95,
five traffic scenarios, two training seeds, one validation seed, and five
test seeds (120 trace runs total). This default run may be long.

It does **not** run `train_noc_snn.py` or modify the trained model. It has the
same trace-generation integrity blocker observed on 2026-10-27, so use it as
the intended complete workflow only after trace generation succeeds again.

### 9.6 Evaluate preserved model/data without retraining

If `validation/snn_experiment/dataset.csv` exists and is valid:

```powershell
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" `
  .\tools\evaluate_noc_models.py `
  --dataset .\validation\snn_experiment\dataset.csv `
  --output .\validation\run\predictor-evaluation.json
```

The evaluator checks for a `manifest.json` beside the dataset and attempts to
summarize the referenced raw traces. If the manifest/raw files are stale or
inconsistent, evaluation may fail even when the dataset itself is usable. To
isolate model metrics from that optional raw-trace summary, copy only the CSV
into a new directory without the old manifest:

```powershell
$evalDir = ".\validation\run\predictor-eval-isolated"
New-Item -ItemType Directory -Force -Path $evalDir | Out-Null
Copy-Item .\validation\snn_experiment\dataset.csv "$evalDir\dataset.csv" -Force
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" `
  .\tools\evaluate_noc_models.py `
  --dataset "$evalDir\dataset.csv" `
  --output "$evalDir\predictor-evaluation.json"
```

This isolation workaround was necessary after the partial 2026-10-27 trace
generation overwrote a subset of raw traces but left the old manifest in
place. It does not repair or validate that manifest.

### 9.7 Individual demonstrations

```powershell
.\validation\run-router.ps1
.\validation\run-router.ps1 -DisableTfPcr
.\validation\run-mesh.ps1 -Routing XY
.\validation\run-mesh.ps1 -Routing WestFirst
.\validation\run-mesh.ps1 -EnableSnnRouting
.\validation\run-mesh.ps1 -EnableEquationRouting
```

Check `validation/run-mesh.ps1 -?` and the root README for all available
switches, including priority, adaptive selection, exact validation counts,
seed, and TF-PCR enable/disable. Predictor modes are mutually exclusive where
the script documents that constraint.

## 10. Accuracy: current evidence and how to interpret it

### 10.1 Latest successful training/evaluation in this session

Fresh trace generation failed, but the pre-existing dataset CSV remained
intact. The SNN was trained again using that saved dataset, then exported.
Evaluation was run against an isolated copy of the dataset to avoid reading
raw-trace files that no longer matched the stale manifest.

| Split | Samples | Accuracy | Precision | Recall | F1 | False-positive rate |
|---|---:|---:|---:|---:|---:|---:|
| Train | 31,104 | 97.90% | 94.22% | 91.33% | 92.75% | 0.96% |
| Validation | 15,552 | 97.22% | 91.66% | 89.35% | 90.49% | 1.41% |
| Held-out test | 15,552 | **96.28%** | **87.15%** | **87.79%** | **87.47%** | **2.25%** |

The validation counts passed to the selector were 15,120/15,552 correct
(reported integer percentage 97%). The held-out test met the documented
aggregate gates. The experiment is tied to its saved dataset/seed/workload
domain. Test seed in the saved experiment is 3001; validation seed is 2001;
training seeds are 1001 and 1002.

Most recent output paths:

- `validation/snn_experiment/accuracy_results.json`: most recent training
  metrics/model selection output.
- `validation/snn_experiment/distillation_results.json`: equation training
  results.
- `validation/run/project-rerun-20261027/`: individual RTL regression output.
- `validation/run/PROJECT-RESULTS-rerun-20261027.txt`: full regression report.
- `validation/run/predictor-eval-rerun-20261027/predictor-evaluation.json`:
  isolated model evaluation with regression parsing.
- `validation/run/predictor-eval-rerun-20261027/predictor-evaluation.md`:
  readable metrics and routing summary.

### 10.2 Actual 2026-10-27 rerun outcome

- Python environment and dependencies were present.
- Icarus compiler and runtime were present.
- Fresh `generate_noc_traces.py` **failed** at the 50%-load random training
  case (`seed=1001`) because the testbench detected a corrupted/misrouted
  flit.
- Training from the pre-existing dataset completed.
- SNN RTL export completed.
- Equation distillation and equation RTL export completed.
- The full 21-test `run-project.ps1` run completed with exit code 0 and
  all 21 pass markers.
- Isolated frozen-model evaluation completed.
- Held-out SNN test result: 96.28% accuracy, 87.79% recall, 2.25% FPR.
- This was **not** a fully fresh end-to-end dataset regeneration. Be explicit
  about that distinction.

### 10.3 Caveats for accuracy claims

- A majority-only prediction would be misleading because class prevalence is
  about 14.8%; report recall, precision, FPR, confusion matrix, and F1 beside
  accuracy.
- Held-out test accuracy is not a performance improvement in packet latency
  or throughput.
- North and West direction recalls in the documented test are lower than the
  aggregate gate (about 61.48% and 60.00% in the documented SNN report).
- Eight-cycle samples overlap in time. Seed-disjoint splits prevent a traffic
  seed from appearing in two splits, but samples are not independent.
- The historical dataset contains 48 runs of 96 cycles and one test seed.
  Generalization to other workloads/topologies/real application traffic is
  not established.
- Older smoke reports may use different traffic matrices and sample counts;
  do not merge them with the 15,552-sample result.

## 11. Verification: what a passing regression means

The 21 RTL regressions exercise component behavior and packet/routing paths:

- TF-PCR monitor accounting, service deficit, score scaling, saturation,
  reset, and request withdrawal.
- Feature extractor windows, pressure/trend, service accounting, recovery,
  and reset.
- Adaptive-buffer hysteresis and congestion-offload persistence/recovery.
- LIF spikes/leak/reset and parity against independent integer recurrence.
- Delayed-label adaptive selector: exact offline threshold, sample warmup,
  no early future-label use, rolling accuracy fallback.
- Distilled equation parity against randomized fixed-point reference vectors.
- Original router enabled/disabled behavior, priority arbitration, and
  handshake stability under backpressure.
- All-pairs XY/West-First route legality and directed alternate selection.
- Directed SNN and equation routing.
- XY, West-First, priority, baseline, SNN, equation, and adaptive mesh
  configurations with packet integrity checks.

A passing simulation says the exercised finite test completed and assertions
passed. It does not prove all possible traffic, deadlock freedom, starvation
freedom, performance gains, or hardware timing.

An older saved full-mesh result reports 796 scored packets delivered with no
loss, duplicates, corruption, or unexpected flits in those simulations. A
single fixed-seed run showed nearly identical latency/throughput across
baseline and equation variants. Do not claim a statistically meaningful
network performance gain from those data.

## 12. What was assumed and what was not

### Assumptions made for the user-facing run guide

- The user wants a repeatable Windows PowerShell workflow because the project
  root and scripts are Windows/PowerShell-based.
- The existing project location is the path in the environment context.
- `CHATGPT.md` is an acceptable interpretation of “a file named CHATGPT”:
  a Markdown document with the requested base name.
- The current intended reference is the checked-in saved model/dataset and
  current source, not a theoretical claim that every trace run passes.

### Facts verified in the latest work

- Python 3.11.9, NumPy 2.4.6, scikit-learn 1.9.1 were usable in
  `%TEMP%\capstone-snn-venv`.
- `iverilog` and `vvp` were found; version output identified Icarus 12.0
  development build.
- The existing dataset, trained-model JSON, equation JSON, and RTL package
  files existed before the work.
- Trace regeneration failed with an integrity fatal at
  `mesh_trace_tb.sv:208`.
- Training, model exports, all 21 RTL regressions, and isolated evaluation
  succeeded afterward.
- The working tree showed no project-local changes before that run, though
  Git's detected root in this environment was the parent user directory.
  Do not clean or alter unrelated files outside the project.

### Not assumed/proven

- The partially overwritten raw traces are valid, complete, or checksum
  consistent with the old manifest.
- The trained model generalizes beyond the saved traffic distribution.
- RTL simulation provides a synthesis result or an FPGA implementation.
- TF-PCR/SNN routing improves overall network performance.
- The project is novel, patentable, or free of attribution concerns.
- A finite route regression constitutes a formal deadlock proof.

## 13. Research and implementation limits

- The model labels and traffic come from this repository's simulator; real
  application traces and other mesh sizes are not established.
- The test-set direction-wise metrics are uneven.
- The equation is distilled from the SNN and is not an independent learned
  comparator.
- Past baseline/equation metrics are close and use limited fixed-seed samples;
  no robust paired multi-seed performance advantage is established.
- No Quartus synthesis, resource count, Fmax/timing, or physical power report
  is available. Event-driven state-update behavior is not a measured power
  result.
- No formal verification of deadlock, starvation, or arbitrary-state
  correctness is reported.
- Audits raise provenance and novelty limitations; consult
  `audit_report/ATTRIBUTION_AND_PROVENANCE.md` and
  `audit_report/NOVELTY_AND_PRIOR_ART.md` rather than asserting originality.
- Older audit reports may describe earlier counts (7 or 19 regressions) and
  prior implementations. Current `validation/run-project.ps1` defines 21.

## 14. Recommended way to teach the owner

Teach in this order; after each section, ask the learner to explain the data
flow back in their own words, rather than dumping every detail at once:

1. **Digital design basics:** bits, clocked state, reset, ready/valid,
   synchronous FIFOs.
2. **One router:** input FIFOs -> request matrix -> allocator/arbiters ->
   crossbar -> output handshake.
3. **Network topology:** coordinates, destination fields, XY, West-First,
   minimal routes, link FIFOs, boundary ports.
4. **Congestion measurement:** requester-cycle vs packet-arrival, blocked
   cycles, completed service windows, normalized score.
5. **Supervised learning dataset:** input observations at time `t`, event
   labels from `t+1..t+8`, invalid windows, grouped recurrent sequences, and
   seed-disjoint splits.
6. **Integer SNN:** binary spikes, weights, membrane integration, leak,
   threshold/reset, risk classes; hand-calculate one small example.
7. **Model training:** why integer-exact inference is used, validation vs test,
   accuracy vs recall/precision/FPR, class imbalance.
8. **Hardware integration:** feature bus -> SNN/equation -> risk on legal
   routes; distinguish prediction from arbitration.
9. **Adaptive selector:** delayed target maturation, exact gate, 32-sample
   warmup, 64-sample rolling window, equation fallback.
10. **Verification and claims:** what each of the 21 tests proves and does not
    prove; how to read logs and identify `$fatal`.
11. **Research next steps:** fix trace integrity failure first; then regenerate
    all data and manifest; evaluate broader seeds/workloads; preserve a locked
    test set; consider synthesis and formal checking only when tool flows are
    available.

Useful conceptual distinction:

```text
RTL regression success = tested hardware behavior passed.
SNN accuracy = classified held-out local congestion labels correctly.
Packet scoreboard success = tested packets arrived intact in that simulation.
Performance benefit = paired traffic measurements show meaningful improvement.
Hardware cost = synthesis/timing/power evidence.
```

These are different outcomes and require different evidence.

## 15. Canonical project documents and how to use them

Start with `README.md` for supported commands. Use
`docs/feature_specification.md` for precise inputs/labels,
`docs/snn_model_specification.md` for LIF details,
`docs/snn_training_and_accuracy.md` for training/result context,
`docs/adaptive_predictor_selection.md` for online policy, and
`docs/TF-PCR-VALIDATION.md` for baseline estimator and routing semantics.
Use `validation/run-project.ps1` and its latest report as the authority for
current regression scope and result. Use `audit_report/` for dated
investigation, implementation-history context, novelty caveats, and prior
verification. Check file timestamps and the actual current RTL before
repeating historical statements.

## 16. Immediate next action

The next engineering task should be to diagnose the reproducible trace
integrity failure in the 50%-load random trace case and establish whether the
issue is in traffic generation, mesh routing/handshake behavior, or the
testbench scoreboard. A valid fix should:

1. reproduce the exact failing command and seed in isolation;
2. inspect the reported tag, expected destination, and observed ejection;
3. determine whether an RTL transfer is actually misrouted or the scoreboard
   expectation is wrong;
4. add a focused regression reproducing the defect;
5. make the smallest correct code/test change;
6. rerun that case, the full trace generator, and all 21 RTL regressions;
7. regenerate dataset and manifest together only after all trace runs pass;
8. retrain/evaluate on the new data and record new held-out metrics;
9. update this document and relevant source documentation with observed
   results, while preserving old evidence and seed separation.

