# SNN-assisted TF-PCR NoC research validation

**Run date:** 2026-10-25  
**Scope:** reproducibility, frozen-model generalization, routing value, testbench instrumentation, and synthesis availability.  
**Conclusion:** RTL predictor functions and routing integration pass simulation, but these runs do not demonstrate a useful network-level improvement. No model parameters were changed or selected using the new test seeds.

## Executive summary

| Area | Result |
|---|---|
| Existing data/model reproduction | The 48 original traces, all per-trace hashes, complete dataset hash, SNN RTL export, and equation RTL export reproduced exactly in separate output folders. |
| Original held-out prediction result | Confirmed: SNN accuracy 96.277%, equation accuracy 96.701%, agreement 98.997%. The original test split uses only seed 3001 across its workload/load cases. |
| Additional unseen-seed test | Two new, disjoint seeds (4001, 4002), four traffic patterns, three loads, 96 cycles: 31,104 valid samples. Frozen SNN accuracy 97.045%; equation 97.068%. These are correlated cycle/port observations from only two independent seeds, not 31,104 independent trials. |
| RTL verification | Final 19-test Icarus regression passed. This includes 1,000 recurrent SNN reference samples, 2,000 equation vectors, route legality, and full-mesh packet integrity. |
| Paired network performance | West-First, SNN, and equation builds were run on the same ten seeds with priority/adaptive-buffer/offload disabled. All reported latency, throughput, blocked-cycle, and random-phase alternate-hop results matched at the runner's output precision. |
| Statistical claim | No performance gain is established. Paired differences rounded to zero, so the resulting degenerate paired interval is not evidence of equivalence or significance. Higher-resolution measurements and more demanding network-load tests are needed. |
| FPGA implementation | Not synthesized. Quartus/Yosys/Verilator and project timing/device constraints were unavailable. |

## Phase 1 — Reproducibility and causality

### Dataset split and trace reproduction

The checked-in baseline manifest describes 48 simulations: training seeds
`1001,1002`, validation seed `2001`, and test seed `3001`; each seed is run at
loads 30%, 60%, and 85% with uniform, hotspot, transpose, and bursty traffic.
Each run records the four center routers (5, 6, 9, 10), their four physical
candidate outputs, and 96 cycles. The dataset has 73,728 rows; metrics mask
feature-invalid rows and the incomplete H=8 label tail.

The baseline was regenerated under `validation/run/research-audit/reproducibility/`
without changing the checked-in baseline data. All 48 raw CSV SHA-256 values
matched their original manifest entries, and the regenerated dataset hash
matched exactly:

```text
baseline dataset SHA-256:
470cc840113dc7ce5af86f0a4378d0e82433f559cf763c29bd7254fd6c627150
regenerated dataset SHA-256:
470cc840113dc7ce5af86f0a4378d0e82433f559cf763c29bd7254fd6c627150
raw trace hashes matched: 48/48
```

The original manifest's simulator-version field was null. The regenerated
manifest records Icarus Verilog and VVP 12.0 (development build
`s20150603-1539-g2693dd32b`), correcting that metadata gap in the new audit
artifacts without overwriting the original.

### Models, exports, and RTL/reference parity

The checked-in parameter packages were regenerated from the JSON model files
into the audit output folder and compared byte-for-byte:

| Artifact | Regeneration |
|---|---|
| `models/snn_trained.json` → SNN RTL package | Exact match; package SHA-256 `28ff8b4db269f7ad36eaFF0f5706cb49c2471ef58098b7c02ece00a8bb468e13` |
| `models/distilled_equation.json` → equation RTL package | Exact match; package SHA-256 `83971f8f9354900b72b503a1dc97db5a49daae39cba5b64f7f0827b5bced3cfc` |

The final regression independently checked 1,000 recurrent integer-LIF SNN
samples against a reference and 2,000 randomized equation vectors against
the exported coefficients. Both passed. The frozen model files are
`models/snn_trained.json` (SHA-256
`e07e6ffd0f0b2075db64f740044d1e42b78ba2a44bf9a72e8769c934d5c1e8f0`) and
`models/distilled_equation.json` (SHA-256
`4ba7b9982fa5008d3c6e86676de93f8ba09fcff3cd60e1d6122afa1e7186823f`).

### H=8 target, observation windows, and leakage check

For a sample at cycle `t`, the label is true if the congestion event occurs
in any of cycles `t+1` through `t+8`. The generator computes that label from
the future event rows only after traces are complete. `train_noc_snn.infer`
consumes the feature vector and valid bit; it does not consume target,
future-event, or split metadata.

All model inputs are current or historical observations:

- blocked streak is based on current/past request and transfer behavior;
- request/service counts are snapshots of the completed aligned eight-cycle
  window, refreshed at each eight-cycle boundary (not an FFT frequency and
  not a continuously rolling window);
- occupancy trend uses the current sample and four-sample history;
- link occupancy and requester-buffer pressure are current hardware state.

In the 96-cycle baseline raw trace, the first feature-valid row is cycle 8.
`target_valid` excludes the final eight rows, so metrics use feature-valid
cycles 8 through 88 (81 samples per stream). The SNN is recurrent, but resets
its state while features are invalid. The source review and trace timing show
no future feature leakage; the H=8 future slice is used only for labels.

### Exact reproduction commands

From the project root, baseline trace reproduction can be repeated without
overwriting the checked-in artifacts:

```powershell
py -3.11 tools\generate_noc_traces.py `
  --data-dir validation\run\research-audit\reproducibility `
  --cycles 96
```

The new two-seed test dataset and frozen-model evaluation were produced with:

```powershell
py -3.11 tools\generate_noc_traces.py `
  --data-dir validation\run\research-audit\generalization `
  --cycles 96 --train-seeds= --validation-seeds= `
  --test-seeds=4001,4002 --loads=30,60,85 `
  --workloads=uniform,hotspot,transpose,bursty

& "$env:TEMP\noc-research-validation-venv\Scripts\python.exe" `
  tools\evaluate_noc_models.py `
  --dataset validation\run\research-audit\generalization\dataset.csv `
  --output validation\run\research-audit\generalization\model-evaluation.json
```

The generalization dataset has 36,864 raw rows and SHA-256
`e127078d0919563ec3f41ca59a0f12f28b316bba52190dbdd2c1ca525123ed83`.
Its manifest has no training or validation seeds and lists only the two new
test seeds.

## Phase 2 — Generalization

Metrics below use the frozen checked-in SNN and equation. No training,
distillation, or threshold adjustment used seeds 4001 or 4002. PR-AUC is
average precision. Confusion matrices are `[[TN, FP], [FN, TP]]`.

### Original test versus additional independent seeds

| Test set | Model | Samples | Accuracy | Precision | Recall | F1 | FPR | PR-AUC | Confusion matrix |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| Original seed 3001 | SNN | 15,552 | 96.277% | 87.150% | 87.793% | 87.470% | 2.249% | 0.8237 | `[[12952,298],[281,2021]]` |
| Original seed 3001 | Equation | 15,552 | 96.701% | 91.355% | 85.838% | 88.511% | 1.411% | 0.9205 | `[[13063,187],[326,1976]]` |
| Seeds 4001, 4002 | SNN | 31,104 | 97.045% | 90.746% | 89.730% | 90.235% | 1.642% | 0.8550 | `[[25939,433],[486,4246]]` |
| Seeds 4001, 4002 | Equation | 31,104 | 97.068% | 93.508% | 86.750% | 90.002% | 1.081% | 0.9338 | `[[26087,285],[627,4105]]` |

SNN/equation agreement was 98.997% on the original seed and 99.071% over
the two added seeds. The added results support that both frozen models work
on these new seeds, but only two independent seeds are insufficient to
establish broad traffic-distribution generalization or a tight seed-level
confidence interval.

### Results by workload and offered load (new two-seed set)

| Group | Model | Accuracy | Precision | Recall | F1 | FPR | PR-AUC |
|---|---|---:|---:|---:|---:|---:|---:|
| 30% load | SNN | 99.431% | 97.801% | 96.091% | 96.938% | 0.223% | 0.9245 |
| 30% load | Equation | 99.306% | 97.771% | 94.753% | 96.238% | 0.223% | 0.9677 |
| 60% load | SNN | 96.586% | 88.903% | 88.903% | 88.903% | 2.018% | 0.8262 |
| 60% load | Equation | 96.692% | 91.901% | 86.082% | 88.896% | 1.379% | 0.9233 |
| 85% load | SNN | 95.120% | 88.962% | 87.483% | 88.216% | 2.865% | 0.8070 |
| 85% load | Equation | 95.206% | 92.682% | 83.649% | 87.934% | 1.743% | 0.9264 |
| Bursty | SNN | 99.704% | 99.238% | 99.169% | 99.203% | 0.174% | 0.9813 |
| Bursty | Equation | 99.614% | 99.234% | 98.684% | 98.958% | 0.174% | 0.9983 |
| Hotspot | SNN | 99.151% | 98.624% | 96.892% | 97.751% | 0.318% | 0.9539 |
| Hotspot | Equation | 99.138% | 98.960% | 96.486% | 97.708% | 0.238% | 0.9922 |
| Transpose | SNN | 95.216% | 85.714% | 81.250% | 83.422% | 2.355% | 0.7696 |
| Transpose | Equation | 94.766% | 88.521% | 74.306% | 80.793% | 1.676% | 0.7780 |
| Uniform | SNN | 94.110% | 64.348% | 67.683% | 65.973% | 3.455% | 0.5161 |
| Uniform | Equation | 94.753% | 72.794% | 60.366% | 66.000% | 2.079% | 0.5992 |

Uniform and transpose traffic remain materially harder than hotspot/bursty
traffic. Overall accuracy alone hides that difference.

### Lead time and event-duration strata (new two-seed set)

| Model | Detected events | Mean lead | Median lead |
|---|---:|---:|---:|
| SNN | 743 | 7.538 cycles | 8 cycles |
| Equation | 735 | 7.479 cycles | 8 cycles |

There were 711 short (1–4 cycle), 58 medium (5–8 cycle), and 39 long (9+ cycle)
event episodes. SNN episode recall was 91.70%, 93.10%, and 94.87% respectively;
equation episode recall was 90.58%, 93.10%, and 94.87%. These are episodes
from the recorded traces, not independent traffic-seed replications.

## Phase 3 — Directional weakness diagnosis

Port encoding is North=1, South=2, East=3, West=4. The additional test's
positive-label prevalence and recall were:

| Direction | Positive prevalence | SNN recall | Equation recall |
|---|---:|---:|---:|
| North | 6.71% | 72.41% | 63.79% |
| South | 15.57% | 91.58% | 88.60% |
| East | 36.28% | 93.26% | 91.60% |
| West | 2.29% | 71.91% | 64.61% |

This confirms strong class imbalance by direction, especially West, and
supports imbalance as a plausible contributor to lower North/West recall.
However, the model is evaluated on only the four center routers and two new
traffic seeds; this does not prove imbalance is the sole cause. Feature
definitions are shared across output directions rather than using
direction-specific weights. Candidate availability and route legality are
not predictor inputs; the route selector applies those constraints after
prediction. Thus unavailability is a plausible limit on routing utility, not
an explanation for the classifier's ground-truth recall.

West-First may leave only one legal next hop for some destinations (notably
when traveling West), which limits the opportunity to act on a correct
prediction. It does not itself change the per-link label. Training used two
seeds and only the four center routers, so coverage also remains limited.

Validation-only threshold sweeps do not remove the directional issue:

| Decision threshold | North recall / FPR | West recall / FPR | Overall accuracy / recall / FPR |
|---|---|---|---|
| SNN risk class >= 1 | 82.59% / 1.16% | 53.42% / 1.58% | 97.190% / 89.744% / 1.517% |
| SNN risk class >= 2 (current) | 82.59% / 1.05% | 52.05% / 1.50% | 97.222% / 89.352% / 1.411% |
| SNN risk class >= 3 | 80.37% / 0.91% | 47.26% / 1.31% | 97.029% / 87.093% / 1.245% |
| Equation score >= 0 (current) | 75.93% / 0.64% | 48.63% / 1.02% | 97.197% / 86.441% / 0.936% |

The equation sweep produced identical classifications at score thresholds
-2 through +1; at +2 it reduced FPR slightly (0.936% to 0.898%) without
changing recall (86.441%). Threshold changes trade recall for false alarms;
they do not justify direction-specific bias. No direction-specific
parameter changes were made.

## Phase 4 — Network-level routing value

### Paired three-way experiment

The mesh runner now accepts a deterministic `-Seed`, and the testbench reports
mean/p95/p99 latency, throughput, blocked output cycles, network-congested
cycles, longest network congestion, and alternate hops during its randomized
phase. Ten independent seeds, 7001–7010, were run for each configuration:

- West-First + existing TF-PCR route scores;
- the same configuration with SNN routing enabled;
- the same configuration with equation routing enabled.

Priority, adaptive-buffer control, and offload were disabled in all three
paired configurations. Packet counts matched within each seed and every run
passed the packet-integrity and drain checks.

| Metric | West-First mean (95% t CI across seeds) | SNN | Equation |
|---|---:|---:|---:|
| Average latency | 8.052 cycles (7.994–8.111) | same | same |
| p95 latency | 22.7 cycles (22.35–23.05) | same | same |
| p99 latency | 53.3 cycles (52.62–53.98) | same | same |
| Throughput | 0.34016 packets/cycle (0.33641–0.34391) | same | same |
| Blocked output cycles | 99 | 99 | 99 |
| Network-congested cycles | 52 | 52 | 52 |
| Longest network-congestion streak | 43 cycles | 43 cycles | 43 cycles |
| Alternate hops in randomized phase | 0 | 0 | 0 |

At the runner's output precision, every paired per-seed difference for these
metrics is zero. In particular, average latency is printed to 0.001 cycle and
throughput to 0.0001 packet/cycle. The computed paired t intervals therefore
collapse to zero because the recorded differences have zero variance; this
is a quantization limitation and **must not be read as proof of equivalence
or statistical significance**. Raw latency sums and higher-precision
throughput should be emitted in a future run before finer effect claims.

### Existing full-integration regression

The final 19-test run used the original default seed and recorded:

| Configuration | Added policies vs default West-First | Mean latency | p95 / p99 | Throughput | Blocked output cycles | Network-congested cycles / longest |
|---|---|---:|---:|---:|---:|---:|
| West-First | TF-PCR only | 8.196 | 23 / 56 | 0.3324 | 99 | 52 / 43 |
| SNN full variant | SNN + priority + adaptive buffer + offload | 8.195 | 23 / 54 | 0.3324 | 82 | 49 / 33 |
| Equation full variant | Equation + priority + adaptive buffer | 8.195 | 23 / 54 | 0.3324 | 82 | 49 / 33 |

These single-seed full-integration variants are **confounded**: priority,
buffer control, and offload settings differ from the default West-First run.
Their lower blocked-cycle counts cannot be attributed to the predictor.
The paired isolated experiment is the fairer predictor comparison and shows
no observed change at the available measurement resolution.

The testbench includes 16-source hotspot bursts and sustained destination
backpressure, but its randomized phase offers only about one injection
opportunity in eight per source per cycle. It does not sweep sustained
network offered load as the trace-generation experiment does. The randomized
phase recorded no alternate hops for any of the three predictors. The
directed route test separately forces a risk score to verify that a legal,
ready alternate can be selected; that forced test does not establish that
the learned predictor naturally triggers useful rerouting under the
performance workload.

The same traffic is packet-checked end-to-end and drained within bounded
timeouts. No drops, duplicates, corruption, or deadlock timeout occurred.
There is not yet a robust estimate of route changes under sustained
high-load prediction.

## Phase 5 — Ablations and contribution

The paired ten-seed runs isolate West-First+TF-PCR, SNN routing, and equation
routing under otherwise identical settings. They show no measured marginal
network benefit at the current reporting precision.

The existing 19-test suite also checks TF-PCR disabled/enabled, priority,
SNN-full, equation-full, adaptive-buffer, and offload-controller behaviors.
Those regressions establish functionality, not comparable marginal
performance. Dedicated time-only and frequency-only configurations are not
present. Adaptive buffer, offload, and priority have not each been measured
as isolated paired performance treatments. Their incremental timing/area
overhead and effect on network metrics remain unquantified.

No thresholds or weights were tuned against the new test seeds. No online
accuracy measurement, online SNN retraining, or runtime switch from SNN to
equation exists in the RTL; the 90% figure is an offline acceptance gate.

## Phase 6 — Statistical interpretation

Predictor metrics over cycles, ports, and repeated workload/load cases are
correlated. The report therefore identifies the seed as the independent
generalization unit and uses paired network scenarios for comparisons.
There are only two added predictor test seeds, so a meaningful tight
seed-level prediction-quality confidence interval is not supportable.

Network performance uses ten independent paired seeds. The reported
confidence intervals describe the mean per-seed run metric. Paired
differences are all zero after output rounding, so no positive/negative
effect or statistical significance is claimed. More seeds alone will not
resolve the output-precision issue; the simulator should report exact
latency totals and measurement-cycle denominators and should test higher
offered loads.

## Phase 7 — FPGA feasibility

The environment has Icarus Verilog and VVP. `quartus_sh`, `quartus_map`,
Yosys, and Verilator were not found. No Quartus `.qpf`/`.qsf` project or
`.sdc` timing constraints were found. The exact EP4CE10 package and speed
grade are also unspecified. Therefore no synthesis, fitting, resource,
memory, critical-path, timing, or power result is claimed.

Reproducible synthesis plan:

1. Select the exact Cyclone IV EP4CE10 package/speed grade and install a
   Quartus edition/device-family package that supports that part.
2. Create a Quartus project targeting `noc_mesh_4x4`, include the source list
   in `validation/run-all.ps1`, and add the real board pin assignments and
   clock/reset constraints. Preserve the selected parameters for both builds.
3. Compile baseline West-First and equation-enabled designs with identical
   clock, device, and constraints; separately compile SNN if measuring its
   incremental cost.
4. Run synthesis, fitting, and timing analysis. Record logic elements,
   registers, embedded memory, Fmax/slack, and critical path for each build.
   Report incremental use versus baseline; do not infer physical power from
   RTL counts.
5. Archive the `.qsf`, `.sdc`, Quartus version, compile logs, and reports with
   the experiment so the result can be reproduced.

## Phase 8 — Final regression and artifacts

The final regression passed **19/19** tests. Notable checks:

- original router enabled/disabled: 710 stage/transfer checkpoints each;
- SNN recurrent reference parity: 1,000 samples;
- equation coefficient parity: 2,000 randomized vectors;
- all 256 source/destination route pairs and West-First legality;
- XY, West-First, priority, SNN-full, and equation-full mesh tests: 796
  packets each, no drops/duplicates/corruption.

The final logs are in `validation/run/research-audit/final-regression/`.
Other preserved outputs:

- `validation/run/research-audit/reproducibility/` — regenerated traces,
  manifest, and exact RTL model exports;
- `validation/run/research-audit/baseline-evaluation.json` — frozen-model
  baseline replay and validation threshold sweeps;
- `validation/run/research-audit/generalization/` — unseen-seed traces,
  manifest, and per-seed/model/subgroup metrics;
- `validation/run/research-audit/paired-routing.csv` and
  `snn-routing.csv` — ten-seed matched network runs;
- `validation/run/research-audit/routing-ablation.csv` and
  `routing-ablation-summary.json` — combined three-way measurements and
  seed-level summaries.

## Remaining work / decision

Keep the current predictor and model artifacts unchanged. The evidence
supports verified simulation behavior and high aggregate prediction quality
on the tested distribution, with meaningful weaknesses on uniform traffic
and North/West labels. It does **not** yet support a useful network-level
performance claim. Before further model optimization, add sustained
high-load paired traffic, exact unrounded performance counters, more
independent test seeds, isolated time/frequency/buffer/offload/priority
ablations, and target-device synthesis.
