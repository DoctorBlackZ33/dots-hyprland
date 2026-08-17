# Custom fork workflow

This repository is a Git fork of `end-4/dots-hyprland`.

Remotes:

- `upstream`: `https://github.com/end-4/dots-hyprland.git`
- `origin`: the personal GitHub fork

The `dots/` tree is the upstream installation tree. Changes to files already
owned by end-4 are committed in their original paths so upstream changes can
be merged with normal Git three-way merges.

The `local/` tree contains partial personal configuration that must not be
treated as a complete upstream directory. It is applied additively by
`./end4 apply`.

## Unified system workflow

```bash
system
```

The menu offers five operations:

- `merge`: fetch `upstream/main`, open a structured three-way review, and
  prepare a non-committing Git merge.
- `review`: compare the common base, this fork, and upstream without starting
  a merge.
- `update`: run checks, show a deployment dry-run, ask for a target device, and
  deploy only after confirmation.
- `discard`: after a typed `DISCARD` confirmation, abort an active merge,
  reset uncommitted tracked changes, and remove untracked non-ignored files.
- `tui`: open this repository in LazyGit.

The direct equivalents are:

```bash
system merge
system review
system update
system update --dry-run
system discard
system tui
```

The installed `update` command is now a compatibility alias for
`system update`; it no longer stashes, pulls, runs `setup install`, or replaces
files from an external cache.

## Reviewing an upstream merge

`system merge` requires a clean worktree and fetches upstream. It first shows a
compact comparison with three explicit roles:

- `BASE`: the common ancestor before either side changed.
- `FORK`: this repository's `main` branch, or “ours”.
- `UPSTREAM`: end-4's `upstream/main`, or “theirs”.

Select files from the review list. Each selected file opens in a three-pane
`nvim -d` view in the order `BASE | FORK | UPSTREAM`, with normal syntax-aware
diff highlighting. Files marked `UC` changed on both sides and deserve the
closest review. The review is read-only and uses temporary snapshots.

After the comparison, the command prepares a non-committing Git merge.
LazyGit then handles actual conflicts: its conflict view lets you resolve each
file/hunk by choosing ours (this fork), theirs (upstream), both, or opening an
editor for manual resolution. The merge is never committed automatically.

Inside LazyGit, press `Ctrl-G` and choose `r` for the comparison or `m` to run
the full review-plus-merge flow. LazyGit's own ref comparison (`W`) remains
useful for a quick two-ref view.

After resolving conflicts:

```bash
git status
system check
git add path/to/file
git commit -m "Merge upstream/main into custom main"
```

You can abandon the entire active merge with `system discard`. Committed custom
history is never rewritten by that command. For one-off command-line choices,
Git still supports `git restore --ours -- path/to/file` and
`git restore --theirs -- path/to/file` before staging the result.

Inspect the fork's intentional deviation from upstream with:

```bash
git diff --stat upstream/main...main
git diff upstream/main...main -- dots/.config
git log --oneline upstream/main..main
```

## Deployment

Always review first:

```bash
system update --dry-run --general
system update --dry-run --device DarkArch
```

`system update` asks for a device target interactively every time. `General
only` applies the common fork configuration; selecting a device applies that
device's additive overlay afterward. Use `--general` or `--device NAME` for
scripts and non-interactive use.

The default deployment is non-destructive: upstream-managed directories are
updated without deleting live files that are not present in Git. Personal and
device overlays are always additive. If an upstream deletion should also
remove the corresponding live file, explicitly request:

```bash
system update --prune --device DarkArch
```

`--prune` is shown in the confirmation prompt and only affects upstream-owned
directories. It is not enabled by default.

`system update` does not merge upstream and does not run `setup install`.
First use `system merge`, review/resolve/commit it, then use `system update` to
deploy the committed result. `system bootstrap` remains available for the
upstream dependency/full installer when that is intentionally needed.

For compatibility, `./end4 apply` remains available with `--dry-run`,
`--device`, `--force`, and `--prune`; the `system` interface is the preferred
entry point.

## Seeing deviations from upstream

```bash
system status
git diff --stat upstream/main...main
git diff upstream/main...main -- dots/.config
git log --oneline upstream/main..main
```

The `dots/` tree contains the fork's committed upstream-relative edits.
`local/` contains additive personal files and LazyGit/system wrappers, while
`devices/` contains only hardware-specific overlays.
