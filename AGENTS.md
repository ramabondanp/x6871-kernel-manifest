# Aturan Kerja X6871

Dokumen ini hanya berisi aturan umum untuk agen AI. Detail teknis, temuan,
perintah build/repack, dan status terbaru ada di `docs/`; jangan menduplikasi
detail tersebut di sini.

## Prinsip keputusan

- Utamakan keputusan pragmatis: perubahan harus memberi fungsi nyata atau
  menghilangkan akar masalah.
- Jangan membuat stub, module palsu, atau ioctl palsu hanya untuk
  menyembunyikan log. Kalau stub tidak benar-benar bekerja, skip.
- Kalau cara yang ada tidak menghasilkan apa-apa, cari cara lain yang benar
  atau catat sebagai known limitation.
- Buka kembali item yang di-skip hanya kalau ada source resmi atau regresi
  terukur.

## 1. Scope dan rilis

- Fokus kerja dan build ada di **6.18** (`x6871-android17-6.18`), sementara
  baseline stabil tetap **6.12** (`x6871-android16-6.12`). Jika sebuah fix
  berlaku untuk kedua kernel, commit langsung ke kedua branch
  (`x6871-android17-6.18` dan `x6871-android16-6.12`), tetapi tidak perlu build
  **6.12** kecuali diminta.
- 6.12 dipakai untuk penggunaan harian; 6.18 masih pratinjau dan belum punya
  image rilis publik.
- Jangan mencampur image antar versi kernel maupun antar generasi/set build
  KMI (**6.12 KMI 6**, **6.18 `r13` KMI 5**, dan **6.18-lts KMI 6 build GKI
  lokal**).
- README bersifat user-facing. Info 6.18 ditulis sederhana.

## 2. Sumber kebenaran

- Perilaku stock X6871 mengikuti **DTB/DTBO stock** dan **module `.ko` stock**
  dari dump firmware.
- Source 6.12 di tree adalah hasil port, bukan source stock.
- Source donor hanya referensi porting, bukan acuan perilaku stock.
- Jangan mengarang isi stock dari source tree.

## 3. Donor dan sumber eksternal

| Sumber | Link | Kegunaan |
|---|---|---|
| OPPO MT6896 modules | <https://github.com/oppo-source/android_kernel_modules_oppo_mt6896/tree/oppo/mt6896_b_16.0_reno12> | Donor driver/media 6.12 |
| Infinix MT6897 tarball | <https://d1wd32b69guoqm.cloudfront.net/opensource/android15_kernel_modules_and_devicetree_mt6897.tar.gz> | Donor Transsion 6.1 |
| Infinix Open Source Center | <https://opensource.dev.infinixmobility.com/> | Halaman resmi source Infinix |
| Stock X6871 GitLab | <https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6871> | DTB, DTBO, image, dan `.ko` stock |
| Stock X6871 branch | `X6871-16.3.0.155SP20(OP008PF001AZ)` | Versi referensi stock |
| OPPO PMX110 (MTK 6.18) | <https://gitlab.com/rama-firmware-dumps/oppo/PMX110> | Referensi biner `.ko` 6.18 (lihat `docs/6.18/PMX110-REFERENCE.md`) |

Langkah unduh referensi ada di [`docs/guides/BUILD.md`](docs/guides/BUILD.md#unduhan-referensi).
Jangan commit file donor, tarball, atau dump firmware ke repo.

## 4. Commit, checkpatch, dan push

- Satu commit untuk satu topik. Jangan menggabungkan beberapa bugfix.
- **Jangan amend commit fix.** Kalau ada perbaikan, buat commit baru.
- Di **manifest**, fix/analisa juga harus menjadi **commit baru**, bukan amend.
- **Format commit repo manifest (`x6871-kernel-manifest`):**
  - Wajib berbahasa **Indonesia** (subjek dan body sekitar 72 kolom) serta
    menyertakan `Signed-off-by: Rama Bondan Prakoso <ramanarubp@gmail.com>`.
  - Gunakan prefix `6.18:` **hanya** untuk topik khusus 6.18 (dan subjek
    hanya boleh memiliki satu `6.18`). Untuk topik umum atau lintas 6.12 &
    6.18 (mis. `AGENTS.md`, `tools/`, `BUILD.md`, `DEVICES.md`), pakai prefix
    topik (`docs:`, `tools:`, `manifest:`) tanpa `6.18:`.
- **Format commit repo kernel/vendor (`alps-kernel_device_modules`,
  `alps-vendor_mediatek_kernel_modules`):**
  - Wajib berbahasa **Inggris** (subjek dan body sekitar 72 kolom), memakai
    format commit kernel, dan `Signed-off-by: Rama Bondan Prakoso <ramanarubp@gmail.com>`.
  - **Jangan** menambahkan prefix `6.18:`. Untuk commit yang khusus 6.18,
    akhiri subjek dengan `for 6.18`.
  - Jika fix berlaku untuk kedua kernel (6.18 dan 6.12), terapkan dan commit
    langsung ke kedua branch (`x6871-android17-6.18` dan
    `x6871-android16-6.12`) tanpa akhiran `for 6.18`; tidak perlu build 6.12
    kecuali diminta.
- **Checkpatch:**
  - Sebelum push, jalankan `checkpatch` untuk setiap commit, difokuskan pada
    **commit message**, bukan code warning.
  - Warning `MAINTAINERS`, `FILE_PATH_CHANGES`, code warning checkpatch, DOS
    line endings, dan false positive ejaan kata Indonesia (mis. `modul`) di-skip.
- **Push:**
  - Langsung `git push` setelah commit dan checkpatch bersih untuk tugas
    perubahan yang diminta, kecuali perubahan masih eksperimental/belum
    diverifikasi atau pengguna meminta untuk menahan push.

## 5. Dokumentasi dan bukti

- Jangan menulis nama file log lokal (`pstoreX`, `dmesgX`, `logcatX`,
  `twrpX`) atau path lokal mesin di repo (aturan ketat pada seluruh dokumen
  aktif; arsip historis lama di `docs/archive/` bersifat *read-only* setelah
  ditutup).
- Jangan menyertakan URL unduhan sementara (seperti `gofile.io`) di repo;
  cukup catat nama artefak, MD5/commit, dan kutipan baris log.
- Bukti log harus dikutip sebagai baris log.
- Log mentah dan image uji disimpan lokal, tidak disertakan di repo.
- **Struktur wajib `docs/`:**
  - Hanya `docs/README.md` yang boleh berada di root `docs/`; **jangan**
    menaruh file dokumen baru langsung di root `docs/`.
  - `docs/guides/` — panduan operasional hidup (build, repack, flash,
    SELinux).
  - `docs/hardware/` — pemetaan hardware dan DT/DTBO stock lintas versi.
  - `docs/6.18/` — status (`STATUS.md`), tracker temuan/prioritas
    (`TRACKER.md`), dan referensi teknis aktif 6.18.
  - `docs/archive/<versi>/` — arsip historis *read-only setelah ditutup*
    (rencana awal, riwayat rilis lama, log bringup yang sudah ditutup; tidak
    diaudit/diubah rutin dan hanya ditambah saat mengarsipkan fase baru yang
    sudah selesai).
- **Disiplin penambahan & pembaruan dokumen:**
  - Satu topik = satu file; jangan membuat file catatan ad-hoc campur aduk.
  - Temuan baru, prioritas fix, dan known limitation 6.18 dicatat di
    `docs/6.18/TRACKER.md`; ringkasan status di `docs/6.18/STATUS.md`;
    kronologi bringup yang sudah selesai dipindahkan ke
    `docs/archive/6.18/BRINGUP-LOG.md`.
  - Analisa, hasil build, dan status uji dicatat sebagai commit baru, bukan
    amend.
  - Setiap menambah, memindahkan, atau menghapus dokumen di `docs/`, wajib
    memperbarui `docs/README.md` (serta `README.md` dan `AGENTS.md` bila
    relevan) dan memastikan tidak ada broken link relatif.

## 6. Build, GKI, DTB/DTBO, dan image

- **Jangan pakai `/tmp`** — gunakan `~/tmp` / `$TMPDIR`.
- **Tree GKI (`kernel-6.12` / `common`) tidak boleh diedit** untuk adaptasi
  modul atau KMI (pengecualian sementara hanya patch SHA-gated
  `patches/common-6.18-blk-plug-invalidate-ts.patch` pada profil uji `6.18-lts`
  lewat `setup.sh` hingga upstream fix masuk).
- **Wajib lulus 8/8 `tools/verify-kmi-abi.py`** sebelum uji/rilis; jangan
  memasukkan modul GKI terproteksi (`CONFIG_MODULE_SIG_PROTECT`) ke
  `vendor_boot`, `vendor_dlkm`, atau `odm_dlkm`.
- **Hard rule DTB/DTBO:** semua `dtb` dan `dtbo.img` yang dipakai di vendor
  berasal dari stock. Jangan berasumsi ada DTBO kustom dan jangan mengubah
  `dtbo.img` stock.
- DT di tree tidak pernah dipakai untuk membuat image; tree hanya untuk build
  modul.
- Repack `vendor_boot` harus mempertahankan `dtb` dan `bootconfig`
  byte-identical dengan stock/base packer, serta mempertahankan
  `vendor_ramdisk01` dari base TWRP.
- Node yang disabled di stock tetap disabled.
- Jangan menambah node, thermal zone, GCE event, atau channel CMDQ yang tidak
  ada di stock.
- Fix driver/HAL, bukan DT.

## 7. Branch dan backup

- Repo modul resmi: `alps-kernel_device_modules` dan
  `alps-vendor_mediatek_kernel_modules`.
- Default branch repo kernel/vendor: `x6871-android17-6.18`; baseline stabil:
  `x6871-android16-6.12`.
- History lama dipertahankan di branch `backup/*`.
- Repo publik harus bersih dari rujukan log lokal dan path lokal mesin, dan
  dokumentasi 6.18 harus akurat.

## 8. Testing dan artefak

- Uji yang belum dilakukan harus dicatat di dokumen.
- Jangan commit log, image, atau artefak uji ke repo.
- Perintah build, repack, flash, dan verifikasi ada di `docs/`:
  - `docs/README.md` — peta/indeks dokumentasi
  - `docs/6.18/STATUS.md` — status eksekusi dan perintah kerja 6.18
  - `docs/6.18/TRACKER.md` — temuan, prioritas fix, dan checklist verifikasi 6.18
  - `docs/6.18/API-AUDIT.md` — audit perubahan semantik API 6.13–6.18 & scan KCFI
  - `docs/guides/BUILD.md` — build, repack, konfigurasi, troubleshooting
  - `docs/guides/FLASH-AND-TEST.md` — flash, rollback, dan checklist uji
  - `docs/guides/SELINUX-6.18.md` — patch SELinux `firmware_load` untuk boot 6.18
  - `docs/hardware/DEVICES.md` — pemetaan hardware

## 9. Checklist agen

- [ ] Build difokuskan ke 6.18; jika fix berlaku untuk kedua kernel, sudah di-commit ke branch 6.18 dan 6.12 tanpa perlu build 6.12.
- [ ] Perubahan hanya pada topik yang diminta.
- [ ] GKI (`common`/`kernel-6.12`) tidak diedit (kecuali patch SHA-gated `6.18-lts` via `setup.sh`).
- [ ] DTB/DTBO stock tidak diubah dan tidak menambah node/zone/event di luar stock.
- [ ] Jika melakukan build/repack, `tools/verify-kmi-abi.py` lulus 8/8.
- [ ] Commit baru, bukan amend, untuk fix/analisa.
- [ ] Bahasa, prefix/akhiran commit, dan `Signed-off-by` sesuai aturan.
- [ ] Checkpatch commit message bersih (0 error).
- [ ] Dokumentasi memakai kutipan log, tanpa nama file log lokal, path lokal mesin, maupun URL temporer.
- [ ] Struktur `docs/` rapi sesuai aturan dan `docs/README.md` terbarui bila file berubah.
- [ ] Testing yang belum dilakukan dicatat.
