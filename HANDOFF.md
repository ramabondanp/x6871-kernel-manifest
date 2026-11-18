# HANDOFF — W1VO36.88-36-7 kernel build

Status per 2026-11-18: **`modules_install.user` berhasil**, 1.401 `.ko`,
0 error. Target ABI tidak bisa lulus (lihat bawah).

## Hasil build

```
target   : //kernel_device_modules-6.12:mgk_64_k612_customer_modules_install.user
platform : mt6895        variant: user
result   : Build completed successfully, 2011 actions, 800s
output   : 1.401 file .ko
```

Perintahnya ada di `build.sh`. Tiga flag yang wajib:

```bash
--allow_ddk_unsafe_headers=1
--user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers
--repo_env=SUPPORT_PLATFORM=mt6895
```

`mtk_use_gki_unsafe_headers` (di `kernel_device_modules-6.12/BUILD.bazel`,
isi 4.187 header dari `ack_headers.bzl`) adalah kunci yang lama hilang. Tanpa
itu puluhan module gagal `fatal error: file not found` karena sandbox DDK
hanya berisi header yang dideklarasikan.

## Target ABI: gagal, bukan karena KMI

`mgk_64_k612.user_customer_abi` gagal di `stg merge`, sebelum sempat
membandingkan simbol dengan `gki/aarch64/abi.stg`:

```
346x warning: duplicate symbol during merge: <nama>
merge failed
```

328 simbol bentrok karena beberapa varian driver dibangun bersamaan:

| Simbol | Bentrok antara |
|---|---|
| `eara2fbt_*`, `fpsgo_*` | `performance/fpsgo_v3` + `fpsgo_v8` |
| `DAL_SetColor`, `disp_*` | `drm/mediatek/mediatek_v2` + `mediatek_v2/v1` |
| `display_enter_tui` | `tee/gud/{510,600,610,700}/TlcTui` |
| `btmtk_set_country_code_from_wifi` | `bt/mt66xx` + `bt/linux_v2` |

Untuk lulus, `mgk_64.bzl` harus dipersempit ke satu varian per driver.
Build referensi MTK/Samsung tidak menjalankan target ini sama sekali —
`build_kernel.sh` mereka hanya `modules_install` + `_dist`.

## Jebakan yang sudah ditemukan

| Gejala | Penyebab | Fix |
|---|---|---|
| `fatal error: '<header>' file not found` (puluhan module) | sandbox DDK hanya berisi header yang dideklarasikan; header privat kernel tidak ikut | `--user_ddk_unsafe_headers=...:mtk_use_gki_unsafe_headers` |
| `--allow_ddk_unsafe_headers` tidak menolong | daftar unsafe bawaan AOSP tidak memuat header MTK | pakai target MTK di atas |
| build sangat lambat / gagal di module platform lain | `SUPPORT_PLATFORM` kosong -> 14 platform ikut dibangun | `--repo_env=SUPPORT_PLATFORM=mt6895` |
| `fatal error: '../virt-dma.h'` | commit Moto `917d6d689d69` hapus 73.548 file "identik ACK" | ikut tertutup flag di atas |
| `duplicate default in manifest` | `<default>` kedua di local manifest | tulis `remote`/`revision` per project |
| `use_repo(kernel_toolchain_info) already used` | root `MODULE.bazel` AOSP + MGK | pakai `mgk.MODULE.bazel` utuh |
| `//build/bazel_common_rules/dist:dist.bzl` tidak ada | tidak ada di manifest AOSP | tambah repo `kernel_platform-build-bazel_common_rules` |
| `key "KERNEL_VERSION" not found` | `export` tidak sampai ke module extension | `--repo_env=KERNEL_VERSION=...` |
| `.../vendor/mediatek does not exist` | `mgk_repo.MODULE.bazel` pakai `path="../vendor/mediatek"` | symlink satu level di atas workspace |
| `repo sync` gagal `Missing Cookiefile` | build `repo` di server ini wajib `http.cookiefile` | `git config --global http.cookiefile <file-kosong-format-Netscape>` |
| `reproduce-cleanup.sh` berhenti "konflik tak terduga" | server bersih tanpa `user.name`/`user.email`; git lapor `Committer identity unknown` | script sekarang set identitas lokal otomatis |

## Catatan server

- Build ini multi-tenant: load average sering >400 di 96 core. Build 2011
  action butuh ~13 menit; ABI target (~7.386 action) ~13 menit juga.
- Jangan taruh `TMPDIR` di `/tmp` kalau server melarang. Bazel sendiri pakai
  `<workspace>/out_bazel/.../javatmp`, tapi `mktemp`/`git`/`make` ikut TMPDIR.
- Butuh ~60 GB disk untuk workspace + output.

## Yang belum diuji

- Runtime: campuran module Moto + donor OPPO belum pernah di-boot.
- `mt6991` / `mt6993` (platform lain) belum dibangun; hanya `mgk_64.bzl` yang
  menyebutnya.
- 49 label module yang dihapus `setup.sh` (lihat README) — kalau nanti perlu,
  cari donor lain.
