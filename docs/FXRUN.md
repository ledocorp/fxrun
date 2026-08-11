# fxrun — user design summary

fxrun is a **command runner** (closer to `just` than Make/Bazel): named recipes, explicit dependencies, optional content-hash skip when both `inputs` and `outputs` are declared.

## Why fxrun

| Keep | Refuse (v1) |
|------|-------------|
| Human `Fxrun.toml` in the repo | Generated ninja / Bazel graphs |
| Listable recipes + docs | Cryptic Make / tab tax |
| Deps run first; fail-fast | Parallel DAG scheduler |
| Opt-in hash skip | Always-mtime rebuild theater |
| fx for logic; C for argv/spawn | Rewriting the tool in C |

## Schema (v1)

```toml
[fxrun]
version = 1
default = "test"

[recipe.build]
doc = "One-line help for --list"
cmds = ["echo build"]

[recipe.test]
depends = ["build"]
cmds = ["echo test"]

[recipe.gen]
inputs = ["src/in.txt"]
outputs = ["out/generated.txt"]
cmds = ["cmd /c copy /Y src\\in.txt out\\generated.txt"]
```

Rules:

1. Recipes are tasks (not implicit file targets).  
2. Skip only when **both** `inputs` and `outputs` are non-empty and hashes match.  
3. `--force` bypasses skip.  
4. `--dry-run` prints commands without spawning.  
5. Manifest discovery walks from cwd to parents (`Fxrun.toml` preferred, else `fxrun.toml`).

## Platforms

Windows and Linux **x86_64** (same floor as fx 0.9.6). Shell command strings differ by OS — document recipes per platform or use portable tools.

## Dual path

Product builds support **emit-C** (ship oracle) and **IR → QBE → native**. Release binaries may include both `fxrun` and `fxrun-ir`.
