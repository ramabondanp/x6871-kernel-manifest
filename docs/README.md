# Peta Dokumentasi X6871

Indeks seluruh dokumentasi di `docs/`, dikelompokkan berdasarkan tujuan pembaca. Untuk ringkasan rilis stabil **6.12** dan langkah cepat memulai, baca [README utama](../README.md).

## Panduan Operasional (`guides/`)

- [BUILD.md](guides/BUILD.md) — lingkungan workspace, `X6871.config`, perintah build 6.12 & 6.18, baseline MTK, repack `vendor_boot`/DLKM, setup patch zstd `Android_boot_image_editor`, catatan referensi KMI 7, profil uji 6.18-lts, serta aturan keras build.
- [FLASH-AND-TEST.md](guides/FLASH-AND-TEST.md) — komposisi artefak 6.12 (KMI 6), prosedur flash & rollback, checklist subsistem, dan debugging `modules.dep`.
- [SELINUX-6.18.md](guides/SELINUX-6.18.md) — prosedur wajib patch policy SELinux `firmware_load` untuk boot sistem Android pada kernel 6.18.

## Referensi Hardware (`hardware/`)

- [DEVICES.md](hardware/DEVICES.md) — pemetaan lengkap node DTBO + base DTB stock ke driver/modul (berlaku lintas 6.12 & 6.18).
- [DEVICES-OVERLAY.md](hardware/DEVICES-OVERLAY.md) — tabel ringkas node spesifik X6871 yang hanya berasal dari overlay DTBO.

## Pengembangan Aktif 6.18 (`6.18/`)

- [STATUS.md](6.18/STATUS.md) — status fase & subsistem terkini, komposisi 487 modul, verifier 8 gerbang, dan perintah cepat 6.18.
- [TRACKER.md](6.18/TRACKER.md) — temuan log, prioritas perbaikan (P0–P3), known limitation, dan checklist verifikasi pasca-fix.
- [API-AUDIT.md](6.18/API-AUDIT.md) — audit perubahan semantik API Linux 6.13–6.18 dan hasil pemindaian KCFI tracepoint.
- [COMMIT-AUDIT.md](6.18/COMMIT-AUDIT.md) — audit statis commit awal 6.12 & bringup 6.18 pada kedua repo modul OOT (daftar P0–P3 dan rencana perbaikan forward-fix).
- [PMX110-REFERENCE.md](6.18/PMX110-REFERENCE.md) — referensi biner modul `.ko` dari dump OPPO PMX110 (MediaTek 6.18).

## Arsip Historis (`archive/`, read-only)

### Porting 6.12 (`archive/6.12/`)
- [HANDOFF-HISTORY.md](archive/6.12/HANDOFF-HISTORY.md) — riwayat rilis `v1`–`v19-kmi6`, audit gap 20 modul, detail 4 modul fitur, Storage/UFS Opsi A, dan catatan teknis awal.
- [REPACK-HISTORY.md](archive/6.12/REPACK-HISTORY.md) — arsip percobaan repack manual awal (`cfig`/zstd) dan ringkasan histori DLKM `v1`–`v19-kmi6`.
- [PLAN.md](archive/6.12/PLAN.md) — arsip rencana porting awal 6.12 dan catatan kalibrasi kamera/fuel gauge/AW22XXX.
- [PRETEST.md](archive/6.12/PRETEST.md) — log kronologis analisis statis, RE biner, dan investigasi boot 6.12.

### Bringup Awal 6.18 (`archive/6.18/`)
- [PLAN-INITIAL.md](archive/6.18/PLAN-INITIAL.md) — arsip rencana awal migrasi X6871 ke `android17-6.18-2026-09_r13` (Fase 0–5).
- [BRINGUP-LOG.md](archive/6.18/BRINGUP-LOG.md) — kronologi eksekusi Fase 0–2, uji boot `test1`–`test13`, serta analisa MIUMPU/APU IOMMU dan regresi audio DPCM yang sudah ditutup.
