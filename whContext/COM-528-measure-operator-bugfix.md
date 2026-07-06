# COM-528 — баг оператор-селектора в Measure после Target Level (+ фикс)

Регрессия, найденная после добавления **Target Level** в визард кастомных полей (стори COM-528, PR #5548
в `match`). Репорт от @esokolov: «operator selector always shows the collection operators instead of value
operators even for a top-level field; filter button shows but does nothing».

## TL;DR
- **Где:** вкладка **Measure** («Measure giving») визарда кастомных полей, `match/portal-admin`.
- **Симптом:** для скалярного top-level поля (напр. gender / в демо — `First Name`) оператор-селектор
  показывает только **агрегационные (collection) операторы** («Last item», «First item», «Contains»)
  вместо value-операторов; кнопка **фильтра** появляется, но по клику ничего не открывает.
- **Причина:** COM-528 не менял Measure-редактор — он поменял, какие поля попадают в пикер. Раньше
  «measure = агрегация над коллекцией», поэтому `MeasureConditionRowEditor` жёстко просит collection-операторы
  (`useOperatorCatalog(type, true)`) и показывает кнопку фильтра для любого поля. Target Level добавил в тот же
  пикер **at-level скалярные** поля (напр. person-уровня), которые метрикой быть не могут.
- **Фикс:** пикер Measure строим только из агрегируемых (`isCollection`) полей — скаляры не появляются,
  и обе проблемы исчезают «по построению». Один файл, одна правка.

## Механика (почему только Measure)
- `showAggregation = isListNatureField(options, field)` = `field.isCollection`.
- **Flag/Label** гейтят на `showAggregation`: для скалярного поля показывают value-операторы (`isList:false`)
  и прячут фильтр → корректно.
- **Measure** такой развилки не имеет: единственный operator-dropdown всегда строится из
  `useOperatorCatalog(selectedFieldType, /*isList*/ true)` (collection-операторы), а
  `canUseFilter = condition.fieldValue !== null` (фильтр для любого поля). При этом сама filter-секция
  рендерится только если `filterCollectionPath != null`, а у скаляра он `null` → кнопка есть, секции нет.
- Контракт подтверждает, что скаляр — невалидная метрика: `buildMeasureFormulaAst` бросает
  `"Field is not aggregatable"`, если у поля нет `isCollection/collectionPath/leafSegment`.

Баговые строки (29, 40) написаны ещё в COM-336 (Evgeny Sokolov, 28.04.2026) — тогда были корректны;
COM-528 их «обнажил», сменив в `CreateCustomFieldPage` проброс `options={fieldOptions}` (сырые) на
`options={scopedFieldOptions}` = `rebaseFieldOptionsToLevel(...)`, который включает at-level скаляры.

## Фикс (в репозитории `match`)
Файл: `portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/condition-editors/MeasureConditionRowEditor.tsx`

```diff
-  const fieldSelectData = useMemo(() => buildFieldSelectData(options), [options]);
+  // A measure is always an aggregation over a collection (see buildMeasureFormulaAst), so only
+  // aggregatable fields are valid choices. At-level scalar fields (e.g. an account's own gender,
+  // surfaced by the target-level picker) are excluded rather than offered with collection
+  // operators and a filter they cannot use.
+  const aggregatableOptions = useMemo(() => options.filter((option) => option.isCollection), [options]);
+  const fieldSelectData = useMemo(() => buildFieldSelectData(aggregatableOptions), [aggregatableOptions]);
```

Полный `options` осознанно оставлен для `findFieldDataType`/`findCollectionPath` и `FilterSectionEditor`
(там нужны sibling-поля коллекции для filter-строк). Строки 29/40 не трогаем — после фильтрации пикера они
корректны по построению.

Перед коммитом (в `match`): `cd portal-admin/frontend && pnpm prettier --write <файл>`, затем `pnpm test`.

## Затронутость
- **portal-admin Measure** — починено этим фиксом.
- **Flag / Label** — не затронуты (у них есть развилка по `showAggregation`).
- **contextual-analytics** — та же строка `useOperatorCatalog(selectedFieldType, true)` в его копии
  `MeasureConditionRowEditor`, но Target Level там ещё нет → сейчас латентно. Заведена отдельная задача.

---

## Демо-датасет для проверки
Совпадает с [COM-528-ui-scenarios.md](COM-528-ui-scenarios.md) / [COM-528-demo-scenarios.md](COM-528-demo-scenarios.md):
- account `1`, dataset `demo-dataset`; классификации **person** и **gift** (`transactions.items`).
- **person** (скаляры): `First Name`, `Last Name`, `Id` (аналог gender из репорта).
- **gift** (коллекция, one-deeper от person): `Amount` (float), `Transaction Type` (string), `Id`.
- URL визарда: `/accounts/1/datasets-compass/demo-dataset/custom-fields/create`

## A. Воспроизвести баг (код БЕЗ фикса)
1. Открыть визард (URL выше).
2. Карточка типа **«Measure giving»**.
3. **Target Level = Person** (по умолчанию).
4. Селект **Field** → выбрать **First Name** (person-скаляр).
5. **Ожидаемо (баг):**
   - **Operator** показывает только collection-операторы («Last item», «First item», «Contains»);
   - справа появляется иконка **фильтра**, по клику ничего не открывается.

## B. Проверить фикс (код С фиксом)
1. Визард → **«Measure giving»** → **Target Level = Person**.
2. Открыть **Field**:
   - ✅ `First Name` / `Last Name` / `Id` (person-скаляры) в списке **отсутствуют**;
   - ✅ доступны только агрегируемые gift-поля (`Amount`, `Transaction Type`).
3. Выбрать **Amount**:
   - ✅ **Operator** = корректные агрегаты (SUM/MAX/…);
   - ✅ иконка фильтра **работает** — по клику раскрывается секция фильтра.
4. Переключить **Target Level = Gift**:
   - ✅ пикер Measure **пуст** — у gift нет коллекции на уровень глубже (line items в демо нет),
     значит валидных метрик на этом уровне нет (ожидаемо, а не баг).
5. **Регресс Flag/Label** (не должны меняться): карточка **«Label donors»** (или Flag) →
   **Target Level = Person** → **Field = First Name**:
   - ✅ поле выбирается; **Operator = value-операторы** (equals/contains/…); фантомной кнопки фильтра нет.
