# PLAN 6.18 — Rencana Upstreaming X6871 (MT6895) ke `android17-6.18-2026-09_r13`

> **Status (2026-11-22): PLAN ONLY — belum dieksekusi.**
> Baseline produksi tetap di `android16-6.12-2026-09_r16` (KMI 6, rilis `gki-kmi6-20261122`, workspace `/serverhive1/ramabondanp/x6871-clean/ws`).

---

## 1. Tujuan

Memigrasikan seluruh **487 modul runtime** Infinix GT 20 Pro (X6871 / MT6895) — `221 vendor_boot` (tanpa `mkp.ko`) + `209 vendor_dlkm` + `57 odm_dlkm` (100% C source, 0 objek `.o`/`.a` prebuilt) — ke GKI AOSP murni **`android17-6.18-2026-09_r13`** **tanpa mengedit satu berkas pun di `kernel-6.18`**, agar kompatibel 100% dengan `boot.img` + `system_dlkm.img` rilis resmi Google.

| Parameter | Baseline Saat Ini (6.12) | Target (6.18) |
|---|---|---|
| Tag GKI AOSP | `android16-6.12-2026-09_r16` | `android17-6.18-2026-09_r13` (`910ab23e44c4`) |
| Versi Linux | `6.12.92` | `6.18.32` |
| KMI Generation | `6` | `5` |
| Page Size | `4KB` (`kernel_aarch64`) | `4KB` (`kernel_aarch64`, bukan `16k`) |
| Clang / Rust | `r536225` / `1.82.0.p2` | `r584948c` / `1.91.1.p3` |
| Manifest AOSP | `common-android16-6.12-2026-09` | `common-android17-6.18-2026-09` |
| Workspace | `/serverhive1/ramabondanp/x6871-clean/ws` (tetap utuh) | `/serverhive1/ramabondanp/x6871-6.18/ws` (terpisah) |

---

## 2. Hasil Assessment Teknis (Terukur)

Audit langsung dilakukan dengan mencocokkan seluruh **488 `.ko` runtime** (`v19-kmi6`: **16** modul in-tree GKI, **432** `kernel_device_modules`, **40** `vendor/mediatek/kernel_modules`) terhadap `gki/aarch64/abi.stg`, `bazel/modules_private.bzl`, `arch/arm64/configs/gki_defconfig`, dan `BUILD.bazel` milik `android17-6.18-2026-09_r13`.

### 2.1 Yang Mendukung Kelayakan (0 Hard Blocker Struktural)

1. **100% Source di Set Runtime**: 0 modul X6871 menautkan `.o`/`.a` prebuilt (`sched_cus` tidak dipakai X6871).
2. **GKI 4KB Resmi Masih Ada**: `kernel_aarch64` (4KB) tetap tersedia terpisah dari `kernel_aarch64_16k`.
3. **KMI MTK & Transsion Resmi Hadir**: `gki/aarch64/symbols/mtk` dan `gki/aarch64/symbols/transsion` ada di 6.18 (`abi.stg`: 9.593 simbol).
4. **Kecocokan Simbol 97,9%**: dari **2.643** simbol GKI unik yang diimpor 488 modul kita, **2.588** sudah ada di `abi.stg` 6.18; hanya **55** yang hilang (sebagian besar sekadar rename/macro/inline di header 6.18).
5. **Vendor Hooks 95/99 Utuh**:
   - **91** hook arity sama; hanya **1** berubah arity (`android_vh_binder_restore_priority`: 3 → 2 param di `task_turbo.ko` & `vip_engine.ko`).
   - **4** hook yang dihapus (`android_rvh_{commit,exit,override,revert}_creds`) **hanya dipakai `mkp.ko`** (0 ekspor, 0 modul lain yang mengimpornya).
6. **`CONFIG_MODULE_SIG_PROTECT` Aman**: kolisi dengan modul GKI 6.18 hanya `zram.ko` dan `zsmalloc.ko` (`odm_dlkm`), dan keduanya tetap masuk `_COMMON_UNPROTECTED_MODULES_LIST`.
7. **Kleaf `main-kernel-2026` Kompatibel Secara Primitif**: `ddk_module`, `ddk_headers`, `kernel_build`, `kernel_module`, `kernel_modules_install`, `build.config.{common,aarch64,gki,constants}`, dan `--user_ddk_unsafe_headers` masih tersedia.
8. **cgroup v2 Sudah Aktif di Stock ROM X6871**: `dmesg10.txt` mengonfirmasi `libprocessgroup` memakai `/sys/fs/cgroup/...` (cgroup v2) walau `CONFIG_MEMCG_V1=y` dihapus di `gki_defconfig` 6.18.

### 2.2 Hambatan Utama (Kenapa Ini Proyek Major)

- **Belum ada donor publik MTK 6.18** (`kernel_device_modules-6.18` / `bazel_mgk_rules` 6.18 di Motorola/OPPO/GitHub). Seluruh adaptasi Kleaf dan API internal Linux **6.12 → 6.18** (6 rilis minor: 6.13–6.18) harus dikerjakan manual.
- **Ruang disk `/serverhive1`**: tersisa ~200 GB (95% terpakai). Sync workspace 6.18 (~50–75 GB termasuk `out_bazel`) wajib memakai `--depth=1` / `-c --no-tags`.

---

## 3. Keputusan Desain

1. **Branch baru, BUKAN repo baru**:
   - `alps-kernel_device_modules-6.12` → branch `x6871-android17-6.18` (di-checkout ke path `kernel_device_modules-6.18`)
   - `alps-vendor_mediatek_kernel_modules` → branch `x6871-android17-6.18`
   - `build/bazel_mgk_rules` → tetap ambil dari `MotorolaMobilityLLC/kernel-build-bazel_mgk_rules` lalu di-patch secara idempotent oleh `setup.sh` memakai `patches/bazel_mgk_rules-6.18.patch` di repo manifest (tidak perlu membuat repo baru).
   - `build/kernel` → gunakan langsung `kernel/build` AOSP `main-kernel-2026` bawaan manifest `common-android17-6.18-2026-09`.
   - Branch 6.12 stabil (`x6871-android16-6.12`) dan workspace `x6871-clean/ws` **tidak disentuh**.
2. **Hapus `mkp.ko` (MediaTek Kernel Protection) dari profil 6.18 (FINAL)**:
   - `mkp.ko` adalah modul proteksi kernel berbasis hypervisor EL2 (mengunci `.text`/`.rodata` S2 page table dan memantau `struct cred` / `selinux_state` anti-exploit/anti-root). Ia memiliki **0 ekspor, 0 dependen**, tidak menyentuh hardware/HAL, berisiko bentrok dengan perubahan internal SELinux 6.18 serta root (KernelSU), dan keempat hook `android_rvh_*_creds`-nya dihapus Google di `android17-6.18`.
   - **Keputusan**: `mkp.ko` **dihapus** dari target build `mgk_64.bzl` cabang 6.18 dan dikecualikan dari daftar modul `vendor_boot` profil 6.18 (`221` modul, `164` `modules.load`, `215` `modules.load.recovery`, total **487** modul runtime). Dengan ini, **0** vendor hook yang hilang tersisa di set 6.18.
3. **Pemangkasan Target Build (`mgk_64.bzl`)**:
   - Cabang `x6871-android17-6.18` memangkas daftar modul di `mgk_64.bzl` agar hanya membangun **closure ~429 modul runtime X6871 (+ `ko_deps` transitifnya, tanpa `mkp.ko`)**, bukan seluruh 812 modul multi-varian/SoC lain.
4. **Aturan Keras Tetap Berlaku**:
   - `kernel-6.18` **JANGAN PERNAH diedit** (Aturan Keras #15).
   - Jangan masukkan modul GKI terproteksi ke `vendor_boot`/`vendor_dlkm`/`odm_dlkm` (Aturan Keras #16).
   - Wajib lulus 8 gerbang `tools/verify-kmi-abi.py --kver 6.18` sebelum flash/rilis (Aturan Keras #17).

---

## 4. Peta Tahapan Eksekusi (*Fail-Fast*)

```text
Fase 0: Setup workspace & branch x6871-android17-6.18 (terisolasi dari 6.12)
   │
Fase 1: Port Kleaf main-kernel-2026 + patches/bazel_mgk_rules-6.18.patch
        + audit ack_headers.bzl (4.192 entri) + trim mgk_64.bzl ke ~430 modul
   │
Fase 2: Codemod API mekanis Linux 6.13–6.18 (1 commit per kategori)
   │
Fase 3: Milestone vendor_boot (221 modul, tanpa mkp.ko)
   │
[GERBANG UJI BOOT #1] Flash GKI android17-6.18-2026-09_r13 (4KB) + vendor_boot 6.18
   ├── Gagal blocker userspace A16 vs 6.18 (BPF/cgroup/mseal/TWRP) -> Stop & Evaluasi
   └── Lulus (TWRP + early-init Android + UFS + Display OK)
           │
Fase 4: Port 4 subsistem berat DLKM (209 vendor_dlkm + 57 odm_dlkm)
        (1) mtk_sched/eas -> (2) mali_kbase r54p1 -> (3) wlan_gen4m -> (4) cam/vcodec/audio
           │
Fase 5: Repack penuh + verify-kmi-abi.py --kver 6.18 (8 gerbang) + uji boot penuh
```

---

## 5. Rincian Teknis per Fase

### Fase 0 — Manifest, Branch, & Workspace Terisolasi
- Tambah `local_manifest-6.18.xml` di repo manifest:
  - `repo init -u https://android.googlesource.com/kernel/manifest -b common-android17-6.18-2026-09 --depth=1`
  - Pin `kernel/common` → path `kernel-6.18`, `revision="refs/tags/android17-6.18-2026-09_r13"`.
  - Buat branch `x6871-android17-6.18` dari HEAD stabil `x6871-android16-6.12` pada `alps-kernel_device_modules-6.12` (`20a8f5d`) dan `alps-vendor_mediatek_kernel_modules` (`83b4fa6`).
- Parameterisasi `KVER=${KVER:-6.12}` / `--kver 6.18` pada `setup.sh`, `build.sh`, `tools/repack-vendor-boot-latest.sh`, `tools/repack-dlkm-latest.sh`, dan `tools/verify-kmi-abi.py` (default tetap `6.12`).

### Fase 1 — Adaptasi Kleaf & `bazel_mgk_rules`
- Buat `patches/bazel_mgk_rules-6.18.patch`:
  - `BUILD.bazel`: tambah `config_setting(name = "kernel_version_6.18", flag_values = {":kernel_version": "6.18"})`.
  - `mgk.bzl`: tambah `"6.18": "mgk_64_k618"`, cabang `select()` untuk `6.18`, ganti `kernel_aarch64_debug` (kini `fail_rule` di 6.18) → `kernel_aarch64`.
  - `bzlmod/mgk.MODULE.bazel` & `mgk_extension.bzl`: sinkronkan `bazel_dep`/`local_path_override` (`rules_rust`, `rules_rust_bindgen`, `rules_devicetree`, `package_metadata`, `zstd`) dengan `build/kernel/kleaf/bzlmod/bazel.MODULE.bazel` milik `main-kernel-2026` serta pembacaan `bazel/constants.scl`.
- Di `kernel_device_modules-6.18` (branch `x6871-android17-6.18`):
  - `BUILD.bazel`: ubah referensi `6.12` → `6.18`, `define_mgk(name = "mgk_64_k618", ...)`.
  - `kernel/kleaf/mgk_modules.bzl`: load dari `//kernel-6.18:bazel/modules.bzl`; bersihkan `pstore_blk` (dihapus di `gki_defconfig` 6.18).
  - `kernel/kleaf/ack_headers.bzl`: audit otomatis 4.192 entri terhadap pohon `kernel-6.18` dan buang/sesuaikan path yang berubah.
  - `kernel/kleaf/mgk_64.bzl`: pangkas ke closure ~430 modul runtime X6871.
  - `arch/arm64/configs/mgk_64_k618_defconfig`: adaptasi dari `mgk_64_k612_defconfig` (`CONFIG_CFI_CLANG` → `CONFIG_CFI`, hapus `CONFIG_MEMCG_V1`).
- **Kriteria selesai Fase 1**: `mgk_64_k618_kernel_aarch64.user` selesai dibangun bersih.

### Fase 2 — Codemod API Mekanis (Skrip `scripts/port-6.18-mechanical.py`)

| # | Perubahan Linux 6.13–6.18 | Hit Terukur (OOT Runtime) | Transformasi |
|---|---|---|---|
| 1 | `MODULE_IMPORT_NS` string literal (6.13) | 87 hit / 85 file | `MODULE_IMPORT_NS(NS)` → `MODULE_IMPORT_NS("NS")` |
| 2 | `del_timer*` dihapus (6.15) | 156 hit / 82 file | `del_timer(` → `timer_delete(`, `del_timer_sync(` → `timer_delete_sync(` |
| 3 | `from_timer` dihapus (6.16) | 40 hit / 34 file | `from_timer(v, t, f)` → `timer_container_of(v, t, f)` |
| 4 | `hrtimer_init` dihapus (6.15) | 98 hit / 82 file (43 `.ko`) | `hrtimer_init(&h, c, m); h.function = fn;` → `hrtimer_setup(&h, fn, c, m);` |
| 5 | `no_llseek` dihapus | 2 file | Hapus `.llseek = no_llseek` / `noop_llseek` |
| 6 | Power supply phandle API | 9 modul charger/battery | `[devm_]power_supply_get_by_phandle` → `[devm_]power_supply_get_by_reference` |
| 7 | ASoC DAPM helper rename | `snd-soc-mt6895-afe`, `snd-soc-mt6368` | `dapm_{clock,regulator}_event`, `dapm_kcontrol_get_value` → `snd_soc_dapm_*` |
| 8 | Wakeup source API | `mediatek_drm_v1`, `mtk-soc-offload-common`, `c2k_usb` | `wakeup_source_create/add` → `wakeup_source_register`, `remove/destroy` → `wakeup_source_unregister` |

*(Catatan: simbol `alloc_workqueue`, `init_timer_key`, `ioremap_prot`, `__memcpy_fromio/toio`, `__memset_io`, `krealloc_noprof`, `debugfs_create_file`, `dma_pool_create`, `kthread_create_worker`, `sg_next`, `__get_task_comm`, `device_get_child_node_count`, `napi_gro_receive`, `snd_soc_set_runtime_hwparams`, dan `__v4l2_find_nearest_size` akan otomatis ter-resolve saat recompile ke header 6.18.)*

### Fase 3 — Milestone `vendor_boot` (221 Modul) & Gerbang Uji Boot #1

Fokus menyelesaikan kompilasi 221 modul `vendor_boot` (tanpa `mkp.ko`):
- **Display (`mediatek_drm_v1.ko`, `panel-rm69220-vdo-x6871.ko`, `mtk-mml.ko`)**: adaptasi `iommu_present`/`iommu_dev_disable_feature`, `drm_bridge`/`drm_panel`/`drm_atomic_*` (463 hit / 89 file) tanpa merusak fix C3D dual-pipe, PQ 12 B, AOD/HBM notifier enum `0..4`, 4 mode RM69220, dan `vddi-gpios` HIGH.
- **TEE & RPMB (`mcDrvModule.ko`, `rpmb-mtk.ko`)**: ganti `crypto_shash_update`/`final` → `crypto_shash_digest`/`finup` atau `sha256` lib.
- **Core platform (`mtk_iommu.ko`, `8250_mtk.ko`, `mtu3.ko`, `mtk-mmc.ko`, `tran_fp.ko`, `aee_hangdet.ko`, `mediatek-cpufreq-hw.ko`, `ufs-mediatek-dbg.ko`, GPIO/Thermal/OPP)**: adaptasi `iommu_ops`, `serial8250_rpm_{get,put}`, `device_find_child_by_name`, `mmc_can_gpio_cd`, `devm_gpio_request` → `devm_gpio_request_one`/`gpiod`, `irq_get_nr_irqs()`, `ipi_desc_get`, `cpufreq_generic_attr`, `tracepoint_srcu`, serta `gpio_chip.set` (return `int` di 6.17).
- **Gerbang Uji Boot #1**: flash `boot.img` + `system_dlkm.img` resmi `android17-6.18-2026-09_r13` (4KB) + `vendor_boot` 6.18. Wajib lolos TWRP (layar, touch, `/data` UFS, ADB) & early-init Android tanpa blocker dari `bpfloader`/`NetBpfLoad`, `cgroup`/`memcg`, `CONFIG_MSEAL_SYSTEM_MAPPINGS=y`, atau DTB stock.

### Fase 4 — Port 4 Subsistem Berat DLKM (209 `vendor_dlkm` + 57 `odm_dlkm`)

Dikerjakan berurutan pasca-Gerbang #1 lulus:
1. **Scheduler & Power MTK**: 61 file `kernel/sched/sched.h` (`mtk_sched`/`eas` terhadap perubahan EEVDF/`cfs_rq`/`rq`), `cpufreq_sugov_ext.ko` (`scx_*` / `__scx_ops_enabled`), arity `android_vh_binder_restore_priority` (3→2 di `task_turbo` & `vip_engine`), `cpufreq_get_policy` (`mtk_fpsgo_v8`, `mtk_sbe`), `__hw_protection_shutdown` (`mtk_low_battery_throttling`).
2. **GPU Mali `mali_kbase_mt6895_a16w.ko` (r54p1-11eac0)**: tangani penghapusan `__SetPageMovable`/`__ClearPageMovable` (nonaktifkan `CONFIG_MALI_PAGE_MIGRATION` terlebih dahulu, lalu evaluasi port `folio`), adaptasi `mm`/`dma_fence`/`devfreq` dengan menjaga ABI userspace `libGLES_mali.so` Android 16 & layout `gpufreq_shared_status`.
3. **Connectivity & Modem**: `wlan_drv_gen4m_6895.ko` (`cfg80211_ops` vs `cfg80211.ko` 6.18 in-tree, `init_dummy_netdev` → `alloc_netdev_dummy`, `netif_napi_add_weight`/`__netif_napi_del` → `*_locked`, `napi_gro_flush`), `ccmni`, `conninfra`, `bt_drv_6895`, `gps_drv_dl_v050`, `ccci_*`.
4. **Kamera, V4L2, Video Codec, & Audio**: `mtk-cam-isp`, `imgsensor`, `mtk-vcodec-{enc,dec}`, `flashlight`, `snd-soc-mt6895-afe`, `snd-soc-mt6368`, `snd-soc-mtk-scp-ultra`, `met` — jaga penuh ABI X6871 (`VENC_H264=1`, 6-field QP, `sink_fmt` inline, 4 sensor kamera, `RCV Select=Playback_R_DAC`, FS1599 PA).

### Fase 5 — Verifikasi Safeguard & Uji Perangkat Penuh

- Jalankan `./tools/verify-kmi-abi.py --kver 6.18` — **wajib lulus 8 gerbang (0 error)**:
  1. `kernel-6.18` bersih (0 edit lokal)
  2. Vermagic seragam `6.18.32-android17-5-...-4k`
  3. 0 mismatch CRC vs `kernel-6.18/gki/aarch64/abi.stg`
  4. 0 impor `vmlinux` non-KMI
  5. 0 kolisi `CONFIG_MODULE_SIG_PROTECT`
  6. 0 unresolved symbol (`vendor_boot` standalone & closure penuh)
  7. Integritas `modules.dep`/`modules.load`
  8. AVB hashtree `vendor_dlkm.img` + `odm_dlkm.img` valid
- Audit regresi tabel DT & struct ABI (`mtk-scpsys-mt6895` 39 domain, `charger_ops` 138 field, `gpufreq_shared_status`, `venc_vcu_config`).
- Jalankan checklist boot penuh seluruh subsistem di [`docs/BOOTTEST.md`](BOOTTEST.md) dengan rollback KMI 6 siap pakai.
