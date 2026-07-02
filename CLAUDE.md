# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workspace layout

This directory is a workspace containing **four repositories** evolved side by side — three services and one shared library:

- `match/` — Match Portal. Legacy product, but actively developed: it owns the current production data-matching, enrichment, model-scoring, CRM-integration, workflow, and reporting stack, plus two modern React UIs (`portal-admin`, `contextual-analytics`) that already replaced the old Thymeleaf portal for most flows.
- `hamster/` — Hamster / Compass. The new Kotlin platform that is taking over data ingestion, classification, and the Bronze→Silver→Gold pipelines. Hamster exposes the public REST API consumed by the new UIs and by the `compass` CLI client.
- `orchestrator/` — DAG workflow execution engine ("THE OVERLORD OF ALL JOBS"). Kotlin/Spring Boot 3.4 + gRPC service that runs cross-service DAGs (CSV upload → match → model scoring → CRM write etc.), tracks per-step status in its own `jobmeta` Postgres DB, and drives jobs in match (and other executors) via Pub/Sub. This is the "external GRPC orchestrator" that match's internal `workflow` module talks to.
- `commons-kotlin/` — Shared Kotlin library publisher. Builds Maven artifacts under `com.windfall.commons:*` (notably `event-types`, which holds the cross-service domain event contracts like `CsvUploadEventV1`, `CsvOutputCompleteEventV1`, `IntegrationJobCompletedEventV1`). Both match and hamster pull these artifacts at fixed versions — match via Maven `<version>`, hamster via `wf-commons-kotlin` in `gradle/libs.versions.toml`. Editing a shared event type requires a release here **before** match or hamster can use the new field.

`ij-code-style.xml` at the workspace root is the IntelliJ code style profile shared across all four projects — import it once per IntelliJ workspace.

`temp/` at the workspace root is the home for ad-hoc scratch files (sample CSVs, fixtures, throwaway scripts) — write to it instead of `~/Downloads` or `/tmp`.

There is no workspace-level build, lint, test, dependency graph, or git repo — the workspace root is **not** version-controlled, and each of the four subdirectories is its own independent git repository with its own branches, history, and CI. **Always operate inside one repo at a time** (`cd match`, `cd hamster`, `cd orchestrator`, or `cd commons-kotlin`); commands described below — including every `git` / branch / commit / push operation — assume you are in that subdirectory. Each repo has its own `CLAUDE.md` that is the authoritative guide for that project's commands, architecture, and conventions — read those before doing real work:

- `match/CLAUDE.md` — Maven build, frontend (`portal-admin`, `contextual-analytics`), Clean Code rules, frontend conventions (TanStack Query, Mantine, routing), Java/Spring patterns, FeatBit feature flags, Spotless formatting requirement.
- `hamster/CLAUDE.md` — Gradle multi-module build, Beam/Dataflow pipelines, BigTable + BigQuery sinks, Pub/Sub, service-layer architecture (Validating/Logging/Main), Kotest FreeSpec test layout, Resilience4j retries, Compass CLI.
- `orchestrator/CLAUDE.md` — Gradle multi-module build (`orchestrator-proto/api/core/grpc/server` + `orchestration-config-*`), YAML DAG definitions with `dags:` / `triggers:` top-level keys, JGraphT DAG model, hydration pattern, ShedLock-backed scheduled tasks, Pub/Sub topics `jobCreateRequestTopic` and `portalJobCompletedTopic`, two-PR flow for proto changes.
- `commons-kotlin/CLAUDE.md` — Library-only repo, GitVersion-driven versioning, GCP Maven artifact registry publishing, additive-only contract evolution, Java 11 / Kotlin 2.1 toolchain.

## Most-used commands per repo (quick reference)

Run from inside the named subdirectory. These are the high-frequency ones; the per-repo `CLAUDE.md` is authoritative for the rest. Formatting (`spotless`) is mandatory before commit/push in every repo — CI and (in hamster) a pre-push hook reject unformatted code.

| | match (Maven) | hamster (Gradle) | orchestrator (Gradle) | commons-kotlin (Gradle) |
|---|---|---|---|---|
| Build | `mvn -T 1C package -DskipTests` (frontend first: `make build`) | `./gradlew :server:build -x test` | `./gradlew build -x test` | `./gradlew build` |
| All tests | `mvn test` | `./gradlew test` | `./gradlew test` | `./gradlew test` |
| Single test | `mvn test -Dtest=ClassName#methodName` | `./gradlew :hamster-core:test --tests "ClassificationServiceTest"` | `./gradlew test --tests "com.windfall.orchestrator.CentralOrchestratorTest"` | `./gradlew :event-types:test` |
| Integration tests | `mvn test-compile failsafe:integration-test failsafe:verify -Pfailsafe` | (Kotest + TestContainers, Docker required) | `./gradlew test` (TestContainers) | `./gradlew test-testcontainer` |
| Format (mandatory) | `mvn spotless:apply` | `./gradlew spotlessApply` | `./gradlew spotlessApply` | `./gradlew spotlessApply` |
| Image build | `mvn ... jib:build` | `./gradlew :server:jib` | `./gradlew jib` / `jibDockerBuild` | (library — published, not imaged) |

## Why this matters when picking a repo

Roughly: anything Java/Spring 2.7/Maven/Postgres-multi-schema-with-`portal_admin_user` and any work touching `portal-admin` or `contextual-analytics` UI lives in **match**. Anything Kotlin/Spring 3.4/Gradle/Beam/BigTable/Compass-CLI lives in **hamster**. Anything about DAG definitions, `JobConfigStep` / `JobDagConfig`, the `dags:` / `triggers:` YAML, `DagRun` / `DagRunStep` tables, or routing CSV-upload / integration / ad-hoc / workflow triggers to a sequence of jobs lives in **orchestrator**. When the user asks for a change but does not name the repo, infer from these markers before searching.

When a task spans both repos (e.g. model scoring integration — staging tables produced in `hamster/pipelines/silver-to-gold` and consumed by `match/shared/.../modelscoring/`), default to making changes that minimize cross-repo coupling: hamster writes structured data to a shared bus (BigQuery, BigTable, GCS, or Pub/Sub); match reads from there. There are **no direct in-process imports between the two projects**, and there should not be — they are deployed as separate services.

## Tech-stack contrast (use to orient quickly)

| | match | hamster | orchestrator |
|---|---|---|---|
| Language | Java 11 + Kotlin 2.1 | Kotlin (JVM 21 toolchain via convention plugins) | Kotlin + Java 17 |
| Framework | Spring Boot 2.7.16 (MVC) | Spring Boot 3.4 (WebFlux + coroutines) | Spring Boot 3.4 + gRPC server |
| Build | Maven (`mvn -T 1C package`) | Gradle Kotlin DSL (`./gradlew`) | Gradle Kotlin DSL (`./gradlew`) — recently migrated from Maven |
| DB / ORM | PostgreSQL with JDBC + Flyway, multi-schema (`match`, `build`, `public`) | PostgreSQL with Exposed + Flyway | PostgreSQL (`jobmeta` DB) with JPA + Flyway |
| Storage / OLAP | GCS, BigQuery | GCS, BigQuery, BigTable | (none — metadata only) |
| Messaging | Google Pub/Sub (Spring Cloud GCP) | Google Pub/Sub (custom `event:*` modules) | Google Pub/Sub (`jobCreateRequestTopic`, `portalJobCompletedTopic`) |
| Pipelines | In-process scheduled jobs / batch services | Apache Beam Dataflow Flex Templates (`pipelines:*`) + Jobbernaut | JGraphT DAGs + ShedLock-backed scheduled tasks |
| Frontend | React 18 (modern) + React 15 / Thymeleaf (legacy `portal`) | None — API only (frontends live in `match`) | None — gRPC API consumed by other services |
| Code formatter | Spotless + Prettier for Java (`mvn spotless:apply` is mandatory) | Spotless for Kotlin (`./gradlew spotlessApply` is mandatory) | Spotless for Kotlin (`./gradlew spotlessApply`) |
| Image build | Jib via `mvn ... jib:build` | Jib via `./gradlew :server:jib` | Jib via `./gradlew jib` / `jibDockerBuild` |
| Local infra | Pub/Sub emulator + local Postgres | Docker Compose (`docker-compose -p hamster up -d`) — Postgres + BigTable emulator | Pub/Sub emulator (`localhost:2222`) + local `jobmeta` Postgres |
| Validation harness | Maven failsafe + JUnit 5 + Mockito + AssertJ | Kotest FreeSpec + MockK + Playwright e2e | Kotest + MockK + TestContainers |

## Cross-cutting product concepts

These names recur across both repos and across product specs the user will paste in. Knowing where each one lives prevents misrouting:

- **Account, dataset, candidate, classification, classification field, semantic tag** — modelled in both repos. Hamster is the system of record for the *new* classification graph and tag vocabulary; match still owns legacy account/dataset/feature-mapping tables. Migration scripts in hamster bootstrap tags from match's `feature_mapping` and `dataset_object_staging_table`.
- **Bronze / Silver / Pre-match / Gold** — pipeline layers in hamster. Match has its own pre-Compass pipeline terminology (`bigquery_sync_job`, staging tables); they are not the same artifacts and must not be conflated.
- **Model scoring** — orchestration (`BatchModelScorer`, `ModelScoreSyncService`, Postgres `model_scores`, BQ domain column tables) lives in match. The *staging table that feeds the scoring job* is being moved to hamster's `silver-to-gold` pipeline driven by `model.{id}.{classification}.{feature}` semantic tags. Score enrichment back into Gold also runs in hamster.
- **Compass / CDM** — when specs say "Compass" or "CDM accounts" they mean hamster-managed accounts. "Legacy accounts" means match-only accounts that have not yet onboarded to hamster.
- **Datalink / dataset match** — currently a match concern (`bq_all_account_matches.sql`, `data_link_enrichment` CTE). Do not assume it has a hamster equivalent unless the code shows one.
- **Workflow / Jobbernaut / Orchestrator** — match uses an internal `workflow` module that talks via gRPC to the **`orchestrator/`** service in this workspace; the orchestrator drives the DAG and emits job-creation messages on Pub/Sub that match (and other executors) consume. Hamster uses Jobbernaut (separate Windfall service) plus Beam Direct Runner for local pipeline execution. The orchestrator and Jobbernaut are different systems — commands, message types, and DAG definitions do not transfer between them.
- **Feature flags** — match uses FeatBit via OpenFeature SDK (see `match/CLAUDE.md` for the `OpenFeatureUtilities.fromAccountId(...)` pattern). Hamster has no equivalent system documented; do not introduce one without confirming.

## When the user asks for cross-repo work

Repos do not share build files, CI, or tests. A "cross-repo PR" means separate PRs that must merge in coordinated order. The two common shapes:

**Two-repo (data-bus integration):** producer publishes data to a shared bus (BigQuery, BigTable, GCS, Pub/Sub topic), consumer reads. Order: producer first, consumer second. Make the consumer-side change additive — never remove the legacy path until both have shipped and the data has been validated.

**Three-repo (shared event-type change):** the payload class lives in `commons-kotlin/event-types/` and is consumed by both match and hamster as a Maven artifact. Order: `commons-kotlin` first (PR + merge → new release version published), then match (bump dep, populate new field), then hamster (bump dep, read new field). Contract changes must be **additive only** — add nullable fields with defaults; never reorder, rename, or remove an existing field, since downstream services on older library versions will fail to deserialize.

When planning such work:

1. Identify the integration surface (event class in commons-kotlin, BigQuery table, GCS path, BigTable column family, Pub/Sub topic, REST endpoint).
2. Make the producer-side change first, behind a feature flag or new optional parameter where possible.
3. Keep the consumer-side change additive — fall back to the old field/path when the new one is absent, so a partial rollout doesn't break.
4. For shared event types, do not redefine them privately in one repo — edit them in `commons-kotlin/event-types/` and bump the dep in both consumers. The "copy don't import" rule only applies to per-integration payloads (e.g. one-off Pub/Sub messages between a single producer/consumer pair) — the events in `commons-kotlin/event-types/` are explicitly the shared schema.

## Things to read before changing code

- For any change in `match`: read `match/CLAUDE.md` Code Standards, React/Frontend, and Code Formatting sections — they are stricter than typical Spring/React projects (final everywhere, `Optional<T>` with `maybe` prefix, `mvn spotless:apply` is non-negotiable).
- For any change in `hamster`: read `hamster/CLAUDE.md` Service Layer Architecture (Validating/Logging/Main split), Testing with Kotest FreeSpec (AAA layout, named-arg style, `coEvery` formatting), Retries (Resilience4j only — no hand-rolled retry loops), and Dataflow Pipelines (the three-way alignment between `JobPayload`, `PipelineOptions`, `metadata.json`).
- For any change in `orchestrator`: read `orchestrator/CLAUDE.md` core-orchestration section (`CentralOrchestrator.kickOffDagRun` / `handleDagRunStepUpdate` / `processNextSteps`), the hydration pattern (`JobDagHydrationService` turns template `JobDagConfig` into runtime `HydratedJobDag`), and the two-PR proto-change flow before touching anything in `orchestrator-proto/`.
- For any change in `commons-kotlin`: read `commons-kotlin/CLAUDE.md` — additive-only contract evolution, GitVersion bump via commit-message (`+semver: feature|fix|breaking`), and the publish-then-bump rollout sequence into match/hamster.
- The `compass` CLI in `hamster/compass-cli/` is the supported way to talk to a running hamster server from the terminal — prefer it over hand-crafting `curl` calls when verifying behavior.
