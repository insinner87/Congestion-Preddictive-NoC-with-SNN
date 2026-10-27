# Attribution and provenance audit

**Audit date:** 2026-10-24  
**Purpose:** Record what can and cannot be inferred about source origin, licensing, citations and similarity. This is not a legal opinion and not a plagiarism clearance.

## 1. Git and authorship evidence

- The Git worktree root resolves to `C:\Users\legen`, not the project directory.
- `git ls-files -- "Desktop/Capstone research/Temporal and Freq"` returned no tracked project files.
- The narrow Git status showed the project directory as untracked (`?? "Desktop/Capstone research/Temporal and Freq/"`).
- The visible branch name is `master`; no project commit history or remote is available for the project files.

Therefore, Git cannot establish who wrote or imported the RTL, when it was written, what prior versions existed, or whether its current comments reflect original authorship. This is especially important because the project history describes `router_5port.sv` as a pre-existing baseline, but no source repository/commit is available here to document that origin.

## 2. License and notices

The project tree contains no root `LICENSE`, `COPYING`, `NOTICE`, `AUTHORS`, or `CITATION` file. The inspected RTL/testbench files do not contain SPDX identifiers or copyright/license headers. No third-party source attribution notice was found by searching the source/documentation for copyright, SPDX, license, author and attribution markers.

Absence of a license file does not establish that the code is public domain, owned by the present author, or freely reusable. Obtain provenance and permission for the original baseline and any reused modules before publishing or distributing the project.

## 3. Citation and attribution observations

- `docs/TF-PCR-VALIDATION.md:109-113` cites C. J. Glass and L. M. Ni, “The Turn Model for Adaptive Routing,” ISCA 1992, pp. 278-287. The in-text citation is useful but lacks a full bibliography entry/DOI and is the only located named research citation.
- The documentation's score equation and parameter choices have no accompanying literature citation or explicit statement of whether they are independently proposed, adapted, or selected as an initial engineering configuration.
- The predictor event definition, occupancy comparator, route-score decision policy, and performance metrics have no separate bibliography beyond the turn-model citation.
- Standard terms and patterns—ready/valid, FIFO, round-robin arbitration, crossbar, XY, mesh, West-First—are ordinary technical terminology and are not evidence of plagiarism.
- No exact textual match to an external source was established in this audit. The files are small enough to inspect, but no recognized plagiarism checker or complete source-repository comparison was run.

## 4. Potential similarity/provenance risks

| Location | Observation | Evidence / confidence | Recommended action |
|---|---|---|---|
| `rtl/router/*`, especially `router_5port.sv` | The design is presented as an existing router baseline, but Git provides no tracked version or original attribution. | Confirmed provenance gap; **high confidence** that the repository itself cannot prove origin. No copying conclusion. | Identify the original author/repository/source and version; record license, commit/URL, and any local changes. Preserve notices. |
| All RTL files | No license/SPDX headers or third-party notices found. | Search of project text; **high confidence** for absence in the inspected tree, not for external ownership. | Establish project license and verify reuse rights before public release. |
| `docs/TF-PCR-VALIDATION.md` score formula/defaults | Formula and constants are reported without a citation or origin note. | **Medium confidence** citation gap; not evidence of copying. | State which elements are standard, designed here, adapted, or selected empirically; cite prior work for reused algorithmic ideas. |
| West-First statements | Turn model is cited but the deadlock argument is concise and lacks a complete bibliographic entry. | **High confidence** documentation could be stronger; no copied text identified. | Add full Glass–Ni bibliographic record/DOI and explain channel-dependency reasoning in original wording. |
| Project prose/comments | No known verbatim external source match found by this limited check. | **Low confidence** any global originality statement; no similarity service or corpus comparison. | Run an institution-approved similarity review over the manuscript and an authorized code provenance review; do not upload private code to third-party services without approval. |

## 5. Plagiarism conclusion and limitations

**No confirmed plagiarism was identified, but this audit cannot conclude that the work is plagiarism-free.** No suspicious passage could be tied to an exact external source with adequate evidence. This is not a positive originality certificate:

- a public-web search does not cover subscription databases, private repositories, unpublished theses, or all versions;
- generic RTL structure and well-known routing algorithms can be similar without plagiarism;
- code similarity needs source-to-source comparison and provenance/license context;
- AI-assisted origin does not itself prove either originality or plagiarism;
- no complete commit history, source-of-baseline record, plagiarism service, or legal review was available.

## 6. Practical provenance checklist

1. Recover the baseline router's original URL, author, license, and commit/release.
2. Keep original notices in source files and document local edits distinctly.
3. Add a `LICENSE` only after confirming that the project author has authority to grant it; do not invent ownership.
4. Add a references section for the turn model, predictors, congestion metrics, and adaptive routing being compared.
5. Save exact citations and source PDFs/DOIs in a bibliography; attribute any reused equations, figures, pseudocode, or test methodology.
6. If similarity checking is required, use an approved tool and only submit material authorized for that service.
