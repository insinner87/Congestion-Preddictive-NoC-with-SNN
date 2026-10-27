param(
    [string]$OutputDirectory,
    [ValidateRange(16, 4096)]
    [int]$TraceCycles = 256,
    [string]$TrainSeeds = '1001,1002',
    [string]$ValidationSeeds = '2001',
    [string]$TestSeeds = '3001,3002,3003,3004,3005',
    [string]$Loads = '5,50,95',
    [string]$Workloads = 'no_congestion,random,moderate,severe,mixed',
    [string]$PythonExecutable
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $runDirectory = Join-Path $PSScriptRoot "run\complete-$timestamp"
}
elseif ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $runDirectory = $OutputDirectory
}
else {
    $runDirectory = Join-Path $projectRoot $OutputDirectory
}
$regressionDirectory = Join-Path $runDirectory 'regressions'
$traceDirectory = Join-Path $runDirectory 'traces'
$regressionReport = Join-Path $runDirectory 'regression-report.txt'
$evaluationReport = Join-Path $runDirectory 'predictor-evaluation.json'
$validationEvaluationReport = Join-Path $runDirectory 'validation-predictor-evaluation.json'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

foreach ($tool in @('iverilog', 'vvp')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required simulator command '$tool' was not found on PATH."
    }
}

if ([string]::IsNullOrWhiteSpace($PythonExecutable)) {
    $defaultVenvPython = Join-Path $env:TEMP 'capstone-snn-venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $defaultVenvPython) {
        $PythonExecutable = $defaultVenvPython
    }
    else {
        $PythonExecutable = 'py'
    }
}
$pythonCommand = Get-Command $PythonExecutable -ErrorAction SilentlyContinue
if (-not $pythonCommand) {
    throw "Python command '$PythonExecutable' was not found. Install Python 3.11+ or pass -PythonExecutable."
}
$pythonPrefix = @()
if ($pythonCommand.Name -eq 'py.exe' -or $pythonCommand.Name -eq 'py') {
    $pythonPrefix = @('-3')
}
$pythonPath = $pythonCommand.Source
& $pythonPath @pythonPrefix -c 'import numpy, sklearn'
if ($LASTEXITCODE -ne 0) {
    throw "Python dependencies are missing. Install tools\requirements-noc-snn.txt in the selected Python environment."
}

$powershell = (Get-Process -Id $PID).Path
$traceGenerator = Join-Path $projectRoot 'tools\generate_noc_traces.py'
Write-Host 'Generating seeded congestion scenarios and scored route traces'
& $pythonPath @pythonPrefix $traceGenerator `
    --data-dir $traceDirectory `
    --cycles $TraceCycles `
    --train-seeds $TrainSeeds `
    --validation-seeds $ValidationSeeds `
    --test-seeds $TestSeeds `
    --loads $Loads `
    --workloads $Workloads
if ($LASTEXITCODE -ne 0) {
    throw "Traffic generation or flit-integrity verification failed."
}

$modelEvaluator = Join-Path $projectRoot 'tools\evaluate_noc_models.py'
Write-Host 'Evaluating frozen models on validation traces to derive the exact SNN gate'
& $pythonPath @pythonPrefix $modelEvaluator `
    --dataset (Join-Path $traceDirectory 'dataset.csv') `
    --output $validationEvaluationReport
if ($LASTEXITCODE -ne 0) {
    throw "Validation predictor evaluation failed."
}
$validationReport = Get-Content -LiteralPath $validationEvaluationReport -Raw |
    ConvertFrom-Json
if (-not $validationReport.validation -or
    -not $validationReport.validation.snn -or
    -not $validationReport.validation.snn.confusion_matrix) {
    throw "Validation report does not contain SNN confusion-matrix metrics."
}
$validationSamples = [int]$validationReport.validation.snn.samples
$validationCorrect = [int]$validationReport.validation.snn.confusion_matrix[0][0] +
    [int]$validationReport.validation.snn.confusion_matrix[1][1]
if ($validationSamples -le 0 -or $validationCorrect -lt 0 -or
    $validationCorrect -gt $validationSamples) {
    throw "Validation SNN sample counts are invalid: $validationCorrect/$validationSamples."
}
$validationPercent = [int][Math]::Floor(
    (100.0 * $validationCorrect) / $validationSamples
)
Write-Host "SNN validation accuracy: $validationCorrect/$validationSamples ($validationPercent% truncated)"

$runProject = Join-Path $PSScriptRoot 'run-project.ps1'
Write-Host "Running full RTL regression with the measured validation gate in $regressionDirectory"
& $powershell -NoProfile -ExecutionPolicy Bypass -File $runProject `
    -OutputDirectory $regressionDirectory `
    -ReportPath $regressionReport `
    -SnnValidationAccuracyPercent $validationPercent `
    -SnnValidationCorrectSamples $validationCorrect `
    -SnnValidationTotalSamples $validationSamples
if ($LASTEXITCODE -ne 0) {
    throw "RTL regression failed; see $regressionReport"
}

Write-Host 'Producing final frozen-model evaluation with regression and adaptive-selection results'
& $pythonPath @pythonPrefix $modelEvaluator `
    --dataset (Join-Path $traceDirectory 'dataset.csv') `
    --output $evaluationReport `
    --regression-dir $regressionDirectory
if ($LASTEXITCODE -ne 0) {
    throw "Final predictor evaluation failed."
}

Write-Host "`nCOMPLETE EXPERIMENT PASSED"
Write-Host "Regression report: $regressionReport"
Write-Host "Machine-readable results: $evaluationReport"
Write-Host "Readable summary: $([System.IO.Path]::ChangeExtension($evaluationReport, '.md'))"
Write-Host "Validation gate source: $validationEvaluationReport"
Write-Host "Trace data, route decisions, and manifest: $traceDirectory"
