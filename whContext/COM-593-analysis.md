# COM-593 — COMPASS-mode CSV mapping never sets MAPPED (analysis + plan)

Bug, Highest, assignee Viktor, epic ENG-5504 (Orchestrator-Driven Portal-Admin CSV Workflows).
Investigated via a code-verified workflow (match + hamster). commons-kotlin & orchestrator are NOT checked out
in this workspace, so anything about the shared event contract is UNVERIFIED here.

## Root cause (verified in code — hypothesis in ticket is inverted)
MAPPED is written **unconditionally** in the legacy path; there is no `DataProcessingMode` branch anywhere in the CSV flow.
- `match/shared/.../db/dao/CsvFileUploadDao.java:1172` `setMappingsApproved()` appends `CsvFulfilledState.MAPPED` via
  `array_agg(DISTINCT ... array_append(...))` — idempotent, no mode check.
- `CsvFileUploadDao.java:1146` `setAutomaticallyMappedAt()` same (auto-map).
- `match/shared/.../portal/csv/CsvUploadServiceImpl.java:591` calls it (setApproved=true); `Account` loaded at 497-499 but
  `getDataProcessingMode()` never read. `DataProcessingMode.COMPASS_PROCESSING_MODES` exists, unused in CSV flow.
So the real bug: in COMPASS the mapping is finalized in **Compass (hamster)** via the frontend hook
`match/portal-admin/frontend/src/domain/accounts/hooks/useDocumentMapping.ts:14` → `POST /compass/proxy/document-mappings/{id}:finalize`
(proxied by `CompassProxyController.java:54/81`). That path never calls match's `setCsvFileMappings()`, so MAPPED is never written.
Workflow gate reads it: `match/portal-admin/.../CsvFileWorkflowsService.java:299` `isEligible()` (kickoff at :138, no filtering).

## Chosen Solution (from ticket diagram — this overrides the workflow's "async-primary" recommendation)
Both paths ship in COM-593; SSE is explicitly LATER (out of scope):
- **Primary (now): synchronous two-frontend-call.** Frontend, after the 200 from Compass finalize, makes a 2nd call to a
  NEW match portal-admin backend endpoint that upserts `csv.states += "MAPPED"`.
- **Fallback (async): PubSub.** hamster emits a `document-updated` event on mapping received/updated; match subscribes
  (`document-updated-sub-match`) and upserts the same MAPPED via `CsvFileUploadDao`.
- Both funnel into the same MAPPED upsert; safe to overlap because the DAO write is idempotent (DISTINCT).
- Gate the write to COMPASS accounts (`account.getDataProcessingMode() ∈ DataProcessingMode.COMPASS_PROCESSING_MODES`)
  so the legacy path isn't double-touched.

## Change map
### Phase 1 (sync, match-only)
- `match/shared/.../portal/csv/CsvUploadServiceImpl.java` — new `markCsvMapped(fileUploadId, ...)`, COMPASS-gated, calls DAO.
- `match/portal-admin/.../` new endpoint `POST /api/csv-file-upload/{fileUploadId}/csv-state:upsert` (model on existing
  CsvFileUploadController mutating endpoint, ~:521).
- `useDocumentMapping.ts` onSuccess (lines 29-32) — call the new endpoint after finalize succeeds. Frontend already knows
  csvFileId/accountId, so it does NOT depend on the Compass finalize response body.
- Consider a narrow DAO method that sets ONLY MAPPED (check `setMappingsApproved` side effects: mappings_approved_at/approved_by).

### Phase 2 (async)
- commons-kotlin (out of workspace): new `DocumentUpdatedEventV1` under `com.windfall.shared.types.event.*` — UNVERIFIED (repo absent).
- hamster: `EventingDocumentMappingService` (model: `EventingDatasetService.kt:22-86`), `DocumentMappingChangedPublisher`
  (model: `DatasetConfigChangedPublisher.kt:29-32`), topic config (model: `HamsterDatasetConfigChangedTopicConfig.kt:10-33`),
  `application.yaml` entry (model: dataset-config-changed, 258-262), wire into `DocumentMappingServiceConfig.kt:38-49`
  (Main→Validating→Logging→ADD Eventing). Bump `wf-commons-kotlin` in `gradle/libs.versions.toml` (currently 0.46.0).
- match: new `DocumentUpdatedMessageReceiver` (model: `AddressProcessingCompleteMessageReceiver.java:38-52` + channel config
  `DatasetServiceMain.java:38-86`), subscription `document-updated-sub-match`; bump `wf-commons-kotlin` in `pom.xml:54` (0.45.0).
  NOTE: match currently has NO PubSub subscribers of its own — receive infra is built from scratch here.
- Cross-service event precedent: `CsvUploadEventV1` — match publishes (`CsvFileUploadPublisherService.java`), hamster subscribes
  (`CsvUploadedSubscriber.kt`, subscription `match-csv-file-events_sub_hamster`, hamster application.yaml:177-184).
- Rollout order (strict): commons-kotlin release → bump both → hamster producer → match consumer (create subscription before first event).

## Phase 1 — IMPLEMENTED (sync path; needs build/format in IntelliJ — no mvn/pnpm in the CLI env)
Reuses the existing idempotent `CsvFileUploadDao.addFulfilledState(fileId, state)` (same call MatchJobCompletedHandler/
SdeJobCompletedHandler use). Generic "upsert fulfilled states" endpoint (ticket task 1), not MAPPED-hardcoded. NOT mode-gated
(idempotent + COMPASS-only by call-site); revisit if a mode guard is wanted.
- match `.../controller/frontend/FulfilledStatesUpsertRequest.java` (NEW) — `{ states: List<CsvFulfilledState> }`.
- match `.../service/frontend/CsvFileWorkflowsService.java` — new `addFulfilledStates(csvFileUploadId, List<CsvFulfilledState>)`
  → findById-or-404 then `addFulfilledState` per state. (+import CsvFulfilledState)
- match `.../controller/frontend/ApiCsvFileWorkflowsController.java` — new `POST /api/csv-files/{csvFileUploadId}/fulfilled-states`
  (validates non-empty; class already `@AllowedUserPermissions(PROCESS_FILES)`).
- match `portal-admin/frontend/.../hooks/useDocumentMapping.ts` — signature `useDocumentMapping(mappingId, csvFileMatchId?)`;
  in finalize `onSuccess` (after 200) POST `/csv-files/{csvFileMatchId}/fulfilled-states` `{states:['MAPPED']}`; try/catch notifies on failure.
  On success invalidates `CSV_FILES_WITH_CONSTRAINTS` + `CSV_FILE_WORKFLOW_TRIGGERS` so the UI status/eligibility refresh
  (same pattern as useKickoffWorkflowRun/useRetryWorkflowRun). After Done the wizard navigates to `/accounts/{id}/csv-enrichment`.
- match `.../components/CsvMappingWizardModalSubmit.tsx` — pass `csvFile?.csvFileMatchId` into the hook.
TODO before commit (user, in IDE): `mvn spotless:apply`, `pnpm prettier --write` the 2 TS files, build + a unit test for the new endpoint/service.
Phase 2 (async PubSub fallback) still pending — see §4/§5.

## Open questions
- Confirm with author: COMPASS finalize truly bypasses `setCsvFileMappings()` (finalize backend is in Compass, not this repo).
- commons-kotlin absent → can't confirm if `DocumentUpdatedEventV1` exists / its package / fields.
- orchestrator absent → can't confirm exactly how it requires MAPPED beyond match passing unfiltered fulfilledStates.
- Does the async event contract belong in commons-kotlin (shared) or copied per-integration? (whContext CLAUDE.md notes both rules.)
