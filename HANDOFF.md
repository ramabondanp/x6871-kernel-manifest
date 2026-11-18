# HANDOFF — W1VO36.88-36-7 kernel build

Tanggal: 2026-11-18
Server lama: temp (lambat). Build dihentikan di `[8,265 / 9,183]`, 0 error.

---

## 1. Ringkasan

Yang sudah selesai:

1. `kernel_device_modules-6.12` dibersihkan dari kode device Motorola.
   - `mtk-base` (tree MTK murni) dan `mtk-base-latest` (MTK + 12 patch).
2. GKI tag ditemukan: **android16-6.12-2025-09_r32**
   (full MTK kernel = repo `kernel-mtk`, Linux 6.12.38, KMI gen 5).
3. Manifest `repo` dibuat (13 project) + donor OPPO untuk module yang miss.
4. Workspace hasil overlay AOSP 2025-09 berhasil di-sync (41 GB).
5. Bazel berhasil query semua target (1.893 target) dan **build berjalan
   sampai compile kernel, tanpa error**, lalu dihentikan karena server lambat.

Belum selesai:

- Build module sampai selesai (`modules_install.user`).
- Verifikasi ABI (`mgk_64_k612.user_customer_abi`).

---

## 2. Repo & branch

Private manifest repo (sudah di-push):

    https://github.com/ramabondanp/w1vo36-kernel-manifest

Isi: `default.xml`, `local_manifest.xml`, `post-sync.sh`, `trim-missing.sh`,
`build-w1vo.sh`, `verify-abi.sh`, `reproduce-cleanup.sh`, `docs/HANDOFF.md`.

Repo yang dipakai (semua branch `android-16-release-w1vo36.88-36-7` kecuali donor):

| Repo | Path di workspace | Peran |
|---|---|---|
| kernel-mtk | kernel-6.12 | full MTK ACK 6.12.38 + GKI 2025-09_r32 |
| kernel-kernel_device_modules-6.12 | kernel_device_modules-6.12 | device modules (hasil cleanup) |
| kernel-build-kernel | build/kernel | Kleaf |
| kernel-build-bazel_mgk_rules | build/bazel_mgk_rules | MGK rules |
| kernel_platform-build-bazel_common_rules | build/bazel_common_rules | `dist.bzl` untuk mgk.bzl |
| motorola-kernel-modules | motorola/kernel/modules | module Moto out-of-tree |
| vendor-mediatek-kernel_modules-gpu | vendor/.../gpu | GPU |
| vendor-mediatek-kernel_modules-mtkcam | vendor/.../mtkcam | Camera |
| vendor-mediatek-kernel_modules-connectivity-conninfra | vendor/.../conninfra | Conninfra |
| vendor-mediatek-kernel_modules-connectivity-bt-linux_v2 | vendor/.../bt/linux_v2 | BT |
| vendor-mediatek-kernel_modules-connectivity-bt-mt66xx | vendor/.../bt/mt66xx | BT |
| vendor-mediatek-kernel_modules-connectivity-wlan-core-gen4m | vendor/.../wlan/core/gen4m | WLAN |
| oppo-source/android_kernel_modules_oppo_mt6896 (donor) | donor/oppo-mt6896 | pengisi module miss |

---

## 3. Cleanup kernel_device_modules

Base MTK: `30a0466a2be7` — `[ALPS10637729] slbc: fix info leak` (2025-11-17).

333 commit setelah base, 321 Moto dihapus, 12 dipertahankan:

```
fb615de2bb88  drm: dsi: Support dynamic fps by sending CMD in VFP
91ce1f5c9dfd  [Patch] Update TEE version to 700a-v008
9051d6953575  [ALPS10686914] mrdump: fix spinlock deadlock in die()
79250785b80c  [ALPS10704707] mrdump: Support "big" kernel symbols
64ae591edd11  mfd: mt6375: limit io size
3022b2737530  tcpc: update tcpc driver to v2.0.32_MTK
25d069c09d80  [ALPS10739195] dpmaif: TPUT IPv4 hotspot
eafd39c4b64c  [ALPS11054976] thermal: add lvts init flow
17ef8004643f  [ALPS10657582] DISP: fix RPO two scaling layers
803db3b99f8a  TF-A: remap debug buffer as read-only
c188c78edaba  Disable MTK_DRM_OPT_IDLEMGR_BY_REPAINT
4000205a644b  ack_headers.bzl untuk GKI 2025-06_r1 (path module/nvhe)
```

Verifikasi tree hasil:

```
file bogota/taipei/moto : 0
diff vs HEAD asli        : 368 file, 113.728 deletion
ack_headers vs ACK 2025-09: 4.184 / 4.185 path ada
                          (1 stale: drivers/thermal/thermal.h)
```

**PENTING:** branch `mtk-base` dan `mtk-base-latest` hanya ada di server lama
(tidak di-push, 2,5 GB). Di server baru jalankan:

```bash
./reproduce-cleanup.sh            # clone + 12 cherry-pick + resolve tcpc
```

Script itu menghasilkan tree yang sama (sudah diverifikasi urutan dan
resolusi konfliknya).

---

## 4. GKI tag

Manifest AOSP: branch `common-android16-6.12-2025-09`.

Bukti dari `kernel-mtk` (commit `2c4fd33ae6`, 2026-04-13):

```
"Merge source code with GKI android16-6.12-2025-09_r32 for Bogota/Taipei"
"Merge source code with GKI from android16-6.12-2025-09_r15 to ..._r32"
```

Perbandingan tree `kernel-mtk` vs ACK `android16-6.12-2025-09_r32`:

```
file hanya di ACK        : 0
file hanya di kernel-mtk : 0
file isi berbeda         : 22
```

`build.config.constants` kernel-mtk:

```
BRANCH=android16-6.12
KMI_GENERATION=5
```

KMI gen 5 dipakai dari tag 2025-06 s/d 2025-09 (gen 6 mulai 2025-12).

---

## 5. Workspace yang sudah terbentuk (server lama)

```
/tmp/opencode/w1vo/                 41 GB
  build/kernel/                     Kleaf w1vo
  build/bazel_mgk_rules/            MGK w1vo
  build/bazel_common_rules/         dist.bzl
  kernel-6.12/                      kernel-mtk 6.12.38
  kernel_device_modules-6.12/       mtk-base-latest (903e942c) + trim
  motorola/kernel/modules/
  vendor/mediatek/kernel_modules/   w1vo + symlink donor
  donor/oppo-mt6896/
  prebuilts/...
  tools/bazel
  out_bazel/                        build output (~1 GB saat stop)

/tmp/opencode/vendor/mediatek -> /tmp/opencode/w1vo/vendor/mediatek
```

Catatan: `kernel_device_modules-6.12` di workspace sudah diganti ke branch
`mtk-base-latest` dari clone lokal, dan sudah dijalankan `trim-missing.sh`
(49 baris dihapus dari `mgk_64.bzl`).

---

## 6. Cara lanjut di server baru

```bash
git clone https://github.com/ramabondanp/w1vo36-kernel-manifest
cd w1vo36-kernel-manifest
./reproduce-cleanup.sh ~/kernel-kernel_device_modules-6.12

mkdir ~/w1vo && cd ~/w1vo
repo init -u https://android.googlesource.com/kernel/manifest \
          -b common-android16-6.12-2025-09
cp ~/w1vo36-kernel-manifest/local_manifest.xml .repo/local_manifests/w1vo.xml
repo sync -j16

# ganti device modules dengan hasil cleanup
cd kernel_device_modules-6.12
git remote add local ~/kernel-kernel_device_modules-6.12
git fetch local mtk-base-latest
git checkout -B mtk-base-latest FETCH_HEAD
cd ..

../w1vo36-kernel-manifest/post-sync.sh
../w1vo36-kernel-manifest/trim-missing.sh

cp ../w1vo36-kernel-manifest/build-w1vo.sh ../w1vo36-kernel-manifest/verify-abi.sh .
./build-w1vo.sh user
./verify-abi.sh user
```

`post-sync.sh` melakukan:

1. `MODULE.bazel` <- `build/bazel_mgk_rules/bzlmod/mgk.MODULE.bazel`
2. symlink `common-6.12 -> kernel-6.12`
3. 13 symlink module donor OPPO
4. symlink `../vendor/mediatek -> $PWD/vendor/mediatek`

---

## 7. Jebakan yang sudah ditemukan (jangan diulang)

| Gejala | Penyebab | Fix |
|---|---|---|
| `duplicate default in manifest` | `<default>` kedua di local manifest | tulis `remote`/`revision` per project |
| `use_repo(kernel_toolchain_info) already used` | root `MODULE.bazel` AOSP + include MGK | pakai `mgk.MODULE.bazel` utuh |
| `//build/bazel_common_rules/dist:dist.bzl` tidak ada | tidak ada di manifest AOSP | tambah `kernel_platform-build-bazel_common_rules` |
| `key "KERNEL_VERSION" not found` | `export` tidak sampai ke module extension | `--repo_env=KERNEL_VERSION=...` |
| `--repo_env` unknown startup option | posisi arg salah | taruh setelah subcommand (`query`/`build`) |
| `/tmp/opencode/vendor/mediatek does not exist` | `mgk_repo.MODULE.bazel` pakai `path="../vendor/mediatek"` | symlink satu level di atas workspace |
| `--kernel_version` tidak konsisten | build setting vs env | kirim keduanya: `--//build/bazel_mgk_rules:kernel_version=6.12` dan `--repo_env=KERNEL_VERSION=kernel-6.12` |

---

## 8. Build & ABI

Target module (customer, karena `vendor/mediatek/tests/kernel` tidak ada):

```
//kernel_device_modules-6.12:mgk_64_k612_customer_modules_install.user
```

Kalau `vendor/mediatek/tests/kernel` ada, ganti ke `internal`.

Status terakhir: `[8,265 / 9,183] Building kernel (trim)
//kernel_device_modules-6.12:mgk_64_k612_kernel_aarch64.user`, 0 ERROR.

Setelah selesai, verifikasi ABI:

```
//kernel_device_modules-6.12:mgk_64_k612.user_customer_abi
```

Target itu pakai:

```starlark
abi_definition_stg = "//kernel-6.12:gki/aarch64/abi.stg"
kmi_enforced = True
kmi_symbol_list_add_only = True
```

Jadi mismatch KMI = build gagal, bukan warning.

Dist (kalau perlu artifacts):

```bash
tools/bazel --output_user_root=$PWD/out_bazel run \
  --repo_env=KERNEL_VERSION=kernel-6.12 \
  --repo_env=KERNEL_BUILD_VARIANT=user \
  --//build/bazel_mgk_rules:kernel_version=6.12 \
  --nokmi_symbol_list_violations_check \
  //kernel_device_modules-6.12:mgk_64_k612_customer_dist.user \
  -- --dist_dir=$PWD/out_krn/dist
```

---

## 9. Kekurangan yang masih ada

20 grup module tidak dipublikasikan Motorola dan tidak ada di donor OPPO.
Sudah dihapus dari `mgk_64.bzl` oleh `trim-missing.sh` (49 baris):

```
afs_core_cus / afs_core_int
cpufreq_cus / cpufreq_int
fpsgo_cus / fpsgo_int
game_cus / game_int
gpio_sap_ctrl
met_drv_secure_v3
msync2_frd_cus / msync2_frd_int
mtk_input
perf_common_cus / perf_common_int
sched_int
task_turbo_cus / task_turbo_int
thinmd_exception
wwan
```

Kalau butuh module itu, cari donor lain (mis. branch
`android-16-release-w1ve36h.10-12r3` di repo Moto yang sama) atau ambil dari
BSP MTK.

Catatan kompatibilitas: 6 module w1vo (gpu, mtkcam, conninfra, bt/linux_v2,
bt/mt66xx, wlan/core/gen4m) dicampur dengan module donor mt6896. Belum diuji
runtime, hanya build.

---

## 10. File di server lama (kalau masih hidup)

```
/tmp/opencode/kernel-kernel_device_modules-6.12   clone + mtk-base + mtk-base-latest
/tmp/opencode/w1vo                                workspace 41 GB
/tmp/opencode/w1vo36-kernel-manifest              manifest repo (sudah push)
/tmp/opencode/MOTO-REMOVAL-REPORT.md              daftar 321 commit dihapus
/tmp/opencode/MOTO-W1VO-REPOS.md                  scan 312 repo Moto
/tmp/opencode/BUILD-NOTES.md                      catatan build
```
