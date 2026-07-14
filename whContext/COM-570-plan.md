> **Handoff note (2026-07-13):** approved design plan for COM-570, copied into whContext so it travels
> across environments. The **live status, current branch state, and decisions that evolved during
> implementation** are in [`COM-570-implementation.md`](./COM-570-implementation.md) — read that first.
> Deviations from this plan already decided:
> - COM-639 is no longer "not yet committed": its branches are pushed; COM-570 is rebased onto the real
>   `origin/viktor/COM-639/register-fields-confirmation-dialog` (which merges COM-572).
> - Step-2 mapping for a brand-new object goes through **"Create New Field"** only (no `tagPathRoot` before
>   create ⇒ the known-field list is naturally empty; matches the mockup), NOT the "full COM-572 parity" the
>   text below suggests. Known-field mapping stays available post-registration via COM-572's per-object flow.
> - The `frontend-feature` / `self-review` skills referenced below are **not installed** in this workspace —
>   follow their conventions manually and run the CI gates (`prettier` / `ci:format` / `ci:lint` / `checkts`).
> - Still open (deferred by user): whether step 2 reuses the in-review code via a shared refactor of
>   `CrmRegistryModal` or leaves it untouched. See the implementation doc's "PAUSED" section.

---

# COM-570 — Compass Dataset Mgmt | Add Object ("Register New Object") Wizard

## Context

The Compass Dataset Management UI (epic **COM-563**, in `match/` portal-admin — the "New Interface"
redesign) lets users manage a dataset's objects, fields, and relationships. For **CRM-backed
datasources**, users need a way to register a brand-new CRM object (e.g. `Transaction`) into the
dataset without a full CRM sync — pulling from data already ingested.

**Story: [COM-570 "Compass Dataset Mgmt | Add Object Wizard"](https://windfalldata.atlassian.net/browse/COM-570)**
(Story, *In Definition*, epic COM-563).
Figma: `Portal-Admin — Working File`, node `13268-24903`.

Story notes (verbatim intent):
- The flow is triggered by the **"Register New Object"** button.
- That button should **only be visible for CRM datasources**.
- "For CRMs this should **pull from the existing CRM Object Registry UI**."

### Relationship to work already in flight (both assigned to Viktor)
The wizard reuses infrastructure the user is already building for sibling stories under COM-563:
- **[COM-572](https://windfalldata.atlassian.net/browse/COM-572)** (*Review*) — "Map New Fields"
  button on a CRM classification opens the **CRM Registry** to map **fields** to an existing object.
  Establishes: object/field fetch from CRM, the Fields table (toggle + Label + API Name + Type +
  "Map to Field"), "Create New Field" default, the Windfall-field-vs-create-new modal (type,
  description, use-cases), per-row edit icon, multi-select, and CRM-load error handling.
- **[COM-639](https://windfalldata.atlassian.net/browse/COM-639)** (*In Progress*) — confirmation
  dialog that persists mapped CRM fields to the classification and (debounced) kicks off bronze
  orchestrator processing. "Only persist data when clicked." This is the analogue of COM-570's final
  **"Register & Reprocess Data"** confirmation.

COM-570 is the **object-level** counterpart of COM-572's field-level flow: same registry UI, but it
registers a whole new object (object picker + Record ID + relationships) rather than adding fields to
an existing one.

## Precise screen-by-screen breakdown (from the mockups)

The wizard is a modal sequence launched by **"Register New Object"** (top-right of Datasets > `<name>`,
next to "Map New Fields"). Steps:

**0. Entry point** — On the dataset-specific page (Objects tab), "Register New Object" button. Visible
only when the datasource is a CRM (HubSpot/Salesforce). Adjacent per-object "Map New Fields" is the
COM-572 flow.

**1. Modal "Select Object to Import"** — subtitle "Select which object you'd like to register from the
CRM". Search box "Search objects…". Loading state: spinner + "Fetching Data from Hubspot…". Then a
table: columns **Object** (display name) / **API Name** (e.g. `Transaction_c`), each row chevron →
selects the object and advances. Cancel.

**2. Modal "Enter Object Details"** — header "API Name: `<Object>`".
- **Record ID** — a select whose menu is a multi-select checklist of the object's ID-type fields
  (Transaction ID, Account Contact Relationship ID, Account ID, …). Selected values render as
  removable chips (e.g. `Transaction ID ×`). Searchable, multiple selection.
- **Permissions: Write** toggle (info icon), default on. *(Decision: dropped — see below.)*
- **Fields (N)** table with a search box ("Search fields…") + a **type filter** ("All Types",
  clearable). Header has a master toggle. Rows: **toggle | Label | API Name | Type**. When a row is
  enabled, a **"Map to Field"** cell appears with **"Create New Field"** pre-selected by default and an
  **edit pencil**; clicking pencil = "Create New Field + Edit" (opens the field-detail modal from
  COM-572: type/description/use-cases, or pick a Windfall field). **When a Record ID is selected, its
  matching rows auto-enable** in the table.
- Footer: Cancel · Back · **Next Step**.

**3. Modal "Map Object Relationships"** — subtitle "Create a new relationship between objects in your
data model". Info banner: "Order of the fields is very important for mapping the object relationships."
Repeating relationship rows, each: left **Object** select (defaults to the new object, e.g.
`Transaction`) + **Field** select (e.g. `ContactId`), an arrow, right **Object** select (e.g.
`Contact`) + **Field** select (e.g. `ID`). Each row has up/down reorder handles. **"+ Add New
Relationship"** link adds an empty row. Footer: Cancel · Back · **Next Step** (disabled until valid).

**4. Confirmation modal "Register New Object"** — icon, body: `"<Object>" will be registered as a new
object. Registering will pull from existing data, no CRM sync needed.` Buttons: **← Back** ·
**Register & Reprocess Data** (mirrors COM-639's persist-then-trigger-bronze behavior).

## Story mapping (found in Jira)

Epic **COM-563 "Compass | Dataset Mgmt UI"** children of interest:
- COM-568 (*Done*) — Dataset-specific view converted to tabbed (Objects/Custom Fields/Relationships) +
  accordion UI. **Base page already exists.**
- COM-570 (*In Definition*) — **THIS**: Add Object ("Register New Object") wizard.
- COM-572 (*Review*, Viktor) — Map New Fields → CRM Registry (field-level).
- COM-639 (*In Progress*, Viktor) — confirm dialog: persist mapped field + bronze reprocess.
- COM-573 — Dataset view: pull in Records/People/Transactions (the stat cards).
- COM-575/576/577/578 — *Won't Do* (superseded).

## Where it lives (confirmed)

- App: **`match/portal-admin/frontend`** (React 19 + Vite + **Mantine v9** + TanStack Router/Query).
- Screen: `src/domain/datasets/DatasetDetail.tsx` (the `datasets-compass/$datasetKey` route), Objects tab =
  `components/classifications/ClassificationsTab.tsx` + `ClassificationAccordionItem.tsx`.
- Backend is two-tier: `match/portal-admin` (Spring MVC) owns CRM metadata discovery
  (`ApiCrmConnectionController`, `/api/crm-connection/metadata/...`) and proxies everything else to
  **hamster/Compass** via `/api/compass/proxy/**` (classifications, datasets, merge-strategy, reprocessing).

## Direct dependency on in-flight work

COM-570 is the **object-level** sibling of COM-572 (field-level) and reuses COM-639's confirm+reprocess:
- **COM-572** branch `viktor/COM-572/crm-registry-map-fields` created the
  `datasets/components/classifications/crm-registry/` folder: `RecordIdSelect` (multi-select → `isKey`),
  the Fields table (search + type filter, per-row toggle, hover-pencil rename, Map-to-Field with
  "Create New Field" pinned + type-compatible known-field list via `isSchemaTypeCompatible`, locked
  CRM-inferred type via `lockDataType`, multi-line description), "Save Changes" stages locally, "Next
  Step" batch-creates via `useAddClassificationField.addField`. Backend: CRM-agnostic
  `CrmObjectMetadataProvider` strategy (Salesforce + **HubSpot**), DTOs `CrmObjectMetadata`/`CrmFieldMetadata`.
- **COM-639** branches `viktor/COM-639/register-fields-confirmation-dialog` (match) +
  `viktor/COM-639/reprocess-on-classification-change` (hamster): `RegisterFieldsConfirmModal`
  ("← Back" + "Register & Pull Data", copy "…will pull from existing data, no CRM sync needed") and the
  server-side **debounced bronze→silver reprocess**: `CLASSIFICATION_FIELDS_ADDED` event →
  `DispatchingDatasetReprocessor` → `BronzeToSilverReprocessor`. This is exactly COM-570's step-4 behavior.

## Reuse map (mockup → existing code)

| Wizard step | Reuse |
|---|---|
| "Register New Object" button (Objects tab, CRM-only) | new button next to `CreateDatasetObjectButton.tsx`; gate on CRM datasource (`dataset.dataSourceKey`) |
| 1. Select Object to Import | CRM object list via `useCrmObjectMetadata` (`GET /api/crm-connection/metadata/{accountId}`) |
| 2. Enter Object Details | **COM-572 `crm-registry/` components**: `RecordIdSelect`, Fields table, Map-to-Field, Create-New-Field editor; fields via `useCrmObjectFields` (`/metadata/{accountId}/{objectName}`) |
| 3. Map Object Relationships | NEW row-based UI (NOT the ReactFlow editor); writes `DatasetMergeStrategy` via `useSaveMergeStrategy` |
| 4. Register & Reprocess Data | **COM-639 `RegisterFieldsConfirmModal` pattern** + server-side bronze→silver reprocess |
| Wizard shell | single Mantine `Modal` with an internal step switch (pattern from `create-dataset-wizard/CreateDatasetPopover.tsx`, but Modal not Drawer) |

## Register orchestration (the one genuinely new bit)

COM-572 adds fields to an *existing* classification; COM-570 must **create a new object end-to-end**.
On "Register & Reprocess Data", compose the existing proxied Compass calls:
1. `POST /compass/proxy/classifications` — create the classification (`crmEntityKey = object.name`, type
   inferred, `fields: []`) → reuse `useCreateDatasetClassification` (also does `:assign`).
   NB: the client `CreateClassification` type has **no `crmEntityKey`** yet — add it (backend accepts it).
2. Per staged field, `addField({ classification: created, newField })` sequentially
   (`useAddClassificationField` re-reads latest each time). **This is what emits the event and triggers
   the COM-639 bronze→silver reprocess** — `createClassification` alone does NOT.
3. Rebuild `classificationNodeTree` from the **existing** `mergeStrategy.classificationNodeTree` + new
   node + step-3 edges (row order → `linkPriority`), then `saveMergeStrategy` (**PUT replaces the whole
   tree** — build from current, don't send only the new subtree).
4. Invalidate `DATASET_DETAIL` / `CLASSIFICATIONS`, close, land on Objects tab.
- **Idempotent/resumable:** create only if `createdClassification == null`; `addField` only for staged
  keys not already present; classifications aren't deletable → a mid-sequence failure leaves a partial
  object (show per-step progress + retry).

## Decisions (recommended defaults; user had no strong preference — can override at review)

- **Register flow → client-side sequence reusing COM-639.** `createClassification` does NOT emit a
  reprocess event — only amend/`addFields` does — so field creation must go through `addField`.
- **Write toggle → dropped** (matches COM-572; registration is a pure pull, "no CRM sync needed").
- **Branch base → stacked on COM-639** (rebased onto the real pushed branch).
- **Step-2 mapping → "Create New Field" for new objects** (revised from "full parity"; a new object has
  no `tagPathRoot` before create, so the known-field list is naturally empty and matches the mockup).

## Architecture

- **Entry:** `DatasetDetail.tsx` Objects tab shows `<RegisterObjectButton>` when `dataset.dataSourceKey != null`,
  else the existing `<CreateDatasetObjectButton>`.
- **Shell:** one Mantine `Modal` (`size={1000}`, `closeOnClickOutside={false}`) with an internal step switch.
- **New folder** `match/portal-admin/frontend/src/domain/datasets/components/classifications/register-object-wizard/`:
  `RegisterObjectButton.tsx`, `RegisterObjectWizard.tsx`, `SelectCrmObjectStep.tsx`, `EnterObjectDetailsStep.tsx`,
  `MapRelationshipsStep.tsx` + `RelationshipRow.tsx`, `RegisterConfirmationStep.tsx`, `useRegisterObject.ts`,
  `registerObjectWizard.types.ts`.
- **Reuse as-is:** `crm-registry/RecordIdSelect`, `crm-registry/crmRegistryUtils`, `CrmRegistryFieldRow`,
  `UnifiedCreateClassificationFieldForm`; hooks `useCrmObjectMetadata`/`useCrmObjectFields`,
  `useCreateDatasetClassification`, `useAddClassificationField.addField`, `useSaveMergeStrategy`.
- **`wizardState`:** `selectedObject`, `recordIdFieldNames` (→ `isKey`), `stagedFields`/`mapSelection`
  (by CRM api-name), `relationships` (index = `linkPriority`), `createdClassification` (for resume). Lives in
  the container; steps are controlled. Nothing written to the server before step 4.
- **Relationships (step 3):** NEW row-based UI (`MapRelationshipsStep` + `RelationshipRow`) on Mantine
  `Select`s + reorder handles — NOT the ReactFlow editor. Object options = existing classifications + the new
  object. Row order → `linkPriority`.

## Prerequisites / risks

1. Reprocess depends on COM-639's hamster branch; verify the amend event type is in
   `REPROCESS_TRIGGERING_CHANGE_TYPES` (`DatasetConfigChangedPublisher`) and handled by
   `ReprocessingDebouncePolicy.debounceFor`.
2. No transaction across create+assign+addFields+mergeStrategy; classifications aren't deletable → make
   register idempotent/resumable with clear per-step errors.
3. `merge-strategy` PUT replaces the whole tree — rebuild from the existing tree or existing relationships drop.
4. Confirm hamster allows create with `fields: []`; else seed the record-id key field in create.
5. Is ≥1 relationship required to register? Can the new object self-reference? Confirm with PM.

## Verify (end-to-end)

Account `tvv_hs` (id 5, `crm_type=HUBSPOT`), `localhost:5173/accounts/5/datasets-compass/tvv-hs-hubspot`.
Hamster must run **on the COM-639 branch** for reprocess (live :8090 is the old build).
1. On a CRM dataset click "Register New Object" → run all 4 steps.
2. Verify the object appears on the Objects tab; fields + relationships persist across reload.
3. hamster DB: `select status, pending_change_types, reprocess_after from dataset_reprocessing where
   dataset_id = '<id>';` → PENDING with `CLASSIFICATION_FIELDS_ADDED`, then PROCESSING + `current_job_id`.
4. Gates: `pnpm prettier --write` (touched files), `pnpm ci:format`, `pnpm ci:lint`, `pnpm checkts`.

## Conventions

- match frontend: Mantine style-props (no inline styles), `type` over `interface`, no `any`, TanStack Query
  layering (component → hook → service), query keys in the central enum. Reuse existing patterns first.
- Do **not** commit/push — the user does all git ops.
