# COM-528 — демо на одном датасете: данные + пошаговые сценарии

Один датасет (классификации **person** и **gift**). Сценарии — пошаговые: на каждом шаге
конкретный выбор в UI, и сразу «→ Наблюдаем», как этот выбор влияет на работу визарда (доступные
поля, агрегация, какой тег/формула уйдёт, что попадёт в данные).

---

## 0. Платформенное ограничение

Gold-модель содержит один список — `transactions.items`. Классификация **gift** имеет тип
**DONATION** (`{DONATION, GIFT, PLEDGE}`), donation-root = `transaction`, поэтому gift ложится в
`transactions.items`. Полей `events` и вложенного `lineItems` нет.

→ Единственный per-item уровень — **Gift** (`transactions.items`). Примеры из комментариев про
line item (target+2) и events (соседний список) на этой модели вживую не показать — они в разделе 4
(иллюстративно). На датасете то же правило показываем парой **Person ↔ Gift**.

## 1. Датасет (blueprint)

- **person** (PERSON, корень): `id → person.id`, `firstName → person.name.firstName`, `lastName → person.name.lastName`.
- **gift** (DONATION, ребёнок person, `ONE_TO_MANY`, `placement.rootFieldName="transactions.items"`):
  `id → transaction.id`, `amount → transaction.amount`, `transactionType → transaction.transactionType`.

Target Level в визарде: **Person** и **Gift**. Поля gift: `Amount` (float), `Transaction Type` (string), `Id` (string).

## 2. Данные (seed) — `COM-528-demo-gold-records.jsonl`

| Person | id | Gift'ы (amount / transactionType) |
|---|---|---|
| Ada Lovelace | 1 | `txn-1-a`: 1500 / cash · `txn-1-b`: 75 / check |
| Ben Carter | 2 | `txn-2-a`: 2000 / cash |
| Cleo Diaz | 3 | — (нет gift'ов) |

---

## Сценарий 1 — как выбор Target Level меняет визард (центральный)

Цель: на одном и том же поле `Amount` показать, что **уровень меняет поведение** — на Gift поле
берётся напрямую, на Person требует агрегацию.

1.1 В блоке «What are you trying to create?» выбрать карточку **Flag**.
1.2 В «Custom Field Logic» → **Target Level** = **Gift**.
   → Наблюдаем: в строке условия дропдаун поля показывает поля **gift'а** (Amount, Transaction Type, Id); дропдауна агрегации **нет**.
1.3 В строке условия: поле = **Amount**, оператор = **Greater Than**, значение = **1000**.
   → Наблюдаем: формула = `amount > 1000`; тег, который уйдёт = `person.transactions.items.customAttributes[<name><boolean>]` (per-item).
1.4 Переключить **Target Level** = **Person** (не трогая условие).
   → Наблюдаем: поле `Amount` теперь помечено как требующее **агрегации** (появляется дропдаун агрегации SUM/MAX/…); прямой `amount > 1000` на Person недоступен — нужно выбрать агрегат.
1.5 Выбрать агрегат **MAX** для `Amount`, оператор **Greater Than**, значение **1000**.
   → Наблюдаем: формула = `agg:max(transactions.items, 'amount') > 1000`; тег = `person.customAttributes[<name><boolean>]` (root).

Вывод: один выбор поля + смена уровня = другая форма формулы, другой тег, другой контекст вычисления.

---

## Сценарий 2 — per-item Flag «Large Gift» (end-to-end на Gift)

2.1 Карточка **Flag**.
2.2 **Target Level** = **Gift**.
2.3 Условие: поле = **Amount**, оператор = **Greater Than**, значение = **1000**.
2.4 «Custom Field Details» → **Name** = `Large Gift`.
2.5 Нажать **Create Custom Field**.
   → Тег: `person.transactions.items.customAttributes[largeGift<boolean>]`; placement = PerItem.
   → Результат после пересчёта: на каждом gift'е появляется `largeGift` — Ada `txn-1-a`=**true**, `txn-1-b`=**false**; Ben `txn-2-a`=**true**; Cleo — gift'ов нет, ничего.

---

## Сценарий 3 — per-item цепочка «Gift Bucket» (ссылка на предыдущий CF)

3.1 Карточка **Label**.
3.2 **Target Level** = **Gift**.
3.3 Условие: поле = **Large Gift** (ранее созданный per-item CF), значение-метка = `large`; иначе `small`.
   → Наблюдаем: в пикере доступен ранее созданный per-item CF `largeGift` (он на том же уровне).
3.4 **Name** = `Gift Bucket`, **Create**.
   → Формула = `largeGift ? 'large' : 'small'`; тег = `person.transactions.items.customAttributes[giftBucket<string>]`.
   → Результат: Ada A=**large**, B=**small**; Ben C=**large**.

---

## Сценарий 4 — Person-агрегат «Total Giving» + цепочка

4.1 Карточка **Measure**.
4.2 **Target Level** = **Person**.
4.3 «Calculate metric using» → агрегат = **SUM**, поле = **Amount**.
   → Наблюдаем: на Person поле gift'а доступно только через агрегат (прямого `amount` нет).
4.4 **Name** = `Total Giving`, **Create**.
   → Формула = `agg:sum(transactions.items, 'amount')`; тег = `person.customAttributes[totalGiving<float>]`.
   → Результат: Ada=**1575**, Ben=**2000**, Cleo=**0**.
4.5 Новый CF: карточка **Flag**, **Target Level** = **Person**, условие: поле = **Total Giving**, оператор = **Greater Than**, значение = **1000**, **Name** = `Major Donor`, **Create**.
   → Наблюдаем: на Person доступен ранее созданный person-CF `totalGiving`.
   → Результат: Ada=**true**, Ben=**true**, Cleo=**false**.

---

## Сценарий 5 — дефолт и убранная Classification

5.1 Открыть **Create Custom Field**.
   → Наблюдаем: **Target Level** по умолчанию = **Person**.
5.2 Посмотреть секцию «Custom Field Details».
   → Наблюдаем: дропдаун **Classification отсутствует** (раньше был) — уровень задаётся через Target Level.

---

## Сценарий 6 — Known Field лочит уровень

6.1 В «Custom Field Details» → «Browse Known Fields».
6.2 Выбрать любое известное поле из каталога.
   → Наблюдаем: **Target Level** автоматически становится **Person** и **disabled** (заблокирован).
6.3 Нажать **Create**.
   → Уходит тег самого known-поля (его `tagPath`), а не сгенерированный из уровня.

---

## Сценарий 7 — редактирование (round-trip)

7.1 Открыть на редактирование per-item CF `Large Gift` (из сценария 2).
   → Наблюдаем: **Target Level** = **Gift** (восстановлен из сохранённого тега) и **disabled**; условия формулы заполнены из неё.
7.2 Открыть на редактирование `Total Giving` (person).
   → Наблюдаем: **Target Level** = **Person**, disabled.

---

## Сценарий 8 — ошибка «Name already exists»

8.1 Создавать новый CF, в **Name** ввести `Large Gift` (имя существующего).
   → Наблюдаем: под полем Name инлайн-ошибка «This custom field already exists, please try another name.»; кнопка **Create Custom Field** **disabled**.
8.2 Поменять Name на уникальное (`Large Gift 2`).
   → Наблюдаем: ошибка исчезает, Create снова активна.

---

## Сценарий 9 — сохранение значений при переключении

9.1 Карточка **Flag**, заполнить условие (Amount > 1000).
9.2 Переключиться на карточку **Measure**, затем обратно на **Flag**.
   → Наблюдаем: условие Flag (Amount > 1000) **сохранилось**.
9.3 На уровне **Person** заполнить условие, переключить **Target Level** = **Gift**, затем обратно на **Person**.
   → Наблюдаем: условия Person **сохранились** (а у Gift — свои, независимые).
9.4 Нажать **Create**.
   → Наблюдаем: после создания черновики сбрасываются.

---

## Сценарий 10 — formula editor НЕ защищён правилами визарда (поломка)

10.1 Нажать «Switch to formula editor →».
   → Наблюдаем: модалка с Name / Formula / Data Type / **Semantic Tags** (тег вводится руками; Target Level и проверок правил визарда нет).
10.2 **Name** = `Broken Per Gift`, **Data Type** = FLOAT.
10.3 **Semantic Tags** (вручную) = `person.transactions.items.customAttributes[brokenPerGift<float>]` (per-item).
10.4 **Formula** (вручную) = `agg:sum(transactions.items, 'amount')` (агрегат по всей коллекции).
10.5 Нажать **Create**.
   → Наблюдаем: создание **проходит** — клиентской проверки нет.
   → Результат после пересчёта: `brokenPerGift` **пусто на всех gift'ах** — per-item контекст = один gift, в нём нет всей коллекции `transactions`, формула невычислима.

Контраст: в визарде это собрать нельзя — на Gift агрегация выключена, а `sum(transactions)` это
Person-уровень с root-тегом.

---

## 4. Иллюстративно (вне текущей gold-модели) — правило «свой уровень + один глубже»

Требуют схемы person → gift → **line item** и **events**, которых в модели нет. На слайде:

- VALID: `person.age > 50`
- VALID: `person.age > 50 && avg(gift) > 100` (gift = target+1, агрегат)
- INVALID: `person.age > 50 && count(lineItem) > 10` (lineItem = target+2)
- VALID: `count(events) > 5 && avg(gift) > 100` (оба — прямые дети person)
- INVALID: `events.location == 'Boulder' && gift.amount > 50` (два разных списка сырьём)
- INVALID: `events.state == 'CO' && person.age > 50` (вверх к родителю с event-уровня)
- VALID: `count(events.state == 'CO') && person.age > 50` (events свёрнут агрегатом на person)

На датасете то же правило — пара Person ↔ Gift (сценарий 1): на Gift поля напрямую, на Person — только агрегатом.

## 5. Инженерное подтверждение / вне скоупа

- `pnpm exec vitest run` → ~50 юнит-тестов на placement, полный прогон 499 зелёных.
- Formula editor без изменений (нет Target Level, тег руками, без клиентской валидации правил визарда — сценарий 10).
- Typed-field placement (`…transactions.items.isClosedWon`) имеет билдер тега, но UI-контрола нет.
