---
# SPDX-License-Identifier: GPL-2.0-only
name: commit-message
description: >-
  Write, rewrite, or review commit messages for the X6871 kernel manifest and
  out-of-tree module repositories following project conventions. Use when
  committing changes, drafting patch descriptions, or checking commit message
  style and checkpatch compliance.
---

<!--
Adapted from Sasha Levin's Linux kernel agents branch
(https://git.kernel.org/pub/scm/linux/kernel/git/sashal/linux.git,
commit d19a42b5d636). Modified for X6871 manifest and OOT modules on 2026-11-27.
-->

# Write a commit message

Draft or review commit messages in accordance with `AGENTS.md`. Do not run
`git commit` or `git commit --amend` unless explicitly asked. Do not amend an
existing fix or analysis commit unless requested by the user; follow-up
corrections must be new commits.

## Repository-specific format (`AGENTS.md` rules)

- **Manifest repository (`x6871-kernel-manifest`):**
  - Write subject and body in **Indonesian**, wrapped around 72 columns.
  - Use the `6.18:` prefix **only** for 6.18-specific topics (and ensure `6.18`
    appears at most once in the subject).
  - For general or cross-version topics (`AGENTS.md`, `tools/`, `BUILD.md`,
    `DEVICES.md`, `.agents/`), use a topic prefix (`docs:`, `tools:`,
    `manifest:`, `agents:`) without `6.18:`.
- **Kernel/vendor module repositories (`alps-kernel_device_modules`,
  `alps-vendor_mediatek_kernel_modules`):**
  - Write subject and body in **English**, wrapped around 72 columns, using
    standard Linux kernel commit style (`subsystem: ...`).
  - **Never** add a `6.18:` prefix.
  - End 6.18-only commit subjects with `for 6.18`.
  - When a fix applies to both `x6871-android17-6.18` and
    `x6871-android16-6.12`, omit `for 6.18` and apply the commit to both
    branches.

## Content and evidence rules

- Keep **one logical change per commit**; never bundle unrelated bugfixes, mix
  pure code moves with behavior modifications, or make pure reformatting
  commits on legacy vendor code.
- Explain the problem, user/system-visible impact (to aid 6.18/6.12 backport
  decisions), and technical solution, stating only what the diff and verified
  sources support (build results, device verification, quoted log lines, commit
  hashes, or MD5 checksums). Explicitly note what was **not** tested when
  relevant (e.g., compile-tested only, 6.12 not built). If the reason for the
  change is unknown, return no message and say what is missing.
- Never mention local log filenames (`pstoreX`, `dmesgX`, `logcatX`, `twrpX`),
  local machine paths, or temporary download URLs; quote log lines instead.
- Use the imperative mood and keep the message as short as its content
  allows. Leave out markdown formatting, labels such as `"Root cause:"`,
  intensifiers, restatements of the subject, and narration of the
  investigation.
- When citing another commit in the body, include at least 12 characters of
  its SHA-1 and its oneline summary: `Commit 1234567890ab ("summary")`.
- When quoting kernel oops/dmesg backtraces, trim timestamps, module lists, and
  raw register/stack dumps down to the essential error line and call trace.
- Name the analysis or verification tool that detected or verified the issue
  (e.g., `scan-cfi-tracepoints.py`, `check-private-structs.py`,
  `verify-kmi-abi.py`, `sparse`, or Coccinelle). If a Coccinelle semantic
  patch found the bug, include it between `// <smpl>` and `// </smpl>` lines
  or give its path under `common/scripts/coccinelle/`.

## Trailers and checkpatch

- Always include `Signed-off-by: Rama Bondan Prakoso <ramanarubp@gmail.com>`.
- Take `Fixes:` tags only from the `find-fixes` skill and never line-wrap
  `Fixes:` lines (exempt from the 72/75-column wrap limit). Add
  `Reviewed-by:`, `Tested-by:`, or `Acked-by:` only with explicit
  permission/supply; never add unverified or upstream mailing-list tags.
- Validate the commit message with `checkpatch.pl` (for example,
  `<ws>/common/scripts/checkpatch.pl --git HEAD` or on a generated patch
  before pushing) and ensure 0 commit-message errors. Per `AGENTS.md`,
  `MAINTAINERS`, `FILE_PATH_CHANGES`, code warnings, DOS line endings, and
  Indonesian spelling false positives may be ignored.
