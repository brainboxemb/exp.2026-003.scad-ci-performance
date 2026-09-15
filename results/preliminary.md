# Preliminary results

These observations are intentionally preliminary. The benchmark must be repeated before a recommendation is made.

## Controlled workload

All variants use the same `fixture/benchmark.scad` and `scripts/run-benchmark.sh` workload:

1. STL export;
2. 1024×768 PNG render;
3. Pillow watermark;
4. non-empty validation and SHA-256 evidence.

Docker variants use `ghcr.io/brainboxemb/scad-toolchain:v0.4.1`, which reports `OpenSCAD version 2026.09.09.nightly`. The cached-host action is pinned to the matching dated AppImage snapshot `2026.09.09`.

## Run 34951061705 — first execution

The first cached-host execution was a cold cache miss.

| Variant | Tool setup | STL | PNG | Watermark | Workload total |
| --- | ---: | ---: | ---: | ---: | ---: |
| A — job container | ~17.2 s container initialization | 221.5 ms | 423.1 ms | 109.0 ms | 758.3 ms |
| B — cached host, cold | 17.50 s | 557.5 ms | 2590.2 ms | 111.1 ms | 3264.0 ms |
| C — host + docker pull/run | 17.77 s | 214.4 ms | 422.7 ms | 110.3 ms | 751.1 ms |

Cold cached-host setup included:

- missing Ubuntu runtime packages (`libegl1`, `libopengl0`, Pillow and dependencies);
- an 80.5 MB OpenSCAD AppImage download;
- checksum verification and AppImage extraction;
- saving the ~79 MB Actions cache.

A and C produced byte-identical STL and watermarked PNG output. B produced the same watermarked PNG bytes, but its STL bytes differ slightly because the dated official AppImage is not the exact same OpenSCAD package build as the OBS nightly frozen in the Docker image.

## Warm-cache rerun attached to run 34951061705

The rerun restored cache key `openscad-linux-x86_64-2026.09.09` successfully (~79 MB), so the AppImage itself was warm.

However, a fresh GitHub runner still lacked the runtime packages checked by the historical setup action. It therefore ran `apt update` and installed the OpenGL/EGL/Pillow packages again before extracting the cached AppImage.

Observed warm-cache setup in that sample: **22.81 s**.

Observed workload in that sample:

- STL export: 3738.9 ms;
- PNG render: 2414.1 ms;
- watermark: 112.4 ms;
- workload total: 6271.0 ms.

The large STL-time variation reinforces the need for several repetitions before interpreting runtime differences. The structural observation is already stable: an AppImage cache hit alone does not remove host runtime provisioning on the current GitHub runner image.

## Run 34951397954 — second full execution

This full run used fresh GitHub runners while the OpenSCAD AppImage cache was already populated.

| Variant | Tool setup | STL | PNG | Watermark | Workload total |
| --- | ---: | ---: | ---: | ---: | ---: |
| A — job container | ~15.7 s container initialization | 241.9 ms | 408.6 ms | 107.5 ms | 762.3 ms |
| B — cached host, warm AppImage | 11.95 s | 482.7 ms | 2563.6 ms | 85.1 ms | 3135.9 ms |
| C — host + docker pull/run | 25.68 s | 179.1 ms | 339.6 ms | 86.2 ms | 608.4 ms |

The host cache restore itself took about 2.0 s, but B still had to run `apt update/install` on the clean runner. C demonstrates substantial registry/layer-pull variation between runners: the exact same immutable image took materially longer to pull in this sample than in the first run.

## Run 34951519205 — third full execution

The third run again used fresh GitHub runners and a warm cached AppImage.

| Variant | Tool setup | STL | PNG | Watermark | Workload total |
| --- | ---: | ---: | ---: | ---: | ---: |
| A — job container | ~18.3 s container initialization | 234.3 ms | 424.3 ms | 107.9 ms | 770.9 ms |
| B — cached host, warm AppImage | 12.45 s | 2701.1 ms | 1958.7 ms | 115.7 ms | 4781.1 ms |
| C — host + docker pull/run | 26.37 s | 180.4 ms | 330.1 ms | 85.9 ms | 599.5 ms |

B again restored the ~79 MB AppImage from cache quickly, but spent most of setup provisioning the missing EGL/OpenGL/Pillow packages on the new runner. Its OpenSCAD execution time also remains both slower and more variable than the Docker-packaged nightly.

## Phase-one pattern

Three complete A/B/C runs plus one additional warm-host rerun now show a repeatable structural pattern:

- **A — job-level container:** startup is roughly 16–18 s; the measured OpenSCAD workload is stable around 0.76 s.
- **B — historical cached-host action:** a warm AppImage can make nominal setup faster than A (about 12 s in two normal samples), but the clean runner still needs host-package provisioning and the AppImage workload is materially slower and variable (~3.1–6.3 s across warm samples).
- **C — explicit `docker pull` + `docker run`:** OpenSCAD execution is as fast as A, but image-pull latency is more variable and was ~25–26 s in two of three samples. It currently has no performance case over GitHub's native job-container boundary.
- **Watermark:** ~0.09–0.12 s everywhere. The final watermarked PNG is byte-identical across all three variants, so watermarking is included without confounding the execution-boundary result.

For the production decision, B is still not an exact-equivalence implementation: it uses the official dated AppImage (`2026.09.09`) while A/C use the OBS nightly package frozen in the v0.4.1 image (`2026.09.09.nightly`). That difference is visible in STL bytes and likely contributes to runtime differences.

## Next experiment

The historical cached-host action is useful evidence but not the strongest possible host design because it caches only the AppImage. The next variant should therefore test a **complete cached user-space host bundle**:

- pre-extracted OpenSCAD snapshot;
- cached user-space EGL/OpenGL runtime libraries required by that AppImage where feasible;
- cached/pinned Pillow rather than `apt install` on every runner;
- no `apt update/install` on the warm path;
- the same benchmark workload and watermark.

If that design cannot be made self-contained without effectively maintaining a second container-like runtime bundle, record that as a maintenance/reproducibility cost rather than hiding it from the comparison.

## Current non-conclusion

Do **not** yet change Migration 004's production runtime based on phase one alone. Job-level Docker is currently the most stable complete runtime; the dedicated optimized-host variant is needed to test whether host caching can remove the setup penalty without sacrificing reproducibility or creating a second toolchain distribution format.
