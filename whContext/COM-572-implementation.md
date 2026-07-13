# COM-572 — "Add Field" in a CRM datasource opens the CRM Registry (PR open, in review)

Story COM-572, epic COM-563. Branch `viktor/COM-572/crm-registry-map-fields`. PR created, awaiting review
(incl. Copilot). This is a **living checklist** — update it as review / demo feedback changes scope.

## What it delivers
"Map fields" on a CRM dataset's classification opens the "Enter Object Details" modal listing the CRM
object's fields; the operator toggles fields on and either creates a new classification field or maps to an
existing known field. Works for **HubSpot and Salesforce** (was Salesforce-only).

## Backend (match/shared + portal-admin)
- CRM object-field metadata is now **CRM-agnostic via the Strategy pattern**: interface
  `CrmObjectMetadataProvider` + `SalesforceObjectMetadataProvider` (SFDC) / `HubSpotObjectMetadataProvider`
  (HUBSPOT) `@Service` beans; `CrmConnectionService.getObjectFields` injects `List<…>` → `Map<CrmType,…>` and
  dispatches by the account's CRM type (mirrors `OAuthService.credentialsProviderMap`). No more `switch`.
- Neutral DTOs `CrmObjectMetadata` / `CrmFieldMetadata`; `HubSpotMetadataService` reads HubSpot properties.
- Endpoint contract unchanged shape-wise (frontend `SalesforceObjectMetadata` type still deserializes).

## Frontend (portal-admin/frontend, crm-registry/)
- **Record ID**: custom multi-select that auto-closes on pick (`RecordIdSelect`). Picks → `isKey` on create.
- **Fields table**: search + type filter; per-row enable toggle; Label shown as text with a **hover pencil**
  for inline rename; **API Name wraps** to next line (no ellipsis); Type; Map to Field.
- **Map to Field**: "Create New Field" pinned at top; known-field list filtered to **type-compatible** entries
  (`isSchemaTypeCompatible` — e.g. a text field can't map to a number); after Save the picker shows the new
  field's name; picker wraps long names instead of overflowing the column.
- **Field Type**: locked to the CRM-inferred type (`lockDataType`), not editable. Inference handles both
  Salesforce and HubSpot spellings (`bool`, `number`, `datetime`, …).
- **Description**: multi-line.
- **Save Changes**: stages the mapping locally — does **NOT** write to the classification. **Next Step**
  batch-creates the enabled fields via `useAddClassificationField.addField`; guards if a Record-ID pick is left
  on a disabled row. Cancel restores the pre-edit selection; toggling a row off stashes its saved mapping so
  re-enabling restores it.
- **Modal scroll**: `ScrollArea.Autosize mah='50dvh' type='always'` (self-contained; footer stays pinned).
- Permission "Write" toggle **removed**.

## Decisions / deferred
- **Create-on-save was tried, then reverted** (user: "пока что не сохранять в классификацию на Save"): fields
  are created on **Next Step**, not on Save. See [[feedback_confirm_persistence_semantics_before_build]].
- No dev-only mocks in the PR (the local HubSpot field mock was removed once real data flowed).
- Field types are real `SchemaFieldType`; "ID" from the mock is expressed via the Record ID selector (isKey).

## Local testing
Account `tvv_hs` (id 5, `crm_type=HUBSPOT`); real HubSpot metadata now flows (444 Contact fields). Reach it at
`localhost:5173/accounts/5/datasets-compass/tvv-hs-hubspot` → expand a classification → Map fields.
