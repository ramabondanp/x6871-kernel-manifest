# Status Eksekusi PLAN-6.18

Diperbarui: 2026-11-23 (UTC)

> Dokumen ini melacak eksekusi [`PLAN-6.18.md`](PLAN-6.18.md). Baseline
> produksi 6.12 (`gki-kmi6-20261122`) tidak berubah.

## Ringkasan

| Fase | Status | Catatan |
|---|---|---|
| 0 — Manifest, branch, workspace | **Selesai** | Workspace `<workspace-6.18>` |
| 1 — Kleaf/MGK + device tree 6.18 | **Berjalan** | Kernel 6.18.32 target `mgk_64_k618` |
| 2 — Codemod API 6.13–6.18 | **Sebagian** | 8 kelas diterapkan (lihat bawah) |
| 3 — Milestone `vendor_boot` | Belum | Menunggu kompilasi 6.18 |
| Gerbang boot #1 | Belum | Butuh TWRP + early-init |
| 4 — DLKM berat | Belum | Sched, Mali, WLAN, cam/vcodec/audio |
| 5 — Repack + verifier 8 gerbang | Belum | `verify-kmi-abi.py --kver 6.18` |

## Referensi donor 6.18

Dump OPPO PMX110 (MediaTek 6.18) sudah dianalisis; lihat
[`PMX110-6.18-REFERENCE.md`](PMX110-6.18-REFERENCE.md). Bukti utamanya:
`clk-common.ko` OOT mengekspor `mtk_alloc_clk_data`/`mtk_clk_register_plls`,
dan modul 6.18 memakai `hrtimer_setup`, `timer_delete`,
`wakeup_source_register`, `devm_power_supply_get_by_reference`,
`alloc_netdev_dummy`, `netif_napi_add_weight_locked`, `crypto_shash_finup`,
serta `for_each_kernel_tracepoint`.

## Fase 0 — selesai

- `local_manifest-6.18.xml`:
  - GKI tetap di path bawaan `common`, dipin ke tag
    `android17-6.18-2026-09_r13` (commit `ecdaacc9`, Linux `6.18.32`,
    KMI 5, 4 KB).
  - `kernel/build` memakai AOSP `main-kernel-2026`.
  - `build/bazel_mgk_rules` + `build/bazel_common_rules` dari Motorola.
  - Device modules di `kernel_device_modules-6.18`; vendor modules di
    `vendor/mediatek/kernel_modules`.
  - Repo berat non-DDK dibuang dari sync.
- Branch `x6871-android17-6.18` dibuat dari ujung
  `x6871-android16-6.12` pada kedua repo port.
- Workspace terisolasi: `<workspace-6.18>`
  (`../vendor/mediatek` milik workspace ini, bukan workspace 6.12).
- Script mendukung `KVER=6.18`: `build.sh`, `setup.sh`,
  `tools/repack-vendor-boot-latest.sh`, `tools/repack-dlkm-latest.sh`,
  `tools/verify-kmi-abi.py --kver 6.18`.

## Fase 1 — berjalan

- `patches/bazel_mgk_rules-6.18.patch`:
  - target `mgk_64_k618`, path GKI `common`, device tree
    `kernel_device_modules-6.18`;
  - toolchain dari `main-kernel-2026` (`kernel_toolchain_ext`,
    `rules_rust`, `rules_devicetree`, `package_metadata`, `zstd`);
  - `mgk_build_config` tidak lagi meng-source
    `build.config.{common,aarch64,gki}` yang sudah menjadi trap di
    `main-kernel-2026`;
  - `KERNEL_DIR` dihapus dari build config dan diganti
    `kernel_build(makefile = "//common:Makefile")` sesuai
    `docs/build_configs.md`;
  - defconfig/fragmen diserahkan ke `kernel_build`;
  - `Image.lzma`/`Image.zst` ditambahkan ke `make_goals`.
- Device tree:
  - `BUILD.bazel`, `fake_manifest.xml`, `mgk_64.bzl`, `mgk_modules.bzl`
    memakai `//common` dan `kernel_device_modules-6.18`.
  - `mgk_64_k618_defconfig` (salinan 6.12, belum dipangkas).
  - `kernel/kleaf/gki_modules_6.18.bzl`: 83 modul GKI + 22 KUnit
    (daftar statis karena `get_gki_modules_list()` 6.18 mengembalikan
    `select()`).
  - `ack_headers.bzl`: 134 header yang tidak ada di 6.18 dibuang
    (4.051 entri tersisa).
  - 3 blok `choice` Kconfig diubah dari `bool`/`tristate` ke `prompt`
    agar diterima parser 6.18.
  - `x6871_modules.bzl`: 412 target OOT (tanpa `mkp.ko`).
- `X6871.config`:
  - ditambah disable 192 driver platform MTK **in-tree**
    (`COMMON_CLK_MT*`, `PINCTRL_MT*`, `COMMON_CLK_MEDIATEK`) karena
    X6871 memakai modul OOT (`clk-common.ko`, `clk-mt6895*.ko`,
    `pinctrl-*`). Ini hanya berlaku pada build modul perangkat, bukan
    GKI base, sehingga ABI/KMI tetap murni.
- Fragmen config:
  - `kernel_build_config` `x6871_fragments_{user,eng,userdebug}`
    menggabungkan **gki_defconfig + device defconfig + overlay +
    `sign.config`** (+ varian) menjadi satu defconfig penuh.
  - `kernel_build.defconfig` diarahkan ke file itu untuk build device;
    `check_defconfig = "disabled"`.
  - Alasan: `merge_config.sh` melewati simbol yang tidak ada di base
    defconfig. `CONFIG_COMMON_CLK_MT8196` baru muncul sebagai default
    `ARCH_MEDIATEK`, jadi harus ada di defconfig penuh agar disable
    `# CONFIG_... is not set` dihormati.
  - Bug yang ditemukan: disable sempat ditulis tanpa prefix `CONFIG_`
    (`# COMMON_CLK_MT8196 is not set`) sehingga diabaikan parser;
    sudah diperbaiki menjadi `# CONFIG_COMMON_CLK_MT8196 is not set`.
- `X6871.config` juga menonaktifkan dua modul in-tree yang duplikat
  dengan OOT: `CONFIG_MTK_DVFSRC` dan `CONFIG_REGULATOR_RT5133`.
- Build target:
  `//kernel_device_modules-6.18:mgk_64_k618_customer_modules_install.user`
  sedang dijalankan di `out_bazel_test`.
- Error yang sudah dilewati: repo sync tidak lengkap
  (`prebuilts/kernel-build-tools`), `gbl` override, `py_binary` Bazel 8,
  glob kosong, trap `build.config`, `DEFCONFIG` deprecated, dan
  modpost `clk-mt8196-*`.

## Fase 2 — codemod diterapkan

Commit di branch `x6871-android17-6.18` (device + vendor):

1. `MODULE_IMPORT_NS("...")` — 107 file device, 86 file vendor.
2. `del_timer[_sync]` → `timer_delete[_sync]` — 114 + 128 file.
3. `from_timer` → `timer_container_of` — 30 + 35 file.
4. `hrtimer_init` + `.function` → `hrtimer_setup` — 57 + 1 file.
5. Hapus `.llseek = no_llseek` — 54 file.
6. `*_get_by_phandle` → `*_get_by_reference` — 28 file;
   dua call site non-devm memakai `of_fwnode_handle()`.
7. DAPM `snd_soc_dapm_*` — 6 file.
8. `wakeup_source_register/unregister` — DRM, WLAN, charger, rawbulk.

Referensi OPPO PMX110 mengonfirmasi kelas-kelas ini dan menambah
`init_dummy_netdev`/`alloc_netdev_dummy`, `netif_napi_add_weight_locked`,
`crypto_shash_finup`, `for_each_kernel_tracepoint`,
`iommu_get_domain_for_dev`, dan Mali `__folio_lock`.

## Rencana codemod (arsip)

Skrip: `scripts/port-6.18-mechanical.py` (dry-run default; `--apply`,
`--all`, `--only <kelas>`). Satu commit per kategori:

| # | Kelas | Hit (device+vendor) | Transformasi |
|---|---|---:|---|
| 1 | `module_import_ns` | 196 | `MODULE_IMPORT_NS(NS)` → `MODULE_IMPORT_NS("NS")` |
| 2 | `timer_delete` | 438 | `del_timer[_sync]` → `timer_delete[_sync]` |
| 3 | `timer_container_of` | 75 | `from_timer` → `timer_container_of` |
| 4 | `hrtimer_setup` | 68 | `hrtimer_init` + `.function` → `hrtimer_setup` |
| 5 | `no_llseek` | 54 | hapus `.llseek = no_llseek` |
| 6 | `power_supply_reference` | 43 | `*_get_by_phandle` → `*_get_by_reference` |
| 7 | `dapm_rename` | 41 | `dapm_*` → `snd_soc_dapm_*` |
| 8 | `wakeup_source` | 18 | create/add | remove/destroy → register/unregister |

Transformasi 1–5 aman secara mekanis; 6–8 memerlukan pemeriksaan
argumen/manual setelah kompilasi pertama.

## Perintah kerja

```bash
cd <workspace-6.18>

# build
KVER=6.18 OUT_DIR="$PWD/out_bazel_6.18" \
  $HOME/x6871-kernel-manifest/build.sh user

# codemod (dry-run)
python3 $HOME/x6871-kernel-manifest/scripts/port-6.18-mechanical.py

# verifikasi akhir
cd $HOME/x6871-kernel-manifest
./tools/verify-kmi-abi.py --kver 6.18 \
  --ws <workspace-6.18> \
  --vb-dir ... --vd-dir ... --od-dir ...
```

## Catatan risiko

- `X6871.config` menonaktifkan simbol config yang **namanya dipakai
  bersama** Kconfig in-tree dan OOT. Target OOT yang diperiksa
  (`clk-*`, `pinctrl-*`) tidak memakai `kconfig`/`defconfig`, jadi tetap
  dibangun; tetap wajib diverifikasi lewat 8 gerbang dan uji boot.
- Jangan pernah mencampur image KMI 6 dan KMI 7/6.18.
- `kernel-6.18`/`common` tidak boleh diedit; semua perubahan di device
  modules dan overlay manifest.
