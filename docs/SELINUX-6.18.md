# SELinux `firmware_load` — syarat boot sistem 6.18

Diperbarui: 2026-11-23

Kernel 6.18 memeriksa `READING_FIRMWARE` di
`selinux_kernel_read_file()`, sedangkan 6.12 tidak. Policy Android 16
X6871 belum mendefinisikan permission `firmware_load`, sehingga
firmware yang dibaca `request_firmware()` dari domain `kernel` ditolak.

Gejala tanpa patch (`log pstore uji`/`log pstore uji`):

```text
mali: loading /vendor/firmware/mali_csffw.bin failed with error -13
haptic_hv: loading /odm/firmware/haptic_ram.bin failed with error -13
avc: denied { firmware_load } for ... scontext=u:r:kernel:s0
     tcontext=u:object_r:vendor_file:s0 tclass=system
```

Mali firmware gagal termuat → SurfaceFlinger crash berulang → zygote
restart loop → `hang_detect` reboot. **Boot ke sistem 6.18 memerlukan
patch SELinux ini**; patch bukan bagian dari kernel dan tidak mengubah
`kernel-6.18` (gate #7 tetap bersih).

## Isi patch

[`patches/selinux-x6871-6.18.patch`](../patches/selinux-x6871-6.18.patch):

1. `plat_sepolicy.cil` — tambah `firmware_load` ke
   `(class system (...))`.
2. `vendor_sepolicy.cil` — izinkan domain `kernel` membaca
   `same_process_hal_file` dan `vendor_file` dengan permission
   `firmware_load`.
3. `vendor_file_contexts` — label `/odm/firmware/haptic_ram.bin`
   sebagai `same_process_hal_file` (sama seperti `mali_csffw.bin`).

## Cara pasang

Ambil ketiga file dari image hasil ekstrak:

- `plat_sepolicy.cil` dari `system.img`:
  `system/system/etc/selinux/plat_sepolicy.cil`
- `vendor_sepolicy.cil` dan `vendor_file_contexts` dari `vendor.img`:
  `vendor/etc/selinux/`

```bash
mkdir -p selinux-x6871 && cd selinux-x6871
cp <extract-system>/system/system/etc/selinux/plat_sepolicy.cil .
cp <extract-vendor>/vendor/etc/selinux/vendor_sepolicy.cil .
cp <extract-vendor>/vendor/etc/selinux/vendor_file_contexts .
patch -p1 < $HOME/x6871-kernel-manifest/patches/selinux-x6871-6.18.patch
```

Kembalikan ketiga file ke path asalnya, lalu rebuild `system.img` dan
`vendor.img`.

Aturan pemakaian:

| Kondisi | File yang dipatch |
|---|---|
| System stock X6871 (Android 16) | `plat_sepolicy.cil` **dan** `vendor_sepolicy.cil` + `vendor_file_contexts` |
| System Android 17 (plat sudah punya `firmware_load`) | cukup vendor; jangan pakai `plat_sepolicy.cil` patch |
| `odm_dlkm`/ODM | jangan andalkan CIL jika `odm/etc/selinux/precompiled_sepolicy` ada; file binary itu mengabaikan CIL. Hapus/rename hanya jika memang ingin compile dari CIL |

Tanpa patch `plat_sepolicy.cil`, `secilc` gagal saat boot:

```text
Failed to resolve permission firmware_load
Failed to resolve allow statement at vendor_sepolicy.cil
```

sudah diuji dengan `secilc` 3.5.

## Verifikasi

Setelah boot:

```bash
dmesg | grep -E 'mali_csffw|haptic_ram|avc.*firmware_load'
```

Harus tidak ada lagi `failed with error -13` untuk kedua firmware;
SurfaceFlinger/zygote tidak crash berulang.

## Hasil uji

- Boot ke sistem 6.18: **PASS setelah patch SELinux** (system plat +
  vendor) dan `vendor_boot-6.18-test12-twrpfix.img`.
- TWRP touch/vibrator tidak memakai patch ini; itu diperbaiki lewat
  policy TWRP di `vendor_boot` (lihat
  [`PLAN-6.18-STATUS.md`](PLAN-6.18-STATUS.md#twrp-touch--vibrator-test12)).
