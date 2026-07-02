# COM-528 — UI-сценарии без прогона пайплайна

Показываем, что визард **генерит корректный semantic tag** и **не даёт собрать невалидную формулу**, а
через **formula editor** невалидный тег сделать можно (escape-hatch). Пересчёт/обогащение НЕ запускаем —
наблюдаем по запросу create и его ответу.

Датасет: классификации **People** (person) и **Gifts** (donation → `transactions.items`).

## Как наблюдать (без пайплайна)

Открыть DevTools → Network. При нажатии **Create Custom Field** идёт
`POST /api/compass/proxy/accounts/1/datasets/demo-dataset/custom-field-definitions`.
Смотрим:
- **тело запроса** → поле `semanticTags` (что именно UI сгенерил);
- **статус ответа** → `2xx` = бэкенд принял тег (placement валиден), `4xx` = бэкенд отверг (невалидная форма тега).

Это и есть проверка: визард всегда шлёт корректный тег → 2xx; невалидное визард просто не даёт собрать.
Recalc не нужен — данные не проверяем.

---

## Сценарий 1 — корректная генерация тегов (по уровню и типу)

1.1 Person + **Measure**: «Calculate metric using» SUM(`Amount`); Name = `Total Giving`; Create.
   → `semanticTags: ["person.customAttributes[totalGiving<float>]"]` — root-уровень, binding `<float>`.
1.2 Gift + **Flag**: `Amount` Greater than `1000`; Name = `Large Gift`; Create.
   → `semanticTags: ["person.transactions.items.customAttributes[largeGift<boolean>]"]` — per-item, `<boolean>`.
1.3 Gift + **Label**: метка по `Transaction Type`; Name = `Gift Bucket`; Create.
   → `semanticTags: ["person.transactions.items.customAttributes[giftBucket<string>]"]` — `<string>`.

Вывод: префикс задаётся уровнем (`person` vs `person.transactions.items`), binding — типом (boolean/float/string),
key — из имени (camelCase). Всё это видно прямо в payload.

---

## Сценарий 2 — визард НЕ даёт собрать невалидное

2.1 Target Level = **Gift**, поле `Amount`.
   → Наблюдаем: дропдауна агрегации **нет** — `amount` берётся напрямую. Нельзя засунуть агрегат в per-item тег.
2.2 Target Level = **Person**, поле `Amount`.
   → Наблюдаем: у `amount` **обязательна** агрегация (SUM/MAX/…). Нельзя сослаться на сырое поле gift'а на person.
2.3 На обоих уровнях открыть дропдаун поля.
   → Наблюдаем: предлагаются только поля, допустимые для уровня (своё + на один глубже). Поля вне scope
     (родитель / соседний список / на два уровня глубже) **в списке отсутствуют** → сослаться на них нельзя.
     (На этом датасете модель плоская — один список gift'ов; недопустимых полей просто нет в каталоге.)
2.4 В **Name** ввести имя уже существующего поля (напр. `Large Gift` из 1.2).
   → Наблюдаем: инлайн-ошибка «This custom field already exists…»; кнопка **Create** disabled. Дубликат не создать.
2.5 Собрать формулу, чьё возвращаемое значение не совпадает с выбранной карточкой (напр. Flag, но формула
   возвращает число).
   → Наблюдаем: алерт о несовпадении типа; **Create** disabled.

Вывод: невалидные комбинации физически не собираются — не тем, что бэкенд отвергнет, а тем, что UI их не предлагает /
блокирует Create.

---

## Сценарий 3 — formula editor: невалидный тег СДЕЛАТЬ можно (escape-hatch)

3.1 «Switch to formula editor →». Name = `Broken Per Gift`, Data Type = FLOAT.
   Semantic Tags (вручную) = `person.transactions.items.customAttributes[brokenPerGift<float>]` (per-item).
   Formula (вручную) = `agg:sum(transactions.items, 'amount')` (агрегат по всей коллекции). Create.
   → Наблюдаем: запрос проходит (**2xx**) — клиентской проверки правил визарда нет, а **placement тега валиден**,
     поэтому бэкенд принимает. Рассогласование «per-item тег + агрегатная формула» проявится только на пересчёте
     (поле будет пустым — в контексте одного gift'а нет всей коллекции). Пайплайн не гоняем — фиксируем, что
     **визард такое не дал бы собрать, а formula editor дал**.
3.2 Тот же редактор, Semantic Tags = `revenue` (или `person.unknown.items.customAttributes[x<string>]`). Create.
   → Наблюдаем: бэкенд **отвергает** (**4xx**, ошибка про невалидный тег). То есть форму тега сервер всё же
     проверяет, но правила визарда (уровень / агрегация) — нет.

Вывод: гарантии «корректный тег + согласованная формула» дают **только визард**; formula editor — сырой путь
без этих рельсов (намеренно вне скоупа COM-528).

---

## Сценарий 4 — прочие UI-кейсы

4.1 Открыть Create CF → Target Level по умолчанию = **Person**.
4.2 «Custom Field Details» → дропдаун **Classification отсутствует** (уровень задаётся через Target Level).
4.3 Заполнить условия в **Flag** → переключиться на **Measure** → обратно на **Flag**: условия Flag **сохранились**.
4.4 На **Person** заполнить условие → сменить Target Level на **Gift** → обратно на **Person**: условия Person
   **сохранились** (у Gift — свои). После Create черновики сбрасываются.
4.5 «Browse Known Fields» → выбрать поле: Target Level → **Person** и **disabled**; на Create уходит тег known-поля.
4.6 Открыть существующий per-item CF на редактирование: Target Level = **Gift** (распарсен из сохранённого тега),
   селектор **disabled**; условия восстановлены из формулы.
4.7 Косметика по макету: Target Level — узкий инпут **внутри** секции «Custom Field Logic»; у дропдаунов двойной
   шеврон (вверх-вниз).

---

## Что НЕ показываем здесь

- Реальные данные после пересчёта (per-item значения, fill-rate) — это отдельный файл `COM-528-demo-scenarios.md`
  (требует прогона пайплайна/обогащения).
