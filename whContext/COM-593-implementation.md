# COM-593 — Phase 2 (async Pub/Sub) IMPLEMENTATION (current state)

Supersedes the "Phase 2 (async)" plan in `COM-593-analysis.md`. Phase 1 (sync `/csv-files/{id}/fulfilled-states`
API) is merged to match `master` (#5586) and inherited into the phase-2 match branch. Nothing committed — Viktor
commits each repo himself. Code does NOT build yet — blocked on commons release + version bump (see bottom).

## Branches (3 repos)
- commons-kotlin: `viktor/COM-593/document-updated-event-type`
- hamster:        `viktor/COM-593/pubsub-document-updated-topic`
- match:          `viktor/COM-593/pubsub-document-updated-sub-match`

## Mechanism (as built)
Compass finalizes a mapping → emits `document-updated` → match consumes → `addFulfilledState(matchId, MAPPED)`.
It is the async twin of the sync API: both do the SAME idempotent `addFulfilledState` at finalize, so whichever
lands first wins, the other is a no-op. Sync = fast UI; event = durable fallback (survives browser death / lost sync call).

Key facts that shaped the design:
- Compass `finalizeMapping` is **dataset-level** (`DocumentMapping` is per accountId+datasetId; file↔dataset link is
  `CsvFileIntrospection.datasetId`). It does not know the CSV file by itself.
- The mapping wizard is per-file (routes `/csv/$fileId/premapping|mapping|submit/$mappingId`). "MAPPED" happens at the
  **submit/finalize** step (same as legacy `setMappingsApproved`), NOT at the earlier per-file premap processing
  (premap = assign-dataset + introspect + convert-to-jsonl).
- So to emit a **per-file** event from a dataset-level finalize, the wizard threads the specific `csvFileId` into the
  finalize call. (We deliberately kept this over a dataset fan-out, to mark exactly the one file being mapped.)
- hamster does NOT hold a "MAPPED" file state (its `CsvFileState` is conversion-only). The MAPPED fulfilled-state lives
  in match. hamster's role = "mapping finalized"; match's role = "file MAPPED (workflow gate)".

## Event payload (commons-kotlin)
`event-types/.../event/hamster/DocumentUpdatedEventV1.kt` — 5 flat fields, no enum/discriminator:
```
csvFileId: UUID          // Compass id (trace)
csvFileMatchId: Long     // match csv_file_upload id — the key match writes by
accountId: String
fulfilledStates: List<String>   // states to add, e.g. ["MAPPED"] — mirrors the sync API's `states`
updatedAt: Instant
```
Design settled here after iterating: earlier drafts had `changeType`+`enum DocumentChangeType`+`changeTypeAsEnum()`
(threw on unknown → contradicted forward-compat) + nullable mapping fields + a `changes: Map` — all dropped as unused
bloat. Chosen principle: **symmetry with the sync `/fulfilled-states` API** (same {file id + states}).
OPEN NUANCE (not actioned): the payload carries match's fulfilled-state vocabulary ("MAPPED"), so commons/Compass
"speak" a match concept. Accepted because this is a point-to-point Compass→match status channel. If it ever bothers a
reviewer, the alternative is a Compass-owned `changeType` that match translates — not done.

## hamster changes (producer)
- `hamster-api/.../mapping/api/main/DocumentMappingService.kt` — `finalizeMapping(..., csvFileId: UUID? = null)`.
- `hamster-core/.../mapping/core/main/{Main,Validating,Logging}DocumentMappingService.kt` — propagate the param.
- `compass-client/.../HttpDocumentMappingService.kt` — sends `csvFileId` as `FinalizeMappingRequest` body when set.
- `hamster-api/.../mapping/api/main/model/request/FinalizeMappingRequest.kt` (NEW) — `{ csvFileId }`.
- `hamster-rest-controller/.../mapping/rest/DocumentMappingController.kt` — finalize takes optional body, passes csvFileId.
- `hamster-core/.../mapping/core/main/EventingDocumentMappingService.kt` (NEW) — decorator; on finalize with csvFileId,
  resolves `CsvFile` (→ csvFileMatchId/accountId), publishes `document-updated` with `fulfilledStates=["MAPPED"]`
  (const `MAPPED_FULFILLED_STATE`). Best-effort (emit failure doesn't fail finalize). null csvFileId (migration/CLI) → no event.
- `server/.../service/DocumentMappingServiceConfig.kt` — wires decorator into the chain, gated on
  `pubsub.events.document-updated.enabled`; injects EventPublisher + CsvIngestionService + PubSubProperties.
- `server/.../events/HamsterDocumentUpdatedTopicConfig.kt` (NEW) + `server/.../application.yaml` — topic
  `hamster_document_updated` (publish-only), auto-created.
- Test: `hamster-core/.../EventingDocumentMappingServiceTest.kt` (emit w/ csvFileId; no emit if null; no emit if CsvFile absent).
- PENDING: bump `wf-commons-kotlin` in `gradle/libs.versions.toml` (currently 0.46.0).

## match changes (consumer + frontend)
- `portal-admin/.../config/application.properties` — `pubsub.domain-events.events.document-updated.*`: subscription
  `document-updated-sub-match` on topic `hamster_document_updated`.
- `portal-admin/.../pubsub/DocumentUpdatedSubscription.java` (NEW) — @Configuration, provisions sub + `ProjectSubscriptionName` bean
  (model: workflow `DagStepCompletedSubscription`).
- `portal-admin/.../pubsub/DocumentUpdatedSubscriberService.java` (NEW) — `AbstractCloudEventListener<DocumentUpdatedEventV1>`;
  loops `fulfilledStates`, validates each via `CsvFulfilledState.valueOf` (skips+logs unknown → forward-compat), `addFulfilledState`.
- Frontend `portal-admin/frontend/.../hooks/useDocumentMapping.ts` — finalize sends `csvFileId` (Compass UUID) to Compass so the
  event fires; keeps the phase-1 sync path (`addCsvFulfilledStates(csvFileMatchId, ['MAPPED'])` in onSuccess, from master merge).
- Frontend `.../components/CsvMappingWizardModalSubmit.tsx` — passes both `csvFile?.csvFileMatchId` (sync) and `csvFileUuid` (async).
- Test: `portal-admin/.../pubsub/DocumentUpdatedSubscriberServiceTest.java` (MAPPED added; unknown state ignored).
- PENDING: bump `wf-commons-kotlin.version` in `pom.xml` (currently 0.45.0).
- Note: match had no modern CloudEvent subscriber before; `AbstractCloudEventListener`/`PubSubProperties`/`PubSubInfrastructureProvisioner`
  come transitively from `shared`. Cross-service topic namespace alignment is env-config (same as existing `match-csv-file-events`).

## Blocker + rollout (strict order)
commons-kotlin versioning is **GitVersion by commit-message** (`+semver: feature|fix|breaking`); adding a class = additive = `feature`.
1. Merge commons-kotlin branch → CI publishes a new `com.windfall.commons:event-types` version (or use the PR snapshot for local test).
2. Bump `wf-commons-kotlin` → new version in match `pom.xml` AND hamster `gradle/libs.versions.toml`.
3. Then per-repo: `mvn spotless:apply` + `pnpm prettier --write` (match), `./gradlew spotlessApply` (hamster/commons); build; run the new tests.
Until step 2, match/hamster don't compile (0.45.0/0.46.0 lack `DocumentUpdatedEventV1`).
