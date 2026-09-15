# SCAD CI lifecycle topology benchmark

This document records the end-to-end topology experiment requested by Migration 004 experiment #53. It complements `preliminary.md`, which settles the runtime-boundary sub-question.

## Decision

**Use one host orchestrator job around the immutable Docker SCAD runtime.**

The recommended shared lifecycle is:

```text
one host job
  -> Moon affected preflight
  -> if affected: docker run exact SCAD toolchain
  -> validate/stage after the container exits
  -> host publication in the same GitHub job
```

This keeps the qualified Docker runtime and the zero-container unaffected path, while removing the serial GitHub job/artifact handoffs that caused the Step-5 proportionality regression.

The recommendation requires one ownership correction before it can be released: generated-output publication safety is currently owned by `tool.git-project` but exposed only through a reusable workflow. `tool.git-project` must first expose the same publication contract as a reusable same-job action/script; `tool.scad-project` can then compose that primitive instead of copying publisher logic.

## Compared topologies

### A — released `tool.scad-project v0.13.0`

```text
host preflight job
  -> GitHub job-container production
  -> separate host publication jobs
```

Observed on `brainboxemb/lib.scad.clamps` PR #7:

- run `34946834079`: about 64 s end-to-end;
- run `34947426305`: about 65 s end-to-end;
- one SCAD container;
- aggregate runner consumption roughly 68–70 runner-seconds.

The producer graph itself is small. Most relevant-change latency is serial GitHub job/container/publication orchestration.

### C — one host orchestrator job

```text
one host job
  -> released Moon affected preflight
  -> if affected: docker run exact scad-toolchain:v0.4.1
  -> validate/stage after container exit
  -> publish both output trees from the same host job
```

The SCAD process still runs in the immutable qualified Docker image. Publication is outside the SCAD container process, but no separate GitHub publisher jobs are needed.

## Fixed consumer candidate

All relevant measurements use the exact Step-5 candidate:

- repository: `brainboxemb/lib.scad.clamps`;
- source: `bb071329e1d6c764d09f87ecd2cc78d42ac73679`;
- base: `52048164db5e5da0b9522c758551bc3af65cae45`;
- source-impact target: `consumer:scad.production-impact`;
- execution aggregate: `consumer:scad.ci`;
- SCAD image: `ghcr.io/brainboxemb/scad-toolchain:v0.4.1`;
- released Moon action/orchestrator code: `tool.git-project v0.2.6` / `5e004f0cee53648d6b6284b014b26bed502d2da2`;
- `tool.scad-project`: `da57820fdadd7d203091b6818984991f1548408f` (`v0.13.0`).

Generated Build and Verification trees are pushed only to experiment-repository branches, never to the real clamps publication branches.

## Wiring proof

An initial v1 run (`34955340243`) proved the README-only path but failed the relevant path because it accidentally invoked `moon-project.sh` from the older `tool.git-project` consumer gitlink. That was experiment wiring, not an architectural result.

v2 mounts the exact released `tool.git-project@v0.2.6` action source into the Docker process and uses its `moon-project.sh`, matching the released workflow's generic orchestration semantics.

## Sample 1 — run 34955615827

Both v2 jobs passed.

### Relevant change

Preflight:

- `affected=true`;
- status `success`;
- reason `target-or-upstream-affected`.

Production materialization:

- task `consumer:scad.ci`;
- source revision `bb071329e1d6c764d09f87ecd2cc78d42ac73679`;
- `tool_git_project_version=0.2.6`;
- Moon `2.5.4`;
- status `success`;
- exit code `0`;
- materialization duration `4028 ms`.

Moon completed six tasks in about 3.4 s. Build/documentation and Verify remain separate logical producer branches in the graph.

| Phase | Time |
| --- | ---: |
| Checkout + exact base fetch | 3.059 s |
| Moon affected preflight | 2.725 s |
| Docker login/pull | 24.738 s |
| Container bootstrap + producer graph | 6.342 s |
| Two same-job host publications | 3.862 s |
| **Measured lifecycle** | **41.024 s** |

The complete job, including Actions setup/artifact cleanup outside the explicit timer, was about 44 s wall-clock.

Both real publication pushes succeeded in the experiment repository:

- `dev/pr-1/clamps-lifecycle-build`;
- `dev/pr-1/clamps-lifecycle-verification`.

The sample used exactly **one** SCAD container and **one** GitHub lifecycle job.

### README-only control

- `affected=false`;
- zero Docker/container starts;
- affected-preflight: **3.261 s**;
- measured lifecycle: **4.369 s**.

## Sample 2 — run 34955904779

The second independent run also passed end-to-end and restored the portable Moon caches from the preceding run.

Production materialization again reported:

- task `consumer:scad.ci`;
- exact source `bb071329e1d6c764d09f87ecd2cc78d42ac73679`;
- `tool_git_project_version=0.2.6`;
- Moon `2.5.4`;
- status `success`;
- exit code `0`;
- materialization duration `4642 ms`.

| Phase | Time |
| --- | ---: |
| Checkout + exact base fetch | 3.026 s |
| Moon affected preflight | 2.569 s |
| Docker login/pull | 26.026 s |
| Container bootstrap + producer graph | 8.188 s |
| Two same-job host publications | 4.529 s |
| **Measured lifecycle** | **45.169 s** |

The two experiment publication branches were force-updated successfully again after the Docker process exited.

### README-only control

- `affected=false`;
- zero Docker/container starts;
- affected-preflight: **3.446 s**;
- measured lifecycle: **4.819 s**.

## Comparison

| Property | A — released multi-job topology | C — single host orchestrator |
| --- | ---: | ---: |
| Relevant sample 1 | ~64 s | **41.024 s** measured / ~44 s wall |
| Relevant sample 2 | ~65 s | **45.169 s** measured |
| Relevant SCAD container starts | 1 | 1 |
| Relevant GitHub lifecycle jobs | preflight + production + publishers | **1** |
| Relevant runner consumption | ~68–70 runner-s | roughly **one 44–48 s job** |
| README-only container starts | 0 | 0 |
| README-only measured lifecycle | short preflight | **4.369 s / 4.819 s** |
| SCAD runtime | immutable v0.4.1 image | **same immutable v0.4.1 image** |
| Build/Verify logical independence | yes | **yes, same Moon graph** |
| Publication boundary | separate host job | **same host job after Docker exits** |

The two C samples differ mainly in registry/layer-pull and normal hosted-runner variance. Both remain roughly 20 s faster than the released A topology. The measured C critical path is also close to the old ~37 s parallel Build/Verify baseline, without returning to two heavy container starts.

## Scenario coverage

The topology decision reuses the same released `tool.git-project v0.2.6` affected engine; changing the GitHub job boundary does not introduce a second affected implementation.

The Step-5 candidate already has retained exact-revision scenario evidence:

- README-only/unaffected: C runs `34955615827` and `34955904779`, zero container starts;
- docs/design-only: `lib.scad.clamps` proof PR #9, run `34947625311`; only `scad.docs` is in the producer impact route;
- Verify-only: proof PR #10, run `34947539588`; only `scad.verify` is in the producer impact route;
- normal relevant aggregate: C runs above, one container and current-source materialization;
- representative SCAD source and conservative missing-base behavior were already proven for the same generic v0.2.6 affected/production semantics during Migration-004 qualification; the production implementation of the single-job topology must retain those tests, including the existing `MOON_FORCE=true` conservative fallback, before release.

Cold/warm cached-host behavior is covered separately in `preliminary.md`; cached host tooling is rejected as the production runtime.

## Qualitative trade-offs

### Reproducibility and isolation

C preserves the exact immutable `scad-toolchain:v0.4.1` process boundary. It therefore avoids the AppImage/host-library divergence found in variants B and D. The SCAD process need not receive the publication token or Docker socket.

### Security/update surface

The host job already requires GitHub credentials for publication, but publication happens only after the SCAD container exits. Production implementation should pass only the environment/mounts required by SCAD/Moon into `docker run`; the GitHub token remains host-only.

### Debugging

A single relevant job gives one chronological log from preflight through production and publication. The Docker process remains explicit, so SCAD-runtime failures are still separated from host publication failures.

### Maintenance

The prototype copied generic publication mechanics only to measure the topology. That duplication is not acceptable production architecture. The existing stale-source checks, branch validation/context mapping and force-push policy belong to `tool.git-project`; they must be factored into a callable same-job primitive and reused by both the existing reusable publication workflow and `tool.scad-project`.

### Portability

The C topology is not clamps-specific. Inputs remain generic source-impact task, aggregate task, output trees, publication suffixes and exact source/base revisions. Once the publisher primitive is generic, the same `tool.scad-project` workflow can serve projects and libraries.

## Recommendation and required owner sequence

1. **Retain Docker as the SCAD runtime.** Do not revive cached host OpenSCAD tooling.
2. **Adopt C as the shared workflow topology:** one host orchestrator job with conditional `docker run` and same-job host publication after the container exits.
3. **First change `tool.git-project`:** extract the generated-output publication contract from `reusable-generated-output-publish.yml` into a reusable action/script, retain the existing workflow as a thin wrapper, test stale-source/context/branch safety, and release it.
4. **Then change `tool.scad-project`:** consume that released primitive, collapse preflight/production/publication into one host job, preserve exact Docker/version/Moon/materialization semantics and the conservative fallback, qualify the normal and README-only paths, then release it.
5. **Only then resume Step 5:** update `lib.scad.clamps` PR #7 to the released topology and repeat the retained Step-5 evidence/performance checks.
6. Keep Step 6 (`lib.scad.hub75`) blocked until Step 5 is complete.
