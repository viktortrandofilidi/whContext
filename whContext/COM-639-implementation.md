# COM-639 — Confirmation dialog + trigger bronze→silver on classification field-add

Story COM-639 (epic COM-563), builds on COM-572. Two repos, two branches, **not committed/pushed**.
Living checklist — update as scope/review changes.

- match: `viktor/COM-639/register-fields-confirmation-dialog` (from the COM-572 branch)
- hamster: `viktor/COM-639/reprocess-on-classification-change` (from origin/main)

## What it delivers
On a CRM dataset, "Next Step" no longer persists. It opens a "Register New Fields" confirmation
dialog; only its **"Register & Pull Data"** button writes the staged fields to the classification.
That write then triggers a **debounced bronze→silver re-run** over the dataset's existing data (no
fresh CRM/CSV upload), so the newly-mapped fields get materialized.

## Frontend (match/portal-admin) — done, gates green
- `Next Step` → `handleContinueToConfirm` (runs the 3 validation guards, then opens the dialog; no
  persist, no `isSaving`). Persist moved to `handleRegisterAndPull` (the batch `addField` loop),
  called only from the dialog.
- Redundant `Back` removed from step 1 → footer is `Cancel` + `Next Step`. `handleClose` resets
  `confirmOpen`.
- New `RegisterFieldsConfirmModal.tsx` — centered dialog, `← Back` + `Register & Pull Data` (loading),
  copy: `{n} new field(s) will be registered to the "{object}" object. Registering will pull from
  existing data, no CRM sync needed.` No inline styles.
- No reprocessing/trigger call from the client — the re-run is entirely server-side.
- `pnpm ci:format` / `ci:lint` / `checkts` all pass.

## Backend (hamster) — done, additive, unit tests green
Reuses the existing debounced reprocessing subsystem (the COM-611 index-trigger is the template).
End-to-end is wired: `:amend` → `ClassificationService.addFields` → `EventingClassificationService`
emits `CLASSIFICATION_FIELDS_ADDED` (via `publishClassificationChange`) → recorded as a debounced
reprocessing row → scheduler tick → `DispatchingDatasetReprocessor` → `BronzeToSilverReprocessor`.

- Trigger + debounce (mirror COM-611): `CLASSIFICATION_FIELDS_ADDED` added to
  `REPROCESS_TRIGGERING_CHANGE_TYPES`; `ReprocessingDebouncePolicy` branch → new `classificationDebounce`;
  `ReprocessingProperties.classificationDebounce`; config `reprocessing.debounce.classification-update: PT2M`.
- `BronzeToSilverReprocessor` (new `DatasetReprocessor`): dataset → classification (via
  `findDatasetClassificationRelationships`, first relationship) → latest BRONZE_TO_SILVER flow by
  execution-group-key `bronze-to-silver-classification[<classificationId>]` → `setRequirements` to
  refresh the flow's classification requirement to the current revision → `FlowJobService`
  `requestJobExecution(BRONZE_TO_SILVER_PIPELINE, flowId)` → returns the real job id. Throws
  `REPROCESSING_NO_BRONZE_TO_SILVER_FLOW` when no flow/classification exists.
- `DispatchingDatasetReprocessor` (new, additive): classification change → bronze→silver; everything
  else → custom-field recalc; mixed → bronze→silver (it re-materializes silver, covering recalc).
  Wired in `DatasetReprocessingServiceConfig`; `MainDatasetReprocessingService` untouched.
- Self-contained: the change touches no unrelated flow code. The bronze→silver execution-group-key
  is built inline in `BronzeToSilverReprocessor` (with a comment that it must match the format in
  `MainFlowWriteService`) — deliberately duplicated rather than extracting a shared helper, to keep
  the footprint minimal. Separate `classificationDebounce` kept (not folded into the custom-field one).
- No contract change (launch returns a real job id via the flow-scoped launcher); no new Document
  infrastructure. Verified `updateFlowRequirements` does not itself launch a job → no double-launch.

## Verified by hand (not just agent report)
- Emit path is live: `EventingClassificationService` is in the `ClassificationServiceConfig` chain,
  so `:amend` fires the event. (The builder's "nothing emits it" note was a false alarm — it grepped
  the wrong method.)
- No double-launch from `setRequirements` + `requestJobExecution`.

## Caveats / open
- **Multi-classification datasets**: reprocessor uses the first relationship (one job per row). Fine
  for the single-classification CRM case; broader support needs a reprocessing-contract change.
- **`eventConfig.enabled`** must be true for the emit to fire (default on).
- Debounce `PT2M` (matches custom-field) — tune if needed.

## Local end-to-end test (needs hamster running ON the branch — the live :8090 is the old build)
1. Pick a dataset whose classification has a BRONZE_TO_SILVER flow. Example locally: classification
   `b35d826a-5499-4968-94ec-68c32e7c992d` (has a flow + a `dataset_relationship`).
2. Add a field to that classification (`POST /classifications/{id}:amend`, or via portal-admin).
3. Event fired: `select status, pending_change_types, reprocess_after from dataset_reprocessing
   where dataset_id = '<id>';` → PENDING, `pending_change_types` contains `CLASSIFICATION_FIELDS_ADDED`,
   `reprocess_after ≈ now + 2m`.
4. Pipeline launched (after ~2m debounce + 10s poll): row → PROCESSING with a `current_job_id`, and a
   new BRONZE_TO_SILVER job on that flow.

## Next gate
Pre-PR self-review (code-reviewer over both branch diffs) not yet run. No commit/push until asked.
