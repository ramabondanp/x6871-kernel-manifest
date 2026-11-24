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
| DPE `v4l2_fh` | **Terbuka** | Perbaiki driver atau lepas node V4L2 DPE |
| CMDQ/GCE + MML | **Noise, prioritas rendah** | Jangan tambah event DT; perbaiki fallback driver |
| Thermal `lvts`/`soc_max` | **Terbuka** | Periksa registrasi `lvts`, jangan tambah zone |
| `tranhalconfig` | **Terbuka, userspace** | Service/sepolicy vendor, bukan kernel |
| `fpsgo`/`msync2` | **Terbuka, build/init** | Tambah module atau hapus `insmod` |
| TEE/Widevine | **Terbuka, vendor security** | Provisioning/TA/HDCP, bukan DT |
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
vdec_vcp_decode() VP9 header rejected: changed=0x4 payload=... length=... offset=0 flags=0x0
vb2ops_vdec_buf_queue: Error!! Codec driver not support the file!
vidioc_vdec_qbuf: Call on QBUF after unrecoverable error   (15x)
mtk_vdec_g_v_ctrl: Error!! Cannot get param                (7x)
```

**Temuan:** logcat menunjukkan `c2.mtk.avc.decoder` (H.264) start/stop
normal. Yang gagal spesifik jalur VP9. Fix `7c48ebd` menambah sync DMA-BUF
header VP9 sebelum VCP `DEC_START`, tetapi belum ada log setelah commit itu.

**Rencana fix:**

1. Build dengan `7c48ebd`, ulangi playback file VP9 yang sama.
2. Cek apakah `VP9 header rejected`, `unsupported (-1,-1)`, dan
   `QBUF after unrecoverable error` masih muncul.
3. Kalau masih: periksa `vdec_vcp_if.c`, terutama nilai `changed=0x4`,
   `payload`, `length`, `offset`, dan `flags`; bandingkan dengan donor dan
   pastikan cache/IOMMU header sudah sinkron.
4. Kalau hilang: update status video di README dan dokumen status.

**Verifikasi:** playback VP9 selesai, tidak ada error qbuf, dan decoding
tidak berhenti di tengah.

### 5.2 DPE `v4l2_fh` — warning 2x per boot

**Gejala:**

```text
WARNING: CPU: ... at drivers/media/v4l2-core/v4l2-dev.c:438 v4l2_open+...
```

**Temuan:** 6.18 mewajibkan driver V4L2 memakai `v4l2_fh`. Di
`camera_dpe.c`, `dpe_fop_open()` hanya memanggil `DPE_open()` lalu
`return 0`, tanpa `v4l2_fh_init()`. Akibatnya node video DPE ditolak
`-ENODEV`. Kamera masih berjalan lewat char device `/dev/DPE`, jadi ini
bukan penyebab kamera mati, tetapi node V4L2 DPE tidak bisa dipakai.

**Rencana fix:**

- Opsi A: tambahkan lifecycle `v4l2_fh` di DPE dengan wrapper yang tidak
  merusak `file->private_data` milik `DPE_USER_INFO_STRUCT`.
- Opsi B: jangan daftarkan node V4L2 DPE jika memang tidak dipakai; cukup
  char device.

Jangan asal memanggil `v4l2_fh_open()` karena DPE memakai
`file->private_data` untuk state sendiri; perlu penyesuaian ioctl.

**Verifikasi:** warning `v4l2_open` hilang; open node DPE mengembalikan 0;
kamera dan DPE tetap berfungsi.

### 5.3 CMDQ/GCE dan MML — noise, prioritas rendah

**Gejala CMDQ:**

```text
[cmdq][err] no gce-event-names property or no such event:disp_ovlsys_wdma0_eof0
[cmdq][err] no gce-event-names property or no such event:disp_mdp_rdma0_eof0
[cmdq][err] channel request fail:-2 idx:1 @cmdq_mbox_create,511
[cmdq][err] vote mminfra on err:1 @cmdq_mbox_enable,3953
```

**Temuan:** 101 baris error CMDQ pada satu boot penuh. `gce-event-names` di
DT stock memang hanya berisi subset; driver display 6.18 meminta event yang
lebih banyak. `cmdq_mbox_create(..., 1)` meminta channel kedua, sedangkan
node GCE stock hanya punya satu entri `mboxes`.

**Rencana fix:**

- Jangan menambah event atau channel baru ke DT. DT di tree tidak dipakai
  untuk image, dan DTB stock memang hanya punya subset tersebut.
- Di driver, tangani `-ENOENT` saat channel hw trace tidak tersedia; jangan
  request index 1 jika `hw_trace_built_in` tidak aktif.
- Untuk event yang tidak ada, pastikan driver tetap memakai fallback dan
  tidak menganggapnya fatal.

**Gejala MML:**

```text
mediatek-mml 1f800000.mmlsys-config: error -EBUSY: can't request region for resource
```

**Temuan:** `syscon@1f800000` dan `mmlsys-config@1f800000` memakai region
yang sama. Ini juga ada di DT stock. MML tetap `probe success`, jadi ini
lebih ke perilaku driver 6.18 daripada node DT yang hilang. DT tree tidak
dipakai untuk image, jadi fix harus di driver.

**Rencana fix:** gunakan syscon/regmap atau fallback `devm_ioremap` untuk
region yang sudah diklaim; jangan menghapus node stock.

**Prioritas:** rendah, kecuali muncul gejala MML/video yang spesifik.

### 5.4 Thermal `lvts`/`soc_max` — prioritas menengah

**Gejala:**

```text
mtk-soc-temp-lvts 10315000.lvts: Error: Failed to register lvts tz 26, ret = -19
Failed to get thermal zone for soc_max
kernel_thermal_hint: get soc-bot0 thermal zone error   (33x)
kernel_thermal_hint: get soc-smap0 thermal zone error  (33x)
kernel_thermal_hint: get soc-smap1 thermal zone error  (33x)
```

**Temuan:** DT stock hanya punya `soc_max`, bukan `soc-bot0/smap/Vtskin/
charger/camera0`. DT tree juga tidak dipakai untuk image, jadi jangan tambah
zone di tree. Tetapi `soc_max` ada di stock dan tetap gagal ditemukan, plus
`lvts tz 26` gagal register. Ini kemungkinan masalah driver `lvts` 6.18 atau
konfigurasi thermal HAL, bukan DTBO. Pembacaan thermal userspace bisa
`-274000` (invalid), sehingga thermal throttling dan charging limit perlu
dicek.

**Rencana fix:**

1. Cek `/sys/class/thermal` di device: apakah `soc_max` terdaftar dan
   tipenya sesuai.
2. Periksa `lvts` probe: mengapa tz 26 gagal `-19`; apakah ada sensor yang
   tidak ada di DT.
3. Periksa konfigurasi thermal HAL vendor; jangan menambah zone baru.

**Verifikasi:** `thermal_core` bisa membaca `soc_max` dan suhu tidak
`-274000`; tidak ada `kernel_thermal_hint` error berulang.

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

### 5.6 `fpsgo`/`msync2` — build/init

**Gejala:**

```text
init: Command 'insmod /vendor/lib/modules/fpsgo.ko' ... failed: No such file or directory
init: Command 'insmod /vendor/lib/modules/msync2_dms.ko' ... failed ...
init: Command 'insmod /vendor/lib/modules/msync2_frd.ko' ... failed ...
uas-service: trans sched init falied!   (50x)
```

**Temuan:** init masih mencoba memuat module yang tidak ada di build.
`uas-service` dan `setTranSchedUxTags` juga gagal, jadi fitur performance
Transsion tidak aktif.

**Rencana fix:** pilih salah satu:

- Tambahkan `fpsgo.ko`, `msync2_dms.ko`, `msync2_frd.ko` ke build dan
  pastikan ABI 6.18 cocok; atau
- Hapus baris `insmod` dan nonaktifkan fitur terkait agar log bersih.

**Verifikasi:** tidak ada `insmod ... No such file`, dan tidak ada
`uas-service` error berulang.

### 5.7 TEE/Widevine — vendor security

**Gejala:**

```text
Trustonic TEE: GF_ERROR_OPEN_SECURE_OBJECT_FAILED  (59x)
device_authen_ta: gp_read_raw g_device_key err=-65528
tdrv_drmhdcpcommon drDcihInit(): drApiStartThread failed: 0x6f03
tdrv_widevine      drDcihInit(): drApiStartThread failed: 0x6f03
```

**Temuan:** sebagian GF error karena `finger_extra_info` belum ada (wajar
untuk data fingerprint baru). `device_authen` gagal membaca device key, dan
HDCP/Widevine init gagal. Ini bisa memengaruhi Play Integrity dan playback
DRM/HDCP.

**Rencana fix:** periksa provisioning device key/certificate, TA
Widevine/HDCP, dan firmware TEE. Ini bukan DT kernel.

**Verifikasi:** device attestation berhasil, HDCP init tidak gagal, dan
playback DRM/HDCP berjalan.

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
5. Cek warning `v4l2_open` sudah hilang.
6. Cek `/sys/class/thermal`: `soc_max` ada dan suhu valid, bukan
   `-274000`.
7. Cek service `tranhalconfig` ditemukan; tidak ada `audit_lost`.
8. Cek tidak ada `insmod ... No such file` untuk `fpsgo`/`msync2`.
9. Jalankan playback DRM/HDCP dan cek TEE/Widevine.

## 8. Urutan Kerja yang Disarankan

| Prioritas | Pekerjaan | Alasan |
|---|---|---|
| P0 | Verifikasi crash/EMI pasca-fix dengan log baru | Memastikan 7 Oops + RCU stall benar-benar hilang |
| P0 | Video VP9 | Isu user-facing yang masih terbuka |
| P1 | Pastikan DTB/DTBO stock yang dipakai, bukan DT tree | ADSP dan node disabled lain tidak relevan untuk DT tree |
| P1 | Thermal `lvts`/`soc_max` | Risiko thermal/charging jika suhu invalid |
| P1 | `tranhalconfig` | Log storm, audit loss, dan lookup lambat |
| P2 | DPE `v4l2_fh` | Warning 2x per boot; node V4L2 DPE tidak berfungsi |
| P2 | CMDQ/GCE + MML | Noise; perbaiki fallback driver |
| P2 | `fpsgo`/`msync2` | Fitur performance; pilih tambah module atau hapus init |
| P2 | TEE/Widevine | DRM/Play Integrity; butuh provisioning vendor |
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
- Code warning checkpatch, DOS line endings, dan MAINTAINERS di luar scope
  dokumen ini.
- `audit_lost=437` berarti sebagian denial SELinux mungkin tidak terlihat;
  setelah `tranhalconfig` dibereskan, audit perlu dicek ulang.
