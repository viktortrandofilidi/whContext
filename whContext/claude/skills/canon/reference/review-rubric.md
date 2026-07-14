# Review rubric (shared)

The one rubric used by both the builder agents' self-review step and the fresh-eyes
`code-reviewer`. Walk only the sections for what changed. Trace the real data path —
don't pattern-match. Clean tsc/eslint/prettier/spotless is NOT enough; the surviving
bugs are logic bugs. Report correctness before conventions.

## Frontend — match (portal-admin / contextual-analytics)

- **Inline styles.** Any `style={{}}` / `styles={{}}` → finding, with the replacement.
  Order: Mantine style props → `Box/Stack/Flex/Group` → co-located `*.module.css`.
- **Reuse over generic.** A hand-rolled UI shape (accordion/table/wizard/drawer) that a
  sibling already implements → name the sibling to mirror (props + CSS classes).
- **Filter-before-cap.** A cap judged on filtered length instead of the raw count →
  silent truncation. The cap must be judged on the raw count *before* filtering.
- **Query-key ↔ queryFn normalization.** Key not using the same normalized value the
  service fetches → duplicate cache entries + requests.
- **gcTime vs staleTime.** "Session-cached" with only `staleTime: Infinity` (default
  `gcTime` is 5 min → GC'd on unmount, refetches on reopen). Comment must match config.
- **`x ?? Object.values(map)[0]`** fallback with more than one candidate → returns
  unrelated data. Guard: exact key → normalized-key → "first" only when one entry.
- **Mode-scoped pickers.** A wizard selector not filtered by the current mode.
- **Validate the effective value.** When a field's validator is skipped in a mode
  (hidden / overridden), it must validate the value the **submit path actually uses**
  (the override) — not skip validation — or an empty override slips through and fails
  downstream on a hidden field.
- **Stable keys from stable identity.** Derive a persisted key/id from the immutable
  identifier (an API name), never a renamable display label — or a rename changes the
  key, breaks the "already exists" check, and creates duplicates on the next open.
- **Backend-contract type fidelity.** When an endpoint's response shape narrows (e.g. a
  list endpoint now returns a summary DTO *without* a field the full type has), the FE
  type AND every consumer of that path (hook return type, component props/state/callbacks,
  imports) must be the narrower type — mirror the backend split (`Summary` +
  `Full = Summary & { extra }`). Leaving the wider type "because it's runtime-harmless"
  lets consumers assume the missing field is present → real contract mismatch, flagged
  High. Keep the detail path on the full type; only the list path narrows.
- **Query keys** inline instead of the centralized enum; redundant `as XNode` cast
  after a type guard (a `--max-warnings 0` failure) + its now-unused type import.

## Backend — match (Java/Spring, Kotlin)

- **Required-lookup-or-throw.** A null meaning "should exist" handled by
  `if (x == null) { warn; return }` instead of `retrieveXxxOrThrow` (typed
  `CodedException`/custom exception + error code). Watch for a throw swallowed by a
  `runCatching {}` / best-effort wrapper.
- **`final` missing** on a local/param that is never reassigned; **boolean flag
  argument** on a business method; **>3 args** on business logic.
- **`Optional` misuse** — returning `null` where `Optional` fits, or a `maybe`-less
  Optional variable.
- **Doc hygiene** (KDoc/JavaDoc/JSDoc): ticket/story/roadmap refs; names of classes
  from other modules or sibling projects; a doc naming a specific provider or
  implementation ("Salesforce", "Compass") for code that is now generic
  (provider-agnostic) = drift, describe the generic behavior; C1 prose where A2 is
  required; a bare `TODO` without a JIRA ticket.
- **JDBC `Instant`** bound without `Timestamp.from(...)`.
- **Unchecked downcast.** A `(X) y` cast with no `instanceof` / type check →
  `ClassCastException` with a misleading message when the runtime type differs; check
  the type and throw a clear exception first.
- **Signature change breaks a call site.** A changed constructor/method signature whose
  callers weren't all updated — **especially a test the diff doesn't even touch** → the
  module stops compiling. Formatters/linters never catch this; only a compile does.
- **Behavior parity across implementations.** A new implementation of a shared interface
  (e.g. a second CRM/provider) must match the observable behavior of the existing one —
  sort order, null handling, casing — or the same UI behaves differently per account.
- **Unimplemented strategy branch hard-fails the endpoint.** A service that dispatches to
  a strategy/provider where one branch isn't built yet (throws
  `UnsupportedOperationException` / similar) will 500 the whole user-facing endpoint for
  that type. Give a graceful fallback (degrade to a related result — e.g. already-connected
  objects — or empty) or have the caller handle it; an unimplemented provider must not
  break the endpoint for that CRM/type.
- **Exception thrown inside an `Optional.map` / stream.** A method reference in `.map(...)`
  that can throw (e.g. an `asX()` that throws for the wrong subtype) fires *before* any
  later `instanceof` / guard — validate the source's type/shape before transforming it.
- **Internal-only method growth** — a public service interface (out-of-process impls)
  gaining its *second* server-internal method → split into a separate service +
  `Main→Validating→Logging` chain + transactional resolver, not more stubs.

## Backend — hamster / orchestrator / commons (Kotlin)

- **Service-layer leak.** Validation in the Main layer, business logic in a controller,
  or logging concerns outside the Logging decorator. Controllers must be thin
  pass-throughs.
- **Exception not extending `CodedException`** (or a subclass), or missing its
  `XxxErrorCode` enum entry / a publicKey that doesn't match the enum name / no domain
  prefix.
- **Top-level list** in a REST request or response (must be wrapped in an object).
- **Hand-rolled retry** instead of Resilience4j; a retry keyed on a message substring
  instead of an exception type; a retry buried inside the target function instead of at
  the call site.
- **File layout** — more than one top-level declaration in a `.kt` file (interface
  bundled with its DTOs/exceptions).
- **Temporary / current-state comment** ("for now…", "until Y…"); a section comment in
  a controller; a comment on a private function that a rename would remove.
- **Dataflow drift** — a business param in `PipelineOptions`/`metadata.json` absent
  from the Payload; a write destination inferred/computed instead of passed as its own
  payload param.
- **Kotest** — a test name missing the expected behavior; AAA blocks not blank-line
  separated; `coEvery`/named-arg formatting off (spotless won't catch these).

## Production readiness — no leftover scaffolding

The change is going to master; dev-only scaffolding must not ride along.

- **Dev-only mocks / fixtures / hardcoded sample data / fallback stubs** on a
  production code path (in `src/`, **not** a `*.test.*` file) → finding: remove it. A
  comment like `LOCAL DEV ONLY`, `not for commit`, or `delete once real X works` is
  strong evidence it is real, not weak — the real path being live is the trigger to
  delete. Unit-test mocks (Mockito `@Mock`, JFixture, MockK in `*Test.*`) are fine.
- **A `catch` that swallows a real failure and returns a stub**, or an
  `import.meta.env.DEV` / profile / flag branch that returns fake data → finding.
  Production behavior must surface the error (e.g. TanStack Query `isError`).
- **Commented-out code; debug `console.*` / `print` added by this change; dead code
  paths** the diff no longer reaches.
- **Look in NEW/untracked files.** They don't appear in `git diff` — that is exactly
  where mocks and scaffolding hide. List (`git status --porcelain`, `??` entries) and
  read them.
- If it is genuinely unclear whether a fallback is meant to ship (a documented,
  flagged path), **flag it and ask — don't silently keep or delete.**

## Cross-cutting

- **Ephemeral peer overrides** left in `deploy/environments/ephemeral/*.values.yaml`.
- Any suggested PR/commit/Slack text must not use `>` blockquotes (plain paragraphs +
  fenced code blocks); copyable snippets are not blockquoted.

## Verify before reporting

For every candidate, try to **refute** it: is this a real defect that produces wrong
behavior / a CI failure, or a definite convention the team enforces — or is it a valid
pattern, a premature nitpick, or already handled nearby? Re-read the exact code. Drop
anything you can't confirm. Default to dropping when uncertain — false positives waste
time as much as misses.
