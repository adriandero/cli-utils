# cli-utils

Small command-line utilities.

## Contents

- [`unwrap.py`](#unwrappy) — clean terminal-copied text for pasting
- [`shell/wt.zsh`](#wt) — git worktree helper

## Install (new machine)

```bash
git clone https://github.com/adriandero/cli-utils.git ~/Documents/cli-utils
~/Documents/cli-utils/install.sh
source ~/.zshrc
```

`install.sh` appends a `# --- cli-utils ---` block to `~/.zshrc` (sources
`wt.zsh`, adds the `unwrap` alias). Rerunning it is a no-op.

Requirements: zsh, git ≥ 2.31. Setup scripts may need more (see each script).

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
pbpaste | python3 unwrap.py | pbcopy
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

A git **worktree** helper for a ticket-based branching workflow. Works in any
git repo: it creates one worktree per branch under a configurable subfolder,
names branches with a type prefix (`feature/`, `bugfix/`, …), `cd`s you into
the new worktree, and runs a **per-project** setup script if one exists.

Because it changes your shell's current directory, `wt` is a **shell
function**, not a standalone script — it must be *sourced* (see Install).

### Usage

```text
wt create <ticket>             create or switch to a worktree
wt create -t <type> <ticket>   use a custom branch prefix
wt touch <ticket>              alias for `wt create`
wt list                        list worktrees
wt rm [-f] <ticket>            remove worktree and delete its branch
wt help                        show help
wt-open                        open the current worktree in $WT_OPEN_CMD
```

### Examples

```bash
wt create sw-3302              # -> branch feature/sw-3302
wt create -t bugfix sw-3302    # -> branch bugfix/sw-3302
wt list
wt rm sw-3302                  # detects & deletes the branch that worktree used
```

Branch names get the `<type>/` prefix, but worktree **folders** stay flat
(e.g. `sw-3302`), so directories never nest. Worktrees are always created
relative to the *main* repo root (via `git --git-common-dir`), so running
`wt` from inside one worktree won't create nested worktrees in another.
The worktrees folder is added to `.git/info/exclude` so it never shows up in
`git status`.

### Per-project setup scripts

After creating a worktree, `wt` looks for a setup script (first match wins):

1. `git config wt.setup <name|path>` in that repo — a bare name means
   `wt-setups/<name>.sh`, anything with a `/` is a path (`~` allowed).
2. `wt-setups/<main-repo-folder-name>.sh` — e.g. a repo cloned into `~/code/app`
   uses `wt-setups/app.sh`.
3. Nothing found → worktree is created without setup.

The script runs with `bash`, from inside the new worktree, with the worktree
path as `$1` and `WT_SUBDIR` in the environment. If it fails, `wt` says so;
fix the cause and rerun the script by hand.

If a repo's folder name differs on another machine, point it at the script
once:

```bash
git config wt.setup app
```

| Script              | Project                                                                                    |
| ------------------- | ------------------------------------------------------------------------------------------ |
| `wt-setups/app.sh`  | Smart Wallet monorepo — symlinks `node_modules`, copies certs, assigns ports, Prisma client |

### Configuration

All optional; set as env vars before sourcing.

| Variable          | Default               | Description                                         |
| ----------------- | --------------------- | --------------------------------------------------- |
| `WT_DEFAULT_TYPE` | `feature`             | Branch prefix used when `-t/--type` isn't given.    |
| `WT_SUBDIR`       | `.claude/worktrees`   | Worktrees location, relative to the main repo root. |
| `WT_SETUPS_DIR`   | `<cli-utils>/wt-setups` | Where per-project setup scripts live.             |
| `WT_OPEN_CMD`     | `webstorm`            | Editor command used by `wt-open`.                   |

### Tip: simpler `git push`

To let git auto-create the upstream branch (so a plain `git push` works on a
fresh branch and pushes to the matching remote name):

```bash
git config --global push.autoSetupRemote true
```