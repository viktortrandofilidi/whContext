# COM-570 — "Register New Object" wizard (object-level CRM registry)

Story COM-570, epic COM-563. The object-level sibling of COM-572 (field-level "Map New Fields"):
a "Register New Object" button on a CRM dataset's Objects tab opens a 4-step wizard to register a
whole new CRM object (Select object → Enter object details → Map object relationships → Register &
Reprocess). Design mockups + full plan: `~/.claude/plans/jaunty-weaving-hamming.md`.
Living checklist — update as scope/review changes. No commit/push until asked.

## Branch chain (this workspace)
COM-639 was initially absent here (created empty placeholders), then the user **pushed the real COM-639
branches** and I rebased onto them. Current state:
- match: `viktor/COM-570/add-object-wizard` is **rebased onto real `origin/viktor/COM-639/register-fields-confirmation-dialog`**
  (which merges `origin/viktor/COM-572/crm-registry-map-fields`). So `crm-registry/` + `RegisterFieldsConfirmModal.tsx`
  + the COM-639 `CrmRegistryModal` changes are all present. `checkts` green on the combined tree.
- hamster: local `viktor/COM-639/reprocess-on-classification-change` aligned to origin (real reprocess code:
  `BronzeToSilverReprocessor`, `DispatchingDatasetReprocessor`, `CLASSIFICATION_FIELDS_ADDED` trigger). hamster
  is checked out on `main`; switch to that branch only if backend work is needed (COM-570 register is client-side).
- The COM-570 foundation is **uncommitted** in the match working tree (new `register-object-wizard/` folder +
  `DatasetDetail.tsx` edit). User's pre-existing `portal/package.json` edits remain in `stash@{0}` (restore with
  `git stash pop` on master). No commits made (user does all git). NB: uncommitted work is local to this machine.

## Decisions (from plan; user had no strong preference → recommended defaults)
- Register = **client-side sequence** reusing existing proxied hooks (create classification → `:assign`
  → `addField` amend loop → `saveMergeStrategy`). `createClassification` does NOT emit a reprocess
  event — only amend/`addFields` does — so field creation must go through `addField` to trigger the
  COM-639 bronze→silver reprocess.
- **Write toggle dropped** (matches COM-572; registration is a pure pull, "no CRM sync needed").
- Step 2 keeps **full COM-572 parity** (Create New Field + known-field mapping; provisional tag root,
  re-resolve tags at register).
- Wizard shell = a single Mantine `Modal` (`size={1000}`) with an internal step switch (not Drawer).

## Frontend layout
New folder `portal-admin/frontend/src/domain/datasets/components/classifications/register-object-wizard/`.
Reuse as-is: `crm-registry/{RecordIdSelect,crmRegistryUtils}`, `UnifiedCreateClassificationFieldForm`,
hooks `useCrmObjectMetadata`/`useCrmObjectFields`, `useCreateDatasetClassification`,
`useAddClassificationField.addField`, `useSaveMergeStrategy`. Entry gate: `dataset.dataSourceKey != null`.

## Status
### Done + gates green (`pnpm checkts` + eslint on touched files = 0)
- `registerObjectWizard.types.ts` — `RegisterObjectWizardState` + `StagedRelationship` + initial state.
- `RegisterObjectButton.tsx` — gated entry button (mirrors `CreateDatasetObjectButton`).
- `RegisterObjectWizard.tsx` — Modal shell: `activeStep` + `wizardState` + per-step title + step switch.
- `SelectCrmObjectStep.tsx` (step 1) — search + "Fetching data from {CRM}…" loading + Object/API-Name
  table with clickable rows; `useCrmObjectMetadata`. Error + empty states.
- `DatasetDetail.tsx` — shows `RegisterObjectButton` for CRM datasets, else `CreateDatasetObjectButton`.
- Steps 2–4 are placeholders (Alert + Back/Cancel) so the shell is navigable.

### PAUSED — resume here (next session)
- **Open decision (deferred by user, "продолжим завтра"): how step 2 reuses the in-review code.**
  Option A "don't touch in-review" (recommended): extract `useCrmFieldStaging` hook + `CrmFieldMappingTable`
  for the wizard only; reuse `CrmRegistryFieldRow` as-is via a light object-context; leave `CrmRegistryModal`
  untouched (temporary duplication, dedupe later). Option B "refactor shared": extract hook+table, change
  `CrmRegistryFieldRow` prop `classification → objectContext`, migrate `CrmRegistryModal` too (clean, but edits
  COM-572/COM-639 files that are in review). Decide this first, then build step 2.
- **Decision already made:** step-2 mapping goes through "Create New Field" for a new object (no `tagPathRoot`
  before create ⇒ known-field list is naturally empty; matches the mockup). Known-field mapping stays available
  post-registration via COM-572's per-object "Map New Fields".

### Next
1. **Step 2 (Enter Object Details)** — per the decision above: staging table (search + type filter + per-row
   toggle + Map-to-Field via `CrmRegistryFieldRow`) + `RecordIdSelect`; fields via `useCrmObjectFields`
   (`selectedObject.name`). Stage into wizard state (no commit); Next Step runs the 3 guards and advances.
2. **Step 3 (Map Object Relationships)** — NEW row-based UI (`MapRelationshipsStep` + `RelationshipRow`),
   NOT the ReactFlow editor. Object options = existing `classifications` + the new object; row order →
   `linkPriority`.
3. **Step 4 (Register & Reprocess)** — confirm dialog (COM-639 `RegisterFieldsConfirmModal` pattern,
   rebuilt) + `useRegisterObject.ts` orchestration. **Needs `crmEntityKey` added to the client
   `CreateClassification` type** (backend `CreateClassificationRequest` accepts it) so the new
   classification is linked to the CRM object. Rebuild merge-strategy `classificationNodeTree` from the
   existing tree (`PUT` replaces the whole tree). Idempotent/resumable (guard create on
   `createdClassification`; classifications aren't deletable).
4. Verify per COM-572 note (account `tvv_hs`, id 5, HUBSPOT); hamster on the COM-639 branch for reprocess.

## Caveats
- Server-side bronze→silver reprocess depends on COM-639 hamster work (absent here) — wire/verify once
  that lands or is rebuilt on `viktor/COM-639/reprocess-on-classification-change`.
- `whContext/claude/` skills (`frontend-feature`, `self-review`) are not installed on this machine —
  following their conventions manually; run `self-review`/`code-review` equivalents before PR.
