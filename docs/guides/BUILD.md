# Panduan Build, Konfigurasi, dan Repack X6871

Panduan operasional aktif untuk membangun modul kernel X6871 (baseline stabil **6.12** dan pratinjau **6.18**), mengatur `X6871.config`, merepack image partisi kernel, serta memverifikasi KMI/ABI.

- Untuk flash dan uji boot di perangkat, lihat [FLASH-AND-TEST.md](FLASH-AND-TEST.md).
- Untuk status pratinjau **6.18**, lihat [STATUS.md](../6.18/STATUS.md) dan [SELINUX-6.18.md](SELINUX-6.18.md).
- Untuk riwayat rilis `v1`–`v19-kmi6` dan catatan historis 6.12, lihat [HANDOFF-HISTORY.md](../archive/6.12/HANDOFF-HISTORY.md).

## Lingkungan

- **Workspace 6.12:** `~/x6871-kernel` (setup mengikuti [README](../../README.md#build-dari-source))
- **Workspace 6.18:** `~/x6871-6.18/ws` (terisolasi dari 6.12)
- **Manifest:** `~/x6871-kernel-manifest`
- Jika `../vendor/mediatek` sudah dipakai workspace lain, tempatkan checkout
  baru di direktori induk terpisah (mis. `~/x6871-build/kernel`). `setup.sh`
  tidak akan menimpa link workspace lain. Set `KERNEL_ROOT` untuk repack.
- Referensi stock (modul `.ko` dari `vendor_boot`/`vendor_dlkm`/`odm_dlkm`,
  decompile `dtb`/`dtbo.img`, serta `ikconfig` stock) diekstrak dari
  [dump firmware stock X6871](https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6871)
  dan disimpan lokal di luar repo.

### Unduhan referensi

- **Source donor OPPO MT6896 (kernel 6.12):** [repo modul kernel OPPO Reno12, branch `oppo/mt6896_b_16.0_reno12`](https://github.com/oppo-source/android_kernel_modules_oppo_mt6896/tree/oppo/mt6896_b_16.0_reno12). Modul donor yang dipakai sudah disertakan di repo modul vendor X6871; tidak perlu clone terpisah untuk build.
- **Source donor Transsion 6.1:** [unduh `android15_kernel_modules_and_devicetree_mt6897.tar.gz`](https://d1wd32b69guoqm.cloudfront.net/opensource/android15_kernel_modules_and_devicetree_mt6897.tar.gz) dari [Infinix Open Source Center](https://opensource.dev.infinixmobility.com/). Tarball ini hanya untuk referensi porting driver, bukan basis atau prasyarat build.
- **Firmware stock X6871:** [dump firmware di GitLab](https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6871), versi referensi `X6871-16.3.0.155SP20`. Dipakai untuk mencari image bawaan serta membandingkan modul dan DTB/DTBO. Untuk rollback, gunakan firmware bawaan yang sesuai dengan perangkat dan versi yang dipakai sebelumnya.
- **Base `vendor_boot` recovery X6871 (6.18):** [`OrangeFox-X6871-k6.18-xos16.3.0.155.img`](https://github.com/transsion-custom-recovery-6-12/twrp-device_infinix_Infinix-X6871/releases/download/fox-16.0-k6.18-20261128/OrangeFox-X6871-k6.18-xos16.3.0.155.img) (rilis `fox-16.0-k6.18-20261128`, 64 MiB, SHA-256 `3d194830507f4d350caf99f2181aaf4a303dff13271c0082cda67670e6edaa8c`, MD5 `6503f225505f24bb18cd9453ae1abca4`; sudah menyertakan `permissive kernel;` untuk `firmware_load` 6.18). Untuk 6.12 gunakan rilis `k6.12` (`fox-16.0-20261128`) di repo yang sama.

### Perintah build

Build **6.12 (stabil)**:

```bash
cd ~/x6871-kernel
"$HOME/x6871-kernel-manifest/build.sh" user
```

Atau bentuk perintah Bazel lengkapnya:

```bash
cd ~/x6871-kernel
TMPDIR=~/tmp BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1 \
./tools/bazel --output_user_root="$PWD/out_bazel" build --config=stamp \
  --repo_manifest="$PWD/kernel_device_modules-6.12/fake_manifest.xml" \
  --experimental_writable_outputs --allow_ddk_unsafe_headers=1 \
  --user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers \
  --repo_env=KERNEL_VERSION=kernel-6.12 --repo_env=KERNEL_BUILD_VARIANT=user \
  --repo_env=DEFCONFIG_OVERLAYS="entry_level_legacy.config X6871.config" \
  --repo_env=SUPPORT_PLATFORM=mt6895 --repo_env=SOURCE_DATE_EPOCH=0 \
  --//build/bazel_mgk_rules:kernel_version=6.12 \
  "//kernel_device_modules-6.12:mgk_64_k612_customer_modules_install.user"
```

Staging hasil build 6.12:
`out_bazel/*/execroot/_main/bazel-out/k8-fastbuild/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/`

#### Build 6.18 (pratinjau)

```bash
cd "$HOME/x6871-6.18/ws"
KVER=6.18 OUT_DIR="$PWD/out_bazel_6.18" \
  "$HOME/x6871-kernel-manifest/build.sh" user
```

Verifikasi 6.18: lihat [STATUS.md](../6.18/STATUS.md#perintah-kerja).

#### Profil uji `6.18-lts` (`android17-6.18-lts`, `6.18.65`, KMI 6, build GKI lokal)

Default `local_manifest-6.18.xml` tetap pada tag pure-GKI
`android17-6.18-2026-09_r13` (`6.18.32`, KMI 5). Profil uji
`local_manifest-6.18-lts.xml` mem-pin `kernel/common` ke
`c22205f6c5bc5c483d45ffd8d39340a505976a2a` (`android17-6.18-lts`, `6.18.65`,
KMI 6) sebagai **profil build GKI lokal (*self-built*)**:

```bash
manifest="$HOME/x6871-kernel-manifest"
cp "$manifest/local_manifest-6.18-lts.xml" .repo/local_manifests/zz-x6871-6.18-lts.xml
repo sync -j16
KVER=6.18 "$manifest/setup.sh"

# Build 487 modul X6871 + GKI lokal (opsional: LOCALVERSION_SUFFIX="-<tag>")
KVER=6.18 OUT_DIR="$PWD/out_bazel_6.18_lts" "$manifest/build.sh" user
KVER=6.18 OUT_DIR="$PWD/out_bazel_6.18_lts" "$manifest/build.sh" gki
```

Catatan penting profil ini:

- **Pasangan wajib `boot` + `system_dlkm` lokal:** `boot-lz4.img` dan
  `system_dlkm.flatten.erofs.img` dari `./build.sh gki` memakai kunci signing
  ephemeral dari build tersebut sehingga keduanya wajib berasal dari satu set
  build yang sama (dan jangan dicampur dengan KMI 5). Untuk modul OOT
  (`vendor_boot`, `vendor_dlkm`, `odm_dlkm`), penentu boot di GKI adalah
  generasi KMI dan kecocokan simbol/CRC (`modversions`), bukan exact
  `vermagic`; modul OOT dengan `vermagic` berbeda pada KMI yang sama tetap
  dapat boot selama simbol/CRC-nya cocok.
- **Patch sementara `common` (`c22205f6c5bc`):** `6.18.63+` upstream sempat
  menghapus guard NULL di `blk_plug_invalidate_ts()` sehingga preemption IRQ di
  dalam `blk_finish_plug+0x54/0x78` memicu
  `Unable to handle kernel NULL pointer dereference at virtual address 0000000000000020`.
  `setup.sh` menerapkan `patches/common-6.18-blk-plug-invalidate-ts.patch`
  lewat `git am` **hanya** pada satu commit yang dipin saat ini
  (`c22205f6c5bc`, menghasilkan `c985884f48da`, tree bersih tanpa `-dirty`),
  dan tidak menyentuh `r13` maupun revisi lain. Build pada pin `c22205f6c5bc`
  (+ `c985884f48da`) sudah lulus `8/8` `verify-kmi-abi.py` (`9.877` simbol ABI;
  `vendor_boot.img` `56f9d11ba8a44c348d96de2b8cabdc43` menunggu uji live reboot
  TWRP), sedangkan set 5 image terakhir yang lulus uji live penuh di X6871
  adalah `6.18.65-android17-6-g39d19ad1a460-rama982-4k` (`4cc5bb220b50` +
  `39d19ad1a460`,
  boot, kamera/VENC, VP8/VP9/AV1, DPE, CMDQ, thermal LVTS, touch, serta fix minor
  `kthread_run_worker` dan `/proc/mtk_typec` dengan `0` panic/Oops; rincian di
  [`STATUS.md`](../6.18/STATUS.md) dan [`TRACKER.md`](../6.18/TRACKER.md)).
- `patches/kleaf-localversion-suffix.patch` menambah env var opsional
  `LOCALVERSION_SUFFIX` di `build/kernel/kleaf/workspace_status_stamp.py`
  (tidak aktif bila tidak diset).
- Saat repack & verifikasi, arahkan `--staging` dan `--out-dir` secara
  eksplisit ke `out_bazel_6.18_lts/` dan jalankan
  `./tools/verify-kmi-abi.py --kver 6.18` (wajib 8/8 PASS).

## Repack Image & Verifikasi KMI/ABI

### Repack vendor_boot (WAJIB dari build terbaru)

Ikuti [alur repack dan verifikasi di FLASH-AND-TEST](FLASH-AND-TEST.md#2-membuat-image-vendor_boot--dlkm),
termasuk penyiapan base recovery (OrangeFox/TWRP) dan packer.

Skrip ini menjalankan build di [Perintah build](#perintah-build), mengambil staging
**hasil build itu**, men-stage 222 modul dari `tools/recovery-modules.txt`
(221 modul pada `tools/recovery-modules-6.18.txt` untuk 6.18), menghapus debug
info, meregenerasi `modules.dep`/`alias`/`softdep`, pack dengan
`Android_boot_image_editor`, lalu membongkar hasilnya dan **gagal** kalau ada `.ko` yang beda dari staging.
Modul tidak pernah disalin dari image lama. Info commit/md5 ditulis ke `<out>.buildinfo`.

Menambah/mengurangi modul recovery: edit `tools/recovery-modules*.txt`,
`tools/modules.load*`, dan `tools/modules.load.recovery*` sekaligus.

#### Setup patch zstd untuk Android_boot_image_editor

Image recovery OrangeFox/TWRP untuk X6871 memakai ramdisk **zstd** (`28 b5 2f fd`), bukan lz4.
`cfig/Android_boot_image_editor` (commit `f692aff`) belum mengenalnya dan
berhenti dengan `ramdisk is in unknown format` saat `./gradlew unpack`.

Terapkan patch [`patches/abie-zstd-ramdisk.patch`](../../patches/abie-zstd-ramdisk.patch)
pada checkout `Android_boot_image_editor`:

```bash
git apply "$HOME/x6871-kernel-manifest/patches/abie-zstd-ramdisk.patch"
```

Isi patch:

- `helper/.../ZipHelper.kt` — `getZstdProg()`, `hasZstd`, `isZstd()` (deteksi
  lewat magic, bukan binary), `zstdcat()`, `zstd()` (kompres `-15 -T0`).
- `bbootimg/.../Common.kt` — cabang `isZstd` di `dumpRamdisk` (suffix `.zst`)
  dan cabang `.zst`/`.zstd` di kedua `packRootfs`.
- `bbootimg/.../cpio/AndroidCpio.kt` — skip hanya nilai positif untuk ramdisk
  kosong (`emptyrecovery` 60 byte).

### Repack DLKM & Safeguard Verifikasi KMI/ABI (WAJIB untuk setiap rilis & upgrade GKI)

Gunakan [perintah lengkap di FLASH-AND-TEST](FLASH-AND-TEST.md#2-membuat-image-vendor_boot--dlkm).
Skrip repack DLKM memverifikasi AVB hashtree. `verify-kmi-abi.py` memeriksa
kompatibilitas modul; arahkan `--vd-dir` dan `--od-dir` ke hasil repack bila
direktori kerja tidak berada di `out/` di sebelah workspace (default `~/out`).
Catatan: secara default, gerbang #2 di `verify-kmi-abi.py` memvalidasi
generasi KMI, page-size, dan flag `vermagic` agar selaras dengan
kompatibilitas runtime GKI (bukan exact `vermagic`); gunakan
`--strict-vermagic` bila ingin memaksa kecocokan string `vermagic` persis
satu set build.

#### Checklist cepat upgrade GKI

1. Cocokkan tag atau SHA `kernel/common` dari `manifest_<build-id>.xml` dengan banner `boot-lz4.img` CI. Cek `CLANG_VERSION`, `RUSTC_VERSION`, dan `KMI_GENERATION` di `build.config.constants` serta ketersediaan prebuilt.
2. Checkout revisi GKI murni di `ws/kernel-6.12` (atau `ws/common` untuk 6.18; jangan edit satu berkas pun di tree ini). Audit perubahan `modules.bzl`, header yang dipakai DDK, dan `gki/aarch64/abi.stg.allowed_breaks`. Jika rule Kleaf lama belum mendukung target GKI, perbaiki rule di `build/kernel`, bukan di GKI.
3. Build `mgk_64_k612_customer_modules_install.user` dengan kedua fragment X6871. Gunakan `OUT_DIR` terpisah dari output generasi KMI sebelumnya.
4. Repack dengan `./tools/repack-vendor-boot-latest.sh --skip-build` dan `./tools/repack-dlkm-latest.sh`; beri keduanya `--staging` dari build baru.
5. Jalankan `./tools/verify-kmi-abi.py` dengan `--out-dir` dan direktori modul hasil repack yang eksplisit. Wajib lulus semua pemeriksaan dan cocokkan CRC ekspor dengan `vmlinux.symvers` serta `system_dlkm.erofs.img` dari CI yang sama.
6. Setelah validasi lulus, pin tag atau SHA yang persis sama di `local_manifest.xml`. Untuk uji perangkat, pasangkan ketiga image modul baru dengan `boot-lz4.img` + `system_dlkm.erofs.img` CI tersebut. Jangan campur generasi KMI.

## Konfigurasi & Baseline

### Konfigurasi X6871

Refaktor ini ada di commit modul perangkat [`0fba8e7`](https://github.com/ramabondanp/alps-kernel_device_modules/commit/0fba8e7f20f47dc5814acd28fba14d6854b00520). Build uji KMI 6 dengan fragment X6871 dibangun dari revisi awal `f8198be`.
`entry_level_legacy.config` tetap dipakai untuk modul legacy MT6895.
`X6871.config` diterapkan sesudahnya untuk fitur perangkat. Simbol baru
dideklarasikan di `kernel/configs/Kconfig.x6871` dan dibaca melalui
`Kconfig.ext`; aturan DDK memakai konfigurasi yang dihasilkan Kconfig.
Tidak ada perubahan pada tree `kernel-6.12` (GKI). Pola fragment yang sama
juga dipakai di `kernel_device_modules-6.18/kernel/configs/` untuk build
6.18. Gunakan kedua fragment saat membangun branch port X6871. `OVERLAYS=""`
ditujukan untuk checkout baseline MTK yang dijelaskan di bawah.

Audit 106 commit modul perangkat (`06079c2..fa18f7f`):

| Asal override | Di build X6871 |
| --- | --- |
| Pengisian dan USB (`fdc1174`, `fb88495`, `93b7ebc`) | `TC_CLASS_SUPPORT=m`, `TC_CHARGER=m`; implementasi tetap berupa modul. |
| Audio (`4bd2024`, `7aa967a`, `eadd5eb`) | `SND_SOC_FS1599=m`, `USB_SWITCH_ET7480=y`; dependensi DDK tetap terdaftar. |
| Touch dan sidik jari (`1f42363`, `0e527bf`, `55aa132`) | `TOUCHSCREEN_GOODIX_BRL_SPI`, `TRAN_FP_DRV_MODE_SPI` dan `TRAN_HBM_NOTIFY_FINGERPRINT` aktif. Cabang API SPI pra-5.10 yang tidak dipakai dihapus. |
| Display (`2b880e6`, `381f45e`, `a31d53a`) | `PXLW_IRIS` memilih source Iris dan `TRANSSION_DOZE_BRIGHTNESS_SUPPORT` mengaktifkan doze brightness. RM69220 selalu membutuhkan ekstensi panel MTK, jadi makro lokal `CONFIG_MTK_PANEL_EXT` tidak diperlukan. |
| Senter (`1d3f17a`, `ebca3e1`) | `TRAN_FLASHLIGHT_TELE_SUPPORT=y`; kedua opsi `MTK_FLASHLIGHT_PT*` dinonaktifkan lewat fragment untuk menyamai stock. |
| LED (`39044a9`) | `CONFIG_TC_LEDS_CLASS` dihapus karena tidak dibaca oleh source. |

Konstanta protokol dan makro internal pustaka donor (misalnya Goodix dan
FourSemi) bukan opsi perangkat. Driver GPU Mali tetap memakai fragment DDK
milik modul vendor. Catatan dan skrip porting historis masih
mendokumentasikan override lama; jangan jalankan ulang skrip tersebut pada
branch yang sudah memakai fragment ini.

Validasi profil baru (`mt6895`, `user`): daftar modul hasil build tidak
berubah (553 file staging, 419 file flat). Semua 488 modul yang ditargetkan
untuk paket lulus delapan pemeriksaan `verify-kmi-abi.py` terhadap GKI KMI 6.
Maintainer melaporkan bahwa build uji KMI 6 dengan `X6871.config` (`f8198be`)
sudah diuji langsung di X6871. Rincian hasil uji per fitur belum dicatat.

**Untuk port berikutnya:** deklarasikan opsi baru di Kconfig tree modul dan
tetapkan nilainya di `X6871.config`, bukan lewat `-DCONFIG_*` di Bazel atau
`#define`/`#undef` di C. Pertahankan `=m` untuk implementasi modular dan
gunakan `IS_ENABLED()` bila kode harus aktif untuk `y` maupun `m`.
Setelah pindah versi, cek `.config` akhir build modul (Kconfig dapat membuang
opsi jika dependensinya tidak terpenuhi), pastikan konfigurasi GKI tetap
terpisah, lalu cek daftar modul, ABI/KMI, dan regresi di perangkat.

### Build baseline MTK tanpa driver X6871

Gunakan langkah ini untuk memverifikasi baseline MTK. Mulai dari workspace
terpisah yang sudah di-sync seperti di [README](../../README.md#build-dari-source),
agar checkout port X6871 tetap utuh. Contoh ini memakai
`~/x6871-mtk-baseline/kernel` sebagai root workspace terpisah.

```bash
~/x6871-kernel-manifest/scripts/reproduce-cleanup.sh ~/kernel-kernel_device_modules-6.12

cd ~/x6871-mtk-baseline/kernel/kernel_device_modules-6.12
git fetch ~/kernel-kernel_device_modules-6.12 mtk-base-latest
git checkout -B mtk-base-latest FETCH_HEAD
cd ..

~/x6871-kernel-manifest/setup.sh
OVERLAYS="" ~/x6871-kernel-manifest/build.sh user
```

Ini mengganti tree `kernel_device_modules-6.12` dengan baseline MTK; manifest
vendor tidak berubah. Untuk mengganti SoC build, set `PLATFORM` (default `mt6895`).

## Status Ringkas & Catatan Teknis

### Status ringkas (6.12 stabil)

| Item | Nilai |
|---|---|
| GKI base (`kernel-6.12`) | AOSP murni `android16-6.12-2026-09_r16` (`6.12.92-android16-6-g7cc745542612-4k`, **KMI 6**, tanpa patch) |
| `.ko` flat customer install | **419** (di-trim via `kernel/kleaf/x6871_modules.bzl` ke **413** target OOT X6871; sebelumnya 679) |
| `.ko` di staging (file / nama unik) | **553 / 552** (`mtk-socinfo` dobel; sebelumnya 813 / 812; action Bazel `4.867 → 919`) |
| Modul di firmware X6871 | 237 (`vendor_boot`) + 288 (`vendor_dlkm` + `odm_dlkm`) |
| Nama stock `vendor_boot` tidak ada di build | **20** (6 tidak direncanakan, 14 kandidat) |
| Modul recovery `vendor_boot` | **222** `.ko` dibangun dari kode sumber (KMI 6) |
| DLKM (`vendor_dlkm` + `odm_dlkm`) | **266** `.ko` (`209` + `57`) dibangun dari kode sumber (KMI 6, tanpa bentrok `CONFIG_MODULE_SIG_PROTECT`) |
| Build target | `//kernel_device_modules-6.12:mgk_64_k612_customer_modules_install.user` |
| Build terakhir | sukses (clean KMI 6 + trimmed X6871 allowlist), 2026-11-22 |
| Revisi modul perangkat untuk build dari source | [`0fba8e7`](https://github.com/ramabondanp/alps-kernel_device_modules/commit/0fba8e7f20f47dc5814acd28fba14d6854b00520) (`x6871-android16-6.12`, referensi build uji `v19-kmi6` memakai `fa18f7f`; backport lintas-branch terbaru hingga `175263d9b928`, belum dibuild ulang) |
| Vendor MTK modules HEAD | `83b4fa6` (`alps-vendor_mediatek_kernel_modules`, `x6871-android16-6.12` saat uji `v19-kmi6`; backport lintas-branch terbaru hingga `5e9b2d8`, belum dibuild ulang) |
| Active clean workspace | `~/x6871-kernel` |
| Runtime | **Lulus boot di GKI KMI 6 (`android16-6.12-2026-09_r16`, `v19-kmi6`)** dengan `boot-lz4.img` + `system_dlkm.erofs.img` resmi Google (0 mismatch CRC vs `abi.stg` `10.630` simbol, 0 kolisi `CONFIG_MODULE_SIG_PROTECT`, 0 unresolved symbol). Rincian log fitur berasal dari KMI 5; konfirmasi uji langsung oleh maintainer dicatat pada build uji `v19-kmi6` (GitHub Release lama sudah dihapus). |

Klaim dibangun dari kode sumber berlaku untuk **488 modul `.ko`** dalam tiga
image rilis X6871, bukan seluruh isi image. Tidak ada `.ko` stock yang disalin
ke dalamnya. Image GKI Google dipakai tanpa modifikasi; repack `vendor_boot`
mempertahankan komponen dasar TWRP seperti DTB dan ramdisk recovery.

Source resmi khusus X6871 tidak dipublikasikan. Port ini menggunakan tree
modul Motorola W1VO36.88-36-7 sebagai basis, mengadaptasi driver dari kode
sumber donor, dan merekonstruksi bagian yang belum tersedia lewat reverse
engineering modul kernel (`.ko`) dari firmware bawaan X6871. AOSP GKI adalah
kernel dasar yang ditargetkan, bukan objek reverse engineering.

#### Catatan referensi KMI 7 (arsip eksperimen 6.12)

Profil overlay `local_manifest-kmi7.xml` dan patch Kleaf KMI 7 sudah dihapus
karena fokus pengembangan pindah ke **6.18** dan **6.12** di-pin ke tag stabil
`android16-6.12-2026-09_r16` (KMI 6). Catatan teknis berikut dipertahankan
sebagai referensi bila suatu saat perlu meng-upgrade generasi KMI 6.12:

- **Revisi GKI referensi:** `kernel/common`
  `14d40582269013a9bc6df12b2479da18f27e3d33` dari
  [Google CI `16987858`, target `kernel_aarch64`](https://ci.android.com/builds/submitted/16987858/kernel_aarch64/latest)
  (`6.12.96-android16-7-g14d405822690-ab16987858-4k`, KMI 7, 4 KB). Ini
  berbeda dari tag `android16-6.12-2026-09_r17`, yang masih KMI 6.
- **Kompatibilitas Kleaf:** tree Kleaf Motorola (`w1vo36.88-36-7`) memerlukan
  backport rule `multi_abi_update` di `build/kernel` (bukan mengedit checkout
  GKI) agar target ABI GKI KMI 7 bisa dibangun.
- **Rebuild penuh modul & isolasi KMI:** peta CRC `abi.stg` revisi tersebut
  memuat `10.704` simbol (`2.657` simbol impor unik dari GKI). Seluruh 488
  modul (`222` `vendor_boot`, `209` `vendor_dlkm`, `57` `odm_dlkm`) memiliki
  CRC impor berbeda terhadap KMI 7, sehingga ketiga image modul wajib dibangun
  ulang pada `OUT_DIR` terpisah (berikan `--staging` dan `--out-dir` eksplisit
  ke skrip repack/verifier) dan tidak boleh dicampur dengan `boot-lz4.img`
  atau `system_dlkm.erofs.img` KMI 6. Rollback ke KMI 6 mewajibkan pemulihan
  kelima image sebagai satu set (lihat
  [prosedur rollback](FLASH-AND-TEST.md#3-flash-dan-rollback)).
- **Modul GKI baru:** `pretimeout_dump.ko` ditambahkan oleh GKI KMI 7 dan
  sudah tersedia di `system_dlkm.erofs.img` Google; tidak perlu disalin ke
  image modul X6871.
- **Hasil uji hardware dari build eksperimen KMI 7:**
  - [OTP kamera](../archive/6.12/PRETEST.md#69-uji-kamera-dengan-port-otp--kmi-7):
    kamera dilaporkan normal, tetapi pemakaian data OTP oleh HAL belum
    terverifikasi.
  - [Fuel gauge MT6375](../archive/6.12/PRETEST.md#70-uji-fuel-gauge-mt6375--kmi-7):
    profil 3 dan `charge_full` 5.000.000 µAh terbaca; `fuelgauged` stock aktif
    dan UI naik dari 78% ke 81%. Uji sampai `DONE` masih pending.
  - [LED AW22XXX](../archive/6.12/PRETEST.md#71-uji-probe-aw22xxx--kmi-7):
    probe dilaporkan berhasil setelah koreksi GPIO interrupt; efek LED belum
    diuji.

### Aturan teknis build & audit biner

Aturan kerja umum (commit, push, checkpatch, struktur `docs/`, DTB/DTBO, dan
GKI) ada di [`AGENTS.md`](../../AGENTS.md). Berikut aturan teknis khusus build
dan audit modul `.ko`:

1. **Jangan pakai `/tmp`** — pakai `~/tmp` / `$TMPDIR`.
2. **GKI (`kernel-6.12` / `common`) tidak boleh diedit untuk menyesuaikan modul.**
   Semua adaptasi KMI/API dilakukan di `kernel_device_modules-*`,
   `vendor/mediatek/kernel_modules`, atau `local_manifest*.xml` agar modul
   selalu kompatibel dengan `boot.img` + `system_dlkm.img` resmi Google
   (pengecualian sementara hanya untuk profil uji `6.18-lts`: `setup.sh`
   menerapkan patch SHA-gated `patches/common-6.18-blk-plug-invalidate-ts.patch`
   hingga upstream fix masuk).
3. **Jangan masukkan modul GKI terproteksi ke `vendor_dlkm`/`vendor_boot`/`odm_dlkm`.**
   Pada GKI resmi Google (`CONFIG_MODULE_SIG_PROTECT=y`), setiap modul di
   `modules.bzl` selain `_COMMON_UNPROTECTED_MODULES_LIST`
   (`zram.ko`, `zsmalloc.ko`) akan ditolak (`-EACCES`) bila tidak bertanda
   tangan kunci GKI Google (mis. `rfkill.ko`, `bluetooth.ko`, `libarc4.ko`).
   Modul-modul itu disediakan langsung oleh `system_dlkm.img` Google.
4. **Wajib jalankan `./tools/verify-kmi-abi.py` sebelum setiap uji atau rilis.**
   Skrip ini memvalidasi 8 gerbang sekaligus (GKI murni bersih, vermagic,
   0 kolisi `CONFIG_MODULE_SIG_PROTECT`, closure `vendor_boot` standalone & penuh,
   0 mismatch CRC vs `gki/aarch64/abi.stg`, 0 impor `vmlinux` non-KMI, dan
   integritas `modules.dep`/`modules.load`).
5. **Saat KMI generation naik (mis. 5 → 6), audit semua objek prebuilt (`.o`/`.a`).**
   Perubahan layout struct di `gki/aarch64/abi.stg.allowed_breaks` tidak memicu
   error compile pada `ddk_prebuilt_object`; pastikan tidak ada modul di set
   runtime X6871 yang menautkan `.o` prebuilt (saat ini hanya `sched_cus` yang
   punya `.o` prebuilt dan ketiganya tidak dipakai X6871).
6. **Audit kesesuaian modul vs firmware stock:**
   - Cocokkan modul lewat fingerprint simbol/isi `.ko` (`GLOBAL` ekspor dan
     impor via `readelf -sW`), bukan lewat nama file semata.
   - "Tidak ada `<nama>.c`" tidak berarti tidak ada source: modul gabungan
     terdaftar di `Makefile` sebagai `<module>-objs`; cek `.c` senama,
     `Makefile`/`Kbuild`, `Kconfig`, `mgk_64_module_outs` di `*.bzl`, dan
     fingerprint simbol.
   - `LOCAL FUNC` hanya mencerminkan inlining; perbedaan impor sysfs pada build
     DDK bukan bug.
   - Layout struct diukur dari `.ko`, bukan dari diff header saja.
   - Build hijau bukan jaminan isi benar (mis. kebocoran simbol panel atau
     offset ops `charger_ops`/`tcpc_ops`/`tc_tfcp_ta`/`pca_tfcp_ta` hanya
     tertangkap dari diff simbol/relokasi).
   - `tc_charger_class` menggantikan `charger_class` MTK (firmware stock tidak
     mengirim `charger_class.ko`).
   - 7 modul GKI (`arm_dsu_pmu`, `drm_display_helper`, `drm_dma_helper`,
     `industrialio-triggered-buffer`, `kfifo_buf`, `reboot-mode`,
     `syscon-reboot-mode`) ada di `mgk_module_ext_outs`, bukan gap modul.

### Jebakan build

- `--user_ddk_unsafe_headers=...mtk_use_gki_unsafe_headers` **wajib**; tanpa
  itu puluhan header hilang.
- Target ABI `user_customer_abi` **tidak bisa lulus** (328 simbol duplikat
  dari driver multi-varian). Referensi MTK/Samsung juga tidak menjalankannya.
- Label `//kernel_device_modules-{}` **wajib** diikuti
  `.format(kernel_version)` — generator sempat menjatuhkannya 4 kali.
- Komentar Bazel adalah `#`, bukan `/* */`.
- `ko_deps` harus memuat **setiap** penyedia simbol yang diimpor, kalau tidak
  `modpost: "<sym>" undefined!`.
- `tar` gzip satu inti mati di tengah (>3 menit). Pakai
  `pigz -dc file.tar.gz | tar -x -C dir` — 7.106 file <60 s.
- **Jangan menyalin `.ko` dari image lama sebagai baseline repack.** Itu
  penyebab `usb-replug` memuat panel driver pra-perbaikan layar
  ([`PRETEST.md` §43](../archive/6.12/PRETEST.md)). Selalu pakai `tools/repack-vendor-boot-latest.sh`.

## Resep verifikasi

```bash
B=<dir-modul-staging>; F=<dir-modul-stock>
# ekspor
diff <(readelf -sW $B/<m>.ko | awk '$4=="FUNC"&&$7!="UND"&&$5=="GLOBAL"&&$8!=""{print $8}' | sort -u) \
     <(readelf -sW $F/<m>.ko | awk '$4=="FUNC"&&$7!="UND"&&$5=="GLOBAL"&&$8!=""{print $8}' | sort -u)
# impor
diff <(readelf -sW $B/<m>.ko | awk '$7=="UND"{print $8}' | sort -u) \
     <(readelf -sW $F/<m>.ko | awk '$7=="UND"{print $8}' | sort -u)
# alias DT
diff <(strings -a $B/<m>.ko | grep '^alias=' | sort) \
     <(strings -a $F/<m>.ko | grep '^alias=' | sort)
```

Untuk layout struct: cari `ldr x8,[x0,#0x8]` lalu `ldr x8,[x8,#N]`; `N/8`
adalah indeks field. Bandingkan dengan firmware. Tambahkan `_Static_assert`
agar build gagal kalau offset bergeser.
