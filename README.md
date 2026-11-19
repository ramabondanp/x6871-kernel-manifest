# Manifest W1VO36.88-36-7

Workspace kernel Motorola W1VO36.88-36-7 (Android 16 / kernel 6.12.38 /
MediaTek mt6895), dibangun dengan Bazel+Kleaf.

## Quickstart

```bash
git clone https://github.com/ramabondanp/w1vo36-kernel-manifest
cd w1vo36-kernel-manifest

# 1. Buat branch kernel_device_modules yang sudah dibersihkan dari kode Moto
./reproduce-cleanup.sh ~/kernel-kernel_device_modules-6.12

# 2. Sync workspace AOSP + overlay
mkdir -p ~/w1vo && cd ~/w1vo
repo init -u https://android.googlesource.com/kernel/manifest \
          -b common-android16-6.12-2025-09
cp ~/w1vo36-kernel-manifest/local_manifest.xml .repo/local_manifests/w1vo.xml
repo sync -j16

# 3. Pasang branch hasil cleanup
cd kernel_device_modules-6.12
git remote add local ~/kernel-kernel_device_modules-6.12
git fetch local mtk-base-latest
git checkout -B mtk-base-latest FETCH_HEAD
cd ..

# 4. Siapkan workspace, lalu build
~/w1vo36-kernel-manifest/setup.sh
~/w1vo36-kernel-manifest/build.sh user
```

Hasil: `1.401 .ko` di
`out_bazel/*/execroot/_main/bazel-out/k8-fastbuild/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/`.

Soc lain: `PLATFORM=mt6991 ./build.sh user` (default `mt6895`).

### Branch port (sudah termasuk semua driver X6871)

`mtk-base-latest` di langkah 3 hanya MTK murni. Semua pekerjaan port
(Iris, panel rm69220, `tran_ldo`, fondasi charger Transsion) ada di branch
terpisah, ter-push ke remote `local`:

```bash
cd kernel_device_modules-6.12
git remote add alps https://github.com/ramabondanp/alps-kernel_device_modules-6.12
git fetch alps w1vo36-6.12-port
git checkout -B w1vo36-6.12-port FETCH_HEAD

cd ..
~/w1vo36-kernel-manifest/setup.sh
~/w1vo36-kernel-manifest/build.sh user   # 1.422 .ko
```

Branch: <https://github.com/ramabondanp/alps-kernel_device_modules-6.12/tree/w1vo36-6.12-port>

Branch ini dibuat baru (bukan di atas `android16`) supaya riwayat `android16`
tidak tersentuh. `android16` (`30a0466a`) memang ancestor dari baseline
w1vo36.88-36-7 (`06079c2`), jadi branch ini juga fast-forward-able ke sana.

Branch itu 6 commit di atas `06079c2` (baseline w1vo36.88-36-7), satu commit
per fitur:

| commit | isi |
|---|---|
| `33d0005` | `tran_audio_control`, `splitswitch-gpio`, `hiber` |
| `2b880e6` | Iris (34 file, Pixelworks) |
| `cfb098c` | `tran_ldo` (ET5904) |
| `381f45e` | panel rm69220 X6871 |
| `fdc1174` | `tc_common_class` (fondasi `tran_device`) |
| `618a8c5` | `tc_charger_class`/`adapter`/`algorithm`/`misc_intf` |

Catatan: remote `local` menolak push ke `mtk-base-latest` karena branch itu
sedang checked-out di working tree-nya (`receive.denyCurrentBranch`), jadi
hasil port di-push ke branch `w1vo36-6.12-port`.


## File

| File | Isi |
|---|---|
| `local_manifest.xml` | 13 project w1vo + donor OPPO, overlay ke manifest AOSP |
| `reproduce-cleanup.sh` | buat branch `mtk-base-latest` (MTK murni + 12 patch) |
| `setup.sh` | MODULE.bazel, symlink donor + `../vendor/mediatek`, trim label |
| `build.sh` | build module (`./build.sh user`) |
| `add-transsion.sh` | tambah 3 modul Transsion mandiri dari donor mt6897 |
| `add-iris.sh` | pasang Pixelworks Iris ke `mediatek_drm_v1` + patch 6.12 |
| `add-panel-rm69220.sh` | panel X6871: init table + timing hasil ekstrak firmware |
| `add-tran-ldo.sh` | regulator `tran_ldo` (ET5904) — sumber `TRANLDO26` untuk panel |
| `add-tc-common-class.sh` | fondasi `tran_device` API — dipakai 19 modul firmware |
| `add-tc-charger-stack.sh` | fondasi charger Transsion: `tc_charger_class` + `tc_adapter_class` + `tc_algorithm_class` + `tc_misc_intf` |
| `patch-tc-misc-6.12.sh` | 8 fungsi `tc_misc_intf` tambahan 6.12, rekonstruksi dari `.ko` |
| `audit-sources.sh` | cocokkan modul firmware -> file source **tanpa** peduli nama file |
| `PLAN.md` | rencana port driver device lain (X6871) — Tingkat A sudah selesai |

## Kenapa ada `reproduce-cleanup.sh`

Repo Motorola `kernel-kernel_device_modules-6.12` berisi 321 commit kode
device (bogota/taipei/moto) di atas base MTK. Script ini checkout base MTK
murni lalu cherry-pick 12 patch MTK yang diperlukan.

Hasil terverifikasi identik dengan branch referensi:

```
tree mtk-base-latest : fab94f37a9ee8a1d43828bdda55bc669e3138de6
```

## Kenapa ada donor OPPO

20 grup module tidak dipublikasikan Motorola. 13 di antaranya ada di donor
OPPO mt6896 dan di-symlink oleh `setup.sh`. Sisanya (49 label) dihapus dari
`mgk_64.bzl` oleh `setup.sh`:

```
afs_core_cus/int  cpufreq_cus/int  fpsgo_cus/int  game_cus/int
gpio_sap_ctrl     met_drv_secure_v3  msync2_frd_cus/int  mtk_input
perf_common_cus/int  sched_int  task_turbo_cus/int
thinmd_exception  wwan
```

Module donor **ikut ter-build** dan masuk output (afs_common_utils, hbt_*,
met_drv_v3, sched_cus, connectivity/*). Campuran Moto+OPPO ini belum diuji
runtime.

## Tiga flag yang wajib

Kalau salah satu hilang, build gagal:

| Flag | Tanpa ini |
|---|---|
| `--user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers` | `fatal error: '<header>' file not found` di puluhan module |
| `--repo_env=SUPPORT_PLATFORM=<soc>` | semua 14 platform ikut dibangun, gagal di module platform lain |
| `--repo_env=KERNEL_VERSION=...` | `key "KERNEL_VERSION" not found` |

`--allow_ddk_unsafe_headers` saja tidak cukup — itu hanya mengaktifkan daftar
bawaan AOSP yang tidak memuat header MTK.

## Batasan

- `user_customer_abi` **tidak bisa lulus** di tree ini: `stg merge` gagal
  karena 328 simbol duplikat antar varian driver yang memang dibangun
  bersamaan (fpsgo v3+v8, mediatek_v2+v1, tee gud 510/600/610/700,
  bt mt66xx+linux_v2). Ini artefak build multi-varian, bukan mismatch KMI.
  Build referensi MTK/Samsung juga tidak menjalankan target ABI.
- Detail status dan jebakan: lihat `HANDOFF.md`.
