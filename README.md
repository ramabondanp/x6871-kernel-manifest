# Manifest Kernel X6871 — Port Linux 6.12 Tidak Resmi

Repo ini menyediakan manifest dan skrip untuk mengambil kode sumber dan membangun modul kernel **Android 16** untuk **Infinix GT 20 Pro (X6871 / MT6895)**. Port tidak resmi ini mengadaptasi driver dari kode sumber donor dan merekonstruksi bagian yang tidak dipublikasikan melalui reverse engineering modul kernel (`.ko`) dari firmware bawaan X6871. Modul hasil port berjalan di atas **AOSP GKI 6.12 tanpa modifikasi**.

## Apa yang sudah diuji?

**[Rilis eksperimental `gki-kmi6-20261122`](https://github.com/ramabondanp/x6871-kernel-manifest/releases/tag/gki-kmi6-20261122)** berhasil boot sampai launcher dengan GKI resmi Google `android16-6.12-2026-09_r16` (Linux 6.12.92, KMI 6). Maintainer telah menguji langsung fungsi perangkat yang tercantum di bawah pada X6871 dan melaporkan semuanya berfungsi.

Pada build sebelumnya (KMI 5), TWRP, layar hingga 144 Hz dan Always-On Display (AOD), GPU, Wi-Fi, audio speaker dan earpiece, kamera foto dan video, senter, getar, ketuk dua kali untuk membangunkan layar, sidik jari dalam layar, dan pengisian daya cepat sudah diuji dan berfungsi. Masalah USB saat kabel dicabut dan dipasang kembali ditemukan pada GKI kustom, bukan pada modul perangkat. Lihat [hasil pengujian](docs/HANDOFF.md) untuk rinciannya.

## Build dari source

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
perangkat, bukan image GKI resmi. Lihat [konfigurasi X6871](docs/HANDOFF.md#konfigurasi-x6871).

Modul `.ko` hasil build ada di direktori berikut, relatif terhadap `~/x6871-kernel`:

```text
out_bazel/*/execroot/_main/bazel-out/k8-fastbuild/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/
```

## Sebelum flash

Unduh `vendor_boot`, `vendor_dlkm`, dan `odm_dlkm` dari [GitHub Release](https://github.com/ramabondanp/x6871-kernel-manifest/releases/tag/gki-kmi6-20261122). Pasangkan ketiganya dengan **`boot-lz4.img` dan `system_dlkm.erofs.img`** dari [artefak GKI resmi Google `android16-6.12-2026-09_r16` (KMI 6)](https://ci.android.com/builds/submitted/16901051/kernel_aarch64/latest). Jangan campur dengan image KMI 5. `dtbo.img` tetap bawaan perangkat.

**Khusus X6871 dengan bootloader terbuka.** Cadangkan data dan siapkan image bawaan untuk rollback sebelum flash. Lihat [daftar image dan checksum](docs/BOOTTEST.md#1-artefak-uji-terbaru-gki-kmi6-20261122) serta [panduan flash dan rollback](docs/BOOTTEST.md#3-flash-dan-rollback). Jika build sendiri, ikuti [langkah membuat image](docs/BOOTTEST.md#2-membuat-image-vendor_boot--dlkm) terlebih dahulu.

## Dokumentasi lanjutan

- [Panduan teknis](docs/HANDOFF.md) — riwayat rilis, [unduhan referensi](docs/HANDOFF.md#unduhan-referensi), pemecahan masalah build, dan [build baseline MediaTek tanpa driver X6871](docs/HANDOFF.md#build-baseline-mtk-tanpa-driver-x6871).
- [Profil uji KMI 7](docs/HANDOFF.md#profil-uji-kmi-7--google-ci-16987858) — overlay terpisah untuk Google CI `16987858`; build default dan image rilis di atas tetap KMI 6.
- [Pemetaan hardware](docs/DEVICES.md) dan [overlay X6871](docs/DEVICES-OVERLAY.md) — hubungan perangkat dengan drivernya.
- [Log pengujian](docs/PRETEST.md), [catatan porting 6.12](docs/PLAN.md), dan [rencana 6.18](docs/PLAN-6.18.md) (belum tersedia).

## Kredit dan lisensi

Port ini memakai GKI dari [AOSP](https://android.googlesource.com/kernel/common), basis MediaTek dari [Motorola](https://github.com/MotorolaMobilityLLC/kernel-kernel_device_modules-6.12), modul tambahan dari [OPPO Reno12 (MT6896)](https://github.com/oppo-source/android_kernel_modules_oppo_mt6896/tree/oppo/mt6896_b_16.0_reno12), dan driver Transsion dari [Infinix Open Source Center](https://opensource.dev.infinixmobility.com/). Kode port tersedia di repo [modul perangkat](https://github.com/ramabondanp/alps-kernel_device_modules-6.12/tree/x6871-android16-6.12) dan [modul vendor](https://github.com/ramabondanp/alps-vendor_mediatek_kernel_modules/tree/x6871-android16-6.12). Repo manifest ini berlisensi [GPL-2.0](LICENSE).
