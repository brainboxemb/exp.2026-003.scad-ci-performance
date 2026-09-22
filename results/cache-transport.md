# Cache transport benchmark

Follow-up round for
[`tool.scad-project#89`](https://github.com/brainboxemb/tool.scad-project/issues/89).

## Decision

For SCons-backed SCAD production, do **not** transport a rolling portable Moon
output cache through a broad restore prefix.

Keep Moon as the affected/task orchestration layer, but scope its portable
output cache to the **exact producer source SHA**:

```text
same source SHA rerun
  -> exact Moon cache hit
  -> fast whole-capability hydration

new source SHA
  -> Moon cache miss / empty generation
  -> SCons CacheDir provides target-level reuse
  -> save one bounded Moon generation for this SHA
```

This preserves the useful same-source Moon fast path without carrying every
older capability generation into every later PR commit.

Direct-engine consumers are a different case: they do not have SCons as the
fine-grained target cache and should not be changed by this experiment.

## Why

The current rolling cache restored `.moon/cache/hashes` and
`.moon/cache/outputs` from the most recent compatible run and then saved the
expanded directories under a new run-specific key. A new source hash therefore
adds another set of capability outputs while retaining the previous ones.

In this experiment one incremental SCAD source change grew Moon outputs from
about **21.38 MB to 42.76 MB uncompressed** and from about **21.41 MB to
42.78 MB compressed in Actions cache**.

That accumulation matches the real HUB75 PR #45 observation: production run
167 restored a **1,317,063,917 B (~1,256 MiB)** portable Moon cache. At roughly
21 MB per generation that is the same order as about sixty retained
generations.

## Fixed consumer and tooling

The seed is the same HUB75 source/tooling line used by green SCAD production
run 167:

- HUB75 seed source: `660b04129bb127d13eaf59dca3c51ffeb8251572`;
- `tool.scad-project`: `70fd4162731484a949dc390e942dde8b8d811f10` / v0.15.2;
- `tool.git-project`: `9879da589101f41b2b0e634d196ddcc51e1a6102` / v0.2.9;
- runtime: `ghcr.io/brainboxemb/scad-toolchain-openscad:v0.6.1`.

The incremental round creates the same deterministic source commit in both
matrix jobs by appending a comment-only SCAD source change:

- base: `660b04129bb127d13eaf59dca3c51ffeb8251572`;
- source: `9cbaae4985e7d39ffdc931f82cfe19ab27e2e98c`.

The comment intentionally changes source identity without changing geometry.

## Compared variants

### A — rolling Moon + SCons

Transport between runners:

- Moon `.moon/cache/hashes` + `.moon/cache/outputs`, restored through the
  broad compatible-prefix behavior used by production;
- normal SCons cache;
- Verification SCons cache.

### B — SCons-only transport

Transport between runners:

- normal SCons cache;
- Verification SCons cache.

Moon still performs affected selection and invokes the same three SCAD
capabilities. Only portable Moon output transport is removed.

Each variant has an independent cache lineage so neither can seed the other's
SCons state.

## Round 1 — cold seed

Run `35704327282` seeded both independent lineages. The CAD/materialization
work and cache saves succeeded; the first harness revision failed only in the
post-build evidence step and was corrected before the measured warm rounds.

Both variants were actually cold:

- Build: 57 built / 0 cache-restored;
- Verification: 60 built / 0 cache-restored.

Compressed cache saves for A were approximately:

| Cache family | Cold seed |
| --- | ---: |
| Moon portable | 21.41 MB |
| normal SCons | 18.16 MB |
| Verification SCons | 0.74 MB |

Variant B seeded the same-size SCons caches and intentionally saved no portable
Moon cache.

## Round 2 — same-source warm rerun

Run `35704781495` reran the exact seed source.

| Phase | A — Moon + SCons | B — SCons only |
| --- | ---: | ---: |
| cache restore | 2.464 s | 1.163 s |
| runtime pull | 13.768 s | 12.769 s |
| materialization | **9.884 s** | 19.950 s |
| cache save | 4.004 s | 2.570 s |
| total | **39.802 s** | 47.250 s |

For B, SCons restored every target:

- Build: 0 built / 57 cache-restored;
- Verification: 0 built / 60 cache-restored.

For A, Moon hydrated the cached whole-capability outputs. Producer SCons
summaries visible in the hydrated log still describe the original cold producer
execution; they must not be read as evidence that 57/60 targets rebuilt in the
rerun.

**Result:** a small, clean Moon output cache is useful for rerunning an exact
source SHA. A was about 7.45 s faster end-to-end.

## Round 3 — incremental source commit

Run `35705122613` restored each variant's warm seed caches and then built the
same deterministic new SCAD source commit.

Both variants made exactly the same target decisions:

- Build: **28 built / 29 cache-restored**;
- Verification: **9 built / 51 cache-restored**.

Their generated-output checksum manifests are **byte-for-byte identical**.

### Timing

| Phase | A — rolling Moon + SCons | B — SCons only | A minus B |
| --- | ---: | ---: | ---: |
| cache restore | 5.407 s | 2.413 s | +2.994 s |
| runtime pull | **15.596 s** | 25.390 s | -9.795 s |
| materialization | 79.612 s | **55.184 s** | +24.427 s |
| cache save | 6.454 s | **3.218 s** | +3.236 s |
| total | 118.599 s | **102.441 s** | +16.157 s |

B suffered almost ten seconds more runtime-pull latency yet still finished
about sixteen seconds earlier. The cache/materialization difference therefore
dominates the observed result even with registry noise working against B.

### Cache growth

Before the incremental source:

| Cache family | A retained data |
| --- | ---: |
| Moon hashes | 0.10 MB |
| Moon outputs | **21.38 MB** |
| normal SCons | 182.92 MB uncompressed / ~18.16 MB Actions cache |
| Verification SCons | 0.96 MB uncompressed / ~0.74 MB Actions cache |

After one incremental source:

| Cache family | A retained data |
| --- | ---: |
| Moon hashes | 0.20 MB |
| Moon outputs | **42.76 MB** |
| normal SCons | 276.24 MB uncompressed / ~27.44 MB Actions cache |
| Verification SCons | 1.19 MB uncompressed / ~0.74 MB Actions cache |

The Moon output directory almost exactly doubled because the restored previous
generation remained present beside the new source generation. Its compressed
Actions save likewise grew from ~21.41 MB to **42.78 MB**.

SCons also accumulates reusable objects, but its cache is strongly compressed
and its target-level reuse is exactly the behavior needed for an incremental
source commit.

## Correctness

Variant A and B retained the same:

- affected capability set;
- materialization capability set;
- Build target decisions;
- Verification target decisions;
- generated PNG/STL/verification outputs.

The retained `generated.sha256` manifests from run `35705122613` have no
differences.

No real HUB75 generated-output branch was published by the experiment.

## Proposed production cache policy

For `build_engine.engine == scons`:

```text
Moon key =
  moon version
  + runner OS
  + repository-local namespace
  + exact resolved source SHA

restore keys =
  none
```

The existing normal and Verification SCons caches retain their compatible
restore behavior.

For a new source SHA, Moon starts with an empty portable output cache and SCons
performs target-level reuse. If that exact source SHA is rerun, Moon can hydrate
the already-produced capabilities immediately.

For non-SCons/direct consumers, retain the existing broader Moon reuse until a
separate experiment shows a better policy.

## Separate follow-up questions

This round intentionally does not change these independent concerns:

1. materialization still emits Moon's
   `A full Git history is required ... falling back to an empty files list`
   warning even though the host explicit base/head preflight is precise;
2. normal PR validity still uses PR base -> current head rather than previous
   PR head -> current head for incremental execution scope;
3. consumer-local Moon input declarations remain broad enough that a SCAD
   source change can affect docs + build + verify.

Those should be investigated after the cache-transport fix so their evidence is
not confounded with a second simultaneous orchestration change.
