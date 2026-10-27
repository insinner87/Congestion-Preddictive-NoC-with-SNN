# Go / no-go assessment

**Decision date:** 2026-10-24  
**Overall recommendation:** **CONDITIONAL GO for continued research; NO-GO for claiming established novelty or submitting the current evidence as a validated research result.**

## Three separate verdicts

### 1. Is the current implementation worth continuing?

**Verdict: CONDITIONAL GO.**

**Evidence supporting continuation**

- The preserved router, monitor, estimator, mesh wrapper and route computation compile and pass all seven current Icarus regression configurations in the audit run.
- The design has an identifiable hypothesis to evaluate: combine temporal waits/blocking and a fixed-window demand/service deficit, then use the resulting signal to choose among legal West-First minimal alternatives.
- The code exposes meaningful test points and has a useful packet scoreboard, forced route-choice test, boundary assertions and fixed-seed traffic.

**Uncertainties**

- No provenance/license for the original router is available.
- There is no synthesis-cost estimate or formal proof.
- The current workload metrics show no end-to-end latency/throughput benefit for the tested trace.

**Conditions that would improve the verdict**

- Establish baseline provenance and legal reuse rights.
- Retain the existing router regression while adding independent targeted tests and reproducible builds.
- Define the intended claim narrowly as an evaluated implementation unless literature establishes a stronger algorithmic contribution.

### 2. Is the current algorithm sufficiently supported as a research contribution?

**Verdict: NO—not yet.**

**Evidence**

- The score is precisely recoverable from RTL, and a small worked example is tested.
- Congestion prediction and congestion-aware adaptive NoC routing are established research topics. PreNoc, the SNN prediction paper, DyAD, the temporal/spatial ACO work, and the 2013 congestion-prediction paper are direct leads.
- The current code's distinguishing details may be the exact demand/service deficit, normalization/weights, and its integration with West-First, but no full-text prior-art comparison or controlled ablation demonstrates that these details are new or advantageous.
- West-First itself is established prior art (Glass and Ni).

**Uncertainties**

- Several closest publications could not be accessed in full; the patent search was partial.
- No exact novelty search can prove universal absence.
- The score thresholds and 3:1 weight lack a separate training/tuning trace or sensitivity analysis.

**Conditions that could change the verdict**

- A complete search and claim-by-claim/algorithm-by-algorithm comparison identifies a specific, non-obvious difference.
- Held-out traffic traces show consistent, statistically supported value over strong tuned baselines.
- An ablation shows the proposed time signal, deficit, weighting, or route integration individually contributes to an outcome.

### 3. Is the evidence sufficient to submit a paper now?

**Verdict: NO.**

**Evidence**

- Seven regressions passed. This is meaningful engineering evidence of the tested packet paths and assertions.
- The mesh congestion result includes only six qualifying sustained-blocking onsets in one seeded workload family; confusion windows overlap heavily.
- The TF-PCR route selection is demonstrated by a forced test, but measured aggregate latency and throughput are identical to the XY/fallback cases on the reported run.
- No raw per-cycle prediction traces, synthesis results, formal results, multiple seeds, held-out traces, confidence intervals or comprehensive related-work analysis are present.
- The existing literature citation list is incomplete; source-code authorship/license provenance is unresolved.

**Conditions to revisit**

- Add actual baseline and ablation results over multiple traffic classes/seeds, tune thresholds only on separate traces, save raw traces, and report event-level statistics/uncertainty.
- Synthesize both baseline and feature variants in a documented technology/flow; report area/timing/power only if measured.
- Establish baseline code provenance and license; finish literature and patent claim review; add complete references.
- Provide a formal or independently reviewed channel-dependency argument for the adaptive route set, and use formal/exhaustive checks where feasible.

## Assessment dimensions

| Dimension | Assessment | Confidence |
|---|---|---|
| RTL functionality under tested scenarios | Positive: all seven Icarus regressions pass | High for those exact regressions only |
| Algorithmic novelty | Unproven; existing predictive and congestion-aware routing literature is close | Low-to-moderate |
| Combination novelty | Possible research question, not established | Low |
| Implementation contribution | Concrete reusable RTL integration and validation artifact | Moderate |
| Experimental strength | Preliminary smoke/functional study; limited event count and workload coverage | High confidence in limitation |
| Attribution risk | Unresolved baseline provenance/license; no confirmed plagiarism | High confidence in provenance gap; low confidence on any plagiarism inference |
| Publication readiness | Not ready as a novelty/performance paper | Moderate |
| Patentability/freedom to operate | Not assessed and cannot be concluded | None |

## Priority actions

### Before making a novelty claim

1. Read full papers for PreNoc, Javed et al., DyAD, Hsin et al., and the 2013 congestion-prediction lead.
2. Search all bibliographic and patent databases listed in `NOVELTY_AND_PRIOR_ART.md`; follow citations, family members, and prosecution records.
3. Create an algorithm table that compares input signals, update timing, score equation, prediction horizon, candidate path constraints, cost, and reported baselines.

### Before making a performance claim

1. Use separately generated tuning and evaluation traffic. Include uniform, transpose, hotspot, burst, sustained-backpressure, and near-saturation traffic across multiple seeds.
2. Compare XY, West-First deterministic fallback, West-First TF-PCR, a reasonable occupancy-only baseline, and at least one strong established adaptive baseline if practical.
3. Report both per-cycle and event-level metrics, precision/recall/F1, false alarms per output/window, lead-time distributions, missed events, confidence intervals, and raw traces.
4. Measure network-level effects separately from route correctness. A legal detour and a passing packet scoreboard do not demonstrate better throughput or latency.

### Before publishing or distributing

1. Recover and document original-router provenance/license and create accurate attribution.
2. Add a complete bibliography; distinguish facts, implementation decisions, and research hypotheses.
3. Synthesize baseline and feature RTL if hardware-cost claims are central; record tools, constraints, target library/device and exact scripts.
4. Obtain appropriate academic and, if needed, patent/legal review. This report is not a legal opinion.

## Final decision

Continue the project as a verified RTL prototype and a testable research hypothesis. Do not describe TF-PCR as first, novel, generally superior, deadlock-proven, or hardware-efficient on the current evidence. A conditional research path is justified; a definitive novelty, performance or patent claim is not.
