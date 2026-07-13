---
name: frontend-feature
description: >-
  Implement or change UI in match's React apps (portal-admin, contextual-analytics).
  Use for a new or edited screen, page, component, modal, dialog, drawer, form,
  input, table, grid, list, accordion, wizard, tab, chart, or data hook — anything
  with Mantine + TanStack Query. Front-loads the conventions (reuse the existing
  pattern, Mantine style props / no inline styles, centralized query keys,
  mode-scoped wizard pickers, the logic traps) so the change is right first time
  and passes review without back-and-forth.
---

# Frontend feature playbook (match / portal-admin)

Work these steps in order. Load the linked reference file for a step only when
that step is in play — the details live there so this file stays short.

## The loop

1. **Orient — reuse, don't reinvent.** Find the nearest existing implementation of
   the same UI shape and mirror its props + CSS-module classes. Never hand-roll a
   generic version. → `reference/reuse-patterns.md`
2. **Style with no inline styles.** Mantine style props → `Box/Stack/Flex/Group` →
   co-located `*.module.css`. Never `style={{}}` / `styles={{}}`. → `reference/styling-and-layout.md`
3. **Fetch data the project way.** TanStack Query, keys from the centralized enum,
   key matches the normalized queryFn input, `gcTime: Infinity` for session cache.
   → `reference/data-and-logic.md`
4. **Route & gate.** portal-admin = TanStack Router (file-based, absolute `Link`
   paths); contextual-analytics = React Router v6 (don't over-convert legacy).
   Wrap permission-gated UI in `Restricted`.
5. **Scope wizard pickers to the current mode.** Every selector filters by the
   active mode, not the union of modes. → `reference/data-and-logic.md`
6. **Self-check before done.** Trace the logic traps, then run the gates and the
   `self-review` skill. → `reference/data-and-logic.md`

## Before you say "done" (from `match/portal-admin/frontend`)

```
pnpm ci:format && pnpm ci:lint && pnpm checkts
```

- Grep touched files for `style={{` / `styles={{` and convert any hit.
- If the task used an ephemeral env, strip peer-image override blocks from
  `deploy/environments/ephemeral/*.values.yaml`.
- Run the `self-review` skill to catch logic/convention issues before Copilot does.
