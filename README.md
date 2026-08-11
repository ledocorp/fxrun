# fxrun

**Task / command runner for [fx](https://github.com/ledocorp/fxlang) projects.**

fxrun reads a `Fxrun.toml` manifest, runs named recipes with dependencies, and can skip work when declared inputs are unchanged (content hash). Logic is implemented in **fx**; a thin C host owns argv and process spawn.

| | |
|--|--|
| **Requires** | [fx](https://github.com/ledocorp/fxlang) **0.9.6+** (Win + Linux x86_64), `gcc`, PowerShell 5.1+ on Windows |
| **License** | Apache-2.0 |
| **Org** | [LedoCorp](http://www.ledocorp.org) |

## Install (from source in this repo)

```powershell
# With fx 0.9.6+ on PATH and FX_STD_ROOT pointing at fx std/ (or vendor)
.\build.ps1          # emit-C binary → out/prog.exe
.\build-ir.ps1       # IR dual-path → out-ir/prog.exe (or prog_ir.exe)
Copy-Item out\prog.exe bin\fxrun.exe   # optional rename
```

Prebuilt `bin/fxrun.exe` (emit-C) and `bin/fxrun-ir.exe` (IR) ship in release archives when tagged.

## Quick start

```toml
# Fxrun.toml
[fxrun]
version = 1
default = "test"

[recipe.build]
doc = "Build the project"
cmds = ["fx build main.fx -o out --emit-c"]

[recipe.test]
doc = "Run tests after build"
depends = ["build"]
cmds = ["fx test . --backend both"]
```

```text
fxrun --list
fxrun test
fxrun --dry-run test
fxrun --force gen
```

Walk-up: if you run `fxrun` in a subdirectory, it finds the nearest parent `Fxrun.toml` / `fxrun.toml` and runs commands from that directory.

## CLI

| Invocation | Behavior |
|------------|----------|
| `fxrun` | Run `[fxrun].default`, or `--list` if unset |
| `fxrun --list` | Print recipes and docs |
| `fxrun <name>` | Resolve depends (fail-fast), then run |
| `fxrun --dry-run <name>` | Print plan; do not spawn |
| `fxrun --force <name>` | Bypass content-hash skip |

Exit codes: `0` ok · `2` unknown recipe / missing manifest · `4` dependency cycle · otherwise the failing command’s exit code.

## Manifest (v1)

- Recipe names: `[a-z][a-z0-9_]*`
- `depends`: other recipe names
- `cmds`: shell strings (`cmd.exe` / `sh -c`)
- Optional `inputs` + `outputs`: content-hash skip (stamp under `.fxrun/`)
- Restricted TOML subset (tables, strings, string arrays, ints) — see [docs/FXRUN.md](docs/FXRUN.md)

## Testing

```powershell
.\tests\smoke.ps1
```

Corpus runs on **both** emit-C and IR backends: list, default, depends order, dry-run, fail-fast, cycle, skip, force, walk-up, missing manifest.

## Non-goals (v1)

Parallel DAG · remote cache · Make/just syntax · replacing `fx build` · macOS prebuilt claim

## Docs

- [docs/FXRUN.md](docs/FXRUN.md) — design summary for users  
- [docs/releases/0.1.0.md](docs/releases/0.1.0.md) — release notes  
- Language package: [ledocorp/fxlang](https://github.com/ledocorp/fxlang)

## License

Copyright Shawn Londono · LedoCorp · Apache-2.0 — see [LICENSE](LICENSE).
