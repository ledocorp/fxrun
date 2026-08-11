# Pin presence check for fxrun (called from Fxrun.toml recipe verify).
$ErrorActionPreference = 'Stop'
if (-not (Test-Path (Join-Path $PSScriptRoot 'fx.mod'))) { throw 'missing fx.mod' }
if (-not (Test-Path (Join-Path $PSScriptRoot 'fx.sum'))) { throw 'missing fx.sum' }
Write-Host 'fxrun: pin files present'
exit 0
