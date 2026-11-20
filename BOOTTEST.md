# BOOTTEST — uji boot utuh X6871

> **Status 2026-11-20:** TWRP final sudah memakai 222 modul 100% source
> (`twrp-vendor_boot-allsrc-display-usb.img`, md5
> `0ecdaa1edb3d405954331539b24c911b`); layar dan USB replug sudah lolos.
> Dokumen ini tetap dipakai untuk checklist system boot. Prosedur repack
> yang berlaku ada di §2; angka 217/240 di §9-§10 (dan catatan historis
> di §7) adalah artefak lama.

Tujuan: memvalidasi **seluruh boot**, bukan hanya satu modul. Empat modul
fitur (`tran_fp`, `tnek`, `tkv`, `tran_extcon_usb`) hanya bagian kecil dari
222 modul yang menggantikan modul stock.

## 0. Tiga kenyataan yang menentukan prosedur

1. **Modul ada di dalam `vendor_boot`.** Di image stock, 237 `.ko` berada di
   `vendor_ramdisk00/lib/modules/` (flat, tanpa direktori versi), bersama
   `modules.dep`, `modules.alias`, `modules.softdep`, `modules.load`,
   `modules.load.recovery`. Tidak ada partisi modul terpisah.
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

## 1. Artefak

| Artefak | Sumber | Catatan |
|---|---|---|
| `twrp-vendor_boot-allsrc-display-usb.img` | `tools/repack-vendor-boot-latest.sh` | **final**: 222 modul source, dtb/bootconfig/recovery TWRP tetap |
| kernel `Image` | `out_bazel/.../mgk_64_k612_kernel_aarch64.user/Image` | hanya jika boot.img ikut diganti |
| `dtbo.img` | stock, tidak diubah | build tidak menghasilkan dtbo |
| modul | `.../mgk_64_k612_customer_modules_install.user/staging/lib/modules/6.12.38-android16-5-g2c4fd33ae6d8-4k` | 806 file / 805 nama unik; 222 dipakai di vendor_boot |

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
# bootloader harus unlocked; image tidak ditandatangani (AVB akan menolak
# kalau verifikasi aktif)
fastboot flash vendor_boot vendor_boot-new.img
fastboot reboot
```

Rollback (wajib disiapkan sebelum tes):

```bash
fastboot flash vendor_boot /serverhive1/ramabondanp/tmp/x6871/vendor_boot.img
```

Kalau kernel juga diganti, simpan `boot.img` stock dan flash balik dengan
cara yang sama.

## 4. Checklist boot per subsistem

Ambil `dmesg` penuh setelah boot, lalu periksa:

| Subsistem | Cek | Kriteria lulus |
|---|---|---|
| Loader modul | `dmesg \| grep -E 'Unknown symbol\|disagrees about version\|version magic'` | kosong |
| Storage/UFS | `dmesg \| grep -iE 'ufs\|scsi'`; `ls /dev/block/by-name`; mount `/data` | UFS probe, semua partisi ada, `/data` ter-mount |
| Display/panel | matikan lalu nyalakan layar; `dmesg \| grep -iE 'lcm_prepare\|panel_ext_lcm_power_set\|underrun'` | resume memanggil `panel_ext_lcm_power_set(1)` + `lcm_prepare` + `lcm_panel_init`, 0 underrun |
| Touch | `dmesg \| grep -i goodix`; `/dev/input/event*` | tidak ada gagal probe |
| Charger/USB | cabut-colok kabel; `dmesg \| grep -iE 'tran_extcon\|ssusb_set_mode\|online=.*type='` | cabut -> role NONE, colok -> `online=1, type=1` (SDP), `pullup D+`, `gadget RESET` |
| Audio | `dmesg \| grep -iE 'mt6895-afe\|snd'`; `tinymix`/`aplay` | card terdaftar, tidak ada timeout IPI |
| Kamera | `dmesg \| grep -iE 'mtk-cam\|imgsensor'` | ISP probe, tidak ada error regulator |
| Connectivity | `dmesg \| grep -iE 'wlan\|wmt\|bt'`; `ip link` | wlan0 ada |
| Sensor/thermal | `dmesg \| grep -iE 'thermal\|lvts\|sensorhub'` | tidak ada trip panic |
| RTC/PMIC | `dmesg \| grep -iE 'mt6685\|rtc\|spmi'` | RTC jalan, tidak ada error SPMI |
| Key/PMIC keys | `getevent` | volume/power berfungsi |
| Fingerprint | `dmesg \| grep -i tran_fp`; `/sys/kernel/tran_fp/vendor_name` | `goodix chip id 0x...`, `vendor_name` terisi |
| tkv | `/proc/tkv` | ada, atau log `refusing to map` (aman) |
| tnek | `/dev/tnek` | ada |
| LED | `/sys/class/leds/aw22xxx*` | node ada |
| Reboot/suspend | `reboot`; `echo mem > /sys/power/state` | tidak hang |

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

## 7. Artefak final

```text
/serverhive1/ramabondanp/tmp/x6871/twrp-vendor_boot-allsrc-display-usb.img
  ukuran : 67108864 (sama dengan partisi stock)
  md5    : 0ecdaa1edb3d405954331539b24c911b
  modul  : 222, semuanya hasil build sendiri
  dtb / bootconfig / vendor_ramdisk01 : identik dengan base TWRP
  modules.load           : 165 entri
  modules.load.recovery  : 216 entri
  modules.dep            : hasil depmod, 0 referensi menggantung
  vermagic semua modul   : 6.12.38-android16-5-g2c4fd33ae6d8-4k
```

Catatan historis: image 217 modul (`vendor_boot-new.img`) dan 240 modul
campuran stock (`cfig` §9-§10) sudah tidak dipakai. Yang berlaku adalah
222 modul source di atas.

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

## 11. DLKM source (2026-11-20)

`vendor_dlkm` dan `odm_dlkm` sudah di-repack 100% source:

```text
vendor_dlkm.img  md5 c329bbb8a465e32dc5bfd4cdcaede45f  24.551.424 B
odm_dlkm.img     md5 0ffbb42985d445f7c12808df3b50960e   4.206.592 B
twrp-dlkm-source-20261120.zip  (release dlkm-20261120)
```

- 212 modul vendor + 57 modul odm, `modules.load` 194/57.
- EROFS memakai opsi stock persis, AVB hashtree footer dipertahankan.
- Zip TWRP memetakan logical partition (`lptools map`) lalu `dd`; tidak
  delete/create partition.
- Setelah flash: reboot, ambil dmesg/pstore, cek
  `dmesg | grep -iE 'Unknown symbol|module|verity'` dan pastikan sistem
  mencapai launcher. Kalau gagal, rollback dengan stock
  `vendor_dlkm`/`odm_dlkm`.
- Fix SCP: `vendor_dlkm.img` md5 `5b7472dea26b60dd8eef5370a2cd13a9`,
  zip `twrp-dlkm-scpfix-20261120.zip` (`SCP_IPI_COUNT` 56 -> 59).
- Fitur dari 25 modul stock tanpa source (`transsion_tranlog`,
  `thd`, dll) tidak akan ada.
