# cli-utils

Small command-line utilities.

## Contents

- [`unwrap.py`](#unwrappy) — clean terminal-copied text for pasting
- [`shell/wt.zsh`](#wt) — git worktree helper

---

## `unwrap.py`

Reflows text copied from a terminal back into clean, paste-ready Markdown.

When you copy multi-line output from a terminal, each visual line becomes a
hard line break — so wrapped paragraphs arrive full of awkward mid-sentence
newlines. `unwrap.py` rejoins those wrapped lines into continuous paragraphs
while **preserving** structure that should stay on its own line:

- Bullet and numbered lists (`-`, `*`, `1.`)
- Headings (`#`)
- Fenced code blocks (```` ``` ````) — kept verbatim
- Tables and box-drawing characters (`─│┌┐└┘…`)
- Blank lines (collapsed to at most one)

It also strips Claude Code's leading marker character (`▎`).

### Usage

Reads from stdin, writes to stdout:

```bash
pbpaste | python3 unwrap.py | pbpaste
```

Or pipe from anywhere:

```bash
cat messy.txt | python3 unwrap.py
```

**Handy macOS clipboard round-trip** (copy messy → clean → back to clipboard):

```bash
pbpaste | python3 unwrap.py | pbcopy
```

Consider adding an alias:

```bash
alias unwrap='pbpaste | python3 "$HOME/Documents/cli-utils/unwrap.py" | pbcopy'
```

---

## `wt`

A git **worktree** helper for a ticket-based branching workflow. It creates
one worktree per branch under a configurable subfolder, names branches with a
type prefix (`feature/`, `bugfix/`, …), and `cd`s you straight into the new
worktree.

Because it changes your shell's current directory, `wt` is a **shell
function**, not a standalone script — it must be *sourced*, not executed.

### Install

Source it from your `~/.zshrc`:

```bash
# --- cli-utils ---
export WT_SETUP_SCRIPT="$HOME/Documents/app/.claude/setup-worktree.sh"
# export WT_DEFAULT_TYPE="feature"
# export WT_SUBDIR=".claude/worktrees"
# export WT_OPEN_CMD="webstorm"
source "$HOME/Documents/cli-utils/shell/wt.zsh"
```

Then reload:

```bash
source ~/.zshrc
```

### Usage

```text
wt <ticket>                switch/create worktree (default type: feature)
wt -t <type> <ticket>      use a custom branch prefix (bugfix, chore, ...)
wt --list | -l             list worktrees
wt --rm <ticket>           remove worktree + delete its branch
wt --help | -h             show help
```

### Examples

```bash
wt sw-3302                 # -> branch feature/SW-3302
wt -t bugfix sw-3302       # -> branch bugfix/SW-3302
wt -t chore sw-3302        # -> branch chore/SW-3302
wt --list
wt --rm sw-3302            # detects & deletes the branch that worktree used
```

Branch names get the `<type>/` prefix, but worktree **folders** stay flat
(e.g. `SW-3302`), so directories never nest. Worktrees are always created
relative to the *main* repo root (via `git --git-common-dir`), so running
`wt` from inside one worktree won't create nested worktrees in another.

### Configuration

All optional; set as env vars before sourcing.

| Variable          | Default             | Description                                                        |
| ----------------- | ------------------- | ------------------------------------------------------------------ |
| `WT_DEFAULT_TYPE` | `feature`           | Branch prefix used when `-t/--type` isn't given.                   |
| `WT_SUBDIR`       | `.claude/worktrees` | Worktrees location, relative to the main repo root.                |
| `WT_SETUP_SCRIPT` | *(unset)*           | Script run after creating a worktree; receives the path as `$1`.   |
| `WT_OPEN_CMD`     | `webstorm`          | Editor command used by the `wt-open` alias.                        |

### Tip: simpler `git push`

To let git auto-create the upstream branch (so a plain `git push` works on a
fresh branch and pushes to the matching remote name):

```bash
git config --global push.autoSetupRemote true
```