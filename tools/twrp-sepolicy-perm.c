// SPDX-License-Identifier: GPL-2.0
/*
 * Mark the "kernel" domain permissive in a compiled SELinux policy.
 *
 * TWRP's /sepolicy is policy v30 and does not define the firmware_load
 * permission that 6.18 checks for READING_FIRMWARE. The recovery domain
 * is permissive there, but request_firmware() runs as the kernel domain,
 * so goodix cfg/firmware and haptic_ram.bin are denied. Setting the
 * kernel domain permissive restores the 6.12 behaviour for TWRP only.
 *
 * Build (needs libsepol-dev):
 *   gcc -O2 -o twrp-sepolicy-perm twrp-sepolicy-perm.c \
 *       /usr/lib/x86_64-linux-gnu/libsepol.a -lpcre
 *
 * Usage:
 *   twrp-sepolicy-perm <policy-in> <policy-out>
 *   twrp-sepolicy-perm --check <policy>
 */
#include <stdio.h>
#include <string.h>
#include <sepol/policydb/policydb.h>
#include <sepol/policydb/ebitmap.h>

static int open_pf(policy_file_t *pf, const char *path, const char *mode)
{
	FILE *f = fopen(path, mode);

	if (!f) {
		perror(path);
		return -1;
	}
	policy_file_init(pf);
	pf->type = PF_USE_STDIO;
	pf->fp = f;
	return 0;
}

int main(int argc, char **argv)
{
	policydb_t p;
	policy_file_t in, out;
	type_datum_t *t;
	int check, rc = 1;

	check = argc == 3 && !strcmp(argv[1], "--check");
	if (!check && argc != 3) {
		fprintf(stderr,
			"usage: %s <policy-in> <policy-out>\n"
			"       %s --check <policy>\n",
			argv[0], argv[0]);
		return 2;
	}

	if (policydb_init(&p)) {
		fprintf(stderr, "policydb_init failed\n");
		return 1;
	}
	if (open_pf(&in, check ? argv[2] : argv[1], "rb"))
		return 1;
	if (policydb_read(&p, &in, 0)) {
		fprintf(stderr, "policydb_read failed\n");
		goto done;
	}
	fclose(in.fp);

	t = hashtab_search(p.p_types.table, "kernel");
	if (!t) {
		fprintf(stderr, "type kernel not found\n");
		goto done;
	}

	if (check) {
		printf("kernel sid=%u permissive=%d\n", t->s.value,
		       ebitmap_get_bit(&p.permissive_map, t->s.value) ? 1 : 0);
		rc = 0;
		goto done;
	}

	if (ebitmap_set_bit(&p.permissive_map, t->s.value, 1)) {
		fprintf(stderr, "ebitmap_set_bit failed\n");
		goto done;
	}
	if (open_pf(&out, argv[2], "wb"))
		goto done;
	if (policydb_write(&p, &out)) {
		fprintf(stderr, "policydb_write failed\n");
		goto done;
	}
	fclose(out.fp);
	printf("kernel permissive set (sid %u)\n", t->s.value);
	rc = 0;
done:
	policydb_destroy(&p);
	return rc;
}
