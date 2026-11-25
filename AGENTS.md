# Aturan Kerja X6871 6.18

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
- Jangan mencampur image KMI 6 (6.12) dengan KMI 5/6.18.
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

Clone/unduh langsung:

```bash
mkdir -p donor && cd donor

# Donor OPPO MT6896
git clone --depth 1 --single-branch \
  --branch oppo/mt6896_b_16.0_reno12 \
  https://github.com/oppo-source/android_kernel_modules_oppo_mt6896.git \
  oppo-mt6896

# Donor Transsion/Infinix MT6897
curl -L --retry 3 -o infinix-mt6897.tar.gz \
  https://d1wd32b69guoqm.cloudfront.net/opensource/android15_kernel_modules_and_devicetree_mt6897.tar.gz
mkdir -p infinix-mt6897
tar -xzf infinix-mt6897.tar.gz -C infinix-mt6897

# Firmware stock X6871
git clone --depth 1 --single-branch \
  --branch 'X6871-16.3.0.155SP20(OP008PF001AZ)' \
  https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6871.git \
  stock-x6871
```

Jangan commit file donor, tarball, atau dump firmware ke repo.

## 4. Commit dan checkpatch

- Satu commit untuk satu topik. Jangan menggabungkan beberapa bugfix.
- **Jangan amend commit fix.** Kalau ada perbaikan, buat commit baru.
- Di **manifest**, fix/analisa juga harus menjadi **commit baru**, bukan amend.
- Jangan menambahkan prefix `6.18:` kalau bug yang diperbaiki juga ada di 6.12.
- Jika fix kernel/vendor berlaku untuk kedua kernel (6.18 dan 6.12), terapkan
  dan commit langsung ke kedua branch (`x6871-android17-6.18` dan
  `x6871-android16-6.12`) tanpa akhiran `for 6.18`; tidak perlu build 6.12
  kecuali diminta.
- Untuk commit kernel yang khusus 6.18: tanpa prefix `6.18:`, subjek diakhiri
  `for 6.18`.
- Commit manifest/docs wajib berbahasa **Indonesia** (subjek dan body),
  memakai prefix `6.18:` dan subjek hanya boleh punya satu `6.18`.
- Commit kernel/vendor wajib berbahasa **Inggris** (subjek dan body),
  memakai format kernel, body sekitar 72 kolom, dan
  `Signed-off-by: Rama Bondan Prakoso <ramanarubp@gmail.com>`.
- Sebelum push, jalankan checkpatch untuk commit.
- Untuk kernel/vendor, checkpatch difokuskan ke **commit message**, bukan code
  warning.
- Warning `MAINTAINERS` di-skip. Code warning checkpatch, DOS line endings, dan
  MAINTAINERS di luar scope dokumen plan.

## 5. Dokumentasi dan bukti

- Jangan menulis nama file log lokal (`pstoreX`, `dmesgX`, `logcatX`,
  `twrpX`) atau path lokal di repo (aturan ketat pada seluruh dokumen aktif;
  arsip historis lama di `docs/archive/` bersifat read-only).
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
  - `docs/archive/<versi>/` — arsip historis *read-only* (rencana awal,
    riwayat rilis lama, log bringup yang sudah ditutup).
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

## 6. DTB, DTBO, dan image

- **Hard rule:** semua `dtb` dan `dtbo.img` yang dipakai di vendor berasal
  dari stock.
- Jangan berasumsi ada DTBO kustom.
- DT di tree tidak pernah dipakai untuk membuat image; tree hanya untuk build
  modul.
- Repack harus mempertahankan `dtb`, `bootconfig`, dan recovery ramdisk
  byte-identical dengan stock.
- Node yang disabled di stock tetap disabled.
- Jangan menambah node, thermal zone, GCE event, atau channel CMDQ yang tidak
  ada di stock.
- Fix driver/HAL, bukan DT.

## 7. Branch dan backup

- Default branch repo kernel/vendor: `x6871-android17-6.18`.
- Branch `android16` dihapus hanya dari repo device.
- History lama dipertahankan di branch `backup/*`.
- Repo publik harus bersih dari rujukan log lokal dan dokumentasi 6.18 harus
  akurat.

## 8. Testing dan artefak

- Uji yang belum dilakukan harus dicatat di dokumen.
- Jangan commit log, image, atau artefak uji ke repo.
- Perintah build, repack, flash, dan verifikasi ada di `docs/`:
  - `docs/README.md` — peta/indeks dokumentasi
  - `docs/6.18/STATUS.md` — status eksekusi dan perintah kerja 6.18
  - `docs/6.18/TRACKER.md` — temuan, prioritas fix, dan checklist verifikasi 6.18
  - `docs/guides/BUILD.md` — build, repack, konfigurasi, troubleshooting
  - `docs/guides/FLASH-AND-TEST.md` — flash, rollback, dan checklist uji
  - `docs/guides/SELINUX-6.18.md` — patch SELinux `firmware_load` untuk boot 6.18
  - `docs/hardware/DEVICES.md` — pemetaan hardware

## 9. Checklist agen

- [ ] Build difokuskan ke 6.18; jika fix berlaku untuk kedua kernel, sudah di-commit ke branch 6.18 dan 6.12 tanpa perlu build 6.12.
- [ ] Perubahan hanya pada topik yang diminta.
- [ ] DTB/DTBO stock tidak diubah.
- [ ] Tidak menambah node/zone/event yang tidak ada di stock.
- [ ] Commit baru, bukan amend, untuk fix/analisa.
- [ ] Prefix/akhiran commit sesuai aturan.
- [ ] `Signed-off-by` ada.
- [ ] Checkpatch commit message bersih.
- [ ] Dokumentasi memakai kutipan log, bukan nama file lokal.
- [ ] Struktur `docs/` rapi sesuai aturan, tanpa URL temporer, dan `docs/README.md` terbarui bila file berubah.
- [ ] Testing yang belum dilakukan dicatat.
