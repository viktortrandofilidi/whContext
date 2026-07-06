# COM-572 — «Add Field» в CRM-датасорсе открывает CRM Registry (implemented, needs IDE build)

Story COM-572, epic COM-563. Frontend-only in `match/portal-admin/frontend`. No CLI toolchain in this env → not
built/typechecked/prettier'd here; do it in IntelliJ.

## Approach
"Map fields" on a CRM dataset's classification (`dataset.dataSourceKey != null`) opens a new full-width
"Enter Object Details" modal listing the CRM object's fields; operator toggles fields on and either maps to a
Windfall field or creates a new one (type/description/use-cases). Reuses existing building blocks:
- source: `useCrmObjectFields(accountId, objectName)` → `/api/crm-connection/metadata/{acct}/{object}` (Salesforce metadata).
- inline editor: `UnifiedCreateClassificationFieldForm` (Windfall picker via Browse Known Fields, Field Type, Description, Application/Modelling).
- save: `useAddClassificationField.addField` (`:amend`), mirroring `CreateClassificationFieldModal.handleUnifiedSubmit`.

## Files
- `types/dataset.types.ts` — added `Dataset.dataSourceKey?` and `Classification.crmEntityKey?`.
- `domain/datasets/components/classifications/crm-registry/crmRegistryUtils.ts` (NEW) — `crmTypeToSchemaFieldType`, `unmappedCrmFields`.
- `.../crm-registry/CrmRegistryFieldRow.tsx` (NEW) — table row: toggle, Label/API Name/Type, Map-to-Field summary + edit icon, expandable inline editor (UnifiedForm + Save Changes/Cancel).
- `.../crm-registry/CrmRegistryModal.tsx` (NEW) — "Enter Object Details": API Name header + count, Record ID select, Permissions Write switch, search + type filter, unmapped-fields table, Cancel/Back/Next-Step, loading/error. Next Step → sequential `addField` per enabled field; Record ID field → `isKey`.
- `.../classifications/ClassificationAccordionItem.tsx` — gate: CRM → CrmRegistryModal, else CreateClassificationFieldModal.

## Deviations from mock / not done (revisit)
- **Map to Field**: implemented as an expandable inline editor (with Browse-Known-Fields Windfall picker + Create New) rather than the mock's in-row dropdown listing Windfall fields directly. Functionally equivalent; UX differs.
- **Use-cases (Application/Modelling)**: shown in editor; persistence mirrors the existing create-field modal (no explicit use-case tag suffix built client-side — server/form concern). Confirm this persists use-cases as intended.
- **Field types**: real `SchemaFieldType` (STRING/FLOAT/INTEGER/BOOLEAN/DATE), not the mock's "ID" — "ID" is expressed via the Record ID selector (isKey), not a type.
- **Permissions: Write** — visual switch only, no backend effect (semantics undefined in story).
- **Enter-to-confirm + auto-focus next row** (mock note) — NOT implemented.
- CRM coverage: works for Salesforce (only live metadata source); other CRMs → error state (per story).

## Open / verify
- `crmEntityKey` must equal the Salesforce object API name accepted by `/crm-connection/metadata/{acct}/{object}` — verify on a real account; add a mapping if it diverges.
- `unmappedCrmFields` matches CRM api name (sanitized) against classification field keys — approximate; confirm.
- Record ID / Permissions semantics not specified in story.

## TODO before commit (user, IDE)
`pnpm prettier --write` the new/changed TS; typecheck + build; manual verify per plan; commit.
