# PLAN — Port driver ke sumber X6871 (Infinix GT 20 Pro)

Dokumen ini mengarsipkan rencana porting awal dan temuan teknis (§6.x).
Untuk build, mulai dari [README](../README.md#build-dari-source). Untuk status
rilis dan panduan pemeliharaan, lihat [HANDOFF](HANDOFF.md).

> **Status 2026-11-22:** Seluruh **488 modul `.ko`** dalam `vendor_boot` (222),
> `vendor_dlkm` (209), dan `odm_dlkm` (57) dibangun dari kode sumber port dan GKI;
> tidak ada `.ko` yang disalin dari firmware stock. Kernel dasar AOSP GKI
> **`android16-6.12-2026-09_r16`** (`6.12.92-android16-6`, **KMI 6**) tidak diubah.
> Revisi modul perangkat untuk rilis ini setelah trim: `fa18f7f`. Pada rilis `gki-kmi6-20261122`,
> Android 16 terbukti boot sampai launcher dengan `boot-lz4.img` dan
> `system_dlkm.erofs.img` resmi Google.
> Pengujian TWRP dan fitur perangkat yang dirangkum di §10 berasal dari KMI 5.
> Angka 688/806 `.ko` di bagian awal dokumen ini adalah snapshot historis; angka build
> saat ini (setelah trim allowlist `x6871_modules.bzl`) adalah **553** file / **552** nama unik
> di staging dan **419** flat customer install (919 action Bazel). Untuk status terkini,
> mulai dari `HANDOFF.md`.

---

## 1. Masalah

Tujuannya membuat port kode sumber kernel tidak resmi untuk **Infinix X6871
(GT 20 Pro)** karena source resmi khusus perangkat ini tidak dipublikasikan.
Versi firmware bawaan yang dijadikan referensi: `X6871-16.3.0.155SP20`.

Titik keberangkatan yang menguntungkan:

```
X6871  : MT6895 (Dimensity 8200 Ultimate), kernel 6.12.38-android16-5-gb575a0b6e647
W1VO   : mt6895                          , kernel 6.12.38-android16-5-g2c4fd33ae6d8
                                                       ^^^^^^^^ KMI generation sama
```

SoC, versi kernel, dan generasi KMI pada titik awal sama, sehingga tree modul
Motorola W1VO36 dipakai sebagai basis port. Driver yang tersedia diambil dari
kode sumber donor. Modul kernel (`.ko`) dan Device Tree dari firmware bawaan
X6871 dipakai sebagai referensi untuk reverse engineering dan verifikasi.

---

## 2. Selisih modul (terukur)

Bandingkan 546 modul di firmware X6871 vs 764 modul hasil build w1vo:

| | jumlah |
|---|---|
| modul firmware X6871 | 546 |
| sudah dibangun w1vo (baseline) | **439** (80%) |
| sudah dibangun w1vo (setelah Tingkat A) | **452** (82%) |
| selisih awal | 107 |
| **selisih sekarang** | **94** |

107 selisih itu dipecah 4 tingkat:

| Tingkat | Isi | Jumlah | Status |
|---|---|---|---|
| **A** | sudah ada target Bazel di tree w1vo, cuma dimatikan config | **13** | ✅ selesai |
| **B** | sudah dibangun tapi beda nama (`fpsgo`→`mtk_fpsgo_v3/v8`, `game`→`mtk_game`) | **2** | belum |
| **C** | source Transsion/MTK ada di donor (6.1 atau OPPO 6.12) | **38** | ⚠️ blokir struktural, lihat §5 |
| **D** | tidak ada di mana pun | **~41** | belum |

Catatan penting hasil investigasi: dari 94 selisih, **hanya 15 yang dirujuk
device tree X6871**. Sisanya kemungkinan dependensi internal atau modul yang
tidak dipakai build ini. Lihat §5.0c.

---

## 3. Tingkat A — 12 modul, cuma perlu flag  ✅ SELESAI

Bukan port. Ini modul MTK "legacy" yang **sudah ada di tree w1vo** dan sudah
punya target Bazel. Kita mematikannya sendiri waktu build dengan
`DEFCONFIG_OVERLAYS=` kosong.

File yang mengatur: `kernel_device_modules-6.12/kernel/configs/entry_level_legacy.config`

```
CONFIG_MTK_CM_MGR_LEGACY_V1=m          -> mtk_cm_mgr_legacy_v1
CONFIG_MTK_CM_MGR_MT6895=m             -> mtk_cm_mgr_mt6895
CONFIG_MTK_LPM_LEGACY=m                -> mtk-lpm-legacy
CONFIG_MTK_LPM_MT6895=m                -> mtk-lpm-plat-v1-legacy, mtk-lpm-dbg-mt6895-legacy
CONFIG_MTK_LPM_GS_DUMP_SUPPORT=y
CONFIG_MTK_SWPM_MODULE_LEGACY_V2=m     -> mtk-swpm-legacy
CONFIG_MTK_SWPM_MT6895=m
CONFIG_MTK_SWPM_PERF_ARMV8_PMU_LEGACY_V2=m -> mtk-swpm-perf-arm-pmu-legacy
CONFIG_MTK_EMI_LEGACY=m                -> emi-mpu-v2
```

### Hasil build (terverifikasi 2026-11-18)

```
flag    : --repo_env=DEFCONFIG_OVERLAYS=entry_level_legacy.config
hasil   : Build completed successfully, 784 actions, 715s
modul   : 764 -> 775  (+13, -2)
gap     : 107 -> 94   (coverage 439/546 = 80% -> 452/546 = 82%)
```

13 modul yang hidup (semua menutup selisih nyata, 0 bonus):

```
emi-mpu-hook-v1   emi-mpu-v2          mtk-lpm-dbg-common-v1-legacy
mtk-lpm-dbg-mt6895-legacy             mtk-lpm-legacy
mtk-lpm-plat-v1-legacy                mtk-swpm-dbg-common-v1-legacy
mtk-swpm-dbg-v6895                    mtk-swpm-legacy
mtk-swpm-perf-arm-pmu-legacy
mtk_cm_ipi_legacy_v1                  mtk_cm_mgr_legacy_v1
mtk_cm_mgr_mt6895
```

Catatan: PLAN awal menebak 12, hasilnya 13. Bedanya `mtk-swpm-dbg-v6895` —
ikut hidup dari blok yang sama, tidak saya hitung karena di daftar gap
namanya `mtk-swpm-dbg-v6895` dan saya salah memasukkan yang `...-legacy`.

2 modul yang hilang, dan aman:

```
ffa-core, ffa-module   -> X6871 tidak memakai keduanya (0 di firmware)
ffa_v11                -> tetap ter-build; modinfo depends kosong
```

Semua `.ko` baru ber-vermagic benar
(`6.12.38-android16-5-g2c4fd33ae6d8-4k SMP`).

---

## 4. Tingkat B — 2 modul, rename

`fpsgo` dan `game` sudah dibangun sebagai `mtk_fpsgo_v3`, `mtk_fpsgo_v8`,
`mtk_game`. Firmware menamai `.ko`-nya beda. Tidak ada pekerjaan source.
Perlu dicek apakah ada yang meng-`request_module("fpsgo")` — kalau iya,
sediakan symlink/alias di `.ko` atau di userspace.

---

## 5. Tingkat C — 38 modul, port dari donor mt6897  ⚠️ BLOKIR STRUKTURAL

### 5.0 Hasil investigasi — baca ini dulu

Waktu mulai mengeksekusi Tingkat C, ketemu dua hal yang mengubah rencana.
Keduanya terukur, bukan dugaan.

**(a) `tc_charger_class` bukan penambahan, tapi PENGGANTI.**

Transsion mem-fork `charger_class.c` MTK. Perbandingan simbol:

```
simbol diekspor charger_class.c MTK       : 104 dipakai driver lain
simbol diekspor tc_charger_class.c        : 115
simbol bentrok (nama sama, definisi beda) : 78
```

Artinya `tc_charger_class` **tidak bisa hidup berdampingan** dengan
`charger_class` MTK. Di device X6871 tidak ada `charger_class.ko` sama sekali —
hanya `tc_charger_class.ko`. Jadi ini migrasi framework, bukan tambah modul.

**(b) X6871 membuang seluruh framework charger MTK.**

Modul MTK yang kita bangun tapi **tidak ada** di firmware X6871:

```
charger_class   adapter_class   mtk_charger_framework
mtk_charger_algorithm_class     mtk_pd_adapter   mtk_pd_charging
mtk_chg_type_det  mtk_pep  mtk_pep20  mtk_pep40  mtk_pep45  mtk_pep50
mtk_hvbpc  mtk_ufcs_adapter  mtk_2p_charger
```

15 modul. Kalau Transsion dipasang, 15 modul ini harus **dilepas**, dan
`mt6375-charger`, `mt6375-battery`, `mtk_battery_manager` dll harus tetap
jalan di atas API Transsion.

Kabar baiknya: sudah diuji. `mt6375-charger.ko` di device mengimpor 6 simbol
`charger_dev_*`, dan **keenamnya disediakan** `tc_charger_class.ko`. Jadi
kompatibel — tapi ini pekerjaan ganti-fondasi, bukan salin-file.

**(c) DT menunjukkan yang benar-benar dipakai cuma 15 dari 94 modul.**

Dari 94 selisih, yang disebut di DT X6871 hanya 15:

```
aw8601af   ocp81375_v4l2   sgm37864_v4l2   pca_tfcp_ta
rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871
tc_auto_test  tc_gauge  tc_pd_adapter  tc_pmic  tc_tcpc
tc_trancare   tran_audio_control  tran_fp  tran_ldo  tran-led-core
```

Sisanya (79 modul) tidak dirujuk DT — kemungkinan besar dependensi internal
atau modul yang memang tidak dipakai build ini.

### 5.1 Ketersediaan source untuk 15 modul yang DT butuhkan

| Modul | Source ada di | Catatan |
|---|---|---|
| `tc_auto_test` `tc_gauge` `tc_pd_adapter` `tc_pmic` `tc_tcpc` | donor 6.1 | butuh fondasi Transsion (5.0a) |
| `tran_audio_control` | donor 6.1 | mandiri, 628 baris |
| `ocp81375_v4l2` `sgm37864_v4l2` | donor 6.1 | port flashlight |
| `tran_fp` | donor 6.1 | CMD, perlu TEE |
| `aw8601af` `pca_tfcp_ta` `tran_ldo` `tran-led-core` `rm69220...` | **tidak ada** | Phase 3 / cari donor |

### 5.2 Yang bisa dikerjakan tanpa ganti fondasi — hasil

Langkah 1 dikerjakan 2026-11-19. Dari 4 kandidat, **3 berhasil, 1 ditolak**.

| Modul | Baris | Hasil | Catatan |
|---|---|---|---|
| `tran_audio_control` | 716 | ✅ **ter-build** | 1 patch: `.remove` → `void` |
| `splitswitch-gpio` | 353 | ✅ **ter-build** | 1 patch: `.remove` → `void`; 4 include dibuang |
| `hiber` | 967 | ✅ **ter-build** | 3 patch: `strlcpy`→`strscpy`, 2 signature tracepoint binder |
| `leds-aw22xxx` | 1818 | ❌ **ditolak** | butuh framework `tc_led_class` (lihat bawah) |

**Kenapa `leds-aw22xxx` ditolak:** `leds-aw22xxx.c` meng-include
`tc_led_class.h` dan memakai `tc_led_device_register()`, `tc_led_ops`,
`tc_led_class`. Itu bagian dari framework LED Transsion
(`drivers/power/supply/transsion/leds/tc_led.c`), bukan modul mandiri.
Menambahkannya berarti menyeret fondasi charging/LED Transsion — persis yang
kita tunda di §5.0. File sudah dikembalikan, tidak ditinggal di tree.

**Patch yang ternyata diperlukan (6.1 → 6.12):**

| Pola | Jumlah | Contoh |
|---|---|---|
| `platform_driver.remove` kembali `void` (bukan `int`) | 2 | `splitswitch-gpio.c`, `tran_audio_control.c` |
| `strlcpy` dihapus → `strscpy` | 1 | `tran_hiber.c` |
| signature tracepoint vendor hook berubah | 2 | `android_vh_binder_preset` (+`binder_proc *`), `android_vh_binder_alloc_new_buf_locked` (+`bool *should_fail`) |

Catatan `hiber`: ia mengait ke **binder internal** lewat vendor hook. Butuh
`CONFIG_ANDROID_VENDOR_HOOKS=y` — sudah aktif di build kita, jadi aman.

**Pelajaran untuk modul berikutnya:** sebelum port, cek apakah file
meng-include header `tc_*` atau memakai `tc_*_register()`. Kalau iya, modul itu
**bukan** mandiri — tolak dan tunda sampai fondasi Transsion dipasang.


Stack audio Transsion (`aw87xxx`, `fs1599`, `oca72xxx`, `elliptic`) sekitar
70.000 baris, mandiri, tapi butuh `BUILD.bazel` DDK baru untuk tiap codec.

### 5.3 Jebakan nyata: aw36515 (sudah dicoba)

Percobaan pertama: salin `aw36515.c` dari donor 6.1. **Gagal compile** dengan
2 error:

```
aw36515.c:744: error: use of undeclared identifier 'FLASH_IOC_SET_CURRENT'
aw36515.c:1094: error: incompatible function pointer types initializing
                'int (*)(struct i2c_client *)' with 'int (struct i2c_client *,
                const struct i2c_device_id *)'
```

Sebabnya: header 6.12 (`flashlight.h`) menghapus `FLASH_IOC_SET_CURRENT`, dan
`i2c_driver.probe` di 6.12 tidak lagi menerima argumen `i2c_device_id`.

**Jalan keluarnya bukan patch, tapi pakai source yang sudah 6.12.** Donor OPPO
kita (`donor/oppo-mt6896`, tree 6.12) punya `aw36515_23021.c` yang sudah
6.12-native: `probe(struct i2c_client *client)`, tanpa `FLASH_IOC_SET_CURRENT`,
lengkap dengan `BUILD.bazel` yang sudah jalan.

Pelajaran untuk sisa Tingkat C: **cek donor OPPO 6.12 dulu sebelum port dari
6.1.** Untuk nama modul yang sama persis, OPPO 6.12 hanya punya 1 (`game`),
tapi untuk codec audio/flashlight filenya beda nama dan sudah native.

### 5.4 Rekomendasi urutan Tingkat C

1. `tran_audio_control` + `splitswitch-gpio` — bersih, ~1.000 baris, mandiri.
2. `leds-aw22xxx`, `hiber` — mandiri, ~2.800 baris.
3. `aw8601af` / `ocp81375` / `sgm37864` — pakai pola 5.3 (cari yang 6.12-natively
   di donor OPPO dulu).
4. Stack audio penuh (~70k baris) — butuh penulisan `BUILD.bazel` per codec.
5. **Charging Transsion (5 modul DT + fondasi)** — kerjakan paling akhir,
   karena ini ganti fondasi dan harus melepas 15 modul MTK (§5.0b).


---

## 6. Tingkat D — ~55 modul, belum ada source  ⚠️ AUDIT tran_* SELESAI

### 6.1 Audit lengkap semua driver `tran_*` (2026-11-19)

Firmware X6871 punya **25 modul** bernama `tran*`/`trans*`. Diperiksa satu per
satu terhadap donor mt6897, donor OPPO 6.12, dan tree w1vo:

| Modul firmware | Ada di donor? | Sumber / catatan |
|---|---|---|
| `tran_audio_control` | ✅ | `sound/soc/transsion/tran_audio_control` — **sudah dipasang & ter-build** |
| `tran_charge_transfer` | ✅ | `drivers/power/supply/transsion/` — butuh fondasi `tc_*` |
| `tran_usb_ctrl` | ✅ | `drivers/power/supply/transsion/` — butuh fondasi `tc_*` |
| `tran_fp` | ✅ (nama beda) | donor: `tran_fp_v2.o` di `drivers/input/fingerprint/tran_common_v2` |
| `tran-led-core` | ✅ (nama beda) | donor: `tc_pdlc.o` di `drivers/leds/tran_leds_pdlc` |
| `tran_richtap_haptic_hv` | ✅ (nama beda) | donor: `richtap_haptic_hv/` di `drivers/misc/mediatek/tran_lra` |
| `tran_zram` | ❌ | **fork** dari `zram` — X6871 kirim `tran_zram.ko`, bukan `zram.ko` |
| `tran-ufshcd-core` | ❌ | **fork** dari `ufshcd-core` — X6871 kirim ini, bukan `ufshcd-core.ko` |
| `tran-ufshcd-pltfrm` | ❌ | **fork** dari `ufshcd-pltfrm` |
| `tran_ldo` | ❌ | **PENTING**: DT pakai `dvdd-supply = <&TRANLDO26>`, lihat §6.2 |
| `tran_rhi` | ❌ | tidak ada di donor mana pun |
| `tran_scsi_mod` | ❌ | fork SCSI |
| `tran_sd_mod` | ❌ | |
| `tran_block` | ❌ | fork block layer |
| `trans_sched` | ❌ | fork scheduler; ada `trans_sched.ko` di firmware |
| `tran_mmc_block` | ❌ | |
| `tran_audio_typec` | ❌ | |
| `tran_extcon_usb` | ❌ | |
| `tran_health_sched` | ❌ | |
| `tran_expand_key` | ❌ | |
| `tran_perf_util` | ❌ | |
| `tran_mm_collect` | ❌ | |
| `tran_key_bigdata` | ❌ | |
| `tran-proc-bootdevice-mod` | ❌ | |
| `transsion_tranlog` | ❌ | |

**Ringkasan: 6 ada (3 sudah dipasang, 3 butuh fondasi `tc_*`), 19 tidak ada.**

Pola penting: `tran_*` yang tidak ada bukan modul tambahan, tapi **fork dari
subsistem kernel**. Kalau dipasang, ia **mengganti** modul aslinya
(`tran_zram` ↔ `zram`, `tran-ufshcd-core` ↔ `ufshcd-core`), sama seperti
`tc_charger_class` menggantikan `charger_class` (§5.0a). Itu pekerjaan
ganti-fondasi, bukan salin-file.

### 6.2 `tran_ldo` — SELESAI, tidak perlu RE

**Hasil 2026-11-19: source-nya ada, GPL-2.0. RE dibatalkan.**

Jalan penemuannya (bukan tebakan):

1. `gh search code "i2c_ldo_sclk_mode"` → ketemu
   `ramabondanp/transsion-kernel_device_modules-6.1/drivers/regulator/et5904.c`
   (mirror open-source Infinix, `opensource.dev.infinixmobility.com`).
2. `et5904.c` punya `my_regulator_enable_regmap` + discharge `RDIS` — sama
   persis dengan `.ko` firmware.
3. Pola nama: source `"ET5904LDO"#num#i2cid` == format `.ko` `TRANLDO%d%d`.
4. `et5904_regulators6[]` = LDO 1..4 di i2c bus 6 →
   `TRANLDO16 / TRANLDO26 / TRANLDO36 / TRANLDO46` == **persis** node DT X6871.
5. Rentang tegangan cocok DT:
   VIND `600000 + sel*6000` (600k–2.13M) ⊇ DT 600k–1.8M
   VINA `1200000 + sel*12500` (1.2M–4.39M) ⊇ DT 1.2M–3.3M

**Hasil build:** `tran_ldo.ko` masuk output, total 1.410 → 1.412.
Identitas cocok 100% dengan firmware:

| | kita | firmware |
|---|---|---|
| name | `tran_ldo` | `tran_ldo` |
| alias | `of:N*T*Ctran,tran_ldo` | `of:N*T*Ctran,tran_ldo` |
| description | `Tran 4LDO  driver` | `Tran 4LDO  driver` |

Keempat regulator yang dibutuhkan DT ada di `.ko` hasil build:
`TRANLDO16`, `TRANLDO26`, `TRANLDO36`, `TRANLDO46`.

Patch 6.x yang diperlukan (hanya 1):
- `probe(struct i2c_client *, const struct i2c_device_id *)` → `probe(struct i2c_client *)`

Guard `IS_ENABLED(TRAN_AD10)` / `TRAN_AE10` /
`CONFIG_TRAN_DUAL_INTERNAL_TEMP_PATCH` dibiarkan apa adanya: ketiganya tidak
didefinisikan, jadi bloknya tidak dikompilasi. Blok itu memanggil
`regulator_init_complete_mainlcm()` yang tidak ada di tree w1vo.

Catatan: `tran_ldo` memilih tabel `regulatorsN[]` berdasarkan
**i2c adapter id**, bukan compatible. X6871 pakai bus 6, jadi yang aktif
`et5904_regulators6[]`. Kalau nanti bus-nya beda, tabelnya harus disesuaikan.

### 6.2b Kenapa ini penting untuk panel

Dengan `tran_ldo` ter-build, `dvdd-supply = <&TRANLDO26>` di DT **sekarang
bisa di-resolve**. Sebelumnya rantainya putus:
`panel → dvdd → TRANLDO26 → tran_ldo (tidak ada)`.

Alur power panel (dibaca dari kode):

```
lcm_probe()
  ├─ schedule_delayed_work(3000ms)     DVDD, async
  └─ devm_regulator_get("vci") + enable
       └─ gagal → probe GAGAL

lcm_regulator_power_init()             jalan 3s kemudian
  ├─ devm_regulator_get("dvdd")        sekarang resolve ke TRANLDO26
  ├─ regulator_set_voltage(1.254V)
  └─ regulator_enable()
```

Kalau `dvdd` gagal, driver retry tiap 7 detik **selamanya**. Dengan
`tran_ldo` ada, retry itu seharusnya tidak terjadi lagi.



### 6.1b Aturan umum hasil kasus `tran_ldo` — dan audit ulang semua modul

Kasus `tran_ldo` mengajarkan satu hal yang berlaku untuk **semua** modul:

> Nama modul firmware dan nama file source tidak harus sama.
> `tran_ldo.ko` (compatible `tran,tran_ldo`) berasal dari `drivers/regulator/et5904.c`
> (compatible `tran,et5904`).

Jadi **jangan cari berdasarkan nama modul**. Cari berdasarkan sidik jari isi
`.ko`: simbol fungsi yang didefinisikan, lalu cari file source mana pun yang
mendefinisikan simbol-simbol itu. Alatnya sekarang ada di repo:

```
./audit-sources.sh <tree-source> <dir-modul-firmware> [modul...]
```

Skrip itu membaca semua `.ko`, mengindeks semua definisi fungsi di `.c/.h`,
dan mencetak file sumber terbaik per modul beserta skor `%`.

#### ATURAN WAJIB: "tidak ada `<nama>.c`" BUKAN berarti "tidak ada source"

Ini kesalahan yang sudah dua kali saya buat, dan akibatnya modul penting
sempat saya nyatakan mustahil padahal sourcenya lengkap:

> `find . -name 'tc_charger_framework.c'` mengembalikan kosong, jadi saya
> menulis "Transsion tidak pernah merilis modul ini". Kenyataannya kelima
> komponennya ada dan Makefile donor menyebutkan komposisinya secara
> eksplisit.

Modul gabungan (compound module) di kernel **tidak punya file `.c` bernama
sama dengan modulnya**. Namanya hanya ada di `Makefile` sebagai
`<modul>-objs`. Karena itu, sebelum menyimpulkan "tidak ada source", wajib
menempuh urutan berikut:

| # | Periksa | Perintah |
|---|---|---|
| 1 | file `.c` bernama sama | `find $SRC -name "<modul>.c"` |
| 2 | **entri `Makefile`** | `grep -rn "<modul>" $SRC --include=Makefile --include=Kbuild` |
| 3 | **entri `Kconfig`** | `grep -rn "<modul>" $SRC --include=Kconfig*` |
| 4 | **daftar modul bazel** | `grep -rn "<modul>" $SRC --include='*.bzl' --include=BUILD.bazel` |
| 5 | sidik jari simbol | `./audit-sources.sh` (§6.1b) |

Langkah 2 yang menjawab kasus `tc_charger_framework`:

```make
tc_charger_framework-objs := tc_charger.o tc_charger_intf.o tc_charger_attr.o \
                             tc_basic_charger.o tc_voter.o
```

Modul gabungan juga sering muncul di daftar `.bzl` Kleaf. `tc_charger_framework`
tercatat di `kernel/kleaf/mgk_64_k61.bzl` baris 587 — itu bukti tambahan yang
juga terlewat saat saya memeriksa.

**Konsekuensi praktis:** untuk modul gabungan, cara membangunnya bukan mencari
satu `.c`, tapi mendaftar semua `<modul>-objs` sebagai `srcs` dalam satu
`define_mgk_ddk_ko()`. Itulah yang dipakai untuk `tc_charger_framework`
(commit `439b840`).

Aturan ini juga berlaku untuk `hiber` (compound: `tran_hiber` +
`tran_netfilter` + `hiber_help`) yang sudah lebih dulu diport — di sana
kebetulan namanya cocok sehingga tidak terasa.

**Hasil audit ulang (2026-11-19), sumber = tree Transsion 6.1 lengkap
(7.106 file `.c/.h`, 2 GB, `android15-split`):**

Dari 91 modul gap: **47 ada source**, 13 benar-benar tidak ada, 31 tidak ada
`.ko` di firmware (jadi bukan gap).

Kelompok `tc_*` — fondasi charger Transsion:

| Modul | Skor | File sumber |
|---|---|---|
| `tc_common_class` | 100% | `drivers/power/supply/transsion/tc_common_class.c` |
| `tc_adapter_class` | 100% | `.../tc_adapter_class.c` |
| `tc_ta_class` | 100% | `.../tc_ta_class.c` |
| `tc_audio`, `tc_auto_test`, `tc_hl7139a`, `tc_lcd_notify`, `tc_phy_insert_det`, `tc_pid_chg_algo`, `tc_pmic`, `tc_port_corrosion_prevention`, `tc_tcpc`, `tc_temp_forecast` | 100% | `.../tc_*.c` |
| `tran_charge_transfer` | 100% | `.../tran_charge_transfer.c` |
| `tran_usb_ctrl` | 100% | `.../tran_usb_ctrl.c` |
| `tc_gauge` | 96% | `.../tc_gauge.c` |
| `tc_charger_class` | 96% | `.../tc_charger_class.c` (menimpa `charger_class`) |
| `tc_chg_type_det` | 95% | `.../tc_chg_type_det.c` |
| `tc_algorithm_class` | 95% | `.../tc_algorithm_class.c` |
| `tc_otg_ctrl` | 92% | `.../tc_otg_ctrl.c` |
| `tc_pd_adapter` | 88% | `.../tc_pd_adapter.c` |
| `tc_ambient_temp_det` | 87% | `.../tc_ambient_temp_det.c` |
| `tc_misc_intf` | 86% | `.../tc_misc_intf.c` |
| `tc_water_detect` | 86% | `.../tc_water_detect.c` |
| `leds-aw22xxx` | 76% | `.../leds/leds-aw22xxx/leds-aw22xxx.c` |
| `nfc_i2c` | 44% | `drivers/nfc/pn560/common.c` |

`tran_ldo` sendiri hanya 50% menurut skrip ini (modul kecil, 4 fungsi), tapi
terbukti benar — jadi skor rendah untuk modul kecil bukan berarti salah.

**Yang benar-benar tidak ada source di tree 6.1 (13):**
`pca_tfcp_ta`, `sd_tray`, `tc_hvdcp20_algo`, `tc_tc30_algo`, `tc_tfcp_ta`,
`tc_trancare`, `tkv`, `tkv_recovery`, `tran-proc-bootdevice-mod`,
`tran-ufshcd-pltfrm`, `tran_expand_key`, `tran_key_bigdata`, `tran_rhi`.

Catatan: `tran-ufshcd-pltfrm` hanya 5 fungsi dan `tran-ufshcd-core` 22% —
keduanya fork UFS, jadi tetap masuk kelompok ganti-fondasi.

`tran_fp` (14%) dan `tran-led-core` (10%) ternyata **modul gabungan**: satu
`.ko` berisi banyak vendor. `tran_fp.ko` memuat kode focaltech + goodix +
cdfinger + egis + silead + sunwave + fpsensor + chipone sekaligus (164 fungsi).
Source 6.1 hanya menyediakan inti `tran_fp_*` (39 fungsi). Untuk
`tran-led-core`, file `tc_led_class.c` hanya menyediakan 4 dari 42 fungsi dan
tidak ada string `[tlc]` di tree 6.1 — modul ini memang tidak ada.

### 6.1c Koreksi penting: "nama sama" tidak berarti "sudah match"

Cara lama menghitung cakupan (`nama modul ada di output build`) **menyesatkan**.
Setelah semua `.ko` dibangun, 172 dari 237 nama modul firmware ada di output.
Tapi setelah membandingkan **simbol yang diimpor** tiap `.ko`, hasilnya:

| | jumlah |
|---|---|
| nama sama, isi & impor **sama** | **120** |
| nama sama, isi **BEDA** | **52** |
| hanya di firmware | 65 |
| hanya di kita (modul lain, bukan target) | 483 |

**Cakupan nyata = 120/237 = 51%**, bukan 73% seperti hitungan berbasis nama.

Contoh yang paling merugikan — nama sama, tapi yang kita build versi MTK murni
sementara firmware versi Transsion:

| Modul | Simbol yang hanya diminta firmware |
|---|---|
| `mtk_battery_manager.ko` | `tc_is_si_battery`, `tc_is_support_charge_transfer`, `tran_device_register`, `tran_get_by_name` |
| `mt6375-battery.ko` | `tc_get_monkey_flag`, `tc_is_support_temp_forecast`, `tran_dev_get_prop` |
| `tcpc_class.ko` | `tc_get_uisoc`, `tran_get_by_name`, `tran_dev_get_prop` |
| `rt6160-regulator.ko` | `tran_device_register` |
| `ufs-mediatek-mod.ko` | `tran_scsi_alloc_request`, `tran_scsi_execute_cmd`, `tran_ufshcd_link_recovery`, `tran_ufs_proc_bootdevice_work` |
| `monitor_hang.ko`, `aee_hangdet.ko` | `tran_expinfo` |
| `cache-parity.ko`, `device-apc-common.ko`, `emi-mpu.ko` | `tran_record_devmsg_api` |
| `mediatek_drm_v1.ko` | `tranlog_local` |

Jadi `mtk_battery_manager.ko` yang kita build **bukan** yang dijalankan
firmware. Ini persis pola `tran_ldo`: nama tidak menceritakan isinya.

### 6.2c `tc_common_class` — SELESAI, fondasi 19 modul

Nama modul `tc_common_class`, nama file `tc_common_class.c`, tapi maknanya
bukan "charger class biasa": ia yang menyediakan `tran_device_register` /
`tran_get_by_name`, dan **19 modul firmware bergantung padanya**:

```
mt6375-battery, mtk_battery_manager, rt6160-regulator, tc_ambient_temp_det,
tc_audio, tc_charger_framework, tc_gauge, tc_lcd_notify, tc_misc_intf,
tc_otg_ctrl, tc_phy_insert_det, tc_pid_chg_algo, tc_pmic, tc_tcpc,
tc_temp_forecast, tc_trancare, tc_water_detect, tran_charge_transfer,
tran_usb_ctrl
```

Sifatnya **aditif**: tree w1vo belum punya `struct tran_device` sama sekali,
jadi tidak ada simbol bertabrakan (beda dengan `tc_charger_class` yang
menimpa `charger_class`, 80 simbol kolisi).

Sumber: `drivers/power/supply/transsion/tc_common_class.{c,h}`, 273 + 389 baris,
hanya memakai header kernel standar (`linux/device.h`, `linux/kernel.h`,
`linux/mutex.h`, `linux/slab.h`, `linux/string.h`).

**Hasil build:** `tc_common_class.ko` masuk output, 1.412 → 1.414.

Perbandingan `.ko` kita vs firmware — **nol selisih**:

| | kita | firmware |
|---|---|---|
| exports | 8 | 8 |
| imports | 23 | 23 |
| selisih ekspor | — | — |
| selisih impor | — | — |
| description | Switching Charger Class Device | sama |
| license | GPL v2 | sama |

Ekspor: `tran_device_register`, `tran_device_unregister`,
`register_tran_device_notifier`, `unregister_tran_device_notifier`,
`tran_dev_notify`, `tran_get_by_name`, `tran_dev_set_prop`, `tran_dev_get_prop`.

Patch 6.12 (2):
1. `tc_common_class.h` memakai `#if IS_ENABLED(CONFIG_TC_CLASS_SUPPORT)`.
   Config itu tidak ada di tree kita -> header jatuh ke `static inline`
   fallback dan bertabrakan dengan definisi di `.c` (`redefinition of
   'tran_dev_set_prop'` dkk). Diaktifkan lewat `copts =
   ["-DCONFIG_TC_CLASS_SUPPORT=1"]`.
2. `class_create(THIS_MODULE, "tran_class")` -> `class_create("tran_class")`
   (6.12 membuang argumen owner).

### 6.2e TEMUAN BESAR: `struct charger_ops` kita BUKAN layout firmware

**Status 2026-11-19: SUDAH DIPERBAIKI. Bug ini akan membuat charger mati
total saat boot, dan tidak terlihat dari perbandingan simbol.**

#### Apa yang salah

Perbandingan simbol (`readelf -sW`, nama ekspor/impor) hanya membuktikan
**nama** fungsi sama. Ia tidak membuktikan **layout struct** sama. Untuk
`tc_charger_class` — yang menggantikan fondasi `charger_class` — layout-lah
yang menentukan semuanya.

Kita mengukur langsung slot tiap wrapper di `.ko` firmware: di dalam
`charger_dev_*` selalu ada pola `ldr x8,[x0,#16]` (chg_dev->ops) lalu
`ldr x8,[x8,#N]`; `N/8` = indeks field. Hasil untuk
`tc_charger_class.ko` firmware, 120 wrapper:

| titik sisip | posisi firmware | isi |
|---|---|---|
| 1 | sebelum `run_aicl` | `get_mivr_gap`, `set_boot_volt_times` (2 field) |
| 2 | sebelum `enable_usbid` | 1 field tak dikenal (tidak punya wrapper, slot 71) |
| 3 | sebelum `get_ilim_state` | `pd_set_hiz_flag`, `pd_set_charge_flag` (2 field) |
| 4 | sebelum `get_wireless_authenticate` | `need_hz_ctrl` (1 field) |

Total: firmware punya **138** field, header kita **132**. Enam selisih.

Verifikasi silang: layout hipotesis (header TC + 6 sisipan di posisi itu)
dicocokkan ke **120 wrapper** firmware → **120 cocok, 0 beda**. Sisanya 14
wrapper tidak punya padanan nama (`do_event`, `get_vbus`, `get_ibus`,
`get_ibat`, `get_temperature`, `get_ts`, `get_vrefts`, `authenticate`,
`wireless_ta_get_vbus/ibus`, `volt_sync`, `get_pg_state`,
`set_reverse_boost`, `get_ce`) — perlu dipetakan ke field yang sudah ada,
bukan field baru.

#### Kenapa ini fatal, bukan kosmetik

`mt6375-charger.ko` **kita** dibangun dengan `charger_class.h` MTK
(89 field). Firmware membangunnya dengan `tc_charger_class.h` (138 field).
Slot yang sama, arti berbeda:

| slot | driver kita mengisi | `tc_charger_class` firmware membaca |
|---|---|---|
| 25 | `send_ta_current_pattern` | `set_mivr` |
| 56 | `enable_discharge` | `get_mivr_gap` |
| 57 | `set_boost_current_limit` | `run_aicl` |
| 58 | `enable_chg_type_det` | `set_boot_volt_times` |
| 59 | `run_aicl` | `reset_eoc_state` |
| 64 | `set_pe20_efficiency_table` | `get_adc` |
| 71 | `get_ibus_adc` | `enable_usbid` |
| 85 | `enable_hz` | `pd_set_charge_flag` |

Artinya: `charger_dev_get_adc()` akan memanggil `mt6375_set_pe20_efficiency_table()`.
`charger_dev_set_mivr()` akan memanggil `mt6375_send_ta_current_pattern()`.
Tidak crash — ia **memanggil fungsi yang salah dengan signature yang salah**.
Yang paling mungkin: charger tidak mau charge, atau ADC baterai salah baca.

Bukti tambahan bahwa firmware memang memakai layout TC: `mt6375-charger.ko`
firmware punya `mt6375_tran_is_water_detected` dan `mt6375_set_dp_data`,
yang **tidak ada** di `mt6375-charger.c` MTK. Keduanya ada di
`transsion/mt6375-charger.c` (3.886 baris vs 3.112).

Dan `.ko` firmware itu memakai layout hasil rekonstruksi:
`plug_in`=2, `set_charging_current`=9, `set_mivr`=25, `run_aicl`=58,
`reset_eoc_state`=59, `dump_registers`=63, `get_adc`=64, `enable_hz`=79
→ **semua cocok dengan TC+6, tidak satu pun cocok dengan MTK**.

#### Bahaya kedua: dua modul mengklaim simbol yang sama

`charger_class.ko` (MTK, 89 field) **dan** `tc_charger_class.ko` (TC,
138 field) sama-sama didaftarkan di `mgk_64.bzl` dan sama-sama masuk staging:
**84 simbol `charger_dev_*` didefinisikan oleh keduanya**. Firmware X6871
tidak mengirim `charger_class.ko` sama sekali. Jadi keduanya tidak boleh
ada bersamaan — yang menang ditentukan urutan load, dan itu tidak deterministik.

#### Hasil perbaikan (terverifikasi)

1. `tc_charger_class.h`: 6 field disisipkan pada posisi terukur → 132 → **138 field**.
   Verifikasi: 120 wrapper firmware, **120 cocok, 0 beda**.
2. `tc_charger_class.c`: 5 ekspor baru ditambahkan dengan pola guard-then-dispatch
   yang sama seperti wrapper lain.
   Verifikasi: ekspor kita **136**, firmware **136** — `comm` kosong (identik).
3. `mt6375-charger` sekarang dibangun dari `transsion/mt6375-charger.c`
   (3.886 baris), bukan `mt6375-charger.c` MTK (3.112 baris).
   Verifikasi slot `charger_ops`: **60 slot, semua cocok** dengan firmware —
   `set_mivr`=25, `run_aicc`=58, `reset_eoc_state`=59, `get_adc`=64,
   `enable_hz`=79, `set_dp_data`=89, `tran_is_water_detected`=127.
   Verifikasi impor: **identik** dengan firmware (comm kosong).
4. Build ulang: sukses, **659 `.ko`** tetap utuh.

Patch 6.12 untuk `transsion/mt6375-charger.c` (selain layout):

| masalah | perbaikan |
|---|---|
| `.usb_types = array` + `.num_usb_types` | 6.12 mengubahnya jadi bitmask `u32`; `num_usb_types` dihapus dari struct |
| `remove()` mengembalikan `int` | 6.12 `void` |

#### Rencana perbaikan

1. Sisipkan 6 field ke `tc_charger_class.h` pada posisi terukur, dengan
   signature dari pemanggil (bukan tebakan):
   - `charger_dev_need_hz_ctrl(dev)` → `int`, tanpa argumen kedua
     (dibuktikan: `tran_usb_ctrl.ko` tidak menyiapkan `w1`; `cbz w0` setelah call)
   - `charger_dev_get_mivr_gap(dev)` → `int`, tanpa argumen kedua
     (dibuktikan: `tc_charger_framework.ko` hanya menyiapkan `x0`)
   - `set_boot_volt_times(dev, u32)` → dari MTK `charger_class.c`
   - `pd_set_hiz_flag(dev, bool)`, `pd_set_charge_flag(dev, bool)` →
     `and w1,w1,#1` di wrapper membuktikan argumen kedua `bool`
   - slot 71: belum teridentifikasi, tidak punya wrapper di firmware
2. Bangun ulang, verifikasi ulang slot-per-slot (harus 0 beda).
3. Ganti `mt6375-charger.c` MTK dengan `transsion/mt6375-charger.c`.
4. Keluarkan `charger_class` MTK dari daftar modul (firmware tidak punya).
5. Audit modul lain yang sama-sama include `charger_class.h` — 8 modul kita
   dibangun dengan layout MTK, tapi hanya `mt6375-charger` yang ada di
   firmware X6871; sisanya (`rt9490`, `rt9758`, `mtk_chg_type_det`,
   `mtk_2p_charger`, `rt9759`, `bq2589x_charger`) tidak dikirim firmware.

#### Pelajaran umum

Aturan §6.1b ("cocokkan lewat isi `.ko`, bukan nama") **belum cukup**.
Perbandingan simbol hanya lapisan pertama. Untuk modul yang **mendefinisikan
struct yang dipakai lintas modul**, yang wajib dibandingkan adalah
**layout struct**, dan cara mengukurnya adalah offset `ldr` di wrapper —
bukan daftar nama simbol.

### 6.2d Fondasi charger Transsion — 4 modul, 3 IDENTIK

**Catatan: Transsion hanya merilis source kernel 6.1, tidak pernah 6.12.**
Jadi apa pun yang dipakai firmware 6.12 tapi tidak ada di source 6.1 harus
direkonstruksi dari `.ko`, bukan ditunggu.

Satu paket: `tc_charger_class` + `tc_adapter_class` + `tc_algorithm_class` +
`tc_misc_intf` (+ `tc_common_class`, §6.2c).

**Kenapa satu paket.** `tc_misc_intf` tidak standalone. Di firmware X6871 ia
mengimpor dari ketiga modul lain:

| simbol diimpor | penyedia |
|---|---|
| `get_charger_by_name`, `charger_dev_get_{adc,vbus,ibus}` | `tc_charger_class` |
| `get_tadapter_by_name`, `tadapter_dev_get_property` | `tc_adapter_class` |
| `get_tchg_alg_by_name`, `tchg_alg_get/set_prop` | `tc_algorithm_class` |
| `mt_boot_finish` | `mtprof:bootprof` |

**`tc_charger_class` menggantikan `charger_class` MTK**, bukan menambah:

- firmware X6871 **tidak mengirim** `charger_class.ko`
- `tc_charger_class.ko` **mendefinisikan** 115 simbol `charger_dev_*`
  (bukan mengimpor) — jadi ia implementasi lengkap
- 80 simbol bertabrakan dengan `charger_class.c` MTK di tree kita

Ini ganti-fondasi: begitu `tc_charger_class` aktif, `charger_class.ko` MTK
tidak boleh ikut, dan semua pengguna `charger_dev_*` beralih ke versi Transsion.

**Hasil build + verifikasi isi terhadap firmware:**

| modul | ekspor kita/fw | impor kita/fw | status |
|---|---|---|---|
| `tc_common_class` | 8 / 8 | 23 / 23 | **IDENTIK** |
| `tc_adapter_class` | 22 / 22 | 19 / 19 | **IDENTIK** |
| `tc_algorithm_class` | 17 / 17 | 19 / 19 | **IDENTIK** |
| `tc_misc_intf` | 50 / 50 | 31 / 41 | ekspor identik, impor beda* |
| `tc_charger_class` | 127 / 132 | 21 / 21 | kurang 5 |

\* Selisih impor `tc_misc_intf` bukan bug: build DDK meng-optimize habis jalur
sysfs/DT (dead code elimination). Terbukti modul MTK pun (`charger_class.ko`,
`mt6375-charger.ko`, `tc_charger_framework.ko`) **tidak** mengimpor
`sysfs_create_group` di build kita, padahal source-nya memakainya.
Dialog `tc_misc_sysfs_init()` juga hilang total dari `.ko`. Jadi impor tidak
bisa dipakai sebagai kriteria untuk modul yang menyentuh sysfs.

**Yang tidak bisa disalin dari source 6.1:**

| modul | kurangan | cara |
|---|---|---|
| `tc_misc_intf` | 8 ekspor (`tc_is_si_battery`, `tc_is_support_*`, `tc_get_battery_id`, `tc_is_dts_node_available`) | **direkonstruksi**, lihat di bawah |
| `tc_charger_class` | 5 ekspor (`charger_dev_get_mivr_gap`, `charger_dev_need_hz_ctrl`, `charger_dev_pd_set_charge/hiz_flag`, `charger_dev_set_boot_volt_times`) | belum |

**Bukti rekonstruksi 8 fungsi `tc_misc_intf` (bukan tebakan):**

1. Pola seragam, terverifikasi per-fungsi di disassembly:
   ```
   info = tc_get_misc_info();   /* helper yang memang ada di 6.1 */
   if (!info) -> error, return 0
   if (cached) -> return cached
   np = of_find_compatible_node(NULL, NULL, compatible)
   cached = of_device_is_available(np)
   ```
2. Tabel `dtsi_check_fea_list` (5 entri di `.data`) dipulihkan **lengkap** dari
   relokasi `R_AARCH64_ABS64`:
   `tran,otg_fun`, `transsion, charge_transfer`, `tran,battery_manager`,
   `tc,temp_forecast`, `transsion, adapter_control`
3. `TRAN_PROP_BATTERY_ID` = 49 di source 6.1, dan firmware memakai
   `mov w1, #0x32` (50) — enum identik, aman dipakai.
4. Offset `struct misc_info` di firmware (16/24, 32/40, 48/56, 64/72) memang
   berbeda dari source 6.1. **Tidak masalah**: struct itu internal modul ini,
   jadi yang wajib sama adalah nama ekspor + signature + perilaku.

Patch 6.12 yang diperlukan:

1. `class_create(THIS_MODULE, "x")` -> `class_create("x")` (3 file)
2. `const char *const f(...)` -> `const char *f(...)` (`-Wignored-qualifiers`)
3. platform `.remove`: `int` -> `void`, buang `return 0;`
4. `tc_misc_intf.h` butuh rantai header transitif penuh (`tc_charger.h`,
   `tc_voter.h`, `tc_tcpc.h`, `tc_gauge.h`)
5. `ko_deps`: 4 modul `tc_*` + `mtprof:bootprof`

Skrip: `add-tc-charger-stack.sh` + `patch-tc-misc-6.12.sh` +
`patches/tc_misc_intf_6_12_extra.c`, semuanya **reproduksi byte-identik**.

### 6.2g TEMUAN: `struct tcpc_ops` juga drift — belum diperbaiki

Pola yang sama seperti §6.2e muncul lagi, kali ini di `tcpc_class`. Saat
mencoba `tc_tcpc`, build gagal karena `tcpm_tran_inquire_remote_cc` tidak ada.
Ternyata fungsi itu memanggil `tcpc->ops->tran_get_cc_status`, dan field itu
**tidak ada** di `tcpc_ops` versi kita.

Perbandingan `struct tcpc_ops` — **diukur dari `.data` `tcpc_mt6375.ko`
firmware**, bukan dari header. Slot ditemukan lewat relokasi
`R_AARCH64_ABS64` ke `.text`; `base` dikalibrasi dari `mt6375_tcpc_init`
(selalu field 0, di 0x130).

| | jumlah field |
|---|---|
| firmware | **37** |
| kita (dan Transsion 6.1) | 32 |

Pemetaan lengkap hasil ukur (yang terisi di `tcpc_mt6375.ko`):

| idx | firmware | kita |
|---|---|---|
| 0–16 | sama | sama |
| **17** | **`tran_get_cc_status`** | `set_water_protection` |
| **18** | **`get_pdphy_vid`** | `set_cc_hidet` |
| **19** | **`get_pdphy_pid`** | `get_cc_hi` |
| **20** | **`get_pdphy_did`** | `set_vbus_short_cc` |
| 21 | `set_water_protection` | `set_low_power_mode` |
| 22 | `set_cc_hidet` | `set_force_discharge` |
| 23 | `get_cc_hi` | `reset_ctd` |
| 24 | `set_vbus_short_cc` | **`set_command`** ← dibuang di firmware |
| 25 | `set_low_power_mode` | `set_msg_header` |
| 26 | `set_force_discharge` | `set_rx_enable` |
| 27 | `reset_ctd` | `get_message` |
| **28** | **`source_vbus`** | `protocol_reset` |
| **29** | **`enable_io_boost`** | `transmit` |
| 30 | `set_msg_header` | `set_bist_test_mode` |
| 31 | `set_rx_enable` | `retransmit` |
| 32–36 | `get_message`, `protocol_reset`, `transmit`, `set_bist_test_mode`, `retransmit` | — |

Jadi: firmware = 32 field 6.1 **+ 6 field baru − `set_command` = 37**.
Enam field baru itu disisipkan di dua titik (4 sesudah `get_vbus_voltage`,
2 sesudah `reset_ctd`), jadi semua field sesudahnya bergeser.

Nama kelima field baru dibaca dari fungsi yang mengaksesnya di
`tcpc_class.ko` firmware, bukan ditebak:

| slot | offset akses | fungsi pemakai | signature |
|---|---|---|---|
| 18 | `[x8,#144]` @0x4b44 | `tcpci_get_pdphy_vid` | `(tcpc, u16 *vid)` |
| 19 | `[x8,#152]` @0x4b90 | `tcpci_get_pdphy_pid` | `(tcpc, u16 *pid)` |
| 20 | `[x8,#160]` @0x4bdc | `tcpci_get_pdphy_did` | `(tcpc, u16 *did)` |
| 28 | `[x8,#224]` @0x5f64 | `tcpci_source_vbus` | `(tcpc, u8 type, int mv, int ma)` |
| 29 | `[x8,#232]` @0x63bc | `tcpci_enable_io_boost` | `(tcpc, bool en)` |

Slot 17 (`tran_get_cc_status`) signature-nya `(tcpc, int *cc1, int *cc2)`,
dari `tcpm_tran_inquire_remote_cc()` di `tcpm.c` 6.1.

Catatan penting: `set_water_protection`, `set_force_discharge`, dan `reset_ctd`
dipagari `#if CONFIG_WATER_DETECTION` / `CONFIG_TYPEC_CAP_FORCE_DISCHARGE` /
`CONFIG_CABLE_TYPE_DETECTION`. **Layout struct ini bergantung config.** Jadi
header harus dipakai dengan config yang sama di semua modul yang berbagi
`tcpc_ops`, kalau tidak offset-nya bergeser lagi.

**SUDAH DIKERJAKAN (commit `3351b6c`).** Enam field disisipkan di dua titik
(slot 17-20 dan 28-29). Hasil verifikasi:

| pemeriksaan | hasil |
|---|---|
| slot `tcpc_ops` di `tcpc_mt6375.ko` | **33 == 33, 0 beda** |
| ekspor `tcpc_class.ko` | 632 vs 635; 3 sisanya tidak diimpor modul mana pun |

Koreksi penting saat mengerjakan: slot 28 **bukan** `source_vbus()` baru,
melainkan `set_command` yang **dipindah** dari slot 24. Buktinya
`tcpci_source_vbus` (@0x5f64) dan `tcpci_sink_vbus` (@0x60c8) sama-sama
membaca `ops+224` dan menaruh konstanta perintah di `w1` — 119/102 untuk
source, 85/68 untuk sink, persis kontrak `TCPM_CMD_ENABLE/DISABLE_*_VBUS`
6.1. Pembacaan pertama saya yang mengira itu op baru **salah**, dan
disassembly pemanggilnya yang membetulkan.

Tiga simbol yang tidak bisa dipulihkan (`tcpci_get_pe50_det_done`,
`tcpc_retry_enter_low_power_mode`, `tcpm_set_aw_pps_ops`) tidak diimpor
modul firmware mana pun, jadi tidak memblokir apa pun.

Sampai itu selesai, `tc_tcpc`, `tc_port_corrosion_prevention`, `tc_pd_adapter`
dan `tc_water_detect` tidak bisa dipasang.

**Catatan metode.** `tcpc_ops` ada di `.data`, bukan `.rodata`, karena tabel
itu `static struct` (bukan `const`). Skrip `ops-offsets.sh` yang saya pakai
untuk `charger_ops` hanya membaca `.rela.rodata`; untuk `tcpc_ops` harus
`.rela.data`. Alamat prosedur di `.text` untuk modul ini juga di section 14,
bukan 16.

### 6.2f Port `tc_*` tambahan (lanjutan 6.2d)

Setelah fondasi charger masuk, 20 dari 61 modul yang masih hilang ternyata
punya source di donor 6.1. Dua yang pertama sudah selesai:

| modul | ekspor | impor | status |
|---|---|---|---|
| `tc_ta_class` | 35 = 35 | 9 = 9 | **IDENTIK** |
| `tc_hl7139a` | 2 GLOBAL = 2 | beda karena config | **BENAR** |

`tc_ta_class` — kelas device untuk travel adapter, nol dependensi `tc_*`.
Patch 6.12: `class_create(THIS_MODULE, ...)`.

`tc_hl7139a` — driver Richtek HL7139A, **hardware nyata** di X6871:
DT punya `hl7139_master@55` (primary_dvchg) dan `hl7139_slave_change@55`
(secondary_dvchg). Ekspor GLOBAL identik (2 == 2).

Selisih impor di `tc_hl7139a` bukan bug, dan ini **pelajaran baru**:

- `get_charger_by_name` dan `msleep` ada di firmware, tidak di kita → keduanya
  di dalam `#if IS_ENABLED(CONFIG_TC_WIRELESS_CHARGER)`. DT X6871 **tidak
  punya node `wireless_manager`**, jadi jalur itu memang harus mati.
- kita mengimpor `tc_get_alias_type`, firmware tidak → jalur non-wireless
  memakainya, dan compiler firmware meng-inline-nya.
- 3 simbol `LOCAL` di firmware (`hl7139a_set_notify`, `hl7139a_parse_dt_bool`,
  `hl7139a_parse_dt_u32`) tidak diekspor; di build kita mereka ter-inline.
  **Jangan bandingkan `LOCAL FUNC`** — yang menentukan adalah `GLOBAL`.

Aturan tambahan untuk §6.1b: saat membandingkan simbol, filter dulu ke
`GLOBAL` (yang benar-benar diekspor). `LOCAL` adalah keputusan inlining
compiler dan tidak memengaruhi kompatibilitas antar-modul.

Patch 6.12 `tc_hl7139a`: `i2c probe()` kehilangan argumen `i2c_device_id`;
include `tc_misc_intf.h` dikeluarkan dari guard `CONFIG_TC_CHARGER` (Kconfig
itu tidak ada di tree ini, sehingga `tc_get_alias_type` hilang).

### 6.2h Hasil port `tc_*` — ringkasan

| modul | ekspor GLOBAL | impor | status |
|---|---|---|---|
| `tc_ta_class` | 35 == 35 | 9 == 9 | **IDENTIK** |
| `tc_hl7139a` | 2 == 2 | config | **BENAR** |
| `tc_lcd_notify` | 2 == 2 | ±1 | **IDENTIK** |
| `tc_pmic` | 5 == 5 | == | **IDENTIK** |
| `tc_audio` | 2 == 2 | ±1 | **IDENTIK** |
| `tc_phy_insert_det` | 2 == 2 | ±3 | **IDENTIK** |
| `tc_tcpc` | 11 vs 10 | 22 vs 18 | `tc_maybe_dock` ekstra* |
| `tc_port_corrosion_prevention` | 2 == 2 | 7 == 7 | **IDENTIK** |
| `tc_water_detect` | 3 == 3 | — | **IDENTIK** |
| `tc_pd_adapter` | 7 == 7 | — | **IDENTIK** |

\* `tc_maybe_dock` tidak ada di firmware sama sekali: struct `tc_tcpc` di sana
tidak punya field `usb_docking_judge`, jadi jalur itu di-compile-out. Tidak ada
modul firmware yang mengimpornya, jadi aman.

Modul hilang: **61 → 51** dari 237. Total `.ko` di staging: 669.

### 6.2i `tc_charger_framework` — SELESAI, dibangun dari source 6.1

**Status 2026-11-19: sudah dibangun (commit `439b840`).**

Catatan lama saya menyebut modul ini "tidak pernah dirilis". Itu **salah**.
Komposisinya tertulis jelas di Makefile donor:

```make
obj-$(CONFIG_TC_CHARGER) += tc_charger_framework.o ...
tc_charger_framework-objs := tc_charger.o tc_charger_intf.o tc_charger_attr.o \
                             tc_basic_charger.o tc_voter.o
```
  `drivers/power/supply/transsion/Makefile`, baris 12

Jadi yang tidak ada hanyalah **file .o terpisah**; kelima sumbernya lengkap
(8.598 baris). Modulnya cukup dibangun sebagai satu unit.

#### Kenapa dulu saya menolak, dan kenapa sekarang benar

Kekhawatiran lama: shim akan bertabrakan dengan `tc_charger_framework.ko` asli.
Begitu **semua modul diganti hasil build dari source**, tidak ada modul asli
yang tersisa untuk bertabrakan. Jadi ini bukan shim — ini modul yang benar.

#### `tranlog_local` ternyata bukan penghalang

`tc_charger_framework.ko` firmware mengimpor `tranlog_local` dari
`transsion_tranlog` (yang tidak punya source). Tapi:

- dipanggil **2 kali saja**, keduanya di dalam `charger_routine_thread`
- murni logging
- **source 6.1 tidak punya panggilan itu sama sekali** — ditambahkan di 6.12

Jadi build dari source tidak pernah menyentuh `tranlog_local`, dan
`transsion_tranlog` tidak perlu ada.

#### Hasil verifikasi

| pemeriksaan | hasil |
|---|---|
| ekspor GLOBAL | **74 dari 78** |
| impor `tc_*`/`tran_*` | **29/29 terpenuhi** (tc_misc_intf 24, tc_common_class 5, tc_tcpc 1) |
| alias DT | `of:N*T*Ctc,charger` — identik dengan firmware |
| node DT X6871 | ada, `compatible = "tc,charger"` dengan `enable_sw_jeita`, `enable_hv_charging`, `support_allround_bypass` |

Empat ekspor yang belum ada (`charger_cloud_engine_init/exit`,
`tc_bat_repair_dischg_vote`, `tc_update_bat_self_repair_state`) adalah kode
6.12 yang tidak ada di source 6.1, dan **tidak diimpor modul firmware mana
pun**. Bukan penghalang build maupun load.

#### Kenapa layout struct internal tidak masalah

`struct tc_data` kita 3000 byte, firmware minimal 3220 (field terbaca di
offset 3216). Tapi yang wajib sama hanya yang **melintasi batas modul**:

| struktur | dipakai lintas modul? | kesimpulan |
|---|---|---|
| `struct tc_data` | tidak — hanya `tc_charger_framework` | bebas |
| `struct tc_charger` | ukuran 104 byte, hanya simpan pointer | bebas |
| `struct votable` | **opaque** (`struct votable;` di header) | bebas |
| API voter (`vote`, `find_votable`, …) | ya, 7 modul | yang penting signature, bukan layout |

`static inline` di `tc_charger.h` yang menyentuh `data->alg[i]`
(`tc_chg_alg_notify_call`, `tc_chg_alg_plugout_reset`) tidak dipanggil modul
lain — sudah diverifikasi dengan `nm -u` terhadap 14 modul.

### 6.2j Status akhir port `tc_*`

Modul hilang: **61 → 46** dari 237.

Sudah masuk dan terverifikasi identik: `tc_common_class`, `tc_adapter_class`,
`tc_algorithm_class`, `tc_misc_intf`, `tc_ta_class`, `tc_hl7139a`,
`tc_lcd_notify`, `tc_pmic`, `tc_audio`, `tc_phy_insert_det`, `tc_tcpc`,
`tc_port_corrosion_prevention`, `tc_water_detect`, `tc_pd_adapter`,
`tc_temp_forecast`, `tc_otg_ctrl`.

Sudah masuk setelah `tc_charger_framework` dibangun:
`tc_charger_framework`, `tc_ambient_temp_det`, `tc_pid_chg_algo`.

Belum ada source sama sekali: `tc_gauge`,
`tc_chg_type_det`, `tc_auto_test`, `tc_trancare`, `tc_pep50`,
`tc_pd_algo`, `tc_pe20_algo`, `tc_hvdcp20_algo`, `tc_tc30_algo`,
`tc_tfcp_ta`, `pca_tfcp_ta`.

### 6.2k 7 modul "hilang" ternyata modul GKI — bukan gap

Menjalankan aturan §6.1b pada sisa modul menemukan 7 yang tidak tercatat:
`arm_dsu_pmu`, `drm_display_helper`, `drm_dma_helper`,
`industrialio-triggered-buffer`, `kfifo_buf`, `reboot-mode`,
`syscon-reboot-mode`.

Semuanya terdaftar di `kernel/kleaf/mgk_modules.bzl`, tapi di
**`mgk_module_ext_outs`** — dan `ext_outs` dirujuk oleh `user_outs`, bukan oleh
target yang kita bangun.

Buktinya di `build/bazel_mgk_rules/mgk.bzl:431`:

```python
kernel_modules_install(
    name = "{}_customer_modules_install.{}".format(name, build),
    kernel_modules = [
    ] + select({ ... "{}".format(m) for m in (kleaf_customer + real_kleaf_device_modules) ...})
```

`customer_modules_install` hanya memuat `kleaf_customer + kleaf_device_modules`.
`common_user_modules` (yang berisi `mgk_module_user_outs` ->
`mgk_module_ext_outs`) masuk ke target `{}_internal_modules_install`, bukan ke
target device.

Jadi ketujuh modul itu **dibangun oleh GKI build**, bukan oleh
`kernel_device_modules-6.12`. Tidak ada yang perlu dikerjakan, dan tidak
seharusnya dihitung sebagai gap.

Catatan: `arm_dsu_pmu` memang di-`remove()` eksplisit untuk beberapa platform
(`mgk_64.bzl:3424` dan `:4083`), jadi untuk platform itu ia memang tidak
dipakai sama sekali.

**Pelajaran untuk aturan §6.1b:** langkah 4 (cek `.bzl`) tidak cukup hanya
mencari namanya. Yang menentukan adalah **daftar mana** ia berada —
`mgk_module_outs` / `mgk_module_ext_outs` / `mgk_64_module_outs` — karena
hanya `mgk_64_module_outs` yang masuk target device. Cari namanya di `.bzl`
lalu periksa daftarnya.

### 6.2l Hasil port tahap terakhir + bug panel yang ditemukan

Modul hilang: **49 → 40** dari 237. Total `.ko` di staging: 680.

Ditambahkan dan terverifikasi:

| modul | ekspor | status |
|---|---|---|
| `tc_pd_algo` (gabungan `tc_pd.o` + `tc_pd_hal.o`) | 29 == 29 | IDENTIK |
| `tc_auto_test` | 3 == 3 | IDENTIK |
| `tc_gauge` | 32 vs 33 | `gauge_get_battery_id` 6.12-only, tak dipakai |
| `tc_chg_type_det` | 2 == 2 | IDENTIK |
| `tran_charge_transfer` | 4 vs 6 | 2 fungsi 6.12-only, tak dipakai |
| `tran_usb_ctrl` | 2 == 2 | IDENTIK |

#### Bug panel: dua simbol warisan donor yang bocor jadi GLOBAL

`panel-rm69220-vdo-x6871.c` berasal dari donor mt6897. Dua fungsi
(`mtk_get_res_switch_type`, `mtk_scaling_mode_mapping`) ikut terbawa, dan
karena tidak diberi `static` keduanya menjadi **GLOBAL dan diekspor**.

Panel firmware X6871 **tidak punya kedua simbol itu sama sekali** — bukan
LOCAL, memang tidak ada. Sementara di tree ini ada **9 modul panel lain** yang
mendefinisikan nama yang sama (`panel-alpha-jdi-nt36672e-*`,
`panel-nt37801-*`, `panel-rm692h5-*`). Jadi build punya definisi global ganda.

Keduanya hanya dipakai lewat tabel ops panel, tidak pernah dipanggil modul
lain, jadi `static` adalah linkage yang benar.

Setelah diperbaiki: **3 == 3 identik** (`get_mode_by_id`, `init_module`,
`cleanup_module`), persis seperti firmware.

**Pelajaran:** "berhasil build" bukan bukti isi benar. Bug ini hanya ketahuan
karena membandingkan ekspor `.ko` kita dengan `.ko` firmware — modulnya
sendiri berfungsi normal, yang rusak adalah namespace global bersama.

#### `tran-led-core` — satu-satunya sisa yang memblokir modul ber-source

`leds-aw22xxx` (1.818 baris, source tersedia) butuh
`tran_led_device_register` / `tran_led_device_unregister` dari
`tran-led-core`. Modul itu **tidak punya source** di donor mana pun (sudah
diperiksa lewat Makefile, Kconfig, dan `.bzl` sesuai §6.1b). Ekspornya 19
fungsi, dan hanya 3 yang dipakai modul lain.

LED bukan jalur boot, jadi ini sengaja ditunda.

### 6.2m RE 6 algoritma charging: `tc30`/`hvdcp20` = `pe20` dengan prefix diganti

Dugaan bahwa algoritma Transsion adalah fork dari MTK terbukti — tapi bukan
fork dari yang diduga. Sumber resmi Transsion (`android15_kernel_modules_
and_devicetree_mt6897.tar.gz`, 1.789.217.399 byte, sudah ada di disk) **tidak
memuat** `tc30`/`hvdcp20` sama sekali, baik sebagai nama file maupun sebagai
`CONFIG_MTK_TC30_SUPPORT` di Kconfig. Jadi jalurnya memang RE.

#### Ekstraksi tarball sebelumnya tidak lengkap

`ts61-full` hanya berisi 8.789 dari 30.054 file. Ekstraksi ulang paralel
(`pigz -dc ... | tar -x`) menunjukkan 52 file `.c/.h` belum pernah diekstrak —
semuanya `drivers/clk/mediatek` dan `drivers/char/rpmb`, **tidak ada satu pun
file charger**. `drivers/power/supply` sudah lengkap 201/201. Jadi kesimpulan
"tidak ada source" tetap sah, tapi sekarang dibuktikan dengan tree yang benar.

Catatan: `tar` gzip satu inti butuh >3 menit dan sempat mati di tengah;
`pigz` 96 inti menyelesaikan 7.106 file `.c/.h` dalam <60 detik.

#### Hasil RE: ketiga modul adalah satu source

Membandingkan **seluruh fungsi terkompilasi** (bukan hanya ekspor), setelah
normalisasi prefix `pe20_`/`tc30_`/`hvdcp20_` menjadi `X`:

```
pe20 = 36 fungsi   tc30 = 34 fungsi   hvdcp20 = 34 fungsi

tc30    − pe20 = { ta_dev_set_usb_ctrl_tc30 }
pe20    − tc30 = { reset_ta, set_current_pattern, ta_dev_set_usb_ctrl_pe20 }

hvdcp20 − pe20 = { ta_dev_set_usb_ctrl_hvdcp20 }
pe20    − hvdcp20 = { reset_ta, set_current_pattern, ta_dev_set_usb_ctrl_pe20 }
```

Selisih `tc30` dan `hvdcp20` satu sama lain hanya **nama satu fungsi**
(`ta_dev_set_usb_ctrl_{tc30,hvdcp20}`). Artinya ketiganya satu kerangka yang
sama; `tc30`/`hvdcp20` adalah `pe20` tanpa dua fungsi `reset_ta` /
`set_current_pattern`, diganti satu fungsi `ta_dev_set_usb_ctrl_*`.

#### Perbedaan perilaku yang nyata (dari string DT)

| | pe20 | tc30 | hvdcp20 |
|---|---|---|---|
| `recover_7v5_gap` | – | ✓ | – |
| `recover_9v_gap` | – | – | ✓ |
| `usb_control` | – | ✓ | ✓ |
| `port_burn` | – | ✓ | – |

Ketiganya berbagi `chr_volt`, `chr_volt_mivr`, `chr_volt_input_cur`,
`chr_volt_chg_cur`, `ta_ichg_level_threshold`, `ta_stop_battery_soc`,
`vbat_threshold` — persis tujuh properti yang dibaca `tc_pe20.c`.

`tc30`/`hvdcp20` mengganti `charger_dev_reset_ta` /
`charger_dev_send_ta20_current_pattern` (API MTK) dengan `usb_control`
(API Transsion, lewat `tran_usb_ctrl`). Itu sebabnya dua fungsi `reset_ta`
dan `set_current_pattern` hilang: mekanismenya pindah ke `ta_dev_set_usb_ctrl_*`.

**Konsekuensi:** `tc_tc30_algo` dan `tc_hvdcp20_algo` bisa dibangun dari
`tc_pe20.c` + `tc_pe20_hal.c` dengan prefix diganti dan dua fungsi dihapus,
lalu `ta_dev_set_usb_ctrl_*` diarahkan ke `usb_control`. Tidak perlu menulis
~2.000 baris dari nol.

### 6.2n Sisa 35 modul: apa yang benar-benar bisa dikerjakan

Setelah `tc_pe20_algo`/`tc_tc30_algo`/`tc_hvdcp20_algo`/`tc_pep50`/`tc_tfcp_ta`
masuk, sisa gap **35 modul**. Dikelompokkan menurut apakah ada jalan nyata:

#### Bukan gap — dibangun GKI (§6.2k)

`arm_dsu_pmu`, `drm_display_helper`, `drm_dma_helper`,
`industrialio-triggered-buffer`, `kfifo_buf`, `reboot-mode`,
`syscon-reboot-mode`. Ketujuhnya di `mgk_module_ext_outs`.

#### Sudah ada, tinggal alias/nama

- `rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871` — modul kita
  `panel-rm69220-vdo-x6871.ko`, ekspor **3 == 3 identik**, alias DT sama
  persis (`of:N*T*Crm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871`). Yang beda
  hanya nama file; autoload ikut alias, bukan nama.
- `rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_cl8` — **tidak direncanakan**.
  Perangkat target hanya X6871 dan DT `panel1@0` hanya memakai compatible
  `...144hz,x6871`; CL8 tidak punya node DT di X6871.

#### Satu dependency hilang, tapi dependency-nya di luar cakupan charger

`tc_trancare` (`status = "okay"` di DT, jadi aktif). Ekspornya hanya satu
fungsi (`tc_upload_tranlog_chgic_check`) dan **tidak diimpor modul mana pun**.
Blocker-nya `transsion_tranlog` — **92 fungsi, 108 KB**, tanpa source di
tarball resmi (sudah diperiksa lewat file, Makefile, dan Kconfig).

`transsion_tranlog` bukan modul charger: ia membawa `cloudengine_*`,
`athena_*`, `arraylist_*`, dan `__tran_kfifo_*` — satu stack telemetri
lengkap. Enam fungsi yang dipakai `tc_trancare` (`alloc_msg`, `free_msg`,
`msg_put_int`, `msg_put_string`, `submit_msg`, `tranlog_local`) hanya ~2,6 KB,
tapi `submit_msg` sendirian memanggil `strlen`/`memcpy`/`kstrtoll`/`kstrtoint`
/`simple_strtol` untuk mem-parse format string. Merekonstruksinya berarti
menulis parser format sendiri tanpa spesifikasi.

Catatan penting: `tc_charger_framework` dan `tc_water_detect` — yang **sudah
diport dan build bersih** — sama-sama mengimpor `transsion_tranlog` di
firmware, tapi build kita tidak: jalur itu di-gate saat compile. Jadi charger
inti tidak bergantung pada tranlog.

#### Storage path — beda arsitektur, bukan modul lepas

`tran-ufshcd-core` (145 ekspor), `tran-ufshcd-pltfrm`, `tran_scsi_mod`,
`tran_mmc_block`, `mtk-mmc-mod`, `sd_tray`, `tran_block`, `tran_sd_mod`,
`tran-proc-bootdevice-mod`, `low_latency_sched`.

Ini **bukan** tambahan kecil: `tran-ufshcd-core` adalah fork penuh `ufshcd.c`
dengan hook (`scsi_host_alloc_hook`, `ufshcd_lba_tag_release_hook`,
`ufshcd_queuecommand_first_hook`, `ufshcd_transsion_mq_init`).

Yang menentukan: di device config, `CONFIG_SCSI_UFSHCD=y` — **built-in**.
`tran_ufshcd_*` tidak ada di vmlinux kita, dan firmware mengirim
`ufs-mediatek-mod.ko` + `tran-ufshcd-core.ko` sebagai modul. Jadi firmware
memang memakai implementasi UFS berbeda dari yang built-in di tree ini.
Menyamakan itu berarti mengganti storage path, bukan menambah modul — dan
`sdcard_hw_reset`/`msdc_*` menyentuh jalur boot.

**Keputusan 2026-11-19:** kelompok ini memakai **Opsi A (baseline GKI/MTK)**.
Tidak diport. Rincian bukti, inventaris fork, dan rencana ada di §6.2s.

#### Sisanya: fitur, bukan jalur boot

`leds-aw22xxx` (+`tran-led-core`), `nfc_i2c`, `tran_fp`, `tran_rhi`,
`tran_extcon_usb`, `tran_expand_key`, `tran_key_bigdata`, `tkv`,
`tkv_recovery`, `tnek`, `thd`, `pca_tfcp_ta`.

`ili7838e_*` dan `rm69220_..._cl8` **tidak direncanakan**: perangkat target
hanya X6871, dan DT X6871 hanya punya compatible `...144hz,x6871`.

`pca_tfcp_ta` (20 fungsi, semua LOCAL) adalah lapisan protokol di atas
`tc_tfcp_ta` yang baru diport. Semua `tc_ta_device_*` yang ia impor sudah
tersedia di `tc_ta_class`. Ini kandidat terbaik berikutnya.

### 6.2o Hasil akhir 6 algoritma charging

| modul | ekspor | status |
|---|---|---|
| `tc_pe20_algo` | 24 == 24 | IDENTIK |
| `tc_tc30_algo` | 22 == 22 | IDENTIK |
| `tc_hvdcp20_algo` | 22 == 22 | IDENTIK |
| `tc_tfcp_ta` | 2 == 2 | IDENTIK (RE penuh dari `.ko`) |
| `tc_pep50` | 71 vs 89 | 18 fungsi qc3/rfc/wireless — inert di X6871 |
| `tc_trancare` | — | butuh `transsion_tranlog` |

Untuk `tc_pep50`: 18 fungsi yang tidak bisa dibangun
(`pe50_{qc3,rfc,wireless}_algo_*`, `pe50_*_get_ita_lmt`,
`pe50_is_wireless_online`) tidak ada di source resmi mana pun, tidak diimpor
satu modul pun di firmware X6871, dan `frag0.dts` tidak punya node
qc3/wireless/rfc. Jadi bukan gap porting — memang tidak dipakai device ini.

`tc_tfcp_ta` dan `pca_tfcp_ta` adalah dua modul yang **direkonstruksi penuh
dari firmware `.ko`**, bukan dari source. Yang membuatnya bisa tepat:

1. Keduanya implementasi murni dari interface yang **dipublikasikan** —
   `struct tc_ta_device_ops` (27 callback) dan `struct tadapter_ops`
   (19 callback). Fungsi `.ko` cocok 27/27 dan 12/12 dengan slot yang dipakai.
2. `.ko` tidak di-strip, jadi nama fungsi, call graph (`R_AARCH64_CALL26`),
   dan isi tabel ops (`R_AARCH64_ABS64` di `.rela.data`) terbaca.
3. Register map `tc_tfcp_ta` terbaca dari immediate `mov w1, #0x..`
   (0xa0 verinfo … 0xb3 wdt).

**Pelajaran yang berulang:** versi pertama `tc_tfcp_ta` build hijau tapi tidak
mendaftarkan apa pun dan memakai `i2c_transfer` biasa; versi pertama
`pca_tfcp_ta` build hijau tapi punya tabel ops yang salah. Keduanya hanya
ketahuan dari membandingkan **impor dan tabel relokasi** dengan firmware —
bukan dari build.

### 6.2p `nfc_i2c` selesai — 33 modul sisa

`nfc_i2c` adalah modul gabungan keempat yang tertangkap aturan §6.1b (setelah
`tc_charger_framework`, `tc_pd_algo`, `tc_pep50`):

```make
nfc_i2c-objs = common.o common_ese.o i2c_drv.o
```

1.441 baris source TP. Yang membuatnya layak diprioritaskan: node DT X6871
memang aktif, dan `common.h` membaca persis properti yang ada di DT —
`DTS_IRQ_GPIO_STR "nxp,pn544-irq"`, `DTS_VEN_GPIO_STR "nxp,pn544-ven"`.
Tidak ada tebakan kontrak hardware.

Verifikasi terhadap `.ko` firmware:
- ekspor GLOBAL **32 == 32 identik**
- alias DT identik: `of:N*T*Cnxp,pn544` / `of:N*T*Cnxp,pn544C*`

Patch 6.12 (mekanis, bukan perilaku): `class_create(THIS_MODULE, name)` ->
`class_create(name)`; probe i2c jadi satu argumen (definisi + prototipe
header); `no_llseek` -> `noop_llseek`.

Sisa: **33 modul** dari 237, dengan pembagian yang sama seperti §6.2n —
8 bukan gap, 25 tanpa source atau di luar cakupan.

### 6.2q `tran-led-core` direkonstruksi: layout ops dibuktikan dua `.ko`

`tran-led-core` tidak ada di tarball resmi — dicek lengkap lewat aturan §6.1b:
tidak ada file, tidak ada entri Makefile, tidak ada simbol Kconfig. Pencarian
seluruh filesystem juga nihil. Tapi `.ko`-nya masih menyimpan **path source
aslinya**:

```
../kernel_device_modules-6.12/drivers/leds/tran_led/core/tran_led_core.c
../kernel_device_modules-6.12/drivers/leds/tran_led/core/tran_led_class.c
```

Artinya firmware X6871 dibangun dari tree **6.12**, bukan dari tarball 6.1.
Diperkuat: 111 modul firmware membawa path build, **semuanya** menyebut
`kernel_device_modules-6.12`, dan tidak satu pun menyebut `6.1`.

Konsekuensi penting: donor 6.1 punya `tc_led_class.c` + `tc_led.c`, tapi itu
**versi jauh lebih tua** — 7 ekspor dan `struct ops` 4 slot, sementara
firmware punya 18 ekspor dan 13 slot. Donor hanya titik awal; layout harus
dari `.ko`.

#### Layout dibuktikan dua arah, bukan ditebak

Diukur dari dua `.ko` independen, dan kedua pengukuran sepakat:

1. `tran-led-core.ko`: setiap accessor memuat `dev->ops` dari `dev+0x08` lalu
   slot tetap `0x00 set_i2c_retries … 0x60 show_tran_multicolor`.
2. `leds-aw22xxx.ko` (konsumen): tabel `const ops` ada di `.rodata+0x140`, dan
   tujuh entri non-NULL-nya mendarat tepat di `0x158/0x160/0x168/0x178/0x180/
   0x198/0x1a0` → slot `0x18/0x20/0x28/0x38/0x40/0x58/0x60`.

Keduanya identik, jadi layout ditetapkan oleh bukti, bukan disimpulkan dari
header donor.

#### Layout struct di-assert saat compile

`tran_led_device`: ops `+0x08`, dev `+0x220`, `dev.driver_data` `+0x2b8`,
`dev.class` `+0x538`, `sizeof` `0x778`.
`tran_led_core`: class `+0x120`, `support_pdlc` `+0x128`, `chip_type` `+0x12c`,
`primary_led` `+0x130`, `second_led` `+0x138`, mutex `+0x140`,
`log_level` `+0x170`, `sizeof` `0x178`.

#### Hasil verifikasi

| Kriteria | Hasil |
|---|---|
| ekspor GLOBAL | **20 == 20 identik** |
| slot ops | **11/11 offset identik** |
| alias DT | identik (`tran,led_core`) |
| `modinfo` name | identik (`tran_led_core`) |
| atribut sysfs | identik (5 nama) |
| offset probe | `0x118/0x120/0x128/0x140/0x170` identik |
| ukuran alokasi | `0x778` dan `0x178` identik |

Sisa beda impor hanya artefak inlining DDK: firmware punya
`__check_object_size`/`__kmalloc_noprof`/`___ratelimit`, kita punya
`__fortify_panic`. Pola yang sama sudah muncul di modul lain yang diterima
(`tc_charger_framework` punya keduanya; `nfc_i2c` punya `__check_object_size`
di kedua sisi).

**Pelajaran baru:** offset struct adalah hal yang tidak bisa ditangkap build.
Versi pertama menaruh `dev` di `+0x28`, bukan `+0x220`, dan tetap build hijau
— padahal `leds-aw22xxx` membaca data privatnya dari `[led+0x2b8]`, jadi
setiap probe akan rusak. Yang menemukannya adalah membandingkan offset hasil
disassembly kita dengan firmware, bukan build.

Sisa gap: **32 modul**. `leds-aw22xxx` kini tidak lagi terblokir.

### 6.2r `leds-aw22xxx` selesai — 31 modul sisa

`leds-aw22xxx` adalah modul pertama yang dibangun **di atas** `tran-led-core`.
Donor 6.1 ada (53 KB), tetapi itu versi lama: masih memakai `tc_led_ops`
4 slot dan tidak punya jalur cmd/multicolor/chip-type. Firmware X6871
mengimplementasikan tujuh slot:

| offset | slot | fungsi firmware |
|---|---|---|
| 0x18 | `get_chip_type` | `aw22xxx_get_chip_type` |
| 0x20 | `get_cmd` | `aw22xxx_get_tran_led_cmd` |
| 0x28 | `set_cmd` | `aw22xxx_set_tran_led_cmd` |
| 0x38 | `store_tran_led_cmd` | `aw22xxx_ops_store_tran_led_cmd` |
| 0x40 | `show_tran_led_cmd` | `aw22xxx_ops_show_tran_led_cmd` |
| 0x58 | `store_tran_multicolor` | `aw22xxx_tran_multicolor_store` |
| 0x60 | `show_tran_multicolor` | `aw22xxx_tran_multicolor_show` |

Fungsi yang tidak ada di donor direkonstruksi dari `.ko`: `aw22xxx_cover_gain`
(export), `get_chip_type` (melaporkan 5/6, bukan 0x18/0x27), `get/set_cmd`
(buffer 32 byte, `cmd[0] == 1`), wrapper ops, dan `multicolor_*`.

#### Data yang harus diambil dari `.data`, bukan dari donor

- `aw22xxx_cfg_name` adalah **206 entri × 64 byte = 13.184 byte**, bukan 33
  entri. Indeks = nomor effect. `_A` mulai 66, `_B` mulai 132. Array donor
  tidak bisa dipakai.
- Tabel music gain default 16 pasangan, dibaca dari `.rodata+0x1b0`.
- Nama multi-color default `B85`, `E23`, `S30`; DT X6871 memberi
  `aw22xxx,multi_color_count = <3>` dan
  `aw22xxx,multi_color_array = "B85\0E23\0S30"`.
- DT music table X6871 berisi 16 pasangan `(volume_level, music_gain)`;
  `aw22xxx_cover_gain` mencari gain berdasarkan volume level dan
  di-export.

#### Perilaku baru yang tidak ada di donor

1. `tran_led_cmd_cfg_2` sekarang menerima tiga argumen
   `(type, num2, num3)`; `type 0x0A` (audio) memakai `num3` sebagai sub-index
   di dalam grup, dan `type 0x0D` (performance) menambah tiga effect baru.
2. `cfg_loaded` menulis tabel berulang kali sambil memeriksa `GCR` dan `PST`,
   sampai tiga retry; setelah unlock, jika `AUDCTR.bit0` aktif, gain audio
   diterapkan ulang.
3. `reset_imax` (properti DT `aw22xxx,reset_imax`) ditulis ulang ke IMAX
   sebelum request firmware cfg.
4. Probe mendaftar sebagai `"primary_led"`, membuat kobject `aw22xxx_led`
   dengan symlink `led`, dan membuat dua atribut di device i2c
   (`tran_led_cmd`, `tran_multicolor`).

Catatan `dev_get_drvdata`: atribut yang dibuat lewat `sysfs_create_group` pada
`cdev.dev` mendapat `led_classdev *` dan harus `container_of` ke `aw22xxx`;
atribut yang dibuat lewat `device_create_file(&i2c->dev)` mendapat `aw22xxx`
langsung. Dua jalur ini ada di modul yang sama.

#### Verifikasi

| Kriteria | Hasil |
|---|---|
| ekspor GLOBAL (fungsi + objek) | **8 == 8 identik** |
| impor simbol | **58 == 58 identik** |
| alias DT / i2c | identik (`awinic,aw22xxx_led`, `i2c:aw22xxx_led`) |
| relokasi tabel ops | **7/7 offset identik** (0x158…0x1a0) |
| `aw22xxx_cfg_name` | 13.184 byte, **byte-identik** |
| `imax_name`, `imax_code`, `reg_access`, `attributes` | byte-identik |
| layout struct | di-assert saat compile; `sizeof == 0x360` |

Build target modul:
`//kernel_device_modules-6.12/drivers/leds/tran_led:leds-aw22xxx.mgk_64_k612.6.12.user`.

Staging: 688 → **689** `.ko`. Sisa gap: 32 → **31**.

### 6.2s Storage/UFS — Opsi A: baseline GKI/MTK (diputuskan 2026-11-19)

Kelompok 10 modul storage **tidak diport**. Keputusan: pakai stack GKI/MTK
yang sudah ada, karena (a) source fork tidak tersedia, (b) fork adalah satu
paket all-or-nothing, dan (c) hardware MMC/SD X6871 disabled.

#### Bukti

| Pemeriksaan | Hasil |
|---|---|
| ikconfig boot X6871 | `CONFIG_BLOCK=y`, `CONFIG_SCSI_MOD=y`, `CONFIG_BLK_DEV_SD=y`, `CONFIG_SCSI_UFSHCD=y`, `CONFIG_SCSI_UFSHCD_PLATFORM=y` |
| base DTB (dari `vendor_boot.img`) | `mmc@11240000` + `mmc@11242000` `status = "disabled"`; tidak ada `/odm/sd_tray` |
| tarball donor `mt6897-full.tar.gz` (4,7 GB) | tidak ada `fs/atomic_storage`; `kernel/kernel-6.1` kosong; hanya `drivers/ufs/ufs-mediatek*`, `drivers/mmc/host/mtk-mmc.c`/`mtk-sd.c`, `fs/f2fs` |
| pencarian simbol fork di donor | **0 hit**: `tran_badblocks`, `tran_get_sd_tray_insert_status`, `tran_ufshcd_pltfrm_init`, `tran_ufs_proc_bootdevice`, `blk_busyidle_event_subscribe` |
| build path di `.ko` firmware | semua fork berasal dari `kernel_device_modules-6.12/fs/atomic_storage/` (67 file `.c`) |
| vermagic | firmware `...gcc51d883045d`, build kita `...g2c4fd33ae6d8` → binary reuse tidak mungkin |

Closure baseline (2026-11-19): seluruh impor dari modul `ufs-mediatek-mod`,
`phy-mtk-ufs`, `blocktag`, `rpmb`, `rpmb-mtk`, `cqhci`, `ufs-mediatek-dbg`,
dan `mtk-mmc` disediakan oleh vmlinux atau `.ko` lain di staging —
**0 simbol benar-benar hilang**.

#### Inventaris fork (`fs/atomic_storage`)

| Modul | File `.c` | Ekspor |
|---|---:|---:|
| `tran-ufshcd-core` | 6 | 192 |
| `tran_scsi_mod` | 10 | 242 |
| `tran_sd_mod` | 2 | 46 |
| `tran_block` | 36 | 709 |
| `low_latency_sched` | 10 | 336 |
| `tran_mmc_block` | 2 | 41 |

Tujuh modul yang ditunda: 5 core fork (`tran-ufshcd-core`,
`tran-ufshcd-pltfrm`, `tran_scsi_mod`, `tran_sd_mod`, `tran_block`) +
`tran-proc-bootdevice-mod` + `low_latency_sched`.

Tiga tidak direncanakan:

- `tran_mmc_block` — MMC disabled di base DTB.
- `sd_tray` — tidak ada node `/odm/sd_tray`.
- `mtk-mmc-mod` — sudah dilayani `mtk-mmc.ko` (alias identik, 17/21 ekspor
  sama; beda hanya empat helper ioctl Transsion). MMC juga disabled.

#### Rencana

1. Boot test baseline: probe `ufshcd`, `sd 0:0:0:0`, mount `/data`, tidak ada
   `Unknown symbol tran_*`.
2. Kalau userspace membuka `/proc/bootdevice` dan gagal, tulis shim kecil
   (`manfid`/`serial`/`fw_version`/`manfdate`/`ffu_support`) — bukan port
   modul 85 KB.
3. Kalau storage gagal total, rekonstruksi `fs/atomic_storage` dari upstream
   6.12.38 + hook sampai ekspor/impor cocok dengan `.ko` firmware.

### 6.2t Empat modul fitur selesai — `tran_extcon_usb`, `tran_fp`, `tnek`, `tkv`

Empat modul prioritas dari kelompok fitur dikerjakan berurutan. Staging
**689 → 693** dan gap **31 → 27** (angka ini sebelum `charger_class` dihapus
di §6.2u).

| Modul | Commit | Ekspor | Impor | Status verifikasi |
|---|---|---|---|---|
| `tran_extcon_usb` | `3194d4f10237` | identik | identik | alias + `depends` identik |
| `tran_fp` | `0e527bf7c6f4` | **0 vs 2** (asli) | 90 vs 145 | common layer; alias `tran_fp_legacy` |
| `tnek` | `24b5fe361653` | **9 == 9** | **24 == 24** | export asli `__ksymtab`; modinfo identik |
| `tkv` | `cb088a63c4b2` | **0 == 0** | **24 == 23** | +`page_is_ram` pengaman; lihat §6.2u |

#### `tran_extcon_usb`

Firmware hanya mengirim modul ini, bukan `extcon-mtk-usb.ko`, dan DTBO
mengganti compatible `mediatek,extcon-usb` menjadi `transsion,extcon-usb`.
Modul kita tetap mempertahankan `extcon-mtk-usb.ko` untuk node
`mediatek,extcon-usb` yang tersisa; modul baru hanya match compatible
Transsion, jadi tidak ada rebutan.

Perilaku yang direkonstruksi: `register_tc_tcpc_notifier` dan event
`tc_tcpc` (OTG/audio plug, PD source/sink swap), debounce swap tiga kali
500 ms, power supply dari phandle `charger` dengan fallback `primary_chg`,
proc `/proc/mtk_typec/smt_u2_cc_mode` lewat `TRAN_PROP_TYPE_CC_SMT`, flag
`mediatek,bypss-typec-sink`, dan uevent `SWITCH_NAME`/`SWITCH_STATE` pada
perubahan `EXTCON_USB_HOST`.

Verifikasi: ekspor/impor **identik**, alias **identik**
(`transsion,extcon-usb`), `depends` **identik** (`tc_tcpc,tc_common_class`).

#### `tran_fp`

Basis: donor 6.1 `tran_common_v2` (main/ext/cust, 2.440 baris) dipindah ke
`drivers/input/fingerprint/tran_common/`, lalu disesuaikan ke 6.12 dan ke
compatible X6871 `tran_fp_legacy`.

Modul firmware 6.12 adalah bundel multi-vendor `tran_common` dengan **129
simbol GLOBAL** dan hanya **2 export asli** (`tran_fasync_for_lcm_full_HBM`,
`yxy_test_func`; keduanya tidak diimpor modul lain). X6871 memakai Goodix
dan HAL memakai `/dev/tran_fp` untuk kontrol (init, reset, IRQ, power, SPI
clock, chip info, key event), netlink route 30/29, input,
pinctrl/regulator, dan `/sys/kernel/tran_fp/vendor_name`. Port ini membawa
common layer itu, bukan backend vendor lain. Karena itu ekspor/impor
**tidak identik** dan wajib diuji saat boot.

Perubahan 6.12: lookup DT lewat `dev.of_node` (bukan
`of_find_compatible_node("tran_fp")`), match `tran_fp_legacy`, include
`pinctrl/consumer.h` + `regulator/driver.h`/`internal.h`,
`gpiod_set_debounce`, `KEY_F28 = KEY_ENTER` (tabel firmware memetakan F28
ke 28), dan buang include TEE/power yang tidak dipakai.

#### `tnek`

Tidak ada source di donor maupun tarball. Direkonstruksi penuh dari `.ko`:
node 0x418 byte (list +0x00, tag +0x10, api +0x30, type +0x38, data +0x3c,
name +0x3f8), pesan user 0x408 byte, queue maksimum 9 node (drop tertua),
`/dev/tnek` misc device, poll/read/write, empat caller API, `tne_pollwait`
/`tne_readwait`, dan `strlcpy` ekspor vendor yang sudah tidak ada di 6.12.

Verifikasi: **9 ekspor asli identik, 24 impor identik**, `depends` kosong
identik. Pengecekan awal sempat menghasilkan “17 == 17” karena menghitung
semua simbol GLOBAL, bukan `__ksymtab`; koreksi dan pengaman ada di §6.2u.
`mcDrvModule` firmware mengimpor `tnek_caller_api`; build kita meng-gate
impor itu, tetapi modulnya sekarang tersedia bila jalur TEE diaktifkan.

#### `tkv`

Direkonstruksi dari `.ko`. Membaca `/chosen` → `bootargs` → `tkv=<desimal>`,
memetakan region 32 KiB dengan `ioremap_prot`, menyalin ke `tkv_value`,
membuat `/proc/tkv` untuk membaca pasangan `key=value` (batas 90 byte,
melewati `ro.bootimage.build.fingerprint`), dan menerima tulis desimal yang
disimpan ke `g_tkv` sebagai “lcm invertion”.

Perbedaan yang disengaja: bila `tkv=` tidak ada di bootargs, init berhenti
dengan log `get_tkv_base fail` dan tidak melakukan `ioremap` alamat 0
(firmware tetap melanjutkan dan berpotensi memfault). Pengaman tambahan:
region wajib page-aligned dan seluruh page `page_is_ram()`; kalau tidak,
`/proc/tkv` dilewati (lihat §6.2u).

Verifikasi: **0 ekspor asli** (firmware juga tidak mengekspor), **24 impor
identik** ditambah `page_is_ram` sebagai pengaman, `depends` kosong identik.

### 6.2u Pre-flight sebelum boot — simulasi load, ABI, dan keamanan hardware

Sebelum boot pertama, keempat modul dibandingkan ulang dengan `.ko` stock
dan seluruh staging disimulasikan dengan `depmod`. Laporan lengkap:
`PRETEST.md`. Commit kernel: `6334ce2b9910`.

Hasil utama:

```
staging tree (staging/lib/modules/6.12.38-.../) : 796 .ko
modul stock yang ada di staging               : 217 / 237
impor tak terselesaikan                        : 0
CRC modversions tak terpenuhi                  : 0
export ambigu yang dipakai                     : 0
duplikat export antar modul yang di-load       : 0
```

20 nama stock yang tidak ada tetap yang sudah direncanakan: 2 panel tidak
direncanakan + 1 alias panel X6871, 3 MMC/SD, 7 storage ditunda, 4 terblokir
`transsion_tranlog`, dan 3 fitur mandiri (`tkv_recovery`, `tran_rhi`,
`tran_expand_key`).

Koreksi penting:

1. **Export asli ≠ semua simbol GLOBAL.** Firmware `tnek` mengekspor 9
   (bukan 17), `tkv` mengekspor 0 (bukan 11), `tran_fp` hanya 2 (debug,
   tanpa importer), `tran_extcon_usb` 0. Export berlebih di `tnek`/`tkv`
   sudah dihapus; `tnek` sekarang **9 == 9**, `tkv` **0 == 0**.
2. **`charger_class.ko` dihapus dari daftar install.** Stock X6871 tidak
   mengirimnya; `tc_charger_class.ko` mengekspor simbol yang sama dengan CRC
   yang diharapkan `tc_tcpc`/`tc_misc_intf`. Sebelumnya dua exporter membuat
   depmod bisa memilih CRC yang salah dan memutus rantai USB/charger.
3. **`tran_fp` regulator guard.** DT X6871 memakai `mt6368_vfp` fixed
   3,3 V (min == max), jadi jalur normal tidak berubah. Regulator variabel
   atau di luar 1,5–3,6 V sekarang ditolak, bukan disetel ke `max_uV`.
4. **`tkv` hanya memetakan RAM.** Region `tkv=` wajib page-aligned dan
   seluruh page `page_is_ram()`. Kalau tidak, `/proc/tkv` dilewati; firmware
   memetakan alamat apa pun dan membaca 32 KiB. `tkv` tidak pernah menulis
   balik ke region.
5. **Hardening memori.** `tran_fp` netlink copy dibatasi `nlmsg_len`/`skb`;
   `fod_location_xy` dan `icname[10]` memakai `strscpy`; `tnek`
   men-NUL-terminasi tag/name/data user dan memperbaiki race `poll_wait`;
   `tkv` memakai `memchr`.

Risiko fungsional yang **bukan** risiko hardware: `tran_fp` masih common
layer saja. Ioctl transfer SPI (15/16/17) belum ditangani dan tidak ada
`spi_sync`; akuisisi gambar fingerprint kemungkinan gagal sampai backend
Goodix diport. Power/reset/IRQ/netlink/sysfs tetap tersedia.

Prasyarat packaging: image harus memakai `modules.dep`/`modules.alias` yang
digenerate build dari tree staging, bukan `modules.dep` stock (path flat dan
masih mencantumkan `transsion_tranlog` untuk `tran_fp`).

### 6.3 Kesimpulan Tingkat D


Jangan kerjakan Tingkat D sebelum Phase 3 selesai. Alasannya:
`tran-ufshcd-*`, `tran_zram`, `tran_block`, `tran_mmc_block`, `trans_sched`
semuanya **fork subsistem inti**. Memasangnya berarti mengganti UFS, zram,
block layer, dan scheduler sekaligus — dan kalau satu saja salah, device
tidak boot. Itu bukan cara memulai.

Untuk kelompok storage, keputusan sudah diambil di §6.2s: **Opsi A** —
baseline GKI/MTK, fork ditunda, tiga modul MMC/SD tidak direncanakan.

Empat modul fitur sudah selesai di §6.2t (`tran_extcon_usb`, `tran_fp`,
`tnek`, `tkv`). Pre-flight §6.2u menghapus `charger_class` dari install:
flat customer **692** `.ko` (27 nama stock hilang, termasuk 7 modul GKI yang
sebenarnya ada di tree staging), sedangkan tree staging lengkap **796**
`.ko` dengan **20** nama stock hilang. Dari 20 itu, 6 memang tidak
direncanakan (2 panel lain + 1 alias panel X6871 + 3 MMC/SD), sehingga
kandidat nyata tinggal **14** — 7 storage ditunda, 4 terblokir
`transsion_tranlog`, dan 3 fitur mandiri (`tkv_recovery`, `tran_rhi`,
`tran_expand_key`).


---

## 7. Phase 3 — panel + Iris (INI YANG PALING PENTING)

Panel adalah satu-satunya penghalang boot sungguhan. Perangkat target proyek
ini **hanya X6871**, dan DT `panel1@0` hanya memakai satu compatible:

```
rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871   <- panel utama X6871
```

Dua nama panel lain yang muncul di donor/firmware **tidak direncanakan**:

```
rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_cl8      <- bukan X6871, tanpa DT
ili7838e_fhdp_dsi_cmd_dsc_tm_tm_120hz_cl9         <- bukan X6871, tanpa DT
```

### 7.1 Framework panel 6.1 == 6.12 (terverifikasi)

```
mtk_drm_panel_drv.h          102 vs 102   IDENTIK
mtk_drm_panel_common.h        59 vs  59    IDENTIK
mtk_drm_panel_helper.h       603 vs 603   IDENTIK
mtk_drm_panel_helper_dsi.c  2889 vs 2889  IDENTIK
mtk_drm_panel_drv.c           97 vs  97    IDENTIK
```

Byte-identik. Artinya driver panel 6.1 bisa drop-in; API-nya tidak berubah.
Drift hanya di `mtk_panel_ext.h` (762 → 884 baris, murni aditif), dan
struct-nya cuma kehilangan:

| Hilang di 6.12 | Dipakai rm692j0? |
|---|---|
| `vdo_per_frame_lp_enable` | tidak (0) |
| `hbm_set_cmdq_switch` | ya (2) |
| `lcm_power_set` | ya (2) |

Jadi paling banyak 3 penghapusan per driver panel.

### 7.2 Iris — WAJIB, bukan opsional

Panel X6871 punya `pxlw-iris-enable = <1>` di DT, dan `.ko`-nya mengimpor
9 simbol `iris_*` sebagai UND. Semua 9 diekspor `mediatek_drm_v1.ko` di device:

```
iris_enable  iris_disable  iris_reset  iris_reset_off  iris_set_valid
iris_is_pt_mode  iris_panel_cmd_passthrough  iris_conver_one_panel_cmd
iris_loop_back_validate
```

Dan firmware Iris-nya ada di dump:

```
vendor/firmware/iris5.fw
vendor/firmware/iris5_ccf1.fw
vendor/firmware/iris5_ccf2.fw
vendor/firmware/pxlw-rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.fw   <- per-panel
```

Ada fw per-panel yang namanya persis sama dengan panel = Iris memang dipakai
di jalur display panel ini.

**Tree w1vo tidak punya satu baris pun `iris_`.** Donor mt6897 juga tidak.

### 7.3 Sumber Iris yang cocok (sudah ditemukan)

`oppo-source/android_kernel_oppo_mt6896` (yang ditunjuk user) **bukan**
tempatnya — itu kernel mainline, `mediatek_v2` tidak ada di sana. Sibling-nya
`android_kernel_modules_oppo_mt6896` punya `mediatek_v2` tapi hanya
`color_softiris_status` (software color tuning, bukan hardware Iris).

Yang benar (hasil GitHub code search):

| Repo | Lokasi iris | SoC | Pakai |
|---|---|---|---|
| `OnePlusOSS/android_kernel_5.10_oneplus_mt6895` | `mediatek_v2/iris_*.c` | **mt6895** | **YA — ini yang dipakai** |
| `oppo-source/android_kernel_modules_and_devicetree_oppo_mt6897` | `vendor/oplus/.../drm/iris/` | mt6897 | alternatif |
| `Oneplus-Ce5/android_kernel_modules_oneplus_mt6897` | `oplus/.../iris/core/` | mt6897 | alternatif |

Branch yang dipakai: `oneplus/mt6895_v_15.0.0_ace` (paling baru, Android 15).

File (16 `.c`, ~8.950 baris, sudah diunduh ke `tmp/iris-src/`):

```
iris_cmds.c   iris_i2c.c    iris_i3c.c     iris_loop_back.c
iris_extended.c  iris_gpio.c  iris_ioctl.c   iris_frc.c
iris_pq.c     iris_lp.c     iris_lightup.c  iris_lightup_ocp.c
iris_lut.c    iris_mode_switch.c  iris_timing_switch.c  iris_dbg.c
```

Header: `iris_api.h iris_def.h iris_log.h iris_mtk_api.h iris_lightup.h
iris_loop_back.h iris_gpio.h iris_lp.h iris_uapi.h iris_frc.h iris_ioctl.h`
dll. Di-`obj-` masuk `mediatek-drm-y` (Makefile baris 78-93).

### 7.4 Kelayakan port Iris (terukur)

API 6.4+ yang dihapus — hampir tidak ada:

```
class_create 0   strlcpy 0   timer_setup 0   kernel_read 0
get_user_pages 0  proc_create 0  i2c_new_dummy 0  mipi_dsi_dcs_write 0
```

Hanya `gpio_set_value` (3) dan `of_get_named_gpio` (4), dua-duanya tidak dihapus.

Semua header dependensi ada di tree 6.12 kita:

```
mtk_drm_drv.h mtk_drm_crtc.h mtk_drm_ddp_comp.h mtk_drm_ddp.h
mtk_drm_mmp.h mtk_drm_trace.h mtk_debug.h mtk_panel_ext.h
mtk_log.h mtk_drm_debugfs.h drm_internal.h(kernel)   -> semua present
```

`struct dsi_panel` (sisa Qualcomm) muncul 4x, **semuanya di dalam `#if 0`** —
dead code, sudah diverifikasi per-baris. Tidak perlu diapa-apakan.

Struct `mediatek_v2` yang disentuh iris cuma sedikit:

```
struct mtk_ddp_comp    (2x)
struct mtk_panel_params (1x)  -> lcm_esd_check_table  (ADA di 6.12, baris 577)
struct mtk_panel_ext   (1x)   -> ->params  (ADA)
struct mtk_drm_crtc    (1x)
```

Ini yang membuat port Iris terbatas: iris sebagian besar mandiri (I2C/I3C,
GPIO, firmware load, LUT sendiri) dan menyentuh MTK DRM lewat API sempit.

### 7.5 Langkah Phase 3

**Status 2026-11-19: langkah 1 SELESAI — Iris sudah ter-compile dan link.**

Iris dimasukkan ke `mediatek_v2/v1/` (tempat `mediatek_drm_v1.ko` dibangun),
bukan ke `mediatek_v2/`, supaya persis sama dengan layout modul di device.
16 `.c` + 18 header, masuk daftar `srcs` `mediatek_drm_v1` di BUILD.bazel.

Hasil verifikasi: kesembilan simbol yang dibutuhkan panel
(`iris_enable`, `iris_disable`, `iris_reset`, `iris_reset_off`,
`iris_set_valid`, `iris_is_pt_mode`, `iris_panel_cmd_passthrough`,
`iris_conver_one_panel_cmd`, `iris_loop_back_validate`)
**semuanya EXPORTED** dari `mediatek_drm_v1.ko` hasil build kita.

#### Patch yang diperlukan (semua terukur, 6 iterasi build)

| # | Masalah | Perbaikan | Jumlah |
|---|---|---|---|
| 1 | `strlcpy` dihapus di 6.x | → `strscpy` | 14 |
| 2 | `PXLW_IRIS` tidak didefinisikan, jadi `iris_uapi.h` kosong → 40+ error `msmfb_*` | `local_defines += CONFIG_PXLW_IRIS=1, PXLW_IRIS5=1` | 1 |
| 3 | `struct mipi_dsi_msg` OPPO punya `ctrl`+`wait_ms`; kernel 6.12 stock tidak | buang 2 initializer kosong | 64 |
| 4 | `platform_driver.remove` / `i2c_driver.remove` kembali `void` | ubah tipe + buang `return` | 5 |
| 5 | `i2c_driver.probe` kehilangan argumen `i2c_device_id` | ubah signature | 2 |
| 6 | `params->oplus_cmdq_pkt_set_event` field OPPO-only | guard `&& 0` | 3 |
| 7 | `DISP_SLOT_IRIS_READ_BASE` tidak ada di `mtk_drm_crtc.h` MTK | tambah define (nilai dari OPPO `mtk_drm_crtc.h`) | 1 |
| 8 | `MIPI_DSI_MSG_LASTCOMMAND` di-comment | aktifkan define | 1 |
| 9 | `iris_dsi_pre_cmd/pos_cmd` dideklarasikan + dipanggil tapi tak ada definisi | tambah 2 wrapper di `mtk_dsi.c` | 2 |
| 10 | `vmalloc`/`vzalloc`/`vfree` tidak diekspor ke modul di 6.12 | → `kvmalloc`/`kvzalloc`/`kvfree` (+ `GFP_KERNEL`) | 59 |
| 11 | `int func()` tanpa void | → `(void)` | 1 |

Catatan penting soal #3: nama `dsi_mode_info`, `dsi_cmd_set_state`,
`iris_cmd_desc` memang berbau Qualcomm, **tapi semuanya didefinisikan sendiri
oleh `iris_def.h`**. Yang benar-benar tipe Qualcomm cuma 26 referensi, dan
**semuanya di dalam `#if 0`** — dead code, tidak perlu disentuh.

#### Langkah berikutnya di Phase 3

**Status 2026-11-19: langkah 2 SELESAI — panel rm69220 ter-build.**

`panel-rm69220-vdo-x6871.ko` (631 KB) masuk output, total 1.408 → 1.410 `.ko`.
Basis: `rm692j0_..._lj9.c` dari donor mt6897 — keluarga RM692xx sama,
23 dari 27 fungsi cocok dengan `rm69220` di firmware X6871.

Compatible string cocok persis dengan device:
`rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871`

**Data yang di-recover dari firmware** (tidak ada source publik — GitHub code
search hanya menemukan `panel-raydium-rm69220.c` mainline, bukan MTK):

| Data | Simbol di `.ko` | Hasil |
|---|---|---|
| Init table | `lcm_initialization_setting` | 63 entri, format `{u32 cmd; u8 count; u8 para[251]}` |
| Timing 4 mode | `.rodata` + relokasi `lcm_get_modes` | lihat tabel bawah |
| DSC params | `ext_params_144hz` | 10bpc, 128bpp, pic 1080×2436, slice 540×12, chunk 540 |

Timing hasil decode (semua 1080×2436):

| Mode | clock | HFP | HSA | HBP | VFP | VSA | VBP | htotal | vtotal |
|---|---|---|---|---|---|---|---|---|---|
| 144Hz | 403992 | 24 | 4 | 16 | 40 | 4 | 16 | 1124 | 2496 |
| 120Hz | 368928 | 120 | 4 | 16 | 64 | 4 | 16 | 1220 | 2520 |
| 60Hz | 368928 | 120 | 4 | 16 | 2584 | 4 | 16 | 1220 | 5040 |
| 40Hz | 368732 | 120 | 4 | 16 | 5100 | 4 | 16 | 1220 | 7556 |

Cara decode struct `drm_display_mode` di `.rodata`: cari relokasi
`R_AARCH64_ADR_PREL_PG_HI21` ke `.rodata` di dalam `lcm_get_modes`
(offset 0x1d0/0x248/0x2c0/0x338), lalu baca field sebagai **u16** mulai
offset 4: hdisplay, hsync_start, hsync_end, htotal, (skip), vdisplay,
vsync_start, vsync_end, vtotal. `clock` = u32 di offset 0.

#### Patch 6.1 → 6.12 untuk panel

| Masalah | Perbaikan |
|---|---|
| `{0x11, 0, {0x}}` — brace kosong | `{0}` |
| `struct tran_panel_driver_params` tidak ada di `mtk_panel_ext.h` 6.12 | definisikan lokal di file panel |
| `.tran_panel_params` designator tidak ada | dibuang |
| `.lcm_power_set` callback dihapus di 6.12 | dibuang, fungsi ditandai `__maybe_unused` |
| `.hbm_set_cmdq_switch` dihapus di 6.12 | dibuang, idem |
| `struct lcm` tak punya `dsi`/`dcs_write_gce`/`handle` | init table ditulis sebagai `lcm_dcs_write_seq_static()` |

#### Sisa Phase 3

3. ~~Port panel `ili7838e` dan `rm69220_..._cl8`~~ — **tidak direncanakan**.
   Perangkat target hanya X6871; keduanya tidak punya node DT di `frag0.dts`.
4. DT: node `panel1@0` + GPIO/regulator sesuai `frag0.dts`.
5. Pasang firmware `iris5.fw` + `pxlw-rm69220_..._x6871.fw` ke image.

Status: panel sudah dijalankan di device; layar mati->nyala OK (PRETEST §40).

Catatan mode: `rm692j0` (donor 6.1) itu **CMD 1260x2800**, sedangkan
`rm69220` X6871 **VDO RAMLESS 1080x2400**. Beda drive mode — jangan pakai
rm692j0 sebagai basis struktur, pakai rm692h5 (VDO) atau template VDO lain.

### 7.6 Data yang sudah diekstrak dari firmware

`.ko` firmware sudah di-strip debug info, tapi `.rodata` dan nama simbol masih
utuh — cukup untuk mengambil tabel init. Contoh `rm69220_..._x6871.ko`:

```
lcm_probe                 1232 B
lcm_prepare                832 B
lcm_enable                 140 B
mtk_panel_ext_param_set    280 B
panel_ext_lcm_power_set    792 B
```

Ini satu-satunya bagian yang benar-benar RE, dan sifatnya **ekstraksi data**
(tabel perintah DSI, timing, gamma), bukan dekompilasi logika.

---

## 8. Urutan kerja yang disarankan

| # | Kerjaan | Biaya | Risiko | Hasil |
|---|---|---|---|---|
| 1 | Tingkat A: nyalakan `entry_level_legacy.config` | 1 build | rendah | +12 modul, sekaligus validasi loop build varian |
| 2 | Tingkat C: port stack charging Transsion | sedang | sedang | +38 modul |
| 3 | Phase 3: vendor Iris + port panel rm69220 | besar | **tinggi** | ✅ selesai: device menyala (2026-11-20) |
| 4 | Tingkat B: rename fpsgo/game | kecil | rendah | +2 |
| 5 | Tingkat D: cari donor Transsion 6.12 | ? | ? | ~55 |

Phase 3 didahulukan secara logika (tanpa panel tidak boot), tapi Tingkat A
layak dikerjakan lebih dulu karena murah dan memvalidasi bahwa
`SUPPORT_PLATFORM=mt6895` + `DEFCONFIG_OVERLAYS` bisa dipakai bersamaan.
Jawaban itu menentukan semua langkah berikutnya.

---

## 9. Aset yang sudah diunduh (di `~/tmp/`)

- **Firmware dump X6871 (`X6871-16.3.0.155SP20`)**: [`https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6871`](https://gitlab.com/rama-firmware-dumps/infinix/Infinix-X6871)
- **Tarball donor Transsion 6.1 (`mt6897`)**: [`https://d1wd32b69guoqm.cloudfront.net/opensource/android15_kernel_modules_and_devicetree_mt6897.tar.gz`](https://d1wd32b69guoqm.cloudfront.net/opensource/android15_kernel_modules_and_devicetree_mt6897.tar.gz) (dari [`https://opensource.dev.infinixmobility.com/`](https://opensource.dev.infinixmobility.com/))

| Path | Ukuran | Isi |
|---|---|---|
| `mt6897-full.tar.gz` | 1,7 G | donor Transsion/MTK (kernel 6.1, mt6897) |
| `mt6897/` | 4,7 G | hasil ekstrak |
| `x6871/boot.out/kernel` | 18 M | kernel X6871 (LZ4) |
| `x6871/vb.out/` | 33 M | vendor_boot: 237 `.ko` + DTB |
| `x6871/vr/root/lib/modules/` | — | 237 `.ko` siap analisa |
| `x6871/frag0.dts` | 113 K | DTBO X6871 (sumber kebenaran hardware) |
| `x6871-files.txt` | 728 K | 12.897 path firmware X6871 |
| `iris-src/` | 292 K | 16 file source Iris mt6895 (OnePlusOSS) |
| `gap-ko.txt` | 4 K | 107 selisih modul |

Untuk mengulang: `bootRE/ikconfig` (220 K) berisi config kernel device —
bisa dipakai membandingkan `CONFIG_*` kita vs device.

---

## 10. Status ringkas (diperbarui 2026-11-22)

- **KMI 6 (`gki-kmi6-20261122`):** Android 16 boot sampai launcher dengan GKI resmi Google `android16-6.12-2026-09_r16`. `vendor_boot` (222 modul), `vendor_dlkm` (209), dan `odm_dlkm` (57) dibangun dari source; audit mencatat 0 mismatch CRC, 0 kolisi `CONFIG_MODULE_SIG_PROTECT`, dan 0 simbol tak terselesaikan.
- **KMI 7 (Google CI `16987858`):** maintainer melaporkan operasi kamera normal setelah menguji build dengan port OTP di X6871. Lihat [hasil uji dan cakupan port](#11-kalibrasi-kamera-x6871--kmi-7).
- **KMI 5 (build sebelumnya):** TWRP, GPU, Wi-Fi, storage, haptic, fast charging, audio speaker dan earpiece, layar hingga 144 Hz dan AOD, touch dan DT2W, sidik jari dalam layar, senter, serta kamera foto dan video 1080p telah diuji. Lihat [HANDOFF](HANDOFF.md#hasil-uji-perangkat-sebelum-migrasi-kmi-5) untuk rincian dan status USB.

Belum / sengaja dilewati:

- Sumber kalibrasi OTP `camera_eeprom_v4l2` dan patch Ext-ISP tidak tersedia di donor. Lihat audit dan cakupan port X6871 di §11.
- 25 modul stock tanpa source (`transsion_tranlog`, `thd`, dll.) dan 7 modul fork storage `fs/atomic_storage/` (diganti baseline GKI/MTK yang sudah terbukti boot).
- Tingkat B rename `fpsgo`/`game` belum dikerjakan; target build di `mgk_64.bzl` kini sudah di-trim ke allowlist 413 target OOT X6871 (`kernel/kleaf/x6871_modules.bzl`).
- Target ABI `user_customer_abi` tidak bisa lulus (328 simbol duplikat antar varian driver, gagal di `stg merge`); sebagai gantinya verifikasi KMI/ABI resmi dilakukan oleh `./tools/verify-kmi-abi.py` (8 gerbang). Lihat `HANDOFF.md`.

## 11. Kalibrasi kamera X6871 — KMI 7

Gunakan GKI 6.12.96 (4 KB) dari Google CI `16987858`, lewat
[`local_manifest-kmi7.xml`](../local_manifest-kmi7.xml). Baseline port sensor
dan probe EEPROM ada di [PRETEST §51](PRETEST.md#51-port-driver-kamera-x6871-imgsensorko--camera_eeprom_v4l2ko).

Angka **46** di [audit awal](PRETEST.md#modul-kamera-yang-beda) adalah jumlah
fungsi tambahan di seluruh modul EEPROM stock, bukan 46 fungsi untuk setiap
sensor X6871. DT stock punya dua node EEPROM: S5KHM6SX di `camera_eeprom0@50`
dan GC32E1 di `camera_eeprom1@51`. Kedua slot GC02M3 tidak punya node EEPROM
terpisah di DT tersebut.

Implementasi baca-saja di `mtkcam/cam_cal/src_v4l2/custom/x6871_cam_cal.c`
([commit modul vendor `1d259ab`](https://github.com/ramabondanp/alps-vendor_mediatek_kernel_modules/commit/1d259ab7de1727b1ecf0615907d4f1980175d88f))
memakai layout berikut, ditelusuri dari tabel, relokasi, dan jalur baca
di `camera_eeprom_v4l2.ko` stock (SHA-256
`021fa9a16d2ad9676f10921921fe64602d57b8bd66c9f105383e47590bdc734e`):

| Sensor | AWB unit / golden | AF | LSC (1868 byte) | PDAF |
|---|---|---|---|---|
| S5KHM6SX | `0x0c81` / `0x0c87`, checksum `0x0c8f` | `0x0c91`–`0x0c9c` | `0x0ca1`, checksum `0x13ed` | `0x13ef`, checksum `0x19cb` |
| GC32E1 | `0x0a8c` / `0x0a92` | — | `0x0a9c`, checksum `0x11e8` | Dinonaktifkan di tabel stock |

Kedua layout memeriksa ID `0x010b00ff` pada offset `0x01` sebelum membaca
isi kalibrasi. Port lebih ketat daripada biner stock: pembacaan yang tidak
lengkap, ID yang berbeda, atau checksum yang salah ditolak. Belum ada dump
EEPROM perangkat untuk memastikan ID dan checksum ini pada semua varian modul.
Ioctl baca/query stock memakai payload `0x2c30` byte, sedangkan donor memakai
`0x2a88`. Port menerima kedua ukuran untuk kedua sensor X6871; hanya field
AWB/AF, LSC dan PDAF dengan offset yang cocok yang diisi. Tidak menambah
ioctl tulis EEPROM, OIS, kalibrasi multicam, atau Pre-ISP.

**Ext-ISP:** tidak ditemukan node Ext-ISP/AI-ISP/fake-sensor pada DT gabungan
stock dan tidak ditemukan impor callback Ext-ISP pada 527 file modul stock
yang diaudit dari `vendor_boot`, `vendor_dlkm` dan `odm_dlkm`. Jangan port
cabang ini ke build X6871 tanpa bukti jalur yang memakainya. `mtk-cam-isp`
tidak diubah oleh port kalibrasi ini.

**Validasi sebelum uji perangkat:** build KMI 7 `user` berhasil tanpa perubahan
pada tree GKI. Uji parser dengan data sintetis mencakup kedua layout,
normalisasi AWB, AF, LSC, PDAF, penolakan header/checksum yang salah, dan
pembacaan parsial. Delapan pemeriksaan KMI/ABI lulus untuk 488 modul; 10.704
CRC ekspor KMI dan 2.658 CRC impor GKI unik cocok dengan artefak CI. AVB
hashtree `vendor_dlkm` lulus verifikasi dan satu-satunya `.ko` yang berubah
adalah `camera_eeprom_v4l2.ko`. `vendor_boot` dan `odm_dlkm` tetap memakai
image dari pre-release KMI 7.

**Hasil uji perangkat:** maintainer menguji `vendor_dlkm.img` dengan port OTP
pada X6871 yang memakai set KMI 7 `16987858` dan melaporkan operasi kamera
normal. Penggunaan data OTP oleh HAL belum terverifikasi;
lihat [PRETEST §69](PRETEST.md#69-uji-kamera-dengan-port-otp--kmi-7).

## 12. Profil baterai MT6375 X6871 — KMI 7

Log port `dmesg10.txt` melaporkan `charge_full = 2946000 µAh`. Angka ini
sesuai entri fallback `g_Q_MAX[0][0] = 2946` di modul MediaTek, bukan hasil
pengukuran kapasitas baterai. Isi tabel fallback `g_Q_MAX` dan `g_Q_MAX_H_CURRENT`
sama dengan `mt6375-battery.ko` stock. `tc_gauge.ko` hanya meneruskan
`POWER_SUPPLY_PROP_CHARGE_FULL`, jadi bukan sumber selisih.

Port memulihkan dua bagian konfigurasi stock di `drivers/power/supply/mtk_battery.c`:

1. Baca `batteryID-channel` dari AUXADC sebelum menginisialisasi kurva.
   Pembacaan stock pada perangkat ini adalah 1820 mV, yang memilih profil 3.
   Kurva profil 3 dari DT stock mencapai 5060,1 mAh. Pemilihan profil
   eksplisit melalui DT tetap berlaku jika diaktifkan.
2. Gunakan `tran_Q_diff` sesuai ID baterai untuk Qmax. Nilainya 5000 mAh
   pada DT stock X6871. Konversi yang sudah benar di port dipertahankan:
   target laporan `charge_full` adalah `5000000 µAh`, bukan `500000 µAh`
   seperti pada log pembanding dengan modul stock. Ini nilai desain,
   bukan hasil pengukuran kapasitas baterai yang sudah menua.

Uji lokal memeriksa batas pemilihan ID, override ambang dari DT, dan
penanganan error baca. DTB dasar dari `vendor_boot` juga sudah diuji
bersama overlay stock: hasil gabungan memuat kelima kurva profil 3 dan
nilai `tran_Q_diff` yang diharapkan. Build `user` KMI 7 lulus delapan
pemeriksaan KMI/ABI untuk 488 modul; 2.658 CRC impor GKI unik cocok
dengan Google CI `16987858`. Perubahan ini tidak mengubah ABI antara
fuel gauge dan daemon userspace atau batas pengisian.

`mt6375-battery.ko` ada di `vendor_boot` dan `odm_dlkm`; gunakan kedua
image tersebut dari build yang sama. Pertahankan `vendor_dlkm` dari
build OTP jika sudah terpasang. GKI dan DTBO tidak diubah.

Untuk uji perangkat, cek ID profil dan Qmax di log. Dari terminal perangkat,
jalankan:

```sh
cd /sys/class/power_supply/battery
cat charge_full charge_full_design capacity
```

Dua baris pertama dalam µAh, baris terakhir dalam persen. Uji perangkat
di `dmesg11.txt` mengonfirmasi profil 3 pada 1820 mV dan `charge_full`
sebesar `5000000 µAh`. Perubahan profil tersedia di commit modul perangkat
[`94fc581`](https://github.com/ramabondanp/alps-kernel_device_modules-6.12/commit/94fc58164d984734e5666a70a821ce5cb324ace7).

### 12.1. Antarmuka `tran_batt` dan ABI `fgauged`

Donor Transsion MT6897 6.1 mendaftarkan `tran_batt` dari `mtk_battery.c`.
Modul stock X6871 6.12 mendaftarkannya dari `mtk_battery_manager.ko`,
sedangkan port belum mendaftarkannya. Akibatnya, `dmesg11.txt` mencatat
`Couldn't get dev(tran_batt)` saat `tc_gauge` membaca data fuel gauge.

Port menambahkan bagian baca-saja di battery manager untuk MT6375
single-gauge: ID baterai, siklus mentah, SOC, coulomb counter, dan estimasi
sisa kapasitas. Sisa kapasitas diambil dari mode gauge yang aktif, bukan
dari angka kapasitas desain. Ini tidak memulihkan riwayat siklus yang
belum disuplai ke kernel dan tidak mengubah algoritme charging.

ABI `fuel_gauge_custom_data` donor 6.1 berukuran 784 byte, port 6.12
900 byte, dan biner X6871 stock 952 byte. Donor membantu mencocokkan
properti `tran_batt`, tetapi layout-nya bukan pengganti ABI daemon stock.
Build uji `tran_batt` KMI 7 dari Google CI `16987858` lulus delapan
pemeriksaan KMI/ABI untuk 488 modul. Uji lokal mencakup perhitungan sisa
kapasitas untuk mode kernel dan daemon serta penanganan data yang belum
tersedia. Dibanding build profil baterai, hanya `mtk_battery_manager.ko`
di `vendor_boot` dan `odm_dlkm` yang berubah. `vendor_dlkm` OTP tetap
identik. `dmesg12.txt`
mengonfirmasi pembacaan `tran_batt` untuk SOC (`7700` = 77,00%); siklus
mentah masih `0`.

### 12.2. Akhir pengisian dan ABI daemon stock

`dmesg13.txt` mencatat MT6375 `DONE` (`CHG_STAT = 0x07`), event EOC sudah
diterima, dan arus baterai turun ke hampir nol saat UI masih menunjukkan
78%. Disassembly `mtk_battery_manager.ko` stock menunjukkan perilaku
laporan `Charging` yang sama; fallback kernel stock juga tidak menangani
`FG_INTR_CHR_FULL`. Library stock `libfgauge_gm30.so` menangani event itu
melalui `fg_charging_full_int_handler`.

Port mengadaptasi ABI stock untuk gauge MT6375 dengan `tran_Q_diff`:
13 field `DYNAMIC_VC_*` dan `DIFFERENCE_*` mulai offset `0x384`, lengkap
dengan default dan override DT dari modul stock. Paket pengaturan 952 byte,
tabel 55.124 byte, dan paket gabungan 56.076 byte diperiksa saat kompilasi.
Gauge lain tetap memakai ABI lama. Pemeriksaan versi dan fallback tetap
berlaku bila daemon tidak cocok. Notifikasi penuh juga mengikuti stock:
tetap jalankan kalibrasi EOC, tetapi jangan beri event penuh ke daemon
jika pengisian sedang memakai mode tegangan rendah (`low CV`). Tidak ada
perubahan batas listrik atau pemaksaan persentase 100%.

Build `user` KMI 7 dari Google CI `16987858` lulus delapan pemeriksaan
KMI/ABI untuk 488 modul. Uji lokal memeriksa pembacaan potongan paket
900 dan 952 byte, termasuk potongan yang melewati batas offset `0x384`
serta permintaan di luar batas. Dibanding build uji `tran_batt`, hanya
`mt6375-battery.ko` dan `mtk_battery_manager.ko` di `vendor_boot` dan
`odm_dlkm` yang berubah. `vendor_dlkm` OTP tetap identik. Adaptasi ABI,
jalur EOC, dan antarmuka `tran_batt` tersedia di commit modul perangkat
[`8164631`](https://github.com/ramabondanp/alps-kernel_device_modules-6.12/commit/8164631010c02019a5b9c9ab9d23bbadfc4b70af).

Uji perangkat (`dmesg14.txt`) menunjukkan `fuelgauged` aktif dan UI naik
dari 78% ke 81%. Perilaku pada `DONE` belum terverifikasi. Lihat
[PRETEST §70](PRETEST.md#70-uji-fuel-gauge-mt6375--kmi-7) untuk bukti log.
