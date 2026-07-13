#!/usr/bin/env bash
# Stop: fast pre-finish gate, repo-aware. No-op unless tracked files changed.
# Works whether Claude Code is launched from the wf workspace root (code in
# ./match, ./hamster, …) or from inside one of the repos itself.
#
# match (default, cheap → hard-block, exit 2):
#   - prettier formatting on changed React files
#   - inline styles in changed React files
#   Set WF_STOP_GATE_FULL=1 to also hard-block eslint + tsc.
#
# Kotlin repos (hamster / orchestrator / commons-kotlin) — Gradle is heavy and needs
# a JDK 21 launcher, so spotless is OFF by default (the builder agent runs
# spotlessApply as a step and a pre-push hook enforces it). Set WF_STOP_GATE_KOTLIN=1
# to hard-block on `./gradlew spotlessCheck` when .kt files changed.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
payload="$(cat)"
# Don't loop: if this stop is itself a continuation triggered by the hook, release.
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0
command -v git >/dev/null 2>&1 || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
fail=0
msg=""

# ---- match: cheap formatting + inline-style checks (always on) ----------------
if [ -d "$ROOT/portal-admin/frontend" ]; then MATCH="$ROOT"
elif [ -d "$ROOT/match/portal-admin/frontend" ]; then MATCH="$ROOT/match"
else MATCH=""
fi

if [ -n "$MATCH" ]; then
  changed="$(git -C "$MATCH" status --porcelain 2>/dev/null | awk '{print $2}')"
  if [ -n "$changed" ]; then
    fe_files="$(printf '%s\n' "$changed" | grep -E 'portal-admin/frontend/.*\.(ts|tsx)$' || true)"
    fe_any="$(printf '%s\n' "$changed" | grep -E 'portal-admin/frontend/.*\.(ts|tsx|css)$' || true)"
    FE="$MATCH/portal-admin/frontend"

    if [ -n "$fe_any" ] && [ -d "$FE" ] && command -v pnpm >/dev/null 2>&1; then
      if ! out="$(cd "$FE" && pnpm ci:format 2>&1)"; then
        fail=1
        msg="$msg"$'\n'"[prettier] formatting check failed. Fix: cd match/portal-admin/frontend && pnpm format"$'\n'"$(printf '%s' "$out" | tail -20)"
      fi
      if [ "${WF_STOP_GATE_FULL:-0}" = "1" ]; then
        if ! out="$(cd "$FE" && pnpm ci:lint 2>&1)"; then
          fail=1; msg="$msg"$'\n'"[eslint] ci:lint failed:"$'\n'"$(printf '%s' "$out" | tail -30)"
        fi
        if ! out="$(cd "$FE" && pnpm checkts 2>&1)"; then
          fail=1; msg="$msg"$'\n'"[tsc] checkts failed:"$'\n'"$(printf '%s' "$out" | tail -30)"
        fi
      fi
    fi

    if [ -n "$fe_files" ]; then
      # shellcheck disable=SC2086
      hits="$(cd "$MATCH" && grep -nE 'style=\{\{|styles=\{\{' $fe_files 2>/dev/null || true)"
      if [ -n "$hits" ]; then
        fail=1
        msg="$msg"$'\n'"[inline-style] remove inline styles from changed files:"$'\n'"$hits"
      fi
    fi
  fi
fi

# ---- Kotlin repos: opt-in spotless check (WF_STOP_GATE_KOTLIN=1) ---------------
if [ "${WF_STOP_GATE_KOTLIN:-0}" = "1" ]; then
  for name in hamster orchestrator commons-kotlin; do
    if [ -d "$ROOT/$name/.git" ] || { [ -f "$ROOT/settings.gradle.kts" ] && [ "$(basename "$ROOT")" = "$name" ]; }; then
      if [ -d "$ROOT/$name" ]; then REPO="$ROOT/$name"; else REPO="$ROOT"; fi
      kt_changed="$(git -C "$REPO" status --porcelain 2>/dev/null | awk '{print $2}' | grep -E '\.kts?$' || true)"
      if [ -n "$kt_changed" ] && [ -x "$REPO/gradlew" ]; then
        if ! out="$(cd "$REPO" && ./gradlew spotlessCheck -q 2>&1)"; then
          fail=1
          msg="$msg"$'\n'"[$name] spotlessCheck failed. Fix: cd $name && ./gradlew spotlessApply (JDK 21)"$'\n'"$(printf '%s' "$out" | tail -25)"
        fi
      fi
    fi
  done
fi

if [ "$fail" -eq 1 ]; then
  printf 'Pre-finish gate:%s\n' "$msg" >&2
  exit 2
fi
exit 0
