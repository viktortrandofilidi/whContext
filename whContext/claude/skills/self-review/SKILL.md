---
name: self-review
description: >-
  Pre-handoff self-review of a match change. Use after finishing an edit and
  before saying "done", opening a PR, committing, or pushing — it catches the
  correctness bugs and convention issues Copilot flags, so they're fixed first.
  Runs the automated gates and spawns the repo-tuned code-reviewer subagent over
  the working diff. Invoke as /self-review. For a deeper, multi-agent review use
  the deep-review skill instead.
---

# Self-review before handoff

Goal: land the review comments yourself before Copilot or a human does. Do this
whenever you've changed code and are about to hand it back or push. This is the
everyday, single-pass review; for an important PR use the `deep-review` skill.

## 1. Run the automated gates (only what changed)

Frontend (`match/portal-admin/frontend`) — whole-tree, the same commands CI runs:

```
pnpm ci:format && pnpm ci:lint && pnpm checkts
```

Java — mandatory formatter (CI rejects unformatted code):

```
mvn spotless:apply
```

Fix everything red here first. A whole-tree `pnpm ci:lint` failure surfaces as a red
**build-jars / build-docker** check, not an obvious frontend one.

**If the change affects layout/visuals** (scroll, overflow, sizing, spacing, a new modal/table),
green gates are not enough — `tsc`/`eslint` don't render. Attach to the running app via the preview
tool (`.claude/launch.json` → `portal-admin` / `contextual-analytics`), reproduce the screen, and
read the **computed styles / DOM** to confirm it actually looks/behaves right. Don't iterate on CSS
math blind and don't hand it back on gates alone.

## 2. Spawn the code-reviewer subagent over the diff

Launch the `code-reviewer` agent (Agent tool, `subagent_type: "code-reviewer"`). It
has its own context, so it reviews with fresh eyes and doesn't bloat this one. Give it:

- One line of intent: what the change is meant to do.
- Scope: for a pre-PR / pre-push review, the **whole branch** —
  `git diff origin/<base>...HEAD` (base = master or main), which includes
  already-committed code — not just the working diff (`git diff` + `git diff --staged`).
  Most of a PR is committed; reviewing only the working diff misses it (and lets Copilot
  find what you didn't).

It returns a structured JSON block of confirmed findings (it verifies its own
findings before reporting), ranked most-severe first, plus a short prose summary.

## 3. Triage and fix

- Fix every CONFIRMED correctness finding.
- Apply convention findings (inline styles, query-key/gcTime, reuse-existing-pattern,
  KDoc hygiene, `retrieveXxxOrThrow`, ephemeral overrides).
- For anything you disagree with, say why in your summary — don't silently drop it.

## 4. Re-run gates if you changed code, then report

Report: what the reviewer found, what you fixed, what you deliberately left and why.
Only now is the change ready to hand off.
