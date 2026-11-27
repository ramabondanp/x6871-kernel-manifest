---
# SPDX-License-Identifier: GPL-2.0-only
name: find-fixes
description: >-
  Determine the bug-introducing commit and return a verified Fixes tag for
  an out-of-tree X6871 kernel module fix. Use when preparing or reviewing
  bug-fix patches, drafting their commit messages, or checking an existing
  Fixes tag.
---

<!--
Adapted from Sasha Levin's Linux kernel agents branch
(https://git.kernel.org/pub/scm/linux/kernel/git/sashal/linux.git,
commit afe85438baf9). Modified for X6871 OOT kernel modules on 2026-11-27.
-->

# Determine a Fixes tag

Inspect and report only. Do not edit files or create commits. If the origin
cannot be established from the available history, return no tag and explain
what is missing instead of guessing or fabricating a placeholder.

- First establish exactly which bug the fix addresses: the failure, how it is
  triggered, and the code involved. Trace only that bug. If the search leads to
  a different bug or subsystem, go back to the fix.
- Name a commit from the history of the target branch in the same out-of-tree
  repository (`x6871-android17-6.18` or `x6871-android16-6.12`). A commit that
  exists only on another branch, in an external donor repository, or in GKI
  `common` is not a valid `Fixes:` target for an out-of-tree commit (mention
  upstream/donor origins in the commit message body if helpful).
- Treat `git blame` output, an existing `Fixes:` tag, and a bisection result
  as leads, not answers. Follow the code back through moves, renames, file
  splits, 6.18 mechanical codemods, and refactors to the commit that made it
  wrong.
- For each candidate, compare the commit with its parent (`git show <sha>`)
  and explain why the code was correct before and wrong after. Keep apart the
  commit that imported or added the code, the commit that made it wrong, and
  a later commit that only made the bug reachable (which gets a `Fixes:` tag
  of its own if applicable).
- Check each parent of a merge, whether the bug was reverted and later
  reintroduced, and whether a port between `6.12` and `6.18` differs from its
  source commit.
- Check whether the clone is shallow (`git rev-parse --is-shallow-repository`).
  A shallow clone boundary is not an introducing commit; report the limit
  instead. Likewise, if the defect already existed in the initial donor import
  commit of the out-of-tree repository, report that explicitly rather than
  inventing a mainline Linux anchor commit.

Extract the commit ID and subject directly from the commit itself using:

    git log -1 --abbrev=12 --format='Fixes: %h ("%s")' <commit>

Return the verified `Fixes:` tag(s) with the explanation and the candidates
you rejected. If the origin cannot be established, return no tag and state
what is missing.
