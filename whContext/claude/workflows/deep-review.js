export const meta = {
  name: 'deep-review',
  description:
    'Adversarial find→verify review of the match working diff: dimension-specialized finders, independent skeptic verification, ranked synthesis of confirmed findings.',
  phases: [
    { title: 'Find', detail: 'one finder per review dimension over the diff' },
    { title: 'Verify', detail: 'an independent skeptic tries to refute each finding' },
  ],
}

// Review dimensions tuned to this repo's real review pain (not generic logic/perf/style).
const DIMENSIONS = [
  {
    key: 'correctness',
    focus: `Logic bugs that pass tsc/eslint but fail review. Trace the real data path:
- filter-before-cap: a cap judged on filtered length instead of the raw count (truncates silently)
- "x ?? Object.values(map)[0]" fallback used with more than one candidate (returns unrelated data)
- off-by-one, missing null/undefined guards, unhandled error/empty paths, wrong async ordering, missing useEffect deps
- a field validator skipped in a mode (hidden/overridden) that does NOT validate the effective value the submit path uses (the override) → empty value slips through and fails downstream.`,
  },
  {
    key: 'react-query',
    focus: `TanStack Query data-flow bugs:
- queryKey does not use the SAME normalized value the queryFn fetches (duplicate cache entries + requests)
- "session-cached" set with only staleTime: Infinity but default gcTime (5 min) → refetches on reopen
- query key is an inline string instead of the centralized queryKey enum
- Component calls a service/axios directly instead of Component → hook → service → API.`,
  },
  {
    key: 'styling',
    focus: `Mantine / styling conventions:
- any inline style={{}} or styles={{}} (order: Mantine style props → Box/Stack/Flex/Group → *.module.css)
- a hand-rolled UI shape (accordion/table/wizard/drawer) that an existing sibling already implements (should mirror it)
- a mode-driven wizard selector not filtered by the currently selected mode.`,
  },
  {
    key: 'backend',
    focus: `Java/Spring + Kotlin invariants:
- a null that means "should exist" handled by "if (x == null) { warn; return }" instead of a retrieveXxxOrThrow (typed CodedException + error code); or such a throw swallowed inside runCatching {}
- KDoc/JavaDoc that names tickets/stories, classes from other modules, or sibling projects; or C1 prose (must be A2)
- a public service interface (with out-of-process impls) gaining its SECOND server-internal method (should split into a separate service + Main→Validating→Logging chain + transactional resolver)
- an unchecked downcast ((X) y with no instanceof/type check) → ClassCastException with a misleading message when the runtime type differs
- a changed constructor/method signature whose callers/tests were not all updated → compile break; check callers of any changed signature, including test files that are not themselves in the diff
- ephemeral peer-image override blocks left in deploy/environments/ephemeral/*.values.yaml.`,
  },
  {
    key: 'scaffolding',
    focus: `Leftover non-production code that must not merge to master:
- dev-only mocks / fixtures / hardcoded sample data / fallback stubs on a production code path (in src/, NOT *.test.* files) added to exercise the UI or unblock local testing — a comment like "LOCAL DEV ONLY" / "not for commit" / "delete once real X works" is STRONG evidence it is real, not weak
- a catch that swallows a real failure and returns a stub, or an import.meta.env.DEV / profile / flag branch that returns fake data instead of surfacing the error
- commented-out code, debug console.* / print statements added by this change, dead code paths the diff no longer reaches
Unit-test mocks (Mockito @Mock, JFixture, MockK in *Test.* files) are legitimate — flag ONLY mocks/stubs on production code paths.`,
  },
]

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          summary: { type: 'string' },
          failure_scenario: { type: 'string' },
          fix: { type: 'string' },
        },
        required: ['file', 'severity', 'summary', 'failure_scenario', 'fix'],
      },
    },
  },
  required: ['findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    real: { type: 'boolean' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    reason: { type: 'string' },
  },
  required: ['real', 'confidence', 'reason'],
}

const finderPrompt = (d) =>
  `You review the CURRENT git working diff. The code lives in sub-repos under the workspace root (match, hamster, orchestrator, commons-kotlin); the project dir may be the workspace root or one of those repos. First find which repo has uncommitted changes: run \`git -C <path> status --porcelain\` for each candidate, then get the diff with \`git -C <path> diff\` and \`git -C <path> diff --staged\` for the one(s) that changed. Read the changed files and enough surrounding code to judge each change in context. IMPORTANT: untracked new files (lines starting \`??\` in status) do NOT appear in \`git diff\` — list them and Read each one in full, because brand-new files are where leftover scaffolding and mocks hide. And when the change is already committed on a feature branch (the working diff is empty or only part of it), review the WHOLE PR: detect the base (master or main) and diff \`git -C <repo> diff origin/<base>...HEAD\` — the committed code is most of the PR and is fully in scope.

Focus ONLY on the "${d.key}" dimension:
${d.focus}

Report ONLY real issues in the changed lines. If there are none, return an empty findings array — do not pad. For each finding give file, line, severity, a one-sentence summary, a concrete failure_scenario (inputs/state → wrong output or CI failure), and the fix.`

const verifyPrompt = (f, dimKey) =>
  `A "${dimKey}" reviewer of the match working diff claims this finding. Your job is to REFUTE it, not agree.

Finding: ${f.summary}
File/line: ${f.file}:${f.line ?? '?'}
Claimed failure: ${f.failure_scenario}
Proposed fix: ${f.fix}

Read the actual code at that location and its context. The file path is repo-relative to one of the sub-repos (match, hamster, orchestrator, commons-kotlin) under the workspace root — find and Read it, and check the surrounding diff with \`git -C <repo> diff\`. Decide: is this a REAL defect that causes wrong behavior, or a convention this team definitely rejects — or is it a false positive (valid pattern, already handled nearby, premature nitpick, out of scope of the diff)? Default real=false when uncertain. Give confidence and a one-line reason.`

phase('Find')
const perDimension = await pipeline(
  DIMENSIONS,
  (d) =>
    agent(finderPrompt(d), {
      label: `find:${d.key}`,
      phase: 'Find',
      schema: FINDINGS_SCHEMA,
      agentType: 'code-reviewer',
    }),
  (review, d) =>
    parallel(
      (review?.findings ?? []).map((f) => () =>
        agent(verifyPrompt(f, d.key), {
          label: `verify:${d.key}:${(f.file || '').split('/').pop()}`,
          phase: 'Verify',
          schema: VERDICT_SCHEMA,
        }).then((v) => ({ ...f, dimension: d.key, verdict: v }))
      )
    )
)

const rank = { high: 0, medium: 1, low: 2 }
const all = perDimension.flat().filter(Boolean)
const confirmed = all
  .filter((f) => f.verdict && f.verdict.real && f.verdict.confidence !== 'low')
  .sort((a, b) => (rank[a.severity] ?? 3) - (rank[b.severity] ?? 3))
const dropped = all.filter((f) => !(f.verdict && f.verdict.real && f.verdict.confidence !== 'low'))

log(
  `Found ${all.length} candidate(s) across ${DIMENSIONS.length} dimensions; ${confirmed.length} confirmed after verification, ${dropped.length} dropped.`
)

return {
  confirmed,
  dropped: dropped.map((f) => ({ file: f.file, summary: f.summary, reason: f.verdict?.reason })),
  counts: { candidates: all.length, confirmed: confirmed.length, dropped: dropped.length },
}
