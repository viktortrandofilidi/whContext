# match backend canon (Java 11 / Kotlin 2.1, Spring Boot 2.7)

Clean Code is enforced in review. Write it right the first time.

## Functions & structure

- Small, single-responsibility, one level of abstraction. Prefer extracting a
  well-named private method over a long function — but a cohesive 30-line function
  beats 5 fragmented ones.
- **Few arguments** (0–2 ideal, 3 max for business logic). Constructor injection with
  many deps is fine for Spring services. **No boolean flag arguments** — they mean the
  function does more than one thing.
- **Guard clauses** for edge cases early; reduce nesting.
- **`final` on every local variable and parameter that is not reassigned.** This is a
  house rule, not optional.

## Naming

- Intent-revealing, no abbreviations (`remainingAttempts`, not `r`). Classes = nouns,
  methods = verbs. DAO methods: `find*`, `create*`, `update*`, `delete*`, `is*`.

## Null & error handling

- **`Optional<T>`** for maybe-absent results (especially DAO lookups); prefix the
  variable with `maybe` (`maybeConnectionInfo`). Never return `null` where `Optional`
  fits.
- **Required-lookup-or-throw.** A null that means "should exist" is a fail-fast via a
  `retrieveXxxOrThrow` (typed exception + error code), NOT
  `if (x == null) { warn; return }`. Watch for a throw swallowed by a `runCatching`/
  best-effort wrapper.
- Prefer **exceptions over error codes**. Author custom exception types
  (`InvalidFileNameLengthException`) and handle them in a `@RestControllerAdvice` /
  `@ExceptionHandler` at the controller layer — not inline try-catch.
- Annotate `@Nullable` / `@Nonnull` on interface and public-method params. Don't pass
  `null` to a param that isn't `@Nullable`.

## Comments & docs

- Self-documenting code first. If you comment, say **why**, not **what**. Don't write
  one-off comments that restate a name — rename instead.
- Delete commented-out code. Bare `TODO`s are not allowed — every TODO carries a JIRA
  ticket: `// TODO [ECS-1234] ...`.
- **Document every interface + its methods** with JavaDoc/KDoc: contract and params,
  not implementation.
- Doc hygiene: **A2-level English** (short sentences, common words, active voice,
  present tense, no hedges). **No ticket/story/roadmap refs** ("Story 5", "ENG-1234",
  "downstream phase") in source docs — that's for the PR description. **No names of
  classes from other modules or sibling projects** (`XService`, "hamster") — describe
  behavior in self-contained terms.
- Don't delete existing `console.log/warn/error` (or their Java equivalents) while
  making unrelated changes — they're intentional aids.

## Imports

- Use imports, not fully-qualified names. Kotlin: meaningful import aliases if needed.

## Spring / platform specifics

- **Feature flags = FeatBit via OpenFeature.** Inject `OpenFeatureAPI`, call
  `getBooleanValue("kebab-case-flag", false, ...)`, always default `false`. Context:
  `OpenFeatureUtilities.fromAccountId(accountId)` (per-account, most common),
  `.fromUser(user, account)`, or `.serviceAccount()`. Low-level modules that `shared`
  depends on (e.g. `google-apis`) can't inject `OpenFeatureAPI` — take the evaluated
  boolean as a method param from a higher-level caller.
- **JDBC + `Instant`:** convert to `java.sql.Timestamp` via `Timestamp.from(instant)`
  before binding to `NamedParameterJdbcTemplate` / `SimpleJdbcInsert`, or you get
  `PSQLException: Can't infer the SQL type`.
- Integration tests live in `src/integration-test/`, classes end `*IT.java`.

## Growth signal — split before it sprawls

A public service interface (with out-of-process impls) gaining its **second**
server-internal method → extract a separate service + its own decorator chain + a
transactional resolver. Don't keep adding internal stubs to the public interface.

## Before finishing

`mvn spotless:apply` (mandatory) + frontend gates if you touched React
(`reference/commands-and-gates.md`), then self-review (`reference/review-rubric.md`).
