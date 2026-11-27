---
# SPDX-License-Identifier: GPL-2.0-only
name: find-siblings
description: >-
  Find other places in the out-of-tree X6871 kernel module repositories that
  have the same defect as a bug being fixed, and verify each candidate. Use
  after fixing or reviewing a bug fix, or when asked whether the same bug
  exists elsewhere.
---

<!--
Adapted from Sasha Levin's Linux kernel agents branch
(https://git.kernel.org/pub/scm/linux/kernel/git/sashal/linux.git,
commit a81384aff4a3). Modified for X6871 OOT kernel modules on 2026-11-27.
-->

# Find other instances of a bug

Inspect and report only. Do not modify sibling sites, shared interfaces, or
GKI `common` unless explicitly asked. Return the result with verified
evidence, or state what is missing instead of guessing.

- State the defect as a rule that does not depend on local names, such as
  "memory from `kvmalloc()` is released with `kfree()`", missing lock
  serialization, or missing `v4l2_fh` cleanup.
- Search the tree as it was before the fix across the out-of-tree module
  repositories (`alps-kernel_device_modules` and
  `alps-vendor_mediatek_kernel_modules`). Look at sibling drivers, copied
  MediaTek/Transsion/OPPO donor code, other users of the same interface,
  field, or lock, the introducing series, and earlier fixes for the same
  defect. Limit history searches to the relevant directories. Never suggest
  modifying GKI `common` for out-of-tree workarounds.
- If Coccinelle is available (`spatch --version` works), search for the defect
  with a semantic patch as described in
  [references/coccinelle.md](references/coccinelle.md). Otherwise use text
  searches (`rg` or `git grep`) and report that Coccinelle is unavailable.
- Treat every match as a lead. Read each candidate with its callers, locking,
  power/clock state, and object lifetimes, and classify it as `confirmed`,
  `safe`, or `undetermined` with the reason.
- For each confirmed site, check whether it is active on X6871 (enabled in
  `X6871.config` or referenced by stock DTB/DTBO) and whether it is already
  fixed on `x6871-android17-6.18` or `x6871-android16-6.12`.
- If several active sites share the same defect, check whether the shared
  helper or interface invites it. Report that finding alongside the sites;
  the developer decides whether to fix the interface or each site.

Return the searches run and their scope, any semantic patch used, and the
classified sites. Do not fix the sites or the interface.
