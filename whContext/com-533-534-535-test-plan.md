# COM-533 / 534 / 535 — демо-сценарий (чистый SQL для IDE)

Гоняешь SQL в IDE-консоли (DataGrip/IntelliJ). Меняешь **только число id файла** — в каждом скрипте оно встречается один раз (в run-скриптах вынесено в CTE).

## Подключения в IDE (два data source)

**match** (стадии / меню / кнопка)
```
host=localhost  port=5432   database=match   user=<твой_юзер>   password=(пусто)
```

**jobmeta** (статусы прогона — ring/timeline/Retry)
```
host=localhost  port=15433  database=jobmeta  user=dev   password=password
```

UI: `http://localhost:5173/accounts/1/csv-enrichment`, аккаунт 1. После каждого скрипта — **hard refresh** (⌘⇧R).

> ⚠️ ПРЕДУСЛОВИЕ для Части B: match должен читать ЛОКАЛЬНЫЙ оркестратор. Уже настроено — в `match/portal-admin/.../config/application-local.properties` добавлено `orchestrator.base-url=http://localhost:9081`, и `orchestrator-svc` поднят. **Нужно перезапустить match** (IntelliJ), чтобы override применился. Проверка: `GET localhost:5173/api/csv-files/<id>/workflows/runs` должен вернуть `{"runs":[]}` (локальная jobmeta пустая), а не dev-прогоны 39–42. Тогда `localhost:15433 / jobmeta` — та самая БД, что отвечает UI.

Связи jobmeta: `dag_run.csv_file_id` = id файла; `dag_run_step_v2.dag_run_id` → `dag_run.id`.
Статусы: прогон `PENDING|RUNNING|SUCCESS|FAILED`; шаг `PENDING|IN_PROGRESS|SUCCESS|FAILURE|SKIPPED`.

---

## РЕСЕТ — connection: **match**
```sql
UPDATE csv_file_upload SET fulfilled_states=NULL, dataset_object_id=NULL, ignore_file=false WHERE id=468;
UPDATE account SET data_processing_mode='COMPASS' WHERE id=1;
```

---

## ЧАСТЬ A — стадии / меню / кнопка — connection: **match**

### A1. Нет маппинга + есть dataset object
```sql
UPDATE csv_file_upload SET fulfilled_states=NULL, dataset_object_id=3 WHERE id=468;
```
Открой `⋮`: категории WORKFLOW(S)/ENRICHMENT(свёрнут)/OTHER, иконки, **Unlink from Dataset Object**; раскрой ENRICHMENT → триггеры серые + tooltip «Requires data state…»; кнопка действия **Map CSV**. *(533: категории/collapse/иконки/Unlink/ineligible; 535: !MAPPED)*

### A2. Mapped
```sql
UPDATE csv_file_upload SET fulfilled_states=ARRAY['MAPPED'] WHERE id=468;
```
Синяя пилюля **Mapped**; в меню **Load & Standardize Data** активен → клик → `POST /workflow-runs` (создаёт прогон для Части B); повторный быстрый клик → жёлтый notify «Workflow already running»; кнопка действия **Load & Standardize Data** (teal). *(534: пилюли; 533: eligible→POST + already-running; 535: displayName/disable/error)*

### A3. Порядок пилюль + игнор неизвестного
```sql
UPDATE csv_file_upload SET fulfilled_states=ARRAY['STANDARDIZED','MAPPED'] WHERE id=468;
```
→ **Mapped**(blue) перед **Standardized**(indigo).
```sql
UPDATE csv_file_upload SET fulfilled_states=ARRAY['MAPPED','STANDARDIZED','MATCHED','VALIDATED','ENRICHED','DELIVERED','BOGUS'] WHERE id=468;
```
→ 6 пилюль blue→indigo→violet→teal→green→gray, **BOGUS** скрыт. *(534: порядок/цвета/игнор)*

### A4. Matched, не Validated → Map CSV
```sql
UPDATE csv_file_upload SET fulfilled_states=ARRAY['MAPPED','STANDARDIZED','MATCHED'] WHERE id=468;
```
→ кнопка **Map CSV** (контур). *(535: MATCHED && !VALIDATED)*

### A5. Все стадии → кнопка скрыта
```sql
UPDATE csv_file_upload SET fulfilled_states=ARRAY['MAPPED','STANDARDIZED','MATCHED','VALIDATED','ENRICHED','DELIVERED'] WHERE id=468;
```
→ колонка действия пустая. *(535: else hidden)*

### A6. Feature gate — connection: **match**
```sql
UPDATE account SET data_processing_mode='DEFAULT' WHERE id=1;   -- legacy-меню без категорий
```
```sql
UPDATE account SET data_processing_mode='COMPASS' WHERE id=1;   -- снова категории
```
*(533: gate)*

---

## ЧАСТЬ B — статусы прогона — connection: **jobmeta**

> Кикофф-кнопка локально не запускает воркфлоу (оркестратор в Docker не достаёт Pub/Sub-эмулятор → 500), поэтому прогон создаём **чистым SQL** ниже — кликать «Load & Standardize Data» для этого не нужно.

Перед B верни рабочую стадию (connection **match**): `UPDATE csv_file_upload SET fulfilled_states=ARRAY['MAPPED'] WHERE id=468;`

### B-seed. Создать прогон RUNNING для файла (SQL, без кикоффа)
Меняешь `468` в трёх местах (2 DELETE + `csv_file_id` в INSERT). `csvFileId` внутри `trigger_data` не важен — рендер берёт `csv_file_id` из колонки.
```sql
DELETE FROM dag_run_step_v2 WHERE dag_run_id IN (SELECT id FROM dag_run WHERE csv_file_id = 468);
DELETE FROM dag_run WHERE csv_file_id = 468;
WITH ins AS (
  INSERT INTO dag_run (dag_name, account_id, created_at, start_time, end_time, trigger_data, hydrated_dag, csv_file_id, status)
  VALUES (
    'wf-load-standardize-data-flow', 1, now(), now(), NULL,
    '{"dag": "wf-load-standardize-data-flow", "type": "CSV_WORKFLOW", "context": null, "dagName": "wf-load-standardize-data-flow", "display": {"icon": "tabler:database-import", "name": "Load & Standardize Data", "category": "Workflow", "priority": 4}, "csvFileId": 0, "dataset-id": 0, "alert-level": "MEDIUM", "trigger-type": "CSV_WORKFLOW", "portal-mappings": null, "dagAlertPriority": "MEDIUM", "dataset-object-id": null, "available-data-states": ["MAPPED"]}'::jsonb,
    '{"dagName":"wf-load-standardize-data-flow","alertLevel":"MEDIUM","alertConfig":{"activate-after":{"ms":0,"s":0,"m":0,"h":12},"repeat-every":{"ms":0,"s":0,"m":0,"h":6},"alert-attempt":0},"emitStepCompletionEvents":false,"windfallDefault":false,"jobsMap":{"cdm-csv-staging-job":{"job-type":"CDM_CSV_STAGING_JOB","requires":[],"handle":"cdm-csv-staging-job","dataset-id":0,"dataset-object-id":0,"statusMessageClassName":"com.windfalldata.commons.orchestration.job.CdmCsvStagingJobConfig","no-op":false},"sde-job":{"job-type":"NO_OP","requires":["cdm-csv-staging-job"],"handle":"sde-job","statusMessageClassName":"com.windfalldata.commons.orchestration.job.NoOpStep","no-op":true},"csv-data-load-job":{"job-type":"CSV_DATA_LOAD_JOB","requires":["sde-job"],"handle":"csv-data-load-job","statusMessageClassName":"com.windfalldata.commons.orchestration.job.CsvDataLoadJobConfig","no-op":false}}}',
    468, 'RUNNING')
  RETURNING id
)
INSERT INTO dag_run_step_v2 (id, dag_run_id, job_handle, job_type, account_id, status, created_at, updated_at)
SELECT gen_random_uuid()::text, i.id, h.handle, h.jt, 1, h.st, now(), now()
FROM ins i, (VALUES
  ('cdm-csv-staging-job','CDM_CSV_STAGING_JOB','IN_PROGRESS'),
  ('sde-job','SDE_JOB','PENDING'),
  ('csv-data-load-job','CSV_DATA_LOAD_JOB','PENDING')) AS h(handle, jt, st);
```
→ в UI появляется прогон **Load & Standardize Data**, ring **0/3**, timeline (cdm синий → серые). Проверено.

### B0. Посмотреть прогоны и шаги файла
```sql
SELECT r.id AS run, r.status AS run_status, s.job_handle, s.status AS step_status, r.created_at
FROM dag_run r
LEFT JOIN dag_run_step_v2 s ON s.dag_run_id = r.id
WHERE r.csv_file_id = 468
ORDER BY r.created_at DESC, s.created_at;
```

Каждый скрипт ниже — один стейтмент (id файла один раз в `latest`), и сам пересоздаёт 3 строки шагов, поэтому ring/timeline всегда корректны (даже если у прогона ещё не было строк шагов). Все три проверены против локального оркестратора.

### B2. Последний прогон → SUCCESS (все 3 шага зелёные, ring 3/3)
```sql
WITH latest AS (SELECT id FROM dag_run WHERE csv_file_id = 468 ORDER BY created_at DESC LIMIT 1),
     upd AS (UPDATE dag_run SET status='SUCCESS', end_time=now() WHERE id IN (SELECT id FROM latest) RETURNING id),
     del AS (DELETE FROM dag_run_step_v2 WHERE dag_run_id IN (SELECT id FROM latest) RETURNING id)
INSERT INTO dag_run_step_v2 (id, dag_run_id, job_handle, job_type, account_id, status, created_at, updated_at)
SELECT gen_random_uuid()::text, l.id, h.handle, h.jt, 1, 'SUCCESS', now(), now()
FROM latest l, (VALUES
  ('cdm-csv-staging-job','CDM_CSV_STAGING_JOB'),
  ('sde-job','SDE_JOB'),
  ('csv-data-load-job','CSV_DATA_LOAD_JOB')) AS h(handle, jt);
```
→ таб зелёный, ring **3/3**, timeline весь зелёный. *(534: SUCCESS-таб)*

### B3. Последний прогон → FAILED (кнопка Retry; cdm красный, остальные серые)
```sql
WITH latest AS (SELECT id FROM dag_run WHERE csv_file_id = 468 ORDER BY created_at DESC LIMIT 1),
     upd AS (UPDATE dag_run SET status='FAILED', end_time=now() WHERE id IN (SELECT id FROM latest) RETURNING id),
     del AS (DELETE FROM dag_run_step_v2 WHERE dag_run_id IN (SELECT id FROM latest) RETURNING id)
INSERT INTO dag_run_step_v2 (id, dag_run_id, job_handle, job_type, account_id, status, created_at, updated_at)
SELECT gen_random_uuid()::text, l.id, h.handle, h.jt, 1, h.st, now(), now()
FROM latest l, (VALUES
  ('cdm-csv-staging-job','CDM_CSV_STAGING_JOB','FAILURE'),
  ('sde-job','SDE_JOB','PENDING'),
  ('csv-data-load-job','CSV_DATA_LOAD_JOB','PENDING')) AS h(handle, jt, st);
```
→ кнопка действия **Retry** (красная); клик → `POST /workflow-runs/{id}/retry`. *(535: FAILED → Retry)*

### B-откат. Вернуть в RUNNING (cdm in-progress)
```sql
WITH latest AS (SELECT id FROM dag_run WHERE csv_file_id = 468 ORDER BY created_at DESC LIMIT 1),
     upd AS (UPDATE dag_run SET status='RUNNING', end_time=NULL WHERE id IN (SELECT id FROM latest) RETURNING id),
     del AS (DELETE FROM dag_run_step_v2 WHERE dag_run_id IN (SELECT id FROM latest) RETURNING id)
INSERT INTO dag_run_step_v2 (id, dag_run_id, job_handle, job_type, account_id, status, created_at, updated_at)
SELECT gen_random_uuid()::text, l.id, h.handle, h.jt, 1, h.st, now(), now()
FROM latest l, (VALUES
  ('cdm-csv-staging-job','CDM_CSV_STAGING_JOB','IN_PROGRESS'),
  ('sde-job','SDE_JOB','PENDING'),
  ('csv-data-load-job','CSV_DATA_LOAD_JOB','PENDING')) AS h(handle, jt, st);
```

---

## CLEANUP
connection **match**:
```sql
UPDATE csv_file_upload SET fulfilled_states=NULL, dataset_object_id=NULL WHERE id=468;
UPDATE account SET data_processing_mode='COMPASS' WHERE id=1;
```
connection **jobmeta**: вернуть прогон в RUNNING — см. B-откат.

## Покрытие требований

| Стори | Требование | Шаг |
|---|---|---|
| 533 | категории + collapse + иконки + Unlink | A1 |
| 533 | ineligible серый + tooltip | A1 |
| 533 | eligible → POST + already-running notify | A2 |
| 533 | feature gate | A6 |
| 534 | пилюли (порядок/цвета/игнор) | A2, A3 |
| 534 | ring + displayName + View Details + раскрытие | B1 (клик по строке) |
| 534 | табы + summary + timeline + tooltip + multi-run | B1 |
| 534 | SUCCESS-таб (3/3, зелёный) | B2 |
| 535 | !MAPPED → Map CSV | A1 |
| 535 | MATCHED && !VALIDATED → Map CSV | A4 |
| 535 | eligible → displayName teal | A2 |
| 535 | else → скрыта | A5 |
| 535 | FAILED → Retry | B3 |
| 535 | disable во время POST + error notify | A2 |
