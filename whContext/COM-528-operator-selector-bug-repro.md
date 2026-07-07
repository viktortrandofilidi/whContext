# COM-528 (регрессия) — Measure: неверные операторы для top-level поля + «мёртвая» кнопка фильтра

Репорт (Patrick, Slack, «for monday», тэг @vtrandofilidi / @esokolov):

> The custom field builder no longer works properly after the addition of the target level.
> The operator selector always just shows the collection operators as opposed to the value
> operators, even if the value is on the top level. For example, `gender` is an account field
> but the only available selectors are the collection operators. Also, the filter button is
> shown even though it is a top-level field. When the button is pressed the filter isn't shown
> though — so I think it's just some internal state issue.

Скриншот: аккаунт **WorldDenver** (Nonprofit, Neon) → Datasets → **Neon** → New Custom Field → карточка
**Measure** («Measure giving» / «Calculate metric using») → Target Level = **ACCOUNT** → поле = **Gender** →
дропдаун оператора = `Last item / First item / Contains` (коллекционные), рядом висит кнопка фильтра.

---

## Что именно ломается (root cause)

Баг только в **Measure**-карточке. Файл:
`portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/condition-editors/MeasureConditionRowEditor.tsx`

1. **Операторы — строка 29:**
   ```ts
   const { operators, ... } = useOperatorCatalog(selectedFieldType, true);
   ```
   Второй аргумент `useOperatorCatalog(inputType, isList)` — это флаг «поле-коллекция». Он **захардкожен `true`**,
   поэтому каталог всегда оставляет только list-операторы (`operatorMatchesType` требует `firstParam.isList === isList`,
   см. `hooks/useOperatorCatalog.ts:23`). Для скалярного top-level поля (`Gender`, string) вместо value-операторов
   приходят `First item / Last item / Contains`.

2. **Кнопка фильтра — строка 40:**
   ```ts
   const canUseFilter = condition.fieldValue !== null;
   ```
   Кнопка показывается, как только выбрано любое поле — коллекция оно или нет. Но сама секция фильтра рендерится
   только при `condition.filter?.visible && filterCollectionPath` (строка 91), а для top-level скаляра
   `filterCollectionPath === null` (`findCollectionPath` вернёт `null`). Итог: кнопка есть, по клику — пусто. Это и есть
   «internal state issue» из репорта.

**Почему Flag/Label работают правильно** (эталон для фикса): они считают
`showAggregation = isListNatureField(options, fieldValue)` (`condition-editors/field-select-utils.ts:17`) и
- передают `showAggregation ? selectedFieldType : null` в `useOperatorCatalog` (`FlagConditionRowEditor.tsx:53-62`, `LabelConditionRowEditor.tsx:55-64`);
- гейтят `canUseFilter = showAggregation && fieldValue !== null` (`FlagConditionRowEditor.tsx:128`, `LabelConditionRowEditor.tsx:116`).

Target Level-механика **не виновата**: `rebaseFieldOptionsToLevel` (`placement/field-scope.ts:78-104`) корректно даёт
root-полям `isCollection:false, collectionPath:null`. Measure их просто игнорирует.

**Скоуп:** баг в Measure-карточке для **любого прямого скалярного поля** (не только root; per-item прямое поле тоже
пострадает), но репортится и воспроизводится проще всего на **ACCOUNT/root + Gender**. Flag и Label — не затронуты.

---

## Env — где воспроизводить (баг чисто фронтовый, пайплайн не нужен)

### A. Подтвердить за 0 setup (как у Патрика)
Открыть **DEV** portal-admin в браузере (тумблер «New Interface» = ON) → аккаунт **WorldDenver** →
левое меню **Dataset Management (Compass)** → датасет **Neon** → **New Custom Field**. Дальше — степы ниже.
Годится только чтобы увидеть баг, не чтобы чинить.

### B. Локальный фронт с hot-reload на данных DEV (для фикса) — рекомендую
```
cd match/portal-admin/frontend && pnpm dev            # :5173
```
`vite.config.ts` проксирует `/api/*` на `http://localhost:9080`. Чтобы взять реальные аккаунты (WorldDenver) и Compass-датасеты
(Neon) без локального бэкенда — временно переставить `target` в `vite.config.ts` на хост DEV portal-admin и залогиниться
на DEV в том же браузере (кука уйдёт через прокси, `changeOrigin: true`). Правим строки 29/40 — видим результат сразу.

### C. Полностью локально / offline
`AdminPortalMain` на `:9080` (profile `local`, порт из `application.properties`) + локальный hamster на `:8090`
(`compass.base-url=http://localhost:8090` по умолчанию) + сид демо-датасета person+gift из
`whContext/COM-528-demo-*`. Top-level скаляр здесь — **First Name / Last Name** (Gender в демо нет). Тяжело (сборка
hamster) — только если нужен полный офлайн. Target Level будет назван **Person**, не ACCOUNT (это тот же root-уровень).

### D. Самый быстрый цикл фикса — без бэкенда вообще
Компонентный/Vitest-тест на `MeasureConditionRowEditor` с одним top-level скаляром
(`FieldOption { isCollection:false, collectionPath:null }`): проверить, что (1) в дропдауне value-операторы, а не list;
(2) кнопка фильтра НЕ показывается. Это же станет regression-тестом к фиксу.

---

## Степы воспроизведения (UI)

1. Открыть аккаунт с Compass-датасетом, у которого есть **top-level скалярное поле**
   (DEV: WorldDenver → Neon → поле `Gender`; локальный демо: First Name / Last Name).
2. **Dataset Management (Compass)** → открыть датасет → **New Custom Field**.
3. «What are you trying to create?» → карточка **Measure** («Calculate metric using»).
4. «Custom Field Logic» → **Target Level = ACCOUNT** (дефолт, root-уровень — трогать не надо).
5. В строке «Calculate metric using» → выбрать поле **Gender** (top-level, `collectionPath: null`).
6. Открыть дропдаун **оператора** и посмотреть на кнопку-иконку фильтра справа от строки.

### Ожидаемо
- Операторы = **value-операторы** для скаляра (Equals, Greater than, Contains-as-value и т.п.).
- Кнопка фильтра **не показывается** (фильтр — только для агрегируемых коллекций, как в Flag/Label).

### Фактически (баг)
- Операторы = **коллекционные** (`First item / Last item / Contains`) — из-за захардкоженного `isList=true` (стр. 29).
- Кнопка фильтра **показана**, но по клику секция не появляется (`filterCollectionPath === null`, стр. 40 + 91).

### Контроль (не баг)
Повторить те же шаги на карточках **Flag** и **Label** с тем же top-level полем → операторы корректные (value),
кнопки фильтра нет. Подтверждает, что дефект локализован в Measure.

---

## Набросок фикса (2 строки, MeasureConditionRowEditor.tsx)
```ts
const isFieldACollection =
  condition.fieldValue !== null && isListNatureField(options, condition.fieldValue);

// стр. 29
const { operators, operatorsCatalog, isLoading } =
  useOperatorCatalog(isFieldACollection ? selectedFieldType : null, true);

// стр. 40
const canUseFilter = isFieldACollection;
```
(добавить импорт `isListNatureField` из `./field-select-utils.ts`; проверить `useAutoSelectFirstOperator`/сброс
оператора при смене поля). Пара regression-тестов — по варианту D.
