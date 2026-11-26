# Manifest Kernel X6871 — Port Linux 6.12 & 6.18 Tidak Resmi

Repo ini menyediakan manifest dan skrip untuk **membangun kernel Linux (GKI + modul kernel perangkat)** untuk **Infinix GT 20 Pro (X6871 / MT6895)** — **bukan** untuk membangun ROM/OS Android (`system.img`, `vendor.img`, dsb.). Kernel dan modul hasil build dipasang di atas firmware bawaan X6871 dengan tetap memakai `dtb` dan `dtbo.img` stock.

Port tidak resmi ini mengadaptasi driver dari kode sumber donor serta merekonstruksi bagian yang tidak dipublikasikan melalui reverse engineering modul `.ko` bawaan X6871, di atas kernel inti **GKI AOSP** (image GKI resmi Google untuk `6.12` dan `6.18 r13`, atau build GKI lokal pada profil uji `6.18-lts`).

| Jalur Kernel | Basis Branch GKI | Status | Catatan |
|---|---|---|---|
| **6.12** (KMI 6) | `android16-6.12` | **Stabil (harian)** | Bangun dari source; GitHub Release lama sudah dihapus karena kedaluwarsa |
| **6.18** (KMI 5 / 6) | `android17-6.18` | **Pratinjau** | Belum disarankan untuk harian dan belum ada rilis publik; butuh [patch SELinux `firmware_load`](docs/guides/SELINUX-6.18.md) di atas ROM stock X6871 |

## Status pengujian

- **Kernel 6.12 (baseline harian):** berhasil boot ke sistem Android dan TWRP pada X6871 dengan GKI resmi Google `android16-6.12-2026-09_r16` (`6.12.92`, KMI 6). Fungsi utama yang telah teruji mencakup layar hingga 144 Hz dan Always-On Display (AOD), GPU, Wi-Fi, audio speaker dan earpiece, kamera foto dan video, senter, getar, ketuk dua kali untuk membangunkan layar, sidik jari dalam layar, serta pengisian daya cepat ([riwayat pengujian](docs/archive/6.12/HANDOFF-HISTORY.md#hasil-uji-perangkat-sebelum-migrasi-kmi-5)).
- **Kernel 6.18 (pratinjau):** pada perangkat uji (`6.18.65`), sistem sudah bisa boot (dengan [patch SELinux `firmware_load`](docs/guides/SELINUX-6.18.md)). TWRP (sentuh dan getar), Wi-Fi, Bluetooth, audio, kamera foto dan rekam video 1080p, pemutaran video H.264/VP8/VP9/AV1, thermal LVTS, serta kontrol sentuh sudah berfungsi. Perkembangan lengkap dicatat di [status eksekusi 6.18](docs/6.18/STATUS.md).

## Build dari source

Siapkan Linux x86-64, Git, dan [Repo](https://gerrit.googlesource.com/git-repo/), serta ruang disk untuk **source kernel GKI AOSP dan modul kernel** (tidak memerlukan source OS Android penuh).

### Build stabil 6.12

```bash
git clone https://github.com/ramabondanp/x6871-kernel-manifest ~/x6871-kernel-manifest

mkdir -p ~/x6871-kernel
cd ~/x6871-kernel
repo init -u https://android.googlesource.com/kernel/manifest \
  -b common-android16-6.12-2026-09
mkdir -p .repo/local_manifests
cp ~/x6871-kernel-manifest/local_manifest.xml .repo/local_manifests/x6871.xml
repo sync

~/x6871-kernel-manifest/setup.sh
~/x6871-kernel-manifest/build.sh user
```

`build.sh` menerapkan `entry_level_legacy.config` lalu `X6871.config` dari `kernel_device_modules-6.12/kernel/configs/` untuk mengatur build modul perangkat, bukan mengubah image GKI resmi (lihat [konfigurasi X6871](docs/guides/BUILD.md#konfigurasi-x6871)). Modul `.ko` hasil build ada di direktori berikut, relatif terhadap `~/x6871-kernel`:

```text
out_bazel/*/execroot/_main/bazel-out/k8-fastbuild/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/
```

### Build pratinjau 6.18

Gunakan workspace terpisah dari `6.12`:

```bash
mkdir -p ~/x6871-6.18/ws && cd ~/x6871-6.18/ws
repo init -u https://android.googlesource.com/kernel/manifest \
  -b common-android17-6.18-2026-09 --depth=1
mkdir -p .repo/local_manifests
cp ~/x6871-kernel-manifest/local_manifest-6.18.xml .repo/local_manifests/x6871-6.18.xml
repo sync -j16

KVER=6.18 ~/x6871-kernel-manifest/setup.sh
KVER=6.18 ~/x6871-kernel-manifest/build.sh user
```

Untuk opsi build GKI lokal `6.18-lts` dan perintah verifikasi lanjutan, lihat [profil `6.18-lts`](docs/guides/BUILD.md#profil-uji-618-lts-android17-618-lts-61865-kmi-6-build-gki-lokal) serta [status eksekusi 6.18](docs/6.18/STATUS.md#perintah-kerja).

## Sebelum flash

Output build adalah modul dan image partisi kernel (`vendor_boot`, `vendor_dlkm`, dan `odm_dlkm`) melalui [langkah membuat image](docs/guides/FLASH-AND-TEST.md#2-membuat-image-vendor_boot--dlkm):

- **Baseline 6.12 (KMI 6):** pasangkan ketiga image modul hasil build dengan **`boot-lz4.img` dan `system_dlkm.erofs.img`** dari [artefak GKI resmi Google `android16-6.12-2026-09_r16` (KMI 6)](https://ci.android.com/builds/submitted/16901051/kernel_aarch64/latest).
- **Pratinjau 6.18:** untuk profil `6.18-lts`, flash seluruh set 5 image hasil build lokal (termasuk `boot-lz4.img` dan `system_dlkm.flatten.erofs.img`).
- **`dtbo.img` dan `dtb` tetap memakai bawaan perangkat.** Jangan mencampur image antar versi kernel (`6.12` vs `6.18`) maupun antar generasi KMI (`KMI 5` vs `KMI 6`).

**Khusus X6871 dengan bootloader terbuka.** Cadangkan data dan siapkan image bawaan untuk rollback sebelum flash. Lihat [komposisi image dan checksum referensi](docs/guides/FLASH-AND-TEST.md#1-komposisi-artefak-612-kmi-6) serta [panduan flash dan rollback](docs/guides/FLASH-AND-TEST.md#3-flash-dan-rollback).

## Dokumentasi lanjutan

- **Build & Repack:** [panduan build & repack](docs/guides/BUILD.md) — lingkungan, [unduhan referensi](docs/guides/BUILD.md#unduhan-referensi), pemecahan masalah, serta [build baseline MediaTek tanpa driver X6871](docs/guides/BUILD.md#build-baseline-mtk-tanpa-driver-x6871).
- **Flash & Uji Boot:** [prosedur flash, rollback, dan checklist](docs/guides/FLASH-AND-TEST.md).
- **Hardware & DTBO:** [pemetaan hardware](docs/hardware/DEVICES.md) dan [overlay X6871](docs/hardware/DEVICES-OVERLAY.md) — hubungan node DT dengan drivernya.
- **Pratinjau 6.18:** [status 6.18](docs/6.18/STATUS.md), [tracker isu & verifikasi](docs/6.18/TRACKER.md), [audit API 6.18](docs/6.18/API-AUDIT.md), dan [patch SELinux `firmware_load`](docs/guides/SELINUX-6.18.md).
- **Indeks & Arsip:** [peta dokumentasi](docs/README.md) — tautan ke seluruh dokumen termasuk arsip porting 6.12 (`PLAN`, `PRETEST`, `HANDOFF-HISTORY`) dan log bringup awal 6.18.

## Kredit dan lisensi

Port ini memakai GKI dari [AOSP](https://android.googlesource.com/kernel/common), basis MediaTek dari [Motorola](https://github.com/MotorolaMobilityLLC/kernel-kernel_device_modules-6.12), modul tambahan dari [OPPO Reno12 (MT6896)](https://github.com/oppo-source/android_kernel_modules_oppo_mt6896/tree/oppo/mt6896_b_16.0_reno12), dan driver Transsion dari [Infinix Open Source Center](https://opensource.dev.infinixmobility.com/). Kode port tersedia di repo [modul perangkat](https://github.com/ramabondanp/alps-kernel_device_modules) dan [modul vendor](https://github.com/ramabondanp/alps-vendor_mediatek_kernel_modules). Branch `x6871-android16-6.12` berisi rilis stabil; branch `x6871-android17-6.18` berisi pratinjau 6.18. Repo manifest ini berlisensi [GPL-2.0](LICENSE).
