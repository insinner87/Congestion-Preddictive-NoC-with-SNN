# Executive summary

**Audit date:** 2026-10-24  
**Scope:** Read-only inspection of RTL, testbenches, scripts, saved results and Git metadata; a new seven-run Icarus regression; limited public prior-art searches.  
**Recommendation:** **CONDITIONAL GO** to continue as an engineering and research investigation; **not yet a defensible claim of algorithmic novelty or a paper-ready evaluation.**

## What the design actually implements

The project keeps a five-port, input-buffered router and adds an optional congestion-measurement branch. The monitor measures requester-cycle demand, successful output handshakes, per-requester waiting, and per-output consecutive blocked cycles. The estimator normalizes the largest requester wait/output blocked value and the last completed window's demand/service deficit, combines the scores with default weights 3:1, and asserts a threshold bit. The standalone router does **not** use that score to arbitrate.

The separate 4x4 integration wraps 16 instances of that router. At each ingress it rewrites a 3-bit next-hop field in a 64-bit flit, preserving a 2-bit destination X and 2-bit destination Y. XY mode is deterministic. West-First mode permits a limited set of minimal alternatives; when the preferred hop is predicted congested, the selector can choose the lower-score legal hop. Thus, congestion diagnostics affect the mesh's **route choice through the wrapper**, not the router's switch allocator. See [SOURCE_CODE_AUDIT.md](./SOURCE_CODE_AUDIT.md).

## Five important findings

1. **The score is a history/current-state indicator, not a self-contained forecast model.** The RTL thresholds present requester wait, present consecutive blocking and a completed past window's demand/service deficit. The 8-cycle future-event label exists only in the mesh testbench.
2. **The mesh does route adaptively in West-First mode.** `noc_router_wrapper` passes TF-PCR score/prediction signals into `mesh_route_compute`; a directed test forces a legal lower-score choice. The router's own allocator still follows destination-fixed requests.
3. **The West-First model is established prior art.** The project cites Glass and Ni; minimal adaptive routing and congestion-aware routing also have substantial earlier literature, including DyAD and predictive NoC routing works. The specific weighted score/combination is not established as novel by this audit.
4. **Simulation proves finite regression behavior, not broad performance or formal properties.** All seven regression categories passed in Icarus, but measured results come from one deterministic trace family, only six labeled sustained-blocking events, and no separate tuning/evaluation traces. No RTL synthesis, area, power, timing, or formal-deadlock result exists.
5. **Code provenance is not available from Git.** The project files are untracked in a parent Git worktree, with no project commits or remotes; no license or NOTICE file was found. This prevents a reliable authorship/code-origin audit. No plagiarism-free conclusion is possible.

## Closest prior-art leads

- **PreNoc (2017)** is directly titled as neural-network-based predictive routing for NoCs: Kinsy, Khadka and Isakov, DOI [10.1145/3060403.3060406](https://doi.org/10.1145/3060403.3060406). It demonstrates that predictive NoC routing predates this implementation; its predictor is not the same algorithm as the project's fixed-point wait/deficit estimator.
- **Predicting networks-on-chip traffic congestion with spiking neural networks (2021)** is a direct NoC congestion-prediction lead, surfaced in Google Scholar; its publisher page is [ScienceDirect](https://www.sciencedirect.com/science/article/pii/S0743731521000666). The publisher and Crossref endpoints could not be fully retrieved during this audit, so metadata and technical comparison remain provisional.
- **DyAD: Smart Routing for Networks-on-Chip (2004)** is an early congestion-aware smart-routing lead: Hu and Marculescu, DAC, DOI [10.1145/996566.996638](https://doi.org/10.1145/996566.996638). Metadata was verified through Crossref; the ACM page returned HTTP 403, so detailed method/claim comparison needs the paper text.

See [NOVELTY_AND_PRIOR_ART.md](./NOVELTY_AND_PRIOR_ART.md) for the bounded search record, additional sources, query list, patent leads, and comparison matrix.

## Preliminary decision

| Question | Finding |
|---|---|
| Is the current implementation worth continuing? | **Yes, conditionally.** It is a working RTL integration with a useful test suite and a concrete, measurable comparison problem. Preserve the current baseline and improve the experimental design. |
| Is the algorithm currently established as a research contribution? | **No.** Prior predictive and congestion-aware NoC work is close enough that a careful algorithm-level comparison and evidence for the exact differentiator are required. |
| Is the evidence sufficient to submit a research paper now? | **No.** The current traffic evidence is narrow, no hardware-cost study exists, no train/tune/evaluation separation is reported, and provenance/references need improvement. |

These are research-readiness judgments, not patentability, legal, or plagiarism determinations. Confidence is **moderate** for the RTL/dataflow findings and **low-to-moderate** for novelty because the literature/patent search was intentionally limited and some publisher/patent pages were unavailable.

## Most important next actions

1. Build a verified, citation-complete related-work review around predictive congestion methods, DyAD, congestion-aware adaptive routing, West-First, and patent claims; obtain and read full texts for the closest papers.
2. Define a causal predictor observation point and evaluation protocol before measuring it: separate tuning and held-out traces, more seeds/traffic patterns, event-level metrics, confidence intervals, and raw prediction/event traces.
3. Add implementation-cost evidence using a suitable synthesis flow, plus formal or exhaustive channel-dependency/reachability checks; do not claim area, frequency, power, or deadlock proof before those exist.

## Audit artifacts

All requested report files are in this folder. The fresh simulation outputs are preserved in [verification-run](./verification-run/); no existing RTL, testbench, script, documentation, or saved result was edited by this audit.
