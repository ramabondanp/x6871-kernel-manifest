# Arsip Percobaan Repack & Ringkasan DLKM 6.12 (eks BOOTTEST §9–§11)

> **Arsip historis (read-only).** Dokumen ini menyimpan catatan percobaan repack
> manual awal dan ringkasan histori DLKM `v1`–`v19-kmi6` yang sebelumnya berada di
> `docs/BOOTTEST.md` (§9–§11).
>
> Untuk prosedur repack otomatis, flash, dan patch `abie-zstd-ramdisk.patch` yang aktif,
> gunakan [BUILD.md](../../guides/BUILD.md) dan [FLASH-AND-TEST.md](../../guides/FLASH-AND-TEST.md).

## 1. Repack dengan cfig/Android_boot_image_editor (historis)

Selain `tools/pack-vendor-boot.sh`, image bisa direpack dengan
[`cfig/Android_boot_image_editor`](https://github.com/cfig/Android_boot_image_editor)
(commit `f692aff`) — dipakai untuk uji boot ketiga karena lebih ketat soal
format ramdisk.

```bash
cd ~/tmp
git clone --depth 1 https://github.com/cfig/Android_boot_image_editor.git vbwork
cd vbwork
cp /path/stock/vendor_boot.img .          # nama harus vendor_boot.img
./gradlew unpack                          # -> build/unzip_boot/

# ganti modul: root.1 = fragment PLATFORM (tempat lib/modules), root.2 = RECOVERY
M=build/unzip_boot/root.1/lib/modules
rm -f $M/*.ko
cp <staging-217>/*.ko $M/
cp <staging-217>/modules.{dep,alias,softdep,load,load.recovery} $M/

./gradlew pack                            # menimpa ./vendor_boot.img
```

Hasil pack sudah dipad sampai ukuran partisi (67.108.864 byte). Yang perlu
diperiksa setelahnya:

```bash
unpack_bootimg.py --boot_img vendor_boot.img --out chk
md5sum chk/dtb chk/bootconfig chk/vendor_ramdisk01     # harus sama dengan stock
lz4 -d -c chk/vendor_ramdisk00 | cpio -it | wc -l      # 720 entri
lz4 -d -c chk/vendor_ramdisk00 | cpio -it | grep -c '\.ko$'   # 217
```

Catatan dari uji ketiga (`pstore3.txt`): kernel berhenti di **0.41 detik**,
sebelum init, dengan `rootfs image is not initramfs (broken padding)` lalu
`RAMDISK: incomplete write (-28 != 8388608)` dan panic `VFS: Unable to mount
root fs`. Artinya initrd ditolak sebagai initramfs sehingga **tidak ada satu
modul pun yang dimuat** — kegagalan packaging, bukan driver. Repack dengan
tool ini menghasilkan arsip newc yang sah (diawali entri `adb_keys` seperti
stock, `TRAILER!!!` + padding nol, magic lz4 legacy `02 21 4c 18`).

## 2. Ramdisk zstd (TWRP) — catatan tool (historis)

Image TWRP untuk X6871 memakai ramdisk **zstd** (`28 b5 2f fd`), bukan lz4.
`cfig/Android_boot_image_editor` (commit `f692aff`) belum mengenalnya:
`./gradlew unpack` berhenti dengan `ramdisk is in unknown format`.

Patch: [`patches/abie-zstd-ramdisk.patch`](../../../patches/abie-zstd-ramdisk.patch)
(dibuat terhadap `f692aff`). Untuk langkah setup aktif, lihat
[BUILD.md](../../guides/BUILD.md#setup-patch-zstd-untuk-android_boot_image_editor).

```bash
git apply "$HOME/x6871-kernel-manifest/patches/abie-zstd-ramdisk.patch"
```

Isinya:

- `helper/.../ZipHelper.kt` — `getZstdProg()`, `hasZstd`, `isZstd()` (deteksi
  lewat magic, bukan binary), `zstdcat()`, `zstd()` (kompres `-15 -T0`)
- `bbootimg/.../Common.kt` — cabang `isZstd` di `dumpRamdisk` (suffix `.zst`)
  dan cabang `.zst`/`.zstd` di kedua `packRootfs`
- `bbootimg/.../cpio/AndroidCpio.kt` — `fis.skip(bytesRead - 128)` melempar
  `IOException: Invalid argument` untuk ramdisk kosong (fragment TWRP
  `emptyrecovery` 60 byte); sekarang di-skip hanya kalau nilainya positif

### Repack TWRP manual awal dengan modul campuran

```bash
cd vbwork-twrp           # clone editor + patch, taruh vendor_boot.img
./gradlew unpack
# root.1 = fragment PLATFORM (berisi lib/modules), root.2 = emptyrecovery
M=build/unzip_boot/root.1/lib/modules
rm -f $M/*.ko
cp <set-modul>/*.ko $M/ && cp <set-modul>/modules.{dep,alias,softdep,load,load.recovery} $M/
./gradlew pack
```

Untuk X6871 saat uji awal hasilnya: 240 modul, `modules.load.recovery` 236 entri,
ramdisk tetap zstd, `dtb`/`bootconfig` identik TWRP asli, fragment
`emptyrecovery` isinya sama (hanya ukuran terkompresi 60 → 61 byte), image
dipad ke 67.108.864 byte.

Catatan komposisi awal (pra-DLKM 100% source): set TWRP = 237 modul stock + `adaptive-ts`,
`gt9916_common`, `tran_richtap_haptic_hv`. Modul yang kita build diganti versi
kita (termasuk panel `panel-rm69220-vdo-x6871.ko` menggantikan
`rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.ko`), sisanya tetap versi
TWRP/stock — `adaptive-ts` butuh `cloudengine_*` dari `transsion_tranlog`
yang tidak kita build, jadi modul itu harus tetap ada agar sentuhan hidup.

## 3. DLKM 100% Source (2026-11-20 s.d. 2026-11-22)

`vendor_dlkm` (**209** modul pada KMI 6 setelah mengeluarkan 3 modul GKI terproteksi `rfkill`/`bluetooth`/`libarc4`, `modules.load` 191; sebelumnya 212 modul pada KMI 5) dan `odm_dlkm` (**57** modul,
`modules.load` 57) dibangun 100% dari source menggunakan EROFS dengan opsi
identik stock + AVB hashtree footer yang dipertahankan. Template konfigurasi EROFS (`fs_config`, `file_contexts`, `/etc`, daftar modul) dibundel di `tools/dlkm/` dan direpack otomatis oleh `tools/repack-dlkm-latest.sh`.

Artefak DLKM terbaru (`gki-kmi6-20261122`, kernel `20a8f5d` / `fa18f7f`, raw `.img` untuk `fastbootd`):

```text
x6871-twrp-vendor_boot-v19-kmi6.img  md5 91eb249ff001d250fad855c40476f1b5  67.108.864 B
vendor_dlkm.img                      md5 5f7b6cecb1c44a1ffc3280dd481fbfcf  24.551.424 B
odm_dlkm.img                         md5 6ee3cadceb5c4750dbbfe3d0056b6ea8   4.206.592 B
```

Ringkasan perbaikan DLKM + `vendor_boot` yang sudah masuk hingga `v19-kmi6`:

- **Boot system dasar (`dlkm-20261120`..`gpu3`)**: `SCP_IPI_COUNT` 56→59, GPU Mali r54p1-11eac0 donor OPPO + fix padding `gpufreq_shared_status` (`power_count` 0x24..`active_count` 0x34, `temperature` 0x38, `shader_present` 0xe0).
- **Battery OC & layar (`v2`–`v3`)**: `rfg-mtk-tran-conf-diff`, timing/VFP 144/120/60/40 Hz, C3D dual-pipe SRAM, dan `PQ_VIRTUAL_SET_PROPERTY` 12 B — **layar terverifikasi normal penuh**.
- **Audio, AOD & kamera (`v4`–`v6`)**: FS1599 PA + `tran_audio_control`, AOD RM69220, 4 sensor kamera X6871 (`s5khm6sx`/`gc32e1`/`gc02m3`/`gc02m3macro`) + `camera_eeprom_v4l2`, `mtk-cam-isp` inline `sink_fmt`, dan flashlight `ocp81375_v4l2`.
- **VENC, DT2W & FOD (`v7`–`v10`)**: QP ABI 6-field, `VENC_H264 = 1`, `mtk_codec_capability` 24 B + ADAB 4x `U32`, `slbc_request`, enum notifier AOD/HBM DRM, `adaptive-ts` resume khusus `AOD_NOTIFY`, Goodix cmd `0x30` + FOD key `195`, dan `/dev/goodix_fp` + HBM uevent `TRAN_FULL_HBM_EVENT=FULL_HBM_SET` — **rekam video & FOD normal terverifikasi lulus**.
- **FOD saat AOD, screen-off FOD, DT2W & flashlight (`v11`–`v12`)**: hapus `0x39`/`0x38` idle mode + tabel alpha stock RM69220 (**FOD di AOD terverifikasi lulus**), pertahankan `vddi-gpios` HIGH saat panel power-off (`0d456ba`), `simple_read_from_buffer()` + isolasi `0xcc` dari `"al2"` (`e4ed999`), V4L2 `flash_sgm37864` + nonaktifkan PT throttling di `flashlight-core.h` sesuai stock (`ebca3e1`).
- **Fast charging HVDCP20, boot race `mtk_iommu`, earpiece `RCV Mux`, penyelarasan `mtu3`, & GKI KMI 6 (`v13`–`v19-kmi6`)**: 6 entri `alg_name_array` + guard (`0af45b1`), inisialisasi `hw_list` sebelum `iommu_device_register` (`5f569d0`), rute `RCV Select=Playback_R_DAC` (`22efa7e`, `aca5276`), penyelarasan `mtu3.ko` dengan stock (`32a8db7`), serta migrasi bersih ke GKI AOSP `android16-6.12-2026-09_r16` (KMI 6) + safeguard `verify-kmi-abi.py` (`96b299e`, `20a8f5d`, `fa18f7f`).
- Fitur dari 25 modul stock tanpa source (`transsion_tranlog`, `thd`, dll.) tidak disertakan. Detail lengkap ada di [HANDOFF-HISTORY.md](HANDOFF-HISTORY.md) dan [`PRETEST.md`](PRETEST.md) §45–§68.
