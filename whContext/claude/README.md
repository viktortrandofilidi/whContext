# Personal Claude Code agent

My personal Claude Code setup — skills, a review subagent, a review workflow, and
hooks — for working in this workspace (match / hamster / orchestrator / commons-kotlin).

Kept here in `whContext/claude/` (not inside the team repos) so it is tracked by the
whContext git repo and syncs across my machines. It is symlinked into `wf/.claude/`
so Claude Code discovers it when launched from the workspace root.

## Install (per machine)

```
bash whContext/claude/install.sh
```

Then restart Claude Code from the workspace root. `install.sh` symlinks `skills`,
`agents`, `workflows`, `hooks`, and `settings.json` into `wf/.claude/`. It never
touches `wf/.claude/settings.local.json` (machine-local permissions).

If symlinked `settings.json` isn't picked up on some setup, copy it instead:
`cp whContext/claude/settings.json wf/.claude/settings.json`.

## How it fits together

Two roles, one source of truth for the rules:

- **Builder agents write and self-review.** `match-builder` and `hamster-builder`
  implement a change to the repo canon, run that repo's mandatory formatter + gates,
  then self-review their own diff against the shared rubric before handing back.
- **Fresh-eyes review is a separate, on-demand pass.** `/self-review` (spawns the
  read-only `code-reviewer`) and `/deep-review` give a second opinion in their own
  context — run them when you want independent eyes, not self-review bias.
- **The `canon` skill is the single rulebook** both roles read from — per-repo
  commands/gates, match backend + hamster Kotlin conventions, and the review rubric.
  Change a rule once, there.

## What's here

- `skills/canon/` — shared coding canon (source of truth). `SKILL.md` + `reference/`:
  `commands-and-gates.md`, `match-backend.md`, `hamster.md`, `review-rubric.md`.
- `skills/frontend-feature/` — detailed playbook for match React UI (portal-admin /
  contextual-analytics). Lean `SKILL.md` + `reference/*` loaded on demand.
- `skills/self-review/` — everyday pre-handoff fresh-eyes review: gates + the
  `code-reviewer` subagent over the diff.
- `skills/deep-review/` — adversarial find→verify multi-agent review for important PRs
  (runs `workflows/deep-review.js`).
- `skills/pr-summary/` — concise, business-value PR summary from the branch↔base
  (master/main) diff; laconic, no code details, English output.
- `agents/match-builder.md` — authoring agent for match (Java/Spring + React): writes
  to canon, formats (spotless + pnpm), self-reviews. Edits files.
- `agents/hamster-builder.md` — authoring agent for hamster / orchestrator /
  commons Kotlin: writes to canon, runs `spotlessApply`, self-reviews. Edits files.
- `agents/code-reviewer.md` — read-only fresh-eyes reviewer, repo-aware, verifies its
  own findings against the shared rubric.
- `workflows/deep-review.js` — dimension finders → skeptic verification → ranked synthesis.
- `hooks/inline-style-check.sh` — PostToolUse nudge on inline styles in React files.
- `hooks/stop-gate.sh` — repo-aware Stop gate: prettier + inline-style check on changed
  match frontend files (`WF_STOP_GATE_FULL=1` also hard-blocks eslint + tsc);
  `WF_STOP_GATE_KOTLIN=1` hard-blocks `./gradlew spotlessCheck` on changed Kotlin files.
- `settings.json` — wires the two hooks.

The workspace `wf/CLAUDE.md` references the skills at their decision points so they
trigger reliably. orchestrator / commons-kotlin reuse `hamster-builder` + the Kotlin
canon; add dedicated builders by cloning `hamster-builder.md` if they need it.

## Scope note

The agents assume the workspace layout: code lives in sub-repos (`match`, `hamster`,
…) and git commands target the sub-repo that changed, not the workspace root.
