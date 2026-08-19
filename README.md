# end4_custom: the practical guide

This is the operating manual for the custom fork of
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland).

If you only remember one thing, use this entry point:

~~~bash
system tui
~~~

That opens LazyGit on the correct repository and loads the repository-owned
LazyGit configuration. Inside LazyGit, press Ctrl-G to open the end-4
maintenance menu.

This README explains the menu and the commands in two ways:

- **Technical meaning:** what Git, the deployment script, or the live system
  actually does.
- **Plain-language meaning:** what you should expect as a user.

CUSTOM.md contains the longer architecture and design notes. This file is the
day-to-day runbook.

## 1. Where everything lives

| Item | Exact location | Purpose |
| --- | --- | --- |
| Custom fork | /home/black/end4_custom | Git repository and source of truth |
| Normal command | /home/black/.local/bin/system | Wrapper that runs this repository's end4 command |
| Main script | /home/black/end4_custom/end4 | Git review, deployment, Neovim, and development dispatcher |
| Upstream-owned tree | /home/black/end4_custom/dots | Files inherited from end-4 and edited in their original paths when necessary |
| Personal overlay | /home/black/end4_custom/local | Personal configuration, LazyGit, system wrapper, and Neovim |
| Device overlay | /home/black/end4_custom/devices/<name> | Hardware-specific configuration, such as DarkArch |
| Live configuration | ~/.config | The files applications actually read |
| Live user data | ~/.local | Deployed scripts, data, icons, and related files |
| Repository LazyGit config | /home/black/end4_custom/local/.config/lazygit/config.yml | Version-controlled custom menu definition |
| Development worktrees | XDG_STATE_HOME/end4/worktrees | Feature branches attached to the live configuration |
| Development session | XDG_STATE_HOME/end4/dev/session | Record of the currently attached development branch |
| Development snapshots | XDG_STATE_HOME/end4/dev/snapshots | Pre-development live files retained for restoration/inspection |
| Neovim backups | XDG_STATE_HOME/end4/backups/nvim | Archives made before replacing live Neovim |

When XDG_STATE_HOME is not set, it means ~/.local/state. The actual resolved
paths are printed by system dev status.

There are two Git remotes:

~~~text
upstream  = end-4/dots-hyprland
origin    = the personal GitHub fork, if configured
~~~

main is the stable custom branch. Upstream changes arrive through
upstream/main; they do not replace this repository or copy files from a cache.

## 2. The mental model

| Technical meaning | Plain-language meaning |
| --- | --- |
| Git commits in end4_custom describe the desired configuration. | Git is the backup and history of your setup. |
| dots/ tracks end-4 files in their upstream paths. | If end-4 changes a file you also changed, Git shows the exact conflict. |
| local/ and devices/ are additive overlays. | Your personal and machine-specific settings are kept separate from end-4's files. |
| system merge fetches and prepares a normal three-way Git merge. | You can see what end-4 changed and decide what to keep. |
| system update deploys the committed repository state. | Updating the source does not change the running system until you approve deployment. |
| system dev start creates a linked Git worktree and links managed live files to it. | You can edit the live configuration directly while every edit is saved on a feature branch. |
| A development snapshot records the live targets before links are installed. | system dev stop can put the system back the way it was before experimenting. |

Normal deployment is file-aware. It does not delete unrelated live files by
default. Development mode uses individual file symlinks rather than replacing
whole configuration directories, so live extras can remain visible and be
classified later.

## 3. First-time activation

The implementation is committed in the repository, but deploying it is a
separate deliberate action. From a clean checkout:

~~~bash
cd /home/black/end4_custom
git status

# See exactly what would be deployed.
system update --dry-run --general

# Apply the repository-owned LazyGit config and the new Quickshell IPC.
system update --general
~~~

For a named device, replace --general with --device DarkArch.

system tui always loads the repository's LazyGit config directly, so it is the
most reliable way to use the menu even before the live LazyGit config has been
deployed. If Ctrl-G does nothing when running a separate LazyGit process, first
run system tui, or deploy the config above and restart LazyGit.

## 4. Opening and using the LazyGit system

Start LazyGit through the wrapper:

~~~bash
system tui
~~~

Then press:

~~~text
Ctrl-G
~~~

The following keys are inside the end-4 command menu. They are not global
LazyGit keys until the menu is open.

| Key | Menu option | Technical meaning | Plain-language meaning |
| --- | --- | --- | --- |
| r | Compare fork and upstream | Runs system review, showing the common base, this fork, and upstream/main without changing Git state. | Look at what end-4 changed and what this fork changed before merging anything. |
| m | Merge and review upstream | Runs system merge; fetches upstream, presents the structured review, then prepares a non-committing Git merge. | Bring in end-4's latest work and stop before committing so you can resolve every decision. |
| u | Preview and deploy | Runs system update; checks the repository, previews file changes, asks for a device and confirmation, then deploys. | Show me what will change on the computer, then install it only after I approve. |
| d | Discard Git state | Runs system discard; aborts an active merge, resets uncommitted tracked changes, and removes untracked non-ignored files after confirmation. | Throw away work that has not been committed. Committed history is kept. |
| l | Git/deployment status | Runs system status; displays branch, commits ahead/behind upstream, and fork-vs-upstream differences. | Give me a summary of where my configuration stands. |
| s | Development status | Runs system dev status; reports the active branch, worktree, link health, watcher, Git changes, and live candidates. | Tell me which experimental configuration is currently connected to the computer. |
| f | Refresh development links | Runs system dev refresh; rebuilds the source-to-live file map and reconciles new/deleted files. | Notice files I created or removed while experimenting. |
| c | Capture live-only files | Runs system dev capture; asks whether unlinked live files should be adopted, ignored, or left alone. | Find files that exist only on the computer and ask whether they belong in Git. |
| h | Reload development components | Runs system dev reload all; reloads Hyprland and calls the Quickshell end4Dev IPC handler. | Make the running desktop notice the latest experiment without restarting everything. |
| x | Stop and restore | Runs system dev stop; restores snapshotted managed targets and removes the live links while preserving live extras. | Stop experimenting and put the managed configuration back; unrelated live extras are left alone. |
| k | Stop and keep | Runs system dev stop --keep; copies the tested worktree files back as regular live files instead of restoring the snapshot. | Keep the experiment active on the computer, but end the special linked session. |

The m, u, and d actions include LazyGit conflict checks afterward. The
development actions only make sense while a development session is active;
the script refuses unsafe combinations such as updating main behind an
attached feature worktree.

## LazyGit in practice: how the TUI actually works

The repository LazyGit configuration has one custom global key: Ctrl-G. Ctrl-G
opens a second menu containing the end-4 commands. It does not replace normal
LazyGit Git operations.

The custom commands use output: terminal. Technically, LazyGit suspends its
screen, runs end4 with a real terminal so it can ask questions, and returns to
LazyGit when the command exits. In plain language, Ctrl-G actions are normal
interactive commands temporarily launched from inside LazyGit.

The environment flag END4_FROM_LAZYGIT=1 tells end4 that LazyGit is already open.
That prevents the merge/review commands from trying to open a second LazyGit
inside the first one.

### Main checkout versus development worktree

This distinction is essential when committing live configuration.

system tui opens the stable main checkout:

~~~text
/home/black/end4_custom
~~~

When a development session is active, the changed live files belong to the
separate feature worktree, not to main. Main can correctly show no changes while
the live experiment has many changes.

To commit live development changes in LazyGit:

~~~bash
system dev status
~~~

Copy the Worktree path printed by that command, then open that exact path:

~~~bash
lazygit --path "/path/printed-by-system-dev-status" \
  --use-config-file /home/black/end4_custom/local/.config/lazygit/config.yml
~~~

This LazyGit instance is looking at the feature branch that the live files are
linked to. Do not use system tui for this commit; system tui intentionally opens
main.

The Ctrl-G development actions still work from the feature-worktree LazyGit
instance:

- s shows the active development session;
- f refreshes the live link map;
- c captures live-only files;
- h reloads Hyprland and Quickshell;
- x restores the stable managed live files;
- k keeps the tested files deployed.

The l, r, m, u, and d custom actions invoke the main end4 repository and are
not the way to commit the feature worktree. Ordinary update/merge/discard
operations are also blocked while development is active.

### The normal Git actions inside LazyGit

These are the actions used to commit a live configuration change:

1. Open the feature worktree LazyGit as shown above.
2. Press 2 to focus the Files panel. Press ? if the installed LazyGit version
   shows a different panel layout.
3. Move to a file with the arrow keys or j/k.
4. Press Space to stage or unstage the selected file.
5. Press Enter on a file to inspect its diff and stage individual hunks or
   lines. Space stages the selected hunk/line; Esc returns to the file list.
6. Press a in the Files panel to stage all files when that is intentional.
7. Press c in the Files panel to commit the staged files.
8. Type a commit message and press Enter to confirm. If LazyGit opens an
   external editor, save the message and exit that editor.
9. Press 4 to inspect the resulting commit in the Commits panel.
10. Press P only when you intentionally want to push the feature branch.

Plain-language version: select the files that belong together, press Space to
put them in the next commit, press c, write what changed, and press Enter.
Nothing is committed merely because a file changed on the live system.

Useful standard LazyGit keys:

| Key | Where/when | What it does |
| --- | --- | --- |
| 1 | Anywhere | Focus the Status panel |
| 2 | Anywhere | Focus the Files panel |
| 3 | Anywhere | Focus branches/remotes/tags |
| 4 | Anywhere | Focus commits/reflog |
| 5 | Anywhere | Focus stash |
| j/k or arrows | List panels | Move the selection |
| Enter | Files panel | Open the diff/staging view; on a commit, view its files |
| Space | Files/staging view | Stage or unstage a file, hunk, or line |
| a | Files panel | Stage or unstage all files |
| c | Files panel | Commit staged changes |
| P | Global | Push the current branch |
| p | Global | Pull the current branch |
| f | Files panel | Fetch remote changes |
| R | Global | Refresh LazyGit's Git state; it does not fetch |
| W | Global | Open ref/diff comparison options |
| : | Global | Run a shell command from the repository directory |
| ? | Global | Show the installed LazyGit keybindings |
| q | Global | Quit LazyGit |

The installed version's ? help is authoritative if a future LazyGit release
changes a key. The custom Ctrl-G menu is defined in
local/.config/lazygit/config.yml.

### TUI equivalent for starting and developing a branch

The current custom menu does not have a dedicated start-branch key because
starting requires a branch name and optional device. Use LazyGit's built-in
shell bridge:

1. Start with system tui on main.
2. Press :.
3. Type the development command, for example:

~~~text
system dev start panel-experiment --device DarkArch
~~~

4. Press Enter and answer any confirmation prompt.
5. Quit that LazyGit instance with q.
6. Copy the worktree path from system dev status and open it with the
   lazygit --path command shown above.
7. Edit ~/.config normally. The managed files are now links into the feature
   worktree.
8. Use Ctrl-G, then s/f/c/h as needed.
9. Commit from the feature-worktree Files panel using Space and c.

This is the TUI workflow in plain language: use LazyGit's : command once to
start the special linked session, then use a LazyGit window opened on the
feature branch to save the live edits as Git commits.

### TUI equivalent for capturing active live changes

With an active development session:

1. Open the feature worktree in LazyGit.
2. Press Ctrl-G, then c.
3. Classify each candidate in the terminal prompt: a to adopt, i to ignore,
   or l to leave it live-only.
4. When the command returns, press R to refresh the Git view.
5. Stage the adopted files with Space and commit with c.

The terminal equivalent is system dev capture followed by git add and git
commit. The TUI version uses the same capture helper, then uses LazyGit's
Files panel for the actual commit.

For Neovim changes outside a development session, press : in the main LazyGit
window and run:

~~~text
system nvim import
~~~

There is no generic silent import of manually modified existing managed
non-Neovim files. Use : to run system dev capture for live-only files, or
copy an intentional edit into dots/ or local/ and then stage it in the
appropriate LazyGit window.

### TUI equivalent for reviewing and merging upstream

Use the main-checkout LazyGit window for upstream integration:

1. Press Ctrl-G, then r for the read-only three-way comparison.
2. Exit the comparison and press Ctrl-G, then m.
3. The m command fetches upstream and leaves a non-committing merge in the
   main checkout. LazyGit stays the Git review interface.
4. In the Files panel, select an unresolved file and press Enter.
5. In the conflict view, use Space to pick a hunk, b to pick both hunks, e to
   edit the complete file, or M for merge-conflict options.
6. Move between conflicts with the arrow keys or h/l.
7. Return to the Files panel, stage each resolved file with Space, and inspect
   the staged diff with Enter.
8. Run the checks from LazyGit by pressing : and entering system check.
9. Commit the staged merge with c in the Files panel.
10. Press Ctrl-G, then l, to inspect the resulting repository state.

For a one-file choice, the TUI equivalent of keeping a side is the conflict
options menu. The explicit shell fallback through : is:

~~~text
git restore --ours -- path/to/file
git add path/to/file
~~~

or:

~~~text
git restore --theirs -- path/to/file
git add path/to/file
~~~

Plain-language version: r lets you look, m starts the merge, Enter opens the
problem file, Space/b/e lets you choose how to combine it, Space marks it
resolved, and c saves the completed merge as a commit.

### TUI equivalent for deploying the merged setup

For the normal interactive deployment:

1. In the main LazyGit window, press Ctrl-G, then u.
2. The terminal preview shows the checks and deployment plan.
3. Choose General or the device overlay when prompted.
4. Read the preview and confirm.
5. LazyGit resumes after deployment. Press R to refresh its Git state.

For an explicit dry run or a named device, use LazyGit's : bridge instead:

~~~text
system update --dry-run --device DarkArch
~~~

When the preview is satisfactory, run the same command without --dry-run:

~~~text
system update --device DarkArch
~~~

The TUI option u is the same update operation, but it intentionally lets the
script ask for the deployment target. The : bridge is the TUI equivalent for
flags that are not represented by a dedicated menu key.

### TUI equivalent for committing a pre-upstream checkpoint

To make a Git backup before merging upstream:

1. Open main with system tui.
2. Press 2 for Files.
3. Inspect files with Enter.
4. Stage only intended files with Space or stage individual hunks/lines.
5. Press c, enter a checkpoint message, and confirm.
6. Press 4 for Commits, select the new checkpoint commit, and press T to create
   a tag such as before-upstream-20260819T120000Z.
7. Confirm the tag in the prompt.

The terminal equivalent is git add -p, git commit, and git tag. The TUI version
does the same operations without leaving LazyGit.

If the current live configuration is in an active development session, commit
the feature worktree first using the feature-worktree LazyGit window. Then
press Ctrl-G, x to restore stable live files, return to main LazyGit, and use :
to run:

~~~text
system dev integrate panel-experiment
~~~

Review and commit that prepared merge in the main LazyGit Files panel, then
create the checkpoint tag from the resulting commit.

### TUI equivalent for rollback

If an upstream merge is still uncommitted:

1. In main LazyGit, press Ctrl-G, then d.
2. Read the warning in the terminal.
3. Type DISCARD when requested.
4. LazyGit returns with the merge aborted and the uncommitted main state cleaned.

If a development experiment is active:

1. Open either LazyGit window with the active session available.
2. Press Ctrl-G, then x to restore the snapshotted managed live files, or k to
   keep the tested files.
3. Commit the feature branch later or leave it for another session.

If a bad upstream merge was already committed, select that merge commit in the
Commits panel (4) and press t to create a revert commit. For a merge commit
where Git asks for the mainline parent, press : and run the explicit command:

~~~text
git revert -m 1 <merge-commit>
~~~

After the revert is committed, press Ctrl-G, u to deploy the reverted source,
or use : for an explicit device/dry-run command.

For Neovim, press : and run system nvim rollback. It presents the independent
Neovim backup archives.

### TUI equivalent for commands without a custom key

The : key is the deliberate bridge between the TUI and the full command
interface. Run these from the main LazyGit window unless noted otherwise:

| Terminal command | LazyGit equivalent |
| --- | --- |
| system status | Ctrl-G, l |
| system review | Ctrl-G, r |
| system merge | Ctrl-G, m |
| system update | Ctrl-G, u; this uses the interactive device selector |
| system update --dry-run --general | Press :, type the command, Enter |
| system dev start BRANCH --device NAME | Press :, type the command, Enter; then open the printed feature worktree in a second LazyGit instance |
| system dev attach BRANCH or PATH | Press :, type the command, Enter; then open the attached worktree in LazyGit |
| system dev status | Ctrl-G, s |
| system dev refresh | Ctrl-G, f |
| system dev capture | Ctrl-G, c |
| system dev reload all | Ctrl-G, h |
| system dev reload hypr or quickshell | Press :, type the scoped command, Enter |
| system dev check | Press :, type system dev check, Enter |
| system dev sync | Press :, type system dev sync, Enter |
| system dev stop | Ctrl-G, x |
| system dev stop --keep | Ctrl-G, k |
| system dev integrate BRANCH | Press :, type system dev integrate BRANCH, Enter; review the prepared merge in main LazyGit |
| system dev remove BRANCH | Press :, type system dev remove BRANCH, Enter |
| system nvim status | Press :, type system nvim status, Enter |
| system nvim diff | Press :, type system nvim diff, Enter |
| system nvim check | Press :, type system nvim check, Enter |
| system nvim import | Press :, type system nvim import, Enter |
| system nvim deploy | Press :, type system nvim deploy, Enter |
| system nvim sync | Press :, type system nvim sync, Enter |
| system nvim rollback | Press :, type system nvim rollback, Enter |
| system check | Press :, type system check, Enter |
| system update --dry-run --device NAME | Press :, type the command, Enter |
| system update --device NAME | Press :, type the command, Enter, or use Ctrl-G, u for the interactive target menu |
| system update --prune --device NAME | Press :, type the command, Enter; read the deletion preview carefully |
| system discard | Ctrl-G, d |
| system bootstrap | Press :, type system bootstrap, Enter; this is not a normal update |
| system apply OPTIONS | Press :, type the command, Enter; compatibility path only |
| git tag | Commits panel (4), select commit, press T |
| git revert | Commits panel (4), select commit, press t |
| git push | Press P |
| git pull | Press p |

This table is intentional: custom keys cover the high-risk system actions, while
the : bridge keeps every lower-level command available without pretending that
all commands are native LazyGit panels.

### Do not use the ordinary LazyGit worktree action for system development

LazyGit's built-in w action can create a normal Git worktree. It does not run
the end4 development lifecycle: it does not snapshot the live configuration,
create the per-file links, preserve/classify live extras, or install the
session guard.

For system development, use : followed by system dev start. Use LazyGit's
ordinary w only when you explicitly want an unrelated plain Git worktree.


## 5. The command-line equivalents

The LazyGit menu is a convenient front end. These commands are useful when
you want a scriptable or more explicit workflow.

### Repository and deployment commands

| Command | Technical meaning | Plain-language meaning |
| --- | --- | --- |
| system | Opens the text/whiptail maintenance menu. | Pick review, merge, update, discard, or LazyGit from a menu. |
| system status | Prints Git branch state, custom commits, incoming upstream commits, and fork differences. | See the overall health of your setup. |
| system review | Performs a read-only three-way comparison: BASE, FORK, and UPSTREAM. | Inspect changes without starting a merge. |
| system merge | Fetches upstream, reviews it, and runs a non-committing merge. | Bring upstream changes in, but leave the final decision to you. |
| system check | Runs shell, Lua, Python, QML, Neovim, and plugin-lock checks that are available. | Test the configuration before installing it. |
| system update --dry-run --general | Runs checks and prints the deployment plan without changing live files. | Preview a general installation safely. |
| system update --dry-run --device DarkArch | Previews general plus the DarkArch device overlay. | Preview what this specific computer would receive. |
| system update --general | Checks, previews, confirms, and deploys the general configuration. | Install the committed setup after approval. |
| system update --device DarkArch | Checks, previews, confirms, and deploys general plus device configuration. | Install the setup for this machine. |
| system update --prune --device DarkArch | Also removes files deleted from upstream-managed directories. | Clean up old end-4 files too; use only when that deletion is intentional. |
| system discard | Requires a typed DISCARD, aborts a merge, resets uncommitted tracked files, and cleans untracked non-ignored files. | Undo all uncommitted repository work. This is destructive to uncommitted files. |
| system tui | Opens LazyGit on /home/black/end4_custom using the repository config. | Open the correct Git dashboard. |
| system bootstrap | Runs the upstream ./setup install command. | Re-run the large upstream installer only when you intentionally need it. |

system update never fetches or merges upstream and never runs setup install. The
normal order is: review/merge/commit first, deploy second.

### Neovim commands

| Command | Technical meaning | Plain-language meaning |
| --- | --- | --- |
| system nvim status | Compares the repository Neovim tree with live Neovim and checks for recursive trees/runtime artifacts. | Show whether live Neovim has drifted or contains suspicious copies. |
| system nvim diff | Opens a file-selectable, colored source/live comparison in a TTY. | Show me exactly which Neovim files differ. |
| system nvim check | Validates the tree, plugin lock state, Codex integration, commands, keymaps, executable, and adapter. | Confirm that Neovim and Codex are actually usable. |
| system nvim import | Reviews live Neovim files and adopts selected files into local/.config/nvim. | Bring intentional live Neovim changes back into Git. |
| system nvim deploy | Archives live Neovim, atomically replaces it from the repository tree, and runs health checks. | Install the repository Neovim setup with a rollback archive. |
| system nvim sync | Installs/synchronizes plugins from lazy-lock.json. | Make the installed plugins match the committed lockfile. |
| system nvim rollback | Restores a selected archive from ~/.local/state/end4/backups/nvim. | Put Neovim back to a previous saved version. |

## 6. Developing a new feature against the live system

This is the preferred workflow when you want to edit the live configuration,
reload it, and iterate without deploying after every line.

### Start an experiment

Make sure main is clean first. A development worktree is created from the
current HEAD and the main checkout must not contain loose changes.

~~~bash
cd /home/black/end4_custom
git status --short

system dev start panel-experiment --device DarkArch
~~~

Optional arguments:

~~~bash
system dev start panel-experiment --from main --device DarkArch
system dev start panel-experiment --device DarkArch --no-watch
~~~

Technical behavior:

1. A new branch named panel-experiment is created.
2. Its worktree is placed below XDG_STATE_HOME/end4/worktrees.
3. The current live targets are snapshotted.
4. Managed files become individual symlinks from the live tree into the
   feature worktree.
5. Live extras are not deleted.

In plain language: after dev start, edit ~/.config normally. The file you edit
is really the file in the feature branch, so every save changes the experiment
and Git can see it.

Find the exact worktree path at any time:

~~~bash
system dev status
~~~

### Iterate

~~~bash
system dev status
system dev check
system dev reload all
~~~

If inotifywait is installed, the watcher reloads Hyprland and Quickshell after
relevant files change. If it is not installed, the session still works; use
system dev reload all yourself. Neovim is intentionally not restarted
automatically; restart or reload it explicitly.

When you create or delete a file that was not part of the original link map:

~~~bash
system dev refresh
~~~

The refresh links new branch files and restores the old live target for files
deleted from the branch. It does not commit anything.

### Capture live-only files

Use this when a file already exists in the live configuration but is not yet
represented by the branch:

~~~bash
system dev capture
~~~

For every candidate, choose:

- a — adopt it into the feature branch and link it;
- i — ignore it for this development session;
- l — leave it on the live system without adding it to Git.

The following are automatically treated as runtime/noise and are not offered
as normal capture candidates: Git metadata, Python caches, Python bytecode,
logs, Neovim generated colors, scratch files, backup themes, and Hyprland
backup directories.

For intentional automation only:

~~~bash
system dev capture --yes
~~~

--yes adopts all safe candidates without asking. It is not a general backup
button; inspect system dev status afterward and review the branch diff.

### Commit or abandon the experiment

The worktree path is printed by system dev status. Use that path below:

~~~bash
git -C /path/from-system-dev-status status
git -C /path/from-system-dev-status diff
git -C /path/from-system-dev-status add -p
git -C /path/from-system-dev-status commit -m "Experiment with panel layout"
~~~

To restore the snapshotted managed live files while keeping the branch for later:

~~~bash
system dev stop
~~~

To leave the tested files active as ordinary live files:

~~~bash
system dev stop --keep
~~~

The default stop is the safer choice while iterating. --keep ends the linking
session but deliberately leaves the experimental files deployed; make sure the
branch is committed before relying on those files. Files that were never part
of the managed link map are preserved by either stop policy.

### Integrate a finished feature

From the main checkout, with the feature branch clean and committed:

~~~bash
system dev integrate panel-experiment
~~~

Technical behavior:

- captures any remaining live-only candidates interactively;
- requires the feature worktree to be clean;
- stops the active development session and restores stable live files;
- runs checks on the feature branch;
- prepares git merge --no-ff --no-commit panel-experiment on main;
- leaves the merge uncommitted for review.

Plain-language meaning: the experiment is brought back into the stable Git
branch, but the system does not silently accept or commit it.

Review and finish it:

~~~bash
system tui
# Ctrl-G, then l or normal LazyGit review
system check
git status
git diff --cached
git add path/to/resolved/file
git commit -m "Integrate panel experiment"
system dev remove panel-experiment --delete-branch
~~~

If you want to keep the branch for more work, omit --delete-branch and use
system dev attach panel-experiment later.

## 7. Capture the current configuration before an upstream update

There are two kinds of backup: the Git source backup and the live-file backup.
Use both when the current state matters.

### A. Create a Git checkpoint

If the intended current configuration is already represented in the
repository:

~~~bash
cd /home/black/end4_custom
git status
git diff
git add -p
git commit -m "Checkpoint current configuration before upstream update"

checkpoint="before-upstream-$(date -u +%Y%m%dT%H%M%SZ)"
git tag -a "$checkpoint" -m "Known-good configuration before upstream update"
printf 'Created checkpoint: %s\n' "$checkpoint"
~~~

Technical meaning: the exact pre-merge source state now has both a commit and an
easy-to-find tag. Plain-language meaning: you have a named save point.

Do not use git add -A blindly if the repository contains files you have not
reviewed. Use git status and git add -p so generated or accidental files do not
become part of the checkpoint.

### B. Save live files that are not in Git

For Neovim, use the purpose-built importer:

~~~bash
system nvim import
~~~

For a linked development session that is already active:

~~~bash
system dev status
system dev capture
# Commit the worktree shown by system dev status.
git -C /path/from-system-dev-status add -p
git -C /path/from-system-dev-status commit -m "Capture current live configuration"
system dev stop
system dev integrate <that-branch>
~~~

system dev capture is for live-only files and newly discovered files. A
manually edited file that was already managed by the source tree is not
silently imported: this is intentional protection against capturing generated
runtime state. Compare such a file and copy the intentional change into the
appropriate repository path (dots/ for an upstream-owned file or local/ for a
personal overlay), then commit it.

For an additional archive of likely live configuration paths, before making
changes you can create one outside the Git repository:

~~~bash
backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/end4/manual-backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup_dir"
tar -C "$HOME" -czf "$backup_dir/live-config.tar.gz" \
    .config .local/bin .local/share
printf 'Live archive: %s\n' "$backup_dir/live-config.tar.gz"
~~~

This archive is supplementary. Git remains the authoritative, reviewable
backup for configuration that belongs in the repository.

## 8. Merge upstream changes, combine them with the current setup, and deploy

This is the complete example for preserving the current custom setup while
adopting new end-4 changes.

### Step 1: checkpoint the current state

Complete the Git checkpoint in the previous section. If live-only changes
exist, capture and commit them first. Confirm:

~~~bash
git status --short
git log -1 --oneline
git tag --list 'before-upstream-*' --sort=-creatordate | head
~~~

main should be clean and the checkpoint should identify the known-good state.

### Step 2: review upstream without changing anything

~~~bash
system review
~~~

Technical meaning: this is a read-only comparison of the common base, main, and
the locally known upstream/main. It does not create a merge.

Plain-language meaning: look at the proposed update first.

In LazyGit, the equivalent is system tui, Ctrl-G, then r.

### Step 3: prepare the merge

~~~bash
system merge
~~~

This fetches upstream/main, repeats the structured review, and prepares a
non-committing merge. The three roles mean:

~~~text
BASE      the last commit shared by this fork and end-4
FORK      your current main branch, also called ours
UPSTREAM  end-4's fetched upstream/main, also called theirs
~~~

Files changed on both sides are the important ones. Git marks unresolved paths
as conflicts; it does not choose a custom policy for you.

### Step 4: resolve each decision

Use LazyGit's conflict view, or use these explicit Git choices:

~~~bash
# Keep this custom fork's version of one file.
git restore --ours -- path/to/file
git add path/to/file

# Keep end-4's upstream version of one file.
git restore --theirs -- path/to/file
git add path/to/file
~~~

For a real combination, open the file, remove conflict markers, preserve the
desired parts from both sides, test it, and stage it:

~~~bash
$EDITOR path/to/file
git add path/to/file
~~~

Check the result before committing:

~~~bash
git status
git diff --cached --check
git diff --cached
system check
~~~

When every conflict is resolved and checks pass:

~~~bash
git commit -m "Merge upstream/main into custom main"
~~~

The merge is now part of Git history, but it is not live yet.

### Step 5: preview the deployment target

General configuration only:

~~~bash
system update --dry-run --general
~~~

General plus this machine's overlay:

~~~bash
system update --dry-run --device DarkArch
~~~

Read the preview. The default preserves live extras in upstream-managed
directories. Use --prune only if you deliberately want upstream deletions to
remove matching live files:

~~~bash
system update --dry-run --prune --device DarkArch
~~~

### Step 6: deploy after the preview is understood

~~~bash
system update --device DarkArch
~~~

The command checks again, shows the plan again, asks for confirmation, and then
deploys. For a general-only installation use --general.

Afterward:

~~~bash
system status
system nvim check
~~~

If the new Quickshell source was deployed while Quickshell was running, restart
or reload that Quickshell instance as appropriate. system update reloads
Hyprland when available; the development-only system dev reload quickshell
command requires an active linked development session.

## 9. Roll back safely if the merge or deployment goes wrong

The correct rollback depends on where the failure happened.

### Failure before the merge was committed

If system merge is still in progress or you dislike the uncommitted result:

~~~bash
system discard
~~~

Type DISCARD when prompted. This aborts the merge, resets uncommitted tracked
files, and removes untracked non-ignored files. It does not remove the
checkpoint commit, tags, ignored files, or committed history.

In LazyGit, use Ctrl-G, then d.

### Failure during a development experiment

While the session is still active:

~~~bash
system dev stop
~~~

This restores the pre-session snapshot for managed live targets and leaves the
feature worktree available for later inspection. Live extras are preserved. The
snapshot path is printed by the command; use the default stop while the session
is active when you need the supported automatic restoration path.

Do not use system dev stop --keep if your goal is rollback; --keep is the
explicit “leave the experiment deployed” choice.

### Failure after a merge commit but before deployment

If the merge commit is the latest commit and you have not pushed it, the
safest history-preserving rollback is a revert:

~~~bash
git log --oneline --graph -5
git revert -m 1 <merge-commit>
system check
~~~

The revert creates a new commit that returns the source tree to its pre-merge
behavior. If the source was never deployed, no live update is needed.

### Failure after deployment

First create a revert commit as above, then redeploy the reverted source:

~~~bash
git revert -m 1 <merge-commit>
system check
system update --dry-run --device DarkArch
system update --device DarkArch
~~~

This restores repository-managed files. Live extras that were not managed by Git
are intentionally preserved by the default deployment. If you used --prune,
files removed from live storage need to come from the manual archive or another
backup.

For a Neovim-specific failure, use its independent archive rollback:

~~~bash
system nvim rollback
~~~

### Exact pre-merge source restoration without rewriting history

Find the checkpoint and make a normal revert or a new recovery branch from it:

~~~bash
git tag --list 'before-upstream-*' --sort=-creatordate
git show before-upstream-YYYYMMDDTHHMMSSZ --stat
git switch -c recovery/pre-upstream before-upstream-YYYYMMDDTHHMMSSZ
~~~

Do not use git reset --hard on main unless you explicitly intend to rewrite
local branch history and understand what has already been pushed. git revert is
the normal recovery operation.

## 10. Important safety rules

- Commit or inspect changes before starting a development worktree. dev start
  requires a clean main checkout.
- Do not run ordinary merge, update, discard, or standalone Neovim deployment
  while a linked development session is active. The script blocks these
  operations to protect the experiment and stable live state.
- system discard is destructive to uncommitted, non-ignored repository files.
  Use it only when that is what you want.
- --yes skips confirmation. Use it for deliberate automation, not as a default
  interactive habit.
- --prune can remove live files in upstream-managed directories. The normal
  update path preserves extras.
- system dev capture --yes adopts live candidates into the development branch.
  Review the resulting Git diff before committing.
- The default development exit is system dev stop, which restores the stable
  snapshot. Use --keep only when leaving the test deployed is intentional.
- The old workflow of git stash && git pull && ./setup install is obsolete. Use
  system merge, review/resolve/commit, then system update.

## 11. Quick troubleshooting

### Ctrl-G does nothing

Use the authoritative launcher:

~~~bash
system tui
~~~

If it still does not appear, verify LazyGit is installed and deploy/restart
the config:

~~~bash
system update --dry-run --general
system update --general
~~~

The repository config is at
/home/black/end4_custom/local/.config/lazygit/config.yml.

### “A linked development session is active”

Inspect it:

~~~bash
system dev status
~~~

Finish it with system dev stop or intentionally keep it with
system dev stop --keep. Do not use system discard to manage a development
session; it is for the main repository's uncommitted Git state.

### The watcher says inotifywait is unavailable

Development linking still works. Reload explicitly:

~~~bash
system dev reload hypr
system dev reload quickshell
~~~

Or install the distribution package that provides inotifywait if automatic
reloads are important.

### system dev start says the main worktree is dirty

Inspect before changing anything:

~~~bash
git status
git diff
~~~

Commit the intended checkpoint, or deliberately resolve/discard the unwanted
changes. Do not stash blindly; a named checkpoint is easier to understand and
recover.

### A merge conflict is confusing

Use system tui, inspect the conflicted file in LazyGit, and decide per file:

- keep ours for this fork;
- keep theirs for end-4;
- manually combine both;
- abort with system discard if the merge should not continue.

Always run system check before committing the merge.

## 12. The shortest reliable recipes

### Develop, test, and integrate

~~~bash
system dev start my-change --device DarkArch
system dev status
# edit ~/.config and test normally
system dev capture
system dev check
system dev stop
# commit the worktree shown by dev status
git -C /path/to/worktree add -p
git -C /path/to/worktree commit -m "Implement my change"
system dev integrate my-change
system check
git commit -m "Integrate my change"
system dev remove my-change --delete-branch
~~~

### Update from end-4 and deploy

~~~bash
git add -p
git commit -m "Checkpoint before upstream update"
git tag -a "before-upstream-$(date -u +%Y%m%dT%H%M%SZ)" -m "Pre-upstream checkpoint"
system review
system merge
# resolve conflicts, then:
system check
git add path/to/resolved/file
git commit -m "Merge upstream/main into custom main"
system update --dry-run --device DarkArch
system update --device DarkArch
~~~

### Abort the update before it is committed

~~~bash
system discard
~~~

### Undo an already deployed upstream merge

~~~bash
git log --oneline --graph -5
git revert -m 1 <merge-commit>
system check
system update --device DarkArch
~~~
