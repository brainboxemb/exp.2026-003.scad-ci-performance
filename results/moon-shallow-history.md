# Moon shallow-history warning experiment

Follow-up to `tool.scad-project#89`.

This round isolates Moon 2.5.4 task materialization from SCAD rendering. A tiny
cached task is executed against the same two-root shallow Git shape used by
production.

Variants:

1. current shallow behavior;
2. shallow checkout with explicit `MOON_BASE` / `MOON_HEAD`;
3. full-history control.

The goal is to determine whether the warning is actionable without disabling
Moon caching or downloading full repository history.
