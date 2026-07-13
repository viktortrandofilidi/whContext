---
name: deep-review
description: >-
  Deep, high-signal code review of the current match working diff using an
  adversarial find→verify multi-agent workflow. Use before opening an important
  PR, or when the user asks for a thorough / deep / careful review or wants to be
  sure a change is right. Heavier than the single-pass self-review — it fans out
  dimension-specialized finders and verifies every finding, so it costs more
  tokens; run it when depth matters. Invoke as /deep-review.
---

# Deep review (adversarial find → verify)

Use this when a plain `self-review` isn't enough — an important PR, a risky change,
or an explicit request for a thorough review. It runs many agents, so it is more
expensive than `self-review`; prefer `self-review` for everyday changes.

## What to do

Run the `deep-review` workflow with the Workflow tool:

- `Workflow({ name: "deep-review" })`
- If the name does not resolve, use `Workflow({ scriptPath: ".claude/workflows/deep-review.js" })`.

The workflow:
1. **Find** — one finder per review dimension (correctness, react-query, styling,
   backend invariants) reads the working diff and reports candidate findings.
2. **Verify** — an independent skeptic tries to refute each candidate; anything not
   confirmed (or low-confidence) is dropped. This is what keeps signal high and
   nitpicks low.
3. Returns `{ confirmed, dropped, counts }` — confirmed findings ranked most-severe first.

## After it returns

- Present the confirmed findings (file:line, severity, failure scenario, fix), most
  severe first. Fix the CONFIRMED correctness findings; apply convention findings.
- Mention the `dropped` count so the user sees what was considered and refuted.
- For anything you disagree with, say why — don't silently drop it.
- Re-run the fast gates (`pnpm ci:format && pnpm ci:lint && pnpm checkts`) if you
  changed code, then hand off.
