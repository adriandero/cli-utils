#!/usr/bin/env zsh
# wt — git worktree helper
#
# Source this from your ~/.zshrc (or run ./install.sh):
#   source "$HOME/path/to/cli-utils/shell/wt.zsh"
#
# Configuration:
#   WT_DEFAULT_TYPE   Default branch prefix.                  Default: feature
#   WT_SUBDIR         Worktree location relative to repo.     Default: .claude/worktrees
#   WT_SETUPS_DIR     Per-project setup scripts.              Default: <cli-utils>/wt-setups
#   WT_OPEN_CMD       Editor command used by `wt-open`.       Default: webstorm
#
# Setup script lookup after `wt create` (first match wins):
#   1. `git config wt.setup <name|path>` in the repo
#   2. $WT_SETUPS_DIR/<main-repo-folder-name>.sh
#   3. none — the worktree is created without setup

typeset -g _WT_HOME="${${(%):-%x}:A:h:h}"

: "${WT_DEFAULT_TYPE:=feature}"
: "${WT_SUBDIR:=.claude/worktrees}"
: "${WT_SETUPS_DIR:=$_WT_HOME/wt-setups}"
: "${WT_OPEN_CMD:=webstorm}"

_wt_find_setup() {
  local repo_root="$1" configured candidate

  configured=$(git -C "$repo_root" config --path --get wt.setup 2>/dev/null)

  if [[ -n "$configured" ]]; then
    # A bare name refers to a script in $WT_SETUPS_DIR.
    [[ "$configured" == */* ]] || configured="$WT_SETUPS_DIR/$configured.sh"
    print -r -- "$configured"
    return 0
  fi

  candidate="$WT_SETUPS_DIR/${repo_root:t}.sh"
  [[ -f "$candidate" ]] && print -r -- "$candidate"
  return 0
}

# Keep worktrees out of `git status` in repos that don't ignore them already.
_wt_ensure_excluded() {
  local exclude="$1/info/exclude" pattern="/${2%/}/"

  mkdir -p "${exclude:h}" || return 1
  grep -qxF -- "$pattern" "$exclude" 2>/dev/null || print -r -- "$pattern" >>"$exclude"
}

_wt_help() {
  cat <<'EOF'
wt — git worktree helper

Usage:
  wt create <ticket>             create or switch to a worktree
  wt create -t <type> <ticket>   use a custom branch prefix
  wt touch <ticket>              alias for `wt create`
  wt list                        list worktrees
  wt rm <ticket>                 remove worktree and delete its branch
  wt help                        show this help

Aliases:
  wt --list | -l                 same as `wt list`
  wt --rm <ticket>               same as `wt rm`
  wt --help | -h                 same as `wt help`

Examples:
  wt create sw-3302
  wt create -t bugfix sw-3302
  wt touch sw-3302
  wt list
  wt rm sw-3302

Branch examples:
  wt create sw-3302              -> feature/sw-3302
  wt create -t bugfix sw-3302    -> bugfix/sw-3302

Config:
  WT_DEFAULT_TYPE
  WT_SUBDIR
  WT_SETUPS_DIR
  WT_OPEN_CMD

Per-project setup:
  $WT_SETUPS_DIR/<repo-folder>.sh, or `git config wt.setup <name|path>`
EOF
}

wt() {
  local command_name="${1:-help}"

  # Help should work even when we're outside a Git repository.
  case "$command_name" in
    help|--help|-h)
      _wt_help
      return 0
      ;;
  esac

  shift

  local repo_root common_dir worktrees_dir
  local name branch target type existing

  common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    echo "wt: not in a git repo" >&2
    return 1
  }

  # Resolve the main repository root from the common .git directory,
  # ensuring worktrees are never nested inside other worktrees.
  repo_root="${common_dir:h}"
  worktrees_dir="$repo_root/$WT_SUBDIR"

  case "$command_name" in
    list|--list|-l)
      if (( $# > 0 )); then
        echo "wt: 'list' does not accept arguments" >&2
        return 1
      fi

      git worktree list
      ;;

    rm|remove|--rm)
      local force=0
      local -a args=()

      for arg in "$@"; do
        case "$arg" in
          -f|--force) force=1 ;;
          *) args+=("$arg") ;;
        esac
      done

      if (( ${#args[@]} != 1 )); then
        echo "Usage: wt rm [-f|--force] <ticket>" >&2
        return 1
      fi

      name="${args[1]}"
      target="$worktrees_dir/$name"

      if [[ "$PWD" == "$target" || "$PWD" == "$target"/* ]]; then
        echo "wt: you're inside '$name' — cd out first, then rerun" >&2
        return 1
      fi

      if [[ ! -d "$target" ]]; then
        echo "wt: worktree does not exist: $target" >&2
        return 1
      fi

      branch=$(
        git worktree list --porcelain |
          awk -v w="$target" '
            /^worktree / {
              cur = substr($0, length("worktree ") + 1)
            }
            /^branch / {
              if (cur == w) {
                branch = substr($0, length("branch ") + 1)
                sub("^refs/heads/", "", branch)
                print branch
              }
            }
          '
      )

      if (( force )); then
        git worktree remove --force "$target" || return $?
      else
        git worktree remove "$target" || return $?
      fi

      if [[ -n "$branch" ]]; then
        if (( force )); then
          git branch -D "$branch" || return $?
        else
          git branch -d "$branch" || return $?
        fi
      fi

      echo "→ removed worktree: $target"

      if [[ -n "$branch" ]]; then
        echo "→ deleted branch: $branch"
      fi
      ;;

    create|touch)
      type="$WT_DEFAULT_TYPE"

      if [[ "${1:-}" == "-t" || "${1:-}" == "--type" ]]; then
        if [[ -z "${2:-}" ]]; then
          echo "wt: missing branch type after '$1'" >&2
          echo "Usage: wt create -t <type> <ticket>" >&2
          return 1
        fi

        type="$2"
        shift 2
      fi

      if (( $# != 1 )); then
        echo "Usage: wt create [-t <type>] <ticket>" >&2
        return 1
      fi

      name="$1"

      # Protect against accidentally treating flags as ticket names.
      if [[ "$name" == -* ]]; then
        echo "wt: invalid ticket name: '$name'" >&2
        echo "Ticket names cannot begin with '-'." >&2
        return 1
      fi

      if [[ -z "$type" || "$type" == -* ]]; then
        echo "wt: invalid branch type: '$type'" >&2
        return 1
      fi

      branch="$type/$name"
      target="$worktrees_dir/$name"

      # First, find the worktree by its expected target path.
      existing=$(
        git worktree list --porcelain |
          awk -v target="$target" '
            /^worktree / {
              path = substr($0, length("worktree ") + 1)

              if (path == target) {
                print path
                exit
              }
            }
          '
      )

      if [[ -n "$existing" ]]; then
        cd "$existing" || return 1
        echo "→ switched to existing worktree: $existing"
        return 0
      fi

      # Otherwise, find a worktree attached to the expected branch.
      existing=$(
        git worktree list --porcelain |
          awk -v b="refs/heads/$branch" '
            /^worktree / {
              worktree = substr($0, length("worktree ") + 1)
            }
            $0 == "branch " b {
              print worktree
              exit
            }
          '
      )

      if [[ -n "$existing" ]]; then
        cd "$existing" || return 1
        echo "→ switched to existing worktree: $existing"
        return 0
      fi

      # The directory exists but is not a registered Git worktree.
      if [[ -e "$target" ]]; then
        echo "wt: target exists but is not a registered worktree: $target" >&2
        return 1
      fi

      mkdir -p "$worktrees_dir" || return 1
      _wt_ensure_excluded "$common_dir" "$WT_SUBDIR" || return 1

      # Attach an existing branch, or create it from the current HEAD.
      if git show-ref --verify --quiet "refs/heads/$branch"; then
        git worktree add "$target" "$branch"
      else
        git worktree add -b "$branch" "$target"
      fi || return $?

      cd "$target" || return 1
      echo "→ created worktree: $target (branch: $branch)"

      local setup_script
      setup_script=$(_wt_find_setup "$repo_root")

      if [[ -z "$setup_script" ]]; then
        echo "→ no setup script for '${repo_root:t}', skipping"
      elif [[ ! -f "$setup_script" ]]; then
        echo "wt: setup script not found: $setup_script" >&2
        return 1
      else
        echo "→ running setup: $setup_script"
        WT_SUBDIR="$WT_SUBDIR" bash "$setup_script" "$target" || {
          echo "wt: setup failed — fix and rerun: bash $setup_script" >&2
          return 1
        }
      fi
      ;;

    *)
      echo "wt: unknown command: '$command_name'" >&2
      echo "Run 'wt help' to see available commands." >&2
      return 1
      ;;
  esac
}

unalias wt-open 2>/dev/null

wt-open() {
  local root

  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "wt-open: not in a git repo" >&2
    return 1
  }

  "$WT_OPEN_CMD" "$root"
}