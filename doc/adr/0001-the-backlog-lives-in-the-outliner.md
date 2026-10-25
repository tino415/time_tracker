# 1. The backlog lives in the outliner

- **Status:** accepted, 2026-10-25
- **Applies to:** `CLAUDE.md`

## Context

The backlog was `TODO.md` in this repository. Every feature branch that added,
finished or reworded an item edited the same few lines, so parallel branches
conflicted on it, and each conflict was resolved by hand for no change to the
code.

## Decision

The backlog is the board at `Projects/TimeTracker/TODO:` in the outliner, with
the columns Deciding, Next, Implementing, Review and Done, read and changed
with the `outline` CLI. `TODO.md` is gone. The tasks that were in it and in
the Todoist TimeTracker project became cards in Next.

## Consequences

A branch no longer touches the backlog, so branches do not conflict on it.
The backlog is not versioned with the code, and a card cannot be reviewed in a
pull request.
