# Preserved validation results

This folder contains previously saved test transcripts and baseline outputs.
New reproducible runs are written to `validation\run\reorganized\`, so they
do not replace these files. `legacy\` contains original router outputs and
compiled artifacts relocated from the project root.

`baseline_metrics.csv` records the fresh 2026-10-25 pre-change XY and
West-First runs from `audit_report\phase0-20261025\`. It contains the measured
packet and detector metrics from those simulator logs; it does not contain
tail latency, confidence intervals, synthesis, or power estimates.

`integration_metrics.csv` records the 2026-10-25 priority-only and
priority/SNN/adaptive-buffer/offload full-mesh runs from
`audit_report\phase6-20261025\`, plus the earlier SNN/buffer/offload run. Its
detector columns remain TF-PCR and occupancy diagnostics; the tests do not
score the SNN against future-congestion labels.
