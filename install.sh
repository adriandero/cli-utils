#!/usr/bin/env bash
# Hooks cli-utils into ~/.zshrc. Safe to rerun.
#   ./install.sh

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RC="${ZDOTDIR:-$HOME}/.zshrc"

# Write $HOME-relative paths so the block survives a different username.
HERE_RC="${HERE/#$HOME/\$HOME}"

touch "$RC"

if grep -q "cli-utils/shell/wt.zsh" "$RC"; then
  echo "✓ $RC already sources wt.zsh"
else
  cat >>"$RC" <<EOF

# --- cli-utils ---
# export WT_DEFAULT_TYPE="feature"
# export WT_SUBDIR=".claude/worktrees"
# export WT_OPEN_CMD="webstorm"
source "$HERE_RC/shell/wt.zsh"
alias unwrap='pbpaste | python3 "$HERE_RC/unwrap.py" | pbcopy'
EOF
  echo "✓ added cli-utils block to $RC"
fi

echo "Reload with: source $RC"
