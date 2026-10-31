# Run Tutorial

This guide documents the validated SNN training and RTL export flow for the congestion-predictive NoC project, along with the current blocker in the trace-generation step.

## Project status

The project was rerun successfully on the existing dataset and validation pipeline:

- Python 3.11.9 available
- NumPy 2.4.6 installed
- scikit-learn 1.9.1 installed
- Icarus Verilog / VVP 12.0 available
- 21 RTL regressions passed
- Held-out test metrics passed the project gates

## Requirements

I reran the SNN training, model exports, all RTL regressions, and accuracy evaluation. **The 21 RTL regressions passed.** Fresh trace generation did not: it stopped on a traffic-integrity error, so the accuracy below is measured on the project’s existing dataset, not a newly generated one.

## What you need

- Windows PowerShell
- Python 3.11+
- NumPy and scikit-learn
- Icarus Verilog: `iverilog` and `vvp` on `PATH`

## 1) Set up the Python environment

Open PowerShell and run:

```powershell
Set-Location "C:\Users\legen\Desktop\Capstone research\Temporal and Freq with SNN exp"

py -3.11 -m venv "$env:TEMP\capstone-snn-venv"
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" -m pip install -r .\tools\requirements-noc-snn.txt
Get-Command iverilog, vvp
```

Confirm the environment is ready:

```powershell
$python = "$env:TEMP\capstone-snn-venv\Scripts\python.exe"
& $python --version
& $python -c "import numpy, sklearn; print('numpy', numpy.__version__); print('scikit-learn', sklearn.__version__)"
iverilog -V 2>&1 | Select-Object -First 2
vvp -V 2>&1 | Select-Object -First 2
```

## 2) Trace generation

The fresh trace-generation step is currently blocked by a traffic-integrity issue in the mesh simulation.

Command attempted:

```powershell
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\generate_noc_traces.py
```

Observed failure:

- Simulation stopped during a 50%-load random traffic run
- Assertion triggered in `sim\mesh\mesh_trace_tb.sv`
- Error reported: `flit 825 was corrupted or misrouted`

This means the project cannot reliably regenerate a new trace set until the routing/integrity bug is resolved.

## 3) Train the SNN using the preserved dataset

The existing dataset and prior results remained intact, so the SNN was successfully trained from the saved CSV without regenerating traces.

```powershell
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\train_noc_snn.py
```

## 4) Export the trained model and distilled RTL

```powershell
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\export_snn_rtl.py
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\distill_noc_snn.py
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\export_equation_rtl.py
```

## 5) Run the validation regressions

```powershell
.\validation\run-project.ps1 `
  -OutputDirectory "validation\run\project-rerun-20261027" `
  -ReportPath "validation\run\PROJECT-RESULTS-rerun-20261027.txt" `
  -SnnValidationAccuracyPercent 97 `
  -SnnValidationCorrectSamples 15120 `
  -SnnValidationTotalSamples 15552
```

## 6) Evaluate the SNN and combine with regression results

Because the failed trace-generation attempt overwrote some raw trace files, the evaluation was run using an isolated copy of the intact dataset to avoid stale manifest data.

```powershell
$evalDir = ".\validation\run\predictor-eval-rerun-20261027"
New-Item -ItemType Directory -Force -Path $evalDir | Out-Null
Copy-Item .\validation\snn_experiment\dataset.csv "$evalDir\dataset.csv" -Force

& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\evaluate_noc_models.py `
  --dataset "$evalDir\dataset.csv" `
  --output "$evalDir\predictor-evaluation.json" `
  --regression-dir .\validation\run\project-rerun-20261027
```

## Results

### Accuracy summary

| SNN split | Accuracy | Recall | False-positive rate | Samples |
|---|---:|---:|---:|---:|
| Validation | 97.22% | 89.35% | 1.41% | 15,552 |
| Held-out test | 96.28% | 87.79% | 2.25% | 15,552 |

The held-out test passed the project’s stated gates for:

- accuracy
- recall
- false-positive rate

### RTL validation

All 21 RTL regressions passed.

## Final status

The training/export pipeline is working with the preserved dataset, and the end-to-end RTL validation passed. The only remaining issue is the fresh trace-generation workflow, which is blocked by a traffic-integrity failure during random runtime simulation.

## Important note

Because trace generation stopped partway through, some raw trace files may no longer match the current manifest. The successful accuracy and regression validation used the intact saved dataset in isolation, which is the reliable path until the trace-generation bug is fixed.

## Recommended next step

Fix the traffic-integrity issue in `sim\mesh\mesh_trace_tb.sv` and the random-traffic generation path, then rerun:

```powershell
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\generate_noc_traces.py
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\train_noc_snn.py
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\export_snn_rtl.py
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\distill_noc_snn.py
& "$env:TEMP\capstone-snn-venv\Scripts\python.exe" .\tools\export_equation_rtl.py
.\validation\run-project.ps1
```
