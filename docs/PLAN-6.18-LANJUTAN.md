# PLAN 6.18 Lanjutan — Temuan Log dan Prioritas Perbaikan

Diperbarui: 2026-11-24 (UTC)

> Dokumen ini adalah lanjutan dari [`PLAN-6.18-STATUS.md`](PLAN-6.18-STATUS.md).
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
| Oops/panic/RCU stall | **Ada fix, belum diverifikasi** | Ambil log baru setelah semua fix |
| EMI MPU `SRINFO=3` + RCU stall | **Fixed** oleh commit IOMMU | Verifikasi tidak muncul lagi |
| ADSP | **Bukan bug; stock DTB disabled** | Pastikan image memakai DTB stock; jangan ubah DT tree |
| Video VP9 | **Terbuka** | Verifikasi fix `7c48ebd`, lanjutkan jika masih gagal |
| DPE `v4l2_fh` | **Fixed di isp_70; uji device tertunda** | `v4l2_fh` ditambahkan; build lolos |
| CMDQ/GCE + MML | **`vote mminfra` fixed; event/MML historis** | Build lolos; verifikasi device tertunda |
| Thermal `lvts`/`soc_max` | **Fixed, build lolos; uji device tertunda** | Tabel sensor disamakan dengan stock ko; maintainer sedang di luar |
| `tranhalconfig` | **Terbuka, userspace** | Service/sepolicy vendor, bukan kernel |
| `fpsgo`/`trans_sched` | **Known limitation; skip di 6.18** | Jangan buat stub palsu; core FPSGO tetap jalan |
| TEE/Widevine | **Known limitation; sama dengan 6.12 port** | Provisioning/TA, bukan DT atau driver kernel |
| Error minor | **Rendah** | Catat, tangani setelah prioritas utama |

Tidak ada `am_crash` atau `am_anr` di logcat yang dianalisis. Yang ada hanya
`am_wtf`, service lookup lambat, dan proses background mati normal. Semua log
dibuat **sebelum** fix terakhir, jadi status "fixed" di bawah berarti "ada
commit yang cocok", bukan "sudah terbukti hilang di boot baru".

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

**Verifikasi yang dibutuhkan:** boot baru setelah semua commit, lalu cek:

```text
Internal error
WARNING: CPU
rcu_preempt detected stalls
[MIUMPU]srinfo_r 3
```

Kalau semuanya tidak muncul, tabel crash bisa ditutup.

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

**Verifikasi:** pada boot dengan DTB stock, `adsp_system_bootup fail` dan
`invalid cid` tidak muncul; audio speaker/earpiece, kabel, dan Bluetooth
tetap berfungsi.

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
  `VDEC_VENC_MAX = 20` tanpa mengubah ID `VENC_H264..VENC_H263` (build dan
  uji perangkat belum dijalankan).

**Rencana fix:**

1. Jangan menambah patch spekulatif lagi di sisi AP sebelum ada bukti dari
   sisi VCP.
2. Tangkap log sisi VCP (`mtk_vdec_vcp_log`) saat VP9 ditolak untuk melihat
   alasan firmware mengembalikan `changed=0x4` pada frame Profile 0.
3. Bandingkan A/B satu sampel VP9 yang sama antara stock SP20 dan port 6.18
   dengan `mtk_v4l2_dbg_level=3` (`DEC_START_DONE`, device DMA, dan rentang
   IOVA bitstream/working buffer).
4. Setelah playback VP9 lulus, update status video di README dan dokumen
   status.

**Verifikasi:** playback VP9 selesai, tidak ada error qbuf, dan decoding
tidak berhenti di tengah. (Uji build/repack untuk `213a184315ef` dan
`a719a23cee6d` belum dilakukan.)

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

**Verifikasi device (tertunda):** boot baru harus tidak lagi mencetak
`v4l2_open` WARN; kamera dan playback codec tetap berjalan.

### 5.3 CMDQ/GCE dan MML — `vote mminfra` fixed; sisanya historis

**Gejala CMDQ:**

```text
[cmdq][err] no gce-event-names property or no such event:disp_ovlsys_wdma0_eof0
[cmdq][err] no gce-event-names property or no such event:disp_mdp_rdma0_eof0
[cmdq][err] channel request fail:-2 idx:1 @cmdq_mbox_create,511
[cmdq][err] vote mminfra on err:1 @cmdq_mbox_enable,3953
```

**Temuan:** badai sekitar 100 baris (event names + channel index 1)
hanya muncul di dmesg1/3/4. Di dmesg2/5/6/7 yang lebih baru tinggal 2x
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

**Temuan:** gejala ini tidak ada di dmesg1-7. Error `mml-aal` IRQ dan
`read event frame_done fail` hanya muncul di dmesg1/4; di log terbaru
MML probe dan service `vendor.mmlpq-default` berjalan. Tidak ada
perubahan driver; jangan hapus node stock.

**Verifikasi build:** `mtk-cmdq-drv-ext.ko` dan `cmdq-sec-drv.ko`
mengandung pemeriksaan sign bit (`ret < 0`). `vendor_boot.img` baru
md5 `bcf3801494067a5d1cca578cdf3174c5` dan `vendor_dlkm.img` md5
`86fd65af151a1e813d132c5915686285` sudah memuatnya.

**Verifikasi device (tertunda):** boot baru tidak lagi mencetak
`vote mminfra on err:1`; display, codec, dan MML tetap berjalan.

**Artefak gabungan thermal + DPE + CMDQ:**

| Image | Ukuran | MD5 |
|---|---:|---|
| `vendor_boot.img` | 67.108.864 B | `bcf3801494067a5d1cca578cdf3174c5` |
| `vendor_dlkm.img` | 24.551.424 B | `86fd65af151a1e813d132c5915686285` |
| `odm_dlkm.img` | 4.206.592 B | `da2c64a1572ff27382128beb4bbcba8b` (tidak berubah) |

Unduhan: https://gofile.io/d/kV60pldu

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

**Status implementasi:** fix sudah masuk commit
`cbabf0ea8c34` (`thermal: mediatek: Align MT6895 LVTS sensor map with
stock DTB`). Build 6.18 berhasil, dan tabel `mt6895_tc_settings` di
`soc_temp_lvts.ko` hasil build sudah cocok dengan stock: 25 sensor, map
berakhir di id 24, sehingga driver mendaftarkan zone id 1..25. Image
`vendor_dlkm` sudah direpack dengan 209 modul. Belum diuji boot di device;
pengujian runtime ditunda karena maintainer sedang di luar. Image gabungan
terbaru di §5.3 (md5 `86fd65af151a1e813d132c5915686285`) juga memuat fix
ini.

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
`dmesg4.txt` 2026-11-21) memuat pola yang sama: `res 33` berulang, satu
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

## 6. Error Minor/Rendah

| Gejala | Catatan |
|---|---|
| `proc_dir_entry '/proc/mtk_typec' already registered` | `mux_switch` dan `tran_extcon_usb` membuat direktori proc yang sama; salah satu gagal membuat `smt_u2_cc_mode` |
| `get pmic_node fail` (23x) | Voting charger; charging tetap jalan |
| `pe50_is_ta_rdy: all support sepc auth fail` (16x) | Fast charging tetap jalan |
| `fgauged: open .../cus_save_data fail`, `nv_fail(1)` | Kalibrasi battery gauge tidak terbaca |
| `mtu3 ... failed to start g1: -22` | USB gadget gagal start sekali, lalu retry dan jalan |
| `GPU/FREQ ... fail to set STACK limiter: 12` | GPU tetap jalan |
| `wait_for_md_on_complete timeout`, `mddp is not supported` | MDDP tidak aktif; WiFi tetap jalan |
| `WARNING: CPU ... rcu_note_context_switch`, `Workqueue: ... susfs_guard_lkm` | Modul KernelSU/SUSFS, bukan port kernel |
| `mtk_emimpu_set_apc: fail, out-of-range domain`, `[SCP] chre memory reserve fail` | Isu SCP CHRE terpisah, bukan EMI violation `SRINFO=3` yang sudah difix |
| `healthd: battery...Path not found` | Node health/battery tidak ada di DT; sebagian kosmetik |

## 7. Verifikasi Setelah Fix

Urutan verifikasi yang disarankan:

1. Build dan flash dengan DTB/DTBO stock. Repack `vendor_boot` harus
   mempertahankan `dtb` byte-identical dengan stock; jangan memakai DTB
   hasil build tree. `dtbo.img` juga tetap stock.
2. Boot normal, ambil `dmesg`, `pstore`, dan `logcat` baru.
3. Cek tidak ada:

   ```text
   Internal error
   WARNING: CPU
   rcu_preempt detected stalls
   [MIUMPU]srinfo_r 3
   adsp_system_bootup fail
   invalid cid
   ```

4. Cek video VP9: tidak ada `VP9 header rejected`, `unsupported (-1,-1)`,
   atau `QBUF after unrecoverable error`.
5. Cek warning `v4l2_open` sudah hilang dan tidak ada
   `vote mminfra on err:1`; pastikan kamera, playback codec, dan MML
   tetap berjalan.
6. Cek `/sys/class/thermal`: jumlah zone sesuai stock (38 base + 4 camera),
   `soc_max` ada, suhu valid, dan tidak ada `Failed to register lvts tz 26`.
7. Cek service `tranhalconfig` ditemukan; tidak ada `audit_lost`.
8. Cek tidak ada crash dari `trans_sched`/`fpsgo`. Log
   `trans sched don't support!` diterima sebagai known limitation 6.18;
   `msync2` juga tidak ada di stock.
9. Cek level Widevine dengan `DRM Info`, lalu jalankan playback DRM.
   `gp_read_raw`, `insecure default`, dan `drDcihInit` diterima sebagai
   known limitation 6.18; yang penting tidak ada crash dan level DRM
   sesuai kebijakan perangkat.

## 8. Urutan Kerja yang Disarankan

| Prioritas | Pekerjaan | Alasan |
|---|---|---|
| P0 | Verifikasi crash/EMI pasca-fix dengan log baru | Memastikan 7 Oops + RCU stall benar-benar hilang |
| P0 | Video VP9 | Isu user-facing yang masih terbuka |
| P1 | Pastikan DTB/DTBO stock yang dipakai, bukan DT tree | ADSP dan node disabled lain tidak relevan untuk DT tree |
| P1 | Thermal LVTS: verifikasi fix di device | Tabel sensor sudah disamakan dengan stock ko; build lolos |
| P1 | `tranhalconfig` | Log storm, audit loss, dan lookup lambat |
| P1 | DPE `v4l2_fh`: verifikasi fix isp_70 di device | Build lolos; warning seharusnya hilang |
| P3 | CMDQ `vote mminfra`: verifikasi di device | Fix false-positive; event/MML historis |
| P3 | `trans_sched`/`fpsgo` wrapper: skip | Stub tidak memberi fungsi; full RE terlalu besar |
| P3 | TEE/Widevine: skip perubahan kernel | Bukan regresi 6.18; butuh provisioning vendor |
| P3 | Error minor | Bersihkan setelah prioritas utama selesai |

## 9. Batasan dan Catatan

- Semua log yang dianalisis dibuat sebelum fix terakhir. Belum ada bukti
  runtime setelah commit.
- Dokumen ini tidak mengubah kode. Perubahan tetap harus melalui commit
  `6.18:` di repo yang sesuai.
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
