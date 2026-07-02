-- Seed a demo Compass dataset for account 1 in the LOCAL hamster DB.
-- Demonstrates COM-568: accordion ordering (Person > Transaction/Gifts > Custom),
-- use cases (semantic tag text after '?'), data types, and fill-rate column.
-- Idempotent: re-running replaces the demo rows.

BEGIN;

-- Clean up any previous run.
DELETE FROM dataset_relationship
WHERE dataset_id = 'aaaaaaaa-0000-0000-0000-000000000001';
DELETE FROM classification
WHERE account_id = '1' AND key IN ('demo_people', 'demo_gifts', 'demo_memberships');
DELETE FROM dataset
WHERE account_id = '1' AND key = 'demo-dataset';

-- Dataset.
INSERT INTO dataset (id, revision_id, name, account_id, legacy_serial_id, created_at, updated_at, description, active, is_latest, key, data_source_key)
VALUES (
  'aaaaaaaa-0000-0000-0000-000000000001',
  gen_random_uuid(),
  'Demo Dataset',
  '1',
  NULL,
  now(),
  now(),
  'COM-568 demo dataset',
  true,
  true,
  'demo-dataset',
  NULL
);

-- People (PERSON).
INSERT INTO classification (id, revision_id, created_at, is_latest, key, name, state, account_id, created_by_id, created_by_username, type, fields, legacy_serial_id)
VALUES (
  'aaaaaaaa-1111-1111-1111-111111111111',
  gen_random_uuid(),
  now(),
  true,
  'demo_people',
  'People',
  'ACTIVE',
  '1',
  'seed',
  'seed',
  'PERSON',
  '{"content": {
    "personId": {"key": "personId", "tags": [{"id": "11111111-0000-0000-0000-000000000001", "state": "ACTIVE", "value": "person.id", "createdAt": 1780910052.988281000, "updatedAt": 1780910052.988281000}], "isKey": true, "dataType": "STRING", "visibility": "VISIBLE_CUSTOMER", "description": null, "displayName": "Person ID", "isMappingRequired": true},
    "firstName": {"key": "firstName", "tags": [{"id": "11111111-0000-0000-0000-000000000002", "state": "ACTIVE", "value": "person.name.firstName?matching", "createdAt": 1780910052.988281000, "updatedAt": 1780910052.988281000}], "isKey": false, "dataType": "STRING", "visibility": "VISIBLE_CUSTOMER", "description": null, "displayName": "First Name", "isMappingRequired": true},
    "lastName": {"key": "lastName", "tags": [{"id": "11111111-0000-0000-0000-000000000003", "state": "ACTIVE", "value": "person.name.lastName?matching", "createdAt": 1780910052.988281000, "updatedAt": 1780910052.988281000}], "isKey": false, "dataType": "STRING", "visibility": "VISIBLE_CUSTOMER", "description": null, "displayName": "Last Name", "isMappingRequired": true},
    "email": {"key": "email", "tags": [{"id": "11111111-0000-0000-0000-000000000004", "state": "ACTIVE", "value": "person.emails[primary].email?matching,application", "createdAt": 1780910052.988281000, "updatedAt": 1780910052.988281000}], "isKey": false, "dataType": "STRING", "visibility": "VISIBLE_CUSTOMER", "description": null, "displayName": "Email Address", "isMappingRequired": false},
    "zipCode": {"key": "zipCode", "tags": [{"id": "11111111-0000-0000-0000-000000000005", "state": "ACTIVE", "value": "person.addresses[home].zipcode?matching,segmentation", "createdAt": 1780910052.988281000, "updatedAt": 1780910052.988281000}], "isKey": false, "dataType": "STRING", "visibility": "VISIBLE_CUSTOMER", "description": null, "displayName": "Zip Code", "isMappingRequired": false}
  }, "version": 1}'::jsonb,
  NULL
);

-- Gifts (TRANSACTION).
INSERT INTO classification (id, revision_id, created_at, is_latest, key, name, state, account_id, created_by_id, created_by_username, type, fields, legacy_serial_id)
VALUES (
  'aaaaaaaa-2222-2222-2222-222222222222',
  gen_random_uuid(),
  now(),
  true,
  'demo_gifts',
  'Gifts',
  'ACTIVE',
  '1',
  'seed',
  'seed',
  'TRANSACTION',
  '{"content": {
    "transactionId": {"key": "transactionId", "tags": [{"id": "22222222-0000-0000-0000-000000000001", "state": "ACTIVE", "value": "transaction.id", "createdAt": 1780910052.988281000, "updatedAt": 1780910052.988281000}], "isKey": true, "dataType": "STRING", "visibility": "VISIBLE_CUSTOMER", "description": null, "displayName": "Transaction ID", "isMappingRequired": true},
    "amount": {"key": "amount", "tags": [{"id": "22222222-0000-0000-0000-000000000002", "state": "ACTIVE", "value": "transaction.amount?modeling", "createdAt": 1780910052.988281000, "updatedAt": 1780910052.988281000}], "isKey": false, "dataType": "FLOAT", "visibility": "VISIBLE_CUSTOMER", "description": null, "displayName": "Amount", "isMappingRequired": true},
    "giftDate": {"key": "giftDate", "tags": [{"id": "22222222-0000-0000-0000-000000000003", "state": "ACTIVE", "value": "transaction.date?modeling,segmentation", "createdAt": 1780910052.988281000, "updatedAt": 1780910052.988281000}], "isKey": false, "dataType": "DATE", "visibility": "VISIBLE_CUSTOMER", "description": null, "displayName": "Gift Date", "isMappingRequired": false}
  }, "version": 1}'::jsonb,
  NULL
);

-- Memberships (CUSTOM).
INSERT INTO classification (id, revision_id, created_at, is_latest, key, name, state, account_id, created_by_id, created_by_username, type, fields, legacy_serial_id)
VALUES (
  'aaaaaaaa-3333-3333-3333-333333333333',
  gen_random_uuid(),
  now(),
  true,
  'demo_memberships',
  'Memberships',
  'ACTIVE',
  '1',
  'seed',
  'seed',
  'CUSTOM',
  '{"content": {
    "membershipId": {"key": "membershipId", "tags": [{"id": "33333333-0000-0000-0000-000000000001", "state": "ACTIVE", "value": "other.id", "createdAt": 1780910052.988281000, "updatedAt": 1780910052.988281000}], "isKey": true, "dataType": "STRING", "visibility": "VISIBLE_CUSTOMER", "description": null, "displayName": "Membership ID", "isMappingRequired": true},
    "tier": {"key": "tier", "tags": [{"id": "33333333-0000-0000-0000-000000000002", "state": "ACTIVE", "value": "other.customAttributes[tier]?segmentation", "createdAt": 1780910052.988281000, "updatedAt": 1780910052.988281000}], "isKey": false, "dataType": "STRING", "visibility": "VISIBLE_CUSTOMER", "description": null, "displayName": "Tier", "isMappingRequired": false},
    "joinedAt": {"key": "joinedAt", "tags": [{"id": "33333333-0000-0000-0000-000000000003", "state": "ACTIVE", "value": "other.customAttributes[joined]?modeling", "createdAt": 1780910052.988281000, "updatedAt": 1780910052.988281000}], "isKey": false, "dataType": "DATE", "visibility": "VISIBLE_CUSTOMER", "description": null, "displayName": "Joined At", "isMappingRequired": false}
  }, "version": 1}'::jsonb,
  NULL
);

-- Link classifications to the dataset.
INSERT INTO dataset_relationship (id, dataset_id, classification_id) VALUES
  (gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-1111-1111-1111-111111111111'),
  (gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-2222-2222-2222-222222222222'),
  (gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-3333-3333-3333-333333333333');

COMMIT;
