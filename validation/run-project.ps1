param(
    [string]$OutputDirectory,
    [string]$ReportPath,
    [ValidateRange(0, 100)]
    [int]$SnnValidationAccuracyPercent = 97,
    [ValidateRange(0, 2147483647)]
    [int]$SnnValidationCorrectSamples = 0,
    [ValidateRange(0, 2147483647)]
    [int]$SnnValidationTotalSamples = 0
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runAll = Join-Path $PSScriptRoot 'run-all.ps1'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $runDirectory = Join-Path $PSScriptRoot "run\full-project-$timestamp"
}
elseif ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $runDirectory = $OutputDirectory
}
else {
    $runDirectory = Join-Path $projectRoot $OutputDirectory
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $reportPath = Join-Path $PSScriptRoot 'run\PROJECT-RESULTS.txt'
}
elseif ([System.IO.Path]::IsPathRooted($ReportPath)) {
    $reportPath = $ReportPath
}
else {
    $reportPath = Join-Path $projectRoot $ReportPath
}
$testNames = @(
    'tfpcr-monitor',
    'tf-feature-extractor',
    'adaptive-buffer-controller',
    'congestion-offload-controller',
    'snn-predictor',
    'adaptive-predictor-selector',
    'snn-model-parity',
    'distilled-predictor',
    'router-enabled',
    'router-disabled',
    'priority-arbiter',
    'mesh-routes',
    'snn-routing',
    'equation-routing',
    'mesh-xy',
    'mesh-west-first',
    'mesh-west-first-priority',
    'mesh-west-first-baseline',
    'mesh-west-first-snn',
    'mesh-west-first-equation',
    'mesh-west-first-adaptive'
)
$passPatterns = @{
    'tfpcr-monitor' = 'TF-PCR MONITOR TESTS PASSED'
    'tf-feature-extractor' = 'TF FEATURE EXTRACTOR TESTS PASSED'
    'adaptive-buffer-controller' = 'ADAPTIVE BUFFER CONTROLLER TESTS PASSED'
    'congestion-offload-controller' = 'CONGESTION OFFLOAD CONTROLLER TESTS PASSED'
    'snn-predictor' = 'SNN PREDICTOR TESTS PASSED'
    'adaptive-predictor-selector' = 'ADAPTIVE PREDICTOR SELECTOR TESTS PASSED'
    'snn-model-parity' = 'TRAINED INTEGER SNN REFERENCE PARITY PASSED'
    'distilled-predictor' = 'DISTILLED EQUATION RANDOMIZED TEST PASSED'
    'router-enabled' = 'ALL TESTS PASSED \(710 stage/transfer check points\)'
    'router-disabled' = 'ALL TESTS PASSED \(710 stage/transfer check points\)'
    'priority-arbiter' = 'PRIORITY ARBITER TESTS PASSED'
    'mesh-routes' = 'ROUTE TESTS PASSED'
    'snn-routing' = 'SNN ROUTING INTEGRATION TESTS PASSED'
    'equation-routing' = 'EQUATION PREDICTIVE ROUTING TEST PASSED'
    'mesh-xy' = 'ALL MESH TESTS PASSED:.*no drops/duplicates/corruption'
    'mesh-west-first' = 'ALL MESH TESTS PASSED:.*no drops/duplicates/corruption'
    'mesh-west-first-priority' = 'ALL MESH TESTS PASSED:.*no drops/duplicates/corruption'
    'mesh-west-first-baseline' = 'ALL MESH TESTS PASSED:.*no drops/duplicates/corruption'
    'mesh-west-first-snn' = 'ALL MESH TESTS PASSED:.*no drops/duplicates/corruption'
    'mesh-west-first-equation' = 'ALL MESH TESTS PASSED:.*no drops/duplicates/corruption'
    'mesh-west-first-adaptive' = 'ALL MESH TESTS PASSED:.*no drops/duplicates/corruption'
}
$report = [System.Collections.Generic.List[string]]::new()
$report.Add('TF-PCR 4x4 NoC - full project validation')
$report.Add("Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
$report.Add("Project: $projectRoot")
$report.Add("Icarus run output: $runDirectory")
$report.Add('')

$runnerOutput = @()
$runnerExitCode = 1
try {
    $powershell = (Get-Process -Id $PID).Path
    $runnerOutput = & $powershell -NoProfile -ExecutionPolicy Bypass -File $runAll `
        -OutputDirectory $runDirectory `
        -SnnValidationAccuracyPercent $SnnValidationAccuracyPercent `
        -SnnValidationCorrectSamples $SnnValidationCorrectSamples `
        -SnnValidationTotalSamples $SnnValidationTotalSamples *>&1
    $runnerExitCode = $LASTEXITCODE
}
catch {
    $runnerOutput += $_
}

$report.Add('=== RUN SUMMARY ===')
foreach ($name in $testNames) {
    $logPath = Join-Path (Join-Path $runDirectory $name) "$name.log"
    $passed = (Test-Path -LiteralPath $logPath) -and
        (Select-String -LiteralPath $logPath -Pattern $passPatterns[$name] -Quiet)
    $state = if ($passed) { 'PASS' } else { 'FAIL or NOT RUN' }
    $report.Add(('{0,-29} {1}' -f $name, $state))
}
$report.Add("Runner exit code: $runnerExitCode")
$report.Add('')
$report.Add('=== BUILD OUTPUT ===')
foreach ($line in $runnerOutput) {
    $report.Add([string]$line)
}

foreach ($name in $testNames) {
    $testDirectory = Join-Path $runDirectory $name
    $report.Add('')
    $report.Add("=== $name ===")
    foreach ($fileName in @('compile.log', "$name.log")) {
        $filePath = Join-Path $testDirectory $fileName
        if (Test-Path -LiteralPath $filePath) {
            $report.Add("--- $fileName ---")
            foreach ($line in Get-Content -LiteralPath $filePath) {
                $report.Add([string]$line)
            }
        }
        else {
            $report.Add("--- $fileName not created ---")
        }
    }
}

$allPassed = $runnerExitCode -eq 0
foreach ($name in $testNames) {
    $logPath = Join-Path (Join-Path $runDirectory $name) "$name.log"
    if (-not (Test-Path -LiteralPath $logPath) -or
        -not (Select-String -LiteralPath $logPath -Pattern $passPatterns[$name] -Quiet)) {
        $allPassed = $false
    }
}
$report.Add('')
$report.Add("FINAL RESULT: $(if ($allPassed) { 'ALL TESTS PASSED' } else { 'VALIDATION FAILED - inspect failed test/log above' })")
$report.Add("Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
[System.IO.File]::WriteAllLines($reportPath, $report, [System.Text.UTF8Encoding]::new($false))

Write-Host "`n$($report[$report.Count - 2])"
Write-Host "Single-file report: $reportPath"
Write-Host "Individual run files: $runDirectory"
if (-not $allPassed) {
    throw "Full project validation failed. Review $reportPath"
}
