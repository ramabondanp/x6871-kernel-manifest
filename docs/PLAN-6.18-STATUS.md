# Status Eksekusi PLAN-6.18

Diperbarui: 2026-11-23 (UTC)

> Dokumen ini melacak eksekusi [`PLAN-6.18.md`](PLAN-6.18.md). Baseline
> produksi 6.12 (`gki-kmi6-20261122`) tidak berubah.

## Ringkasan

| Fase | Status | Catatan |
|---|---|---|
| 0 — Manifest, branch, workspace | **Selesai** | Workspace `<workspace-6.18>` |
| 1 — Kleaf/MGK + device tree 6.18 | **Selesai** | Kernel 6.18.32 target `mgk_64_k618` |
| 2 — Codemod API 6.13–6.18 | **Selesai** | Build penuh 546 `.ko` berhasil |
| 3 — Milestone `vendor_boot` | **Selesai (build)** | 221 modul, image terverifikasi |
| Gerbang boot #1 | **Lulus** | TWRP PASS (touch + vibrator); boot sistem PASS setelah patch SELinux; WiFi/BT PASS |
| 4 — DLKM berat | **Selesai (build)** | Sched, Mali, WLAN, cam/vcodec/audio |
| 5 — Repack + verifier 8 gerbang | **Selesai** | 8/8 PASS, 487 modul |

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
- Iterasi kompilasi: modul sudah mulai dibangun. Perbaikan yang masuk:
  alarmtimer callback `void`, `hrtimer_setup` 209 call site, `.remove`,
  IDA API, `napi->gro`, `ioremap_prot(pgprot_t)`, `pt_regs.pmr`,
  `dma_fence`, dma-buf attachment privat, `bin_attribute` const,
  `gpio_chip.set` int, `is_midr_in_range_list`, `hw_protection_trigger`,
  UFS trace hooks, dan cluster OOT DVFSRC/MMDVFS
  (`MTK_DVFSRC_HELPER`, `DEVICE_MODULES_REGULATOR_MTK_DVFSRC`,
  `MTK_MMDVFS`).
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

## Fase 2 — iterasi build penuh

Build `//kernel_device_modules-6.18:mgk_64_k618_customer_modules_install.user`
dijalankan dengan `--keep_going`; setiap putaran error dikelompokkan dan
diperbaiki per kategori. Commit terbaru (device modules):

| Commit | Cakupan |
|---|---|
| `1acf9872` | UFS 6.18, audio DSP compress, header privat IOMMU |
| `0a06656b` | namespace dma-heap, GRO ccMNI, alias EYEMON, xHCI DBC |
| `4f6833d5` | `mcdi` → `hrtimer_setup` |
| `8b170ca8` | hapus dependensi ARM SMMUv3, `pgsize_bitmap`, UFS PMC, `vdec_fmt` fence |
| `b5dbe5e7` | argumen `v4l2_fh_add/del`, API CQHCI crypto, rename `rpmb_hmac_sha256`, `bin_attribute` const |
| `e3d9b5a0` | sisa call site RPMB/v4l2_fh |
| `6ac6847a`, `21938485` | semua callback `bin_attribute` → const, wakeup unregister |
| `e840b691` | `mtk-mmc-swcqhci` memakai `key->bytes`/`KEY_TYPE_RAW` |
| `008b4460` | DRM 6.18: argumen `drm_format_info`, `drm_panel_*` void, `mode_valid` const, `mmc_host_can_gpio_cd`, `file_ref_get` |

Commit vendor modules: `d626fe8`, `2bebd04`, `6742b41`, `ed93bfa`,
`59df9af`, `4c25e6d`, `269be18`, `7daa323` (namespace `close_fd`,
`v4l2_fh`, inisialisasi `dev_slave` di camsys).

Kelas error 6.18 yang sudah tertangani antara lain: API privat
`io-pgtable-arm`, `MODULE_IMPORT_NS("DMA_BUF_HEAP")`,
`netif_receive_skb_list_internal` (diganti jalur publik), DBC xHCI yang
tidak diekspor GKI, `hrtimer_init` tersisa, `ufshcd_config_pwr_mode`
tiga argumen, `snd_compr_tstamp64`, `wakeup_source_destroy`,
`vm_fault`/`file->f_count` (`file_ref_t`), `bin_attribute` const,
`drm_panel_*` void, dan `drm_format_info` pada `fb_create`.

Commit setelah pengecekan silang modul OPPO:

| Commit | Cakupan |
|---|---|
| `a4b28b99`, `e749e5ce` | GED/dummy DRM `dma_fence`, `FB_EVENT_BLANK` kompat, `iommu` pgsize, UFS PMC |
| `2479c430`, `a505b426` | sched EEVDF, WLAN cfg80211/GRO, Mali movable/fence, audio `DAIFMT`, apusys format |
| `9720caa9`, `70d8c031` | fpsgo/sbe `cpufreq_cpu_get`, task_turbo rwsem/binder, local `governor.h` |
| `506bd813` | vip_engine binder restore hook memakai `current` |
| vendor `885db78` | prefiks `wpa_` untuk SHA/HMAC WPA agar tidak bentrok `crypto/sha2.h` |

Pengecekan `.ko` OPPO PMX110 6.18 mengonfirmasi arah port: `mediatek-drm`
memakai `cpufreq_cpu_get`, `mtk-mmc` memakai `mmc_host_can_gpio_cd`,
heap memakai `DMA_BUF_HEAP`, `scheduler` memakai `pick_task(rq, rf)`
tanpa `entity_eligible`, GED tanpa notifier fbdev, dan `apu_top` memakai
`devfreq_add_governor` + header privat `governor.h`. Detail ada di
[`PMX110-6.18-REFERENCE.md`](PMX110-6.18-REFERENCE.md).

## Hasil build penuh 6.18 (2026-11-23)

Build `//kernel_device_modules-6.18:mgk_64_k618_customer_modules_install.user`
selesai tanpa error:

- staging total **546** `.ko` = 379 device OOT + 39 vendor OOT + 128 GKI.
- Set runtime **487** modul = **221** `vendor_boot` + **209**
  `vendor_dlkm` + **57** `odm_dlkm`; `mkp.ko` dihapus sesuai keputusan
  desain.
- Inventaris runtime identik dengan rilis 6.12
  `gki-kmi7-aw22xxx-20261122`, kecuali `mkp.ko` (sengaja tidak ada di
  6.18).

### Image hasil repack

| Image | Ukuran | MD5 |
|---|---:|---|
| `vendor_boot-6.18-test.img` | 67.108.864 B | `fbd70f65be1d76c01177320e5d7043c2` |
| `vendor_boot-6.18-test2.img` | 67.108.864 B | `a8ae05e4e172bf0c7c85ae20fff96e5f` |
| `vendor_boot-6.18-test3.img` | 67.108.864 B | `03e95db7dbd5161259f325327a23f037` |
| `vendor_boot-6.18-test4.img` | 67.108.864 B | `c09077991d966a61813d9d85da15bb5c` |
| `vendor_boot-6.18-test5-dbg.img` | 67.108.864 B | `24181af2448d923e0b83cb2bc04b79a2` |
| `vendor_dlkm.img` | 24.551.424 B | `e3a23e686d4ba08646c4d0b763c7c05d` |
| `odm_dlkm.img` | 4.206.592 B | `da2c64a1572ff27382128beb4bbcba8b` |

`vendor_boot-6.18-test5-dbg.img` adalah image diagnostik terbaru:
sama dengan test4 ditambah pembatas log badai MIUMPU. `test4` adalah
image boot normal terakhir. Image test3/test2/test1 jangan dipakai lagi.

`vendor_dlkm.img` di-repack ulang setelah perbaikan `met.ko` (md5 baru
`e3a23e686d4ba08646c4d0b763c7c05d`); `odm_dlkm.img` tidak berubah.

Uji hardware dengan `vendor_boot-6.18-test3.img`: **TWRP berhasil
boot**. Boot ke sistem berikutnya panic di `atf_logger.ko`; lihat
bagian "Panic atf_logger 6.18".

Ukuran ketiga image sama dengan rilis 6.12; hash berbeda karena
vermagic/isi modul 6.18.

| Image | Rilis `gki-kmi7-aw22xxx-20261122` | Build 6.18 |
|---|---|---|
| `vendor_boot.img` | `ca163b1a031658b156dbd5d856e8bad2` | `fbd70f65be1d76c01177320e5d7043c2` |
| `vendor_dlkm.img` | `d54910f726bbdba0630869855be178d9` | `e3a23e686d4ba08646c4d0b763c7c05d` |
| `odm_dlkm.img` | `3b13699addae11e4ddc074013e129f23` | `da2c64a1572ff27382128beb4bbcba8b` |

Perbandingan nama modul: 221/209/57 identik dengan rilis; satu-satunya
selisih adalah `mkp.ko` (222 → 221 di `vendor_boot`, sengaja dihapus).
`modules.load` dan `modules.dep` juga identik selain entri `mkp.ko`.

### Verifikasi 8 gerbang

`tools/verify-kmi-abi.py --kver 6.18`:

```text
GKI release : 6.18.32-android17-5-gecdaacc9a0ee-4k
ABI symbols : 9593 (build vs abi.stg mismatches: 0)
Modules     : 487 ({'vendor_boot': 221, 'vendor_dlkm': 209, 'odm_dlkm': 57})
  1. Pure GKI (common clean)        : PASS
  2. Wrong vermagic                  : 0
  3. CONFIG_MODULE_SIG_PROTECT hits  : 0
  4. vendor_boot standalone unres/crc: 0 / 0
  5. Full runtime closure unres/crc  : 0 / 0
  6. Official abi.stg CRC mismatches : 0
  7. Non-KMI unlisted vmlinux imports: 0
  8. modules.dep/load & other errors : 0
ALL KMI/ABI SAFEGUARDS PASSED.
```

Dua import non-KMI terakhir yang diperbaiki: `serial8250_rpm_get/put`
di `8250_mtk.ko` (diganti `pm_runtime_*` langsung) dan
`__hw_protection_trigger` di `mtk_low_battery_throttling.ko` (diganti
`orderly_poweroff(true)`).

### Artefak dan commit

- Device modules (`kernel_device_modules-6.18`, branch
  `x6871-android17-6.18`): `f09133d503df`
- Vendor modules (`vendor/mediatek/kernel_modules`, branch
  `x6871-android17-6.18`): `d500e72bea0b`
- Manifest: commit dokumentasi ini
- Image: `<artefak-lokal>/`
- Build log: `<log-build-lokal>`

### Panic mrdump 6.18

Uji TWRP pertama panic saat `mrdump.ko` dimuat:

```text
Unable to handle kernel NULL pointer dereference at 0x0000000000000100
pc : __pi_strcmp+0xf0
lr : load_ko_addr_list+0xf8 [mrdump]
```

6.18 mengganti `struct module_sect_attrs`/`module_notes_attrs` privat
kernel: tidak ada lagi `nsections`, `notes`, atau `struct
module_sect_attr` dengan field `address`. Keduanya kini diawali
`struct attribute_group` dan memakai array `grp.bin_attrs` yang
di-terminasi NULL; alamat section/note ada di `bin_attribute.private`.

Salinan struktur lama di `mrdump_mini.c` membuat `fill_ko_list()`
membaca `attr.mode` (0400 = 0x100) sebagai pointer nama string, lalu
`strcmp()` dereference 0x100. Perbaikan: baca lewat
`attribute_group.bin_attrs` dan `bin_attribute.private` tanpa menyalin
layout privat kernel.

### Mismatch KCFI tracepoint 6.18

Uji TWRP kedua sampai melewati mrdump, lalu panic di UFS:

```text
CFI failure at ufshcd_add_uic_command_trace+0x194/0x1c4
(target: probe_ufshcd_uic_command+0x0/0x164; expected type: 0xfa55a7bd)
```

Penyebabnya port 6.18 mengganti parameter `enum ufs_trace_str_t` pada
probe `ufshcd_command`/`ufshcd_uic_command` menjadi `int`; KCFI
membandingkan hash tipe fungsi, bukan isi pointer `void *`. Enum lokal
dikembalikan ke signature probe dan dipindah keluar dari blok
`CONFIG_MTK_AEE_FEATURE`.

Scan statis seluruh modul dengan
`tools/scan-cfi-tracepoints.py` juga menemukan dua probe MET yang
memakai signature lama: `pm_qos_update_request` (tiga argumen) dan
`pm_qos_update_target` (`unsigned int` bukan
`enum pm_qos_req_action`). Keduanya diperbaiki.

Hasil scan staging 546 modul: 97 pasangan tracepoint diperiksa, 0
mismatch. Tujuh entri "unpaired" adalah tabel yang bukan registrasi
probe (misalnya string `"charger"` milik power supply).
`ufs-mediatek-mod.ko` memakai loop registrasi yang tidak dapat
dipasangkan otomatis; tiga callback-nya dicek manual dan cocok.

### Badai MIUMPU 6.18

Uji `vendor_boot-6.18-test4.img` berhenti dengan console yang hanya
berisi badai interupsi (1036 kejadian dalam 57 ms):

```text
emimpu_violation_irq:
[MIUMPU]emiid0
[1c0]0;...;[3c0]104;...;[3d0]7;[3d4]a;[3d8]3;[3e4]2c06;[3e8]0;
```

Nilai register konstan, jadi satu master terus mengulang akses ke
region yang dilindungi. `[3d8]=3` konsisten dengan SRINFO=3 yang
dipakai IOMMU untuk memicu SMPU saat translation fault. Log boot
sebelumnya hilang karena setiap interupsi mencetak dump penuh ke
console pstore 256 KiB.

Commit `f09133d503df` membatasi log 16 kejadian pertama (KERN_ERR,
termasuk register EMIMPU, AXI ID, dan `comm`/pid), lalu tetap membersihkan
violation tanpa mencetak atau menjadwalkan AEE. Tujuannya agar pstore
menyimpan konteks boot sebelum badai. Image `test5-dbg` memakai
perubahan ini untuk mengidentifikasi master/IOMMU yang fault.

Audit perubahan API 6.13–6.18 yang tidak tertangkap compiler (memakai
hasil build 6.12 dan 6.18) dicatat di
[`API-6.18-AUDIT.md`](API-6.18-AUDIT.md).

### Panic atf_logger 6.18

Boot sistem setelah TWRP berhasil berhenti di `modprobe atf_logger`:

```text
WARNING: ... at asm/io.h:275 lookup_reserved_memory+0xa0/0xd8 [atf_logger]
[TFA]RO debug buf vaddr:0x0
Unable to handle kernel NULL pointer dereference at 0x0000000000000000
pc : tfa_debug_probe+0x6c/0x218 [atf_logger]
```

6.18 mengubah `ioremap_prot()` di arm64: fungsi hanya menerima
`pgprot_t` dari mapping user, mengembalikan NULL (dan `WARN_ON_ONCE`)
untuk proteksi kernel. Kode lama memberi
`pgprot_writecombine(PAGE_KERNEL_RO)` sehingga `info.vaddr` menjadi
NULL, tetapi `IS_ERR(NULL)` bernilai false dan
`lookup_runtime_log()` langsung dereference `info.vaddr`.

Perbaikan: pakai `ioremap_wc()` (atribut write-combine yang sama) dan
tolak vaddr NULL. Panggilan `ioremap_prot(PAGE_KERNEL)` di `tkv.c` juga
diganti `ioremap_cache()`.

Pesan commit 6.18 ditulis ulang ke format kernel (`subsystem: ringkasan
imperatif ... for 6.18`, body 72 kolom, `Signed-off-by`), dan sudah
diperiksa dengan `common/scripts/checkpatch.pl`: 0 error/warning pesan.

**Berikutnya:** TWRP sudah PASS; uji boot sistem dengan
`vendor_boot-6.18-test4.img` (GKI `boot.img` + `system_dlkm.img` resmi
6.18 4KB), lalu lanjutkan validasi early-init sesuai
[`BOOTTEST.md`](BOOTTEST.md).

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

## Temuan boot 6.18 (2026-11-23)

- DTB 6.18 identik byte-for-byte dengan DTB 6.12 yang boot normal
  (`ead6a965b0aaacc2a9c520721693f342`); DTS 6.18 juga identik. Jadi
  kegagalan boot bukan karena DT/DTB.
- `log pstore uji` (panic test3) berisi log 6.18 lengkap 0.0–4.68 s.
  Panic test3 berasal dari `tfa_debug_probe` di `atf_logger`; sudah
  diperbaiki oleh `54d86b4eb545` untuk test4 dan sesudahnya.
- Di log yang sama, 91 modul GKI gagal dimuat:
  `.gnu.linkonce.this_module section size must match ...`
  (`zsmalloc`, `pstore_zone`, `netfs`, `virtio*`, `macsec`, dst.).
  Artinya `system_dlkm` yang terpasang tidak cocok dengan `boot.img`
  6.18; kemungkinan masih 6.12 atau build GKI berbeda. Perbaikan:
  flash `boot.img` dan `system_dlkm.img` dari satu paket GKI 6.18
  (`gecdaacc9a0ee`, 4 KB).
- `mtk-wdt` aktif dengan timeout 31 s. Sistem hang setelah 4.68 s,
  watchdog reset sekitar 31 s; badai MIUMPU di 31.76 s muncul di jalur
  reset dan memenuhi 256 KB console ramoops, sehingga menutupi log
  boot. Badai bukan penyebab hang.
- `emi-mpu-hook-v1.ko` tidak ada di `tools/modules.load-6.18`, sehingga
  stage-1 tidak memuat hook `by_plat_isr_hook`. Akibatnya IOMMU
  translation fault (`srinfo_r=3`, `axi_id=0x2c06`) tidak di-bypass dan
  `md_handler`/`iommu_handler` dipanggil berulang di hardirq. Perbaikan:
  hook ditambahkan tepat setelah `emi-mpu-v2.ko` di
  `tools/modules.load-6.18`, dan `md_handler` dibatasi dengan `show`.
- Uji berikutnya: `vendor_boot-6.18-test9-emihook.img`
  (md5 `84522556a4006d2ba78f531b150e2707`), tanpa panic buatan.
  Uji ini untuk melihat apakah badai MIUMPU berhenti dan sistem bisa
  melewati 31 detik. Jika masih hang, langkah berikutnya adalah
  diagnostik `hrtimer` (bukan `delayed_work`).

## Hasil test9 (log pstore uji)

- Hook stage-1 aktif: `emi_mpu_isr_hook`, `srinfo_r 3`,
  `axi_id_r 11270 (0x2c06)`, `To bypass this violation`. Tidak ada lagi
  91 error `.gnu.linkonce.this_module`, jadi `system_dlkm` sudah cocok.
- Log pstore sekarang menyimpan 1.35–31.73 s (tidak lagi didominasi
  badai), tetapi IRQ tetap ~41.000 kali/detik. Bypass hanya menahan
  `printk`, bukan menghentikan sumber fault.
- Fault pertama muncul pada 4.626 s, tepat setelah
  `remoteproc1: attaching to apusys_rv` dan SMC APU 8–11. APU memakai
  IOVA `0xffef9000` (config) dan `0xffef8000` (IPI). APU init timeout
  pada 14.823 s (`APU initialization timeout!!`).
- Pada 25.6 s terjadi RCU stall: `rcu_preempt kthread starved for 2698
  jiffies`; CPU6 terjebak di `stop_machine_yield`/`multi_cpu_stop`,
  CPU0 di badai EMI. `stop_machine` tidak selesai karena CPU0 tidak
  pernah keluar dari hardirq; watchdog reset ~31 s.
- Perbandingan 6.12 vs 6.18: urutan modul APU/EMI identik
  (`mtk_apu_power_throttling` baris 45, `emi-mpu-hook-v1` baris 104,
  `apu_top` baris 130, `apusys` baris 131), dan source APU
  (`apu_config.c`, `apu_ipi.c`, `apu_rproc.c`, `apu.h`,
  `mvpu2_preempt.c`) identik. Jadi regresi ada di kernel/IOMMU/GKI
  6.18, bukan di urutan modul atau source APU.
- Uji konfirmasi APU: `vendor_dlkm.img` tanpa APU
  (md5 `64e8aa756fa72ff150b68a1cb50cf693`, 206 modul, tanpa
  `apusys`/`apu_top`/`mtk_apu_power_throttling`),
  https://gofile.io/d/EclhAxEP. Jika sistem boot melewati 31 s,
  penyebab hang terkonfirmasi APU; kamera/AI/MDLA/MVPU tidak aktif
  pada image ini.



## Penerapan SARAN §5.3 (2026-11-23)

- `mtk_iommu.c`: `mtk_iommu_hw_program()` dipisah dari `mtk_iommu_hw_init()`
  (request IRQ tidak idempoten). Suspend menandai `apu_pm_sta = OFF`;
  resume `APU_IOMMU` memprogram ulang register + `REG_MMU_PT_BASE_ADDR`
  jika hardware kehilangan state, lalu menandai `POWER_ON_STA` hanya
  setelah read-back `ttbr` cocok. Ini memindahkan inisialisasi APU IOMMU
  ke `pm_runtime_get_sync()` di `mt6895_apu_power_on()`, setelah RCX
  menyala dan sebelum SMC start uP.
- `apu_rproc.c`: timeout firmware kini `-ETIMEDOUT` (bukan sukses), dan
  jalur `stop:` mematikan APU (`power_off`) bila `F_FAST_ON_OFF` tidak
  diset.
- Solusi 2 (memindahkan `apu_top` + `mtk_apu_power_throttling` ke
  `vendor_boot`) **tidak diterapkan**: closure `apu_top` di 6.18 berisi
  57 modul dan 13 di antaranya belum ada di `vendor_boot`, termasuk
  `ccci_md_all`/`mtk_pbm`/`mtk_mdpm`; selain itu
  `mt6895_apu_top_pb()` tidak memanggil `__apu_wake_rpc_rcx()` (hanya
  `mt6895_apu_top_on()` saat apusys power-on), sehingga premisnya tidak
  tercapai. Rincian ada di [`SARAN.md` §6.2](SARAN.md).
- Build ulang sukses: `mtk_iommu.ko`, `apusys.ko`, dan target penuh
  `mgk_64_k618_customer_modules_install.user`.

### Image test11 (SARAN 5.3)

| Image | Ukuran | MD5 |
|---|---:|---|
| `vendor_boot-6.18-test11-iommu.img` | 67.108.864 B | `0ee453c16ae20b6dfbf2cc4bf0db492e` |
| `vendor_dlkm.img` (dengan fix ipesys + v4l2) | 24.551.424 B | `70144e66a846b1de359d99c82afbd264` |
| `odm_dlkm.img` | 4.206.592 B | `da2c64a1572ff27382128beb4bbcba8b` (tidak berubah) |

Unduhan: https://gofile.io/d/oTgnm1xd

Verifikasi `tools/verify-kmi-abi.py --kver 6.18` untuk image ini: 8/8
PASS, 487 modul (221/209/57), 0 mismatch. Image berisi 221 modul
`vendor_boot`, termasuk `emi-mpu-hook-v1.ko` di stage-1; `apu_top` tetap
di `vendor_dlkm`.

### Hasil test11 (log pstore uji)

- Solusi 1 bekerja: tidak ada satu pun baris `emimpu_violation_irq` /
  `MIUMPU` di seluruh log. `__apu_wake_rpc_rcx` berhasil pada 4.589 s
  (`PWR_RDY 0x2 -> 0x3`), mapping APU IOMMU berjalan dengan
  `ttbr=0x14c00001` (bukan 0), `smc call 7..11` dan
  `remote processor apusys_rv is now attached` selesai, lalu IPI APU
  bertrafik normal. Badai ~41 kHz dan RCU stall tidak muncul.
- Panic baru pada 4.690 s, tidak terkait APU:
  `Unable to handle kernel NULL pointer dereference at 0x124`,
  `device_link_add+0xdc` dari `mtk_ipesys_me_probe`. DT
  `ipesys_me@15320000` memang menonaktifkan `mediatek,larb` (`#if 0`),
  tetapi probe tetap memanggil `device_link_add(&pdev->dev,
  &larb_pdev->dev, ...)` dengan `larb_pdev = NULL`.
- Perbaikan `e37b531921` (`vendor/mediatek/kernel_modules`):
  lewati device link bila node/device LARB tidak ada, probe lanjut.
- `vendor_dlkm.img` di-repack ulang dengan fix ini
  (md5 `7e8d45ada4a38bee96a79d0c40fcd75d`) dan verifier 8 gerbang
  tetap 8/8 PASS. `vendor_boot`/`odm_dlkm` tidak berubah; cukup flash
  ulang `vendor_dlkm`.
- Solusi 3 belum teruji karena panic terjadi sebelum batas timeout
  firmware 10 s.

### Hasil log pstore uji (vendor_dlkm fix ipesys)

- Fix `e37b531921` bekerja: `mtk_ipesys_me_probe` tidak lagi panic dan
  boot menembus userspace sampai `t = 14.17 s` (apexd, Trustonic,
  charger, UFS, dsb.).
- Dua bug V4L2 6.18 muncul setelah userspace membuka node video:
  1. `v4l2_open+0x12c` WARN untuk node DPE: `dpe_fop_open()` tidak
     memakai `v4l2_fh`, sehingga 6.18 memanggil `release` dan
     mengembalikan `-ENODEV`. Diperbaiki di
     `vendor/mediatek/kernel_modules` commit `8f77ce0001`:
     `struct v4l2_fh` menjadi anggota pertama
     `DPE_USER_INFO_STRUCT`, di-init di open dan di-teardown di release.
  2. `vidioc_vdec_querycap+0x1c` Oops pada `t = 14.167 s`:
     `v4l_querycap()` 6.18 memanggil `vidioc_querycap(file, NULL, cap)`,
     sedangkan driver memakai `fh_to_ctx(priv)` → alamat
     `0xffffffffffffffd8`. Diperbaiki di `kernel_device_modules-6.18`
     commit `e924a12ab6`: decoder dan encoder memakai
     `video_drvdata(file)`.
- Warning non-fatal `proc_register: '/proc/mtk_typec' already
  registered` berasal dari `tran_extcon_usb` dan `mux_switch` yang
  sama-sama membuat entri proc; tidak mematikan boot, dicatat terpisah.
- `vendor_dlkm.img` baru: md5 `70144e66a846b1de359d99c82afbd264`,
  8/8 PASS. `vendor_boot`/`odm_dlkm` tidak berubah.

### TWRP touch & vibrator (test12)

`log TWRP` (6.18) menunjukkan akar yang sama dengan `firmware_load`:

```text
SELinux: Permission firmware_load in class system not defined in policy.
goodix_ts: loading /vendor/firmware/goodix_cfg_group.bin failed -13
goodix_ts: loading /vendor/firmware/goodix_firmware.bin failed -13
haptic_hv: loading /vendor/firmware/haptic_ram.bin failed -13
```

- Probe touch dan haptic sebenarnya berhasil (`goodix_ts_core probe
  success`, `aw_i2c_probe probe completed`), tetapi cfg/firmware
  goodix dan RAM haptic tidak bisa dibaca. Goodix lalu
  `stage2 init failed`; touch tidak melaporkan finger. Vibrator tetap
  tanpa waveform RAM.
- TWRP memakai policy v30 dari `vendor_boot` (`/sepolicy`) yang tidak
  mendefinisikan permission `firmware_load`. Yang permissive hanya
  domain `recovery`; domain `kernel` tetap enforcing, sehingga
  `request_firmware()` dari kworker ditolak.
- 6.12 KMI7 tidak terkena karena `selinux_kernel_read_file()` 6.12
  tidak memeriksa `READING_FIRMWARE`. Perbandingan image KMI7 vs 6.18:
  dtb, bootconfig, dan `vendor_ramdisk01` byte-identik; 980 file
  non-modul di platform ramdisk identik; daftar modul hanya berbeda
  `mkp.ko`.
- Perbaikan TWRP: `sepolicy` di platform ramdisk di-patch agar domain
  `kernel` permissive (bit `permissive_map` untuk tipe `kernel`).
  Ini hanya berlaku untuk TWRP; Android memakai policy dari
  system/vendor. `root.1/sepolicy` packer disimpan aslinya sebagai
  `sepolicy.orig`.
- Image: `vendor_boot-6.18-test12-twrpfix.img`, md5
  `57608d6d57e411db851cd75e2ff0b460`; `sepolicy` md5
  `eec594edb028bc8ed8c4627213bd7ab9` (kernel permissive=1), 221
  modul cocok staging. `vendor_dlkm`/`odm_dlkm` tidak berubah.
- Android tetap memakai patch SELinux vendor (allow `firmware_load`)
  dari paket terpisah; patch TWRP tidak menggantikannya.

### Hasil uji perangkat (2026-11-23)

Flash ketiga image di bawah, lalu diuji di perangkat:

| Image | md5 |
|---|---|
| `vendor_boot-6.18-test12-twrpfix.img` | `57608d6d57e411db851cd75e2ff0b460` |
| `vendor_dlkm.img` | `70144e66a846b1de359d99c82afbd264` |
| `odm_dlkm.img` | `da2c64a1572ff27382128beb4bbcba8b` |

Hasil:
- **TWRP PASS**: touch goodix berfungsi dan vibrator berfungsi
  (perbaikan policy TWRP di `vendor_boot` test12).
- **Boot ke sistem PASS setelah patch SELinux**: `system.img`
  (`plat_sepolicy.cil`) + `vendor.img`
  (`vendor_sepolicy.cil`, `vendor_file_contexts`) dipatch untuk
  permission `firmware_load`. Tanpa patch, `mali_csffw.bin` dan
  `haptic_ram.bin` gagal `-13`, SurfaceFlinger/zygote crash, lalu
  reboot. Prosedur dan patch: [`SELINUX-6.18.md`](SELINUX-6.18.md),
  [`patches/selinux-x6871-6.18.patch`](../patches/selinux-x6871-6.18.patch).
- Tidak ada `enforce=0` global; domain `kernel` permissive hanya di
  policy TWRP. Android memakai policy system/vendor yang sudah dipatch.
- **WiFi/Bluetooth PASS** setelah `vendor_sepolicy.cil` diberi allow
  `kernel → connsys_vendor_file` (`firmware_load`), dikonfirmasi
  pengguna 2026-11-23. Sebelumnya `conninfra.cfg` ditolak `-13`,
  conninfra power on gagal (`WMT turn on WIFI fail`, `BT turn on fail`).
  `vendor_sepolicy.cil` hasil patch: md5
  `5b0827a140e928900a4b91006fba301d`.
- Gerbang boot #1 dinyatakan **LULUS**. Pengujian subsistem lanjutan
  mengikuti checklist `BOOTTEST.md`.
