# Reuse existing patterns — don't reinvent

The single biggest source of rework: building a generic version instead of the one
that already exists. Before writing JSX for any UI shape, find and mirror the
nearest existing implementation.

## How to find the pattern

- `rg -l "Accordion|WFTable|Wizard|Drawer|Modal|InlineEditable" match/portal-admin/frontend/src/domain`
- Feature code is grouped by domain: `domain/<feature>/components|hooks|utils`. Shared
  UI lives in `common/`. Look in the sibling domain first.

## Known reference implementations

- **Accordion** — `domain/accounts/components/CsvMappingWizardModalMap.tsx` + its
  `.module.css` (`.chevron`, `.accordionItem*`, `.chip`): colored left bar per item
  (`border-left: 4px`), left-positioned rotating chevron, rounded chip in the control
  with icon + colored label + count. Mirror these, not a plain `Accordion variant='separated'`.
- **Table** — the project `WFTable` component (grep for it). Use it for overview tables,
  don't hand-roll a Mantine `Table`.
- **Inputs** — `common/forms/*` (`TextInput`, `Select`, `Checkbox`, `InlineEditable*`).
  The custom `@/common/forms/TextInput` forwards Mantine style props (`flex={1}` works).

## What "mirror" means

Match the visual details, not just the rough layout: left bars, icon placement,
chevron side, chip shape, spacing. Copy the props and the CSS-module class names (or
extract a shared component if two places now need it). Confirm against BOTH the mock
and the nearest existing implementation. If they conflict, flag it — don't guess.
