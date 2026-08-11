# Build fxrun (emit-C + thin C host). Run from tools/fxrun.
# Requires: release/debug `fx` on PATH or via FX_BIN; FX_STD_ROOT → repo std/.
param(
    [string]$FxBin = "",
    [string]$OutDir = "out"
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $here "..\..")).Path

if (-not $env:FX_STD_ROOT) {
    $env:FX_STD_ROOT = Join-Path $repo "std"
}

if (-not $FxBin) {
    $cand = @(
        (Join-Path $repo "fx-compiler\target-win\release\fx.exe"),
        (Join-Path $repo "fx-compiler\target\release\fx.exe"),
        (Join-Path $repo "fx-compiler\target\debug\fx.exe")
    )
    foreach ($c in $cand) {
        if (Test-Path $c) { $FxBin = $c; break }
    }
}
if (-not $FxBin -or -not (Test-Path $FxBin)) {
    throw "fx binary not found; pass -FxBin or build the foundry compiler"
}

New-Item -ItemType Directory -Force -Path (Join-Path $here $OutDir) | Out-Null
$cli = Join-Path $repo "host\cli"

# --host implies guest; --no-guest must come *after* --host so ambient std/io is allowed.
& $FxBin build (Join-Path $here "fxrun_lib.fx") `
    -o (Join-Path $here $OutDir) `
    --emit-c `
    --host (Join-Path $here "host\fxrun_host.c") `
    --no-guest `
    --link (Join-Path $here "host\fxrun_spawn.c") `
    --link-include (Join-Path $here "host") `
    --link-include $cli

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "ok: $(Join-Path $here $OutDir)\prog.exe" -ForegroundColor Green
Write-Host "try: .\out\prog.exe --list"
