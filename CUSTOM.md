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

## Daily workflow

```bash
cd /home/black/end4_custom
./end4 status
./end4 update
```

`end4 update` fetches `upstream/main` and starts a non-committing merge. It
never stashes work or installs files. Review the staged merge, resolve any
conflicts, and commit it:

```bash
git diff --cached
git restore --ours -- path/to/file       # keep this fork
git restore --theirs -- path/to/file     # keep upstream
git add path/to/file
./end4 check
git commit -m "Merge upstream/main into custom main"
```

Abort an unwanted merge with `git merge --abort`.

Inspect the fork's intentional deviation from upstream with:

```bash
git diff --stat upstream/main...main
git diff upstream/main...main -- dots/.config
git log --oneline upstream/main..main
```

## Deployment

Always review first:

```bash
./end4 check
./end4 apply --dry-run
./end4 apply --device DarkArch --dry-run
```

Then apply the committed state interactively:

```bash
./end4 apply --device DarkArch
```

`./end4 bootstrap` is reserved for the upstream dependency/full installer.
Normal updates use Git plus `./end4 apply`; they do not use the old `.new`
file workflow.
