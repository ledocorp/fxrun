# Build IR binary if possible (best-effort). Emit-C remains the ship path until FX-IR-HOST-RESULT-1.
param([string]$FxBin = "")
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $here "..\..")).Path
if (-not $env:FX_STD_ROOT) { $env:FX_STD_ROOT = Join-Path $repo "std" }
if (-not $FxBin) {
    $cand = @(
        (Join-Path $repo "fx-compiler\target-win\release\fx.exe"),
        (Join-Path $repo "fx-compiler\target\release\fx.exe")
    )
    foreach ($c in $cand) { if (Test-Path $c) { $FxBin = $c; break } }
}
$cli = Join-Path $repo "host\cli"
& $FxBin build (Join-Path $here "fxrun_lib.fx") `
    -o (Join-Path $here "out-ir") `
    --backend ir `
    --host (Join-Path $here "host\fxrun_host.c") `
    --no-guest `
    --link (Join-Path $here "host\fxrun_spawn.c") `
    --link-include (Join-Path $here "host") `
    --link-include $cli
if ($LASTEXITCODE -ne 0) {
    Write-Host "IR build failed (see FOUNDRY_ISSUES.md FX-IR-HOST-RESULT-1). Emit-C remains ship path." -ForegroundColor Yellow
    exit $LASTEXITCODE
}
Write-Host "ok: out-ir/prog.exe"
