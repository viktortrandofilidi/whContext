# COM-528 — Frontend-Only Analysis: Making the Custom-Field Wizard Incapable of Building an Impossible Formula

**Scope constraint (restated up front): FRONTEND ONLY.** All work lives in `match/portal-admin/frontend`. **No `hamster` changes anywhere** — not to the operator catalog, not to aggregation return types, not to any REST contract. Where a correct fix would require a hamster change (notably `agg:first`/`agg:last` extracted-path typing, and any new COUNT/SIZE aggregation), it is called out as a **deferred known limitation**, not implemented here. This is analysis + plan; no code was written.

All file paths are relative to `match/portal-admin/frontend/src/domain/datasets/` unless given as absolute. Absolute roots are listed at the end of each fix.

---

## 0. Baseline: how enforcement is layered today

Three enforcement layers exist, in order of when they act:

1. **Field-scope filter (already shipped).** `CreateCustomFieldPage` rebases every field option to the selected Target Level via `rebaseFieldOptionsToLevel` (`placement/field-scope.ts:78-104`), which internally calls `partitionFieldsByLevel` / `scopeOf` (`field-scope.ts:29-66`). This drops **deeper-than-one (target+2), sibling-branch, and parent/above-level** fields, marks own fields `isCollection:false, collectionPath:null` (`field-scope.ts:83-89`) and one-deeper lists `isCollection:true` (`field-scope.ts:91-101`). This is **prevention-by-omission** and closes R5, R7, R9, R11 structurally, for all three cards, upstream of the editors. **Verified against `scopeOf`:** target+2 dropped in both branches; sibling lists at a perItem level dropped via the `startsWith(path + '.')` guard whose trailing `.` correctly avoids string-prefix false positives (`transactionsArchive.items` is *not* admitted under `transactions.items`); parent/ancestor fields from a child level dropped. Container (1:1 OBJECT) nesting is depth-transparent because `listDepth` counts only `items` segments, so `person.household.members.items.x` is still correctly `oneDeeper`.

2. **Per-row operator filtering.** `useOperatorCatalog(inputType, isList)` (`hooks/useOperatorCatalog.ts:45-83`) keeps a catalog op only if `firstParam.isList === isList` and `firstParam.acceptedTypes.includes(inputType)` (`useOperatorCatalog.ts:23-28`); `agg:filter` is hidden (`useOperatorCatalog.ts:16`). Comparison ops go through `getAllowedComparisonOperators` (`condition-editors/comparison-operators.ts:15-47`).

3. **Create gate.** `isCreateDisabled` in `CreateCustomFieldPage.tsx:389-401` = `wizardCategoryMismatch || knownFieldTypeMismatch || nameCollision || (per-type completeness)`. `wizardCategoryMismatch` (`CreateCustomFieldPage.tsx:251-252`) infers the built AST's return type and requires `mapReturnTypeToCustomFieldType(inferred) === selectedType`.

**Category mapping (verified, `mappers/formula-resolver.ts:17-20`):** BOOLEAN→FLAG; STRING **or** ENUM→LABEL; **everything else (FLOAT / INTEGER / DATE / UNKNOWN)→MEASURE**. Note two consequences that matter below: **DATE→MEASURE** (a legitimate Measure category member with no aggregation path), and **UNKNOWN→MEASURE** (the fallback that a bare `Identifier` currently lands in).

The gaps below all live in layers 2–3, concentrated in the **Measure** card, because Flag/Label derive `isList` from the field (`showAggregation`) while Measure hardcodes it and pre-filters the field list. **Flag and Label are type-safe by construction** (Flag always emits a comparison/logical `BinaryExpression` or `!` `UnaryExpression` → BOOLEAN; Label always emits a `ConditionalExpression` with a string-literal consequent → STRING), so `inferReturnType` is pinned to the card's category regardless of field/operator. The entire type-mismatch surface is the Measure card.

---

## 1. VALIDITY MATRIX

Cells describe: **operators offered** (by first-param accepted type + isList), **formula return type**, and **category match**. "Dropped" = never reaches the editor because `partitionFieldsByLevel` removed it. **"Dead-end"** = the field is *selectable* but no valid operator/formula can be produced under the current + planned rules — the new class the adversarial pass surfaced.

Type→category via `mapReturnTypeToCustomFieldType` (`formula-resolver.ts:17-20`).

| Card ↓ / Relationship → | **Own-level scalar** (`isCollection:false`) | **Target+1 collection** (`isCollection:true`, one `items` deeper) | **Deeper (target+2)** | **Cross-list sibling** | **Parent / above-level** |
|---|---|---|---|---|---|
| **Flag** (want BOOLEAN) | Offered. `showAggregation=false` → no agg dropdown (`FlagConditionRowEditor.tsx:53-56`). Comparison ops from `{inputTypes:[fieldType], isList:false}` (`:82`) → `jexl:eq/ne/lt/le/gt/ge/strict_eq/…` (all return BOOLEAN). **RT=BOOLEAN ✓ FLAG.** | Offered. `showAggregation=true` → agg dropdown `useOperatorCatalog(fieldType, isList=true)` (`:62`) → `agg:sum/avg/min/max/first/last` + `col:contains`. Comparison then applied to agg's `returnTypes`; comparison forces the row to BOOLEAN. **RT=BOOLEAN ✓ FLAG.** | **Dropped** (`field-scope.ts:44`). ✓ (R5) | **Dropped** (perItem `startsWith` guard). ✓ (R7) | **Dropped** (`scopeOf`). ✓ (R9) |
| **Label** (want STRING) | Offered. Terminal is `test ? 'label' : …` folded to STRING (`label-builder.ts:165-188`). `showAggregation=false`. **RT=STRING ✓ LABEL.** | Offered, agg list extra-filtered to `supportsManualOperatorInputs && parameters.length<=2` (`LabelConditionRowEditor.tsx:66-79`). Terminal STRING. Filter rows scoped to same collection (`field-select-utils.ts:30-38`). **RT=STRING ✓ LABEL.** | **Dropped.** ✓ | **Dropped.** ✓ | **Dropped.** ✓ |
| **Measure** (want FLOAT/INTEGER; DATE is a category member but has no build path — see GAP-5) | **Numeric scalar: EXCLUDED today** — `aggregatableOptions = options.filter(o=>o.isCollection)` (`MeasureConditionRowEditor.tsx:26`). Cannot build a valid numeric own-scalar. ✗ **GAP-1.** **Non-numeric scalar (STRING/BOOL/ENUM/DATE):** correctly *should not* be a Measure; today excluded (side effect of GAP-1's over-filter). Once GAP-1 lifts the filter naively, these become selectable **dead-ends**. ✗ **GAP-4.** | **Numeric leaf:** offered; but `useOperatorCatalog(fieldType, isList=true)` is **hardcoded** (`:34`) and auto-selects the first op (`:41-43`), which may be `agg:first/last` → **RT=STRING → LABEL ≠ MEASURE**. ✗ **GAP-2.** Correct case (`agg:sum/avg/min/max` over numeric leaf) → RT=FLOAT/INTEGER ✓ MEASURE. **Non-numeric leaf (STRING/BOOL/DATE list):** `rebaseFieldOptionsToLevel` marks it `isCollection:true` regardless of leaf type (`field-scope.ts:91-101`), so it stays in `aggregatableOptions`; after GAP-2 filters the dropdown to numeric-returning ops, the operator list is **empty → dead-end**. ✗ **GAP-4.** | **Dropped.** ✓ | **Dropped.** ✓ | **Dropped.** ✓ |

Key reading: the Measure column now shows **two distinct defect classes** — (a) the original *over-block / dead-end mismatch* on numeric fields (GAP-1, GAP-2), and (b) a *newly-surfaced dead-end on non-numeric fields* that GAP-1/GAP-2 do **not** close because they filter operators but never filter the **field list** by leaf type (GAP-4). GAP-5 (DATE) is a valid category member with no build path at all.

---

## 2. OPERATOR-BY-CATEGORY (allow / deny, with reasons)

Return types below are the catalog's `returnTypes[0]`, which is what `inferReturnType` uses for `FunctionCall` nodes (`formula-type-checker.ts:22-26`). Category via `mapReturnTypeToCustomFieldType`.

**There is no COUNT / SIZE aggregation reachable by the wizard.** The catalog exposes only `agg:sum/avg/min/max/first/last/filter` and `col:contains` at `isList=true`. `jexl:size` (list length) has an `isList=false` first param, so `operatorMatchesType` (`useOperatorCatalog.ts:23-28`) never surfaces it when the aggregation dropdown passes `isList=true`; there is no `agg:count`. **Any formula requiring list-length (a COUNT) is therefore not wizard-buildable, on any card.** This corrects §4/§5 below and removes the "COUNT" token from the Measure allow-list narrative.

### Flag (terminal must be BOOLEAN)

The terminal is always a comparison or a logical join, so the operator that fixes the category is the **comparison op**, not the aggregation. `getAllowedComparisonOperators` restricts to `returnsOnlyBoolean` + `COMPARISON_OPS` + 2-param + non-negative + `supportsManualOperatorInputs` (`comparison-operators.ts:27-37`).

- **Allow (comparison layer):** `jexl:eq`, `jexl:strict_eq`, `jexl:lt`, `jexl:le`, `jexl:gt`, `jexl:ge`, `jexl:matches_or_in`, `jexl:starts_with`, `jexl:ends_with` — all `BOOLEAN`. Negatives (`ne`, `strict_ne`, `not_*`, `!~`, `!^`, `!$`) are excluded by `isNegativeComparisonOperator` (`comparison-operators.ts:11-13`); negation is expressed via the `NEGATION_OPTIONS` select. Correct and intentional.
- **Allow (aggregation layer, only when field is target+1):** `agg:sum/avg/min/max` (numeric collapse), and — fine because a comparison follows — `agg:first`, `agg:last`, `col:contains`. The subsequent comparison forces BOOLEAN, so no return-type filter is needed here.
- **Deny:** `agg:filter` (hidden globally). All non-list-first-param scalar ops (denied because `isList=true` is passed).

### Label (terminal must be STRING)

Same comparison allow-list for building the test. The terminal STRING comes from the ternary consequent, not from an operator.

- **Allow (aggregation layer):** `agg:sum/avg/min/max/first/last` and `col:contains`, restricted to `supportsManualOperatorInputs && parameters.length<=2` (`LabelConditionRowEditor.tsx:66-79`). A boolean-returning aggregation (e.g. `col:contains`) can act as the whole test (`label-row-layout.ts:20-52`).
- **Deny:** `agg:filter` (hidden); any op needing an inner `condition` param or a list 2nd param.

### Measure (terminal must be numeric: FLOAT or INTEGER)

This is the card whose operator set is not currently return-type-filtered and is the crux of the story.

**Allow-list (returnTypes[0] ∈ {FLOAT, INTEGER}, first-param isList=true — the only ops that both fit a Measure and consume a collection):**

| key | returnTypes[0] | why allowed |
|---|---|---|
| `agg:sum` | FLOAT/INTEGER | numeric collapse of numeric leaf |
| `agg:avg` | FLOAT/INTEGER | numeric collapse |
| `agg:min` | FLOAT/INTEGER | numeric collapse |
| `agg:max` | FLOAT/INTEGER | numeric collapse |

There is **no COUNT** in this list — the catalog does not expose one (see the note above).

Plus, for the **own-scalar numeric** case (GAP-1 fix): a **direct identifier reference** to a numeric field — no operator. This requires resolver + builder + type-checker work (see GAP-1) because a bare `Identifier` currently infers UNKNOWN (`formula-type-checker.ts:19-20`) and the Measure resolver rejects non-function-call ASTs (`measure-resolver.ts:63`).

**Deny-list (with reason):**

| key | returnTypes[0] | deny reason |
|---|---|---|
| `agg:first` | OBJECT → STRING (sorted `returnSchemaTypes`) | `inferReturnType` reads `returnTypes[0]`=STRING → LABEL ≠ MEASURE. Auto-selected today → dead Create button. |
| `agg:last` | OBJECT → STRING | same as `agg:first`. |
| `col:contains` | BOOLEAN | → FLAG, not MEASURE. |
| `agg:filter` | OBJECT, isList=true | globally hidden; produces a list, not a scalar. |
| `regex:extractAll` | STRING, isList=true | list output; wrong category. |

**KNOWN LIMITATION — DEFERRED (needs a hamster change; out of scope for COM-528):** `agg:first`/`agg:last` **with a `path`** argument extract the leaf's real type at runtime (a number for `agg:first(transactions.items,'amount')`), but the catalog hardcodes `returnType=OBJECT` (`extractsPathType:true`). The frontend cannot know these are numeric, so a genuinely-numeric "first/last gift amount" **Measure is denied from the wizard** and is reachable only via the formula-editor escape hatch. Correctly typing first/last-with-path requires **catalog-side extracted-path type inference in hamster** — deferred. (Note: first/last *without* a path return the whole item OBJECT and are correctly non-Measure regardless — the deferred case is specifically first/last *with* a numeric/date path.)

---

## 3. GAP LIST

Deduped from the frontend agent's findings, the matrix, and the adversarial pass. **All fixes are frontend-only.**

### GAP-1 — Measure card cannot express a top-level (or per-item) numeric own-scalar, and has no resolver/builder path to do so

- **Severity:** High (wrongly blocks a legitimate, common case; violates the Measure category intent and R3).
- **Repro:** Target Level = Person → Measure card → open the Field dropdown. A person-level numeric scalar (e.g. `lifetimeValue` FLOAT, `lifetimeGiftCount` INTEGER) is **absent**. User is stuck; no formula is buildable.
- **Bad/blocked outcome:** The valid Measure `lifetimeValue` (direct numeric reference) can never be assembled.
- **Rule violated:** Category-map sends a numeric scalar → MEASURE (`formula-resolver.ts:17-20`); own/at-level fields must be usable directly. `MeasureConditionRowEditor.tsx:26` (`options.filter(o=>o.isCollection)`) removes them.
- **Fix (frontend), three parts — all three are required or the field will not round-trip on edit (R14):**
  1. **Editor:** in `condition-editors/MeasureConditionRowEditor.tsx`, stop pre-filtering to collections. Offer scoped options **filtered to numeric-or-unknown leaves** (see GAP-4 — do *not* offer STRING/BOOL/ENUM/DATE scalars), compute `isFieldACollection = condition.fieldValue !== null && isListNatureField(options, condition.fieldValue)` (mirror Flag `:53-56`), and pass `useOperatorCatalog(isFieldACollection ? selectedFieldType : null, isFieldACollection)` so a scalar yields no aggregation dropdown.
  2. **Builder:** in `mappers/measure-builder.ts:16`, add a scalar branch — when `!field.isCollection`, emit a direct `Identifier` node instead of throwing. **Also:** the completeness gate must not require `operatorId` for a scalar row (a bare scalar has no operator). Update `buildMeasureFormulaAst`'s guard and the corresponding `isCreateDisabled` Measure completeness check (`CreateCustomFieldPage.tsx:391-393`) so a scalar Measure is "complete" with just `fieldValue`.
  3. **Resolver:** in `mappers/measure-resolver.ts`, add an `Identifier` branch. Today `resolve` returns `unresolvable` for any non-`FunctionCall` AST (`measure-resolver.ts:63`), so a saved scalar Measure would fail edit round-trip and drop the user into the raw formula editor — the exact escape hatch the story exists to close. The resolver must map a bare scoped `Identifier` back into a `MeasureConditionRow` with `operatorId: null`.
  4. **Typing:** extend `inferReturnType`'s `Identifier` case (`formula-type-checker.ts:19-20`) to look the field up in the scoped options and return its `dataType` (instead of UNKNOWN), so the persisted `dataType` and tag binding are correct and the UNKNOWN→MEASURE fallback edge is removed. (This is the "option (a)" choice; see Open Question 3.)
- **Files (absolute):**
  - `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/condition-editors/MeasureConditionRowEditor.tsx:26,34,45`
  - `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/mappers/measure-builder.ts:16`
  - `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/mappers/measure-resolver.ts:63`
  - `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/mappers/formula-type-checker.ts:19-20`
  - `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/CreateCustomFieldPage.tsx:391-393`

### GAP-2 — Measure card offers and auto-selects non-numeric aggregations, producing a dead-end LABEL/FLAG formula

- **Severity:** High (Measure can assemble a non-Measure formula; only feedback is a generic "returns Text" alert with no in-card recovery; violates R10 / category integrity).
- **Repro:** Target Level = Person → Measure → pick a target+1 **STRING** list field (e.g. `transactions.items.status`). `useAutoSelectFirstOperator(true,…)` (`MeasureConditionRowEditor.tsx:41-43`) auto-picks the first collection op, which can be `agg:first`. Every `isCreateDisabled` sub-check passes, yet `wizardCategoryMismatch` (`:251`) disables Create with only a generic alert.
- **Bad formula:** `agg:first(transactions.items,'status')` → `inferReturnType`=STRING → LABEL ≠ Measure. Dead Create button, no in-card fix.
- **Rule violated:** R10 (terminal type must match card) + Measure category definition.
- **Fix (frontend):** in `condition-editors/MeasureConditionRowEditor.tsx`, filter `operators` to those whose return types intersect `{INTEGER, FLOAT}` before building `operatorSelectData` and before auto-select. Use `getReturnTypes(op.id)` from `useOperatorCatalog` (`useOperatorCatalog.ts:67-74`) or `resolveOperatorOutputTypes` (`mappers/catalog-utils.ts:32-38`). This removes `agg:first/last`, `col:contains` so auto-select can only land on `agg:sum/avg/min/max`. Encodes the first/last KNOWN LIMITATION.
- **Files (absolute):**
  - `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/condition-editors/MeasureConditionRowEditor.tsx:34,36-43`
  - `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/hooks/useOperatorCatalog.ts:67-74`
  - `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/mappers/catalog-utils.ts:32-38`

### GAP-3 — Measure filter button renders for a field before an aggregation is meaningful (residual R18 pattern)

- **Severity:** Low-Medium (cosmetic once GAP-1 lands; a real correctness issue if own-scalars are added without gating the filter).
- **Repro (post-GAP-1):** selecting an own-scalar sets `canUseFilter = condition.fieldValue !== null` (`MeasureConditionRowEditor.tsx:45`) → filter button renders, but `filterCollectionPath` is null (`:46-49`) so the section never opens — the "internal state issue" R18 documents.
- **Rule violated:** R18 — filter only on aggregatable (oneDeeper) collections. Flag/Label gate on `showAggregation && fieldValue!==null` (`FlagConditionRowEditor.tsx:128`).
- **Fix (frontend):** change `canUseFilter` in `MeasureConditionRowEditor.tsx:45` to `isFieldACollection && condition.fieldValue !== null` (using GAP-1's `isFieldACollection`). Mirrors Flag exactly.
- **File (absolute):** `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/condition-editors/MeasureConditionRowEditor.tsx:45`

### GAP-4 — Measure field picker is not filtered by leaf type, so non-numeric fields remain selectable and dead-end (NEW — surfaced by the adversarial pass)

- **Severity:** High (GAP-1 and GAP-2 as originally scoped *introduce* this; they filter operators but never filter the field list, so the picker still offers fields that can never form a Measure).
- **Repro A (collection):** Target Level = Person → Measure → `transactions.items.status` (STRING one-deeper list). `rebaseFieldOptionsToLevel` marks it `isCollection:true` regardless of leaf type (`field-scope.ts:91-101`), so it stays in `aggregatableOptions`. Its only compatible ops are `agg:first/last/col:contains` — exactly the ops GAP-2 strips. Result: **empty operator dropdown**, Create stays disabled, no explanation.
- **Repro B (scalar):** after GAP-1 lifts the collection-only filter naively, `person.gender` (STRING own-scalar) becomes selectable → `inferReturnType`=STRING → LABEL ≠ MEASURE → `wizardCategoryMismatch` → disabled Create with only the generic red alert. GAP-1 would re-create, on the scalar side, exactly the dead-end GAP-2 fixes on the collection side.
- **Rule violated:** R10 + Measure category integrity + the story's "prevention-by-omission" principle (an impossible selection should not be offered).
- **Fix (frontend):** filter the **Measure field list itself** by leaf type before building `fieldSelectData`. Keep a field only if its effective leaf `dataType` is numeric (FLOAT/INTEGER) or UNKNOWN — for own-scalars use the field's `dataType`; for one-deeper collections use the leaf's `dataType`. STRING/BOOLEAN/ENUM (and DATE, see GAP-5) fields are dropped from the Measure picker entirely. This makes both GAP-1 and GAP-2 sound (no numeric-side dead-end, no non-numeric-side dead-end) and restores prevention-by-omission for the Measure card.
- **Files (absolute):**
  - `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/condition-editors/MeasureConditionRowEditor.tsx:26`
  - `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/condition-editors/field-select-utils.ts` (leaf-type lookup helper)

### GAP-5 — DATE Measures are silently unbuildable (NEW — surfaced by the adversarial pass); document as limitation

- **Severity:** Low-Medium (a legitimate category member with no build path; needs to be an explicit decision, not a silent hole).
- **Detail:** `mapReturnTypeToCustomFieldType` sends **DATE→MEASURE** (`formula-resolver.ts:17-20`), so a DATE is a valid Measure category. But: (a) no DATE-returning list aggregation exists (`agg:min/max` accept only `[FLOAT,INTEGER]`; `date:*` ops are scalar-first-param and never offered at `isList=true`); and (b) GAP-1's bare-`Identifier` path would still fail without the resolver branch, and even with it there is no aggregation for a DATE *collection*.
- **Decision (frontend):** treat DATE as **not wizard-buildable as a Measure for now** and exclude DATE from the Measure field picker (folded into GAP-4's leaf-type filter). A "most-recent gift date" Measure would need either the deferred `agg:first/last`-with-path typing (hamster) or a dedicated DATE aggregation (hamster) — **out of scope for COM-528**. Document, do not silently drop.
- **File (absolute):** covered by GAP-4's filter — `/Users/viktortrandofilidi/IdeaProjects/wf/match/portal-admin/frontend/src/domain/datasets/components/custom-field-definitions/condition-editors/MeasureConditionRowEditor.tsx:26`

### GAP-6 (formerly GAP-4) — No positive "type-match" affirmation; users hit a silent disabled Create with only a red alert

- **Severity:** Low (UX; the guard is correct, discoverability is poor). Once GAP-1/2/4 land, Measure mismatches become essentially unreachable, so this is optional polish.
- **Fix (frontend, optional):** none required for correctness after GAP-1/2/4. If desired, surface the inferred type inline in the Measure row. No new file.

**Not gaps (verified):** Flag and Label have **no open gaps** — field scope filtered upstream, aggregation gated on `showAggregation`, comparison ops return-type-filtered to boolean, category guard catches residuals. R5/R7/R9/R11/R13/R14/R16 enforced structurally. Scope enforcement (target+2 drop, sibling-list drop with correct trailing-`.` guard, parent-from-child drop, container depth-transparency) is sound under direct verification of `scopeOf` and `walkSchemaField`. The `agg:first/last`-with-path numeric/date case is a **deferred limitation**, not a fixable-here gap.

---

## 4. ENFORCEMENT PLAN (per card, prioritized)

Legend: **[DONE]** = shipped field-scope filter; **[TODO]** = to implement.

### Shared (all cards) — DONE
- **[DONE]** Rebase + partition fields to Target Level so only atLevel + oneDeeper reach any editor (`field-scope.ts:29-104`, wired at `CreateCustomFieldPage.tsx:122-125`). Closes **R5, R7, R9, R11**.
- **[DONE]** Target Level defaults to Person / disabled on edit + known-field lock (`CreateCustomFieldPage.tsx:534`). Closes **R1, R13, R14**.
- **[DONE]** Name-collision guard (`CreateCustomFieldPage.tsx:229-238`). Closes **R16**.
- **[DONE]** Category guard `wizardCategoryMismatch` (`CreateCustomFieldPage.tsx:251-252`) + defensive re-check in submit (`:271-287`). Closes **R10** at the gate.

### Measure (highest priority — this is the story's bug)
1. **[TODO] Filter the Measure FIELD picker by leaf type** — keep only numeric/UNKNOWN leaves (own-scalar and one-deeper). Closes **GAP-4**, encodes **GAP-5** (DATE excluded). *Do this together with GAP-1/GAP-2 or they introduce dead-ends.* File: `MeasureConditionRowEditor.tsx:26`, `field-select-utils.ts`.
2. **[TODO] Offer numeric own-scalar fields + derive `isList` from the field** (mirror Flag/Label) **and add the matching builder + resolver + typing paths** so scalar Measures round-trip on edit. Closes **GAP-1**, restores R3 for numeric scalars. Files: `MeasureConditionRowEditor.tsx:26,34,45`, `measure-builder.ts:16`, `measure-resolver.ts:63`, `formula-type-checker.ts:19-20`, `CreateCustomFieldPage.tsx:391-393`.
3. **[TODO] Filter the Measure operator dropdown to numeric-returning aggregations only** (`agg:sum/avg/min/max`); deny `agg:first/last/col:contains`. Closes **GAP-2**, enforces R10 by construction, encodes the first/last DEFERRED limitation. Files: `MeasureConditionRowEditor.tsx:34,36-43`.
4. **[TODO] Gate the filter button on `isFieldACollection`** (mirror Flag `:128`). Closes **GAP-3**, enforces **R18**. File: `MeasureConditionRowEditor.tsx:45`.

### Flag — no code changes
- **[DONE]** `showAggregation` gating (`FlagConditionRowEditor.tsx:53-56`), boolean-only comparison ops (`comparison-operators.ts:27-37`), filter gated on `showAggregation` (`:128`). Satisfies **R3, R4, R8, R18**.

### Label — no code changes
- **[DONE]** Same as Flag plus manual-input/≤2-param aggregation restriction (`LabelConditionRowEditor.tsx:66-79`) and same-collection filter scoping (`field-select-utils.ts:30-38`). Satisfies **R3, R4, R7, R18**.

**Net:** remaining work is contained to the **Measure card**: field-list leaf-type filter, numeric operator filter, filter-button gate, plus a scalar branch across builder + resolver + type-checker + Create-gate completeness. No changes to Flag/Label editors, no shared-guard changes, **no hamster**.

---

## 5. STORY-EXAMPLE COVERAGE

Under the proposed enforced rules (DONE + the four Measure TODOs). "Buildable"/"Blocked"/"Not buildable" is the target state.

**Correction from the synthesis:** Examples 5 and 6 depend on a **COUNT/SIZE** aggregation that **does not exist** in the catalog and is not reachable by the wizard (see §2). They are **illustrative slide examples on a hypothetical `events`/`lineItem` schema that does not exist in the demo gold model**; the story uses them only to teach the scope rule (aggregate-at-common-parent), not to claim the wizard can emit `count()`. The **scope rule they illustrate is enforced**, but the specific `count(...)` *form* is **not constructible in the wizard**. The blanket "all 7 VALID examples are buildable" claim is therefore corrected below.

| # | Formula (context) | Story verdict | Result under enforced rules | Governing rule / mechanism |
|---|---|---|---|---|
| 1 | `person.age > 50` | VALID | **Buildable** (Flag) | R3: `age` atLevel scalar, no agg, `jexl:gt`→BOOLEAN. |
| 2 | `amount > 1000` (Target=Gift) | VALID | **Buildable** (Flag/per-item) | R3 + R12: on per-item level `amount` is atLevel; tag prefix `person.transactions.items.customAttributes[...]`. |
| 3 | `person.age > 50 && agg:avg(transactions.items,'amount') > 100` | VALID | **Buildable** (Flag) | R3 (age atLevel) + R4 (gift list oneDeeper → agg) + R8, joined by `&&`; `inferReturnType` forces BOOLEAN. |
| 4 | `agg:sum(transactions.items,'amount')` (Target=Person) | VALID | **Buildable** (Measure, after TODO-3 keeps `agg:sum` and TODO-1 keeps the numeric leaf) | R4: oneDeeper numeric list, `agg:sum`→FLOAT→MEASURE. |
| 5 | `count(events) > 5 && agg:avg(gift) > 100` | VALID (illustrative, hypothetical schema) | **Scope rule enforced, but NOT wizard-buildable as written** — requires a COUNT of `events`, and no COUNT/SIZE aggregation exists (§2). Buildable *in principle* only if a numeric aggregate replaces `count`, on a schema that had `events`. | R8 illustration. The teaching point (fold both target+1 lists to scalars at Person, then AND) holds; the literal `count()` primitive is unavailable. |
| 6 | `count(events.state=='CO') > 0 && person.age > 50` | VALID (illustrative, hypothetical schema) | **Scope rule enforced, but NOT wizard-buildable as written** — the filter row builds `agg:filter(events,"it.state=='CO'")` which returns a **list**; there is no COUNT/SIZE op to fold it to a scalar, and `agg:filter` is never a terminal. | R8 + R18 illustration. Sibling list correctly usable only after collapsing to a scalar; the collapse-to-count step is not constructible. |
| 7 | `largeGift ? 'large' : 'small'` (Target=Gift, prior per-item CF) | VALID | **Buildable** (Label, chaining) | R6: prior per-item CF is an atLevel own field at Gift; STRING terminal. |
| — | `person.age > 50 && count(lineItem) > 10` (Target=Person) | INVALID | **Blocked (omission)** — `lineItem` never in picker | R5: target+2 dropped (`field-scope.ts:44`). |
| — | `events.location=='Boulder' && gift.amount > 50` | INVALID | **Blocked (omission)** — only one branch's item fields offered per row | R7: sibling raw item fields never both selectable (perItem `startsWith` guard). |
| — | `events.state=='CO' && person.age > 50` (from Email-Event per-item level) | INVALID | **Blocked (omission)** — `person.age` is a parent field, dropped | R9: perItem branch drops ancestor fields (`field-scope.ts:38`). |
| — | per-item tag + `agg:sum(transactions.items,'amount')` (formula-editor escape hatch) | INVALID | **Not buildable in wizard** — level couples tag prefix to placement | R12: the wizard cannot desync placement from formula. |

Corrected bottom line for §5: **Examples 1, 2, 3, 4, and 7 are wizard-buildable** under the enforced rules (Example 4 contingent on Measure TODO-1 + TODO-3). **Examples 5 and 6 exercise a scope rule that IS enforced, but their literal `count()` form is NOT wizard-constructible** because no COUNT/SIZE aggregation exists — and they were only ever illustrative slide examples on a schema absent from the demo gold model. All INVALID examples are blocked, the overwhelming majority by **prevention-by-omission** (already shipped).

---

## 6. OPEN QUESTIONS / PRODUCT DECISIONS

1. **`agg:first` / `agg:last` numeric/date Measures (DEFERRED LIMITATION, needs hamster).** The catalog hardcodes `returnType=OBJECT` for first/last, so the frontend cannot know `agg:first(transactions.items,'amount')` is numeric. The frontend fix denies these from Measure; a "first/last gift amount/date" Measure is not wizard-buildable (only via formula editor). Making it work needs **catalog-side extracted-path type inference in hamster** — out of scope for COM-528. **Decision:** accept the limitation, or file a follow-up hamster ticket. (Distinguish: first/last *without* a path returns the whole item OBJECT and is correctly non-Measure; only the *with-path* case is the deferred item.)
2. **No COUNT / SIZE aggregation exists (needs hamster if wanted).** Examples 5/6 and any "number of gifts/events > N" metric require counting list length. The catalog exposes no `agg:count` and `jexl:size` is unreachable from the aggregation dropdown. **Decision:** confirm COUNT is genuinely out of scope for COM-528, or file a hamster ticket to add a list-length aggregation. Do **not** assume the wizard can build count-based examples today.
3. **Own-scalar Measure `Identifier` typing.** GAP-1 must make a direct scalar reference infer the field's real `dataType` (not UNKNOWN) so the persisted `dataType`/tag binding is correct, **and** add a Measure-resolver `Identifier` branch so the field survives edit round-trip (R14). Preferred: resolve `Identifier` against `scopedFieldOptions` inside `inferReturnType` (removes the UNKNOWN→MEASURE fallback) + a matching resolver branch. **Confirm this shape before implementation** — it changes `formula-type-checker.ts` and `measure-resolver.ts`.
4. **DATE as a Measure (GAP-5).** DATE→MEASURE per the category map, but no DATE aggregation and no bare-Identifier path today. Proposal: exclude DATE from the Measure picker for now (documented limitation). **Confirm** DATE Measures are out of scope, or route to the hamster work in Q1/Q2.
5. **Non-numeric leaf types under Measure.** GAP-4 filters the Measure field picker to numeric/UNKNOWN leaves. **Confirm** this is the desired behavior (vs. offering them with an inline "not a Measure" hint). The chosen approach is prevention-by-omission, consistent with Flag/Label.
6. **Object-branch `oneDeeper` intentionally admits sibling lists.** The object (top-level) branch uses `listDepth(collection)===1` with no `startsWith` prefix constraint, unlike the perItem branch — this is **correct** (every top-level list is a legitimate target+1 at Person, per R8/Examples 5-6) and must not be "harmonized" with the perItem branch. Noted so a future reader does not accidentally break R8. No decision needed; documentation only.
7. **Cross-list combination in one formula (Examples 5/6 shape).** Rules confirm both sibling lists must be aggregated at the common parent; nothing blocks referencing two different target+1 lists in one Flag/Label formula. Unspecified whether the wizard should actively *offer* this or steer users to split. The flat demo dataset cannot exercise it. **Product confirm.**
8. **Integer vs float for Measure tag binding.** Categories allow both; currently inferred from `returnTypes[0]`. **Confirm inference is acceptable** for the `<integer>` vs `<float>` binding.
9. **Container (1:1 nested record) levels.** `target-level.ts` defines `kind:'container'` but `selectableTargetLevels` excludes it. Story is silent on whether a 1:1 nested record should ever be a selectable Target Level. **Confirm with product.**
10. **Classification dropdown final disposition.** Hidden today (R2); open product decision on full removal vs. repurposing as a level classification-key label. **Confirm with Patrick/Natal** (read-only Jira — do not edit).
11. **Formula-editor escape hatch.** Explicitly out of scope for COM-528, but it can build the exact placement/formula-mismatch class the wizard prevents. **Open** whether these wizard rules should later be back-ported as client-side validation on the formula editor (separate ticket).

---

## 7. WHAT TO IMPLEMENT NEXT (checklist — FRONTEND ONLY)

All in `match/portal-admin/frontend/src/domain/datasets/`. Do the Measure items **together** — any one alone introduces or leaves a dead-end.

- [ ] **Measure field picker leaf-type filter (GAP-4/GAP-5).** In `MeasureConditionRowEditor.tsx:26` + a helper in `condition-editors/field-select-utils.ts`, keep only fields whose effective leaf `dataType` ∈ {FLOAT, INTEGER, UNKNOWN} (own-scalar uses the field's own type; one-deeper uses the leaf type). Drops STRING/BOOL/ENUM/DATE fields from the Measure picker.
- [ ] **Offer numeric own-scalars + derive `isList` from the field (GAP-1, editor).** `MeasureConditionRowEditor.tsx:26,34,45`: replace the `isCollection` pre-filter, add `isFieldACollection`, pass `useOperatorCatalog(isFieldACollection ? selectedFieldType : null, isFieldACollection)`.
- [ ] **Scalar builder branch (GAP-1, builder).** `mappers/measure-builder.ts:16`: emit an `Identifier` node when `!field.isCollection`; drop the throw.
- [ ] **Scalar resolver branch (GAP-1, resolver — required for R14 round-trip).** `mappers/measure-resolver.ts:63`: map a bare scoped `Identifier` back to a `MeasureConditionRow` with `operatorId: null`.
- [ ] **Scalar completeness in the Create gate (GAP-1).** `CreateCustomFieldPage.tsx:391-393`: a scalar Measure is complete with `fieldValue` only (no `operatorId`).
- [ ] **`Identifier` typing (GAP-1).** `mappers/formula-type-checker.ts:19-20`: resolve `Identifier` against scoped options and return its `dataType` (removes the UNKNOWN→MEASURE fallback). *Confirm shape per Open Question 3 first.*
- [ ] **Numeric-only operator filter (GAP-2).** `MeasureConditionRowEditor.tsx:34,36-43`: keep only ops whose `returnTypes[0]` ∈ {INTEGER, FLOAT} (via `getReturnTypes` / `resolveOperatorOutputTypes`), before `operatorSelectData` and before auto-select. Removes `agg:first/last/col:contains`.
- [ ] **Gate the filter button (GAP-3/R18).** `MeasureConditionRowEditor.tsx:45`: `canUseFilter = isFieldACollection && condition.fieldValue !== null`.
- [ ] **Run `pnpm prettier --write` on the touched files** before any commit (per `match/CLAUDE.md`).
- [ ] **Document deferred limitations** (in the PR description, not in source per the KDoc rules): first/last-with-path numeric/date Measures and any COUNT-based metric are out of scope and would require a hamster catalog change; DATE Measures are excluded pending Q1/Q2/Q4.

**Bottom line:** Flag and Label are already sound. The story's entire remaining surface is the **Measure card**. The corrected plan closes it with **four coordinated frontend edits** (field-list leaf-type filter, numeric own-scalar support across editor+builder+resolver+type-checker+gate, numeric-only operator filter, filter-button gate). Two classes the original synthesis missed are now folded in: the **non-numeric-field dead-end** (GAP-4) and the **DATE Measure gap** (GAP-5). Two claims are corrected: **no COUNT/SIZE aggregation exists**, so Examples 5/6 are scope-illustrations that are *not* literally wizard-buildable; and GAP-1 requires a **resolver branch** or it breaks edit round-trip. **No hamster changes**; the `agg:first/last`-with-path numeric/date case and any COUNT aggregation are documented deferred limitations.