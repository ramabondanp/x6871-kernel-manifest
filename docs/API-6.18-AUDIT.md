# Audit API 6.18 pada Modul OOT X6871

Diperbarui: 2026-11-23

Dokumen ini mencatat pemeriksaan perubahan API Linux 6.13–6.18 yang
**tidak tertangkap compiler** (perubahan semantik, bukan rename atau
perubahan signature). Audit dilakukan tanpa hardware, memakai hasil build
6.12 (`out_bazel_kmi7`) dan 6.18 (`out_bazel_test`).

## Metode

1. **Diff impor simbol per modul**: 418 modul OOT yang sama dibangun untuk
   6.12 dan 6.18, lalu daftar simbol kernel yang diimpor dibandingkan.
   Perubahan yang hanya berupa rename/wrapper dipisahkan dari perubahan
   perilaku.
2. **Diff inline/macro**: definisi `static inline` di
   `include/`, `arch/arm64/include/`, `kernel/`, `mm/`, `drivers/base/`,
   dan `lib/` pada tag `android16-6.12.97_r00` dibandingkan dengan working
   tree 6.18; kandidat yang menambah `WARN`/`return NULL`/error diperiksa
   terhadap pemakaian di source OOT.
3. **Scan KCFI tracepoint**: `tools/scan-cfi-tracepoints.py` (hash tipe
   fungsi vs hash call-site `__traceiter_*`).
4. **Audit struktur privat kernel**: modul yang menyalin layout struct
   kernel (mis. `module_sect_attrs`) diperiksa manual.

## Perubahan yang sudah ditangani

| API | Perubahan 6.18 | Modul | Status |
|---|---|---|---|
| `ioremap_prot` | hanya menerima `pgprot_t` user; `WARN_ON_ONCE` + NULL untuk proteksi kernel | `atf_logger` | diperbaiki: `ioremap_wc` + cek NULL |
| `ioremap_prot(PAGE_KERNEL)` | idem | `tkv` | diperbaiki: `ioremap_cache` |
| layout `module_sect_attrs`/`module_notes_attrs` | `attribute_group.bin_attrs` terminator NULL | `mrdump` | diperbaiki |
| prototipe probe `ufshcd_*` | `enum ufs_trace_str_t` | `ufs-mediatek-dbg` | diperbaiki |
| probe `pm_qos_*` | `s32` / `enum pm_qos_req_action` | `met` | diperbaiki |

## Perubahan yang diperiksa dan dinilai aman

| Perubahan | Catatan |
|---|---|
| `napi_gro_receive` → `gro_receive_skb` | `napi_gro_receive()` masih inline wrapper di `netdevice.h` |
| `netif_napi_add_weight` → `_locked` | inline wrapper mengambil `netdev_lock()` |
| `__netif_napi_del` → `_locked` | dipanggil dari wrapper dengan lock |
| `napi_gro_flush` → `__gro_flush` | inline wrapper |
| `init_dummy_netdev` → `alloc_netdev_dummy` | alokasi + init, dipakai WLAN |
| `cfg80211_stop_iface` → `cfg80211_stop_link` | inline wrapper memakai `link_id = -1` |
| `snd_soc_set_runtime_hwparams` | sekarang inline di `sound/soc.h` |
| `snd_soc_unregister_component` | makro ke `snd_soc_unregister_component_by_driver(dev, NULL)` |
| `watchdog_notify_pretimeout` | sekarang inline (tidak diekspor) |
| `put_task_struct` | 6.18 selalu memakai `call_rcu` + `__put_task_struct_rcu_cb` |
| `devm_ioremap*`, `of_iomap`, `memremap` | tetap mengembalikan NULL, bukan ERR_PTR; pemakaian lama tidak berubah |
| `cpufreq_driver.attr` | field dihapus; atribut standar didaftarkan core |
| `iommu_present` / `iommu_dev_disable_feature` | diganti `iommu_get_domain_for_dev()` di DRM |
| `devm_gpio_request_one`, `dma_pool_create_node`, `kthread_create_worker_on_node` | wrapper dengan argumen tambahan |
| `hrtimer_setup`, `timer_init_key`, `debugfs_create_file_full`, `alloc_workqueue_noprof` | rename/wrapper profil |

## Sisa risiko yang hanya bisa dibuktikan saat boot

Hal-hal berikut tidak dapat dipastikan lewat scan statis dan perlu uji
hardware setelah `vendor_boot-6.18-test4.img`:

- field EEVDF `cfs_rq`/`rq` di `scheduler.ko`, `cpufreq_sugov_ext.ko`,
  `task_turbo.ko`, `vip_engine.ko`;
- page migration Mali (`SetPageMovableOps`, tanpa clear);
- jalur DVFSRC/OPP yang tidak lagi mengimpor
  `dvfsrc_get_required_opp_peak_bw` (WLAN, ccmni, mmc);
- sinkronisasi `synchronize_rcu_tasks_trace` pada
  `ufs-mediatek-dbg.ko` dan `mtk_core_ctl.ko`;
- private io-pgtable di `iommu_debug.ko`;
- runtime hwparams dan DAPM audio (`snd-soc-mt6895-afe`,
  `snd-soc-mt6368`);
- apakah `bridge`/panel dan IOMMU display menunggu driver dengan benar.

## Reproduksi

```sh
# staging 6.12 dan 6.18
S12=<workspace-6.12>/out_bazel_kmi7/*/execroot/_main/bazel-out/*/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/staging/lib/modules/6.12.*
S18=<workspace-6.18>/out_bazel_test/*/execroot/_main/bazel-out/*/bin/kernel_device_modules-6.18/mgk_64_k618_customer_modules_install.user/staging/lib/modules/6.18.*

# pemindai KCFI
tools/scan-cfi-tracepoints.py --vmlinux <vmlinux-6.18> --modules "$S18"
```
