<!-- SPDX-License-Identifier: GPL-2.0-only -->

<!--
Adapted from Sasha Levin's Linux kernel agents branch
(https://git.kernel.org/pub/scm/linux/kernel/git/sashal/linux.git,
commit a81384aff4a3). Modified for X6871 OOT kernel modules on 2026-11-27.
-->

# Searching for a bug pattern with Coccinelle

Adapted for Bazel/Kleaf out-of-tree workspaces (`alps-kernel_device_modules`
and `alps-vendor_mediatek_kernel_modules`), where upstream `make coccicheck`
does not apply directly. Keep temporary rules and logs in `$TMPDIR` (never
`/tmp`).

1. If a kernel workspace is present, check `<ws>/common/scripts/coccinelle/`
   for an existing semantic patch that already covers the defect. Read its
   rules rather than its filename: `kfree()` of memory from `kvmalloc()` is
   covered by `api/kfree_mismatch.cocci`, while `api/kvmalloc.cocci` only
   flags an open-coded `is_vmalloc_addr()` test.

2. Otherwise, write a minimal semantic patch outside the repository in
   `$TMPDIR`. Match only what the defect needs, not names or statements
   specific to the fixed site. Mark the lines of interest with `*`, and
   declare `virtual context` (or `virtual report`); without `-D`, rules that
   depend on a virtual mode do not run. A minimal rule for `kvmalloc()`
   released with `kfree()`:

       virtual context

       @@
       expression E;
       @@
       E = \(kvmalloc\|kvzalloc\|kvcalloc\|kvmalloc_array\)(...);
       ...
       * kfree(E);

3. Check that the rule finds the site you fixed. Coccinelle reads files on
   disk, where the fix is usually already applied, so copy the pre-fix file to
   `$TMPDIR` and run:

       spatch -D context --very-quiet --sp-file <rule> <pre-fix-copy>

   The rule must mark the fixed site in that copy and nothing in the fixed
   version. If it misses the site, correct the rule before searching further.

4. Search the target out-of-tree module directory directly with `spatch`
   (pass `--include-headers` or add `// Options: --include-headers` at the
   top of the rule when headers must be checked, and redirect stderr to a new
   log file in `$TMPDIR`):

       spatch -D context --sp-file <rule> --dir <target-dir> 2>"$TMPDIR/spatch.log"

   - In `context` mode the output is a diff where lines starting with `-` are
     marked sites; `report` mode prints one warning per site.
   - Start with the relevant subsystem directory (for example, `drivers/gpu/`
     or `drivers/media/`) before widening to the full out-of-tree repo, and
     read `$TMPDIR/spatch.log` for parse or rule errors.

5. Check what was not searched. Coccinelle silently skips code it cannot
   parse. Run `spatch --parse-c <target-dir>`: a nonzero `nb bad` count means
   part of the code was skipped. Search those skipped files with `rg` or
   `git grep` and report the gap.

If the rule marks many sites that turn out to be safe, tighten it, for example
with `when !=` constraints, and run it again rather than discarding candidates
by hand.
