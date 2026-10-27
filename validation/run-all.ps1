param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'run\reorganized'),
    [ValidateRange(0, 100)]
    [int]$SnnValidationAccuracyPercent = 97,
    [ValidateRange(0, 2147483647)]
    [int]$SnnValidationCorrectSamples = 0,
    [ValidateRange(0, 2147483647)]
    [int]$SnnValidationTotalSamples = 0
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$runRoot = $OutputDirectory
if (-not [System.IO.Path]::IsPathRooted($runRoot)) {
    $runRoot = Join-Path $projectRoot $runRoot
}
$routerRtl = @(
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
    'rtl\router\router_5port.sv'
)
$meshRtl = $routerRtl + @(
    'rtl\mesh\mesh_route_compute.sv',
    'rtl\mesh\mesh_link_fifo.sv',
    'rtl\mesh\noc_router_wrapper.sv',
    'rtl\mesh\noc_mesh_4x4.sv'
)

function Invoke-Test {
    param(
        [string]$Name,
        [string]$Top,
        [string[]]$Sources,
        [string[]]$Parameters = @(),
        [string[]]$IncludeDirectories = @()
    )

    $outputDirectory = Join-Path $runRoot $Name
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    $outputFile = Join-Path $outputDirectory "$Name.vvp"
    $compileArguments = @('-g2012', '-Wall')
    foreach ($directory in $IncludeDirectories) {
        $compileArguments += @('-I', $directory)
    }
    $compileArguments += @('-s', $Top, '-o', $outputFile)
    $compileArguments += $Parameters
    $compileArguments += $Sources

    Write-Host "`n=== Compile: $Name ==="
    New-Item -ItemType File -Force -Path (Join-Path $outputDirectory 'compile.log') | Out-Null
    Push-Location $projectRoot
    try {
        & iverilog @compileArguments 2>&1 |
            Tee-Object -FilePath (Join-Path $outputDirectory 'compile.log')
        if ($LASTEXITCODE -ne 0) {
            throw "Icarus compilation failed for $Name (exit $LASTEXITCODE)."
        }
    }
    finally {
        Pop-Location
    }

    Write-Host "=== Simulate: $Name ==="
    Push-Location $outputDirectory
    try {
        & vvp ".\$Name.vvp" | Tee-Object -FilePath "$Name.log"
        if ($LASTEXITCODE -ne 0) {
            throw "Simulation failed for $Name (exit $LASTEXITCODE)."
        }
    }
    finally {
        Pop-Location
    }
}

Invoke-Test -Name 'tfpcr-monitor' -Top 'tfpcr_monitor_tb' `
    -Sources @(
        'rtl\common\noc_pkg.sv',
        'rtl\congestion\congestion_monitor.sv',
        'rtl\congestion\congestion_estimator.sv',
        'sim\congestion\tfpcr_monitor_tb.sv'
    )

Invoke-Test -Name 'tf-feature-extractor' -Top 'tf_feature_extractor_tb' `
    -Sources @(
        'rtl\common\noc_pkg.sv',
        'rtl\congestion\tf_feature_extractor.sv',
        'sim\congestion\tf_feature_extractor_tb.sv'
    )

Invoke-Test -Name 'adaptive-buffer-controller' -Top 'adaptive_buffer_controller_tb' `
    -Sources @(
        'rtl\common\noc_pkg.sv',
        'rtl\congestion\adaptive_buffer_controller.sv',
        'sim\congestion\adaptive_buffer_controller_tb.sv'
    )

Invoke-Test -Name 'congestion-offload-controller' -Top 'congestion_offload_controller_tb' `
    -Sources @(
        'rtl\common\noc_pkg.sv',
        'rtl\congestion\congestion_offload_controller.sv',
        'sim\congestion\congestion_offload_controller_tb.sv'
    )

Invoke-Test -Name 'snn-predictor' -Top 'snn_predictor_tb' `
    -Sources @(
        'rtl\common\noc_pkg.sv',
        'rtl\congestion\snn_model_parameters_pkg.sv',
        'rtl\congestion\snn_predictor.sv',
        'sim\congestion\snn_predictor_tb.sv'
    )

Invoke-Test -Name 'adaptive-predictor-selector' -Top 'adaptive_predictor_selector_tb' `
    -Sources @(
        'rtl\common\noc_pkg.sv',
        'rtl\congestion\adaptive_predictor_selector.sv',
        'sim\congestion\adaptive_predictor_selector_tb.sv'
    )

Invoke-Test -Name 'snn-model-parity' -Top 'snn_model_parity_tb' `
    -Sources @(
        'rtl\common\noc_pkg.sv',
        'rtl\congestion\snn_model_parameters_pkg.sv',
        'rtl\congestion\snn_predictor.sv',
        'sim\congestion\snn_model_parity_tb.sv'
    )

Invoke-Test -Name 'distilled-predictor' -Top 'distilled_predictor_tb' `
    -Sources @(
        'rtl\common\noc_pkg.sv',
        'rtl\congestion\distilled_congestion_model_pkg.sv',
        'rtl\congestion\distilled_congestion_predictor.sv',
        'sim\congestion\distilled_predictor_tb.sv'
    )

Invoke-Test -Name 'router-enabled' -Top 'router_5port_tb' `
    -Sources ($routerRtl + 'sim\router\router_5port_tb.sv') `
    -IncludeDirectories @('sim\router')

Invoke-Test -Name 'router-disabled' -Top 'router_5port_tb' `
    -Parameters @('-P', 'router_5port_tb.ENABLE_TF_PCR=0') `
    -Sources ($routerRtl + 'sim\router\router_5port_tb.sv') `
    -IncludeDirectories @('sim\router')

Invoke-Test -Name 'priority-arbiter' -Top 'priority_arbiter_tb' `
    -Sources @(
        'rtl\router\round_robin_arbiter.sv',
        'sim\router\priority_arbiter_tb.sv'
    )

Invoke-Test -Name 'mesh-routes' -Top 'mesh_route_compute_tb' `
    -Sources @(
        'rtl\common\noc_pkg.sv',
        'rtl\mesh\mesh_route_compute.sv',
        'sim\mesh\mesh_route_compute_tb.sv'
    )

Invoke-Test -Name 'snn-routing' -Top 'snn_routing_tb' `
    -Sources ($meshRtl + 'sim\mesh\snn_routing_tb.sv')

Invoke-Test -Name 'equation-routing' -Top 'equation_routing_tb' `
    -Sources ($meshRtl + 'sim\mesh\equation_routing_tb.sv')

$meshSources = $meshRtl + 'sim\mesh\mesh_noc_tb.sv'
Invoke-Test -Name 'mesh-xy' -Top 'mesh_noc_tb' `
    -Sources $meshSources -IncludeDirectories @('sim\mesh')

Invoke-Test -Name 'mesh-west-first' -Top 'mesh_noc_tb' `
    -Parameters @('-P', 'mesh_noc_tb.ROUTING_MODE=1') `
    -Sources $meshSources -IncludeDirectories @('sim\mesh')

Invoke-Test -Name 'mesh-west-first-priority' -Top 'mesh_noc_tb' `
    -Parameters @(
        '-P', 'mesh_noc_tb.ROUTING_MODE=1',
        '-P', 'mesh_noc_tb.ENABLE_PRIORITY=1'
    ) `
    -Sources $meshSources -IncludeDirectories @('sim\mesh')

Invoke-Test -Name 'mesh-west-first-baseline' -Top 'mesh_noc_tb' `
    -Parameters @(
        '-P', 'mesh_noc_tb.ROUTING_MODE=1',
        '-P', 'mesh_noc_tb.ENABLE_TF_PCR=0'
    ) `
    -Sources $meshSources -IncludeDirectories @('sim\mesh')

Invoke-Test -Name 'mesh-west-first-snn' -Top 'mesh_noc_tb' `
    -Parameters @(
        '-P', 'mesh_noc_tb.ROUTING_MODE=1',
        '-P', 'mesh_noc_tb.ENABLE_PRIORITY=1',
        '-P', 'mesh_noc_tb.ENABLE_SNN=1',
        '-P', 'mesh_noc_tb.ENABLE_ADAPTIVE_BUFFER=1',
        '-P', 'mesh_noc_tb.ENABLE_OFFLOAD=1'
    ) `
    -Sources $meshSources -IncludeDirectories @('sim\mesh')

Invoke-Test -Name 'mesh-west-first-equation' -Top 'mesh_noc_tb' `
    -Parameters @(
        '-P', 'mesh_noc_tb.ROUTING_MODE=1',
        '-P', 'mesh_noc_tb.ENABLE_PRIORITY=1',
        '-P', 'mesh_noc_tb.ENABLE_EQUATION_ROUTING=1',
        '-P', 'mesh_noc_tb.ENABLE_ADAPTIVE_BUFFER=1'
    ) `
    -Sources $meshSources -IncludeDirectories @('sim\mesh')

Invoke-Test -Name 'mesh-west-first-adaptive' -Top 'mesh_noc_tb' `
    -Parameters @(
        '-P', 'mesh_noc_tb.ROUTING_MODE=1',
        '-P', 'mesh_noc_tb.ENABLE_ADAPTIVE_PREDICTOR=1',
        '-P', 'mesh_noc_tb.ENABLE_SNN=1',
        '-P', "mesh_noc_tb.SNN_VALIDATION_ACCURACY_PERCENT=$SnnValidationAccuracyPercent",
        '-P', "mesh_noc_tb.SNN_VALIDATION_CORRECT_SAMPLES=$SnnValidationCorrectSamples",
        '-P', "mesh_noc_tb.SNN_VALIDATION_TOTAL_SAMPLES=$SnnValidationTotalSamples",
        '-P', 'mesh_noc_tb.ENABLE_ADAPTIVE_BUFFER=1'
    ) `
    -Sources $meshSources -IncludeDirectories @('sim\mesh')

Write-Host "`nAll twenty-one validation runs completed successfully. Logs and waveforms are under $runRoot."
