# Corpus checks for fxrun — mandatory emit-C + IR (excellence bar).
# Uses an isolated workdir so the product Fxrun.toml is never mutated.
param(
    [switch]$Rebuild
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root "out\prog.exe"
$irCandidates = @(
    (Join-Path $root "out-ir\prog_ir.exe"),
    (Join-Path $root "out-ir\prog.exe")
)

function Resolve-Ir {
    foreach ($c in $irCandidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

if ($Rebuild -or -not (Test-Path $exe) -or -not (Resolve-Ir)) {
    Push-Location $root
    try {
        & (Join-Path $root "build.ps1")
        if ($LASTEXITCODE -ne 0) { throw "build.ps1 failed: $LASTEXITCODE" }
        & (Join-Path $root "build-ir.ps1")
        if ($LASTEXITCODE -ne 0) { throw "build-ir.ps1 failed: $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

$exe = Join-Path $root "out\prog.exe"
$ir = Resolve-Ir
if (-not (Test-Path $exe)) { throw "missing emit-C binary: $exe" }
if (-not $ir) { throw "missing IR binary under out-ir/ (IR is mandatory for excellence)" }

$outFile = Join-Path $env:TEMP "fxrun-out.txt"
$errFile = Join-Path $env:TEMP "fxrun-err.txt"
$work = Join-Path $root "tests\corpus_work"

function Reset-Work {
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
}
function Set-WorkToml([string]$Body) {
    Set-Content -Path (Join-Path $work "Fxrun.toml") -Value $Body -Encoding ascii
}

function Assert-Exit([string]$Label, [string[]]$ArgList, [int]$Want, [string]$Bin) {
    Push-Location $work
    try {
        if ($null -eq $ArgList -or $ArgList.Count -eq 0) {
            $p = Start-Process -FilePath $Bin -Wait -PassThru -NoNewWindow `
                -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        } else {
            $p = Start-Process -FilePath $Bin -ArgumentList $ArgList -Wait -PassThru -NoNewWindow `
                -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        }
        $code = $p.ExitCode
    } finally {
        Pop-Location
    }
    if ($code -ne $Want) {
        $err = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
        $shown = if ($ArgList -and $ArgList.Count -gt 0) { $ArgList -join ' ' } else { '(default)' }
        throw "$Label ($shown) on $(Split-Path $Bin -Leaf): want exit $Want got $code; stderr=$err"
    }
}

function Assert-OutContains([string]$Bin, [string[]]$ArgList, [string]$Needle) {
    Assert-Exit "out:$Needle" $ArgList 0 $Bin
    $txt = Get-Content $outFile -Raw
    if ($txt -notmatch [regex]::Escape($Needle)) {
        throw "expected output to contain '$Needle', got: $txt"
    }
}

function Invoke-Corpus([string]$Bin, [string]$Tag) {
    Write-Host "== corpus $Tag ==" -ForegroundColor Cyan
    Reset-Work

    # Product Fxrun.toml list (cwd = tool root)
    Push-Location $root
    try {
        $p = Start-Process -FilePath $Bin -ArgumentList @("--list") -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        if ($p.ExitCode -ne 0) {
            throw "$Tag product-list: want 0 got $($p.ExitCode)"
        }
        $txt = Get-Content $outFile -Raw
        if ($txt -notmatch "test -") { throw "$Tag product-list missing test recipe" }
    } finally {
        Pop-Location
    }

    Set-WorkToml @"
[fxrun]
version = 1
default = "hello"
[recipe.hello]
doc = "default target"
cmds = ["echo fxrun-hello-ok"]
"@
    Assert-Exit "$Tag default" @() 0 $Bin
    Assert-OutContains $Bin @() "fxrun-hello-ok"

    Set-WorkToml @"
[fxrun]
version = 1
[recipe.leaf]
doc = "leaf"
depends = ["root"]
cmds = ["echo LEAF"]
[recipe.root]
doc = "root"
cmds = ["echo ROOT"]
"@
    Assert-Exit "$Tag depends" @("leaf") 0 $Bin
    $depOut = Get-Content $outFile -Raw
    $iRoot = $depOut.IndexOf("ROOT")
    $iLeaf = $depOut.IndexOf("LEAF")
    if ($iRoot -lt 0 -or $iLeaf -lt 0 -or $iRoot -gt $iLeaf) {
        throw "$Tag depends: expected ROOT before LEAF, got: $depOut"
    }

    $dryMarker = Join-Path $work "dry_marker.txt"
    Remove-Item $dryMarker -Force -ErrorAction SilentlyContinue
    Set-WorkToml @"
[fxrun]
version = 1
[recipe.dry]
doc = "must not write on dry-run"
cmds = ["cmd /c echo dry-wrote> dry_marker.txt"]
"@
    Assert-Exit "$Tag dry-run" @("--dry-run", "dry") 0 $Bin
    if (Test-Path $dryMarker) { throw "$Tag dry-run created side-effect file" }
    Assert-OutContains $Bin @("--dry-run", "dry") "dry_marker"

    Set-WorkToml @"
[fxrun]
version = 1
[recipe.fail]
doc = "fail then never"
cmds = ["exit 7", "echo SHOULD_NOT_RUN"]
"@
    Assert-Exit "$Tag fail-fast" @("fail") 7 $Bin
    $fout = Get-Content $outFile -Raw -ErrorAction SilentlyContinue
    if ($fout -match "SHOULD_NOT_RUN") { throw "$Tag fail-fast ran second cmd" }

    Set-WorkToml @"
[fxrun]
version = 1
[recipe.a]
depends = ["b"]
cmds = ["echo a"]
[recipe.b]
depends = ["a"]
cmds = ["echo b"]
"@
    Assert-Exit "$Tag cycle" @("a") 4 $Bin

    Set-WorkToml @"
[fxrun]
version = 1
[recipe.only]
cmds = ["echo only"]
"@
    Assert-Exit "$Tag unknown" @("nosuch") 2 $Bin

    $skipDir = Join-Path $work "skip_fixture"
    New-Item -ItemType Directory -Force -Path $skipDir | Out-Null
    Set-Content -Path (Join-Path $skipDir "in.txt") -Value "v1" -Encoding ascii
    Remove-Item (Join-Path $skipDir "out.txt") -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $work ".fxrun") -Recurse -Force -ErrorAction SilentlyContinue
    Set-WorkToml @"
[fxrun]
version = 1
[recipe.gen]
doc = "hash skip"
inputs = ["skip_fixture/in.txt"]
outputs = ["skip_fixture/out.txt"]
cmds = ["cmd /c copy /Y skip_fixture\in.txt skip_fixture\out.txt"]
"@
    Assert-Exit "$Tag skip-first" @("gen") 0 $Bin
    Assert-OutContains $Bin @("gen") "fxrun: skip"
    Set-Content -Path (Join-Path $skipDir "in.txt") -Value "v2" -Encoding ascii
    Assert-Exit "$Tag skip-dirty" @("gen") 0 $Bin
    $dirty = Get-Content $outFile -Raw
    if ($dirty -match "fxrun: skip") { throw "$Tag expected re-run after input change" }
    Assert-Exit "$Tag force" @("--force", "gen") 0 $Bin

    # walk-up
    $walkRoot = Join-Path $work "walk_fixture"
    $walkNested = Join-Path $walkRoot "nested"
    New-Item -ItemType Directory -Force -Path $walkNested | Out-Null
    Set-Content -Path (Join-Path $walkRoot "Fxrun.toml") -Value @"
[fxrun]
version = 1
[recipe.ping]
doc = "walk-up proof"
cmds = ["cmd /c echo WALK_OK> nested\walk_out.txt"]
"@ -Encoding ascii
    Remove-Item (Join-Path $walkNested "walk_out.txt") -Force -ErrorAction SilentlyContinue
    # Remove work Fxrun.toml so walk-up from nested does not stop at $work
    Remove-Item (Join-Path $work "Fxrun.toml") -Force -ErrorAction SilentlyContinue
    try {
        Push-Location $walkNested
        $p = Start-Process -FilePath $Bin -ArgumentList @("ping") -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        if ($p.ExitCode -ne 0) {
            throw "$Tag walk-up: want exit 0 got $($p.ExitCode)"
        }
    } finally {
        Pop-Location
    }
    if (-not (Test-Path (Join-Path $walkNested "walk_out.txt"))) {
        throw "$Tag walk-up: expected nested/walk_out.txt"
    }

    # missing manifest — outside any Fxrun.toml ancestor
    $tmp = Join-Path $env:LOCALAPPDATA ("fxrun-miss-" + [guid]::NewGuid().ToString("n"))
    [void][System.IO.Directory]::CreateDirectory($tmp)
    try {
        Push-Location -LiteralPath $tmp
        $p = Start-Process -FilePath $Bin -ArgumentList @("--list") -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        if ($p.ExitCode -ne 2) {
            throw "$Tag missing-manifest: want exit 2 got $($p.ExitCode)"
        }
    } finally {
        Pop-Location
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "ok: fxrun $Tag corpus" -ForegroundColor Green
}

try {
    Invoke-Corpus $exe "emit-C"
    Invoke-Corpus $ir "IR"
    Write-Host "ok: fxrun excellence corpus (emit-C + IR)" -ForegroundColor Green
} finally {
    if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}
