# Moon shallow-history warning experiment

Follow-up to `tool.scad-project#89`.

## Decision

Do **not** fetch full Git history during normal SCAD capability materialization
merely to silence Moon's shallow-checkout warning.

The host-side affected preflight already uses the explicit base/head revisions
and is the authoritative changed-file decision. Materialization invokes normal
`moon run` for capabilities that have already been selected; it does not use
`--affected`.

## Controlled probe

Run `35719073604` uses Moon 2.5.4 and one tiny cached task in a synthetic Git
fixture.

| Variant | Full history | Explicit MOON_BASE/HEAD | Warning count | Task |
| --- | --- | --- | ---: | --- |
| shallow-current | no | no | **1** | success |
| shallow-explicit-range | no | yes | **1** | success |
| full-history-control | yes | no | **0** | success |

Both shallow variants emit:

```text
Detected a shallow checkout while comparing against an explicit base,
changed files may be inaccurate. A full Git history is recommended.
```

Supplying explicit `MOON_BASE` / `MOON_HEAD` does not remove the warning.
Only the full-history control removes it.

The real HUB75 production path may phrase the same Moon changed-file limitation
as:

```text
A full Git history is required for affected checks,
falling back to an empty files list.
```

The important boundary is unchanged: this warning occurs during already-selected
task materialization, not during the host's explicit affected preflight.

## Why no production change

Fetching complete history would add Git/network work to every relevant run only
to suppress a warning from an internal Moon changed-file probe.

The production contract instead keeps:

- exact shallow source checkout;
- exact comparison-base fetch for the host affected query;
- explicit base/head affected evidence on the host;
- normal Moon hashing/output hydration for the selected task;
- SCons target-level reuse where configured.

If a future Moon release changes the task-run/affected interaction, requalify
this behavior. Do not globally suppress Moon warnings.

## Experiment housekeeping

The older execution-boundary and clamps-lifecycle workflows are now
`workflow_dispatch` only, so follow-up PRs no longer spend runner time on
completed benchmark rounds.
