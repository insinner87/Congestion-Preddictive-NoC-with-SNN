# Novelty and prior-art audit

**Search date:** 2026-10-24  
**Scope:** A bounded web literature/patent lead search plus comparison with the inspected RTL. This is not a systematic review, patentability opinion, freedom-to-operate analysis, or originality certificate.

## A. Search method and actual coverage

### Sources actually queried

- **Google Scholar:** multiple acronym-independent searches listed below. Search snippets and result links were inspected. It was useful for discovery, but is an index, not the primary source.
- **Crossref API:** exact DOI records and selected title queries for bibliographic metadata. Some requests returned HTTP 429. Crossref metadata is not a full-text method review.
- **Google Patents:** search-index queries and the available page for US12184553B2. Some pages and searches returned HTTP 503.
- **Publisher endpoints:** attempted ACM, IEEE, ScienceDirect and one IAES/TELKOMNIKA URL. ACM returned HTTP 403; IEEE returned an account/login page instead of the record; ScienceDirect returned an error; the IAES URL returned 404. These failures are recorded rather than treated as evidence that a result does not exist.

**Not searched in this pass:** ACM Digital Library as an independent search index (its pages were blocked), IEEE Xplore as an independent query service, Semantic Scholar, arXiv, institutional repositories as a systematic collection, WIPO PATENTSCOPE, Espacenet, and USPTO Patent Center. Their existence is not implied by the searches above.

### Search queries used

Google Scholar:

1. `"buffer level" change-based predictive congestion routing network-on-chip` — no exact result.
2. `"network-on-chip" "congestion prediction" adaptive routing`
3. `"demand" "service" congestion metric network-on-chip routing`
4. `NoC predictive congestion adaptive routing buffer occupancy history`
5. `"network-on-chip" congestion estimation temporal history routing`
6. `"predictive routing" NoC congestion network-on-chip`
7. `"Predicting networks-on-chip traffic congestion with spiking neural networks"`
8. `"Congestion Prediction Algorithm for Network on Chip" Cai Yang` — no exact result in Scholar at access time.

Crossref:

- Exact record requests for `10.1109/ISCA.1992.753324`, `10.1109/71.877831`, `10.1145/996566.996638`, `10.1145/3060403.3060406`, and `10.1145/2377677.2377757`.
- Title queries for “Proactive Adaptation-Based Routing Strategies in 2D Network-on-Chip Architectures,” “Spatial-Temporal Enhancement of ACO-Based Selection Schemes for Adaptive Routing in Network-on-Chip Systems,” and “Congestion Prediction Algorithm for Network on Chip.”
- Requests for the SNN predictor/hotspot-prediction title queries were rate-limited (HTTP 429).

Google Patents:

- `network on chip congestion routing`
- `network-on-chip predictive congestion routing`
- `network-on-chip adaptive congestion-aware routing`
- `network-on-chip predictive congestion adaptive router`

These broad patent queries return many irrelevant records. Search-result snippets are leads only; patent titles/snippets do not reveal the scope of claims.

## B. Bibliographic leads and overlap

“Evidence inspected” below distinguishes verified publication metadata from title/snippet-level understanding. Do not make fine-grained claim comparisons until the complete papers and patent claims are read.

| Relevance | Work / source | Congestion signals or method visible in available evidence | Relation and limitation |
|---|---|---|---|
| **Closest: predictive routing** | M. A. Kinsy, S. Khadka, M. Isakov, **“PreNoc: Neural Network based Predictive Routing for Network-on-Chip Architectures,”** GLSVLSI 2017, pp. 65–70, DOI [10.1145/3060403.3060406](https://doi.org/10.1145/3060403.3060406). Crossref verified title, authors, venue, date and pages; Scholar result describes neural-network predictive NoC routing. ACM page returned 403. | Predictive routing for NoC using neural networks; the available search evidence does not establish its full inputs, labels, or routing restrictions. | Strong evidence that “predictive NoC routing” itself is not new. The project differs in using a small deterministic score from waits, consecutive blocked cycles, and a completed request/service window, then restricting choices to West-First minimal alternatives. Read the paper to verify this distinction. |
| **Closest: NoC congestion prediction** | A. Javed, J. Harkin, L. McDaid, J. Liu, **“Predicting networks-on-chip traffic congestion with spiking neural networks,”** Journal of Parallel and Distributed Computing (2021), [ScienceDirect record](https://www.sciencedirect.com/science/article/pii/S0743731521000666). Title/authors/year/venue surfaced in Scholar; Crossref/publisher access was unsuccessful in this audit. | Explicitly predicts NoC traffic congestion using spiking neural networks, based on the indexed title/result. | Direct conceptual overlap in prediction target, but model/observations may differ substantially. DOI and technical details remain unverified here; do not compare performance or claim algorithmic difference without full text. |
| **Closest: congestion-aware route selection** | J. Hu and R. Marculescu, **“DyAD: Smart Routing for Networks-on-Chip,”** DAC 2004, pp. 260–263, DOI [10.1145/996566.996638](https://doi.org/10.1145/996566.996638). Metadata verified in Crossref; ACM page returned 403. | The title and bibliographic record identify smart NoC routing; detailed mechanism not read in this pass. | Earlier adaptive/smart NoC routing is established prior art. It must be compared against this project’s route-choice rule, not dismissed because the score formula differs. |
| **Related: temporal/spatial adaptive route selection** | H.-K. Hsin, E.-J. Chang, A.-Y. Wu, **“Spatial-Temporal Enhancement of ACO-Based Selection Schemes for Adaptive Routing in Network-on-Chip Systems,”** IEEE TPDS 25(6), 2014, pp. 1626–1637, DOI [10.1109/TPDS.2013.299](https://doi.org/10.1109/TPDS.2013.299). Crossref metadata verified; IEEE page returned login material. | Title establishes use of spatial-temporal information to enhance adaptive route selection; algorithm detail not inspected. | “Temporal” history combined with adaptive routing is not, by itself, a novel distinction. The specific measure, update semantics, and deadlock-safe decision rule need comparative analysis. |
| **Related: explicit congestion prediction** | H. Cai and Y. Yang, **“Congestion Prediction Algorithm for Network on Chip,”** TELKOMNIKA Indonesian Journal of Electrical Engineering 11(12), 2013, DOI [10.11591/telkomnika.v11i12.3987](https://doi.org/10.11591/telkomnika.v11i12.3987). Crossref record lists these authors/title/venue; its publisher URL returned 404 and Scholar exact search returned no hit. | Indexed title and metadata only; full method and paper status were not verified. | A very direct title-level prior-art lead. Obtain the full paper and resolve metadata/authorship differences before relying on it. No method-level conclusion is made here. |
| **Related: congestion-control context** | G. P. Nychis, C. Fallin, T. Moscibroda, O. Mutlu, S. Seshan, **“On-chip networks from a networking perspective,”** SIGCOMM Computer Communication Review 42(4), 2012, pp. 407–418, DOI [10.1145/2377677.2377757](https://doi.org/10.1145/2377677.2377757). Crossref metadata and abstract verified. | The abstract discusses congestion in bufferless NoCs and an application-aware source-throttling congestion-control mechanism. | Useful conceptual background; it is specifically bufferless/source-throttling work, not the same buffered router or TF-PCR score. |
| **Established routing restriction** | C. J. Glass and L. M. Ni, **“The Turn Model for Adaptive Routing,”** ISCA 1992, pp. 278–287, DOI [10.1109/ISCA.1992.753324](https://doi.org/10.1109/ISCA.1992.753324). Crossref metadata verified. | Turn restrictions are the routing/deadlock framework cited by the project. | West-First is established; this project’s contribution cannot be the turn model itself. The report needs a precise channel-dependency argument for its particular topology and implementation. |
| **Established routing restriction (alternative)** | G.-M. Chiu, **“The odd-even turn model for adaptive routing,”** IEEE TPDS 11(7), 2000, pp. 729–738, DOI [10.1109/71.877831](https://doi.org/10.1109/71.877831). Crossref metadata verified. | A known alternative turn restriction for adaptive routing. | Background comparator for choices of deadlock-safe adaptive routing; not implemented in this repository. |

### Patent search record

| Result | Verified status/evidence | Relevance assessment |
|---|---|---|
| **CN105871742B**, search-index title “Adaptive router based on virtual output queue mechanism in a kind of network-on-chip.” It appeared in a Google Patents search result. | The Google Patents page and a targeted follow-up query returned HTTP 503. Applicant, priority date, family, grant status and claim text were **not verified**. Stable search-result lead: [Google Patents record](https://patents.google.com/patent/CN105871742B/en). | It appears NoC-router related by indexed title, but virtual-output-queue wording alone does not establish overlap with TF-PCR. Treat as an unreviewed lead; obtain official CN publication/claims and translations. |
| **US12184553B2**, indexed page title “Prediction-based network routing,” application US18/392,386; the fetched Google Patents page reported priority 2014-06-17, US publication/grant 2024-12-31, Comcast Cable Communications LLC, and “Active” status (the page itself cautions that legal status is an assumption). | Initial page content and metadata were fetched, but later retrieval of the claims section returned HTTP 503. Claims were **not analyzed**. [Google Patents page](https://patents.google.com/patent/US12184553B2/en). | Broad prediction-based network routing is a search lead, but the accessible information did not show NoC-specific claims. Do not infer that it covers or excludes this RTL. Check official USPTO file history and claim text with counsel if commercially relevant. |

No patent search in this audit was exhaustive. WIPO PATENTSCOPE, Espacenet and USPTO Patent Center were not independently queried. No infringement, patentability, ownership, validity, or freedom-to-operate conclusion is made.

## C. Comparison matrix

| Prior work | Congestion signals | Prediction/detection | Routing restrictions | Hardware architecture | Evaluation/baselines | Overlap with this implementation | Evidence-supported distinction / confidence |
|---|---|---|---|---|---|---|---|
| PreNoc (2017) | Not established from available metadata/snippet | Neural network-based predictive routing | Not established here | NoC predictive routing (full architecture not inspected) | Not established here | Predictive routing in a NoC | Project uses integer counters/weighted score and West-First minimal candidates; whether the metric is distinctive remains unverified. **Medium** on broad overlap, **low** on detailed comparison. |
| Javed et al. SNN congestion prediction (2021) | Not established without full text | Spiking neural networks predict NoC traffic congestion | Not established | NoC | Not established | Same broad prediction objective | Predictor class differs at title level; not evidence that the project score is novel. **Low-to-medium**. |
| DyAD (2004) | Not inspected in this pass | “Smart routing” title-level evidence | Not inspected | NoC | Not inspected | Congestion-aware/adaptive routing is the issue to compare | Need full paper for a defensible mechanism-level distinction. **Low** details / **high** relevance. |
| Hsin et al. (2014) | Spatial/temporal information in title | ACO-based selection enhancement | Adaptive route selection | NoC | Not inspected | Uses temporal/spatial history for adaptive routing | Different model is suggested by title; exact distinctions require full text. **Medium**. |
| Cai & Yang (2013) | Not inspected | Congestion prediction in NoC by title | Not verified | NoC | Not verified | Same broad prediction problem | Metadata/page limitations prevent comparison. **Low**. |
| Glass & Ni (1992) | Not a congestion predictor | Not a predictor | Turn-model deadlock avoidance | Mesh routing theory | Theoretical model paper | Supports West-First safety rationale | West-First is established prior art, not a novelty element. **High**. |
| Chiu (2000) | Not a congestion predictor | Not a predictor | Odd-Even turn model | Adaptive mesh routing | Theoretical/algorithm paper | Alternative deadlock-safe adaptive model | Not implemented; useful design baseline. **High** metadata. |
| Nychis et al. (2012) | Bufferless NoC congestion | Source-throttling congestion control | Not the same router adaptation | Bufferless on-chip networks | Performance/scalability analysis per abstract | Congestion control is an established NoC concern | Buffered 4x4 score-based route selection differs; broad context only. **High** abstract-level. |

## D. Novelty by technical element

| Element in this repository | Preliminary classification | Reason |
|---|---|---|
| Per-requester waiting/age counters | **Known technique / implementation detail** | Request age and waiting are standard arbitration/congestion signals; no comparative evidence in this audit supports novelty. |
| Consecutive per-output blocked-cycle counter | **Known technique / implementation detail** | A directly observed ready/valid blockage duration is intuitive and likely conventional; exact source review still needed. |
| Fixed-window demand and successful-service counts | **Known technique with a particular implementation** | Rate/service accounting is conventional. Counting one request-cycle per asserted requester and comparing with output transfer cycles is the exact implementation choice, not proof of novel metric. |
| `max(0, demand-service)` window deficit | **Potentially distinctive implementation choice, unproven** | The exact definition is clear and testable, but demand and service aggregation is a familiar performance-accounting pattern. |
| Saturating normalization to 8-bit 0..255 and 3:1 time/frequency weighted average | **Potentially distinctive parameterization, not demonstrated novelty** | Weighted score and saturation are common design tools. The audit found no independent prior-art search deep enough to support novelty of this formula. |
| Score threshold `>=128` as congestion flag | **Standard/configuration choice** | A tunable threshold is not itself a contribution. |
| West-First minimal alternatives selected by local score | **Known algorithm family plus a potentially distinctive integration** | Adaptive congestion-aware routing and West-First restrictions predate this project. The specific decision policy deserves full comparison against DyAD and predictive-routing works. |
| Existing-router wrapper with 64-bit coordinate packet and route-field rewrite | **Engineering implementation contribution** | Useful integration, but a 4x4 mesh and coordinate routing are established design patterns. |
| Side-by-side occupancy comparator and future blockage event | **Potential experimental contribution, currently weakly supported** | There is a fair same-run comparator, but only limited traces/events; no tuning split or raw trace publication. |
| Name “TF-PCR” | **Not a novelty claim** | Coining an acronym does not make an algorithm new. |

## E. Candidate defensible contribution statement

If the work is continued and prior-art review confirms a gap, a cautious current statement could be:

> “We implemented and evaluated a parameterized RTL congestion-risk score combining per-requester wait, per-output consecutive output blockage, and a windowed request-cycle/service-cycle deficit, and used its thresholded output to choose among legal West-First minimal next hops in a 4x4 mesh built from an existing five-port router.”

This describes an implementation and evaluation. It does **not** claim that the counters, weighted score, West-First routing, predictive NoC routing, or the combination is first. A novelty claim should be narrowed only after full-text prior-art comparison and careful claim/equation matching.

## F. Search matrix for the next literature pass

| Topic | Acronym-independent queries to run in IEEE Xplore, ACM DL, Google Scholar, Crossref/Semantic Scholar, arXiv and institutional repositories |
|---|---|
| Buffer-level-change predictive routing | `"network on chip" predict congestion buffer occupancy change`; `"buffer level variation" predictive routing mesh interconnect`; `"queue growth rate" adaptive router NoC` |
| Time/history congestion | `"network on chip" congestion history wait time`; `"router output blocked cycles" congestion metric`; `"temporal congestion estimation" mesh router` |
| Demand/service deficit | `"NoC" offered load service rate congestion metric`; `"request count" "successful transfers" router congestion`; `"demand service deficit" adaptive routing interconnect` |
| Moving window/weighted scores | `"network on chip" sliding window congestion score weighted`; `"windowed traffic demand" output service adaptive routing`; `"congestion score" normalization router NoC` |
| Occupancy/backpressure baselines | `"NoC" occupancy threshold congestion detector backpressure`; `"buffer occupancy" predictor adaptive routing mesh`; `"valid ready" blocked cycles congestion router` |
| West-First and turn models | `"West-First" adaptive routing mesh deadlock`; `"turn model" west first channel dependency`; `"west-first" congestion-aware minimal routing` |
| Prediction coupled to route choice | `"predictive routing" network on chip congestion`; `"congestion prediction" "route selection" NoC`; `"future congestion" adaptive minimal routing mesh` |
| Hardware implementation cost | `"NoC" congestion predictor RTL area power FPGA`; `"predictive adaptive routing" router synthesis area`; `"congestion estimation" NoC hardware overhead` |
| Patent claims | Google Patents, WIPO PATENTSCOPE, Espacenet and USPTO searches: `"network-on-chip" congestion predictor router`; `"NoC" predicted congestion route selection`; `"buffer occupancy history" router patent`; `("request count" OR "service rate") congestion routing patent` |

For every database search, save the exact query/date, export result IDs, inspect full abstracts/full texts, then follow citations and patent families. For patents, compare **independent and dependent claims**, priority/family, prosecution history, jurisdiction and legal status using the official office record; abstracts are not claim scope.

## G. Limits

This search is a first-pass discovery audit. Google Scholar and search result snippets can omit records, rank results unpredictably, and show false matches. Several recent or relevant results could not be accessed in full. No claim is made that all papers or patents were found. There has been no legal review, systematic PRISMA-style review, patent-family analysis, or source-code/public-repository similarity search.
