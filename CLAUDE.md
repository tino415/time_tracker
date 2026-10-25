# track

Read README.md for project architecture details.

## Tasks

`just --list` is the complete command reference. Each recipe's `[doc]` line
states what it does, what it rebuilds or depends on, and any gotcha worth
knowing before running it — so the listing alone is enough to use a recipe
correctly. You should not need to open the Justfile to run something.

Keep it that way: if using a recipe requires knowing something the listing does
not say, the fix is to improve that recipe's `[doc]` line, not to document it in
README.md or here.

## Workflow

- we branch features from main
- when feature is done, it is going for pr
- merged to main

## Worktrees

A dev stack started from a worktree uses `compose.worktree.yaml`, which
publishes no ports, so it does not clash with the main checkout's stack, and
mounts the main checkout's `.git` so git works inside it:

    GIT_COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir) \
      podman compose -p <worktree dir> -f compose.worktree.yaml up -d

and the same variable, `-p` and `-f` for `down`.

## Backlog

The backlog is the board at Projects/TimeTracker/TODO: in the outliner, not
TODO.md. Read and add cards with the `outline` CLI.
