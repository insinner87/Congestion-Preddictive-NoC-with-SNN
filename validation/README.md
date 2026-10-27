# Validation workflow

## One-command scripts

Run these from PowerShell; each script resolves the project root itself, so
the current directory does not matter:

- `powershell -ExecutionPolicy Bypass -File "C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp\validation\run-router.ps1"` runs the original five-port router.
- `powershell -ExecutionPolicy Bypass -File "C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp\validation\run-mesh.ps1"` runs the 4x4 mesh.
- `powershell -ExecutionPolicy Bypass -File "C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp\validation\run-project.ps1"` runs all 21 RTL regressions and puts the summary and full test output in `validation\run\PROJECT-RESULTS.txt`.
- `powershell -ExecutionPolicy Bypass -File "C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp\validation\run-complete.ps1"` runs the full RTL suite, five seeded traffic scenarios, flit scoreboarding, and frozen-model evaluation.

The router script accepts `-DisableTfPcr`. The mesh script accepts
`-Routing XY` or `-Routing WestFirst`, `-DisableTfPcr`, `-EnablePriority`, and
`-EnableEquationRouting`.
Standalone run artifacts are written to timestamped folders under
`validation\run\standalone`.

`run-all.ps1` is the underlying full-suite runner. It compiles and executes
twenty-one self-checking simulations, stopping on the first failure. It accepts
`-OutputDirectory` for choosing where that run's generated files go. Earlier
saved results under `validation\results\` and `validation\run\mesh-west-first`
are preserved.

`run-complete.ps1` requires Python 3.11+ with packages in
`tools\requirements-noc-snn.txt`, plus `iverilog` and `vvp` on `PATH`. The
defaults generate 120 trace runs (256 cycles each), using disjoint seed splits,
loads 5/50/95, and no-congestion/random/moderate/severe/mixed workloads. It
evaluates the frozen SNN on the generated validation split, passes the exact
correct/total sample counts to the adaptive RTL regression, then produces the
final evaluation with regression results. Pass `-PythonExecutable` to select a
different Python command, or customize seeds, loads, workloads, and cycle
count. All generated artifacts are placed under a timestamped
`validation\run\complete-*` directory; model files are not overwritten.
