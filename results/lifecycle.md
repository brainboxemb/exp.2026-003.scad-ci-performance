# SCAD CI lifecycle topology benchmark

This document records the end-to-end topology experiment requested by Migration 004 experiment #53. It complements `preliminary.md`, which settles the runtime-boundary sub-question.

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

Job: `C lifecycle v2 - relevant change`.

Preflight evidence:

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

Measured lifecycle:

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

The same run created a local commit changing only `README.md` and compared it against the exact Step-5 candidate.

Result:

- `affected=false`;
- zero Docker/container starts;
- affected-preflight time: **3.261 s**;
- measured lifecycle: **4.369 s**.

This independently preserves the key Migration-004 unaffected-change invariant.

## First-sample interpretation

This is a materially different result from the runtime-only benchmark.

Variant C does **not** make Docker image retrieval faster. In this sample, Docker setup was 24.7 s. Its advantage is that checkout, preflight, the single exact Docker process, validation and both publications stay on one hosted runner instead of crossing multiple serial GitHub job boundaries.

Compared with the current released A topology on the same Step-5 candidate:

- A: about **64–65 s** relevant feedback;
- C sample 1: **41.0 s measured / ~44 s wall-clock**;
- old pre-Migration parallel Build/Verify baseline: about **37 s** critical path, but used two heavy containers.

C therefore removes roughly **20–24 s** from the current common-workflow critical path in this first sample while retaining one SCAD container. It also appears to reduce relevant-change runner consumption from roughly 68–70 runner-seconds to roughly one ~44 s runner job.

This is promising but not yet a final architecture decision because Docker-pull latency varies substantially between hosted runners. At least one additional independent relevant-change sample is required before #53 is closed or the shared workflow is redesigned.
