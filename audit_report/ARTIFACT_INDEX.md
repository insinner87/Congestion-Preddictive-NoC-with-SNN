# Artifact index

**Audit date:** 2026-10-24  
**Root:** `C:\Users\legen\Desktop\Capstone research\Temporal and Freq`

## Reports created by this audit

- [EXECUTIVE_SUMMARY.md](./EXECUTIVE_SUMMARY.md) — findings and decision summary.
- [SOURCE_CODE_AUDIT.md](./SOURCE_CODE_AUDIT.md) — RTL architecture, algorithms, signal dependencies and parameters.
- [VERIFICATION_AUDIT.md](./VERIFICATION_AUDIT.md) — test coverage, fresh run results, metrics and limitations.
- [NOVELTY_AND_PRIOR_ART.md](./NOVELTY_AND_PRIOR_ART.md) — search method, papers/patent leads, comparison and query matrix.
- [ATTRIBUTION_AND_PROVENANCE.md](./ATTRIBUTION_AND_PROVENANCE.md) — Git, licenses, citations and originality limitations.
- [GO_NO_GO_ASSESSMENT.md](./GO_NO_GO_ASSESSMENT.md) — three verdicts and conditions.
- [ARTIFACT_INDEX.md](./ARTIFACT_INDEX.md) — this index.

## Fresh regression artifacts

All seven test runs were freshly executed with `validation/run-all.ps1`; output was directed to the new `verification-run/` subtree to preserve saved project results:

| Test | Fresh log | Compiler log |
|---|---|---|
| TF-PCR monitor | `verification-run/tfpcr-monitor/tfpcr-monitor.log` | `verification-run/tfpcr-monitor/compile.log` |
| Router, feature enabled | `verification-run/router-enabled/router-enabled.log` | `verification-run/router-enabled/compile.log` |
| Router, feature disabled | `verification-run/router-disabled/router-disabled.log` | `verification-run/router-disabled/compile.log` |
| XY/West-First route compute | `verification-run/mesh-routes/mesh-routes.log` | `verification-run/mesh-routes/compile.log` |
| XY mesh | `verification-run/mesh-xy/mesh-xy.log` | `verification-run/mesh-xy/compile.log` |
| West-First + TF-PCR | `verification-run/mesh-west-first/mesh-west-first.log` | `verification-run/mesh-west-first/compile.log` |
| West-First baseline | `verification-run/mesh-west-first-baseline/mesh-west-first-baseline.log` | `verification-run/mesh-west-first-baseline/compile.log` |

Router run directories also contain their generated `router_5port_results.txt` and `router_5port_tb.vcd`. Mesh runs print prediction and packet metrics in the simulation log; no mesh raw waveform is generated.

## Key source files inspected

### RTL

- `rtl/common/noc_pkg.sv`
- `rtl/router/router_5port.sv`
- `rtl/router/input_buffer.sv`
- `rtl/router/fifo.sv`
- `rtl/router/switch_allocator.sv`
- `rtl/router/round_robin_arbiter.sv`
- `rtl/router/crossbar.sv`
- `rtl/congestion/congestion_monitor.sv`
- `rtl/congestion/congestion_estimator.sv`
- `rtl/mesh/noc_mesh_4x4.sv`
- `rtl/mesh/noc_router_wrapper.sv`
- `rtl/mesh/mesh_route_compute.sv`
- `rtl/mesh/mesh_link_fifo.sv`

### Testbenches and included test files

- `sim/congestion/tfpcr_monitor_tb.sv`
- `sim/router/router_5port_tb.sv`
- `sim/router/router_5port_tb_checks.svh`
- `sim/router/router_5port_tb_drivers.svh`
- `sim/router/router_5port_tb_scenarios.svh`
- `sim/mesh/mesh_route_compute_tb.sv`
- `sim/mesh/mesh_noc_tb.sv`
- `sim/mesh/mesh_noc_tb_observers.svh`
- `sim/mesh/mesh_noc_tb_helpers.svh`
- `sim/mesh/mesh_noc_tb_detector_eval.svh`
- `sim/mesh/mesh_noc_tb_scenarios.svh`
- `sim/mesh/mesh_noc_tb_watchdog.svh`

### Build, documentation and saved-result sources

- `README.md`
- `docs/TF-PCR-VALIDATION.md`
- `validation/run-all.ps1`
- `validation/run-router.ps1`
- `validation/run-mesh.ps1`
- `validation/run-project.ps1`
- `validation/results/router-enabled.log`
- `validation/results/router-disabled.log`
- `validation/results/tfpcr-monitor.log`
- `validation/results/mesh-route-tests.log`
- `validation/results/mesh-xy.log`
- `validation/results/mesh-west-first-tfpcr.log`
- `validation/results/mesh-west-first-baseline.log`
- `validation/run/PROJECT-RESULTS.txt`

## External research records consulted

Only sources actually queried are listed. See `NOVELTY_AND_PRIOR_ART.md` for exact search strings and access limitations.

- Crossref metadata: Glass and Ni DOI `10.1109/ISCA.1992.753324`; Chiu DOI `10.1109/71.877831`; DyAD DOI `10.1145/996566.996638`; PreNoc DOI `10.1145/3060403.3060406`; Nychis et al. DOI `10.1145/2377677.2377757`; Hsin et al. DOI `10.1109/TPDS.2013.299`; Cai and Yang DOI `10.11591/telkomnika.v11i12.3987`.
- Google Scholar query results for predictive routing, congestion prediction, temporal/historical congestion, occupancy/service metrics, and identified papers.
- Google Patents search results for NoC/congestion/adaptive routing and the accessible initial page for US12184553B2. The CN NoC patent lead and US claims section could not be verified due HTTP 503.
- Attempts to retrieve ACM, IEEE, ScienceDirect and IAES publisher pages; failures/partial access are documented rather than treated as negative evidence.

## Git and tool evidence

- Git root is the parent directory `C:\Users\legen`; no project files were tracked, project path was untracked, and no project remote/history was available.
- Icarus Verilog and VVP version: `12.0 (devel) (s20150603-1539-g2693dd32b)`.
- Verilator, Yosys, Quartus, Vivado, Verible lint, SymbiYosys and common solver tools were not found on PATH during this audit.
- No plagiarism checker, source-code similarity service, synthesis tool, or formal verification tool was used.
