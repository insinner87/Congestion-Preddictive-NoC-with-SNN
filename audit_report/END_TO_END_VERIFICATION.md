# End-to-end NoC verification

This report records implementation and verification evidence after the
congestion-aware adaptive predictor changes. The pre-change architecture and
gap analysis are in [CURRENT_IMPLEMENTATION_AUDIT.md](./CURRENT_IMPLEMENTATION_AUDIT.md).

## Implementation

The existing data path remains `noc_mesh_4x4` -> `noc_router_wrapper` ->
`router_5port`. In adaptive mode, the wrapper evaluates the SNN and distilled
equation on the same features and sends the selected risk into the existing
legal West-First route-choice path. The five-port allocator, FIFOs, crossbar,
and ready/valid protocol are unchanged.

The new per-output selector:

- Evaluates an SNN prediction only after its eight-cycle label horizon has
  matured.
- Requires at least 32 online samples and maintains a 64-sample rolling
  accuracy window.
- Selects the SNN only when both the exact offline validation ratio and the
  online rolling ratio are strictly greater than 90%; otherwise it falls back
  to the equation.
- Emits initial-selection and model-switch events with reason codes.

Trace generation now supports `no_congestion`, `random`, `moderate`, `severe`,
and `mixed` traffic. It records reproducible per-cycle features and route
decisions and checks accepted and delivered flits by unique tag. The complete
workflow evaluates the generated validation split before regression, passes
the exact correct/total SNN counts to the RTL, then evaluates the results with
regression and adaptive-selection logs.

## Verification performed

The updated `validation/run-complete.ps1` completed a deterministic smoke run
using one train, validation, and test seed, one load, the severe workload, and
24 trace cycles. All 21 RTL regressions passed. The run wrote its generated
traces and reports under `%TEMP%\\noc-complete-verified`; it did not overwrite
model files.

| Check | Result |
|---|---|
| Focused adaptive-selector test | Passed; covers exact 95/100 admission, the exact 900/1000 boundary fallback, delayed labels, sample warmup, and online fallback |
| Complete RTL regression | 21/21 pass markers |
| Adaptive mesh packet integrity | 796 injected and delivered; 0 missing, duplicate, corrupted, or unexpected flits |
| Offline validation gate | 2,490/2,528 correct (98.4968%; displayed as 98% truncated); these exact counts were passed to the adaptive RTL |
| Adaptive selection activity | 202,671 SNN-selected samples, 3,889 equation-selected samples, 88 switches to SNN, 8 switches to equation |
| Trace matrix | 3 runs, 8,288 dataset rows; each run had 188 or 189 accepted and delivered flits and zero missing, duplicate, or corrupted flits |
| Python and PowerShell syntax | Passed |
| Final evaluation aggregation | All six reported mesh configurations parsed as passed, including the adaptive policy fields |

On this small severe-workload trace smoke set, validation SNN accuracy/F1 were
98.50%/0.9408 and equation accuracy/F1 were 99.01%/0.9603. Held-out test
SNN accuracy/F1 were 98.38%/0.9376 and equation accuracy/F1 were
99.05%/0.9625. These results describe this generated smoke dataset only; they
are not a general performance or model-superiority claim.

The Windows regression logs are UTF-16LE. The evaluator now detects UTF-16
BOMs as well as UTF-8 logs, so regression and adaptive-policy results are
actually parsed rather than silently omitted.

## Reproduction

Run the complete default experiment from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp\validation\run-complete.ps1"
```

The default workload matrix is larger than the smoke run: 120 trace runs
across the five traffic regimes, three loads, and disjoint seed splits. The
full default 120-run matrix was not executed for this verification. The
reproducible command and scripts can be used to produce that larger
experiment; the smoke results here are not a substitute for it.

## Scope and limitations

- The executed trace matrix used one seed per split, one load, one workload,
  and 24 cycles. It is an end-to-end workflow smoke test, not a substitute for
  the full default workload matrix or multi-seed statistical analysis.
- The route-mode performance results have not been proven against identical
  per-cycle offered-flit traces. No routing-performance improvement is claimed.
- The selector's delayed label measures its documented output-blocked/full-link
  event; it does not prove formal deadlock freedom or liveness.
- No synthesis, area, power, clock-timing, or physical implementation
  evaluation was performed.

## Principal changed files

- `rtl/congestion/adaptive_predictor_selector.sv` and
  `sim/congestion/adaptive_predictor_selector_tb.sv`: delayed-label policy and
  exact validation/online gate tests.
- `rtl/mesh/noc_router_wrapper.sv` and `rtl/mesh/noc_mesh_4x4.sv`: predictor
  selection and validation-count parameter wiring into route choice.
- `sim/mesh/mesh_noc_tb.sv`, its observer/scenario includes, and
  `sim/mesh/mesh_trace_tb.sv`: selection/integrity reporting and trace
  scoreboarding.
- `tools/generate_noc_traces.py` and `tools/evaluate_noc_models.py`:
  reproducible scenario/evaluation summaries and regression-log parsing.
- `validation/run-all.ps1`, `validation/run-project.ps1`,
  `validation/run-mesh.ps1`, and `validation/run-complete.ps1`: exact validation
  gate propagation and the complete reproducible workflow.
- `README.md`, `validation/README.md`, `rtl/README.md`,
  `sim/congestion/README.md`, and `docs/adaptive_predictor_selection.md`:
  reproduction and policy documentation.
