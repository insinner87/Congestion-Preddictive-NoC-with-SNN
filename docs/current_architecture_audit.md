# Current architecture audit

**Audit date:** 2026-10-25  
**Scope:** Current RTL, testbenches, scripts, and saved validation artifacts in this workspace.  
**Method:** Read-only source inspection followed by a fresh run of the repository's seven-test Icarus regression.

## Repository and tool inventory

| Area | Files and responsibility |
|---|---|
| Shared definitions | `rtl/common/noc_pkg.sv`: default 48-bit router flit, five ports, port encodings, FIFO depth 4. |
| Router datapath | `rtl/router/router_5port.sv`, `input_buffer.sv`, `fifo.sv`, `switch_allocator.sv`, `round_robin_arbiter.sv`, `crossbar.sv`. |
| Congestion logic | `rtl/congestion/congestion_monitor.sv`, `congestion_estimator.sv`. |
| Mesh | `rtl/mesh/noc_mesh_4x4.sv`, `noc_router_wrapper.sv`, `mesh_route_compute.sv`, `mesh_link_fifo.sv`. |
| Verification | Router, congestion, route-compute, and 4x4 mesh testbenches under `sim/`, with included `.svh` checkers and scenarios. |
| Automation and records | PowerShell runners under `validation/`; previous source, verification, novelty, and validation reports under `audit_report/` and `docs/`. |

No `AGENTS.md` instructions or synthesis/build project files were found in the enumerated workspace. The RTL has no SNN, priority, packet-offload, or adaptive buffer controller module. Existing source and tests are preserved; this audit did not edit RTL.

### Module hierarchy

```text
noc_mesh_4x4 (4 x 4)
  16 x noc_router_wrapper
    5 x mesh_route_compute
    1 x router_5port
      5 x input_buffer + fifo
      1 x switch_allocator
        5 x round_robin_arbiter
        optional congestion_monitor + congestion_estimator
      1 x crossbar
  48 directed mesh_link_fifo instances (depth 2 by default)
```

## Existing design and data/control flow

### Five-port router

The reusable router is a one-flit-at-a-time (no packet reassembly or multi-flit framing) crossbar switch. Its default `noc_pkg::FLIT_WIDTH` is 48 bits: `[47:45]` selects Local, North, South, East, or West; `[44:0]` passes through as payload. Each input has a four-entry FIFO by default. A FIFO accepts input on `in_valid && in_ready`, and the crossbar pops its head only on the matching output's `out_valid && out_ready`. Invalid destination codes 5–7 are popped and reported so they cannot head-of-line block that input.

The switch allocator decodes each FIFO head into at most one output request. Each output has its own round-robin arbiter, so independent outputs can transfer concurrently. An arbiter locks the selected input while the output is stalled and advances its search pointer after a successful handshake. FIFO count and pointers reset asynchronously with active-low `rst_n`. The ordinary router path is destination-fixed; congestion scores do not alter its own five-port allocation.

### Mesh and routing

`noc_mesh_4x4` instantiates 16 wrappers on a 4x4 orthogonal mesh. Mesh flits are 64 bits: `[63:61]` is the rewritten current-hop output code, `[60:59]` destination X, `[58:57]` destination Y, and `[56:0]` opaque payload. All 57 payload bits are available to an application and no priority subfield is defined. Each directed neighbor link has a registered depth-2 FIFO by default (48 directed FIFOs total); its source-ready depends on local registered occupancy. Nonexistent boundary inputs are tied invalid and boundary outputs are tied not-ready.

XY routing chooses East/West until X matches, then North/South, then Local. West-First permits only West while a destination is West; for an East destination with a vertical displacement, East and the required vertical direction are both legal minimal choices; otherwise the needed vertical direction is the sole legal route. Each permitted non-local hop decreases Manhattan distance. The existing adaptive choice stays within these legal West-First candidates. The wrapper computes a hop before ingress, holds it if the upstream flit is stalled, rewrites `[63:61]`, then hands it to the existing router. The router's output arbiter separately holds a granted flit during downstream backpressure.

West-First relies on its turn restrictions for the usual channel-dependency acyclicity argument. The current evidence is route enumeration and simulation, not formal proof or exhaustive state exploration. Any adaptive choice must remain within the existing legal candidate set; priority or a predictor must never introduce a forbidden turn.

## Existing TF-PCR implementation

`switch_allocator.sv` exports the decoded request matrix and counts a transfer as `grant_valid & output_ready`. `congestion_monitor.sv` measures, per output:

- Per-requester consecutive waiting cycles, saturating at the configured counter maximum and clearing on service or request withdrawal.
- Output blocked cycles while one or more requests exist but no transfer succeeds, also saturating and clearing otherwise.
- Requester-cycle demand and successful transfer-cycle totals over a fixed window. With the default 16-cycle window, it snapshots the current cycle at the boundary, computes `max(demand - service, 0)`, then starts another window.

`congestion_estimator.sv` computes the maximum normalized requester wait or output block as `time_score`. It normalizes the last completed window's service deficit as `frequency_score`, then computes:

```text
score = floor((TIME_WEIGHT * time_score + FREQ_WEIGHT * frequency_score)
              / (TIME_WEIGHT + FREQ_WEIGHT))
congestion_predicted = score >= SCORE_THRESHOLD
```

Defaults are 3:1 temporal-to-deficit weighting, temporal saturation at 16 cycles, deficit saturation at 8 counts, and threshold 128 on a 0–255 scale. The deficit is not traffic-arrival frequency: it is a bounded windowed difference between requester-cycles and successful service-cycles. No FFT, spectral analysis, rate estimator, occupancy history, gradient, hysteresis, or configured prediction horizon exists in the synthesizable monitor/estimator. The output called `congestion_predicted` is a thresholded present/history risk indication; it is not a future-congestion prediction with a defined horizon.

### Does this score change routing?

**Yes, in the mesh's West-First configuration.** `noc_router_wrapper.sv` connects the router's per-output score and threshold bit to `mesh_route_compute.sv` and sets `score_valid` from the static `ENABLE_TF_PCR` parameter. In West-First mode, if the preferred route's threshold bit is high, the route selector scans only legal candidates and picks a strictly lower raw score; equal scores keep the preferred route. If every candidate is high or no alternate is lower, it still chooses a legal route. In XY mode only one candidate exists, so the score cannot change the route. With TF-PCR disabled, the wrapper uses deterministic preferred-hop routing.

The score monitors local router request, grant, transfer, and wait state. It does not directly observe the downstream link FIFO occupancy: the exposed local input FIFO occupancies feed a separate occupancy-only comparator in the wrapper/testbench, not the route scoring path. The current route enable is not a runtime warm-up/valid signal; before a completed service-deficit window the initialized deficit is zero.

## Baseline regression

Fresh command, executed from the project root on 2026-10-25:

```powershell
powershell -ExecutionPolicy Bypass -File .\validation\run-all.ps1 -OutputDirectory .\audit_report\phase0-20261025
```

**Result: all seven regressions passed; runner exited 0.** Icarus and VVP report `12.0 (devel) (s20150603-1539-g2693dd32b)`. Each of the seven compile logs is empty, so this run emitted no compiler warnings. Verilator, Yosys, Quartus, and `quartus_sh` were not available on `PATH`; no synthesis, FPGA area, timing, or power result is claimed. Fresh run logs and generated simulation artifacts are under `audit_report/phase0-20261025/`.

| Test | Fresh result | Scope and limit |
|---|---|---|
| `tfpcr-monitor` | PASS | Directed reset, withdrawal, window boundary, wait/block, service deficit, normalization, and saturation checks. |
| `router-enabled` | PASS, 710 checker points | Original router scenarios: arbitration, all destinations, concurrency, backpressure/full FIFO, invalid code, measurements, saturation, reset. Checker points are not a packet count. |
| `router-disabled` | PASS, 710 checker points | Same router scenarios with diagnostic logic disabled; validates these directed traces only. |
| `mesh-routes` | PASS, 256 XY + 256 West-First pairs | Legal routes, distance progress, forced lower-score alternate, and tie behavior. |
| `mesh-xy` | PASS, 796 packets | Packet integrity, all source/destination pairs, directed concurrency/hotspot/backpressure, plus one seeded traffic sequence. Average latency 8.196 cycles; throughput 0.3324 packets/cycle. |
| `mesh-west-first` | PASS, 796 packets | Same packet scenarios with adaptive West-First enabled. Average latency 8.196 cycles; throughput 0.3324 packets/cycle. |
| `mesh-west-first-baseline` | PASS, 796 packets | Same West-First traffic with TF-PCR disabled. Average latency 8.196 cycles; throughput 0.3324 packets/cycle. |

The mesh test's event label is at least four consecutive blocked cycles within the next eight cycles. On this single deterministic trace, West-First TF-PCR scored TP=23, FP=54, TN=206295, FN=28 (precision 0.299, recall 0.451); its occupancy comparator scored TP=45, FP=170, TN=206179, FN=6 (precision 0.209, recall 0.882). The disabled baseline had no TF-PCR positives. There were six onset-defined events and only two were detected in advance by TF-PCR, with mean lead one cycle. These overlapping per-output-cycle labels are correlated; this trace has no train/held-out split and does not demonstrate improved packet performance. The three mesh configurations have identical packet latency and throughput in this run. These are simulator outputs, not independently recalculated from a persisted raw trace.

## Implemented, incomplete, and absent functionality

| Area | Actual state |
|---|---|
| Router baseline and handshake | Implemented; directed checks cover FIFO, crossbar, arbitration, stable stalled grants, invalid head removal, and simultaneous operations. |
| XY and West-First | Implemented; adaptive West-First selection can select a lower-score legal route. No formal deadlock proof. |
| Time-based congestion | Implemented as saturating requester wait and output-blocked counters. Not occupancy gradient/history. |
| “Frequency” assistance | Implemented as windowed requester-cycle/service-cycle deficit; no explicit arrival-frequency or event-rate estimate. |
| Prediction | No future target horizon in RTL. Current/history score threshold is evaluated against future events only by the testbench. Existing single-seed measurement has modest precision/recall and few onset events. |
| SNN | Absent: no spike encoder, LIF state, fixed-point weights, training/tuning workflow, or SNN evaluation. |
| Adaptive buffer management | Absent beyond fixed-size FIFOs and normal ready/valid backpressure. No adaptive threshold/hysteresis controller. |
| Power-aware control | Absent; no clock enables, activity controls, switching proxy, or measured power. |
| Offloading | No separate persistent congestion trigger/controller or packet migration. Existing West-First alternate-next-hop selection is the only congestion-driven reroute behavior. |
| Priority | No priority field in either packet format and no priority-aware arbiter. The 64-bit mesh payload is opaque, so assigning payload bits to priority would break the existing payload contract. |
| Verification breadth | Seven useful directed/integration regressions; one deterministic mesh random seed; no multi-seed offered-load sweep, predictor train/held-out dataset, comprehensive functional coverage, formal properties, synthesis, or power analysis. |

## Risks and module-level integration plan

| Existing module(s) | Planned responsibility/change | Interfaces and timing | Verification |
|---|---|---|---|
| `congestion_monitor.sv`, `congestion_estimator.sv` | Preserve the existing implementation as the baseline. Add explicitly named rate/history features in separate logic so the old 3:1 estimator remains comparable. | Reuse request, transfer, ready, and FIFO occupancy signals; bounded counters and synchronous feature snapshots on the existing clock/reset. | Unit tests for saturation, window boundaries, trend, reset, simultaneous arrival/service. |
| New `rtl/congestion/tf_feature_extractor.sv` | Per-output occupancy aggregation, short-history gradient, persistence/hysteresis, and fixed-window arrival/service event rates. | Inputs from `output_request_matrix`, `input_occupancy`, actual transfer, and ready/backpressure; combinational observation with registered histories, no added ingress pipeline. | Standalone feature tests plus checks against hand-calculated traces. |
| New `rtl/congestion/snn_predictor.sv` | Small feed-forward LIF predictor (initial target: 4 hidden neurons and 1 output neuron), fixed integer weights/potentials, deterministic reset and bounded state. Model parameters exported by an offline tuning script. | Candidate features enter the encoder; output is one risk bit/class per output. Initial integration should use same-cycle combinational spike calculation from stored membrane state so route timing gains no register stage; synthesis timing remains unmeasured. | Neuron/encoder unit tests, reset and threshold boundaries, trace-based held-out evaluation, bypass/invalid fallback. |
| `noc_router_wrapper.sv`, `mesh_route_compute.sv` | Keep XY baseline. Pass predicted risk/feature score to existing legal West-First candidate selection; preserve legality, preferred-hop tie break, and stall-locked route. Add predictor bypass and deterministic fallback. | Existing ingress route capture remains in place. Combinational inference adds path depth but no cycle; candidate scores only change routes among `legal_ports`. | Exhaustive destination/legality tests and integration tests proving score/prediction can change actual output while preserving packet identity. |
| `input_buffer.sv`, `fifo.sv`, wrapper | Add adaptive buffer pressure state/early notification only after feature tests. Keep physical FIFO depth, pointers, full/empty, and accepted-flit behavior unchanged in the first integration. | Existing ready/valid interface remains authoritative; no dynamically reconfigured capacity. | Full/empty, simultaneous enqueue/dequeue, reset, backpressure, and no-loss assertions. |
| Predictor control in wrapper | Add a documented clock-enable/update policy that holds an idle zero state and avoids unnecessary state updates; do not gate the router clock. | State updates remain on `clk` with `rst_n`; forwarding/arbitration are never disabled. | Compare output behavior to always-updated baseline and count enabled predictor updates as an activity proxy. |
| `round_robin_arbiter.sv` and mesh flit path | Add priority only after the interface choice below is approved. Preserve round-robin fairness within a class and add bounded aging. | No priority encoding exists. Proposed least-invasive option is a priority sideband accepted at mesh injection/ejection and carried with each internal flit through router/link buffers; this adds interface/state bits but preserves all 64 existing flit bits. | Competing-class tests, bounded service under stated downstream-ready assumptions, backpressure and packet-integrity checks. |
| `noc_mesh_4x4.sv`, validation scripts, `sim/` | Expand the reproducible feature ablation, integration regression, trace export, and report scripts. | Existing fixed topology and 64-bit data format stay intact; test seeds and mode parameters are explicit. | Full existing suite after each integration, new independent unit tests, held-out trace evaluation, no unsupported claim of proof. |

### Critical correctness and research risks

1. The existing score is not a forecast, and its “frequency” name overstates what is measured. A future predictor needs a precise label and horizon plus separate tuning and held-out traces.
2. Routing decisions are made on ingress using local per-output request history, not a remote downstream FIFO occupancy report. Added features must keep that signal meaning explicit and account for staleness.
3. Predictor output may affect only candidates allowed by current XY/West-First rules. Current West-First candidates are minimal; changing that set can invalidate the turn-model argument.
4. The full mesh run shows no packet-performance benefit from the existing predictor in this one trace. An SNN's added logic must be justified by a reproducible held-out comparison, not by its implementation alone.
5. The mesh flit had no allocated priority bits. The payload is opaque, so reserving bits in it would be an incompatible format change. The user later approved a two-bit sideband; it is implemented through router and link storage while the 64-bit flit stays unchanged. See the implementation report for storage cost and test evidence.
6. A combinational predictor avoids extra route latency but adds delay to ingress route selection. No FPGA synthesis tool is currently available to check the EP4CE10 resource or clock budget.
7. Simulation demonstrates sampled behavior, not formal deadlock freedom, starvation freedom, Cyclone IV fit, or power savings.

## Phased plan and first files

1. **Audit and freeze baseline:** this report and fresh artifacts in `audit_report/phase0-20261025/`; keep original RTL and results intact.
2. **Define interfaces and measurements:** create `docs/research_architecture.md`, `docs/feature_and_signal_specification.md`, `docs/snn_model_specification.md`, `docs/routing_and_offloading_policy.md`, `docs/verification_plan.md`, and `docs/benchmark_methodology.md` before predictor RTL. These freeze signal meaning, horizon labels, fallback, candidate legality, and comparison definitions.
3. **First RTL increment:** add `rtl/congestion/tf_feature_extractor.sv` and `rtl/congestion/snn_predictor.sv`; add standalone `sim/congestion/` tests and a deterministic offline trace/tuning/evaluation script. Then connect them through `noc_router_wrapper.sv` and `mesh_route_compute.sv`, retaining the existing baseline behind a parameter.
4. **Second RTL increment:** add a pressure/hysteresis controller using existing FIFO occupancy and handshake signals, with no change to FIFO capacity or full/empty semantics. Verify it independently before mesh integration.
5. **Power activity policy:** add only a safe predictor update enable and simulator activity counter/proxy, with an identical-traffic baseline comparison. No clock gating or power claim without measurement.
6. **Priority/offloading increment:** after the audit, the user approved the two-bit sideband. Priority arbitration and the persistent offload controller are implemented and covered by unit and full-mesh regressions; formal fairness proof remains open.
7. **Evaluation:** run the expanded ablation and held-out tests; report synthesis only if an FPGA synthesis tool becomes available. Update the implementation report with actual results and limitations.

**Exact first planned changes after this audit:** the six design/verification specification documents listed in step 2, then the two new congestion RTL modules and their two unit testbenches. `noc_router_wrapper.sv`, `mesh_route_compute.sv`, and the regression script are changed only in the later integration step, after the new module tests pass. Priority RTL is held until the sideband interface is resolved.

## Post-audit implementation update

The priority interface decision was resolved in favor of a two-bit sideband. It now travels with each flit through input FIFOs, crossbars, and registered mesh link FIFOs, and it is exposed at mesh injection/ejection. Optional priority arbitration uses highest-class selection, round-robin tie-breaking, and age promotion. The fifteen-test regression, including a priority-only mesh run and the integrated priority/SNN/buffer/offload run, passed in `audit_report/phase6-20261025/`. Detailed limits and results are recorded in `implementation_report.md`.

## Trained-predictor update

The initial audit above remains the historical pre-change baseline. Since then,
the SNN was trained from actual full-mesh router traces, evaluated on a
disjoint seed, distilled into a fixed-point equation, and connected to the
West-First route selector. The final 19-test suite, including trained SNN
parity and equation-enabled mesh routing, passed in
`audit_report/snn-final-20261025-rerun/`. Measured test accuracy is 96.28% for
the SNN and 96.70% for the equation. Per-port recall remains low on North/West;
no EP4CE10 synthesis, timing, or power result is available. See
`snn_training_and_accuracy.md`, `snn_distillation.md`, and the updated
`implementation_report.md` for the current evidence.
