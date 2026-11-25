# PLAN 6.18 Lanjutan — Temuan Log dan Prioritas Perbaikan

Diperbarui: 2026-11-25 (UTC)

> Dokumen ini adalah lanjutan dari [`STATUS.md`](STATUS.md).
> Fokusnya bukan menambah fitur, tetapi menutup temuan dari log boot 6.18:
> crash yang sudah punya fix, error non-fatal yang masih berulang, dan
> keputusan mana yang **tidak boleh** dikejar karena memang disabled di
> device tree stock.
>
> Prinsip utama: **image selalu memakai DTB/DTBO stock**. DT di tree tidak
> dipakai untuk membuat image, jadi jangan mengubah DT tree untuk mengejar
> error log. Node yang disabled di stock tetap disabled; jangan menambah node,
> event, atau thermal zone yang tidak ada di stock.
>
> Log mentah disimpan lokal dan tidak disertakan di repo. Bukti di dokumen
> ini dikutip sebagai baris log, bukan nama file lokal.

## 1. Ringkasan

| Kategori | Status | Tindakan |
|---|---|---|
| Oops/panic/RCU stall | **Terverifikasi PASS di device** | `0` kemunculan `Internal error`/`WARNING: CPU`/RCU stall/`[MIUMPU]srinfo_r 3` di boot `6.18.65` |
| EMI MPU `SRINFO=3` + RCU stall | **Terverifikasi PASS di device** | `6ebc4934a74a` terkonfirmasi bersih di boot `6.18.65` (`EMIMPU: 0`) |
| ADSP | **Known limitation / skip (stock DTB disabled)** | DTB stock `disabled` (`total 0` core); early boot `t=5.77s` masih mencatat 1x `adsp_system_bootup fail ret(-14)` + 80x `invalid cid` saat init lalu berhenti; audio `fs15xx` aktif |
| Video VP8 / VP9 / AV1 | **Terverifikasi PASS di device** | VP9 (25 sesi s.d. 1080x1920), VP8 720p (120/120 frame, `132.0 fps`), AV1 720p/1080p (120/120 frame, `228.0 / 110.5 fps`), dan VENC 1080p@30fps PASS (`0` error) |
| DPE `v4l2_fh` | **Terverifikasi PASS di device** | `0` `v4l2_open` WARN; `[DPE]DPE open`/`release` bersih di `6.18.65` |
| CMDQ/GCE + MML | **Terverifikasi PASS di device** | `0` `vote mminfra on err` di boot `6.18.65`; display, kamera, codec, MML normal |
| Thermal `lvts`/`soc_max` | **Terverifikasi PASS di device** | `0` `Failed to register lvts tz`; 40 zone aktif (`soc_max` `59.5°C` -> `72.6°C`) |
| Touch (`gt9916_common` + `adaptive-ts`) | **Terverifikasi PASS di device** | Node & `vendor.hardware.trantp-service` aktif, `~352–354 Hz`, charger anti-noise PASS; sisa ukur sleep/wake pada `report_rate_switch=1` |
| `tranhalconfig` | **Terbuka, userspace** | Masih `222` AVC & `audit_lost: 21` di `6.18.65`; perlu fix service/sepolicy vendor |
| `fpsgo`/`trans_sched` | **Known limitation; skip di 6.18** | Jangan buat stub palsu; core FPSGO tetap jalan |
| TEE/Widevine | **Known limitation; sama dengan 6.12 port** | Provisioning/TA, bukan DT/driver; `DRM Info` belum dicek ulang di boot `6.18.65` |
| Error minor | **2 bug kernel PASS di device; 9 item skip** | `kthread_run_worker` (`7d92fc24ce41`, `611ad1f`) & `/proc/mtk_typec` (`112de113630b`, `587a0a7`) terverifikasi PASS di boot baru (`6.18.65`); 9 item lain paritas stock/userspace |

Tidak ada `am_crash` atau `am_anr` di logcat historis yang dianalisis. Pada
uji live terbaru (`6.18.65-android17-6-g39d19ad1a460-rama982-4k`), seluruh fix
kernel di atas sudah terverifikasi di perangkat nyata; item yang belum diuji
atau masih terbuka di userspace ditandai eksplisit pada tiap subbagian.

## 2. Metode dan Cakupan

- Enam log `dmesg` dari beberapa boot, tiga belas log `pstore`, dua log
  `logcat`, dan satu log TWRP.
- Pencarian difokuskan pada: `Oops`, `Internal error`, `WARNING: CPU`,
  `rcu_preempt detected stalls`, `Call trace`, `SMPU`, `MIUMPU`, `v4l2`,
  `cmdq`, `mml`, `thermal`, `adsp`, `TEE`, `Widevine`, `SELinux: avc: denied`,
  dan `init: ... failed`.
- Setiap crash dicocokkan dengan commit di branch `x6871-android17-6.18`
  (device modules) atau branch vendor `x6871-android17-6.18`.
- DTB/DTBO stock diperiksa dari image stock. DTBO stock tidak meng-override
  ADSP; status `disabled` berasal dari DTB `vendor_boot` stock.
- Pipeline image memakai DTB stock: `tools/repack-vendor-boot-latest.sh`
  mewajibkan `dtb` byte-identical dengan packer base, dan
  `tools/pack-vendor-boot.sh` (legacy) juga menyalin `dtb` stock apa adanya.
  DT di tree hanya dipakai untuk build modul, bukan sebagai sumber DTB
  image.

## 3. Crash/Oops yang Sudah Punya Fix

Semua temuan di bawah sudah punya commit yang menyasar signature yang sama.
Belum ada log baru setelah commit, jadi tetap perlu verifikasi.

| Gejala | Fix yang cocok |
|---|---|
| Oops `__pi_strcmp` dari `load_ko_addr_list [mrdump]` | `3fd701c` mrdump section attrs; `089b49c` treewide mrdump API |
| Oops CFI di `ufshcd_add_uic_command_trace` | `6d2e8d1` UFS tracepoint prototypes; `3661489` UFS headers |
| Oops `tfa_debug_probe [atf_logger]` | `54d86b4` ATF debug mapping |
| Oops `device_link_add` setelah `mtk_ipesys_me_probe: larb node not found` | `e37b531` ipesys ME SMI LARB (vendor) |
| Oops `vidioc_vdec_querycap` | `41f442c` querycap file handle |
| Oops `vidioc_vdec_s_fmt` | `29ba44c` V4L2 ioctl NULL priv |
| Oops `mtk_aie_s_fmt_out_mp` | `96f4120` mtk-aie NULL fh (vendor) |
| `[MIUMPU]srinfo_r 3` + `rcu_preempt detected stalls` | `6ebc4934a74a` replay APU IOMMU setelah RCX power on |

Untuk EMI MPU/RCU stall, `6ebc4934a74a` adalah fix utama:

```text
The uP then runs with PT_BASE=0 and every translation faults
into SRINFO=3 SMPU violations that pin CPU0 in the hardirq handler.
```

Commit `32a2cb4`/`f09133d` hanya membatasi log dan `md_handler`, bukan
memperbaiki akar masalah. Jadi `pstore` yang menunjukkan `srinfo_r 3` dan
RCU stall tidak lagi dihitung sebagai isu terbuka.

**Hasil verifikasi live (`6.18.65-android17-6-g39d19ad1a460-rama982-4k`):**
**PASS** — pengecekan `dmesg` sepanjang pengujian kamera, perekaman video,
decode VP9/H.264, charger replug, dan kontrol touch mencatat **0 kemunculan**
untuk seluruh pola berikut:

```text
Internal error: 0
WARNING: CPU: 0
rcu_preempt detected stalls: 0
[MIUMPU]srinfo_r 3: 0
EMIMPU: 0
```

Selain itu, jalur `mtk-aie-5.3 15310000.aie` menutup stream dengan bersih
(`STREAM STOP` dan `[mtk_aie_hw_disconnect] stream_count:0 map_count0`)
tanpa Oops `mtk_aie_s_fmt_out_mp` (`96f4120`). Tabel crash di atas resmi
**ditutup**.

## 4. ADSP: Stock DTB Disabled, DT Tree Tidak Dipakai

DTB `vendor_boot` stock menunjukkan:

```text
adspsys@1e000000      status = "disabled";
adsp-core0@1e020000   status = "disabled";
adsp-core1@1e090000   status = "disabled";
```

DT di tree memang masih `okay`, tetapi DT tersebut **tidak dipakai untuk
image**. Jangan revisi `mt6895.dts` untuk kasus ini.

Log historis menunjukkan:

```text
adsp_system_bootup fail ret(-14)
[IPI][COM] ipi_dsp_id_to_adsp_cid(), invalid cid 0, total 0   (77x)
adsp_register_feature, feature 'voip' not in any core_set
snd-audio-dsp: ASoC error (-1): at snd_soc_component_open()  (15x)
```

Log tersebut konsisten dengan DTB yang mengaktifkan ADSP. Kalau sekarang
image selalu memakai DTB stock, log itu tidak relevan untuk build stock dan
tidak perlu dikejar dengan mengubah DT tree.

**Keputusan:** jangan kejar ADSP dan jangan ubah DT tree. Audio stock
berjalan lewat jalur SCP (`snd-scp-ultra`), bukan ADSP.

Kalau `adsp_system_bootup fail` masih muncul pada boot dengan DTB stock:

1. Pastikan `dtb` di `vendor_boot` hasil repack identik dengan stock.
   `tools/repack-vendor-boot-latest.sh` sudah memverifikasi ini secara
   byte-identical.
2. Pastikan tidak ada DTB/DTBO kustom yang mengaktifkan ADSP.
3. Kalau DTB sudah benar, periksa driver: `adsp_system_bootup()` tetap
   dipanggil saat module init meskipun tidak ada core. Perbaikannya di
   driver, bukan di DT tree.

Catatan: card `snd-audio-dsp` juga ada di DT stock. Jadi error ASoC DSP bisa
saja masih muncul jika userspace tetap membuka PCM DSP. Itu bukan alasan
untuk mengaktifkan ADSP.

**Hasil verifikasi live (`6.18.65-android17-6-g39d19ad1a460-rama982-4k`):**
pada pengecekan boot segar (`up 0 min`) sebelum ring buffer tergulir,
terkonfirmasi kasus butir 3 di atas: karena DTB stock memiliki `total 0`
core (`disabled`) namun module init tetap memanggil `adsp_system_bootup()`,
awal boot mencatat sekali `adsp_system_bootup fail ret(-14)` dan 80x
`invalid cid 0/1, total 0` lalu berhenti setelah init:

```text
[    5.776236] adsp_system_bootup fail ret(-14)
[    5.778138] [IPI][COM] ipi_dsp_id_to_adsp_cid(), invalid cid 0, total 0
[    5.778149] [IPI][COM] ipi_dsp_id_to_adsp_cid(), invalid cid 1, total 0
```

Hal ini menegaskan `dtb` stock aktif (`total 0` core) dan tidak menghambat
audio `fs15xx` (`6-0034`/`6-0035`); ADSP tetap berstatus non-bug / skip.

## 5. Temuan Non-Crash dan Rencana Fix

### 5.1 Video VP9 — prioritas utama user-facing

**Gejala:**

```text
vdec_vcp_decode() - unsupported (-1,-1)
vdec_vcp_decode() VP9 header rejected: changed=0x4 payload=644324 length=2094080 offset=0 flags=0x0
vb2ops_vdec_buf_queue: Error!! Codec driver not support the file!
vidioc_vdec_qbuf: Call on QBUF after unrecoverable error   (15x)
mtk_vdec_g_v_ctrl: Error!! Cannot get param                (7x)
```

**Temuan dan hasil uji perangkat:**

- Uji build DMA-BUF sync VP9 (`7c48ebd`, sync scatterlist + `dma_wmb()`
  sebelum `DEC_START`) tetap gagal di perangkat (Story tetap hitam;
  VP9 masih ditolak `changed=0x4`, `offset=0`, payload berisi data).
  Karena tidak efektif dan modul stock juga tidak melakukannya, `7c48ebd`
  di-revert oleh commit `213a184315ef`.
- Debug runtime dengan `mtk_v4l2_dbg_level=3` memastikan CPU membaca header
  keyframe VP9 Profile 0 yang valid (sync code `49 83 42`) dengan dimensi
  `540×960` dan `720×1280`, bitstream IOVA `0x12fe00000` di dalam aperture
  Video uP VDEC `0x110000000..0x12fffffff`, serta alokasi 3×
  `MEM_TYPE_FOR_SW` dan 3× `MEM_TYPE_FOR_HW_CACHE` berhasil dengan IOVA
  nonzero. VCP mengirim `B001` (`DEC_START_DONE`) dengan status `-1`.
- Audit biner modul stock SP20 (`vcp.ko`, `vcp_status.ko`,
  `mtk_iommu.ko`, `mtk-vcodec-common.ko`, `mtk-vcodec-dec.ko`) dibanding
  build 6.18 menunjukkan paritas pada tabel `vcp_reserve_mblock`,
  `feature_table`, `vcp_io_devs`, `mt6895_multi_dom_mm`, `flags` IOMMU
  MT6895, `vdec_vsi`/IOCTL/VCP probe, dan helper map DMA-BUF (selisih di
  `vcp.ko` hanya ukuran `vcp_ipidev` 136 vs 128 B, PM/logger ops, dan
  wrapper API 6.18).
- Ditemukan bug terpisah pada `mtk_vcodec_drv.h`: reset `VENC_H264 = 1`
  memperkecil `VDEC_VENC_MAX` menjadi `8`, sehingga `mtk_dec_tput_init()`
  selalu gagal memuat 12 entri `max-op-rate-table` dan `throughput-table`
  dari DTB stock. Diperbaiki oleh commit `a719a23cee6d` dengan memulihkan
  `VDEC_VENC_MAX = 20` tanpa mengubah ID `VENC_H264..VENC_H263` (sudah
  termasuk dalam build `6.18-lts` dan lolos uji live di `6.18.65` dengan
  `0` error `tput`/`max-op-rate`).

- Uji live V4L2 M2M pada `/dev/video3` di profil `6.18-lts` mengonfirmasi
  H.264 dan HEVC 720×1280 (`mtk_mm` DMA-BUF) **PASS** (`Init Vdec OK`,
  `B001 status=0`, `DQEVENT changes=0x1`, alokasi UBE `14681088` byte),
  sedangkan VP9 (`82 49 83 42`, 720×1280) gagal identik (`B001 status=-1`,
  `changed=0x4`) pada semua mode buffer (`mtk_mm`, `mtk_mm-uncached`,
  `system`, dan `mmap`), dan VP8 gagal pada `check_codec_id`.
- **Akar masalah terbukti** dari trace live `VCU_IPIMSG_DEC_CHECK_CODEC_ID`
  dan disassembly `vcp_dec_ipi_handler` pada `mtk-vcodec-dec.ko` stock SP20:
  firmware VCP dan modul stock melewati slot `4` di `enum mtk_codec_type`,
  memetakan `VDEC_VP8 = 5`, `VDEC_VP9 = 6` (memiliki varian `svp=1`), ...,
  `VDEC_AV1 = 13`. Karena slot `4` hilang di tree, `VDEC_VP8..VDEC_AV1`
  bergeser `-1` sehingga `check_codec_id()` untuk VP9 menganggap
  `VDEC_VP9 == 5`, menolak `id=6` (VP9 VCP) dan membuka decoder VP8 (`id=5`)
  untuk bitstream VP9 (alokasi 4 buffer kecil tanpa UBE 14 MB), lalu
  firmware langsung menolak header VP9 dengan `changed=0x4`. Bug yang sama
  juga ada di tree `6.12`.

**Fix:**

- Commit `ac2e63fe0411` menetapkan `VDEC_VP8 = 5` di
  `drivers/media/platform/mtk-vcodec/mtk_vcodec_drv.h`, menyelaraskan ID
  decoder `VDEC_VP8..VDEC_AV1` ke `5..13` tanpa mengubah `VENC_H264..VENC_H263`
  (`1..7`) maupun `VDEC_VENC_MAX = 20`.

**Verifikasi:**

- Disassembly `vcp_dec_ipi_handler` pada `mtk-vcodec-dec.ko` build `6.18-lts`
  memastikan ID decoder `1..3`, `5..13` (VP8=`5`, VP9=`6`, AV1=`13`) cocok
  dengan stock. Build penuh `6.18.65-android17-6-g39d19ad1a460-rama982-4k`
  lulus **8/8** `verify-kmi-abi.py` (487 modul runtime, `9.843` simbol ABI,
  0 mismatch/unresolved) dengan set 5 image:
  - `boot-lz4.img`: `b62605570ef07c9ffe5a7fe4aaf1040d`
  - `system_dlkm.flatten.erofs.img`: `8857cbd0d7de0bbaf087cbe80e0253ec`
  - `vendor_boot.img`: `ea13b6dfe2de10b20f8a046d40c429f3`
  - `vendor_dlkm.img`: `c7aa223e09de1b1b50545edcb1fc0a08`
  - `odm_dlkm.img`: `773a5910abfac89c2dbd4fcf7bd74613`
- **Hasil verifikasi live di perangkat (`6.18.65`) — VP9 PASS:**
  - `check_codec_id ipi id 6 svp 0 is correct`: **25x** (`0` penolakan).
  - `Init Vdec OK bs VP90`: **25 sesi** (`360x640`, `540x960`, `720x1280`,
    hingga `1080x1920` `M2CS`), DVFS adaptif aktif (`update adaptive op 0 -> 31`),
    dan progres frame (`decoded_cnt:77 -> 138`).
  - `0` error `B001`, `MTK_V4L2_ERR`, `VP9 header rejected`, `tput`, maupun
    `max-op-rate`.
  - Video encoder (`mtk-vcodec-enc`) juga **PASS** pada rekaman `1920x1080`
    30 fps (`vb2ops_venc_start_streaming(): fmt 0x6, P/L 4/11, w/h 1920/1080, buf 1920/1080, fps/bps 30/20000000(0)`
    -> `vidioc_encoder_cmd=1` -> `vb2ops_venc_stop_streaming` -> `fops_vcodec_release`,
    `0` `MTK_V4L2_ERR`).

```text
[  218.137319] check_codec_id ipi id 6 svp 0 is correct
[  218.137595] [MTK_V4L2] level=0 vdec_vcp_init(),1409: [82] VP90(1) Decoder Instance >> 000000005d094521, ap_inst_addr ffffff8074300010
[  218.142513] [MTK_V4L2] level=0 vb2ops_vdec_buf_queue(),3976: [82] Init Vdec OK bs VP90 fm M21S, wxh=384x640 pic wxh=360x640 bitdepth:8 lo:0 sz[0]=0x5a000 sz[1]=0x0 num_planes 1, fb_sz[0] 368640, fb_sz[1] 0, BS
[  219.760312] [MTK_V4L2_DVFS_QOS] mtk_vdec_dvfs_monitor_op_rate(),910: [VDVFS][VDEC][ADAPTIVE][82] update adaptive op 0 -> 31
[  220.162814] [MTK_V4L2_DVFS_QOS] mtk_vdec_check_alive_work(),2257: [VDVFS] ctx:82, active:1, decoded_cnt:77, last_decoded_cnt:0
[  222.182291] [MTK_V4L2_DVFS_QOS] mtk_vdec_check_alive_work(),2257: [VDVFS] ctx:82, active:1, decoded_cnt:138, last_decoded_cnt:77
[  255.658346] [MTK_V4L2] level=0 vb2ops_vdec_buf_queue(),3976: [104] Init Vdec OK bs VP90 fm M2CS, wxh=1088x1920 pic wxh=1080x1920 bitdepth:8 lo:1 sz[0]=0x300140 sz[1]=0x0 num_planes 1, fb_sz[0] 3146048, fb_sz[1] 0, BS
```

- **Hasil verifikasi live di perangkat (`6.18.65`) — VP8 & AV1 PASS:**
  diuji dengan sampel `ffmpeg` (4 detik, `120` packet) lewat pipeline
  MediaCodec hardware nyata (`c2.mtk.vpx.decoder` dan `c2.mtk.av1.decoder`
  -> V4L2 `mtk-vcodec-dec` -> VCP, dengan `ABinderProcess_startThreadPool()`
  aktif):
  - **VP8 720p (`libvpx`, profile 0, `c2.mtk.vpx.decoder`):**
    - Mode `surface`: `120/120` frame terdekode, `120/120` frame piksel non-zero,
      `acquired_images=120`, `eos=1`, `0.909 s` (**`132.0 fps`**).
    - Mode `bytebuffer`: `120/120` frame, `120/120` non-zero, `eos=1`,
      `0.927 s` (**`129.4 fps`**).
  - **AV1 720p & 1080p (`libsvtav1`, Main Profile `yuv420p`, `c2.mtk.av1.decoder`):**
    - 720p `surface`: `120/120` frame, `120/120` non-zero,
      `acquired_images=120`, `eos=1`, `0.526 s` (**`228.0 fps`**).
    - 720p `bytebuffer`: `120/120` frame, `120/120` non-zero, `eos=1`,
      `0.577 s` (**`208.1 fps`**).
    - 1080p `surface`: `120/120` frame, `120/120` non-zero,
      `acquired_images=120`, `eos=1`, `1.086 s` (**`110.5 fps`**).
  - Selama seluruh rangkaian uji VP8 & AV1: `MTK_V4L2_ERR: 0`, `B001: 0`,
    `rejected: 0`, `unsupported: 0`, `Internal error: 0`, `WARNING: CPU: 0`,
    `EMIMPU: 0`, `MIUMPU: 0`, `rcu_preempt: 0`.

```text
[ 1956.213519] check_codec_id ipi id 5 svp 0 is correct
[ 1956.213891] [MTK_V4L2] level=0 vdec_vcp_init(),1409: [165] VP80(1) Decoder Instance >> 000000009991becc, ap_inst_addr ffffff80a79f9010
[ 1956.215739] [MTK_V4L2] level=0 vb2ops_vdec_buf_queue(),3976: [165] Init Vdec OK bs VP80 fm M21S, wxh=1280x736 pic wxh=1280x720 bitdepth:8 lo:0 sz[0]=0x159000 sz[1]=0x0 num_planes 1, fb_sz[0] 1413120, fb_sz[1] 0, BS
[ 1958.601044] check_codec_id ipi id 13 svp 0 is correct
[ 1958.607098] [MTK_V4L2] level=0 vb2ops_vdec_buf_queue(),3976: [169] Init Vdec OK bs AV10 fm M21S, wxh=1280x736 pic wxh=1280x720 bitdepth:8 lo:0 sz[0]=0x159000 sz[1]=0x0 num_planes 1, fb_sz[0] 1413120, fb_sz[1] 0, BS
[ 1960.289641] check_codec_id ipi id 13 svp 0 is correct
[ 1960.301412] [MTK_V4L2] level=0 vb2ops_vdec_buf_queue(),3976: [173] Init Vdec OK bs AV10 fm M2CS, wxh=1920x1088 pic wxh=1920x1080 bitdepth:8 lo:1 sz[0]=0x300140 sz[1]=0x0 num_planes 1, fb_sz[0] 3146048, fb_sz[1] 0, BS
```

### 5.2 DPE `v4l2_fh` — fixed di isp_70

**Gejala:**

```text
WARNING: CPU: ... at drivers/media/v4l2-core/v4l2-dev.c:438 v4l2_open+...
```

**Akar masalah:** `v4l2_open()` di 6.18 mewajibkan driver memakai
`v4l2_fh` (`V4L2_FL_USES_V4L2_FH`). Kalau flag tidak ada, core mencetak
WARN, memanggil `release`, dan mengembalikan `-ENODEV`. `camera_dpe.c`
mendaftarkan video node `dpe-vid`, tetapi `dpe_fop_open()` hanya
memanggil `DPE_open()` lalu `return 0`; tidak ada `v4l2_fh_init()`.

**Kenapa fix sebelumnya tidak jalan:** commit `3cb567a` hanya mengubah
`mtkcam/mtk-dpe/isp_7sp/camera_dpe.c`. Build X6871 memakai
`camera_dpe_isp70` dari `isp_70/camera_dpe.c`, jadi warning tetap muncul.

**Fix:** commit `b83dca0` menerapkan pola yang sama ke `isp_70`:
`struct v4l2_fh` menjadi anggota pertama `DPE_USER_INFO_STRUCT`,
di-init/di-add di `dpe_fop_open()`, dan di-del/exit di
`dpe_fop_release()`. Karena `fh` adalah anggota pertama,
`file->private_data` tetap menunjuk ke `DPE_USER_INFO_STRUCT` yang
dipakai ioctl/poll.

**Siapa yang membuka node:** di semua dmesg, satu-satunya opener adalah
`VcodecProcess` (C2 codec service, pid 1506) saat enumerasi `/dev/video*`
di boot, 2x. Kamera tidak pernah membuka node V4L2; jalur kamera memakai
char device `/dev/DPE`.

**Verifikasi build:** `camera_dpe_isp70.ko` sekarang mengimpor
`v4l2_fh_init`, `v4l2_fh_add`, `v4l2_fh_del`, `v4l2_fh_exit`.
`vendor_dlkm.img` baru md5 `86fd65af151a1e813d132c5915686285` sudah
memuat module ini.

**Hasil verifikasi live (`6.18.65-android17-6-g39d19ad1a460-rama982-4k`):**
**PASS** — `0` kemunculan `v4l2_open` WARN di `dmesg`. Kamera (`mtk-cam` +
`s5khm6sx_mipi_raw`), flashlight (`ocp81375_v4l2`:
`[ocp81375_get_hw_fault] flag1_0x0A=0 flag2_0x0B =0 enableregval=0`), DPE,
dan playback/rekam codec berjalan normal:

```text
[DPE]DPE open g_u4EnableClockCount: 1
[DPE]- X. Ret: 0. UserCount: 1.
[DPE]DPE release g_u4EnableClockCount: 0
S5KHM6SX[s5khm6sx_feedback_awbgain] set_awbgain: r_gain = 0x6fa b_gain = 0x5f2 sensor mode = 5
```

### 5.3 CMDQ/GCE dan MML — `vote mminfra` fixed; sisanya historis

**Gejala CMDQ:**

```text
[cmdq][err] no gce-event-names property or no such event:disp_ovlsys_wdma0_eof0
[cmdq][err] no gce-event-names property or no such event:disp_mdp_rdma0_eof0
[cmdq][err] channel request fail:-2 idx:1 @cmdq_mbox_create,511
[cmdq][err] vote mminfra on err:1 @cmdq_mbox_enable,3953
```

**Temuan:** badai sekitar 100 baris (event names + channel index 1)
hanya muncul pada log boot awal. Pada log boot yang lebih baru tinggal 2x
`vote mminfra on err:1`. Event display yang diminta driver tidak ada di
`gce-event-names` stock; jangan menambah event/channel ke DT. Karena
tidak muncul lagi di log terbaru, tidak ada perubahan driver untuk
bagian itu.

**`vote mminfra on err:1`:** `pm_runtime_get_sync()` mengembalikan 1
kalau device sudah aktif. Tiga lokasi memeriksa `ret != 0` dan
menganggap 1 sebagai error. Commit `a71cfd2` mengubahnya menjadi
`ret < 0` di `cmdq-sec-mailbox.c` dan `mtk-cmdq-mailbox-ext.c`,
konsisten dengan jalur `fast_mtcmos` yang sudah memakai `ret < 0`.

**Gejala MML:**

```text
mediatek-mml 1f800000.mmlsys-config: error -EBUSY: can't request region for resource
```

**Temuan:** gejala ini tidak muncul pada log boot terbaru. Error `mml-aal` IRQ dan
`read event frame_done fail` hanya muncul pada log boot awal; di log terbaru
MML probe dan service `vendor.mmlpq-default` berjalan. Tidak ada
perubahan driver; jangan hapus node stock.

**Verifikasi build:** `mtk-cmdq-drv-ext.ko` dan `cmdq-sec-drv.ko`
mengandung pemeriksaan sign bit (`ret < 0`). `vendor_boot.img` baru
md5 `bcf3801494067a5d1cca578cdf3174c5` dan `vendor_dlkm.img` md5
`86fd65af151a1e813d132c5915686285` sudah memuatnya.

**Hasil verifikasi live (`6.18.65-android17-6-g39d19ad1a460-rama982-4k`):**
**PASS** — `0` kemunculan `vote mminfra on err` di `dmesg`; display, kamera,
codec, dan MML berjalan normal.

**Artefak gabungan thermal + DPE + CMDQ:**

| Image | Ukuran | MD5 |
|---|---:|---|
| `vendor_boot.img` | 67.108.864 B | `bcf3801494067a5d1cca578cdf3174c5` |
| `vendor_dlkm.img` | 24.551.424 B | `86fd65af151a1e813d132c5915686285` |
| `odm_dlkm.img` | 4.206.592 B | `da2c64a1572ff27382128beb4bbcba8b` (tidak berubah) |

(Image uji disimpan lokal, tidak disertakan di repo.)

`vendor_dlkm` ini juga memuat fix thermal LVTS `cbabf0ea8c34`, jadi bisa
dipakai untuk verifikasi thermal sekaligus.

### 5.4 Thermal LVTS — semua zone hilang karena tabel sensor beda dari stock

**Gejala:**

```text
mtk-soc-temp-lvts 10315000.lvts: Error: Failed to register lvts tz 26, ret = -19
Failed to get thermal zone for soc_max
Failed to get thermal zone for Vtskin-max
kernel_thermal_hint: get soc-bot0 thermal zone error   (33x)
kernel_thermal_hint: get soc-smap0 thermal zone error  (33x)
kernel_thermal_hint: get soc-smap1 thermal zone error  (33x)
```

**Hitungan zone stock X6871:**

- DTB `vendor_boot` stock: **38 zone** — 26 zone LVTS (`soc_max` id 0,
  sisanya id 1..25), 3 NTC (`ap_ntc`, `ltepa_ntc`, `nrpa_ntc`), 8 PMIC,
  dan `consys`.
- DTBO stock: menambah `camera0`, `camera1`, `camera2`, `camera4` sehingga
  total runtime stock **42 zone**.
- `soc_max` adalah zone LVTS id 0, bukan zone tambahan.

**Akar masalah:** module stock `soc_temp_lvts.ko` dari `vendor_dlkm` stock
X6871 `16.3.0.155SP20` memakai **25 sensor** LVTS:

| Controller | num_sensor | sensor_map |
|---|---|---|
| MCU CTRL0 | 4 | 0,1,2,3 |
| MCU CTRL1 | 4 | 4,5,6,7 |
| MCU CTRL2 | 4 | 8,9,10,11 |
| AP CTRL0 | 2 | 12,13 |
| AP CTRL1 | 2 | 14,15 |
| AP CTRL2 | 3 | 16,17,18 |
| AP CTRL3 | 3 | 19,20,21 |
| AP CTRL4 | 3 | 22,23,24 |

Module 6.18 hasil port memakai **26 sensor**. Di AP CTRL1 ada placeholder
`MT6895_TS6_1` di antara `TS6_0` dan `TS6_2`:

```text
AP CTRL1: num_sensor=3  sensor_map={14,15,16}  on_off={ON,OFF,ON}
AP CTRL2: num_sensor=3  sensor_map={17,18,19}
AP CTRL3: num_sensor=3  sensor_map={20,21,22}
AP CTRL4: num_sensor=3  sensor_map={23,24,25}
```

Akibatnya semua id setelah 15 bergeser +1, id 16 tidak pernah didaftarkan,
dan driver mencoba id 26. Stock DTB hanya punya zone LVTS id 0..25, jadi
`devm_thermal_of_zone_register()` untuk id 26 mengembalikan `-ENODEV` (-19).
`lvts_probe()` meneruskan error itu, lalu devres melepas zone 0..25 yang
sudah didaftarkan. Semua zone LVTS hilang; device hanya menyisakan zone
non-LVTS, sehingga jumlahnya jauh lebih sedikit dari stock.

Tabel 26 sensor yang sama juga ada di module 6.12 hasil port. Perlu dicek
apakah 6.12 juga kehilangan zone LVTS; sumber donor MT6896 memakai tabel
yang sama, jadi donor source bukan acuan untuk perilaku stock X6871.
Acuannya adalah `soc_temp_lvts.ko` stock.

**Rencana fix:**

1. Di `drivers/thermal/mediatek/soc_temp_lvts.c`, hapus `MT6895_TS6_1`
   dari enum supaya `TS7_0` kembali ke id 16, `TS8_0` ke 19, `TS9_0` ke 22,
   dan `MT6895_NUM_TS` menjadi 25.
2. Ubah AP CTRL1 menjadi `num_sensor=2`,
   `sensor_map={MT6895_TS6_0, MT6895_TS6_2}`,
   `sensor_on_off={SEN_ON, SEN_ON}`. Kalibrasi sudah cocok: `TS6_0` dari
   efuse block 10 dan `TS6_2` dari block 11; tidak ada kalibrasi `TS6_1`.
3. Tambahkan pengaman di `lvts_register_thermal_zones()`: kalau
   `devm_thermal_of_zone_register()` mengembalikan `-ENODEV` karena DT tidak
   punya zone untuk sensor itu, lewati sensor tersebut dan jangan gagalkan
   seluruh probe.
4. Jangan menambah zone thermal ke DT. Image memakai DTB/DTBO stock.

**Catatan zone opsional:** `Vtskin-max`, `mtk-master-charger`, `soc-bot0`,
`soc-smap0`, dan `soc-smap1` tidak ada di DTB/DTBO stock X6871, tetapi tetap
dicari oleh `thermal_interface` yang dipakai bersama. Log gagal untuk nama
tersebut wajar. Donor MT6897 punya 49 zone termasuk `vtskin*` dan
`soc-bot1..4`; donor MT6896 hanya 35 zone. Jangan menyalin zone donor ke
X6871.

`camera0` berbeda: zone ini memang ditambahkan DTBO stock dan bergantung
pada registrasi thermal dari driver `imgsensor`. Kalau setelah fix LVTS
`camera0` masih hilang, periksa probe/registrasi thermal `imgsensor`, bukan
DTBO.

**Verifikasi:** `/sys/class/thermal` menampilkan 38 zone base + 4 camera;
`soc_max` ada; tidak ada `Failed to register lvts tz 26`; suhu CPU/GPU/APU
valid dan berubah saat beban naik; tidak ada error `soc_max` berulang dari
`thermal_interface`.

**Hasil verifikasi live (`6.18.65-android17-6-g39d19ad1a460-rama982-4k`):**
**PASS** — `cbabf0ea8c34` (`thermal: mediatek: Align MT6895 LVTS sensor map
with stock DTB`) terkonfirmasi aktif di perangkat (`vendor_dlkm.img` md5
`c7aa223e09de1b1b50545edcb1fc0a08`):

- `Failed to register lvts tz`: **0** kemunculan di `dmesg`.
- **40 thermal zone** aktif di `/sys/class/thermal/` (seluruh 38 zone base
  stock termasuk `soc_max`, `cpu_little1..4`, `cpu_big1..6`, `cpu_bigbig1..2`,
  `gpu1..2`, `apu1..2`, `dram_ch0..3`, `soc_top`, `soc_mm`, `md1..3`, 8 PMIC,
  3 NTC, `consys`, ditambah `mt6375-gauge` dan `battery`).
- `soc_max` merespons beban kamera/rekam video secara dinamis: naik dari
  `59523` (`59.5°C`) menjadi `72562` (`72.6°C`).
- **Catatan perilaku runtime:** `apu2` mengembalikan `No data available` saat
  APU idle, dan 4 zone DTBO `camera0..2`, `camera4` tidak didaftarkan oleh
  `imgsensor` (total zone teramati tetap `40`), sementara kamera tetap
  berfungsi normal.

### 5.5 `tranhalconfig` — userspace/sepolicy

**Gejala:**

```text
SELinux: avc: denied { find } for ... tranhalconfig.ITranHalConfigService/default  (567x)
SELinux: avc: denied { find } for ... tranhalconfig.ITranHalNodeService/default    (567x)
TranFwkHalClient: Failed to connect to ITranHalConfigService get No Binder
audit: audit_lost=437
```

**Temuan:** service Transsion tidak ditemukan dan SELinux memblokir `find`
dengan target `default_android_service`. Efeknya retry terus-menerus,
`service_manager_slow`, dan audit log kehilangan event. Ini vendor
service/sepolicy, bukan kernel.

**Rencana fix:**

- Pastikan service `vendor.transsion.hardware.tranhalconfig` ada dan
  di-start.
- Beri label sepolicy yang benar dan izinkan `system_server` melakukan
  `find`.
- Kalau fitur tidak dipakai, nonaktifkan client Transsion agar tidak retry.

**Verifikasi:** lookup service berhasil, `TranFwkHalClient` tidak
`No Binder`, dan `audit_lost` tidak muncul.

**Status di boot `6.18.65`:** **masih terbuka (userspace/SELinux)** — `dmesg`
masih mencatat `222` AVC `tranhalconfig` dan `audit_lost: 21`.

### 5.6 `fpsgo`/`trans_sched`/`msync2` — module stock yang belum ada di 6.18

**Gejala:**

```text
init: Command 'insmod /vendor/lib/modules/fpsgo.ko' ... failed: No such file or directory
init: Command 'insmod /vendor/lib/modules/msync2_dms.ko' ... failed ...
init: Command 'insmod /vendor/lib/modules/msync2_frd.ko' ... failed ...
uas-service: trans sched init falied!   (50x)
uas-service: trans sched don't support!
SystemBinderSchedUxFeature: setTranSchedUxTags fail
```

**Inventaris stock vs build 6.18:**

| Module | Stock | Build 6.18 | Sumber |
|---|---|---|---|
| `mtk_fpsgo_v8.ko` | vendor_dlkm | ada, terpasang | source fpsgo_v8 |
| `fpsgo.ko` | vendor_dlkm | tidak ada | tidak ada |
| `trans_sched.ko` | odm_dlkm | tidak ada | tidak ada |
| `msync2_dms.ko` | tidak ada | tidak ada | tidak ada |
| `msync2_frd.ko` | tidak ada | tidak ada | tidak ada |

**Temuan:**

- `mtk_fpsgo_v8.ko` adalah core FPSGO dan sudah dibangun/dipasang di
  `vendor_dlkm`.
- `fpsgo.ko` stock adalah wrapper kecil (70 KB) yang bergantung pada
  `mtk_fpsgo_v8`; ia mengekspor helper touch latency/legacy FPSGO.
  Source-nya tidak ada di tree port, donor MT6896, maupun tarball MT6897.
- `trans_sched.ko` stock (518 KB) adalah fork scheduler Transsion. Modul ini
  mengisi `g_trans_sched_interface` dan membuat `/dev/trans_sched`.
  Source-nya tidak ada.
- HAL `vendor.transsion.performance.sched.ITransSched/default` membuka
  `/dev/trans_sched`. Karena module tidak ada, HAL gagal dan
  `uas-service` melaporkan `trans sched don't support!`.
- `msync2_dms.ko` dan `msync2_frd.ko` **tidak ada di firmware stock X6871**
  (`all_files` stock tidak memuatnya), walaupun init stock tetap mencoba
  `insmod`. Jadi error kedua module itu bukan regresi 6.18; jangan dikejar
  dengan menambah module palsu.

**Kenapa tidak bisa pakai stock `.ko`:** module stock dibangun untuk 6.12
(vermagic dan modversions 6.12). Tidak bisa dimuat di 6.18. Source 6.12 di
tree juga hasil port, bukan source stock.

**Keputusan pragmatis: skip di 6.18.**

- Stub hanya membuat HAL melihat `/dev/trans_sched` dan mengembalikan
  sukses. Ia tidak menjalankan scheduler Transsion. Itu bisa menipu HAL
  seolah ux tag diterapkan padahal tidak, dan tetap tidak memberi performa.
- `trans_sched` penuh membutuhkan RE fork scheduler 518 KB. Tidak sepadan
  untuk pratinjau.
- `fpsgo.ko` wrapper hanya helper touch latency/legacy. Core
  `mtk_fpsgo_v8.ko` sudah jalan; wrapper dilewati.
- `msync2_dms.ko`/`msync2_frd.ko` tidak ada di stock; dilewati.
- Log `trans sched don't support!` dan `insmod ... No such file` tidak
  menyebabkan crash. Kalau log harus bersih, matikan service/insmod di sisi
  userspace/vendor (HAL `vendor.transsion.performance.sched` dan baris init),
  bukan menambah module palsu di kernel.
- Buka lagi hanya kalau ada source resmi atau regresi performa terukur yang
  bisa dibuktikan.

**Verifikasi:** tidak ada crash dari `trans_sched`/`fpsgo`; core FPSGO
(`mtk_fpsgo_v8.ko`) tetap terpasang; log `don't support` diterima sebagai
known limitation 6.18.

### 5.7 TEE/Widevine — known limitation, sama dengan 6.12 port

**Gejala:**

```text
Trustonic TEE: GF_ERROR_OPEN_SECURE_OBJECT_FAILED  (59x)
Trustonic TEE: WARNING: insecure default Trustonic key detected for TA signature.
device_authen_ta: gp_read_raw g_device_key err=-65528
tdrv_drmhdcpcommon drDcihInit(): drApiStartThread failed: 0x6f03
tdrv_widevine      drDcihInit(): drApiStartThread failed: 0x6f03
```

**Status stack TEE di 6.18:**

- `mcDrvModule`, `teeperf`, `trusted_mem`, `gz_*`, `widevine_driver`,
  `sec`, `iommu_secure`, dan `cmdq_sec_drv` termuat.
- `TAFileServer Kinibi-MediaTek-Android-700a-V010` berjalan. Gatekeeper,
  KeyMint, dan TA fingerprint bisa membuka session.
- `TEESimulator` mencatat KeyMint `from=real-hal rc=0`; jalur TEE KeyMint
  nyata berfungsi.
- HAL `vendor.drm-widevine-hal` tetap hidup; `liboemcrypto` memuat dan
  mencetak BRM commit ID. Tidak ada service death atau crash.
- Logcat memuat module `teesim`/`playintegrityfix`; perangkat berjalan di
  lingkungan root. Play Integrity/attestation tidak bisa dijadikan acuan
  paritas stock selama kondisi ini.

**Arti error:**

| Log | Arti |
|---|---|
| `mcp_cmd ... res 33` | `MC_MCP_RET_ERR_SYSTEM_NOT_READY`; TEE OS belum siap saat service awal, berhenti setelah boot |
| `mcp_cmd ... res 8` | `MC_MCP_RET_ERR_INVALID_PARAM`; satu open session ditolak, bukan kegagalan driver |
| `GF_ERROR_OPEN_SECURE_OBJECT_FAILED` (59x) | TA fingerprint mencari `finger_*.so` yang belum ada; wajar sebelum enrollment |
| `insecure default Trustonic key` | TA ditandatangani/diverifikasi dengan default key; kondisi provisioning TEE/device |
| `gp_read_raw g_device_key err=-65528` | `0xFFFF0008` = `TEE_ERROR_ITEM_NOT_FOUND`; device key belum diprovision |
| `drApiStartThread failed: 0x6f03` | Thread DCIH di TA DRM stock gagal dibuat; terjadi di TA, bukan di `widevine_driver` kernel |

**Perbandingan 6.12 ke 6.18:** dmesg 6.12 port (`6.12.117...Rama982`,
log boot 2026-11-21) memuat pola yang sama: `res 33` berulang, satu
`res 8`, dua `drDcihInit ... 0x6f03`, `gp_read_raw ... -65528`, dan
`insecure default`. Jadi pola ini bukan regresi 6.18. Log runtime stock
X6871 tidak tersedia, jadi paritas dengan stock belum bisa dibuktikan
dari log; yang bisa dipastikan adalah 6.12 port berperilaku sama.

**Perbedaan driver:** stock X6871 6.12 memakai `mcDrvModule`
`Kinibi-FFA-A-700a-V010`, build kita `V008`; stock X6867 6.18 memakai
`V013`. Tetapi 6.12 port juga memakai `V008` dengan log identik, dan source
`V010`/`V013` tidak tersedia. `widevine_driver.ko` build kita byte-identik
dengan stock X6867 6.18. Jadi tidak ada perubahan kernel yang bisa
dibenarkan hanya dari log ini. Buka lagi opsi update GUD hanya kalau ada
regresi L1 terukur dan source `V010`/`V013` tersedia.

**Keputusan pragmatis: skip perubahan kernel; catat known limitation.**

- `device_authen`/Play Integrity dan Widevine L1 bergantung pada
  provisioning pabrik (device key, keybox Widevine, status bootloader),
  bukan DT atau driver kernel.
- `drDcihInit` gagal di TA stock; tidak ada source TA/kernel yang bisa
  diperbaiki di tree ini.
- Jangan menambah stub TA/module atau memalsukan device key.
- Kalau L1 wajib, perlu provisioning vendor (SP Meta/DRM key install)
  dan bootloader terkunci; itu di luar scope kernel 6.18.

**Verifikasi:** `DRM Info` menunjukkan level Widevine; playback DRM
berjalan sesuai level yang tersedia. `gp_read_raw`, `insecure default`,
dan `drDcihInit` boleh tetap muncul sebagai known limitation selama tidak
ada crash dan level DRM sesuai kebijakan perangkat.

**Status di boot `6.18.65`:** cek `DRM Info` dan playback DRM **belum
dijalankan ulang** pada sesi uji terbaru.

### 5.8 Touch (`gt9916_common` + `adaptive-ts`) — dynamic report rate, `tppolldrv`, dan charger anti-noise

**Gejala:** pergerakan sentuh di port terasa kurang mulus dibandingkan stock
pada panel 120/144 Hz meskipun kecepatan SPI (`8 MHz`), resolusi 16x, dan
firmware/config Goodix sudah sama.

**Akar masalah (audit biner stock X6871 `16.3.0.155SP20`):**

- DTBO stock mengaktifkan `touchscreen,dynamic-report-rate-support`,
  `touchscreen,pocket-mode-amt-support`, dan
  `touchscreen,fingerprint-support`.
- HAL userspace stock `vendor.hardware.trantp-service` (`ITrantp`) berinteraksi
  dengan `/proc/report_rate_switch`, `/proc/tp_report_rate_switch`,
  `/proc/border_suppression`, dan char device `/dev/tppolldrv` (`_IOR`/`_IOW`
  magic `'t'`, struct 260 B).
- Port sebelumnya tidak memiliki endpoint kontrol tersebut di `adaptive-ts.ko`,
  belum mengimplementasikan `set_ts_mode()` dan command report rate
  240/360 Hz (`0x9d`/`0xc0`/`0x27`/`0x17`) di `gt9916_common.ko`, belum
  memulihkan state pasca-resume, dan membiarkan `charger_work` tidak terpasang ke
  `power_supply_reg_notifier()`.

**Fix:**

1. `004169f83006` (`adaptive-ts`): parsing properti DT stock, tambah
   `set_ts_mode()` ke `struct tran_controller_ops`, ekspos
   `/proc/tp_report_rate_switch`, `/proc/border_suppression` (serta node DT-gated
   esports/edge-level), daftarkan `/dev/tppolldrv` ioctl, dan jalankan
   `tp_state_recovery()` saat resume display.
2. `92c5a6f9d3f3` (`gt9916_common`): implementasi switch 240/360 Hz (`0x9d`/
   `0xc0`), `goodix_report_rate_switch` (`0x27`), edge restrain (`0x17`), game
   state/lock point (`0x33`), super-idle sampling (`0xc2`), edge level (`0x36`),
   `/proc/report_rate_switch` (0666), serta restore mode 360 Hz di
   `goodix_ts_resume()`.
3. `80f4abf529e2` (`gt9916_common`): pasang `power_supply_reg_notifier()` pada
   supply `"battery"` untuk mengirim command anti-noise charger (`0xaf`) dan
   memulihkannya saat resume ketika terpasang charger.

*(Catatan: `fpsgo.ko` dan `trans_sched.ko` tetap menjadi known limitation
terpisah di 6.18 pada §5.6.)*

**Artefak teruji (`6.18.65-android17-6-g39d19ad1a460-rama982-4k`):**
lihat MD5 set 5 image pada §5.1 (lulus 8/8 `verify-kmi-abi.py`, 487 modul
runtime, `9.843` simbol ABI).

**Hasil verifikasi live (`6.18.65`) — PASS:**

- Seluruh node kontrol aktif dan service `vendor.hardware.trantp-service`
  berjalan: `/dev/tppolldrv`, `/proc/report_rate_switch`,
  `/proc/tp_report_rate_switch`, `/proc/border_suppression`.
- Charger anti-noise + restore pasca-resume **PASS** dengan `0`
  `failed send charger_cmd` maupun `GTP-ERR`:

```text
[  491.662382] [GTP-INF][goodix_ts_resume:2067] resume restore charger mode
[  531.538445] [GTP-INF][mtk_power_misc_psy_event:99] charger mode out
[  535.334302] [GTP-INF][mtk_power_misc_psy_event:93] charger mode in
```

- Pengukuran `getevent -lt` pada `mtk-tpd` (`/dev/input/event5`, resolusi 16x
  `0..17279`):
  - Baseline awal (`0`): `234` `SYN_REPORT` / `225` interval valid,
    `median_dt=2.846ms` (`351.4 Hz`), `mean_dt=3.521ms` (`284.0 Hz`)
  - Setelah `echo 0 > /proc/report_rate_switch`: `223` / `215`,
    `median_dt=2.839ms` (`352.2 Hz`), `mean_dt=3.264ms` (`306.4 Hz`)
  - Setelah `echo 1 > /proc/report_rate_switch`: `215` / `207`,
    `median_dt=2.826ms` (`353.9 Hz`), `mean_dt=3.255ms` (`307.2 Hz`)
  - `0` error perintah Goodix (`failed send 240hz` / `failed send 360hz` /
    `GTP-ERR`: `0`); log resume mencatat
    `[GTP-INF][goodix_report_rate_switch:191] Enter 0 game report rate successful!`.
  - Nilai `/proc/report_rate_switch` dikembalikan ke `0`.
- **Belum diuji terpisah:** pengukuran ulang recovery report rate sesudah
  sleep/wake khususnya pada kondisi `report_rate_switch=1`.
- **Periferal lain terkonfirmasi aktif pada sesi yang sama:** `aw22xxx_led`
  (`3-006a`), `fs15xx` (`6-0034`/`6-0035`), `hl7139a` (`1-0055`/`7-0055`),
  `fuelgauged` (`charge_full=5000000`, `Charging`), `/dev/goodix_fp`,
  `/dev/aw8697_haptic`, dan `/dev/pn553`.

## 6. Error Minor/Rendah

Hasil analisa seluruh 11 item error minor dari log boot `6.18`, source tree,
DTB/DTBO stock, dan biner `.ko` stock SP20:

| Gejala | Status & Tindakan | Catatan Akar Masalah |
|---|---|---|
| `INFO: task hf_manager:788 blocked for more than 307 seconds.` / `INFO: task mml_work1:8470 blocked for more than 307 seconds.` | **Terverifikasi PASS di device (`7d92fc24ce41`, `611ad1f`)** | Bug semantik API 6.18 (`kthread_run_worker()`): seluruh worker `[mml_work0]`, `[mtk_drm_bind]`, `[hf_manager]`, `[kbase_pm_poweroff_wait]` aktif di state `S` (`kthread_worker_fn`), `0` worker di `D`, `blocked for more than: 0` |
| `proc_dir_entry '/proc/mtk_typec' already registered` | **Terverifikasi PASS di device (`112de113630b`, `587a0a7`)** | `already registered: 0`; `/proc/mtk_typec/mux_switch/{mux,switch}` & `/proc/mtk_typec/smt_u2_cc_mode = 0` terbentuk (`tran_usb_extcon_procfs_init ret:0`) |
| `get pmic_node fail` (23x) | **Skip (paritas stock)** | `tc_pmic` mencari phandle `"pmic"`; DTBO stock `fragment@37` tidak menyertakannya dan `tc_pmic.ko` stock identik |
| `pe50_is_ta_rdy: all support sepc auth fail` (16x) | **Skip (perilaku normal)** | `PE50_INFO` normal di `tc_pe5.c` saat adaptor non-PPS / USB PC |
| `mtk_emimpu_set_apc: fail, out-of-range domain`, `[SCP] chre memory reserve fail` | **Skip (paritas stock)** | String sama ada di `emi-mpu.ko` stock; memori reserved CHRE memang `size = 0` di konfigurasi stock X6871 |
| `wait_for_md_on_complete timeout`, `mddp is not supported` | **Skip (non-fatal)** | Jalur MDDP WLAN (`mddp.c`) tidak aktif; Wi-Fi dan data seluler berjalan normal via AP |
| `GPU/FREQ ... fail to set STACK limiter: 12` | **Skip (transient)** | Limiter `12` (`LIMIT_POWERHAL` di `gpufreq_v2.c`) dipanggil sebelum GPUEB/DVFS siap saat boot |
| `mtu3 ... failed to start g1: -22` | **Skip (transient)** | `-EINVAL` pada `drivers/usb/gadget/udc/core.c` karena urutan configfs saat `init`; retry otomatis berhasil |
| `fgauged: open .../cus_save_data fail`, `nv_fail(1)` | **Skip (userspace)** | Daemon `fuelgauged` saat file kalibrasi kustom belum tersedia; pengisian baterai normal |
| `healthd: battery...Path not found` | **Skip (userspace / kosmetik)** | Health HAL mencari properti opsional yang tidak ada di DT stock |
| `WARNING: CPU ... rcu_note_context_switch`, `Workqueue: ... susfs_guard_lkm` | **Skip (modul pihak ketiga)** | Berasal dari modul root KernelSU/SUSFS, bukan source port kernel |

Build gabungan fix minor (`6.18.65-android17-6-g39d19ad1a460-rama982-4k`, 487
modul runtime, `9.843` simbol ABI) lolos **8/8** `verify-kmi-abi.py`
(`vendor_boot.img` md5 `5395e3faaf9ed636177e2a0b45e941a7`, `vendor_dlkm.img`
`540b0a7cda2cf90ed2197ee061f1be78`, `odm_dlkm.img`
`c1f97ae3fe5cf030f2b9e3e416055e58`) dan **PASS** pada uji boot langsung di
perangkat (`495` modul termuat, `already registered: 0`, `blocked for more than: 0`):

```text
[    6.744200] tran-extcon-usb extcon_usb: success creating proc file: smt_u2_cc_mode
[    6.744203] tran-extcon-usb extcon_usb: tran_usb_extcon_procfs_init ret:0
```

## 7. Verifikasi Setelah Fix

Status verifikasi pada uji live `6.18.65-android17-6-g39d19ad1a460-rama982-4k`:

1. Build dan flash dengan DTB/DTBO stock (`dtb` byte-identical, `dtbo.img`
   stock) — **PASS**.
2. Boot normal dan periksa log kernel (`dmesg`) — **PASS**.
3. Tidak ada `Internal error`, `WARNING: CPU`, `rcu_preempt detected stalls`,
   maupun `[MIUMPU]srinfo_r 3` — **PASS** (semuanya `0` kemunculan). Pada boot
   segar `t=5.77s`, ADSP mencatat 1x `adsp_system_bootup fail ret(-14)` + 80x
   `invalid cid` saat init karena DTB stock `disabled` (`total 0` core) lalu
   berhenti; audio normal.
4. Video VP8, VP9, dan AV1: `25` sesi `Init Vdec OK bs VP90`, plus uji
   decode hardware VP8 720p (`c2.mtk.vpx.decoder`, 120/120 frame, `132.0 fps`)
   dan AV1 720p/1080p (`c2.mtk.av1.decoder`, 120/120 frame, `228.0 / 110.5 fps`),
   `0` error/penolakan codec — **PASS**.
5. Tidak ada `v4l2_open` WARN (`0`) dan `vote mminfra on err:1` (`0`); kamera,
   AIE, flashlight, encoder 1080p@30fps, codec, dan MML berjalan — **PASS**.
6. `/sys/class/thermal`: `40` zone aktif (38 base stock + `mt6375-gauge` +
   `battery`), `soc_max` valid dan responsif (`59.5°C` -> `72.6°C`), `0`
   `Failed to register lvts tz` — **PASS** (catatan: `apu2` `No data available`
   saat idle, `camera0..4` belum didaftarkan `imgsensor`).
7. Service `tranhalconfig` — **masih terbuka (userspace/SELinux)**: `222`
   AVC dan `audit_lost: 21`.
8. Tidak ada crash dari `trans_sched`/`fpsgo`; `mtk_fpsgo_v8.ko` tetap
   terpasang — **PASS** (known limitation 6.18).
9. Cek level Widevine dengan `DRM Info` & playback DRM — **belum dicek ulang**
   pada boot `6.18.65`.
10. Touch GT9916: 4 node kontrol + `vendor.hardware.trantp-service` aktif,
    `getevent -lt` terukur `~352–354 Hz`, `charger mode in/out` & `resume restore charger mode`
    tanpa `failed send charger_cmd` — **PASS** (recovery pasca sleep/wake
    pada `report_rate_switch=1` **belum diukur terpisah**).

## 8. Urutan Kerja yang Disarankan

| Prioritas | Pekerjaan | Status / Alasan |
|---|---|---|
| P0 | Verifikasi crash/EMI pasca-fix dengan log baru | **Selesai (PASS di `6.18.65`)** — 7 Oops + RCU stall + EMI `0` kemunculan |
| P0 | Video VP9 / VP8 / AV1 | **Selesai (PASS di `6.18.65`)** — VP9, VP8 720p, dan AV1 720p/1080p terverifikasi PASS (`0` error) |
| P1 | Pastikan DTB/DTBO stock yang dipakai, bukan DT tree | **Selesai (PASS di `6.18.65`)** — ADSP `disabled` sesuai stock |
| P1 | Thermal LVTS: verifikasi fix di device | **Selesai (PASS di `6.18.65`)** — 40 zone aktif, `soc_max` responsif |
| P1 | `tranhalconfig` | **Terbuka (userspace)** — `222` AVC & `audit_lost: 21`, perlu fix vendor/sepolicy |
| P1 | DPE `v4l2_fh`: verifikasi fix isp_70 di device | **Selesai (PASS di `6.18.65`)** — `0` `v4l2_open` WARN |
| P1 | Touch GT9916 (`adaptive-ts` + `gt9916_common`) | **PASS di `6.18.65`**; sisa ukur recovery sleep/wake pada `report_rate_switch=1` |
| P2 | Widevine `DRM Info` & playback DRM | **Belum dicek ulang di `6.18.65`** (non-kernel / known limitation) |
| P3 | CMDQ `vote mminfra`: verifikasi di device | **Selesai (PASS di `6.18.65`)** — `0` `vote mminfra on err` |
| P3 | `trans_sched`/`fpsgo` wrapper: skip | **Skip** — stub tidak memberi fungsi; full RE terlalu besar |
| P3 | TEE/Widevine: skip perubahan kernel | **Skip** — bukan regresi 6.18; butuh provisioning vendor |
| P3 | Error minor | **2 bug kernel PASS di `6.18.65`** (`7d92fc24ce41`, `611ad1f`, `112de113630b`); 9 item lain di-skip |

## 9. Batasan dan Catatan

- Hasil verifikasi live pada `6.18.65-android17-6-g39d19ad1a460-rama982-4k`
  sudah menutup temuan crash, ADSP, VP8/VP9/AV1, DPE, CMDQ, thermal LVTS, dan
  touch di atas; pengujian yang belum dijalankan (`DRM Info` Widevine dan
  recovery sleep/wake `report_rate_switch=1`) tetap dicatat eksplisit.
- Dokumen ini tidak mengubah kode. Perubahan tetap harus melalui commit baru
  sesuai aturan commit di `AGENTS.md` (prefix `6.18:` di manifest; format
  kernel dengan akhiran `for 6.18` di repo kernel/vendor bila khusus 6.18).
- DT di tree tidak dipakai untuk image. `tools/repack-vendor-boot-latest.sh`
  dan `tools/pack-vendor-boot.sh` mempertahankan `dtb` stock secara
  byte-identical. Jangan mengubah `mt6895.dts` untuk mengejar error log.
- Jangan mengubah node yang disabled di DTB/DTBO stock. Kalau sebuah fitur
  tidak ada di stock, jangan diaktifkan hanya untuk menghilangkan log.
- Analisis thermal memakai `soc_temp_lvts.ko` stock X6871
  `16.3.0.155SP20` dari dump GitLab. Source 6.12 di tree adalah hasil port,
  bukan source stock, jadi tabel sensornya tidak boleh dijadikan acuan
  perilaku stock.
- Code warning checkpatch, DOS line endings, dan MAINTAINERS di luar scope
  dokumen ini.
- `audit_lost=437` berarti sebagian denial SELinux mungkin tidak terlihat;
  setelah `tranhalconfig` dibereskan, audit perlu dicek ulang.
