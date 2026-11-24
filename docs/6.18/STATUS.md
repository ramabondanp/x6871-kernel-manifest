# Status Eksekusi Port 6.18

Diperbarui: 2026-11-24 (UTC)

> Dokumen ini merangkum status port **6.18** dari rencana awal
> ([`PLAN-INITIAL.md`](../archive/6.18/PLAN-INITIAL.md)). Baseline produksi
> **6.12** (`gki-kmi6-20261122`) tidak berubah.
>
> - Isu terbuka, prioritas fix, dan checklist verifikasi: [`TRACKER.md`](TRACKER.md)
> - Syarat SELinux `firmware_load` untuk boot sistem 6.18: [`SELINUX-6.18.md`](../guides/SELINUX-6.18.md)
> - Kronologi bringup `test1`–`test13` dan analisa yang sudah ditutup: [`BRINGUP-LOG.md`](../archive/6.18/BRINGUP-LOG.md)
>
> Per 2026-11-24: fix thermal LVTS, DPE `v4l2_fh`, CMDQ `vote mminfra`,
> pemulihan `VDEC_VENC_MAX`, serta kontrol report rate & mode touch
> (`adaptive-ts` + `gt9916_common`: `004169f83006`, `92c5a6f9d3f3`,
> `80f4abf529e2`) sudah di-commit, dibuild, dan lolos 8/8 `verify-kmi-abi.py`;
> uji runtime di device tertunda karena maintainer sedang di luar.
>
> Profil uji opsional `android17-6.18-lts` (`6.18.63`, KMI 6, build GKI lokal)
> tersedia lewat `local_manifest-6.18-lts.xml` (lihat
> [`BUILD.md`](../guides/BUILD.md#profil-uji-618-lts-android17-618-lts-61863-kmi-6-build-gki-lokal)):
> seluruh 487 modul + GKI lokal lulus 8/8 `verify-kmi-abi.py` dan dilengkapi
> patch SHA-gated `patches/common-6.18-blk-plug-invalidate-ts.patch` untuk
> race `blk_finish_plug`/`blk_plug_invalidate_ts` (soak test di device sedang
> berjalan/tertunda konfirmasi).

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
| Touch (`gt9916_common` + `adaptive-ts`) | **Fixed di source, uji device tertunda** | Tambah dynamic report rate 240/360 Hz, `/proc/report_rate_switch`, `/proc/tp_report_rate_switch`, `/proc/border_suppression`, `/dev/tppolldrv` ioctl, state recovery pasca-resume, dan charger anti-noise notifier (`004169f83006`..`80f4abf529e2`); `vendor_boot` + `odm_dlkm` direpack |
| APU IOMMU + MIUMPU/RCU stall | **Fixed, verifikasi log baru tertunda** | `mtk_iommu_hw_program()` saat resume RCX (`6ebc4934a74a`) + hook stage-1 |
| Video V4L2/H.264/JPEG (`priv == NULL` & `q_run_work`) | **Fixed, uji lanjut tertunda** | `file->private_data` (`050d89c`/`41f442c`/`29ba44c`) + workqueue vdec OPPO (`31781fa`) |
| Thermal LVTS (`soc_temp_lvts`) | **Fixed di source, uji device tertunda** | Tabel sensor diselaraskan ke 25 sensor stock (`cbabf0ea8c34`); `vendor_dlkm` direpack |
| DPE `v4l2_fh` & CMDQ `vote mminfra` | **Fixed di source, uji device tertunda** | `b83dca0` (`isp_70/camera_dpe.c`) & `a71cfd2` (`ret < 0`); `vendor_boot` + `vendor_dlkm` direpack |
| Video VP9 (Facebook Story) | **Terbuka (P0)** | Ditolak VCP `changed=0x4`; `7c48ebd` di-revert (`213a184315ef`); `VDEC_VENC_MAX=20` dipulihkan (`a719a23cee6d`, belum dibuild/uji) |
| `tranhalconfig` | **Terbuka (userspace)** | Service/sepolicy vendor belum aktif, menyebabkan `audit_lost` |
| ADSP / `fpsgo`/`trans_sched` / TEE Widevine | **Known limitation / skip** | ADSP disabled di DTB stock; `trans_sched`/`fpsgo` wrapper tanpa source; TEE/L1 isu provisioning |

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
