# SELinux `firmware_load` — syarat boot sistem 6.18

Diperbarui: 2026-11-23

Kernel 6.18 memeriksa `READING_FIRMWARE` di
`selinux_kernel_read_file()`, sedangkan 6.12 tidak. Policy Android 16
X6871 belum mendefinisikan permission `firmware_load`, sehingga
firmware yang dibaca `request_firmware()` dari domain `kernel` ditolak.

Gejala tanpa patch pada uji boot 6.18:

```text
[    5.798231] (NULL device *): loading /vendor/firmware/conninfra.cfg failed with error -13
[    5.798370] type=1400 audit(1795443978.936:55): avc:  denied  { firmware_load } for  comm="modprobe" path="/vendor/firmware/conninfra.cfg" dev="dm-6" ino=4038011 scontext=u:r:kernel:s0 tcontext=u:object_r:connsys_vendor_file:s0 tclass=system permissive=0
[    8.996140][ T1498] mali 13000000.mali: loading /vendor/firmware/mali_csffw.bin failed with error -13
[   10.470333] haptic_hv 3-005a: loading /vendor/firmware/haptic_ram.bin failed with error -13
[   43.194293] [MTK-WIFI] WIFI_write_on[E]: WMT turn on WIFI fail!
```

Mali firmware gagal termuat → SurfaceFlinger crash berulang → zygote
restart loop → `hang_detect` reboot. `conninfra.cfg` gagal dibaca →
`conninfra` tidak bisa power on → WiFi dan Bluetooth mati
(`WMT turn on WIFI fail`, `BT turn on fail`). **Boot ke sistem 6.18
memerlukan patch SELinux ini**; patch bukan bagian dari kernel dan
tidak mengubah `kernel-6.18` (gate #7 tetap bersih).

## Isi patch

[`patches/selinux-x6871-6.18.patch`](../../patches/selinux-x6871-6.18.patch):

1. `plat_sepolicy.cil` — tambah `firmware_load` ke
   `(class system (...))`.
2. `vendor_sepolicy.cil` — izinkan domain `kernel` membaca
   `same_process_hal_file`, `vendor_file`, dan `connsys_vendor_file`
   dengan permission `firmware_load`. `connsys_vendor_file` adalah
   label `conninfra.cfg`/`connfem.cfg`; tanpa ini WiFi/Bluetooth tidak
   bisa power on.
3. `vendor_file_contexts` — label `/odm/firmware/haptic_ram.bin`
   sebagai `same_process_hal_file` (sama seperti `mali_csffw.bin`).

Kalau `selinux-x6871-6.18.patch` versi lama sudah terpasang (baru
mengizinkan `same_process_hal_file`/`vendor_file`), tambahkan allow
`connsys_vendor_file` dengan patch inkremental
[`patches/selinux-x6871-6.18-connsys.patch`](../../patches/selinux-x6871-6.18-connsys.patch):

```bash
cd <dir-berisi-vendor_sepolicy.cil-hasil-patch>
patch -p1 < "$HOME/x6871-kernel-manifest/patches/selinux-x6871-6.18-connsys.patch"
```

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
patch -p1 < "$HOME/x6871-kernel-manifest/patches/selinux-x6871-6.18.patch"
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
dmesg | grep -E 'mali_csffw|haptic_ram|conninfra\.cfg|avc.*firmware_load|WMT turn on|BT turn on'
```

Harus tidak ada lagi `failed with error -13` untuk firmware tersebut;
SurfaceFlinger/zygote tidak crash berulang; `conninfra` power on dan
WiFi/Bluetooth bisa dinyalakan.

## Hasil uji

- Boot ke sistem 6.18: **PASS setelah patch SELinux** (system plat +
  vendor) dan `vendor_boot-6.18-test12-twrpfix.img`.
- Uji boot 6.18 (2026-11-23): boot dan touch jalan, tetapi WiFi dan
  Bluetooth sempat gagal karena `conninfra.cfg` berlabel
  `connsys_vendor_file`. Setelah `vendor_sepolicy.cil` (md5
  `5b0827a140e928900a4b91006fba301d`) memakai allow tersebut,
  **WiFi dan Bluetooth PASS** (dikonfirmasi pengguna 2026-11-23).
- TWRP touch/vibrator tidak memakai patch ini; itu diperbaiki lewat
  policy TWRP di `vendor_boot` (lihat
  [`BRINGUP-LOG.md`](../archive/6.18/BRINGUP-LOG.md#twrp-touch--vibrator-test12)).
