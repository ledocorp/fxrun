#Requires -Version 5.1
<#
.SYNOPSIS
  Local pack of tools/fxrun into dist/ (NO GitHub publish).

.PARAMETER SkipBuild
  Stage existing out/ binaries without rebuilding.
#>
param(
    [switch]$SkipBuild
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Here = $PSScriptRoot
if (Test-Path (Join-Path $Here 'fxrun_lib.fx')) {
    $Tool = $Here
    $Root = (Resolve-Path (Join-Path $Here '..\..')).Path
} else {
    $Root = Split-Path -Parent $Here
    $Tool = Join-Path $Root 'tools\fxrun'
}

$env:FX_STD_ROOT = Join-Path $Root 'std'
if (-not $env:CARGO_TARGET_DIR) {
    $env:CARGO_TARGET_DIR = Join-Path $Root 'fx-compiler\target-win'
}

Write-Host 'pack-fxrun: local stage only (will not publish)' -ForegroundColor Cyan

Push-Location $Tool
try {
    if (-not $SkipBuild) {
        & (Join-Path $Tool 'build.ps1')
        if ($LASTEXITCODE -ne 0) { throw "build failed: $LASTEXITCODE" }
        & (Join-Path $Tool 'build-ir.ps1')
        if ($LASTEXITCODE -ne 0) { throw "build-ir failed: $LASTEXITCODE" }
    }

    $exe = Join-Path $Tool 'out\prog.exe'
    $ir = Join-Path $Tool 'out-ir\prog_ir.exe'
    if (-not (Test-Path $ir)) { $ir = Join-Path $Tool 'out-ir\prog.exe' }
    if (-not (Test-Path $exe)) { throw "missing $exe - build first" }
    if (-not (Test-Path $ir)) { throw "missing IR binary - build-ir first" }

    $stage = Join-Path $Tool 'dist\fxrun-local'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'bin') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'host') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'tests') | Out-Null

    Copy-Item (Join-Path $Tool 'README.md') $stage
    Copy-Item (Join-Path $Tool 'Fxrun.toml') $stage
    Copy-Item (Join-Path $Tool 'fxrun_lib.fx') $stage
    Copy-Item (Join-Path $Tool 'fx.mod') $stage
    Copy-Item (Join-Path $Tool 'fx.sum') $stage
    Copy-Item (Join-Path $Tool 'FOUNDRY_ISSUES.md') $stage
    Copy-Item (Join-Path $Tool 'build.ps1') $stage
    Copy-Item (Join-Path $Tool 'build-ir.ps1') $stage
    Copy-Item (Join-Path $Tool 'pack-local.ps1') $stage
    Copy-Item (Join-Path $Tool 'host\*') (Join-Path $stage 'host')
    Copy-Item (Join-Path $Tool 'tests\smoke.ps1') (Join-Path $stage 'tests')
    Copy-Item $exe (Join-Path $stage 'bin\fxrun.exe')
    Copy-Item $ir (Join-Path $stage 'bin\fxrun-ir.exe')

    @"
# fxrun local pack

Staged: $(Get-Date -Format o)
This tree is for local install / review only.
Do **not** treat as a GitHub release — publish only when steward asks.
"@ | Set-Content (Join-Path $stage 'PACK_NOTES.md') -Encoding utf8

    Write-Host "ok: staged $stage" -ForegroundColor Green
    Write-Host 'binaries: bin/fxrun.exe (emit-C) · bin/fxrun-ir.exe (IR)'
} finally {
    Pop-Location
}
exit 0
