# Generated build output

This directory contains generated output for a successful project build.
It is generated automatically and should not be edited manually.

## Artifacts

- [Design documentation](design/README.md)

<!-- scad-project-evidence-navigation -->
## Producer execution evidence

These files describe the SCAD producer executions that actually created the retained output.
They remain unchanged when equivalent output is later hydrated from cache.

- [scad-docs execution](evidence/executions/scad-docs/execution.json) — capability, producer source revision, exact owner revision and result.
  - [scad-docs log](evidence/executions/scad-docs/execution.log) — concise human-readable producer summary.

## Domain evidence

Structured SCAD/SCons reports contain the detailed target-level build and cache decisions.
They are richer domain evidence, not alternate producer logs.

- No structured domain reports are present for this output.

## Orchestration/materialization evidence

The publication layer may add `orchestration/materialization.json` for the current source revision/context and `orchestration/moon.log` for Moon's execute/cache/hydrate decision.
After cache hydration, that current materialization revision may intentionally differ from the producer `source_revision` above.

## Publication context

- Context: `pull_request`
- Source: pull_request `feature/pr-7-m004-common-production`
- Generated branch: `dev/pr-7/build`
- Policy: mutable snapshot; replaced by the next successful publication

See `publication-info.txt` for the exact source commit, tooling and runtime provenance.
Publication/finalization consumes prepared output and must not rewrite producer execution evidence.
