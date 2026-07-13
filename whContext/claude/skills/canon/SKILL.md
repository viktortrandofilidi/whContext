---
name: canon
description: >-
  Shared coding canon for the Windfall workspace (match / hamster / orchestrator /
  commons-kotlin). One source of truth for per-repo formatters + validation gates,
  match backend (Java/Spring) conventions, hamster (Kotlin) conventions, and the
  review rubric both the builder agents and the code-reviewer use. Load the
  reference file for the repo and layer you are touching — don't reimplement the
  rules from memory.
---

# Workspace coding canon

This skill is the single place the conventions live so the builder agents
(`match-builder`, `hamster-builder`), the `code-reviewer`, and `/self-review` /
`/deep-review` all pull from the same rules — no drift, no duplication.

## Which reference file to load

Load only what the task touches. The files are read by path; from the workspace
root they live under `.claude/skills/canon/reference/`.

| You are… | Load |
|---|---|
| Formatting / running gates in ANY repo | `reference/commands-and-gates.md` |
| Writing match Java/Spring backend | `reference/match-backend.md` |
| Writing match React (portal-admin / contextual-analytics) | the `frontend-feature` skill (`.claude/skills/frontend-feature/`) |
| Writing hamster / orchestrator / commons Kotlin | `reference/hamster.md` |
| Reviewing a diff (self-review step or fresh-eyes reviewer) | `reference/review-rubric.md` |

## The two things that are non-negotiable in every repo

1. **Run the repo's formatter before you finish.** match Java → `mvn spotless:apply`;
   match frontend → `pnpm prettier --write <touched files>`; hamster / orchestrator /
   commons → `./gradlew spotlessApply`. CI (and hamster's pre-push hook) rejects
   unformatted code. Details + the full gate list: `reference/commands-and-gates.md`.
2. **Reuse the existing pattern before inventing one.** Find the nearest sibling
   implementation and mirror it (props, CSS classes, service-layer split, error-code
   enum) rather than hand-rolling a generic version.
