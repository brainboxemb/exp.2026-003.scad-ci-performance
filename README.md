# SCAD CI performance experiment

This repository is a controlled benchmark for the SCAD CI execution-boundary decision tracked by [`brainboxemb.meta#53`](https://github.com/brainboxemb/brainboxemb.meta/issues/53).

The experiment compares functionally equivalent execution models while keeping the SCAD workload fixed.

## Variants

1. **Job container** — GitHub Actions job-level `container:` using `ghcr.io/brainboxemb/scad-toolchain:v0.4.1`.
2. **Cached host** — OpenSCAD restored on the GitHub host through the historical `brainboxemb.github.actions/actions/openscad-setup` composite action, pinned to exact source commit `0c73a5251d10956305aed48306c877e5aca25f1c`.
3. **Host + docker run** — a normal host job that explicitly pulls and starts the same v0.4.1 toolchain with `docker run`.

## Version control

A first probe established that `scad-toolchain:v0.4.1` contains:

```text
OpenSCAD version 2026.09.09.nightly
```

The cached-host variant therefore requests snapshot `2026.09.09` instead of a moving `latest` version.

## Common workload

Every measured variant executes `scripts/run-benchmark.sh`, which:

- exports `fixture/benchmark.scad` to STL;
- renders the same model to a 1024×768 PNG;
- applies the same Pillow-based watermark to the PNG;
- validates both files;
- records checksums, sizes, exact OpenSCAD/Pillow versions and phase timings in `timing.json`.

The watermark is intentionally part of the measured workload because generated project PNGs are watermarked in the production SCAD flow.

## Measurement intent

The first round is deliberately a small execution-boundary microbenchmark. Its purpose is to expose startup/restore overhead rather than hide it behind a long render.

For each run we inspect both the retained `timing.json` artifacts and GitHub job-step timings. The job-level container's `Initialize containers` phase is measured from Actions job metadata; host-cache and explicit-docker setup durations are also recorded inside the benchmark evidence.

Run multiple repetitions before drawing a conclusion. Warm and cold host-cache behavior must be reported separately.

If cached-host OpenSCAD is materially better, a second experiment round must reproduce the full current production-toolchain surface (PythonSCAD, BOSL2, pybosl2, Shapely, docsgen, SCons and Pillow) before Migration 004 changes execution strategy.

This repository is experimental evidence only. Production tooling changes belong in their owning repositories after the experiment reaches a documented conclusion.
