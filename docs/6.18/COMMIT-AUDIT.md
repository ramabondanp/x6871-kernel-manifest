# Audit Commit Awal 6.12 & Bringup 6.18 pada Repo Modul OOT

Diperbarui: 2026-11-28 (UTC)

> Dokumen ini mencatat hasil **audit statis kode** atas seluruh commit awal porting 6.12 dan bringup 6.18 pada kedua repositori modul *out-of-tree* (`alps-kernel_device_modules` dan `alps-vendor_mediatek_kernel_modules`). Belum ada patch perbaikan yang diterapkan, belum ada build baru, dan belum ada uji perangkat untuk temuan-temuan di bawah. Untuk status boot terkini lihat [`STATUS.md`](STATUS.md), daftar isu log di [`TRACKER.md`](TRACKER.md), dan audit API 6.13–6.18 sebelumnya di [`API-AUDIT.md`](API-AUDIT.md).

## Kebijakan & Ringkasan

- **Jangan menulis ulang sejarah (`git log` lama):** kekurangan historis pada commit awal (pesan tanpa `Signed-off-by`, subjek berbahasa Indonesia, commit campuran awal 6.18, atau churn tambah-lalu-revert) tidak memengaruhi hasil build maupun runtime. Menulis ulang sejarah akan mengubah seluruh SHA rujukan, memaksa *force-push* branch publik (`6.12` dan `6.18`), dan berisiko menimbulkan regresi.
- **Perbaiki cacat aktif di `HEAD` lewat commit baru (*forward fix*):** hanya temuan yang masih hidup di `HEAD` yang dibenahi dengan commit baru per topik (berlaku ke kedua branch `6.18` & `6.12` jika akarnya sama).
- **Cakupan modul aktif:** seluruh temuan dipilah berdasarkan allowlist target runtime X6871 di `kernel/kleaf/x6871_modules.bzl` (412 target OOT runtime).

| Kategori | Jumlah | Keterangan |
|---|---|---|
| **P0 — Crash / Panic / Korupsi Memori (Aktif)** | 6 | Wajib dibenahi lebih dulu (Wi-Fi Hotspot/hrtimer, DMA-BUF debug, MML V4L2, `task_turbo`, `pmic_lvsys_notify`) |
| **P1 — Bug Fungsional / ABI / Race / Leak (Aktif)** | 11 | UFS refcount/vops, EEVDF `balance.c`, DPE `kzalloc`, `tran-led-core`, `tc_tfcp_ta`/`pca_tfcp_ta`, Goodix IRQ wake, `mtk_vcodec_util`, `tkv`, `perf_common_v`, `tran_extcon_usb`, `leds-aw22xxx` & `tran_fp` |
| **P2 — Gap Backport 6.12 & Cleanup Layak (Aktif)** | 2 + 6 | 2 fix 6.18 yang berlaku di `6.12` (`met_drv_v3` `pm_qos`, `mtk-vcodec` `dma_buf_vunmap_unlocked`) + 6 cleanup sisa debug/guard |
| **P3 — Cacat Nyata di Modul Tidak Aktif (Opsional)** | 6 | Modul tidak dibangun di `x6871_modules.bzl` (`afs_common_utils`, `mtk-aie` `53`, `drivers/trusty`, `mtk_iommu_v1`, `synaptics_dsx`) |
| **Skip / Sudah Bersih** | — | Sejarah commit lama, konversi CRLF→LF, kosmetik minor, dan subsistem aktif yang sudah bersih |

## Baseline Audit

| Komponen | Branch / Posisi | Referensi |
|---|---|---|
| `alps-kernel_device_modules` (6.18) | `x6871-android17-6.18` | `175efc9f11d7` (178 commit di atas base Motorola `06079c22fb88`) |
| `alps-kernel_device_modules` (6.12) | `x6871-android16-6.12` | `175263d9b928` |
| `alps-vendor_mediatek_kernel_modules` (6.18) | `x6871-android17-6.18` | `e99fff9` (31 commit di atas `86edba6`) |
| `alps-vendor_mediatek_kernel_modules` (6.12) | `x6871-android16-6.12` | `5e9b2d8` |
| `x6871-kernel-manifest` | `main` | `53f7936` |
| Alat statis (`tools/check-private-structs.py`) | 3 gerbang | **PASS 3/3** (`vb2_dc_buf`, 0 redefinisi struct tak terlacak, 110 entri `ack_headers.bzl`) |

---

## 1. Prioritas P0 — Crash / Panic / Korupsi Memori (Modul Aktif X6871)

| ID | Repo & Branch | Modul & Lokasi | Commit Asal | Masalah & Arah Perbaikan | Status |
|---|---|---|---|---|---|
| `P0-1` | `vendor` (`6.18`) | `wlan_drv_gen4m_6895`<br>`connectivity/wlan/core/gen4m/os/linux/gl_p2p_kal.c:1794, 1823` | `28934e3` | `cfg80211_new_sta()` dan `cfg80211_del_sta()` diberi `netdev_priv(prP2pGlueInfo->aprRoleHandler)` (`struct NETDEV_PRIVATE_GLUE_INFO *`), bukan `struct wireless_dev *` (`->ieee80211_ptr`). Saat klien tersambung/putus dari Wi-Fi Hotspot (SoftAP) atau P2P GO, membaca offset `wdev` yang salah berujung korupsi memori/panic. **Fix:** ganti argumen pertama keduanya ke `prP2pGlueInfo->aprRoleHandler->ieee80211_ptr`. (Tidak berlaku di 6.12 karena argumen pertama masih `struct net_device *`.) | Terbuka |
| `P0-2` | `vendor` (`6.18`) | `wlan_drv_gen4m_6895`<br>`connectivity/wlan/core/gen4m/os/linux/gl_kal.c:7173-7208` | `bf88f97` + `28934e3` | `kalHrtimerCancel()` masih menulis `prTimer->function = NULL;` (baris 7207), sementara `kalHrtimerStart()` tidak lagi mengembalikan `prTimer->function = kalHrtimerTimeout;` dan `kalHrtimerIsInit()` hanya memeriksa `!!prTimer->base`. Saat `rCsaTimer` dibatalkan lalu dinyalakan lagi, `hrtimer_start()` menjalankan callback `NULL` di hardirq → NULL-deref panic. **Fix:** hapus `prTimer->function = NULL;` di `kalHrtimerCancel()`. (Tidak berlaku di 6.12 karena `kalHrtimerStart()` 6.12 masih mengisinya.) | Terbuka |
| `P0-3` | `kdm` (`6.18`) | `mtk_heap_debug`, `system_heap`, `mtk_sec_heap`<br>`drivers/dma-buf/heaps/mtk_heap_debug.c:1567-1583`, `mtk_heap_priv.h:90-91, 208-216`, `mtk_system_heap.c:555-585` | `59e73c2d2f4a` | `dma_heap_attach_dump()` men-cast `attach_obj->priv` ke `struct dma_heap_attachment *` tanpa guard `is_dmabuf_from_dma_heap()` / `!= NULL`, padahal `dma_heap_buf_dump_cb()` mengiterasi seluruh `dma_buf` (DRM/Mali/vb2) → NULL deref / type confusion. Selain itu, `system_heap_unmap_dma_buf()` tidak me-reset `a->sgt`/`a->dir` saat unmap, dan `mtk_sec_heap_main.c` tidak pernah mengisinya. **Fix:** guard dengan `is_dmabuf_from_dma_heap()` + `attach_obj->priv != NULL` (termasuk di `dmabuf_release_check()`) serta reset `a->sgt = NULL; a->dir = DMA_NONE;` saat unmap. | Terbuka |
| `P0-4` | `kdm` (`6.18`) | `mtk-mml`<br>`drivers/gpu/drm/mediatek/mml/mtk-mml-m2m-adaptor.c:1160, 1277, 1346, 1372, 1411` | `4fd7813538e9` (terlewat `29ba44c58c26`) | Lima handler ioctl V4L2 MML (`g_fmt_mplane`, `s_fmt_mplane`, `try_fmt_mplane`, `g_selection`, `s_selection`) masih memakai `fh_to_ctx(fh)`. Sejak 6.18 `v4l2-ioctl` mengirim `fh == NULL`, sehingga pemanggilan ioctl format/selection langsung panic (`container_of(NULL, ...)`). **Fix:** ganti ke `fh_to_ctx(file->private_data)`. | Terbuka |
| `P0-5` | `kdm` (`6.18`) | `task_turbo`<br>`drivers/misc/mediatek/task_turbo/task_turbo.c:300-312` | `aff3b45344c7` | `probe_android_vh_binder_restore_priority()` menghapus pemeriksaan `current == inherit_task` (padahal `t->android_vendor_data1` menyimpan pointer mentah `task_struct` tanpa `get_task_struct()`, sehingga berisiko UAF / salah target thread) dan menghapus cabang `else binder_stop_turbo_inherit(cur);`. **Fix:** pulihkan `struct task_struct *cur = current;`, cek `cur == inherit_task`, dan kembalikan cabang `else` (seragam dengan `vip_engine.c` di `3e2ff25d7c63`). | Terbuka |
| `P0-6` | `kdm` (`6.18` + `6.12`) | `pmic_lvsys_notify`<br>`drivers/misc/mediatek/power_throttling/pmic_lvsys_notify.c:645-695` | `b68b368f3e51` (parsial) | Bila node DT `low-battery-throttling` ada tetapi `lvsys-thd-enable == 0`, `thd_l`/`thd_h` tetap `NULL` lalu diteruskan ke `of_property_count_elems_of_size()` dan `of_property_read_u32_array()`. Di `6.12` (`175263d9b928`), `np` juga masih uninitialized. **Fix:** inisialisasi default `np = lvsys_np`, `thd_l = lvsys_node_thd_l`, `thd_h = lvsys_node_thd_h` di kedua branch. | Terbuka |

---

## 2. Prioritas P1 — Bug Fungsional / ABI / Race / Leak (Modul Aktif X6871)

| ID | Repo & Branch | Modul & Lokasi | Commit Asal | Masalah & Arah Perbaikan | Status |
|---|---|---|---|---|---|
| `P1-1` | `kdm` (`6.18`) | `ufs-mediatek-mod`, `ufs-mediatek-dbg`<br>`drivers/ufs/ufs-mediatek.c:1894-2030, 2163-2171`, `ufs-mediatek-dbg.c:1938-1946`, `ufs-mediatek-mimic.c:86-94` | `2a48d6af08b5`, `859c68811e62` | (a) Penghapusan `hba->scsi_block_reqs_cnt` menghilangkan refcount sementara `scsi_block_requests()` di 6.18 hanya assignment bool; pemanggil nested nyata (`ufs_mtk_dynamic_clock_scaling()` → `ufs_mtk_config_pwr_mode()`) meng-unblock SCSI I/O terlalu dini sebelum devfreq/caps selesai. (b) `.negotiate_pwr_mode` belum dipisah dari `ufs_mtk_pwr_change_notify(PRE_CHANGE)`. **Fix:** tambah `atomic_t scsi_block_reqs_cnt` di `struct ufs_mtk_host` dan pisahkan `.negotiate_pwr_mode` sesuai kontrak vops 6.18. | Terbuka |
| `P1-2` | `kdm` (`6.18`) | `scheduler`<br>`drivers/misc/mediatek/sched/eas/balance.c:435-440` | `b7fb33e9422e` | Penggantian mekanis `h_nr_running` → `this_rq->cfs.h_nr_runnable` keliru untuk EEVDF 6.18: task `sched_delayed` mengurangi `h_nr_runnable` tetapi tetap terhitung di `nr_running` dan `cfs.h_nr_queued`, sehingga kondisi `nr_running != h_nr_runnable` memaksa `*pulled_task = -1` (`RETRY_TASK`). **Fix:** ganti ke `this_rq->cfs.h_nr_queued` (sama dengan `kernel/sched/fair.c` 6.18). | Terbuka |
| `P1-3` | `vendor` (`6.18`) | `camera_dpe_isp70`<br>`mtkcam/mtk-dpe/isp_70/camera_dpe.c:5476, 5689-5710` (plus sibling non-aktif `isp_7sp`) | `b83dca0` | `DPE_open()` mengalokasikan `DPE_USER_INFO_STRUCT` (yang meng-embed `struct v4l2_fh`) memakai `kmalloc(..., GFP_ATOMIC)` bukan `kzalloc()`. `v4l2_fh_init()` mengasumsikan struct sudah zero-initialized (`fh->navailable`, `fh->m2m_ctx`). **Fix:** ubah ke `kzalloc` (atau zero-init `fh` sebelum `v4l2_fh_init()`). | Terbuka |
| `P1-4` | `kdm` (`6.18` + `6.12`) | `tran-led-core`<br>`drivers/leds/tran_led/tran_led_core.c:58-64, 141-267, 359, 373-378, 482-562` & `tran_led_class.c:175-211` | `39044a9498af` | Hasil rekonstruksi awal AI mengandung 6 bug nyata: (a) ioctl magic `'L'` (`0x4c`) bertentangan dengan komentar disassembly driver sendiri (`0x12`, mis. `0x40041202`–`0x80201201`), (b) stack leak `kbuf` belum di-zero sebelum `TRAN_GET_CMD` → `copy_to_user`, (c) `size_t len` unsigned underflow di multicolor show saat error, (d) sysfs handler lain tidak memanggil `tran_led_dev_check()`, (e) probe error path mengembalikan `0` dan merusak teardown, (f) `kfree(led_dev)` setelah `device_register()` gagal tanpa `put_device()`/`dev.release`. **Catatan wajib:** verifikasi ulang terhadap `.ko` stock sebelum mengubah nilai ioctl. | Terbuka |
| `P1-5` | `kdm` (`6.18` + `6.12`) | `tc_tfcp_ta`, `pca_tfcp_ta`<br>`drivers/power/supply/transsion/tc_tfcp_ta.c:92-140, 260-278, 384-403, 594-601` & `pca_tfcp_ta.c:48, 197-235, 360-422, 474-478` | `28c7b2655c60`, `649b928bd4cc` | Hasil rekonstruksi awal AI: (a) `tfcp_ta_read_device()` tidak pernah mengirim byte alamat `reg` ke I2C dan membandingkan `crc8(tmp)` vs `crc8(&reg)`, (b) cabang `suspended` return `0` dengan stack uninitialized, (c) `i2c_set_clientdata()` dipanggil sesudah registrasi devm, (d) `get_min_voltage`/`current`/`set_current`/`set_voltage` salah mask & tanpa `io_lock`, (e) `PCA_TFCP_DEFAULT_MV = 5000000` (uV, bukan mV) terpotong `0xffff`, (f) probe `pca_tfcp_ta` mengembalikan `-ENODEV` bukan `-EPROBE_DEFER`. **Catatan wajib:** verifikasi ulang disassembly `.ko` stock sebelum memperbaiki protokol TFCP. | Terbuka |
| `P1-6` | `kdm` (`6.18` + `6.12`) | `gt9916_common`<br>`drivers/input/touchscreen/transsion/vendor/goodix/gt9916_common/goodix_ts_gesture.c:58-66, 253-288` | `466e4c1731c1` | `gsx_gesture_before_suspend()` dan `before_resume()` masing-masing memeriksa `gsx->gesture_type` tanpa menyimpan flag apakah suspend benar-benar mengaktifkan `enable_irq_wake()`. Jika userspace mengubah gesture saat layar mati, resume memicu wake leak atau `WARN: Unbalanced IRQ wake disable`. Selain itu `fingerprint_status_read()` masih menolak `count < len` (`-EINVAL`, seharusnya `simple_read_from_buffer()`). | Terbuka |
| `P1-7` | `kdm` (`6.18` + `6.12`) | `mtk-vcodec-common`<br>`drivers/media/platform/mtk-vcodec/mtk_vcodec_util.c:1821-1844` | `73f4b3f5dbfe` | Jalur fallback `mtk_vcodec_set_task_priority()` pada `prio > 99` memanggil `sched_setscheduler_nocheck(task, SCHED_NORMAL, &param)` tanpa me-reset `param.sched_priority = 0` → selalu gagal `-EINVAL` (juga tidak memeriksa `prio < 0`). | Terbuka |
| `P1-8` | `kdm` (`6.18` + `6.12`) | `tkv`<br>`drivers/misc/transsion/tkv/tkv.c:48-67, 218-241` | `cb088a63c4b2` | `tkv_get_cmd()` membocorkan `of_node_put()`, `tkv_init()` tidak melepaskan `ioremap_cache()` (`iounmap()`), `tkv_exit()` kosong (dangling `/proc/tkv`), dan `pr_info("... %s", (char *)tkv_base)` berisiko OOB read bila region 32 KiB tidak berakhiran NUL. | Terbuka |
| `P1-9` | `kdm` (`6.18` + `6.12`) | `perf_common_v`<br>`drivers/misc/mediatek/perf_common_v/perf_common_v.c:15-41, 55-62` | `73f4b3f5dbfe` | `perf_common_v_exit()` tidak me-reset `format_sbin_data_hook = NULL` (dangling hook jika unload), underflow `ptr - 1` saat `lens == 0` menimpa `'['` pada `"ARRAY["`, serta konflik `SPDX: GPL-2.0` vs `MODULE_LICENSE("Proprietary")` yang men-taint kernel. | Terbuka |
| `P1-10` | `kdm` (`6.18` + `6.12`) | `tran_extcon_usb`<br>`drivers/misc/mediatek/extcon/tran_extcon_usb.c:391-405, 417-427, 454-456` | `3194d4f10237` | `tran_usb_extcon_remove()` kosong → dangling global notifier (`psy_nb`/`tcpc_nb`) UAF serta leak `extcon_wq`/`role_sw`; dan `devm_extcon_register_notifier(..., &extcon->otg_nb)` dipanggil sebelum `INIT_DELAYED_WORK(&extcon->otg_work, ...)`. | Terbuka |
| `P1-11` | `kdm` (`6.18` + `6.12`) | `leds-aw22xxx`, `tran_fp`<br>`drivers/leds/tran_led/leds-aw22xxx.c:2250-2266`, `drivers/input/fingerprint/tran_common/tran_fp_main.c:828-905` | `54c604b9378e`, `0e527bf7c6f4`, `55aa13232a43` | `aw22xxx_i2c_remove()` tidak memanggil `tran_led_device_unregister()`, hapus sysfs, atau cancel timer/work sebelum `devm_kfree()`. Pada `tran_fp_main.c`, gagal `tran_fp_irq_init()` melompati `input_unregister_device()` (leak), dan gagal `kobject_create_and_add()` mengembalikan `0` dengan `g_tran_fp_datap` dangling. | Terbuka |

---

## 3. Prioritas P2 — Gap Backport 6.12 & Cleanup Layak (Modul Aktif)

### 3.1 Gap Backport ke `x6871-android16-6.12`

Mayoritas bugfix di `6.18` sudah masuk ke `x6871-android16-6.12` (`175263d9b928` / `5e9b2d8`). Tersisa **2** fix khusus `6.12` (ditambah `pmic_lvsys_notify.c` pada `P0-6` yang berlaku di kedua branch):

| Repo | Lokasi di `6.12` | Fix di `6.18` | Detail & Dampak di `6.12` |
|---|---|---|---|
| `vendor` | `met_drv_v3/common/trace_event.c:92, 107` | `d500e72` | Header `kernel-6.12/include/trace/events/power.h:410, 453` sudah memakai signature baru (`s32 value` dan `enum pm_qos_req_action`), sedangkan `trace_event.c` di `6.12` (`5e9b2d8`) masih memakai prototipe lama → risiko KCFI mismatch bila MET power event diaktifkan. |
| `kdm` | `drivers/media/platform/mtk-vcodec/mtk_vcodec_dec.c:107-113`, `mtk_vcodec_enc.c:89-95` | `59e73c2d2f4a` | `mtk_vdec_sec_dc_unmap_dmabuf()` & `mtk_venc_sec_dc_unmap_dmabuf()` di `6.12` masih mengoper raw `void *` ke parameter `struct iosys_map *` milik `dma_buf_vunmap()` tanpa `dma_resv_lock`. Perlu `iosys_map_set_vaddr()` + `dma_buf_vunmap_unlocked()`. |

### 3.2 Cleanup Layak di `HEAD`

| Repo & Branch | File & Baris | Commit Asal | Masalah & Arah Cleanup |
|---|---|---|---|
| `kdm` (`6.18` + `6.12`) | `drivers/input/fingerprint/BUILD.bazel:44` | `6566cb27da18` | Hapus `-DTRAN_FP_LOG_LVL_INFO=1` (flag diagnostik bringup yang membuat `TRAN_FP_INFO` menyepam `dmesg` di setiap ioctl FOD). |
| `kdm` (`6.18` + `6.12`) | `drivers/media/platform/mtk-vcodec/venc/venc_vcp_if.c:1442-1451` | `f75c717036ac` | Turunkan atau hapus sisa `mtk_v4l2_debug(0, "first %s: ...")` yang selalu tercetak ke `dmesg` tiap sesi encode baru. |
| `vendor` (`6.18`) | `connectivity/conninfra/conn_drv/connv2/debug_utility/connsyslog/connsyslog.c:1390-1421`, `connectivity/wlan/core/gen4m/os/linux/gl_kal.c:7245-7290` | `bf88f97` | Cabang `#if (KERNEL_VERSION(6, 13, 0) > ...)` alarmtimer rusak/duplikat (`connsyslog.c` dua cabang identik `void`; `gl_kal.c` deklarasi `enum alarmtimer_restart` namun `return;`). Pulihkan cabang `< 6.13` atau bersihkan guard mati. |
| `vendor` (`6.18`) | `gpu/gpu_mali/mali_avalon/a16w/drivers/gpu/arm/midgard/mali_kbase_mem_migrate.c:713-717` | `28934e3` + `9edfe27` | `SetPageMovableOps()` tidak valid di 6.18 (aman saat ini hanya karena `kbase_page_migration_enabled = 0` di ACK). Tolak/abaikan `kbase_page_migration_enabled=1` secara eksplisit pada `>= 6.18`. |
| `kdm` (`6.18`) | `drivers/misc/mediatek/lpm_legacy/modules/debug/v1/lpm_dbg_cpuidle_status.c:647` | `b68b368f3e51` | Pulihkan `mtk_idle->cpu = cpu;` yang ikut terhapus regex `hrtimer_setup` (saat ini field belum dibaca). |
| `kdm` (`6.18` + `6.12`) | `drivers/power/supply/BUILD.bazel:168-170`, `tran_fp_main.c:105-201`, `tnek_api.c:218-220` | `fb88495998a7`, `36e0f17945e8`, `24b5fe361653` | Hapus komentar bahasa Indonesia usang di `BUILD.bazel` setelah `copts` dipindah ke `X6871.config`; opsional hapus dead code `tran_fp_allow_ree_transfer` dan lengkapi cleanup antrean di `tnek_api_exit()`. |

---

## 4. Prioritas P3 — Cacat Nyata di Modul Tidak Aktif X6871 (Opsional)

Modul berikut **tidak** termasuk dalam `x6871_modules.bzl`, sehingga tidak masuk image X6871, namun mengandung cacat kode nyata bila suatu saat diaktifkan atau dibuild target MTK generik:

- `vendor` (`6.18`): `afs_common_utils/src/jank_detection_common.c:660-661` (`b04917c`, `hrtimer_init(&timer_forcepull)` terhapus sementara `.function` tertinggal → `base == NULL`).
- `vendor` (`6.18`): `mtkcam/mtk-aie/mtk_aie_53.c:1564, 1579` (`17b9cf8`, masih memakai `fh_to_ctx(fh)` yang `NULL`; aktifnya `mtk_aie_isp71.c` sudah diperbaiki `96f4120`).
- `kdm` (`6.18`): `drivers/trusty/trusty-virtio.c:988` (`b68b368f3e51`, `tctx->vq_check_period_ms = default_vq_check_period_ms;` terhapus regex `hrtimer_setup`).
- `kdm` (`6.18`): `drivers/iommu/mtk_iommu_v1.c:638` (`f0a5813e776f`, `goto out_bus_set_null;` dengan label yang sudah dihapus → compile break bila diaktifkan).
- `kdm` (`6.18`): `drivers/input/touchscreen/synaptics_dsx_96789/Kconfig:19` & `synaptics_dsx_96851/Kconfig:19` (`354e5ff15b4a`, tipe `bool` pada entri `config` tertimpa `prompt` di dalam `choice`).
- `kdm` (`6.18`): `drivers/media/platform/mtk-aie/mtk_aie_53.c:901, 916` (masih memakai `fh_to_ctx(fh)` yang `NULL`).

---

## 5. Item yang Di-skip & Area Terverifikasi Bersih

**Sengaja di-skip (tidak perlu commit perbaikan):**
- Kekurangan sejarah commit lama (~106 commit `kdm` dan 5 commit `vendor` tanpa `Signed-off-by`, 3 subjek bahasa Indonesia, commit campuran awal 6.18, dan churn revert).
- Konversi CRLF→LF yang tidak disengaja di `6.18` (`synaptics_dsx_core.c`, `sbe_base.c`, `apusys/BUILD.bazel`, `mvpu_driver.c`) — hindari commit *reformatting* balik.
- Kosmetik minor (1 baris kosong sisa penghapusan `FB_EVENT_BLANK` di 6 file `vendor` & 16 file `kdm` non-aktif, fungsi unused `kbase_fence_fence_value_str()`/`fh_to_ctx()`, komentar lama berbahasa Indonesia / rujukan `PLAN.md`, 42 file impor donor tanpa header SPDX, serta bug minor jalur debug sysfs `tran_ldo.c` / error path `flashlight-core.c` bawaan sumber vendor 6.1).

**Area aktif yang sudah diverifikasi bersih di `HEAD`:**
- `panel-rm69220-vdo-x6871.c` (seluruh trace sementara `[LCMDBG]` dan `skip_unprepare` sudah dihapus bersih).
- `mtk_vcodec_enc_pm.c` (workaround SLBC-refuse dan log `VSI venc:` sudah di-drop).
- `mtk_disp_c3d.c`, `mtk_iommu.c`, `ged/` & `gpufreq/v2/`, `mtk_battery*`, `gt9916_common` / `adaptive-ts` core, `tc_tc30` / `tc_hvdcp20`, `mt6368.c` / `mt6895-mt6368.c`.
- `gl_cfg80211.c` di `gen4m` (`cfg80211_ops` & `gro_node` cocok 6.18), `wpa_*` prefix (`3581403`), `kthread_run_worker()` (`7d92fc24ce41`, `611ad1f`), `ack_headers.bzl` (`74f1812dda2d`), serta 5 commit X6871 6.12 di repo `vendor` (`b3d3a5a`–`1d259ab`).

---

## 6. Urutan Eksekusi yang Disarankan

1. **Batch 1 (P0):** `P0-1` s.d. `P0-6` — satu commit terpisah per topik (`P0-6` langsung ke `6.18` & `6.12`).
2. **Batch 2 (P1 langsung):** `P1-1` s.d. `P1-3` dan `P1-6` s.d. `P1-11` (`P1-6` s.d. `P1-11` berlaku ke `6.18` & `6.12`).
3. **Batch 3 (P2):** 2 gap backport ke `6.12` + cleanup debug/guard (`-DTRAN_FP_LOG_LVL_INFO=1`, log VENC frame pertama, alarmtimer `#if`, Mali migrate guard, LPM).
4. **Batch 4 (butuh verifikasi ulang `.ko` stock lebih dulu):** `P1-4` (`tran-led-core`) dan `P1-5` (`tc_tfcp_ta` / `pca_tfcp_ta`), agar perubahan ioctl/protokol sesuai 100% dengan biner stock X6871.
