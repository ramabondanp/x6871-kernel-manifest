# HANDOFF — W1VO36 / X6871 kernel device modules

Ditulis 2026-11-19 untuk sesi AI berikutnya. Baca ini dulu, lalu `PLAN.md`
(bagian §6.1b, §6.2k, §6.2m, §6.2n, §6.2o, §6.2p, §6.2q, §6.2r, §6.2s,
§6.2t, §6.2u) dan `PRETEST.md`.

## Status ringkas

| Item | Nilai |
|---|---|
| `.ko` flat customer install | **692** |
| `.ko` di tree staging lengkap | **796** |
| Modul di firmware X6871 | 237 |
| Masih hilang (flat / tree) | **27 / 20** |
| Build target | `//kernel_device_modules-6.12:mgk_64_k612_customer_modules_install.user` |
| Build terakhir | sukses, 5 aksi (inkremental) |
| Runtime | **TWRP boot normal** (lihat §Status per 2026-11-19) |

Repo bersih, semua ter-push: `alps`, branch `w1vo36-6.12-port`,
HEAD `93b7ebca0841`. Manifest `main` mengikuti commit HANDOFF/PLAN/PRETEST
terakhir.

## Objective

Bangun modul device untuk X6871 (mt6895, kernel 6.12.38-android16-5) yang
tidak punya source vendor, mulai dari tree W1VO36.88-36-7 / mt6895 yang sudah
bisa build. Vendor sumber GPL resmi lebih diutamakan daripada RE; RE dipakai
kalau memang tidak ada source.

## Aturan keras

1. **Jangan pakai `/tmp`** — pakai `/serverhive1/ramabondanp/tmp`.
2. **Selalu commit + push setelah setiap perubahan, tanpa bertanya.**
   Push ke `alps` dan `local` (branch `w1vo36-6.12-port`).
3. Commit di tree 6.12 harus **bahasa Inggris**.
4. Jangan satu commit untuk semua perubahan; satu commit per fitur.
5. Repo manifest harus tetap ramping.
6. **Cocokkan modul lewat fingerprint isi `.ko`, jangan lewat nama.**
7. **Aturan §6.1b: "tidak ada `<nama>.c`" ≠ "tidak ada source".** Modul
   gabungan tidak punya `.c` senama; namanya hanya ada di `Makefile` sebagai
   `<module>-objs`. Periksa 5 hal berurutan: (1) `.c` senama, (2) entri
   `Makefile`/`Kbuild`, (3) entri `Kconfig`, (4) **daftar mana** di `*.bzl`
   (hanya `mgk_64_module_outs` yang sampai ke target device), (5) fingerprint
   simbol.
8. Perbandingan simbol **harus difilter `GLOBAL`**. `LOCAL FUNC` hanya
   mencerminkan inlining.
9. Perbandingan modul = himpunan simbol `GLOBAL` ekspor **dan** impor vs
   firmware (`readelf -sW`).
10. Layout struct **diukur dari `.ko`**, bukan didiff dari header.
11. Perbedaan jumlah impor pada modul yang menyentuh sysfs bukan bug — build
    DDK mengoptimalkan jalur sysfs/DT.
12. **Build hijau bukan bukti isi benar.** Semua bug besar di sesi lalu
    (kebocoran simbol panel, `charger_ops`/`tcpc_ops` meleset, `tc_tfcp_ta`
    tidak mendaftarkan apa pun, tabel ops `pca_tfcp_ta` salah, `dev` di
    offset salah) lolos dari build dan hanya ketahuan dari diff
    ekspor/impor/relokasi.
13. `tc_charger_class` **menggantikan** `charger_class` MTK (firmware tidak
    mengirim `charger_class.ko`).
14. 7 modul GKI (`arm_dsu_pmu`, `drm_display_helper`, `drm_dma_helper`,
    `industrialio-triggered-buffer`, `kfifo_buf`, `reboot-mode`,
    `syscon-reboot-mode`) **bukan gap** — ada di `mgk_module_ext_outs`.

## Lingkungan

- Workspace: `/serverhive1/ramabondanp/w1vo`
- Manifest: `/serverhive1/ramabondanp/w1vo36-kernel-manifest`
- Oracle firmware (237 `.ko`): `/serverhive1/ramabondanp/tmp/x6871/vr/root/lib/modules/`
- DTBO otoritatif: `/serverhive1/ramabondanp/tmp/x6871/frag0.dts`
- Konfigurasi kernel device: `/serverhive1/ramabondanp/tmp/bootRE_ikconfig`
- Source donor 6.1 lengkap: `/serverhive1/ramabondanp/tmp/ts61-src/kernel/kernel_device_modules-6.1/`
- Tarball resmi (donor, **6.1, jangan pernah jadi basis build**):
  `/serverhive1/ramabondanp/tmp/mt6897-full.tar.gz`

### Perintah build

```bash
cd /serverhive1/ramabondanp/w1vo
TMPDIR=/serverhive1/ramabondanp/tmp BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1 \
./tools/bazel --output_user_root="$PWD/out_bazel" build --config=stamp \
  --repo_manifest="$PWD/kernel_device_modules-6.12/fake_manifest.xml" \
  --experimental_writable_outputs --allow_ddk_unsafe_headers=1 \
  --user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers \
  --repo_env=KERNEL_VERSION=kernel-6.12 --repo_env=KERNEL_BUILD_VARIANT=user \
  --repo_env=DEFCONFIG_OVERLAYS=entry_level_legacy.config \
  --repo_env=SUPPORT_PLATFORM=mt6895 --repo_env=SOURCE_DATE_EPOCH=0 \
  --//build/bazel_mgk_rules:kernel_version=6.12 \
  "//kernel_device_modules-6.12:mgk_64_k612_customer_modules_install.user"
```

Staging hasil build:
`out_bazel/ad3c7b30a704e8551ed600a0d11ef0f0/execroot/_main/bazel-out/k8-fastbuild/bin/kernel_device_modules-6.12/mgk_64_k612_customer_modules_install.user/`

### Jebakan build

- `--user_ddk_unsafe_headers=...mtk_use_gki_unsafe_headers` **wajib**; tanpa
  itu puluhan header hilang.
- Target ABI `user_customer_abi` **tidak bisa lulus** (328 simbol duplikat
  dari driver multi-varian). Referensi MTK/Samsung juga tidak menjalankannya.
- Label `//kernel_device_modules-{}` **wajib** diikuti
  `.format(kernel_version)` — generator sempat menjatuhkannya 4 kali.
- Komentar Bazel adalah `#`, bukan `/* */`.
- `ko_deps` harus memuat **setiap** penyedia simbol yang diimpor, kalau tidak
  `modpost: "<sym>" undefined!`.
- `v1/BUILD.bazel` ber-CRLF; pertahankan atau diff meledak.
- `tar` gzip satu inti mati di tengah (>3 menit). Pakai
  `pigz -dc file.tar.gz | tar -x -C dir` — 7.106 file <60 s.

## Yang sudah selesai

Tingkat A (overlay `entry_level_legacy.config`), Tingkat C (`tran_audio_control`,
`splitswitch-gpio`, `hiber`), Iris divendorkan, panel rm69220, `tran_ldo`,
seluruh fondasi charger `tc_*`, `tc_charger_framework`, 5 algoritma charging,
`tc_tfcp_ta`, `pca_tfcp_ta`, `nfc_i2c`, `tran-led-core`, `leds-aw22xxx`,
serta empat modul fitur: `tran_extcon_usb`, `tran_fp`, `tnek`, `tkv`.

Daftar commit per fitur ada di `git log` branch `w1vo36-6.12-port`.

## Yang tersisa: 20 modul di tree staging

Angka 20 adalah nama stock yang tidak ada di **tree staging lengkap**
(`staging/lib/modules/6.12.38-.../`, 796 `.ko`). Flat customer install
(692 `.ko`) masih melaporkan 27 karena 7 modul GKI tidak disalin ke flat
root, tetapi semuanya ada di tree staging. Lihat `PRETEST.md` §3.

Dari 20 nama itu, 6 memang **tidak direncanakan** untuk X6871: dua varian
panel perangkat lain (`ili7838e...cl9`, `rm69220...cl8`), satu alias panel
X6871 (`rm69220...x6871`, dicakup `panel-rm69220-vdo-x6871.ko`), dan tiga
modul MMC/SD (`tran_mmc_block`, `mtk-mmc-mod`, `sd_tray`). Lihat bagian
"Tidak direncanakan" di bawah.

Kandidat nyata tinggal **14**: 7 storage yang ditunda (lihat §"Storage /
UFS"), 4 terblokir `transsion_tranlog`, dan 3 fitur mandiri
(`tkv_recovery`, `tran_rhi`, `tran_expand_key`).

### Bukan gap — dibangun GKI build
`arm_dsu_pmu`, `drm_display_helper`, `drm_dma_helper`,
`industrialio-triggered-buffer`, `kfifo_buf`, `reboot-mode`,
`syscon-reboot-mode`

### Sudah ada, hanya beda nama berkas
`rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871` — modul kita
`panel-rm69220-vdo-x6871.ko` ekspornya **3 == 3 identik** dan alias DT sama.
Autoload ikut alias, bukan nama berkas.

### Tidak direncanakan — varian panel perangkat lain

Perangkat target proyek ini **hanya X6871**. DT X6871 (`frag0.dts`,
`panel1@0`) hanya memakai compatible:

```
rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871
```

Modul kita `panel-rm69220-vdo-x6871.ko` sudah melayani alias itu. Dua varian
berikut **sengaja tidak direncanakan** (bukan blocker, bukan gap yang dikejar):

- `ili7838e_fhdp_dsi_cmd_dsc_tm_tm_120hz_cl9`
- `rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_cl8`

Keduanya untuk konfigurasi/panel perangkat lain; tidak ada node DT-nya di
X6871. Jangan port kecuali target perangkat berubah.

### Empat modul fitur selesai — jangan port ulang

| Modul | Commit | Verifikasi |
|---|---|---|
| `tran_extcon_usb` | `3194d4f10237` | ekspor 0/0, impor 47/47, alias/`depends` **identik** |
| `tran_fp` | `29d21b5d018c` | common layer + chip-id/SPI REE; export asli 0/2 (debug), impor 94/145 |
| `tnek` | `24b5fe361653` | **9 == 9 ekspor asli**, **24 == 24 impor** |
| `tkv` | `cb088a63c4b2` | **0 == 0 ekspor asli**, 24/23 impor (+`page_is_ram`) |

Pre-flight `6334ce2b9910` (§6.2u) mengoreksi hitungan export: yang benar
adalah `__ksymtab`, bukan semua simbol GLOBAL. Ia juga menghapus
`charger_class.ko` dari install dan menambahkan pengaman hardware/memori.
Hasil simulasi load: **217/237 modul stock yang ada + 4 modul kita → 0
impor tak terselesaikan, 0 CRC tak terpenuhi, 0 export ambigu**. Detail di
`PRETEST.md`.

- `tran_extcon_usb`: match `transsion,extcon-usb`; `extcon-mtk-usb.ko` tetap
  ada untuk node `mediatek,extcon-usb`. Jangan gabungkan keduanya.
- `tran_fp`: source donor 6.1 `tran_common_v2` di
  `drivers/input/fingerprint/tran_common/`, match `tran_fp_legacy`. Modul
  firmware 6.12 membundel backend vendor (`gf_*`, `ff_*`, ...); port ini
  **common layer + jalur chip-id Goodix**, bukan seluruh backend.
  Power/reset/IRQ/SPI clock/netlink/sysfs tetap ada. Regulator X6871
  `mt6368_vfp` fixed 3,3 V; guard menolak regulator variabel/di luar
  1,5–3,6 V. **Wajib diuji saat boot**.
  - Sejak `29d21b5d018c` modul mengimpor `spi_sync` dan membaca chip id
    lewat SPI saat probe (`tran_fp_detect_chip=1`), lalu mengisi `ic_name`
    + `vendor_name` (`/sys/kernel/tran_fp/vendor_name` → `common_goodix`).
    Kegagalan deteksi **tidak** menggagalkan probe (stock menggagalkannya).
  - `TRAN_FP_READ_FP_ID` (`_IO('t',3)`) diimplementasikan seperti stock:
    deteksi lalu `tran_netlink_send(6)`/`(7)`; dilewati bila
    `TRAN_FP_OPT_SUPPORT` (`_IO('t',4)`) sudah dipanggil.
  - `TRAN_IOC_TRANSFER_CMD` (ABI `struct tran_ioc_transfer`: `cmd` 0=baca/
    1=tulis, `addr` 16-bit big-endian, `len`, `buf`) + `_RAW_CMD` dan
    `_SPI_INIT_CFG_CMD` (dua yang terakhir tidak dipakai stock; layout
    didefinisikan di port ini). Buffer user di-bounce ke memori kernel
    karena SPI bisa DMA.
  - **Penting**: modul stock tidak punya ioctl transfer sama sekali —
    akuisisi gambar di X6871 lewat TEE, REE hanya untuk chip id. Jadi kalau
    HAL gagal, penyebabnya bukan ioctl 15/16/17.
  - `spi->controller_data` sengaja tidak disentuh: `spi-mt65xx` memilikinya,
    `BUG_ON()` di `spi_dump_config()` bila field cs timing legacy terisi, dan
    `kfree()` di `mtk_spi_cleanup()`. `tran_chip_config` statik ala stock
    tidak bisa dipakai dengan controller driver ini.
- `tnek`: tidak ada source; direkonstruksi penuh. Node 0x418, pesan user
  0x408, queue 9, `/dev/tnek`. `mcDrvModule` firmware mengimpor
  `tnek_caller_api`; build kita meng-gate impor itu. Export asli 9 == 9.
- `tkv`: `/proc/tkv`, `g_tkv` (lcm inversion), region 32 KiB dari
  `tkv=<desimal>` di bootargs. Bila bootargs tidak punya `tkv=`, modul
  berhenti aman. Pengaman baru: region wajib page-aligned dan seluruh page
  `page_is_ram()`; kalau gagal, `/proc/tkv` dilewati. Tidak pernah menulis
  balik ke region.

### Berikutnya paling siap
- **Boot test** memakai checklist `PRETEST.md` §7. Pastikan image memakai
  `modules.dep`/`modules.alias` hasil build dari tree staging, bukan
  `modules.dep` stock (stock masih memaksa `transsion_tranlog` untuk
  `tran_fp`). Ini menentukan apakah 7 modul fork storage masih diperlukan.
- `tkv_recovery` — sibling `tkv`, 20 KB, 11 ekspor / 24 impor; kandidat
  berikutnya yang paling kecil.
- `tran_rhi` — health info storage (ECC/erase/suhu), 47 KB, tanpa source.
- `tran_expand_key` — dump manual volup+voldown 10 detik, 19 KB, 9 ekspor.
- `tc_trancare` — `status = "okay"`, terblokir `transsion_tranlog`.
- `transsion_tranlog` — 92 fungsi / 108 KB, tanpa source, membawa
  `cloudengine_*`/`athena_*`/`arraylist_*`/`__tran_kfifo_*`. `submit_msg`
  mem-parse format string (`strlen`/`memcpy`/`kstrtoll`/`kstrtoint`).
  Catatan: `tc_charger_framework` dan `tc_water_detect` mengimpor tranlog di
  firmware tapi **tidak** di build kita — jalurnya di-gate saat compile, jadi
  charger inti tidak bergantung padanya.
- **Goodix fingerprint backend** — hanya bagian yang belum ada: akuisisi
  gambar bila ternyata dijalankan di REE. Bukti saat ini: modul stock
  (`tran_fp.ko` X6871) **tidak** punya ioctl transfer dan tidak punya
  handler `write()`, jadi transfer gambar berjalan di TEE dan REE hanya
  dipakai untuk chip id (sudah diport di `29d21b5d018c`). Port backend baru
  diperlukan hanya kalau boot test menunjukkan HAL memakai jalur REE.

### Storage / UFS — **Opsi A: baseline GKI/MTK** (diputuskan 2026-11-19)

Kelompok storage **tidak diport sebagai fork**. Stack yang dipakai adalah
yang sudah dibangun:

- GKI builtin: `CONFIG_BLOCK=y`, `CONFIG_SCSI_MOD=y`, `CONFIG_BLK_DEV_SD=y`,
  `CONFIG_SCSI_UFSHCD=y` (dibaca dari ikconfig boot X6871)
- `ufs-mediatek-mod.ko`, `phy-mtk-ufs.ko`, `ufs-mediatek-dbg.ko`,
  `blocktag.ko`, `rpmb.ko`, `rpmb-mtk.ko`, `cqhci.ko`

Closure sudah dicek: seluruh impor kedelapan modul di atas disediakan oleh
vmlinux atau `.ko` lain di staging — **0 simbol benar-benar hilang**.

#### Tidak direncanakan — hardware tidak ada (3)

- `tran_mmc_block` — MMC block; kedua node `mmc@11240000` dan
  `mmc@11242000` di base DTB X6871 berstatus `disabled`.
- `sd_tray` — tidak ada node `/odm/sd_tray` di base DTB.
- `mtk-mmc-mod` — sudah dilayani `mtk-mmc.ko`: alias identik, 17/21 ekspor
  sama; beda hanya empat helper ioctl Transsion. MMC juga disabled.

#### Ditunda sampai boot test (7)

`tran-ufshcd-core`, `tran-ufshcd-pltfrm`, `tran_scsi_mod`, `tran_sd_mod`,
`tran_block`, `tran-proc-bootdevice-mod`, `low_latency_sched`.

Semuanya satu paket fork `fs/atomic_storage/` (67 file `.c`, ~2,9 MB `.ko`)
yang saling impor `tran_*`. `ufs-mediatek-mod.ko` versi firmware juga
di-patch untuk memanggil `tran_scsi_*` / `tran_ufshcd_*`, jadi tidak bisa
diambil sebagian.

Source tidak tersedia: tarball donor MT6897 6.1 (4,7 GB) tidak punya
`fs/atomic_storage`, `tran_block`, `sd_tray`, `low_latency`, maupun
`drivers/bootdevice`. Tidak ada tarball X6871 6.12 di workspace.

Rencana:

1. Boot test dengan baseline. Cek probe `ufshcd`, `sd 0:0:0:0`, mount
   `/data`, dan tidak ada `Unknown symbol tran_*`.
2. Kalau userspace membuka `/proc/bootdevice` dan gagal, tulis shim kecil
   (`manfid`/`serial`/`fw_version`/`manfdate`/`ffu_support`) — bukan port
   modul 85 KB.
3. Kalau storage gagal total, baru eskalasi ke rekonstruksi
   `fs/atomic_storage` dari upstream 6.12.38 + hook firmware.

### Fitur
`tran_rhi`, `tran_expand_key`, `tran_key_bigdata`, `tkv_recovery`, `thd`

Catatan: `tran_key_bigdata` dan `thd` sama-sama bergantung pada
`transsion_tranlog`, jadi keduanya tetap terblokir. `tran_rhi`,
`tran_expand_key`, dan `tkv_recovery` mandiri.

## Pengetahuan kritis

### `tran-led-core` sudah selesai — pakai layout ini, jangan ukur ulang

Alamat: `drivers/leds/tran_led/` (`tran_led_class.c`, `tran_led_core.c`,
`tran_led_class.h`, `BUILD.bazel`). Commit `39044a9498af`.

Firmware dibangun dari tree **6.12**; `.ko` menyimpan path aslinya dan 111
modul ber-path semuanya menyebut 6.12. Donor 6.1 hanya punya leluhur jauh
lebih tua (`tc_led_class.c`, 7 ekspor, 4 slot ops).

Layout sudah diverifikasi dua arah dan di-assert saat compile:

- `struct tran_led_device`: ops `+0x08`, dev `+0x220`, `dev.driver_data`
  `+0x2b8`, `dev.class` `+0x538`, `sizeof` `0x778`
- `struct tran_led_core`: class `+0x120`, `support_pdlc` `+0x128`,
  `chip_type` `+0x12c`, `primary_led` `+0x130`, `second_led` `+0x138`,
  mutex `+0x140`, `log_level` `+0x170`, `sizeof` `0x178`
- `struct tran_led_ops` 13 slot: `0x00` set_i2c_retries, `0x08`
  set_i2c_timeout, `0x10` rw_i2c_data, `0x18` get_chip_type, `0x20` get_cmd,
  `0x28` set_cmd, `0x30` tidak terdokumentasi (hanya jalur ioctl), `0x38`
  store_tran_led_cmd, `0x40` show_tran_led_cmd, `0x48` store_tran_led_check,
  `0x50` show_tran_led_check, `0x58` store_tran_multicolor, `0x60`
  show_tran_multicolor

Ekspor `tran-led-core` **20 == 20 identik** dengan firmware. Nama DT
`tran,led_core`, modinfo `tran_led_core`.

### `leds-aw22xxx` sudah selesai — jangan kembali ke donor 6.1

Alamat: `drivers/leds/tran_led/leds-aw22xxx.c` (+ `.h`, `-reg.h`, `-cfg.h`).
Commit `54c604b9378e`. Implementasi penuh ada di PLAN.md §6.2r.

- Ekspor/impor/alias **identik**, 7 entri tabel ops mendarat di offset yang
  sama (`0x158…0x1a0`), `aw22xxx_cfg_name` 13.184 byte byte-identik.
- Donor 6.1 hanya titik awal: 206 nama cfg, tabel music gain, multi-color
  `B85/E23/S30`, `_A/_B` shift 66/132, dan tiga argumen `tran_led_cmd_cfg_2`
  semuanya berasal dari `.ko`.
- `aw22xxx_cover_gain` dan `aw22xxx_reg_access` di-export; tidak ada modul
  firmware yang mengimpornya, jadi layout privat tidak bocor ke modul lain.
- Perhatikan dua jenis `dev_get_drvdata`: atribut pada `cdev.dev` mendapat
  `led_classdev *` (perlu `container_of` ke `aw22xxx`), sedangkan
  `tran_led_cmd`/`tran_multicolor` pada device i2c mendapat `aw22xxx *`.
- `remove` sengaja mengikuti firmware: tidak memanggil
  `tran_led_device_unregister`, tidak menghapus dua atribut i2c. Modul ini
  praktis tidak pernah di-unload; kalau nanti diubah, tambahkan cleanup-nya.

### Pola pasca-6.12 yang sudah dipetakan

`platform_driver.remove` mengembalikan `void`; `class_create(THIS_MODULE,n)`
→ `class_create(n)`; probe i2c kehilangan argumen `i2c_device_id` (definisi
**dan** prototipe header); `no_llseek` → `noop_llseek`; `crc8()` 4 argumen
(perlu `CRC8_INIT_VALUE`); `usb_types` bitmask `u32`, `num_usb_types` hilang;
`<linux/pinctrl/consumer.h>` harus di-include eksplisit.

Catatan: `tran-led-core` **tidak** memakai `noop_llseek` — firmware tidak
mengimpornya, jadi `.llseek` dibiarkan NULL.

### Kalau ada sumber tanpa spec: pakai interface yang dipublikasikan

Cara yang terbukti pada `tc_tfcp_ta` (27/27 `tc_ta_device_ops`) dan
`pca_tfcp_ta` (tabel 12 entri di `.data+0x108`): kalau `.ko` tidak di-strip
dan modul mengimplementasikan interface yang sudah ada di header, signature
diberikan oleh interface, dan peta register/callback dibaca dari immediate
`mov w1, #0x..` serta relokasi `R_AARCH64_ABS64`.

### Buat ulang generator

`/serverhive1/ramabondanp/tmp/gen-tc30-hvdcp20.py` — menghasilkan
`tc_tc30.*`/`tc_hvdcp20.*` dari `tc_pe20` dengan tukar prefix.
`/serverhive1/ramabondanp/tmp/forkmatch.py` — mencocokkan himpunan fungsi
`.ko` firmware dengan kandidat source MTK.

### Skrip porting

`port-tc-module.sh` — menyalin modul + menerapkan 6 patch 6.12
(remove→void, class_create, probe i2c).

## Resep verifikasi

```bash
B=<staging di atas>; F=/serverhive1/ramabondanp/tmp/x6871/vr/root/lib/modules
# ekspor
diff <(readelf -sW $B/<m>.ko | awk '$4=="FUNC"&&$7!="UND"&&$5=="GLOBAL"&&$8!=""{print $8}' | sort -u) \
     <(readelf -sW $F/<m>.ko | awk '$4=="FUNC"&&$7!="UND"&&$5=="GLOBAL"&&$8!=""{print $8}' | sort -u)
# impor
diff <(readelf -sW $B/<m>.ko | awk '$7=="UND"{print $8}' | sort -u) \
     <(readelf -sW $F/<m>.ko | awk '$7=="UND"{print $8}' | sort -u)
# alias DT
diff <(strings -a $B/<m>.ko | grep '^alias=' | sort) \
     <(strings -a $F/<m>.ko | grep '^alias=' | sort)
```

Untuk layout struct: cari `ldr x8,[x0,#0x8]` lalu `ldr x8,[x8,#N]`; `N/8`
adalah indeks field. Bandingkan dengan firmware. Tambahkan `_Static_assert`
agar build gagal kalau offset bergeser.

## Wajib diuji saat boot

Jalur panel (Iris probe, `tran_ldo` bus i2c 6 / `et5904_regulators6[]`),
`tc_charger_framework` pada `tc,charger`, `nfc_i2c` pada `nxp,pn544`,
`leds-aw22xxx` pada `awinic,aw22xxx_led`.

## Blocker yang perlu dump image vendor/super

`iris5.fw`, `iris5_ccf1.fw`, `iris5_ccf2.fw`,
`pxlw-rm69220_..._x6871.fw` ada di `/vendor/firmware` dan belum pernah
di-dump. Hanya ramdisk `vendor_boot` yang ada di disk.

## Status per 2026-11-19 (akhir sesi)

**TWRP boot normal dan aman dengan modul kita.** Vendor_boot TWRP (ramdisk
zstd) yang diisi modul build kita memuat 238 modul, tanpa `Unknown symbol`,
tampilan hidup (mediatek-drm bind + panel `rm69220...x6871`), sentuhan jalan
(gt9916), dan USB/adb berfungsi.

**System belum diuji dan sengaja belum disentuh.** `vendor_boot` hanya
membawa `lib/modules`; boot ke system masih memerlukan pembaruan
`vendor_dlkm` dan `odm_dlkm`, dan itu belum dilakukan.

Artefak terakhir (release `boottest-20261119`):

| Aset | Layout | Modul | md5 |
|---|---|---|---|
| `twrp-vendor_boot-fixed.img` | TWRP (zstd) | 238 | `327c4e52a0b81e807d71bba00138f6e5` |
| `vendor_boot-new.img` | stock (lz4) | 218 | `e65fdcf92e15a1b9ffd2bafcc7b2ae73` |

Commit terakhir: kernel `93b7ebca0841` (define `CONFIG_TC_CHARGER`),
manifest `c53fce7`.

### Sumber stock `vendor_dlkm` dan `odm_dlkm`

Dump firmware X6871 menyimpan partisi dlkm sebagai **tree file**, bukan image
(tidak ada `super.img`/`vendor_dlkm.img`/`odm_dlkm.img`), tapi bisa diunduh
per-partisi lewat parameter `path=` pada URL archive GitLab:

```bash
B="https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6871/-/archive/X6871-16.3.0.155SP20(OP008PF001AZ)/Infinix-X6871-X6871-16.3.0.155SP20(OP008PF001AZ).zip"
curl -LO "$B?ref_type=heads&path=vendor_dlkm"   # 16 MB
curl -LO "$B?ref_type=heads&path=odm_dlkm"      # 2.6 MB
```

Hasil ekstrak ada di `/serverhive1/ramabondanp/tmp/stock-dlkm/`:

| Partisi | `.ko` | Ukuran | modules.load |
|---|---|---|---|
| `vendor_dlkm` | 219 | 54 MB | 201 entri |
| `odm_dlkm` | 71 | 11 MB | 71 entri |

Gabungan unik 288 modul; hanya 60 di antaranya juga ada di vendor_boot
ramdisk stock (dan untuk yang overlap, ukurannya identik — mis.
`mt6375-charger.ko` 127336 byte di kedua tempat). 177 modul ramdisk memang
khas first-stage (`clk-*`, `aee_*`, `cmdq-*`, `bootprof`, `8250_mtk`, ...) dan
tidak ada di dlkm.

Cakupan build kita: 255 dari 288 modul dlkm sudah kita produksi. 33 modul
belum (harus tetap pakai `.ko` stock):

- `vendor_dlkm` (18): `sgm37864_v4l2`, `ocp81375_v4l2`, `aw8601af`, `dw9800k`,
  `mtk-vcodec-sys-api`, `snd-soc-aw87xxx`, `snd-soc-oca72xxx`, `perf_common_v`,
  `game`, `task_turbo_v`, `fpsgo`, `thd`, `transsion_tranlog`,
  `snd-soc-fs1599`, `snd-soc-fs1894`, `elliptic-ultrasound`, `aw36515_v4l2`,
  `ak7316`.
- `odm_dlkm` (15): `focaltech_ft3683g`, `adaptive-ts`, `gt9916_common`,
  `chipsemi_chsc5xxx_old`, `tran_richtap_haptic_hv`, `tran_key_bigdata`,
  `dw9784ois`, `tran_health_sched`, `tran_mm_collect`, `pages_prefilter`,
  `tran_zram`, `tc_trancare`, `tran_audio_typec`, `trans_sched`,
  `tran_perf_util`, `aw36515`, `priority_allocate`.

Diff per fungsi (nama + ukuran simbol `.text`) untuk 255 modul itu: **126
modul berbeda**, 47 di antaranya berbeda berat. Puncaknya drift versi sumber,
bukan salah config:

| modul | fungsi kita/stock | hilang | ekstra | beda ukuran |
|---|---|---|---|---|
| `wlan_drv_gen4m_6895` | 6262/6644 | 412 | 30 | 457 |
| `conninfra` | 1389/1704 | 315 | 0 | 24 |
| `apusys` | 2253/2300 | 49 | 2 | 35 |
| `imgsensor` (dua partisi) | 597/568 | 33 | 62 | 22 |
| `tc_charger_framework` | 221/249 | 29 | 1 | 34 |

Data lengkap: `/serverhive1/ramabondanp/tmp/dlkm-diff.json`.

Catatan: karena dump hanya berisi tree, mengganti isi partisi dlkm berarti
membuat image `erofs`/`ext4` sendiri lalu memasukkannya ke logical partition
(`super`) + AVB — belum dikerjakan, dan boot ke system belum diuji.

