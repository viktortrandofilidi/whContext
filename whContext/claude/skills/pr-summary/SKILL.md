---
name: pr-summary
description: >-
  Generate a concise, business-value PR summary from the diff between the current
  feature branch and its base (master/main). Accurate and laconic — what the change
  delivers and why it matters, in business terms. No code details: no file lists,
  function/class names, or implementation notes. Use when opening a PR or when the
  user asks for a PR summary / description. Invoke as /pr-summary.
---

# PR summary (business value, laconic)

Produce the description a reviewer or PM reads first: **what this branch delivers and
why it matters — not how it is built.** Ground every line in the actual branch↔base
diff; never invent value.

## 1. Establish the branch and its base

Workspace-aware: the branch lives in one of the sub-repos (match / hamster /
orchestrator / commons-kotlin), or the project dir may be that repo. Work inside the
repo that holds the feature branch.

Find the base branch — repos differ between `master` and `main`, so detect it:

```
cd <repo>
# preferred: the remote's default branch
git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's#refs/remotes/origin/##'
# fallback: whichever resolves
git rev-parse --verify --quiet origin/master || git rev-parse --verify --quiet origin/main
```

Diff the branch against the merge base — **three-dot** (`...`), which is the PR's real
changes and excludes whatever landed on the base since you branched (and cleanly
handles branches that merged the base back in):

```
BASE=origin/master        # or origin/main
git log --oneline "$BASE...HEAD"    # the story of the branch
git diff --stat "$BASE...HEAD"      # scope
git diff "$BASE...HEAD"             # read enough to understand INTENT
```

**Stale-base guard:** if the diff is full of clearly unrelated features (other tickets,
other domains), the local base ref is stale — the summary would wrongly claim other
people's merged work. Say so and suggest `git fetch origin` first; re-run against the
fresh `origin/<base>`.

## 2. Read for intent, not mechanics — efficiently

Answer one question: **what can a user/customer now do, or what problem is fixed, that
they could not before?** Translate technical changes into outcomes.

- Lead with `git log` (commit messages tell the story) and `--stat` for shape; read
  only the files you need to confirm the business intent — don't read every line of a
  large diff.
- Take the ticket key from the branch name (e.g. `COM-572`) for the title. Don't call
  Jira.
- A refactor / cleanup / test-only change with no user-facing effect → say so plainly
  and briefly ("Internal refactor, no behavior change"). Never manufacture value.
- If the branch does several unrelated things, name each outcome once — still laconic.

## 3. Write it — laconic, business value, English

The summary is a PR artifact → **write it in English** (even when we are chatting in
another language). Output a copyable fenced markdown block; no `>` blockquotes.

Shape — a title + 1–2 sentences + at most ~4 bullets:

```markdown
## <TICKET>: <one-line outcome>

<1–2 sentences: what this delivers and why it matters, in business terms.>

- <user/business-level change>
- <user/business-level change>
```

Rules:
- **No code details** — no file names, function/class names, library/framework names,
  or "refactored X into Y". If a reviewer would need the diff to verify a line, it is
  too low-level for this summary.
- **Accurate** — every claim traceable to the diff; no aspirational scope.
- **Laconic** — cut every word that carries no business meaning. Three tight bullets
  beat eight loose ones.
- If a real decision is open for the reviewer/PM (a behavior choice, a flag default),
  add one short `**Note:**` line — still no code.

## 4. Hand off

Present the block for the user to paste into the PR. Offer to adjust length or
emphasis. Don't open or push the PR unless asked.
