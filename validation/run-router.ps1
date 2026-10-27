param(
    [switch]$DisableTfPcr
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputName = if ($DisableTfPcr) { 'router-disabled' } else { 'router-enabled' }
$runDirectory = Join-Path $PSScriptRoot ("run\standalone\{0}-{1}" -f $outputName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null

foreach ($tool in @('iverilog', 'vvp')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required simulator command '$tool' was not found. Install Icarus Verilog and add it to PATH."
    }
}

$sources = @(
    'rtl\common\noc_pkg.sv',
    'rtl\router\fifo.sv',
    'rtl\router\input_buffer.sv',
    'rtl\router\round_robin_arbiter.sv',
    'rtl\congestion\congestion_monitor.sv',
    'rtl\congestion\congestion_estimator.sv',
    'rtl\router\switch_allocator.sv',
    'rtl\router\crossbar.sv',
    'rtl\router\router_5port.sv',
    'sim\router\router_5port_tb.sv'
) | ForEach-Object { Join-Path $projectRoot $_ }
$outputFile = Join-Path $runDirectory 'router.vvp'
$compileArguments = @('-g2012', '-Wall', '-I', (Join-Path $projectRoot 'sim\router'), '-s', 'router_5port_tb', '-o', $outputFile)
if ($DisableTfPcr) {
    $compileArguments += @('-P', 'router_5port_tb.ENABLE_TF_PCR=0')
}
$compileArguments += $sources

Write-Host "Compiling five-port router (TF-PCR enabled: $(-not $DisableTfPcr))..."
Push-Location $projectRoot
try {
    & iverilog @compileArguments 2>&1 | Tee-Object -FilePath (Join-Path $runDirectory 'compile.log')
    if ($LASTEXITCODE -ne 0) {
        throw "Router compilation failed with exit code $LASTEXITCODE. See $runDirectory\compile.log"
    }
}
finally {
    Pop-Location
}

Write-Host 'Running router regression...'
Push-Location $runDirectory
try {
    & vvp '.\router.vvp' 2>&1 | Tee-Object -FilePath '.\router.log'
    if ($LASTEXITCODE -ne 0) {
        throw "Router simulation failed with exit code $LASTEXITCODE. See $runDirectory\router.log"
    }
}
finally {
    Pop-Location
}

$result = Join-Path $runDirectory 'router_5port_results.txt'
if (-not (Test-Path -LiteralPath $result) -or
    -not (Select-String -LiteralPath $result -Pattern 'ALL TESTS PASSED \(710 stage/transfer check points\)' -Quiet)) {
    throw "Router simulation did not produce the expected 710-check pass result. See $runDirectory"
}
Write-Host "`nROUTER TEST PASSED. Results: $result"
