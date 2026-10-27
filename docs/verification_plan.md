# Verification plan and evidence

## Regression evidence

The original seven-test baseline and the earlier 15-test integrated-priority
suite are preserved in their historical audit directories. The latest run
added trained-model parity, equation arithmetic, directed equation routing,
and equation-enabled full-mesh cases:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\validation\run-all.ps1 -OutputDirectory .\audit_report\snn-final-20261025-rerun
```

All 19 runs passed with exit code 0. The 19 compile logs are empty. The
consolidated output is `audit_report/snn-final-run.log` and per-test
executables/logs are under `audit_report/snn-final-20261025-rerun/`.

## Test coverage

- Feature extraction: reset, requester pressure, blocked streak, rising/falling pressure, eight-cycle request/service snapshots, downstream occupancy rise/max, and validity.
- Integer SNN: spike/leak/reset unit behavior plus 1,000 recurrent randomized samples compared with a separate reference using the exported trained package.
- Distilled equation: 2,000 randomized two-port vectors checked against the signed fixed-point score/reference using exported coefficients.
- Route legality: all 256 source/destination pairs for XY and West-First, equal-score preference, lower-risk legal alternative, and unavailable-alternate fallback.
- Directed predictive route: real wrapper occupancy and blocked-request signals set the equation features; a risky East candidate causes a tagged packet to take ready North, while unavailable North falls back to East.
- Full mesh: baseline XY/West-First, priority, disabled TF-PCR, trained SNN, and distilled equation variants each pass a 796-packet integrity scoreboard. Priority metadata remains aligned.
- Adaptive buffer and offload controllers: threshold/persistence, recovery hysteresis, invalid input, and reset behavior.

The final full-mesh equation case initially revealed a test harness that injected
TF-PCR scores even in equation mode. The scenario was corrected to inject risk
on the route-compute equation-score interface, then the full 19-run regression
passed. The separate directed equation test checks the trained equation from
measured wrapper features through the actual route choice and output packet.

## Prediction evaluation

`tools/generate_noc_traces.py` compiles the actual mesh RTL and records measured
feature and occupancy rows. Its manifest documents seed splits, simulator,
workload, offered loads, raw-trace hashes, and dataset hash. The label is an
event within the next eight cycles, with explicit feature and label validity.
The model and equation metrics are machine-readable in
`validation/snn_experiment/accuracy_results.json` and
`distillation_results.json`; summary values and limitations are in
`snn_training_and_accuracy.md` and `snn_distillation.md`.

Held-out SNN accuracy is 96.28% (recall 87.79%, FPR 2.25%); the equation is
96.70% accurate (recall 85.84%, FPR 1.41%) and agrees with the SNN on 98.997%
of test samples. North/West recall is lower than the aggregate. Samples overlap
within each H=8 sequence, so the per-cycle rows are not independent, although
traffic seeds remain disjoint across training, validation, and test.

## Open verification work

No concurrent SVA/formal proof, broad functional coverage database, or formal
deadlock/starvation proof was added. The testbench readiness assumptions are
finite and workload-specific. Multi-seed latency/throughput ablations are not
complete. The 4x4 results show no meaningful measured performance gain. No
Cyclone IV synthesis, resource estimate, critical path/Fmax, or physical power
measurement is available because Verilator/Yosys/Quartus are absent from PATH.
