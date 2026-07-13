#!/usr/bin/env bash
# Install the personal Claude Code agent (skills, subagent, workflow, hooks).
#
# The canonical files live here in whContext/claude/ so they are tracked by the
# whContext git repo and sync across machines. This script symlinks them into the
# workspace .claude/ so Claude Code (launched from the wf workspace root) discovers
# them. The wf/.claude/ dir is gitignored, so the symlinks are per-machine only.
#
# Run once after cloning/pulling whContext on a new machine:
#   bash whContext/claude/install.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../wf/whContext/claude
WS_ROOT="$(cd "$SRC_DIR/../.." && pwd)"                   # .../wf
DEST="$WS_ROOT/.claude"
mkdir -p "$DEST"

link() {
  local name="$1"
  local target="../whContext/claude/$name"   # relative to $DEST
  local path="$DEST/$name"
  if [ -L "$path" ]; then
    rm -f "$path"
  elif [ -e "$path" ]; then
    mv "$path" "$path.backup.$$"
    echo "  backed up existing $name -> $name.backup.$$"
  fi
  ln -s "$target" "$path"
  echo "  linked .claude/$name -> $target"
}

echo "Installing personal Claude agent into $DEST"
for item in skills agents workflows hooks settings.json; do
  link "$item"
done
chmod +x "$SRC_DIR"/hooks/*.sh 2>/dev/null || true

echo
echo "Done. Restart Claude Code (from the wf workspace root) to pick up the skills/agents."
echo "Your machine-local settings.local.json (permissions) is left untouched."
