# BOOTTEST — uji boot utuh X6871

Tujuan: memvalidasi **seluruh boot**, bukan hanya satu modul. Empat modul
fitur (`tran_fp`, `tnek`, `tkv`, `tran_extcon_usb`) hanya bagian kecil dari
217 modul yang menggantikan modul stock.

## 0. Tiga kenyataan yang menentukan prosedur

1. **Modul ada di dalam `vendor_boot`.** Di image stock, 237 `.ko` berada di
   `vendor_ramdisk00/lib/modules/` (flat, tanpa direktori versi), bersama
   `modules.dep`, `modules.alias`, `modules.softdep`, `modules.load`,
   `modules.load.recovery`. Tidak ada partisi modul terpisah.
2. **Vermagic mengikat kernel ke modul.** Stock:
   `6.12.38-android16-5-gcc51d883045d-4k`. Build kita:
   `6.12.38-android16-5-g2c4fd33ae6d8-4k`. Modul kita **tidak akan load**
   di kernel stock, dan sebaliknya. Kalau hanya `vendor_boot` yang di-flash,
   modul akan gagal dengan `version magic ... should be ...`.
3. **Build kita tidak menghasilkan dtb/dtbo.** Target yang dipakai hanya
   membangun `Image` + modul, jadi `dtb` di dalam `vendor_boot` dan
   `dtbo.img` tetap milik stock. Ini risiko yang harus diamati di dmesg
   (lihat §5).

## 1. Artefak

| Artefak | Sumber | Catatan |
|---|---|---|
| `vendor_boot-new.img` | `tools/pack-vendor-boot.sh` | modul kita, dtb/bootconfig/recovery stock |
| kernel `Image` | `out_bazel/.../mgk_64_k612_kernel_aarch64.user/Image` | harus masuk ke `boot.img` |
| `dtbo.img` | stock, tidak diubah | build tidak menghasilkan dtbo |
| modul | `.../mgk_64_k612_customer_modules_install.user/staging/lib/modules/6.12.38-android16-5-g2c4fd33ae6d8-4k` | 217 pengganti + sisanya |

## 2. Membuat `vendor_boot-new.img`

```bash
cd /serverhive1/ramabondanp/w1vo36-kernel-manifest

STAGING=/serverhive1/ramabondanp/w1vo/out_bazel/ad3c7b30a704e8551ed600a0d11ef0f0/execroot/_main/bazel-out/k8-fastbuild/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/staging/lib/modules/6.12.38-android16-5-g2c4fd33ae6d8-4k

./tools/pack-vendor-boot.sh \
  --stock   /serverhive1/ramabondanp/tmp/x6871/vendor_boot.img \
  --staging "$STAGING" \
  --out     /serverhive1/ramabondanp/tmp/x6871/vendor_boot-new.img
```

Yang dilakukan skrip, berurutan:

1. `unpack_bootimg` image stock; parameter header dibaca dari image itu
   sendiri (bukan hardcode).
2. `vendor_ramdisk00` didekompresi (lz4 legacy) lalu di-`cpio` keluar.
3. `lib/modules/*.ko` diganti dengan modul build kita. Hanya modul yang
   memang dikirim stock yang dimasukkan (217 dari ~795 `.ko` di staging),
   basename ganda diselesaikan dengan memilih salinan `extra/` = versi
   device. Tiap `.ko` di-`strip --strip-debug` supaya ukurannya setara stock
   (staging menyimpan debug info; tanpa strip ramdisk jadi ~94 MB dan tidak
   muat di partisi 64 MB).
4. `modules.dep`, `modules.alias`, `modules.softdep` diregenerasi dari
   `modinfo` tiap `.ko`, formatnya disamakan dengan stock
   (`/lib/modules/x.ko: ...`).
5. `modules.load` dan `modules.load.recovery` diambil dari stock lalu
   difilter: entri yang tidak ada di build kita dibuang.
6. Ramdisk di-`cpio` (`newc`, owner root) dan dikompres `lz4 -l -12`.
7. `mkbootimg --header_version 4 --base 0` dengan alamat load, dtb,
   bootconfig, dan fragmen recovery **persis** seperti stock.
8. Verifikasi otomatis: `dtb`, `bootconfig`, dan `vendor_ramdisk01`
   (recovery) harus identik (md5); jumlah modul dan vermagic dicetak;
   image di-pad ke ukuran partisi stock.

Uji round-trip (tanpa mengganti modul) sudah dijalankan dan hasilnya
**identik byte-per-byte** dengan stock di level isi ramdisk dan header —
jadi yang berubah hanya isi `lib/modules`.

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
| Display/panel | `dmesg \| grep -iE 'panel\|dsi\|rm69220'` | panel `rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871` ter-probe, layar menyala |
| Touch | `dmesg \| grep -i goodix`; `/dev/input/event*` | tidak ada gagal probe |
| Charger/USB | `dmesg \| grep -iE 'tc_charger\|tc_tcpc\|extcon'`; `SWITCH_NAME`/`SWITCH_STATE` saat colok | role switch berubah, tidak ada crash |
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
- **`modules.load` menyusut**: dari 179 entri stock, 17 entri menunjuk modul
  yang tidak ada di build dan dibuang oleh skrip.
- **`mtk-socinfo.ko` ter-build dua kali**; `depmod` memilih salinan GKI.
  Bukan penghalang boot, tapi sebaiknya salah satu dikecualikan saat
  packaging.
- **Staging berisi ~795 `.ko`, perangkat hanya butuh 217.** Sisanya modul
  platform lain (mt6858/mt6991/mt6993, varian panel, dsb). Skrip repack
  memfilter ke daftar modul yang benar-benar dikirim stock; tanpa filter itu
  ramdisk membengkak jadi 430 MB dan tidak muat di partisi 64 MB.
  Pakai `--all-modules` hanya kalau memang ingin membawa semuanya.
- **dtb/dtbo stock** dipakai apa adanya. Kalau ada driver yang mengeluh
  properti DT tidak dikenal, itu konsekuensi langsung dari poin ini.
- **API hardware baru** di tiga modul: `clk-common`, `tran_ldo`,
  `tran_usb_ctrl`. Pantau probe-nya.

## 6. Kalau boot gagal

1. Cek apakah kernel-nya benar: `uname -r` harus
   `6.12.38-android16-5-g2c4fd33ae6d8-4k`.
2. `dmesg | grep -i 'version magic'` → kernel dan modul beda build.
3. Tidak ada `/dev/block/by-name` → UFS tidak probe; cek
   `dmesg | grep -i ufs` dan `phy-mtk-ufs`.
4. Layar mati tapi sistem hidup → panel/dtb; cek `dmesg | grep -i dsi`.
5. Ambil `pstore`/`ramoops` (`/sys/fs/pstore`) atau UART untuk panic.
6. Rollback dengan image stock sebelum mencoba varian berikutnya.

## 7. Artefak yang sudah dibuat

```
/serverhive1/ramabondanp/tmp/x6871/vendor_boot-new.img
  ukuran : 67108864 (sama dengan partisi stock)
  md5    : 9c83483806f8cbbe62b2cbfa9236e34a
  modul  : 217 (set pengganti stock, sudah di-strip)
  dtb / bootconfig / vendor_ramdisk01 : identik dengan stock
  modules.load           : 163 entri, 0 menggantung
  modules.load.recovery  : 213 entri, 0 menggantung
  modules.dep            : 0 referensi menggantung
  vermagic semua modul   : 6.12.38-android16-5-g2c4fd33ae6d8-4k
```

Uji round-trip (repack tanpa mengganti modul) menghasilkan isi ramdisk dan
header yang **identik** dengan stock, jadi yang berubah hanya `lib/modules`.
