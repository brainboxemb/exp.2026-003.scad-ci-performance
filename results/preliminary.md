# Preliminary results

These observations are intentionally preliminary. The benchmark must be repeated before a recommendation is made.

## Controlled workload

All variants use the same `fixture/benchmark.scad` and `scripts/run-benchmark.sh` workload:

1. STL export;
2. 1024×768 PNG render;
3. Pillow watermark;
4. non-empty validation and SHA-256 evidence.

Docker variants use `ghcr.io/brainboxemb/scad-toolchain:v0.4.1`, which reports `OpenSCAD version 2026.09.09.nightly`. The historical cached-host action is pinned to the matching dated AppImage snapshot `2026.09.09`, but that AppImage is not the same package build as the Docker image.

The immutable Docker image contains:

- Debian package `openscad-nightly=20260909T191259.git33e8fdd8.debian-0`;
- `/usr/bin/openscad-nightly` SHA-256 `2ae45a19d347c39338f8ffa4b5468f097b96419f23fb814e08cbaed8b965f4e2`.

The live OBS repository no longer offers that exact package version. Variant D therefore derives its exact host bundle from the immutable v0.4.1 image on a cold cache miss, verifies the binary hash above, and stores the resulting user-space bundle in Actions cache. A warm D run must not use Docker or apt.

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

A and C produced byte-identical STL and watermarked PNG output. B produced the same watermarked PNG bytes, but its STL bytes differ because the dated official AppImage is not the exact same OpenSCAD package build as the OBS nightly frozen in the Docker image.

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

Three complete A/B/C runs plus one additional warm-host rerun show a repeatable structural pattern:

- **A — job-level container:** startup is roughly 16–18 s; the measured OpenSCAD workload is stable around 0.76 s.
- **B — historical cached-host action:** a warm AppImage can make nominal setup faster than A (about 12 s in two normal samples), but the clean runner still needs host-package provisioning and the AppImage workload is materially slower and variable.
- **C — explicit `docker pull` + `docker run`:** OpenSCAD execution is as fast as A, but image-pull latency is more variable and often materially worse than GitHub's native job-container boundary.
- **Watermark:** roughly 0.09–0.12 s everywhere. The final watermarked PNG is byte-identical across A/B/C.

For the production decision, B is not an exact-equivalence implementation: it uses the official dated AppImage (`2026.09.09`) while A/C use the OBS nightly package frozen in the v0.4.1 image (`2026.09.09.nightly`).

## Variant D — exact cached host bundle

Variant D tests a stronger host-cache design. On a cold miss it derives a user-space bundle from the immutable Docker image containing the exact OpenSCAD package payload, recursive dynamic-library closure, Qt rendering plugins, Mesa/EGL resources, and Pillow 12.3.0. The OpenSCAD process is launched through the image-derived ELF loader. The image-derived runtime is scoped to OpenSCAD; the watermark remains a host-Python process using the cached Pillow package.

This is deliberately more demanding than B: D tests whether the container execution boundary can be removed **without changing the OpenSCAD binary**.

### Run 34953456808 — first successful cold D bundle

All four variants succeeded in this run.

| Variant | Tool setup | STL | PNG | Watermark | Workload total |
| --- | ---: | ---: | ---: | ---: | ---: |
| A — job container | ~16.2 s container initialization | 246.3 ms | 422.3 ms | 109.9 ms | 782.5 ms |
| B — cached host AppImage | 18.42 s | 8247.5 ms | 5429.3 ms | 114.0 ms | 13795.9 ms |
| C — host + docker pull/run | 15.98 s | 226.2 ms | 406.0 ms | 118.5 ms | 754.8 ms |
| D — exact cached host, cold | 28.31 s | 465.4 ms | 4348.0 ms | 132.2 ms | 4949.6 ms |

D produced and saved a **178 MB uncompressed host bundle**, compressed to about **71.8 MB** in Actions cache. Its OpenSCAD executable reports the same nightly version and matches the exact Docker binary SHA-256.

Functional-equivalence evidence is mixed:

- D's final watermarked PNG SHA-256 is `39e2904488000be0d782cc5e4c119d157ec101beaabe1798d09126b6cf9f0dcb`, **byte-identical to A and C** on this fixture.
- D's STL SHA-256 is `1c511652e554a669e8082115426dd4ca1988a7747d00db52a8cf63c5cc35f17e`, while A/C produce `958c62133b6d0c13351adb738d2f59a646d7a1f4b5dc662366d6d877de915c8a`.
- D still reports `EGL_BAD_DISPLAY`, localization warnings, and missing `ViewEdges.frag` / `ViewEdges.vert` resources. The matching PNG therefore does not yet prove that the cached host runtime is generally equivalent to the container runtime.

The differing STL must not be dismissed as harmless serialization variance without further checking. D is therefore still an experimental runtime, not a candidate production replacement yet.

## Next measurement — warm D

The v5 exact-host cache from run `34953456808` is now populated. The next run must verify that D:

1. restores `scad-exact-host-v5-ubuntu24-x64-image-v0.4.1-pillow12.3.0` from cache;
2. skips GHCR authentication and does not execute Docker or apt in the D job;
3. verifies the exact OpenSCAD binary hash;
4. runs the same STL + PNG + watermark workload;
5. records warm setup and workload timing;
6. retains the current output-equivalence warnings explicitly.

Only after that warm measurement should we decide whether resolving the remaining resource-path/STL difference is worth further engineering. If warm D is not materially better than A, the extra bundle construction and runtime-maintenance complexity is itself sufficient evidence against replacing the job-container model.

## Current non-conclusion

Do **not** yet change Migration 004's production runtime. Job-level Docker remains the most stable complete runtime. Variant D has shown that an exact-binary cached host bundle is technically possible, but it currently requires a second distribution format and is not yet fully output-equivalent. The warm D measurement is the next decision point.
