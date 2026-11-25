# Status Eksekusi Port 6.18

Diperbarui: 2026-11-25 (UTC)

> Dokumen ini merangkum status port **6.18** dari rencana awal
> ([`PLAN-INITIAL.md`](../archive/6.18/PLAN-INITIAL.md)). Baseline produksi
> **6.12** (`gki-kmi6-20261122`) tidak berubah.
>
> - Isu terbuka, prioritas fix, dan checklist verifikasi: [`TRACKER.md`](TRACKER.md)
> - Syarat SELinux `firmware_load` untuk boot sistem 6.18: [`SELINUX-6.18.md`](../guides/SELINUX-6.18.md)
> - Kronologi bringup `test1`–`test13` dan analisa yang sudah ditutup: [`BRINGUP-LOG.md`](../archive/6.18/BRINGUP-LOG.md)
>
> Per 2026-11-25 (uji live di X6871, `6.18-lts` `6.18.65-android17-6-g39d19ad1a460-rama982-4k`):
> set 5 image profil `android17-6.18-lts` (`4cc5bb220b50` + patch
> `39d19ad1a460` untuk `blk_plug_invalidate_ts`, KMI 6, build GKI lokal)
> sudah dibuild, lolos 8/8 `verify-kmi-abi.py` (487 modul runtime, `9.843`
> simbol ABI; `495` modul termuat di perangkat), dan lulus uji runtime di
> perangkat (`boot-lz4.img` md5 `b62605570ef07c9ffe5a7fe4aaf1040d`,
> `system_dlkm.flatten.erofs.img` `8857cbd0d7de0bbaf087cbe80e0253ec`,
> `vendor_boot.img` `ea13b6dfe2de10b20f8a046d40c429f3`, `vendor_dlkm.img`
> `c7aa223e09de1b1b50545edcb1fc0a08`, `odm_dlkm.img`
> `773a5910abfac89c2dbd4fcf7bd74613`):
> - **Crash / EMI / ADSP:** `0` kemunculan `Internal error`, `WARNING: CPU`,
>   `rcu_preempt detected stalls`, `[MIUMPU]srinfo_r 3`, `EMIMPU`,
>   `adsp_system_bootup fail`, `invalid cid`, maupun `Failed to register lvts tz`.
> - **Video & kamera:** VP9 **PASS** (25x `check_codec_id ipi id 6 svp 0 is correct`,
>   25 sesi `Init Vdec OK bs VP90` s.d. 1080x1920, `0` error), VP8 720p
>   (`c2.mtk.vpx.decoder`, 120/120 frame, `132.0 fps` surface / `129.4 fps`
>   bytebuffer) dan AV1 720p/1080p (`c2.mtk.av1.decoder`, 120/120 frame,
>   `228.0 fps` 720p / `110.5 fps` 1080p) **PASS**, H.264/VENC 1080p@30fps
>   **PASS**, kamera (`s5khm6sx_mipi_raw`), AIE (`96f4120`), flashlight
>   (`ocp81375_v4l2`), DPE `v4l2_fh` (`b83dca0`), dan CMDQ `vote mminfra`
>   (`a71cfd2`) **PASS**.
> - **Thermal LVTS & Touch:** `40` thermal zone aktif (`soc_max` merespons
>   beban `59.5°C` -> `72.6°C`); GT9916 + `adaptive-ts` aktif (`~352–354 Hz`,
>   `charger mode in/out`, `resume restore charger mode`, `0` error kirim).
> - **Belum diuji / terbuka:** cek level Widevine via `DRM Info` + playback
>   DRM, serta pengukuran terpisah recovery report rate pasca sleep/wake pada
>   `report_rate_switch=1`; isu tersisa: `tranhalconfig`
>   userspace (`222` AVC, `audit_lost: 21`) serta pesan minor `hung_task`
>   berkala pada kthread MTK idle (`hf_manager`, `mml_work1`).
>
> Profil uji opsional `android17-6.18-lts` tersedia lewat
> `local_manifest-6.18-lts.xml` (lihat
> [`BUILD.md`](../guides/BUILD.md#profil-uji-618-lts-android17-618-lts-61865-kmi-6-build-gki-lokal));
> patch SHA-gated `patches/common-6.18-blk-plug-invalidate-ts.patch` tetap
> diterapkan (`39d19ad1a460`).

## Ringkasan Fase

| Fase | Status | Catatan |
|---|---|---|
| 0 — Manifest, branch, workspace | **Selesai** | Workspace 6.18 terisolasi dari baseline 6.12 (`local_manifest-6.18.xml`) |
| 1 — Kleaf/MGK + device tree 6.18 | **Selesai** | Kernel `6.18.32` (`android17-6.18-2026-09_r13`), target `mgk_64_k618` |
| 2 — Codemod API 6.13–6.18 | **Selesai** | Build penuh 546 `.ko` berhasil |
| 3 — Milestone `vendor_boot` | **Selesai** | 221 modul (tanpa `mkp.ko`), `emi-mpu-hook-v1.ko` di stage-1 |
| Gerbang boot #1 | **Lulus** | TWRP PASS (touch + vibrator); boot sistem PASS setelah patch SELinux; Wi-Fi/BT PASS |
| 4 — DLKM berat | **Selesai** | Sched, Mali, WLAN, cam/vcodec/audio |
| 5 — Repack + verifier 8 gerbang | **Selesai** | 8/8 PASS, 487 modul runtime |

## Status Subsistem Saat Ini

| Subsistem / Area | Status | Keterangan |
|---|---|---|
| Boot GKI 6.18 + TWRP (touch Goodix & vibrator) | **PASS di device** | Memakai policy TWRP `kernel` permissive di `vendor_boot` (`test12`/`test13-clean`) |
| Boot Android + SELinux `firmware_load` | **PASS di device** | Wajib patch `plat_sepolicy.cil` / `vendor_sepolicy.cil` / `vendor_file_contexts` ([SELINUX-6.18.md](../guides/SELINUX-6.18.md)) |
| Wi-Fi & Bluetooth (`conninfra`) | **PASS di device** | Berfungsi setelah allow `connsys_vendor_file` (`firmware_load`) |
| Audio (`mt6895-mt6368`, FS1599) | **PASS di device** | Fix 17 link DPCM dua arah di `mt6895-mt6368.c`; speaker & amplifier aktif |
| Touch (`gt9916_common` + `adaptive-ts`) | **PASS di device** | `~352–354 Hz` (`getevent -lt`), `/proc/report_rate_switch`, `/proc/tp_report_rate_switch`, `/proc/border_suppression`, `/dev/tppolldrv`, `vendor.hardware.trantp-service`, dan `charger mode in/out` + `resume restore charger mode` PASS (`004169f83006`..`80f4abf529e2`, `0` error kirim); recovery sleep/wake pada `report_rate_switch=1` belum diukur terpisah |
| APU IOMMU + MIUMPU/RCU stall | **PASS di device** | `mtk_iommu_hw_program()` saat resume RCX (`6ebc4934a74a`) + hook stage-1; `0` `[MIUMPU]srinfo_r 3`, `EMIMPU`, maupun RCU stall di `6.18.65` |
| Video V4L2/H.264/VENC, Kamera & AIE | **PASS di device** | `priv == NULL` (`050d89c`/`41f442c`/`29ba44c`), AIE `96f4120` (`STREAM STOP` bersih), kamera `s5khm6sx_mipi_raw`, flashlight `ocp81375_v4l2`, dan VENC `1920x1080@30fps` PASS (`0` Oops/`MTK_V4L2_ERR`) |
| Thermal LVTS (`soc_temp_lvts`) | **PASS di device** | Tabel 25 sensor stock (`cbabf0ea8c34`); `0` `Failed to register lvts tz`, `40` thermal zone aktif (`soc_max` `59.5°C` -> `72.6°C`; `apu2` `No data available` saat idle; `camera0..4` belum didaftarkan `imgsensor`) |
| DPE `v4l2_fh` & CMDQ `vote mminfra` | **PASS di device** | `b83dca0` (`0` `v4l2_open` WARN, `[DPE]DPE open`/`release` bersih) & `a71cfd2` (`0` `vote mminfra on err`) |
| Video VP8 / VP9 / AV1 | **PASS di device** | `213a184315ef` + `a719a23cee6d` + `ac2e63fe0411` (`VDEC_VP8 = 5`); VP9 (`25` sesi s.d. `1080x1920`), VP8 720p (`c2.mtk.vpx.decoder`, 120/120 frame, `132.0 fps`), dan AV1 720p/1080p (`c2.mtk.av1.decoder`, 120/120 frame, `228.0 / 110.5 fps`) PASS (`0` error) |
| `tranhalconfig` | **Terbuka (userspace)** | Service/sepolicy vendor belum aktif (`222` AVC di `dmesg`, `audit_lost: 21`) |
| ADSP / `fpsgo`/`trans_sched` / TEE Widevine | **Known limitation / skip** | ADSP disabled di DTB stock (`0` `adsp_system_bootup fail`/`invalid cid`); `trans_sched`/`fpsgo` wrapper tanpa source; TEE/L1 isu provisioning (`DRM Info` belum dicek ulang di `6.18.65`) |

Rincian langkah verifikasi dan prioritas P0–P3 ada di [`TRACKER.md`](TRACKER.md).

## Komposisi Build & Verifikasi 8 Gerbang

- **Target build:** `//kernel_device_modules-6.18:mgk_64_k618_customer_modules_install.user`
- **Staging penuh:** 546 `.ko` (379 device OOT + 39 vendor OOT + 128 GKI)
- **Set runtime:** 487 `.ko` = **221** `vendor_boot` (tanpa `mkp.ko`) + **209** `vendor_dlkm` + **57** `odm_dlkm`
- **Verifier (`tools/verify-kmi-abi.py --kver 6.18`):** **8/8 PASS** terhadap `6.18.32-android17-5-gecdaacc9a0ee-4k` (`abi.stg`: 9.593 simbol, 0 mismatch CRC, 0 impor `vmlinux` non-KMI, 0 kolisi `CONFIG_MODULE_SIG_PROTECT`, 0 unresolved symbol).

## Perintah kerja

Untuk panduan lengkap lingkungan, repack, dan konfigurasi `X6871.config`, lihat
[`BUILD.md`](../guides/BUILD.md).

```bash
cd "$HOME/x6871-6.18/ws"

# build
KVER=6.18 OUT_DIR="$PWD/out_bazel_6.18" \
  "$HOME/x6871-kernel-manifest/build.sh" user

# codemod mekanis (dry-run)
python3 "$HOME/x6871-kernel-manifest/scripts/port-6.18-mechanical.py"

# verifikasi akhir (8 gerbang)
cd "$HOME/x6871-kernel-manifest"
./tools/verify-kmi-abi.py --kver 6.18 \
  --ws "$HOME/x6871-6.18/ws" \
  --vb-dir ... --vd-dir ... --od-dir ...
```

## Catatan risiko

- `X6871.config` menonaktifkan simbol config yang **namanya dipakai bersama**
  Kconfig in-tree dan OOT (`clk-*`, `pinctrl-*`). Target OOT tetap dibangun
  karena tidak memakai `kconfig`/`defconfig`, namun setiap perubahan config wajib
  melewati 8 gerbang `verify-kmi-abi.py` dan uji boot.
- Jangan pernah mencampur image KMI 6 (6.12) dengan image 6.18.
- `kernel-6.18` / `common` **tidak boleh diedit**; seluruh adaptasi berada di
  device modules, vendor modules, atau overlay manifest.
- Boot ke sistem 6.18 memerlukan patch SELinux `firmware_load` ([`SELINUX-6.18.md`](../guides/SELINUX-6.18.md)).

## Dokumen 6.18 terkait

- [`TRACKER.md`](TRACKER.md) — daftar temuan log, rencana fix, known limitation, dan checklist verifikasi
- [`API-AUDIT.md`](API-AUDIT.md) — audit perubahan semantik API 6.13–6.18 dan scan KCFI
- [`PMX110-REFERENCE.md`](PMX110-REFERENCE.md) — referensi biner `.ko` OPPO PMX110 (MediaTek 6.18)
- [`SELINUX-6.18.md`](../guides/SELINUX-6.18.md) — patch policy SELinux `firmware_load`
- [`PLAN-INITIAL.md`](../archive/6.18/PLAN-INITIAL.md) — arsip rencana awal Fase 0–5
- [`BRINGUP-LOG.md`](../archive/6.18/BRINGUP-LOG.md) — arsip kronologi bringup `test1`–`test13`, analisa MIUMPU/APU, dan regresi audio DPCM
