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

Across both full samples, the Docker OpenSCAD runtime remains much faster on this fixture than the AppImage runtime. The watermark itself is not a differentiator: it remains roughly 0.09–0.11 s and the final PNG hash is identical across all variants.

## Current non-conclusions

Do **not** yet conclude that Docker should be retained or removed. More repetitions are needed to establish distributions for job-container startup, explicit Docker pull, cached-host setup, and workload runtime. If the historical host action remains disadvantaged by package provisioning, a separate optimized-host variant should test whether caching a more complete user-space toolchain changes the result.
