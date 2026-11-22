# BOOTTEST — Prosedur Uji Boot & Checklist X6871

> **Status 2026-11-22:** Seluruh subsistem modul 100% lulus/clear (earpiece
> lulus v16; `mtu3.ko` sejajar stock di v18 / `32a8db7`). Bug USB replug
> terkonfirmasi berasal dari kernel GKI custom (`boot.img`) karena tetap
> terjadi identik saat seluruh DLKM & modul stock di-flash (`PRETEST.md` §67).
> Prosedur repack ada di §2 dan §11; §9–§10 adalah arsip historis.

Tujuan: memvalidasi **seluruh boot** (recovery + Android system), bukan hanya satu modul.

## 0. Tiga kenyataan yang menentukan prosedur

1. **Pembagian partisi modul di X6871:**
   - **`vendor_boot`** (`vendor_ramdisk00/lib/modules/`, flat tanpa subdirektori versi): memuat **222 modul** first-stage/recovery bersama `modules.dep`, `modules.alias`, `modules.softdep`, `modules.load` (165 entri), dan `modules.load.recovery` (216 entri).
   - **`vendor_dlkm` + `odm_dlkm`** (partisi logis di `super`, format EROFS + AVB hashtree footer): memuat **269 modul** Android system (**212** `vendor_dlkm` + **57** `odm_dlkm`, `modules.load` 194/57).
2. **Kernel dan modul terikat oleh simbol + CRC, bukan release string.**
   Build ini memakai `CONFIG_MODVERSIONS`, dan `same_magic()` di
   `kernel/module/version.c` melewati token pertama vermagic saat modul punya
   CRC (`/* First part is kernel version, which we ignore if module has crcs */`).
   Yang dibandingkan hanya ` SMP preempt mod_unload modversions aarch64`.
   Konsekuensinya: release string boleh berbeda (`gcc51d883045d` vs
   `g2c4fd33ae6d8`) selama simbol dan CRC-nya sama.

   Sudah diverifikasi untuk pasangan ini:

   | Uji | Hasil |
   |---|---|
   | simbol kernel yang dipakai kedua build | 2174 |
   | CRC identik | **2174 / 2174** |
   | modul build kita yang cocok CRC-nya dengan kernel stock | **795 / 795** (snapshot 2026-11-19) |

   Artinya modul kita bisa di-load di kernel stock, dan sebaliknya. Tetap
   disarankan memakai kernel + modul dari satu build supaya perilaku kode
   (bukan hanya ABI) konsisten.
3. **Build kita tidak menghasilkan dtb/dtbo.** Target yang dipakai hanya
   membangun `Image` + modul, jadi `dtb` di dalam `vendor_boot` dan
   `dtbo.img` tetap milik stock. Ini risiko yang harus diamati di dmesg
   (lihat §5).

## 1. Artefak Uji Terbaru (`mtu3-stock-20261122`)

| Artefak | Sumber | Catatan |
|---|---|---|
| `x6871-twrp-vendor_boot-v18.img` | `tools/repack-vendor-boot-latest.sh` | **222** modul source (`md5 73b94a9f88ed39a852e8a1343978d37e`), `mtu3.ko` sejajar stock (`32a8db7`); dtb/bootconfig/recovery TWRP tetap |
| `vendor_dlkm.img` | EROFS + AVB (`fastbootd`) | **212** modul source (`md5 72daa1f10eba75d9cd0e3359a27ff76f`), identik dengan v16 |
| `odm_dlkm.img` | EROFS + AVB (`fastbootd`) | **57** modul source (`md5 99b2194fa63cab8c751f71b8fbd4eb5e`), identik dengan v16 |
| kernel `Image` | `out_bazel/.../mgk_64_k612_kernel_aarch64.user/Image` | opsional, hanya jika `boot.img` ikut diganti |
| `dtbo.img` | stock, tidak diubah | build tidak menghasilkan dtbo |
| staging modul | `.../mgk_64_k612_customer_modules_install.user/staging/lib/modules/6.12.38-android16-5-g2c4fd33ae6d8-4k` | 806 file / 805 nama unik |

## 2. Membuat image vendor_boot

```bash
cd /serverhive1/ramabondanp/w1vo36-kernel-manifest
./tools/repack-vendor-boot-latest.sh \
  --out /serverhive1/ramabondanp/tmp/x6871/twrp-vendor_boot-$(date -u +%Y%m%d-%H%M%S).img
```

Skrip menjalankan build Bazel resmi, mengambil staging hasil build itu,
men-stage 222 modul dari `tools/recovery-modules.txt`, menghapus debug
info, meregenerasi `modules.dep`/`alias`/`softdep`, pack dengan
cfig/Android_boot_image_editor, lalu membongkar hasilnya dan **gagal**
kalau ada `.ko` yang beda dari staging. Modul tidak pernah disalin dari
image lama.

`tools/pack-vendor-boot.sh` adalah tool legacy dan **jangan dipakai untuk
X6871**: ia memfilter berdasarkan nama stock sehingga modul build-only
(`adaptive-ts`, `gt9916_common`, `mtk-mmc`, `tran_richtap_haptic_hv`)
bisa hilang. Detail repack: `HANDOFF.md` §Repack dan `PRETEST.md` §44.

## 3. Flash dan rollback

```bash
# 1. Dari bootloader fastboot (bootloader unlocked; image tidak ditandatangani)
fastboot flash vendor_boot x6871-twrp-vendor_boot-v18.img

# 2. Lewati blok ini jika DLKM v16 sudah terpasang (isinya identik).
#    Jika belum, masuk fastbootd untuk partisi logis:
fastboot reboot fastboot
fastboot getvar is-userspace  # harus yes
fastboot flash vendor_dlkm vendor_dlkm.img
fastboot flash odm_dlkm odm_dlkm.img

# 3. Boot Android
fastboot reboot
```

Rollback (wajib disiapkan sebelum tes): bila awalnya memakai v16,
flash kembali `x6871-twrp-vendor_boot-v16.img` saja. Untuk rollback penuh ke stock:

```bash
fastboot flash vendor_boot /serverhive1/ramabondanp/tmp/x6871/vendor_boot.img
# dan flash balik stock vendor_dlkm.img / odm_dlkm.img bila perlu
```

Kalau kernel juga diganti, simpan `boot.img` stock dan flash balik dengan
cara yang sama.

## 4. Checklist boot per subsistem

Ambil `dmesg` penuh setelah boot, lalu periksa:

| Subsistem | Cek | Kriteria lulus |
|---|---|---|
| Loader modul | `dmesg \| grep -E 'Unknown symbol\|disagrees about version\|version magic'` | kosong |
| Storage/UFS | `dmesg \| grep -iE 'ufs\|scsi'`; `ls /dev/block/by-name`; mount `/data` | UFS probe, semua partisi ada, `/data` ter-mount |
| Display/panel & AOD | matikan lalu nyalakan layar + uji AOD; `dmesg \| grep -iE 'lcm_prepare\|panel_doze\|underrun'` | resume normal, mode 144/120/60/40 Hz & AOD bersih, 0 underrun |
| Touch & DT2W | `dmesg \| grep -iE 'goodix\|tran_touch'` | touch normal (`goodix_ts_report_finger`); masuk AOD tidak memicu `drm notify tp resume start`; double-tap memicu `got valid gesture type 0xcc` |
| Charger/USB | cabut-colok kabel; `dmesg \| grep -iE 'tran_extcon\|ssusb_set_mode\|online=.*type=\|pullup\|gadget RESET'` | cabut → role NONE, colok → `online=1, type=1` (SDP), `pullup D+`, `gadget RESET`; ADB kabel/MTP tersambung kembali |
| Audio | `dmesg \| grep -iE 'mt6895-afe\|fs15xx\|snd'`; uji speaker | card terdaftar, PA aktif, tidak ada timeout IPI |
| Kamera & Video | foto + rekam video 1080p lalu simpan; `dmesg \| grep -iE 'check_codec_id\|venc\|LARB7'` | `check_codec_id ipi id 1 is correct`, `slbc_request 1`, `mtk_vcodec_enc_clock_on`, **0** fault `LARB7_PORT24`/`mva=0x0` |
| Connectivity | `dmesg \| grep -iE 'wlan\|wmt\|bt'`; `ip link` | `wlan0` ada dan tersambung |
| Sensor/thermal | `dmesg \| grep -iE 'thermal\|lvts\|sensorhub'` | tidak ada trip panic |
| RTC/PMIC | `dmesg \| grep -iE 'mt6685\|rtc\|spmi'` | RTC jalan, tidak ada error SPMI |
| Key/PMIC keys | `getevent` | volume/power berfungsi |
| Fingerprint (FOD) | `ls -l /dev/goodix_fp`; `cat /sys/kernel/tran_fp/vendor_name`; `dmesg \| grep -iE 'tran_fp\|fp key finger\|notify fingerprint'` | `/dev/goodix_fp` ada, `vendor_name=goodix_opt_tee`, sentuh ikon FOD memicu `fp key finger` (key `195`) + HBM uevent `TRAN_FULL_HBM_EVENT=FULL_HBM_SET` |
| tkv | `/proc/tkv` | ada, atau log `refusing to map` (aman) |
| tnek | `/dev/tnek` | ada |
| LED | `/sys/class/leds/aw22xxx*` | node ada |
| Reboot/suspend | `reboot`; `echo mem > /sys/power/state` | tidak hang |

### Uji fokus USB replug v17

1. Boot dengan USB debugging aktif. Verifikasi `adb -d shell true` dari PC;
   `-d` memastikan yang diuji adalah transport USB, bukan Wi-Fi.
2. Cabut hingga port berubah ke NONE, lalu colok kembali. Ulangi minimal
   tiga kali tanpa `stop/start adbd` atau mengubah mode USB. Tiap siklus harus
   kembali ke DEVICE, mengeluarkan `pullup D+` dan `gadget RESET`, lalu
   `adb -d shell true` berhasil. Uji File Transfer (MTP), OTG, dan charger
   dinding terpisah; mode charge-only jangan ikut mengekspor fungsi data.
3. Jika port DEVICE tetapi PC tidak bisa enumerasi, ambil `dmesg`/`logcat -b all`
   dari terminal lokal atau ADB nirkabel. Rekam juga status ini sebelum dan
   setelah kegagalan (akses root mungkin diperlukan untuk configfs):

   ```sh
   getprop sys.usb.config
   getprop sys.usb.state
   getprop sys.usb.ffs.ready
   cat /config/usb_gadget/g1/UDC
   cat /sys/class/udc/11201000.usb0/state
   ```

   `new device session without pullup (gadget bound=0)` menunjukkan tidak
   ada gadget aktif saat replug. Lihat `PRETEST.md` §65 untuk pembeda
   dari kegagalan pullup dengan gadget masih terikat.

## 5. Delta yang **wajar** terlihat (bukan bug)

- **20 modul stock tidak ada**: 2 panel + alias panel, 3 MMC/SD, 7 fork
  storage/UFS, 4 modul yang butuh `transsion_tranlog`, dan 3 fitur
  independen (`tkv_recovery`, `tran_rhi`, `tran_expand_key`).
- **Storage memakai stack GKI/MTK**, bukan fork Transsion. Karena itu
  `ufs-mediatek-mod.ko` kita hanya bergantung pada `ufs-mediatek-dbg`,
  `irq-dbg`, `blocktag`, `rpmb` — bukan `tran-ufshcd-*`.
- **`modules.load`/`modules.load.recovery`**: 165/216 entri. Entri stock
  yang modulnya tidak ada di build dibuang; modul build-only ditambahkan.
- **`mtk-socinfo.ko` ter-build dua kali** (`kernel/` dan `extra/`).
  `tools/stage-recovery-modules.py` sengaja memilih salinan `kernel/`,
  sama dengan image yang sudah terbukti boot.
- **Staging berisi 806 file / 805 nama unik, perangkat hanya butuh 222.**
  Sisanya modul platform lain (mt6858/mt6991/mt6993, varian panel, dsb).
  Komposisi vendor_boot dikunci oleh `tools/recovery-modules.txt`, bukan
  filter nama stock, supaya modul build-only tidak hilang.
- **dtb/dtbo stock** dipakai apa adanya. Kalau ada driver yang mengeluh
  properti DT tidak dikenal, itu konsekuensi langsung dari poin ini.
- **API hardware baru** di tiga modul: `clk-common`, `tran_ldo`,
  `tran_usb_ctrl`. Pantau probe-nya.

## 6. Kalau boot gagal

1. `dmesg | grep -iE 'Unknown symbol|disagrees about version of symbol|no symbol version'`
   → simbol hilang atau CRC beda. Ini pemeriksaan yang benar; pesan
   `version magic ... should be` hanya muncul kalau bagian
   ` SMP preempt mod_unload modversions aarch64` yang berbeda, bukan release.
2. Cek kernel yang jalan: `uname -r`. Release string boleh berbeda dari build
   modul (lihat §0.2), tapi kalau bukan kernel kita sama sekali, driver
   vendor belum tentu ada.
3. Tidak ada `/dev/block/by-name` → UFS tidak probe; cek
   `dmesg | grep -i ufs` dan `phy-mtk-ufs`.
4. Layar mati tapi sistem hidup → panel/dtb; cek `dmesg | grep -i dsi`.
5. Ambil `pstore`/`ramoops` (`/sys/fs/pstore`) atau UART untuk panic.
6. Rollback dengan image stock sebelum mencoba varian berikutnya.

## 7. Artefak terbaru (`venc-fod-dt2w-20261122`)

```text
/serverhive1/ramabondanp/tmp/x6871/twrp-vendor_boot-allsrc-display-usb-v10.img
  ukuran : 67108864 (sama dengan partisi stock)
  md5    : 3409f68913613b38d43052458435558b
  modul  : 222, semuanya hasil build sendiri (kernel 17a6b66d7927)
  dtb / bootconfig / vendor_ramdisk01 : identik dengan base TWRP
  modules.load           : 165 entri
  modules.load.recovery  : 216 entri
  modules.dep            : hasil depmod, 0 referensi menggantung
  vermagic semua modul   : 6.12.38-android16-5-g2c4fd33ae6d8-4k
```

Catatan historis: image awal 217 modul (`vendor_boot-new.img`), 240 modul
campuran stock (`cfig` §9–§10), serta `v1`–`v9` sudah digantikan oleh `v10`.

## 8. Kalau modul gagal load: cek `modules.dep`

Gejala di `pstore`/`dmesg`:

```
init: Loading module /lib/modules/usb_dp_selector.ko with args ''
usb_dp_selector: Unknown symbol mtk_dp_SWInterruptSet (err -2)
usb_dp_selector: Unknown symbol mtk_dp_aux_swap_enable (err -2)
usb_dp_selector: Unknown symbol mtk_dp_set_pin_assign (err -2)
init: Failed to insmod '/lib/modules/usb_dp_selector.ko' with args '': No such file or directory
init: Loaded 54 modules from /lib/modules
init: Failed to load kernel modules
init: InitFatalReboot: signal 6
reboot: Restarting system with command 'bootloader'
```

Penyebabnya bukan modulnya, tapi **`modules.dep`**. `usb_dp_selector`
mengimpor `mtk_dp_*` dari `mediatek_drm_v1.ko` (nama modulnya
`mediatek-drm`), dan init (libmodprobe) memuat dependensi lebih dulu
berdasarkan file itu. Kalau dependensi hilang, `mediatek_drm_v1` belum
ter-load saat `usb_dp_selector` di-insmod → `Unknown symbol` → init abort →
reboot ke bootloader.

Versi awal `tools/pack-vendor-boot.sh` membuat `modules.dep` dari
`modinfo -F depends`, dan field itu berisi **nama modul**, bukan nama file
(`mediatek-drm` vs `mediatek_drm_v1.ko`), sehingga dependensi tersebut
hilang tanpa peringatan. Sekarang skrip memakai `depmod` (berbasis simbol +
CRC, sama seperti stock): 318 → 783 dependensi, dan
`usb_dp_selector.ko: /lib/modules/mediatek_drm_v1.ko ...` kembali ada.

Verifikasi cepat sebelum flash:

```bash
grep '^/lib/modules/usb_dp_selector.ko:' lib/modules/modules.dep
# harus memuat /lib/modules/mediatek_drm_v1.ko
```

`Loaded N modules` yang kecil (mis. 54 dari 163 di `modules.load`) selalu
berarti init berhenti di modul pertama yang gagal — bukan berarti ramdisk
hanya berisi N modul.

Catatan penting dari uji boot pertama: **kernel yang berbeda build bukan
penghalang.** Kernel uji (`6.12.117-...-Rama982`) berhasil boot dengan
seluruh set modul stock, jadi pesan `disagrees about version of symbol ...
(ignoring)` dan `Kernel module BTF mismatch detected` hanya informatif —
jangan dikejar. Yang menentukan hanya apakah simbolnya ada. Karena itu
satu-satunya penyebab kegagalan di log pertama adalah `modules.dep` yang
kehilangan dependensi, bukan beda versi kernel.

## 9. Repack dengan cfig/Android_boot_image_editor (historis)

Selain `tools/pack-vendor-boot.sh`, image bisa direpack dengan
[`cfig/Android_boot_image_editor`](https://github.com/cfig/Android_boot_image_editor)
(commit `f692aff`) — dipakai untuk uji boot ketiga karena lebih ketat soal
format ramdisk.

```bash
cd /serverhive1/ramabondanp/tmp
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

## 10. Ramdisk zstd (TWRP) — catatan tool (historis)

Image TWRP untuk X6871 memakai ramdisk **zstd** (`28 b5 2f fd`), bukan lz4.
`cfig/Android_boot_image_editor` (commit `f692aff`) belum mengenalnya:
`./gradlew unpack` berhenti dengan `ramdisk is in unknown format`.

Patch: `tools/patches/abie-zstd-ramdisk.patch` (dibuat terhadap `f692aff`)

```bash
cd Android_boot_image_editor && git apply /path/tools/patches/abie-zstd-ramdisk.patch
```

Isinya:

- `helper/.../ZipHelper.kt` — `getZstdProg()`, `hasZstd`, `isZstd()` (deteksi
  lewat magic, bukan binary), `zstdcat()`, `zstd()` (kompres `-15 -T0`)
- `bbootimg/.../Common.kt` — cabang `isZstd` di `dumpRamdisk` (suffix `.zst`)
  dan cabang `.zst`/`.zstd` di kedua `packRootfs`
- `bbootimg/.../cpio/AndroidCpio.kt` — `fis.skip(bytesRead - 128)` melempar
  `IOException: Invalid argument` untuk ramdisk kosong (fragment TWRP
  `emptyrecovery` 60 byte); sekarang di-skip hanya kalau nilainya positif

### Repack TWRP dengan modul kita

```bash
cd vbwork-twrp           # clone editor + patch, taruh vendor_boot.img
./gradlew unpack
# root.1 = fragment PLATFORM (berisi lib/modules), root.2 = emptyrecovery
M=build/unzip_boot/root.1/lib/modules
rm -f $M/*.ko
cp <set-modul>/*.ko $M/ && cp <set-modul>/modules.{dep,alias,softdep,load,load.recovery} $M/
./gradlew pack
```

Untuk X6871 hasilnya: 240 modul, `modules.load.recovery` 236 entri,
ramdisk tetap zstd, `dtb`/`bootconfig` identik TWRP asli, fragment
`emptyrecovery` isinya sama (hanya ukuran terkompresi 60 → 61 byte), image
dipad ke 67.108.864 byte.

Catatan komposisi: set TWRP = 237 modul stock + `adaptive-ts`,
`gt9916_common`, `tran_richtap_haptic_hv`. Modul yang kita build diganti versi
kita (termasuk panel `panel-rm69220-vdo-x6871.ko` menggantikan
`rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.ko`), sisanya tetap versi
TWRP/stock — `adaptive-ts` butuh `cloudengine_*` dari `transsion_tranlog`
yang tidak kita build, jadi modul itu harus tetap ada agar sentuhan hidup.

## 11. DLKM 100% Source (2026-11-20 s.d. 2026-11-22)

`vendor_dlkm` (**212** modul, `modules.load` 194) dan `odm_dlkm` (**57** modul,
`modules.load` 57) dibangun 100% dari source menggunakan EROFS dengan opsi
identik stock + AVB hashtree footer yang dipertahankan. Zip TWRP memetakan
logical partition (`lptools map`) lalu menulis image dengan `dd` tanpa
menghapus/membuat ulang partisi.

Artefak DLKM terbaru (`sofod-dt2w-flash-20261122`, kernel `ebca3e1`, raw `.img` untuk `fastbootd`):

```text
x6871-twrp-vendor_boot-v12.img  md5 f345308a330b4ceb5daf586bcd059607  67.108.864 B
vendor_dlkm.img                 md5 4cb91f7c318d0960289e86fe764448e5  24.551.424 B
odm_dlkm.img                    md5 411cc6106caedd526767e9f5cfc5a70d   4.206.592 B
```

Ringkasan perbaikan DLKM + `vendor_boot` yang sudah masuk hingga `v12`:

- **Boot system dasar (`dlkm-20261120`..`gpu3`)**: `SCP_IPI_COUNT` 56→59, GPU Mali r54p1-11eac0 donor OPPO + fix padding `gpufreq_shared_status` (`power_count` 0x24..`active_count` 0x34, `temperature` 0x38, `shader_present` 0xe0).
- **Battery OC & layar (`v2`–`v3`)**: `rfg-mtk-tran-conf-diff`, timing/VFP 144/120/60/40 Hz, C3D dual-pipe SRAM, dan `PQ_VIRTUAL_SET_PROPERTY` 12 B — **layar terverifikasi normal penuh**.
- **Audio, AOD & kamera (`v4`–`v6`)**: FS1599 PA + `tran_audio_control`, AOD RM69220, 4 sensor kamera X6871 (`s5khm6sx`/`gc32e1`/`gc02m3`/`gc02m3macro`) + `camera_eeprom_v4l2`, `mtk-cam-isp` inline `sink_fmt`, dan flashlight `ocp81375_v4l2`.
- **VENC, DT2W & FOD (`v7`–`v10`)**: QP ABI 6-field, `VENC_H264 = 1`, `mtk_codec_capability` 24 B + ADAB 4x `U32`, `slbc_request`, enum notifier AOD/HBM DRM, `adaptive-ts` resume khusus `AOD_NOTIFY`, Goodix cmd `0x30` + FOD key `195`, dan `/dev/goodix_fp` + HBM uevent `TRAN_FULL_HBM_EVENT=FULL_HBM_SET` — **rekam video & FOD normal terverifikasi lulus**.
- **FOD saat AOD, screen-off FOD, DT2W & flashlight (`v11`–`v12`)**: hapus `0x39`/`0x38` idle mode + tabel alpha stock RM69220 (**FOD di AOD terverifikasi lulus**), pertahankan `vddi-gpios` HIGH saat panel power-off (`0d456ba`), `simple_read_from_buffer()` + isolasi `0xcc` dari `"al2"` (`e4ed999`), V4L2 `flash_sgm37864` + nonaktifkan PT throttling di `flashlight-core.h` sesuai stock (`ebca3e1`).
- Fitur dari 25 modul stock tanpa source (`transsion_tranlog`, `thd`, dll.) tidak disertakan. Detail lengkap ada di `HANDOFF.md` dan `PRETEST.md` §45–§61.
