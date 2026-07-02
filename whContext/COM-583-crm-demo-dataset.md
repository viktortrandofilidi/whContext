# COM-583 — CRM dataset must not appear in CSV Mapping Wizard dropdown

## What was verified (implementation is complete)
Filter added in `match` branch `viktor/COM-583/...` (commit `bdd9f5d8b1`):
- `CsvMappingWizardModalPremap.tsx`: `csvDatasets = datasets.filter(d => d.dataSourceKey == null)`;
  both the dropdown (`datasetSelectData`) and the empty-state (`hasNoDatasets`) use `csvDatasets`.
- `dataset.types.ts`: added `dataSourceKey?: string | null`.
- Full chain confirmed: portal-admin `/compass/proxy/accounts/{id}/datasets`
  → hamster `GET /accounts/{id}/datasets` (`Page<Dataset>`, `dataSourceKey` in model + `toDataset()`)
  → column `dataset.data_source_key`. Listing already filters `is_latest AND active`.
- CRM datasets carry a non-null `data_source_key` (SALESFORCE / HUBSPOT / NEON ...); CSV datasets have NULL.

## Demo dataset prepared (local hamster DB, docker `local-hamster-postgres`, port 15433)
Account `1` — already had 2 active CSV datasets, 0 CRM. Added one active CRM (Salesforce) dataset:

- id            = da08b6fc-f804-4ad8-bf06-abd1a2a7bccc
- revision_id   = 937e450c-173c-4770-b1c8-ded2e3f95251
- key           = demo-salesforce-crm
- data_source_key = SALESFORCE

Expected wizard dropdown for account 1 (after the fix):
- Demo Dataset (demo-dataset)            — shown  (CSV, data_source_key NULL)
- Donor Test Dataset (donor-test)        — shown  (CSV, data_source_key NULL)
- Salesforce CRM (demo-salesforce-crm)   — HIDDEN (CRM, data_source_key = SALESFORCE)

## To see it in the UI
Needs local hamster (:8090) + match/portal-admin running (portal-admin proxy → localhost:8090).
Open account 1 → upload/select a CSV → Map CSV wizard → the "Data Source" dropdown lists only the two CSV datasets.

## Equivalent create via API (for dev, when hamster is running)
    curl -X POST "$HAMSTER/datasets" -H 'Content-Type: application/json' \
      -d '{"name":"Salesforce CRM","accountId":"1","key":"demo-salesforce-crm","dataSourceKey":"SALESFORCE"}'
    # compass CLI:
    compass dataset create --body '{"name":"Salesforce CRM","accountId":"1","key":"demo-salesforce-crm","dataSourceKey":"SALESFORCE"}'

## Rollback (remove the demo dataset)
    PGPASSWORD=password psql -h localhost -p 15433 -U dev -d hamster \
      -c "DELETE FROM dataset WHERE revision_id='937e450c-173c-4770-b1c8-ded2e3f95251';"
