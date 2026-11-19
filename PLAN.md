# PLAN — Port driver ke sumber X6871 (Infinix GT 20 Pro)

Dokumen ini rencana kerja. `README.md` = cara build yang sudah jalan,
`HANDOFF.md` = status build + jebakan. Dokumen ini = apa yang belum jalan.

Status per 2026-11-18. Semua angka di bawah hasil pengukuran, bukan perkiraan.

---

## 1. Masalah

Mau bikin source kernel untuk device yang source-nya tidak dipublikasikan
vendor. Target: **Infinix X6871 (GT 20 Pro)**, `X6871-16.3.0.155SP20`.

Titik keberangkatan yang menguntungkan:

```
X6871  : MT6895 (Dimensity 8200 Ultimate), kernel 6.12.38-android16-5-gb575a0b6e647
W1VO   : mt6895                          , kernel 6.12.38-android16-5-g2c4fd33ae6d8
                                                       ^^^^^^^^ KMI generation sama
```

Soc sama, versi kernel sama, generasi KMI sama. Jadi **tree w1vo yang sudah bisa
build dipakai sebagai basis**, bukan diganti. X6871 cuma jadi donor.

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

### 6.2i `tc_charger_framework` — modul terpenting yang tidak pernah dirilis

`tc_charger_framework.ko` adalah **inti charging**: 78 ekspor GLOBAL
(`create_votable`, `enable_primary_charger`, `get_charger_charging_current`,
`charger_cloud_engine_init`, …). Ia ada di firmware tapi **tidak ada di donor
6.1 maupun mt6897**.

Yang dirilis Transsion hanya `tc_charger.c` (4.112 baris, hanya 3 ekspor:
`tchr_get_debug_level`, `_wake_up_charger`, `tc_chg_switch_vbus_ovp`). Ketiga
fungsi itu **ada di dalam `tc_charger_framework.ko`** di firmware — jadi
`tc_charger.c` di-compile masuk ke modul itu, bukan jadi modul sendiri.

**Dampaknya sekarang:** `tc_ambient_temp_det` dan `tc_pid_chg_algo` sudah
selesai diport tapi **sengaja belum dimasukkan** karena keduanya mengimpor
`tchr_get_debug_level`. Tanpa modul penyedianya, modprobe akan gagal.

Yang masih bisa diselamatkan: `tchr_get_debug_level` hanyalah 48 byte —
fungsi pembaca `desc->log_level` dengan fallback 3. Isinya sudah
terverifikasi identik dengan source 6.1 (offset 760 = `log_level`). Tapi
membuat modul shim hanya untuk satu fungsi berisiko: begitu
`tc_charger_framework` asli dipasang, akan ada dua penyedia simbol itu.

**Keputusan: tunggu, jangan shim.** Modul ini terlalu sentral untuk ditebak.
Yang harus dilakukan adalah mencari donor 6.12 Transsion lain (perangkat lain
dengan MTK 6.12 + Transsion), atau merekonstruksi 78 ekspor itu dari `.ko`.

### 6.2j Status akhir port `tc_*`

Modul hilang: **61 → 49** dari 237.

Sudah masuk dan terverifikasi identik: `tc_common_class`, `tc_adapter_class`,
`tc_algorithm_class`, `tc_misc_intf`, `tc_ta_class`, `tc_hl7139a`,
`tc_lcd_notify`, `tc_pmic`, `tc_audio`, `tc_phy_insert_det`, `tc_tcpc`,
`tc_port_corrosion_prevention`, `tc_water_detect`, `tc_pd_adapter`,
`tc_temp_forecast`, `tc_otg_ctrl`.

Tertunda karena `tc_charger_framework`: `tc_ambient_temp_det`,
`tc_pid_chg_algo` (source sudah siap, tinggal menunggu fondasi).

Belum ada source sama sekali: `tc_charger_framework`, `tc_gauge`,
`tc_chg_type_det`, `tc_auto_test`, `tc_trancare`, `tc_pep50`,
`tc_pd_algo`, `tc_pe20_algo`, `tc_hvdcp20_algo`, `tc_tc30_algo`,
`tc_tfcp_ta`, `pca_tfcp_ta`.

### 6.3 Kesimpulan Tingkat D

Jangan kerjakan Tingkat D sebelum Phase 3 selesai. Alasannya:
`tran-ufshcd-*`, `tran_zram`, `tran_block`, `tran_mmc_block`, `trans_sched`
semuanya **fork subsistem inti**. Memasangnya berarti mengganti UFS, zram,
block layer, dan scheduler sekaligus — dan kalau satu saja salah, device
tidak boot. Itu bukan cara memulai.


---

## 7. Phase 3 — panel + Iris (INI YANG PALING PENTING)

Panel adalah satu-satunya penghalang boot sungguhan. Tiga modul:

```
rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871   <- panel utama X6871
rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_cl8
ili7838e_fhdp_dsi_cmd_dsc_tm_tm_120hz_cl9
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

3. Port panel `ili7838e` (CMD+DSC) — ada di donor 6.1 **dan** w1vo 6.12.
4. DT: node `panel1@0` + GPIO/regulator sesuai `frag0.dts`.
5. Pasang firmware `iris5.fw` + `pxlw-rm69220_..._x6871.fw` ke image.

Belum: panel belum pernah dijalankan di device.

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
| 3 | Phase 3: vendor Iris + port panel rm69220 | besar | **tinggi** | device bisa nyala |
| 4 | Tingkat B: rename fpsgo/game | kecil | rendah | +2 |
| 5 | Tingkat D: cari donor Transsion 6.12 | ? | ? | ~55 |

Phase 3 didahulukan secara logika (tanpa panel tidak boot), tapi Tingkat A
layak dikerjakan lebih dulu karena murah dan memvalidasi bahwa
`SUPPORT_PLATFORM=mt6895` + `DEFCONFIG_OVERLAYS` bisa dipakai bersamaan.
Jawaban itu menentukan semua langkah berikutnya.

---

## 9. Aset yang sudah diunduh (di `/serverhive1/ramabondanp/tmp/`)

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

## 10. Yang belum terbukti

- **Runtime**: campuran modul Moto + donor OPPO **belum pernah di-boot**.
  Ini berlaku juga untuk hasil Phase 3 nanti.
- `mt6991` / `mt6993`: kabel sudah ada, belum pernah dibangun.
- Tingkat A: belum pernah dibuild dengan `entry_level_legacy.config`.
- Iris: belum pernah dikompilasi terhadap `mediatek_v2` 6.12. Drift struct
  diperkirakan kecil (§7.4) tapi belum dibuktikan dengan compiler.
- Target ABI `user_customer_abi` tidak bisa lulus di tree ini (328 simbol
  duplikat antar varian driver, gagal di `stg merge`). Bukan mismatch KMI.
  Lihat `HANDOFF.md`.
