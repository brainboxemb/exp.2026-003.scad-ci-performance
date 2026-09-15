# SCAD CI execution benchmark results

## Decision

**Retain the GitHub job-level Docker container as the SCAD production runtime for Migration 004.**

The benchmark found a real warm-cache latency opportunity on the host, but no host implementation preserved the same overall execution semantics as `ghcr.io/brainboxemb/scad-toolchain:v0.4.1` without effectively maintaining a second container-like userspace bundle. The strongest exact-binary host experiment still failed to initialize EGL consistently, produced different STL/PNG bytes from Docker, and rendered materially slower. Explicit `docker pull` + `docker run` preserved correctness but did not outperform GitHub's native job-container boundary.

This recommendation does **not** undo the lightweight host preflight. The production model remains:

```text
host Moon preflight
  -> if affected: one GitHub SCAD job container
  -> lightweight publication outside the SCAD container
```

The performance issue that triggered this experiment should therefore be addressed by reducing serial orchestration/publication overhead around the container, not by replacing the qualified SCAD runtime with cached host tooling.

## Controlled workload

All variants use the same `fixture/benchmark.scad` and `scripts/run-benchmark.sh` workload:

1. STL export;
2. 1024×768 PNG render;
3. Pillow watermark;
4. non-empty validation and SHA-256 evidence.

Docker variants use `ghcr.io/brainboxemb/scad-toolchain:v0.4.1`, which reports `OpenSCAD version 2026.09.09.nightly`.

The immutable Docker image contains:

- Debian package `openscad-nightly=20260909T191259.git33e8fdd8.debian-0`;
- `/usr/bin/openscad-nightly` SHA-256 `2ae45a19d347c39338f8ffa4b5468f097b96419f23fb814e08cbaed8b965f4e2`;
- Pillow `12.3.0` and the qualified image runtime.

The live OBS repository no longer offers that exact OpenSCAD package version. This matters for host reproducibility: the immutable OCI image currently preserves the exact package build while the live package feed does not.

## Variants

| Variant | Description | Runtime identity |
| --- | --- | --- |
| A | GitHub job-level container using `scad-toolchain:v0.4.1` | Reference |
| B | Historical cached-host `openscad-setup` action with dated AppImage | Same date, different OpenSCAD build |
| C | Host job that pulls `scad-toolchain:v0.4.1` and invokes it with `docker run` | Same image as A |
| D | Exact-binary host bundle extracted from immutable v0.4.1 and restored from Actions cache | Same OpenSCAD binary, reconstructed userspace boundary |

## Phase 1 — A/B/C repetitions

### Run 34951061705 — first execution

| Variant | Tool setup | STL | PNG | Watermark | Workload total |
| --- | ---: | ---: | ---: | ---: | ---: |
| A — job container | ~17.2 s container initialization | 221.5 ms | 423.1 ms | 109.0 ms | 758.3 ms |
| B — cached host, cold | 17.50 s | 557.5 ms | 2590.2 ms | 111.1 ms | 3264.0 ms |
| C — host + docker pull/run | 17.77 s | 214.4 ms | 422.7 ms | 110.3 ms | 751.1 ms |

Cold B included missing Ubuntu runtime packages, an 80.5 MB AppImage download, checksum verification, AppImage extraction and saving a roughly 79 MB Actions cache.

A and C produced byte-identical STL and watermarked PNG output. B produced the same watermarked PNG in this sample, but its STL differed because the dated official AppImage is not the OBS nightly package frozen in the Docker image.

### Warm-cache rerun attached to run 34951061705

The OpenSCAD AppImage cache hit successfully, but a fresh GitHub runner still lacked runtime packages checked by the historical setup action. It therefore ran `apt update` and installed OpenGL/EGL/Pillow packages again.

Observed warm-cache setup: **22.81 s**. Workload total: **6271.0 ms**.

This established that caching only the AppImage does not remove host runtime provisioning.

### Run 34951397954 — second full execution

| Variant | Tool setup | STL | PNG | Watermark | Workload total |
| --- | ---: | ---: | ---: | ---: | ---: |
| A — job container | ~15.7 s container initialization | 241.9 ms | 408.6 ms | 107.5 ms | 762.3 ms |
| B — cached host, warm AppImage | 11.95 s | 482.7 ms | 2563.6 ms | 85.1 ms | 3135.9 ms |
| C — host + docker pull/run | 25.68 s | 179.1 ms | 339.6 ms | 86.2 ms | 608.4 ms |

### Run 34951519205 — third full execution

| Variant | Tool setup | STL | PNG | Watermark | Workload total |
| --- | ---: | ---: | ---: | ---: | ---: |
| A — job container | ~18.3 s container initialization | 234.3 ms | 424.3 ms | 107.9 ms | 770.9 ms |
| B — cached host, warm AppImage | 12.45 s | 2701.1 ms | 1958.7 ms | 115.7 ms | 4781.1 ms |
| C — host + docker pull/run | 26.37 s | 180.4 ms | 330.1 ms | 85.9 ms | 599.5 ms |

### Phase-one pattern

- **A — job-level container:** startup roughly 16–18 s in the normal samples; workload stable around 0.76 s.
- **B — historical cached host:** nominal setup can be somewhat shorter when the AppImage cache is warm, but fresh runners still provision host packages and execution is slower/variable. It is not binary-equivalent to Docker.
- **C — explicit Docker invocation:** workload matches A and output is byte-identical, but registry/layer-pull latency is more variable and often materially worse than the native job-container boundary.

## Phase 2 — exact-binary cached host bundle

Variant D was added because B was not an exact runtime comparison. On a cold miss, D extracts from the immutable v0.4.1 image:

- the exact `openscad-nightly` package payload;
- recursive dynamic-library closure;
- Qt platform/image plugins;
- Mesa/GLVND metadata and driver resources;
- Pillow `12.3.0` into a host Python path.

The exact OpenSCAD binary hash is checked before every workload. A warm D hit uses no Docker pull and no apt provisioning.

### Run 34953456808 — first successful cold exact bundle

| Variant | Tool setup | STL | PNG | Watermark | Workload total |
| --- | ---: | ---: | ---: | ---: | ---: |
| A — job container | ~16.2 s container initialization | 246.3 ms | 422.3 ms | 109.9 ms | 782.5 ms |
| B — cached host AppImage | 18.42 s | 8247.5 ms | 5429.3 ms | 114.0 ms | 13795.9 ms |
| C — host + docker pull/run | 15.98 s | 226.2 ms | 406.0 ms | 118.5 ms | 754.8 ms |
| D — exact cached host, cold | 28.31 s | 465.4 ms | 4348.0 ms | 132.2 ms | 4949.6 ms |

D saved a **178 MB uncompressed** bundle, approximately **71.8 MB compressed** in Actions cache. Its OpenSCAD executable is byte-identical to the Docker image.

The initial direct-ELF-loader launcher exposed an important packaging problem: OpenSCAD derives resources from its executable location. Starting the loader directly made the loader appear to be the application and broke localization/shader lookup. The launcher was corrected to invoke the exact cached OpenSCAD binary normally with image-derived libraries in `LD_LIBRARY_PATH`.

### Run 34953752615 — warm v5 bundle

The v5 host bundle restored successfully and skipped GHCR authentication/Docker/apt completely.

- setup: **1196.2 ms**;
- STL export: **255.3 ms**;
- PNG render: **4525.4 ms**;
- workload total: **4893.0 ms**.

This proves that a complete host cache can make tool availability very fast. It does **not** prove execution equivalence: `EGL_BAD_DISPLAY` remained, and outputs were not stable relative to Docker.

### Run 34954027168 — corrected resource lookup, warm cache

The launcher correction removed localization and missing-shader errors. Setup remained fast at **1464.0 ms**, but EGL still failed and workload remained slow:

- STL export: **1029.0 ms**;
- PNG render: **5594.9 ms**;
- workload total: **6726.4 ms**.

Output was still not byte-identical to Docker.

### Run 34954182921 — final v6 cold validation

The v6 bundle made Mesa DRI drivers themselves recursive closure roots so their runtime dependencies were also included. This was the final planned attempt to remove the remaining host-runtime discrepancy.

All four jobs passed at the workflow level, but D still reported **`Unable to initialize EGL: EGL_BAD_DISPLAY`**.

Same-run reference results:

| Variant | Tool setup | STL | PNG | Watermark | Workload total |
| --- | ---: | ---: | ---: | ---: | ---: |
| A — job container | ~17.7 s container initialization | 229.6 ms | 418.2 ms | 108.2 ms | **760.2 ms** |
| C — host + docker pull/run | 16.33 s | 212.7 ms | 403.9 ms | 113.9 ms | **734.4 ms** |
| D — exact cached host v6, cold | 31.03 s | 246.5 ms | 5613.5 ms | 140.5 ms | **6006.2 ms** |

A/C remained byte-identical:

- STL SHA-256: `958c62133b6d0c13351adb738d2f59a646d7a1f4b5dc662366d6d877de915c8a`;
- watermarked PNG SHA-256: `39e2904488000be0d782cc5e4c119d157ec101beaabe1798d09126b6cf9f0dcb`.

D produced different output:

- STL SHA-256: `2d454f3661ae2a92321b62a6c5f4c11856fe5ac08a45fe2876aa45171343d0f9`;
- watermarked PNG SHA-256: `c5c8b4ad084f0a987f53997fb874adc55b74282a2efe95587078e969b5c13db9`.

Because v6 still failed EGL after including the renderer-driver dependency closure, the pre-declared stop condition was met. No warm-v6 run is needed: cache-restore speed was already proven by v5, while v6 did not restore functional equivalence.

## Comparison and recommendation

| Criterion | A — job container | B — cached AppImage host | C — host + Docker | D — exact cached host bundle |
| --- | --- | --- | --- | --- |
| Exact Docker OpenSCAD build | Yes | No | Yes | Yes |
| Exact Docker rendering environment | Yes | No | Yes | No |
| A/C byte-identical fixture output | Reference | Not fully | Yes | No |
| Warm tool availability | Container pull/init | Fast cache but host apt remains | Docker pull | **~1.2–1.5 s** proven |
| Workload stability | **High** | Low | **High** | Low / EGL fallback |
| Extra distribution format | No | AppImage + host packages | No | **Yes: ~178 MB reconstructed userspace bundle** |
| Reproducibility if package feed changes | **Immutable image** | Snapshot server dependent | **Immutable image** | Depends on image-derived cache builder |
| Maintenance complexity | **Lowest complete runtime** | Host package + AppImage logic | Docker orchestration logic | **Highest** |

### Recommendation

Retain **A — the native GitHub job-level Docker container** for affected SCAD production.

Reasons:

1. A and C repeatedly execute the fixture in roughly **0.6–0.8 s** and produce byte-identical STL/PNG evidence.
2. C offers no compelling setup advantage over A and can have worse image-pull variance, so replacing the native job-container boundary with explicit `docker run` does not solve the Step-5 latency problem.
3. B is simpler than D but is not the same OpenSCAD build and still needs runtime provisioning on clean runners.
4. D proves a warm exact-binary host cache can restore in about **1.2–1.5 s**, but achieving that requires maintaining a second userspace distribution. Even after expanding the closure through Mesa drivers, EGL does not initialize equivalently, output differs, and PNG rendering remains roughly an order of magnitude slower than Docker on the fixture.
5. The immutable Docker image is also the only tested artifact that still contains the exact OBS package after that version disappeared from the live repository.

Therefore the Step-5 relevant-change regression should be treated as an **orchestration critical-path problem around a qualified runtime**, not as evidence that the runtime boundary itself should move to the host.

## Consequence for Migration 004

Experiment #53 can be closed with the Docker runtime retained.

Step 5 may resume, but its proportionality reassessment should now focus on whether the shared lifecycle can reduce serial overhead while preserving these invariants:

- README-only/unaffected changes start no SCAD container;
- affected normal CI starts at most one heavy SCAD container;
- Build and Verify remain logically independent;
- publication remains outside the SCAD container;
- current Moon/SCons evidence remains understandable and exact-source current.

Do not roll Step 5 into `lib.scad.hub75` until the current `lib.scad.clamps` draft has been re-evaluated with this decision recorded.