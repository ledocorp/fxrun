# fxrun

**Task / command runner for [fx](https://github.com/ledocorp/fxlang) projects.**

fxrun reads a `Fxrun.toml` manifest, runs named recipes with dependencies, and can skip work when declared inputs are unchanged (content hash). Product logic is **fx**; rebuild with `fx build … --cli` (shared argv/process spine — no author-written host.c).

| | |
|--|--|
| **Requires** | [fx](https://github.com/ledocorp/fxlang) **0.9.6+** |
| **Platforms** | Windows + Linux **x86_64** |
| **License** | Apache-2.0 |
| **Org** | [LedoCorp](http://www.ledocorp.org) |

## Install (release binaries)

1. Install [fx 0.9.6+](https://github.com/ledocorp/fxlang/releases/tag/v0.9.6).  
2. Download the asset for your OS from [Releases](https://github.com/ledocorp/fxrun/releases).  
3. Put `bin/windows/fxrun.exe` or `bin/linux/fxrun` on your `PATH`.

```text
# Windows (PowerShell)
Invoke-WebRequest -Uri https://github.com/ledocorp/fxrun/releases/download/v0.1.2/fxrun-0.1.2-windows-x86_64.zip -OutFile fxrun.zip
Expand-Archive fxrun.zip -DestinationPath .
.\bin\windows\fxrun.exe --list

# Linux
curl -LO https://github.com/ledocorp/fxrun/releases/download/v0.1.2/fxrun-0.1.2-linux-x86_64.tar.gz
tar xzf fxrun-0.1.2-linux-x86_64.tar.gz
./bin/linux/fxrun --list
```

Optional: `fxrun-ir` is the IR dual-path binary (same CLI).

## Quick start

```toml
# Fxrun.toml (see examples/Fxrun.toml)
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

Walk-up: running in a subdirectory finds the nearest parent `Fxrun.toml` / `fxrun.toml` and executes commands from that directory.

## CLI

| Invocation | Behavior |
|------------|----------|
| `fxrun` | Run `[fxrun].default`, or `--list` if unset |
| `fxrun --list` | Print recipes and docs |
| `fxrun <name>` | Resolve depends (fail-fast), then run |
| `fxrun --dry-run <name>` | Print plan; do not spawn |
| `fxrun --force <name>` | Bypass content-hash skip |

Exit codes: `0` ok · `2` unknown recipe / missing manifest · `4` dependency cycle · otherwise the failing command’s exit code.

## Rebuild from source

With `fx` 0.9.6+ on `PATH` and `FX_STD_ROOT` pointing at fx `std/` (and fx package providing `host/cli` + `host/process`):

```text
fx build fxrun_lib.fx -o out --emit-c --cli
```

No author-written `host.c` — `--cli` auto-links the shared process/argv spine ([CLI auto-host](https://github.com/ledocorp/fxlang)).

## Non-goals (v1)

Parallel DAG · remote cache · Make/just syntax · replacing `fx build` · macOS prebuilt claim

## Docs

- [docs/FXRUN.md](docs/FXRUN.md) — design summary  
- [docs/releases/](docs/releases/) — release notes  
- Language: [ledocorp/fxlang](https://github.com/ledocorp/fxlang)

## License

Copyright Shawn Londono · LedoCorp · Apache-2.0 — see [LICENSE](LICENSE).
