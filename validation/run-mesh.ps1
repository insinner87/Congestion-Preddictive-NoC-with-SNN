param(
    [ValidateSet('XY', 'WestFirst')]
    [string]$Routing = 'WestFirst',
    [int]$Seed = 1327219415,
    [switch]$DisableTfPcr,
    [switch]$EnablePriority,
    [switch]$EnableSnnRouting,
    [switch]$EnableEquationRouting,
    [switch]$EnableAdaptivePredictor,
    [ValidateRange(0, 100)]
    [int]$SnnValidationAccuracyPercent = 97,
    [ValidateRange(0, 2147483647)]
    [int]$SnnValidationCorrectSamples = 0,
    [ValidateRange(0, 2147483647)]
    [int]$SnnValidationTotalSamples = 0
)

$ErrorActionPreference = 'Stop'
if (($EnableSnnRouting -and $EnableEquationRouting) -or
    ($EnableAdaptivePredictor -and ($EnableSnnRouting -or $EnableEquationRouting))) {
    throw 'SNN, equation, and adaptive predictor route modes are mutually exclusive.'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$mode = if ($Routing -eq 'WestFirst') { 1 } else { 0 }
$variant = if ($DisableTfPcr) { 'baseline' } else { 'tfpcr' }
if ($EnablePriority) { $variant += '-priority' }
if ($EnableSnnRouting) { $variant += '-snn' }
if ($EnableEquationRouting) { $variant += '-equation' }
if ($EnableAdaptivePredictor) { $variant += '-adaptive' }
$name = "mesh-$Routing-$variant-seed-$Seed"
$runDirectory = Join-Path $PSScriptRoot ("run\standalone\{0}-{1}" -f $name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

foreach ($tool in @('iverilog', 'vvp')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required simulator command '$tool' was not found. Install Icarus Verilog and add it to PATH."
    }
}

$relativeSources = @(
    'rtl\common\noc_pkg.sv',
    'rtl\congestion\snn_model_parameters_pkg.sv',
    'rtl\congestion\distilled_congestion_model_pkg.sv',
    'rtl\congestion\distilled_congestion_predictor.sv',
    'rtl\router\fifo.sv',
    'rtl\router\input_buffer.sv',
    'rtl\router\round_robin_arbiter.sv',
    'rtl\congestion\congestion_monitor.sv',
    'rtl\congestion\congestion_estimator.sv',
    'rtl\congestion\tf_feature_extractor.sv',
    'rtl\congestion\snn_predictor.sv',
    'rtl\congestion\adaptive_predictor_selector.sv',
    'rtl\congestion\adaptive_buffer_controller.sv',
    'rtl\congestion\congestion_offload_controller.sv',
    'rtl\router\switch_allocator.sv',
    'rtl\router\crossbar.sv',
    'rtl\router\router_5port.sv',
    'rtl\mesh\mesh_route_compute.sv',
    'rtl\mesh\mesh_link_fifo.sv',
    'rtl\mesh\noc_router_wrapper.sv',
    'rtl\mesh\noc_mesh_4x4.sv',
    'sim\mesh\mesh_noc_tb.sv'
)
$sources = $relativeSources | ForEach-Object { Join-Path $projectRoot $_ }
$outputFile = Join-Path $runDirectory 'mesh.vvp'
$compileArguments = @(
    '-g2012', '-Wall',
    '-I', (Join-Path $projectRoot 'sim\mesh'),
    '-s', 'mesh_noc_tb',
    '-P', "mesh_noc_tb.ROUTING_MODE=$mode",
    '-o', $outputFile
)
if ($DisableTfPcr) {
    $compileArguments += @('-P', 'mesh_noc_tb.ENABLE_TF_PCR=0')
}
if ($EnablePriority) {
    $compileArguments += @('-P', 'mesh_noc_tb.ENABLE_PRIORITY=1')
}
if ($EnableSnnRouting) {
    $compileArguments += @(
        '-P', 'mesh_noc_tb.ENABLE_SNN=1',
        '-P', 'mesh_noc_tb.ENABLE_SNN_ROUTING=1'
    )
}
if ($EnableEquationRouting) {
    $compileArguments += @('-P', 'mesh_noc_tb.ENABLE_EQUATION_ROUTING=1')
}
if ($EnableAdaptivePredictor) {
    $compileArguments += @(
        '-P', 'mesh_noc_tb.ENABLE_ADAPTIVE_PREDICTOR=1',
        '-P', 'mesh_noc_tb.ENABLE_SNN=1',
        '-P', "mesh_noc_tb.SNN_VALIDATION_ACCURACY_PERCENT=$SnnValidationAccuracyPercent",
        '-P', "mesh_noc_tb.SNN_VALIDATION_CORRECT_SAMPLES=$SnnValidationCorrectSamples",
        '-P', "mesh_noc_tb.SNN_VALIDATION_TOTAL_SAMPLES=$SnnValidationTotalSamples"
    )
}
$compileArguments += $sources

Write-Host "Compiling 4x4 mesh ($Routing routing; TF-PCR enabled: $(-not $DisableTfPcr); priority enabled: $EnablePriority; SNN routing enabled: $EnableSnnRouting; equation routing enabled: $EnableEquationRouting; adaptive predictor enabled: $EnableAdaptivePredictor)..."
Push-Location $projectRoot
try {
    & iverilog @compileArguments 2>&1 | Tee-Object -FilePath (Join-Path $runDirectory 'compile.log')
    if ($LASTEXITCODE -ne 0) {
        throw "Mesh compilation failed with exit code $LASTEXITCODE. See $runDirectory\compile.log"
    }
}
finally {
    Pop-Location
}

Write-Host 'Running mesh regression...'
Push-Location $runDirectory
try {
    & vvp '.\mesh.vvp' "+SEED=$Seed" 2>&1 | Tee-Object -FilePath '.\mesh.log'
    if ($LASTEXITCODE -ne 0) {
        throw "Mesh simulation failed with exit code $LASTEXITCODE. See $runDirectory\mesh.log"
    }
}
finally {
    Pop-Location
}

if (-not (Select-String -LiteralPath (Join-Path $runDirectory 'mesh.log') `
        -Pattern 'ALL MESH TESTS PASSED:.*no drops/duplicates/corruption' -Quiet)) {
    throw "Mesh simulation did not produce the expected packet-integrity pass result. See $runDirectory"
}
Write-Host "`n4x4 MESH TEST PASSED. Results: $(Join-Path $runDirectory 'mesh.log')"
