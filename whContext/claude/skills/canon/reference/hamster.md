# hamster / orchestrator / commons Kotlin canon (Spring Boot 3.4)

hamster is the reference; orchestrator and commons-kotlin share the Kotlin style and
the `spotlessApply` gate. Repo-specific extras: orchestrator DAG/proto rules and
commons additive-only contracts live in their own `CLAUDE.md`.

## Service layer — the Validating / Logging / Main split

Every service is a three-decorator chain. Keep the concerns separate:

- **`ValidatingXxxService`** — all business validation (existence, active status,
  format). One-liner validators named `...OrThrow`: `ensureDatasetExistsOrThrow(id)`.
- **`LoggingXxxService`** — `runCatching` / `onSuccess` / `onFailure` for structured
  logging. Always include `accountId`; set it in MDC via
  `withLoggingContext(LogContextKey.ACCOUNT_ID.name to accountId) { ... }`.
- **`MainXxxService`** — pure business logic, no validation. Resolve identifiers to
  entities **once** at the entry point; after that use `retrieveXxxOrThrow` for
  internal lookups and `!!` where the validating layer already guaranteed non-null.

**Growth signal:** when a public service interface (with out-of-process impls) gains
its **second** server-internal method → extract a new `ClassificationFieldService`-style
service with its own Main→Validating→Logging chain + a transactional resolver. Do not
add more internal stubs to the public interface, and do not reach for inheritance.

Put `retrieveActiveXxxOrThrow` extension functions in the service interface file for
discovery.

## Exceptions & error codes

- **Every exception you author extends `CodedException`** (or a subclass:
  `AuthorizationException`, `BadRequestException`, `ConflictException`,
  `NotFoundException`, `DataReadException`, `DataWriteException`, `InvalidDataException`,
  `AuthenticationException`). Never extend `RuntimeException`/`Exception` directly.
- Pair each with an entry in a domain `XxxErrorCode` enum implementing `ErrorCode`, so
  `RestExceptionHandler` propagates the public key to clients.
- **Enum name must equal the publicKey**: `KNOWN_TAG_UNKNOWN_LABEL_KEY("KNOWN_TAG_UNKNOWN_LABEL_KEY", ...)`.
  Prefix the key with the domain (`KNOWN_TAG_`, `DATASET_`).

## File layout

- **One top-level declaration per file** — each interface, class, data class, enum,
  sealed hierarchy, exception in its own `.kt` named after it. Don't bundle an
  interface with the data classes it returns or the exceptions it throws. A `toDb` /
  `toDomain` helper for a single entity may live in that entity's file.

## REST controllers

- **Thin pass-throughs** — no business logic, filtering, or transformation. HTTP
  concerns only (parsing, mapping, error translation); logic goes to the service layer,
  data filtering to the repo layer.
- Reactive WebFlux: return `Mono<T>` / `Flux<T>`. DTOs in `hamster-rest-model`.
- **Never return a top-level list** — wrap in an object: `{ "categories": [...] }`,
  not `[...]`.

## Retries — Resilience4j only

- No hand-rolled retry loops or `retryOn`-style helpers. Use `libs.resilience4j.retry`
  / `libs.resilience4j.kotlin`.
- Keep the target function straight-line (throws on failure); wrap the retry at the
  **call site**, not inside the function.
- **Key on exception types**, not message substrings (`retryExceptions(IOException::class.java)`,
  never `e.message?.contains("timeout")`).
- Exponential backoff for network retries; register an `onRetry` listener that logs
  attempt + exception type + wait interval.
- Build in a private `buildXxxRetry(): Retry`, store as a field, invoke with
  `retry.executeFunction { ... }`. Canonical: `WaspProcessorJob.buildPostBatchRetry`.

## Comments

- Very sparse — self-documenting code. Never comment private functions unless a
  genuinely complex algorithm needs it. No section comments in controllers
  (`// ===== CRUD =====`). **No temporary / current-state comments** ("for now…",
  "until Y is fixed", "kept non-blocking so…") — those belong in the PR description.
  Keep a comment only for durable knowledge (a non-obvious invariant, an upstream-bug
  workaround, a hidden constraint).
- Avoid fully-qualified imports; if unavoidable, comment why.

## Dataflow pipelines

- Three aligned parameter sources, **Payload is the lead**: `JobPayload.kt` (business
  source of truth) → `PipelineOptions` (extends `BasePipelineOptions`) → `metadata.json`
  (Flex Template). Every business param in Options/metadata must exist in the Payload.
- **Explicit write destinations**: every artifact written (BigQuery/BigTable table, GCS
  path) is its own dedicated payload param — never inferred from another field, parsed
  from a config blob, or computed inside the pipeline.
- Infra-only fields (`templateMetadata`, `bigQueryGcsTempLocation`) live in
  Options/metadata but not the Payload. All pipelines error-sink to BigTable
  (`errorSink*`).

## Testing — Kotest FreeSpec, AAA

- **Nested structure:** first level = function under test (`"fetchDatasets"`), second =
  the case **with the expected behavior in the name** (`"returns dataset when key
  exists"`, not just `"key exists"`). Exception: "roundtrip" mapping tests.
- **AAA with blank lines** for multi-step tests (Arrange / Act / Assert separated by
  blank lines); one-liner validation tests stay on one line.
- **MockK `coEvery` formatting:** `coEvery {` on its own line, `} returns value` on its
  own line.
- **Named arguments** when a call has 3+ params, each on its own line.

## Before finishing

`./gradlew spotlessApply` (mandatory — pre-push hook rejects unformatted code; needs a
JDK 21 launcher). Don't run `:server:build` / full `test` / Dataflow deploys unless
asked. Then self-review (`reference/review-rubric.md`).
