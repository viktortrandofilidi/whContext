# Styling & layout — never inline

A `style={{}}` or `styles={{}}` prop is a review reject on sight (and the
PostToolUse hook nudges you). Resolution order:

## 1. Mantine style props first

`w h mih maw flex p m c fz fw gap justify align`, theme color shorthand (`green.6`, `gray.3`).

- `style={{ width: 60 }}` → `w={60}`
- `style={{ flex: 1 }}` → `flex={1}`
- `style={{ flex: 1, minHeight: 400 }}` → `<Box flex={1} mih={400}>`

## 2. Right Mantine box, not a styled div

Replace raw `<div style>` with `Box` / `Stack` / `Flex` / `Group`. Don't turn a
`Paper` into a flex container via style — put a `Stack` / `Flex` *inside* it.

## 3. CSS module for the rest

What style props can't express — `table-layout: fixed`, child selectors like `th`,
pseudo-selectors — goes to a co-located `*.module.css`, applied via `className`.

## Table-cell overflow: wrap long identifiers, don't ellipsize

For columns holding long unbroken identifiers (API / field names, keys), let the value
**wrap onto the next line** — do not hide it behind a `truncate` ellipsis. The full value
(`associatedcompanylastupdated`) beats `associatedcompanylastup…`. Mantine `truncate`
(nowrap + ellipsis) is only for prose whose tail is disposable, or when truncation is
explicitly asked for. Wrap a long token via a CSS-module class with `overflow-wrap: anywhere`
— a plain `white-space: normal` won't break a token that has no spaces. If rows share a fixed
height, make that height a floor (min-height behaviour), not a hard clamp, so a wrapped cell
can grow instead of clipping.

## Modal with a scrolling list + pinned footer

Don't hand-compute the scroll height — a `calc(100dvh - Nrem)` cap or a `flex:1 / min-height:0`
chain threaded through the Mantine modal wrappers is brittle and silently stops binding at some
viewport sizes (you get either no scroll or the whole modal scrolling). Put the scroll on a
self-contained `ScrollArea.Autosize mah='50dvh'` (or similar) wrapping the long content: it grows to
`mah`, then scrolls, independent of the modal chrome. Add `type='always'` when the user needs the
scrollbar visible. This is the same primitive used for in-panel dropdown lists, so it behaves the
same way in a modal.

## Verify layout by inspecting, not guessing

For a layout bug you can't fully reason about (scroll, overflow, sizing), attach to the running app
via the preview tool (`.claude/launch.json` → `portal-admin` / `contextual-analytics`) and read the
computed styles / DOM — don't iterate on CSS math blind. Also separate the two failure modes before
changing anything: "no scrollbar shown" (often just `type='hover'`) is a different bug from "content
does not scroll" (an unbounded height).

## contextual-analytics caveat

It is mid-transition off styled-components. Only convert legacy components to Mantine
when the scope of the change warrants — don't turn a 2-line fix into a multi-file PR.

## Before pushing

Grep touched files for `style={{` and `styles={{` and convert every hit. Don't wait
for review to catch it.
