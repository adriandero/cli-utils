#!/usr/bin/env zsh
# wt — git worktree helper
#
# Source this from your ~/.zshrc:
#   source "$HOME/path/to/cli-utils/shell/wt.zsh"
#
# Configuration (set before sourcing, or override in your shell):
#   WT_DEFAULT_TYPE   Branch prefix when none is given.   Default: feature
#   WT_SUBDIR         Worktrees location, relative to the Default: .claude/worktrees
#                     main repo root.
#   WT_SETUP_SCRIPT   Optional script run after creating a Default: (unset)
#                     worktree (receives the worktree path
#                     as $1).
#   WT_OPEN_CMD       Editor command for `wt-open`.        Default: webstorm

: "${WT_DEFAULT_TYPE:=feature}"
: "${WT_SUBDIR:=.claude/worktrees}"
: "${WT_OPEN_CMD:=webstorm}"

wt() {
  local repo_root common_dir worktrees_dir name branch target type existing

  common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || {
    echo "wt: not in a git repo" >&2; return 1
  }
  # Resolve the MAIN repo root (parent of the common .git dir),
  # so worktrees never nest inside other worktrees.
  repo_root=$(cd "$(dirname "$common_dir")" && pwd)
  worktrees_dir="$repo_root/$WT_SUBDIR"

  # Help
  if [[ -z "$1" || "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<'EOF'
wt — git worktree helper

Usage:
  wt <ticket>                switch/create worktree (default type: feature)
  wt -t <type> <ticket>      use a custom branch prefix (bugfix, chore, ...)
  wt --list | -l             list worktrees
  wt --rm <ticket>           remove worktree + delete its branch
  wt --help | -h             show this help

Examples:
  wt sw-3302                 -> feature/SW-3302
  wt -t bugfix sw-3302       -> bugfix/SW-3302
  wt -t chore sw-3302        -> chore/SW-3302
  wt --rm sw-3302

Config (env vars): WT_DEFAULT_TYPE, WT_SUBDIR, WT_SETUP_SCRIPT, WT_OPEN_CMD
EOF
    return 0
  fi

  if [[ "$1" == "--list" || "$1" == "-l" ]]; then
    git worktree list
    return 0
  fi

  type="$WT_DEFAULT_TYPE"
  if [[ "$1" == "-t" || "$1" == "--type" ]]; then
    type="$2"
    shift 2
  fi

  # Removal: auto-detect the branch attached to the worktree folder
  if [[ "$1" == "--rm" ]]; then
    name="$2"
    target="$worktrees_dir/$name"
    if [[ "$PWD" == "$target"* ]]; then
      echo "wt: you're inside '$name' — cd out first, then rerun" >&2
      return 1
    fi
    branch=$(git worktree list --porcelain \
             | awk -v w="$target" '
                 /^worktree /{cur=$2}
                 /^branch /{if(cur==w){sub("refs/heads/","",$2); print $2}}')
    git worktree remove "$target" && [[ -n "$branch" ]] && git branch -d "$branch"
    return $?
  fi

  name="$1"
  branch="$type/$name"
  target="$worktrees_dir/$name"

  # 1. Already have a worktree for this branch? Just cd into it.
  existing=$(git worktree list --porcelain \
             | awk -v b="refs/heads/$branch" '
                 /^worktree /{w=$2}
                 $0=="branch "b{print w}')
  if [[ -n "$existing" ]]; then
    cd "$existing" && echo "→ switched to existing worktree: $existing"
    return 0
  fi

  # 2. Existing branch? attach it. Otherwise create from current HEAD.
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$target" "$branch"
  else
    git worktree add -b "$branch" "$target"
  fi || return $?

  cd "$target" && echo "→ created worktree: $target (branch: $branch)"

  # Optional post-create setup hook
  if [[ -n "$WT_SETUP_SCRIPT" && -f "$WT_SETUP_SCRIPT" ]]; then
    echo "→ running setup: $WT_SETUP_SCRIPT"
    bash "$WT_SETUP_SCRIPT" "$target"
  fi
}

alias wt-open='$WT_OPEN_CMD "$(git rev-parse --show-toplevel)"'