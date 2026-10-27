# Current implementation audit

**Audit date:** 2026-10-26  
**Purpose:** Record the repository state and evidence before changes for the
end-to-end congestion-prediction request. This supplements, rather than
replaces, the broader architecture and regression audits in this directory.

## Architecture and actual data path

The top-level experiment is `sim/mesh/mesh_noc_tb.sv`, instantiated with
`rtl/mesh/noc_mesh_4x4.sv`. The mesh contains sixteen `noc_router_wrapper`
instances, each preserving the five-port `router_5port`. The router's five
input FIFOs, switch allocator, round-robin arbiters, and crossbar perform the
actual ready/valid transfers; registered `mesh_link_fifo` instances connect
routers. A mesh flit carries its destination in bits `[60:57]`, its mutable
next hop in `[63:61]`, and the opaque payload in `[56:0]`.

At each wrapper ingress, destination-directed routing computes legal XY or
West-First candidates and rewrites only `[63:61]`. In West-First mode, a valid
congestion risk can select a lower-score, ready minimal alternative. This
changes the router's requested output through the wrapper; it does not change
the router's internal arbitration policy. The baseline XY and TF-PCR-disabled
West-First modes remain available.

For learned prediction, the wrapper derives seven binary features from
request/service history, output blocking, output-link occupancy, and input
buffer pressure. Both the SNN and distilled equation consume these same
features and valid signals. The SNN emits a risk class; the mathematical
equation emits a thresholded risk. Static parameter modes select one model's
signals for next-hop costs/risk. The equation is distilled from the SNN, not an
independently fitted predictor.

`sim/mesh/mesh_noc_tb_observers.svh` records accepted injection handshakes and
delivered ejection handshakes in a tag-indexed scoreboard, compares the full
64-bit flit and priority against the expected values, detects duplicate or
pre-injection ejections, and checks stable data under backpressure. The test
also checks that boundary routers do not assert nonexistent outputs. The
separate `sim/mesh/mesh_trace_tb.sv` records model inputs and measured link
signals for offline training; it does not itself provide the full packet
scoreboard or traffic-performance comparison.

## Findings before changes

1. **Accuracy-based adaptive selection is absent.** The current mesh exposes
   separate static SNN and equation route modes. There is no RTL path that
   gates SNN selection on held-out validation accuracy, delays ground-truth
   evaluation until labels become available, maintains an online accuracy
   window, or emits reasoned model-switch events.
2. **The existing labeled traces are not the requested five scenarios.**
   `tools/generate_noc_traces.py` supports uniform, hotspot, transpose, and
   bursty-hotspot patterns at selected offered-load percentages. These do not
   directly provide distinct no-congestion, random, moderate, severe, and
   alternating mixed phases. Its ground truth is generated from subsequent
   measured blocked/full-link conditions, not passed to the model as a feature.
3. **Existing one-command regression is not the full experiment.**
   `validation/run-project.ps1` runs the 19 Icarus regressions and checks their
   pass markers. It does not create scenario traces, evaluate frozen models on
   held-out data, calculate paired routing metrics, or combine those outputs
   into one machine-readable result.
4. **Existing predictor evaluation is offline.** The checked-in experiment
   separates train/validation/test seeds and stores classification metrics.
   This supports an offline validation claim, not online RTL accuracy or a
   runtime switch-policy claim.
5. **Existing route and scoreboard coverage is useful but bounded.** Directed
   all-pairs route tests and the mesh packet scoreboard cover legal routing
   and end-to-end flit integrity for the exercised test traffic. The trace
   generator's predictor dataset is distinct from the end-to-end packet
   scoreboard/performance test, so accuracy rows alone do not establish packet
   delivery or performance.
6. **Research/performance limitations remain.** Prior saved paired-routing
   summaries report identical West-First and equation-routing metrics for
   their tested seeded traffic; they do not support a claim that predictive
   routing improves performance. The prior audit also notes limited workloads
   and no formal deadlock, synthesis, area, power, or timing verification.
7. **Repository context.** The workspace is nested in `C:\Users\legen`, which
   is the Git root; project files are untracked there. No project-specific
   history is available for this change, so unrelated home-directory
   untracked files must not be modified or cleaned.

## Pre-change validation

The existing runner was `validation/run-all.ps1`; its pre-change source lists
and parameters defined nineteen compile/simulation configurations, including
the router, predictor, route, and mesh regressions. The pre-change baseline
completed with all nineteen pass markers. Post-change verification and measured
results are recorded in
[END_TO_END_VERIFICATION.md](./END_TO_END_VERIFICATION.md).

## Work required to satisfy the request

- Add a delayed-label adaptive selector with explicit validation gating,
  minimum-sample behavior, a documented rolling online window, fallback to
  the equation predictor at accuracy `<= 90%`, and visible selection/switch
  reasons.
- Add tests that prove no future label is consumed early, that the `> 90%`
  gate selects SNN only after the required evidence, and that falling online
  accuracy switches routing back to the equation model.
- Extend reproducible scenario generation and produce actual, held-out
  evaluation artifacts with traffic, prediction, routing, and integrity
  outcomes; report unsupported or unmeasured metrics explicitly.
- Provide one runnable command that runs compilation/regressions and the
  reproducible evaluation without overwriting trained model artifacts.
- Re-run the complete workflow and update the README and verification report
  with observed outputs only.
