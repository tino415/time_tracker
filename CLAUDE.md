# GymTracker

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
