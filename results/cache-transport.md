# Cache transport benchmark

Follow-up round for
[`tool.scad-project#89`](https://github.com/brainboxemb/tool.scad-project/issues/89).

## Hypothesis

For SCons-backed consumers, transporting complete Moon task outputs between
fresh GitHub runners may duplicate the finer-grained reuse already provided by
SCons `CacheDir`.

The controlled comparison keeps Moon as the affected/task orchestration layer
in both variants and changes only whether its portable output/hash cache is
transported between runners.

## Fixed consumer

- HUB75 source: `660b04129bb127d13eaf59dca3c51ffeb8251572`
- comparison base: `f571179432574002a5ab4e4f85a3fb0af2a9fdcd`
- `tool.scad-project`: exact consumer gitlink `70fd4162731484a949dc390e942dde8b8d811f10` / v0.15.2
- `tool.git-project`: `9879da589101f41b2b0e634d196ddcc51e1a6102` / v0.2.9
- runtime family: v0.6.1

This is the same HUB75 source/tooling line as SCAD production run 167.

## Variants

### A — baseline Moon + SCons

Transport between runners:

- Moon `.moon/cache/hashes` + `.moon/cache/outputs`;
- normal SCons cache;
- Verification SCons cache.

### B — SCons-only transport

Transport between runners:

- normal SCons cache;
- Verification SCons cache.

Moon still performs affected selection and invokes the same three SCAD
capabilities. Only portable Moon output transport is removed.

## Measurement protocol

Each variant owns a separate cache namespace.

1. First PR run: cold seed.
2. Second PR run with unchanged benchmark/source inputs: warm comparison.
3. Compare cache transfer sizes from Actions logs, retained cache directory
   sizes, phase timings, SCons target outcomes and generated-artifact manifests.
4. Only after the A/B result, investigate the separate shallow-history and
   incremental-affected questions.

No real HUB75 generated-output branch is published by this experiment.
