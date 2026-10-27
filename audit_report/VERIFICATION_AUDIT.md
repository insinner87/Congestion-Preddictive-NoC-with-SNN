# Verification audit

## Audit run

On 2026-10-24, the seven-regression runner was executed without editing RTL, testbenches, scripts, documentation or saved results:

```powershell
Set-Location 'C:\Users\legen\Desktop\Capstone research\Temporal and Freq'
.\validation\run-all.ps1 -OutputDirectory '.\audit_report\verification-run'
```

The PowerShell runner completed with exit code 0. Icarus Verilog and VVP were version `12.0 (devel) (s20150603-1539-g2693dd32b)`. New compile transcripts, simulator logs, and generated router VCD/result files are under `verification-run/`; compiler logs are empty (no warnings were emitted). The testbench `$finish` message is not treated as a pass by itself; the regression-specific `PASSED` marker and runner exit are used.

## Seven regression results

| Regression and testbench | Scenarios/checks actually present | Result from this audit | Important gaps |
|---|---|---|---|
| `tfpcr-monitor` — `sim/congestion/tfpcr_monitor_tb.sv` | Withdrawn request clears wait/block counters; simultaneous demand/service and contention; exact 4-cycle test window snapshot; deficit and service counts; known normalization/3:1 score (`63`, `127`, `79`); no frequency score when demand equals service; 8-bit saturation at 255; asynchronous reset. Three directed cases and a 400-cycle watchdog (`:56-153`). | **PASS**, `TF-PCR MONITOR TESTS PASSED`; log `verification-run/tfpcr-monitor/tfpcr-monitor.log`. | Uses a 4-cycle parameterized window rather than default 16. No constrained-random counter test, no explicit `WINDOW_CYCLES=1` case, no malformed parameter tests, and no persistent raw waveform. |
| `router-enabled` — `sim/router/router_5port_tb.sv` plus `.svh` fragments | Seven directed scenarios: locked round-robin contention, all five outputs, independent simultaneous transfers, FIFO full/backpressure and simultaneous dequeue/enqueue, invalid destination drop, requester wait/blocked counters and window clearing, score saturation/recovery/reset. The checker compares FIFO contents, decoded requests, grants, crossbar data/pops, handshake stability, and reference queues (`router_5port_tb_checks.svh:1-214`; scenarios: `router_5port_tb_scenarios.svh:25-240`). | **PASS**, `ALL TESTS PASSED (710 stage/transfer check points)`; log and result summary under `verification-run/router-enabled/`. | 710 is the number of stage/transfer checker invocations/check points, not 710 delivered packets. Directed single-router tests do not characterize network-level performance. |
| `router-disabled` — same testbench with `ENABLE_TF_PCR=0` | Same seven cases. The test explicitly checks disabled diagnostic outputs remain zero in cases 6/7 while packet behavior still passes (`router_5port_tb_scenarios.svh:133-238`). | **PASS**, same 710 check points; `verification-run/router-disabled/`. | This exercises one parameter setting, not equivalence checking over arbitrary traffic or synthesis/netlist equivalence. |
| `mesh-routes` — `sim/mesh/mesh_route_compute_tb.sv` | Enumerates all 16×16 pairs in XY and West-First; each step checks route valid/legal, Manhattan-distance reduction, arrival, West-First constraint. Checks forced lower-score alternate and deterministic equal-score preference (`:45-161`). | **PASS**, `ROUTE TESTS PASSED: 256 XY + 256 West-First pairs and adaptive tie cases`; `verification-run/mesh-routes/mesh-routes.log`. | No formal dependency-cycle proof; no explicit invalid-coordinate test, all-legal-options-congested test, or every score-validity/unknown-value case. |
| `mesh-xy` — `sim/mesh/mesh_noc_tb.sv` and include files | All 256 source/destination pairs; four simultaneous independent injections; four 16-source bursts to a hotspot; four packets under destination backpressure and recovery; directed route fallback case; deterministic seeded offered load. Scoreboard checks input acceptance, expected destination, exact flit, duplicate tags, ejection before injection, and stalled source/ejection valid-data stability. Boundary outputs are asserted inactive. Bounded per-tag waits and 20,000-cycle global watchdog (`mesh_noc_tb_observers.svh:21-113`; scenarios: `mesh_noc_tb_scenarios.svh:24-231`). | **PASS**, 796 packets, no loss/duplicates/corruption; `verification-run/mesh-xy/mesh-xy.log`. | The all-pairs case is serialized. Mesh scoreboard does not enforce general per-source packet ordering as a separate invariant. It is not exhaustive over simultaneous traffic states, topology faults, X/Z injection, or all backpressure patterns. |
| `mesh-west-first` — same mesh test, `ROUTING_MODE=1`, TF-PCR enabled | Same traffic and scoreboard plus forced lower-score legal detour at node 4. It compares TF-PCR and occupancy predictions from the same live outputs in that run. | **PASS**, 796 packets; `verification-run/mesh-west-first/mesh-west-first.log`. | The single forced route case is not proof that every score-driven selection is legal/reachable; the route unit test covers legal base paths, not exhaustive congestion-score vectors. |
| `mesh-west-first-baseline` — same mesh test, `ROUTING_MODE=1`, TF-PCR disabled | Same mesh traffic with score disabled and deterministic preferred-hop fallback. | **PASS**, 796 packets; `verification-run/mesh-west-first-baseline/mesh-west-first-baseline.log`. | No equivalence tool compares baseline and enabled nets; the run compares output behavior only for these traces. |

The exact source lists/parameters are in `validation/run-all.ps1:77-112`. The runner checks compiler and simulation exit codes (`:30-74`); `run-project.ps1` additionally checks pass-marker strings (`:10-23`, `:45-88`).

## Mesh prediction and performance audit

The testbench uses 80 outputs and records three Boolean traces per output: TF-PCR threshold bit, occupancy threshold bit, and `out_valid && !out_ready` (`sim/mesh/mesh_noc_tb.sv:24-42`; `mesh_noc_tb_observers.svh:2-17`). A target sample at cycle `t` is positive if the next eight cycles contain at least four consecutive blocked cycles. Confusion is calculated per output-cycle; advance detection is counted separately only for a run's first blocked cycle and only if a predictor was high during the prior eight cycles (`mesh_noc_tb_detector_eval.svh:45-135`).

The detector metrics and packet correctness answer different questions. The exact observed saved values were:

| Run | TP | FP | TN | FN | Precision | Recall | F1 | Advance events detected / 6 | Mean lead | Packet result |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| XY + TF-PCR | 23 | 47 | 206302 | 28 | .329 | .451 | .380 | 2 | 1 cycle | 796 delivered; latency 8.196 cycles; throughput .3324 packets/cycle |
| West-First + TF-PCR | 23 | 54 | 206295 | 28 | .299 | .451 | .359 | 2 | 1 cycle | 796 delivered; latency 8.196 cycles; throughput .3324 packets/cycle |
| West-First, TF-PCR disabled | 0 | 0 | 206349 | 51 | 0 | 0 | 0 | 0 | N/A | 796 delivered; same latency/throughput |
| Occupancy-only comparator, each enabled trace | 45 | 170 | 206179 | 6 | .209 | .882 | .338 | 5 | 1 cycle | Same trace/run as the corresponding TF-PCR result |

Evidence: fresh logs in `verification-run/mesh-{xy,west-first,west-first-baseline}/`; older persistent source results in `validation/results/mesh-*.log`; full table in `docs/TF-PCR-VALIDATION.md:171-193`.

Arithmetic was checked against the reported counts: for example, XY precision is `23/(23+47)=0.329`, recall is `23/(23+28)=0.451`, and F1 is approximately `.380`. The confusion totals are 206,400 output-cycle samples; false positives per output-cycle are FP/206,400. The testbench does not persist raw per-cycle trace arrays to a file, so these figures could not be independently recomputed from raw observations. They are the simulator's own derived values, not an independent external replication.

Interpretation limits:

- There are six onset-defined sustained-blocking events in the run, so event-level advance recall has a very small denominator.
- The per-cycle horizon windows overlap; 206,400 labels are not independent events. The large TN count makes false-positive-per-cycle rates look small; report precision and event-level lead/misses alongside them.
- The occupancy comparator and TF-PCR share each run's output signals, event definition, and observation windows. They are a fair within-run comparator, but XY and West-First can produce different routing/output traces.
- The comparator's threshold is fixed at three occupied flits over inputs whose FIFO-head requests target an output (`noc_router_wrapper.sv:132-145`); the report says it was not tuned on the evaluation trace. No separate tuning/evaluation traces are present.
- This one trace does **not** show a traffic-level latency or throughput advantage for TF-PCR adaptive routing. A directed force test shows a legal lower-score alternative can be selected.
- No raw waveform is generated for mesh; the monitor/testbench stores trace arrays only in simulation memory. No synthesis cost is measured.

## Missing or limited verification

There is no formal proof of deadlock freedom, route stability, FIFO conservation, or equivalence. The mesh test exercises protocol stability and packet conservation for its generated scenarios but is not exhaustive over all concurrent states. No seeded randomized tests exercise only the standalone monitor. There are no explicitly named low-load burst, saturated-but-fully-serviced demand, repeated congestion-onset/recovery series, multiple random seeds, or distributional workload sweeps beyond the directed cases and one uniform-random sequence. The testbench supplies one deterministic seed `0x4f1bc2d7` (`mesh_noc_tb.sv:49`).

The router regression checks saturation and recovery of temporal scores, plus a sustained window deficit; the standalone monitor checks a small representative 4-cycle case. The score and predictor checks are threshold-focused, not calibration/ROC sweeps.

## Reproduction

From the project root:

```powershell
.\validation\run-all.ps1 -OutputDirectory '.\audit_report\verification-run'
```

The current `run-all.ps1` source contains all seven `iverilog`/`vvp` invocations and compile-order lists. Run output from this audit is preserved beside this report.
