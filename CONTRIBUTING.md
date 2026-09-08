# Contributing

1. Keep changes fx-native (`fx build … --cli`; no per-tool host.c).
2. Dual-path: emit-C and IR corpora in `tests/smoke.ps1` must stay green.
3. Do not add parallel DAG / remote cache / Make compatibility in v1 without a design note.
4. Public docs stay free of private monorepo board jargon.

License: GPL-3.0.
