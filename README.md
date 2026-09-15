# SCAD CI performance experiment

This repository is a controlled benchmark for the SCAD CI execution-boundary decision tracked by [`brainboxemb.meta#53`](https://github.com/brainboxemb/brainboxemb.meta/issues/53).

The experiment compares functionally equivalent execution models while keeping the SCAD workload fixed.

## Variants

1. **Job container** — GitHub Actions job-level `container:` using `ghcr.io/brainboxemb/scad-toolchain:v0.4.1`.
2. **Cached host** — OpenSCAD restored on the GitHub host through the historical `brainboxemb.github.actions/actions/openscad-setup` composite action.
3. **Host + docker run** — a normal host job that starts the same SCAD toolchain explicitly with `docker run`.

## Fixture

Every measured variant will execute the same workload:

- export `fixture/benchmark.scad` to STL;
- render it to PNG;
- apply the same Pillow watermark to the PNG;
- validate and checksum both outputs;
- write machine-readable timing evidence.

The watermark is intentionally part of the measured workload because generated project PNGs are watermarked in the production SCAD flow.

## Method

The first commit only probes the exact OpenSCAD development snapshot frozen in `scad-toolchain:v0.4.1`. The cached-host variant will then be pinned to that exact snapshot instead of using a moving `latest` target.

After version alignment, the A/B/C benchmark will be repeated enough times to distinguish structural overhead from GitHub runner and image-pull variance. Warm and cold cache behavior are reported separately.

This repository is experimental evidence only. Production tooling changes belong in their owning repositories after the experiment reaches a documented conclusion.
