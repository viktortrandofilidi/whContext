#!/usr/bin/env bash
# PostToolUse(Edit|Write): nudge when an inline style lands in a portal-admin
# React file. Fires only when the just-edited file contains style={{ / styles={{.
# Fails open (exit 0) if jq or the file is missing, so it can never block work.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
[ -n "$file" ] || exit 0

case "$file" in
  *portal-admin/frontend/*.tsx|*portal-admin/frontend/*.ts) ;;
  *contextual-analytics/*.tsx|*contextual-analytics/*.ts) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

hits="$(grep -nE 'style=\{\{|styles=\{\{' "$file" 2>/dev/null || true)"
[ -n "$hits" ] || exit 0

{
  echo "Inline style in a React file — this gets flagged in review:"
  printf '%s\n' "$hits" | sed 's/^/  /'
  echo "Fix: Mantine style props first (w h mih flex p m c fz fw) → Box/Stack/Flex/Group → co-located *.module.css. No inline style={{}}/styles={{}}."
} >&2
exit 2
