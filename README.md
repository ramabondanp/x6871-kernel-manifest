# Manifest Kernel X6871 — Port Linux 6.12 & 6.18 Tidak Resmi

Repo ini menyediakan manifest dan skrip untuk membangun modul kernel **Infinix GT 20 Pro (X6871 / MT6895)**. Rilis stabil memakai **Android 16 dan kernel Linux 6.12**. **Kernel 6.18** sedang disiapkan untuk **Android 17** dan masih dalam pengujian.

Port tidak resmi ini mengadaptasi driver dari kode sumber donor dan merekonstruksi bagian yang tidak dipublikasikan melalui reverse engineering modul kernel dari firmware bawaan X6871. Kernel inti tetap memakai GKI resmi Google tanpa modifikasi.

**Ringkasan:** gunakan branch **6.12** (bangun dari source) untuk penggunaan harian; semua GitHub Release lama sudah dihapus karena kedaluwarsa. **Kernel 6.18** masih pratinjau dan belum memiliki image rilis publik.

## Apa yang sudah diuji?

Build uji **6.12 KMI 6** (`v19-kmi6`) berhasil boot sampai launcher dengan GKI resmi Google `android16-6.12-2026-09_r16` (Linux 6.12.92, KMI 6). Maintainer telah menguji langsung fungsi perangkat yang tercantum di bawah pada X6871 dan melaporkan semuanya berfungsi.

Maintainer juga melaporkan bahwa build uji KMI 6 dengan `X6871.config` (`f8198be`) sudah diuji langsung di X6871. Rincian hasil uji per fitur untuk build tersebut belum dicatat.

Pada build sebelumnya (KMI 5), TWRP, layar hingga 144 Hz dan Always-On Display (AOD), GPU, Wi-Fi, audio speaker dan earpiece, kamera foto dan video, senter, getar, ketuk dua kali untuk membangunkan layar, sidik jari dalam layar, dan pengisian daya cepat sudah diuji dan berfungsi. Masalah USB saat kabel dicabut dan dipasang kembali ditemukan pada GKI kustom, bukan pada modul perangkat. Lihat [hasil pengujian](docs/archive/6.12/HANDOFF-HISTORY.md#hasil-uji-perangkat-sebelum-migrasi-kmi-5) untuk rinciannya.

## Status 6.18 (pratinjau)

Kernel 6.18 belum dirilis dan belum disarankan untuk penggunaan harian. Pada perangkat uji (`6.18.65`), sistem sudah bisa boot (memerlukan [patch SELinux `firmware_load`](docs/guides/SELINUX-6.18.md)). TWRP (layar sentuh dan getar), Wi-Fi, Bluetooth, audio, kamera foto dan rekam video 1080p, pemutaran video H.264, VP8, VP9, dan AV1, thermal LVTS, serta kontrol sentuh sudah berfungsi. 6.18 belum memiliki image rilis publik.

Rilis 6.12 di atas tetap menjadi versi yang direkomendasikan. Perkembangan 6.18 dicatat di [status eksekusi 6.18](docs/6.18/STATUS.md).

## Build dari source

Panduan berikut untuk rilis stabil 6.12. Pratinjau 6.18 dibangun terpisah dan belum memiliki image rilis publik; langkahnya ada di [status eksekusi 6.18](docs/6.18/STATUS.md#perintah-kerja).

Siapkan Linux x86-64, Git, dan [Repo](https://gerrit.googlesource.com/git-repo/). Sediakan ruang disk untuk source Android dan hasil build.

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

`build.sh` menerapkan `entry_level_legacy.config` lalu `X6871.config` dari
`kernel_device_modules-6.12/kernel/configs/`. Keduanya mengatur build modul
perangkat, bukan image GKI resmi. Lihat [konfigurasi X6871](docs/guides/BUILD.md#konfigurasi-x6871).

Modul `.ko` hasil build ada di direktori berikut, relatif terhadap `~/x6871-kernel`:

```text
out_bazel/*/execroot/_main/bazel-out/k8-fastbuild/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/
```

## Sebelum flash

Bagian ini untuk baseline **6.12** (`android16-6.12-2026-09_r16`, KMI 6). Semua GitHub Release lama sudah dihapus karena sudah kedaluwarsa, dan versi 6.18 belum memiliki image rilis publik serta belum disarankan untuk flash harian.

Bangun `vendor_boot`, `vendor_dlkm`, dan `odm_dlkm` dari source melalui [langkah membuat image](docs/guides/FLASH-AND-TEST.md#2-membuat-image-vendor_boot--dlkm). Pasangkan ketiganya dengan **`boot-lz4.img` dan `system_dlkm.erofs.img`** dari [artefak GKI resmi Google `android16-6.12-2026-09_r16` (KMI 6)](https://ci.android.com/builds/submitted/16901051/kernel_aarch64/latest). Jangan campur dengan image KMI 5. `dtbo.img` tetap bawaan perangkat.

**Khusus X6871 dengan bootloader terbuka.** Cadangkan data dan siapkan image bawaan untuk rollback sebelum flash. Lihat [komposisi image dan checksum referensi](docs/guides/FLASH-AND-TEST.md#1-komposisi-artefak-612-kmi-6) serta [panduan flash dan rollback](docs/guides/FLASH-AND-TEST.md#3-flash-dan-rollback).

## Dokumentasi lanjutan

- **Build & Repack:** [panduan build & repack](docs/guides/BUILD.md) — lingkungan, [unduhan referensi](docs/guides/BUILD.md#unduhan-referensi), pemecahan masalah, serta [build baseline MediaTek tanpa driver X6871](docs/guides/BUILD.md#build-baseline-mtk-tanpa-driver-x6871).
- **Flash & Uji Boot:** [prosedur flash, rollback, dan checklist](docs/guides/FLASH-AND-TEST.md).
- **Hardware & DTBO:** [pemetaan hardware](docs/hardware/DEVICES.md) dan [overlay X6871](docs/hardware/DEVICES-OVERLAY.md) — hubungan node DT dengan drivernya.
- **Pratinjau 6.18:** [status 6.18](docs/6.18/STATUS.md), [tracker isu & verifikasi](docs/6.18/TRACKER.md), dan [patch SELinux `firmware_load`](docs/guides/SELINUX-6.18.md).
- **Indeks & Arsip:** [peta dokumentasi](docs/README.md) — tautan ke seluruh dokumen termasuk arsip porting 6.12 (`PLAN`, `PRETEST`, `HANDOFF-HISTORY`) dan log bringup awal 6.18.

Log mentah (`pstore`, `dmesg`, `logcat`) dan image uji disimpan lokal dan
tidak disertakan di repo. Dokumentasi mengutip baris log sebagai bukti,
bukan merujuk nama file lokal.

## Kredit dan lisensi

Port ini memakai GKI dari [AOSP](https://android.googlesource.com/kernel/common), basis MediaTek dari [Motorola](https://github.com/MotorolaMobilityLLC/kernel-kernel_device_modules-6.12), modul tambahan dari [OPPO Reno12 (MT6896)](https://github.com/oppo-source/android_kernel_modules_oppo_mt6896/tree/oppo/mt6896_b_16.0_reno12), dan driver Transsion dari [Infinix Open Source Center](https://opensource.dev.infinixmobility.com/). Kode port tersedia di repo [modul perangkat](https://github.com/ramabondanp/alps-kernel_device_modules) dan [modul vendor](https://github.com/ramabondanp/alps-vendor_mediatek_kernel_modules). Branch `x6871-android16-6.12` berisi rilis stabil; branch `x6871-android17-6.18` berisi pratinjau 6.18. Repo manifest ini berlisensi [GPL-2.0](LICENSE).
