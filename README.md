# TF-PCR 4x4 NoC

This project preserves the original five-port router and builds a 4x4 mesh
from 16 instances of it. It includes TF-PCR congestion diagnostics, an XY
reference route, a West-First adaptive route, and self-checking simulations.

For the RTL definitions, routing rationale, prediction-event definition, and
previously measured detector results, see
[docs/TF-PCR-VALIDATION.md](docs/TF-PCR-VALIDATION.md).

The full-mesh predictive model pipeline and its measured accuracy are described
in [docs/snn_training_and_accuracy.md](docs/snn_training_and_accuracy.md),
with the seven hardware-visible signals defined in
[docs/feature_specification.md](docs/feature_specification.md).

## Run scripts

Use Windows PowerShell with Icarus Verilog (`iverilog` and `vvp`) installed.
You can start these scripts from any working directory:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp\validation\run-router.ps1"
powershell -ExecutionPolicy Bypass -File "C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp\validation\run-mesh.ps1"
powershell -ExecutionPolicy Bypass -File "C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp\validation\run-project.ps1"
powershell -ExecutionPolicy Bypass -File "C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp\validation\run-complete.ps1"
```

Run **only the first** to validate the original five-port router. It runs
with TF-PCR enabled by default; add `-DisableTfPcr` to run the disabled
baseline instead.

Run **only the second** to validate the 4×4 mesh. It uses West-First adaptive
routing with TF-PCR enabled by default. Add `-Routing XY` for deterministic
XY routing, `-DisableTfPcr` to turn off the diagnostics, `-EnablePriority` to
enable priority arbitration, `-EnableSnnRouting` to use the trained SNN, or
`-EnableEquationRouting` to use the distilled fixed-point predictor.
`-EnableAdaptivePredictor -SnnValidationAccuracyPercent 97` enables the
eight-cycle, rolling-accuracy SNN/equation policy; standalone runs can instead
pass exact `-SnnValidationCorrectSamples` and `-SnnValidationTotalSamples`.
These three predictor modes are mutually exclusive. Use `-Seed <integer>` to set the deterministic random
traffic seed for paired mesh runs. The mesh summary reports average, p95, and
p99 packet latency, throughput, blocked output cycles, congestion duration,
and alternate hops during the seeded phase. These individual scripts compile
and simulate only the selected design.

Run **only the third** for the 21-test RTL regression. It writes a PASS/FAIL
summary and detailed simulator output to `validation\run\PROJECT-RESULTS.txt`.

Run **only the fourth** for the complete reproducible workflow. It runs the
21 RTL tests, then generates no-congestion, random, moderate, severe, and
mixed traffic on disjoint train/validation/test seeds, drains and scoreboards
all accepted flits, records route decisions and per-cycle congestion features,
and evaluates the checked-in frozen SNN/equation without changing model files.
Results are stored in a timestamped `validation\run\complete-*` directory as
trace CSVs, a manifest, predictor-evaluation JSON, and a readable Markdown
summary. Defaults use 256 trace cycles, three load settings, two training
seeds, one validation seed, and five held-out test seeds. Python 3.11+ with
NumPy and scikit-learn, plus Icarus Verilog, are required. Adjust run cost with
`-TraceCycles`, `-Loads`, `-TestSeeds`, or `-OutputDirectory`.

Create the Python environment once before the full experiment if it does not
already exist; `run-complete.ps1` automatically uses this environment:

```powershell
py -3.11 -m venv "$env:TEMP\capstone-snn-venv"
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" -m pip install -r tools\requirements-noc-snn.txt
```

All scripts locate the project files relative to their own location. The
runner stops and reports an error if Icarus Verilog is unavailable or a
compile/simulation fails.

Priority is a two-bit sideband paired with each flit; the 64-bit mesh flit
stays unchanged. Priority arbitration is off by default. Use `-EnablePriority`
with `run-mesh.ps1` or enable `ENABLE_PRIORITY` in the mesh parameters to test
classes 0 through 3, round-robin tie handling, and age promotion.

## What the regressions check

| Regression | What to check for |
|---|---|
| `tfpcr-monitor` | `TF-PCR MONITOR TESTS PASSED`; request withdrawal, requester waits, blocked-cycle counts, window boundaries, service deficit, normalization, saturation, and reset |
| `tf-feature-extractor` | `TF FEATURE EXTRACTOR TESTS PASSED`; pressure, persistence, trend, window snapshots, service deficit, and reset |
| `adaptive-buffer-controller` | `ADAPTIVE BUFFER CONTROLLER TESTS PASSED`; early occupancy notification, persistence, recovery hysteresis, and reset |
| `congestion-offload-controller` | `CONGESTION OFFLOAD CONTROLLER TESTS PASSED`; transient suppression, persistent trigger, recovery, and invalid-predictor fallback |
| `snn-predictor` | `SNN PREDICTOR TESTS PASSED`; LIF spikes, leak/recovery, reset, and idle update gating |
| `adaptive-predictor-selector` | `ADAPTIVE PREDICTOR SELECTOR TESTS PASSED`; eight-cycle delayed labels, offline/online 90% gates, and equation fallback |
| `snn-model-parity` | Random recurrent samples match an independent integer-LIF reference using the exported model package |
| `distilled-predictor` | 2,000 randomized port-vectors match the exported equation's signed fixed-point reference |
| `equation-routing` | Measured East congestion leads to a legal, ready North route; unavailable-alternate fallback is also checked |
| `priority-arbiter` | `PRIORITY ARBITER TESTS PASSED`; class ordering, round-robin ties, aging, and stalled-grant stability |
| `router-enabled` | `ALL TESTS PASSED (710 stage/transfer check points)` |
| `router-disabled` | Same 710 checks pass; diagnostic outputs stay disabled without changing baseline transfers |
| `mesh-routes` | `ROUTE TESTS PASSED`; all source/destination pairs in XY and West-First plus legal adaptive choices, deterministic ties, and unavailable-alternate fallback |
| `snn-routing` | `SNN ROUTING INTEGRATION TESTS PASSED`; persistent risk triggers a legal alternate next hop while a competing flit remains stalled |
| `mesh-xy` | `ALL MESH TESTS PASSED`; 256 source/destination pairs, handshakes, packet integrity, boundary behavior, backpressure, and traffic scenarios |
| `mesh-west-first` | Same packet checks plus legal West-First adaptive decisions using TF-PCR scores |
| `mesh-west-first-priority` | West-First full-mesh packet checks with priority arbitration enabled |
| `mesh-west-first-baseline` | Same legal West-First path checks with TF-PCR disabled |
| `mesh-west-first-snn` | Full-mesh packet checks with priority, SNN routing, adaptive buffer pressure, and offload enabled |
| `mesh-west-first-equation` | Full-mesh packet checks using the distilled equation with priority and adaptive buffer pressure enabled |
| `mesh-west-first-adaptive` | Full-mesh packet checks with online SNN/equation selection, delayed labels, model-switch counts, and flit-integrity reporting |

Each simulation writes a `<test-name>.log` transcript. Mesh runs also print
packet count, average latency, throughput, and TF-PCR versus occupancy-only
detector diagnostics. Those mesh metrics are not SNN prediction-accuracy
results. A passing simulation should exit with status zero and print its
corresponding `PASSED` line. Any `$fatal` identifies a failed
assertion; compilation warnings should be investigated rather than ignored.

The original router waveform and summary files are generated in that test's
own run directory. Open a `.vcd` file with GTKWave (or another VCD viewer) to
inspect signal-level behavior. Verify a ready/valid transfer using
`valid && ready`; a grant without `ready` is not a successful transfer.

## Train and export predictive models

The reproducible training environment needs Python 3.11 or newer, NumPy,
scikit-learn, Icarus Verilog, and VVP. From the project root, run:

```powershell
py -3.11 -m venv "$env:TEMP\temporal-snn-venv"
& "$env:TEMP\temporal-snn-venv\Scripts\python.exe" -m pip install -r tools\requirements-noc-snn.txt
& "$env:TEMP\temporal-snn-venv\Scripts\python.exe" tools\generate_noc_traces.py
& "$env:TEMP\temporal-snn-venv\Scripts\python.exe" tools\train_noc_snn.py
& "$env:TEMP\temporal-snn-venv\Scripts\python.exe" tools\export_snn_rtl.py
& "$env:TEMP\temporal-snn-venv\Scripts\python.exe" tools\distill_noc_snn.py
& "$env:TEMP\temporal-snn-venv\Scripts\python.exe" tools\export_equation_rtl.py
```

The trace generator partitions seeds before training, records actual link FIFO
occupancy and router events, and labels only complete future windows. Training
uses an exact integer-LIF evaluator. Distillation fits a seven-input linear
equation to that trained model and emits fixed-point SystemVerilog constants.
Use `validation/snn_experiment/accuracy_results.json` and
`distillation_results.json` for the machine-readable held-out gates. A failed
gate remains a failure; retrain with a larger bounded search budget and keep
the test seeds untouched.

To evaluate the checked-in SNN and equation on an existing or newly generated
dataset without training or changing model files, run
`& "$env:TEMP\temporal-snn-venv\Scripts\python.exe" tools\evaluate_noc_models.py --dataset <dataset.csv> --output <report.json>`
after creating the training environment above.
The report includes per-seed and workload/load/direction metrics plus
validation-only prediction-threshold sweeps.
For the runtime SNN/equation selection behavior and its validation-accuracy
input, see [docs/adaptive_predictor_selection.md](docs/adaptive_predictor_selection.md).

## Directory map

| Directory | Contents |
|---|---|
| `rtl\common\` | Shared package and definitions |
| `rtl\router\` | Original five-port router, FIFOs, allocator, arbiters, and crossbar |
| `rtl\congestion\` | TF-PCR monitor/estimator, seven-event features, trained SNN, fixed-point distilled predictor, adaptive buffer pressure, and offload controller |
| `rtl\mesh\` | 4x4 integration, router wrapper, link FIFO, and route computation |
| `sim\router\` | Original-router regression harness and included check/driver/scenario files |
| `sim\congestion\` | Standalone monitor testbench |
| `sim\mesh\` | Mesh, route-compute, and detector-evaluation testbenches |
| `docs\` | Detailed design and validation report |
| `validation\results\` | Preserved validation transcripts and legacy artifacts |
| `validation\run\` | New generated executables, logs, and waveforms |
| `tools\` | Full-mesh trace generation, integer SNN training/evaluation, equation distillation, and RTL exporters |

Each source and simulation directory has its own README describing the files
it contains. Icarus Verilog was used for simulation. No synthesis result is
claimed; a synthesis tool was not available in the validated environment.
