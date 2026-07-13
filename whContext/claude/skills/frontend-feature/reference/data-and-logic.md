# Data fetching, wizard pickers & logic traps

## Data fetching (TanStack Query)

- All server state via TanStack Query. Data flow is **Component → custom hook →
  service function → API**; never skip a layer.
- Query keys come from the centralized `queryKey` enum in
  `src/global/react-query/query-keys.ts` — never inline string keys.
- **queryKey must match what queryFn actually fetches.** If the service normalizes
  its input (e.g. strips a `?usecase` suffix), the hook's `queryKey` must use the
  same normalized value, or two equal inputs make duplicate cache entries + requests.
- **"Cached for the session" needs `gcTime: Infinity`, not just `staleTime: Infinity`.**
  Default `gcTime` is 5 min; the entry is GC'd on unmount and refetches on reopen.
  Make the comment match the config.
- Query hooks expose `isLoading` + `isError`. Mutations use `onSuccess` (invalidate),
  `onError` (notify), `onSettled` (cleanup).

## Mode-scoped wizard pickers

In multi-mode wizards (Flag / Label / Measure, etc.) EVERY selector that feeds the
formula — Known Fields catalog, in-panel dataset-field picker, operator dropdown —
filters by the **currently selected mode**, not the union of all modes:
MEASURE → INTEGER/FLOAT; LABEL → STRING/ENUM; FLAG → BOOLEAN; DATE never fits, always excluded.
Save-time validation is not a substitute for filtering the options upstream.

## Logic traps (pass tsc/eslint but fail review)

Trace the real data path for each before declaring done:

1. **Filter-before-cap ordering.** A function that both drops items (nulls/non-strings)
   and returns `[]` when "too many" vs a `limit` must judge the cap on the **raw**
   count *before* filtering — capping on filtered length truncates silently.
2. **Query-key ↔ queryFn normalization** — see above.
3. **gcTime vs staleTime** — see above.
4. **`x ?? Object.values(map)[0]` is only safe with one candidate.** Guard it: exact
   key → normalized-key match → "first" only when the map has a single entry.
5. **Redundant casts.** After a type guard (`isIdentifier(ast)`), drop the `as XNode`
   cast and the now-unused type import — a classic `--max-warnings 0` CI failure.
6. **Validate the effective value, not the raw input.** If a field's validator is
   skipped in a mode (hidden/overridden), it must validate what the submit path uses
   (the override) — else an empty override slips through and fails downstream on a
   hidden field.
