# PRETEST — simulasi & perbandingan sebelum boot X6871

Dibuat 2026-11-19 sebagai catatan kronologis. Kernel
`w1vo36-6.12-port` sekarang di **`af55c9c00426`**.

> **Status 2026-11-20:** TWRP final memakai **222 modul 100% source**;
> image `twrp-vendor_boot-allsrc-display-usb.img` (md5
> `0ecdaa1edb3d405954331539b24c911b`). Layar mati->nyala (§40), cabut-colok
> USB (§42), insiden panel basi (§43), dan workflow repack otomatis (§44)
> sudah selesai. Angka 796 `.ko` / `modules.load` lama di bagian awal adalah
> snapshot saat itu; angka final: 806 file / 805 nama unik di staging,
> 222 modul recovery, `modules.load` 165, `modules.load.recovery` 216.
> Berikutnya: repack dlkm untuk boot system, lalu kamera.

Bagian penting: §23 (set 222 modul), §24 (set dlkm), §25 (storage fork),
§26 (audit kamera), §40 (layar), §42 (USB), §43 (insiden panel basi),
§44 (repack otomatis), §45 (repack dlkm).

Tujuan: memastikan modul tidak menggantung/menimpa simbol stock dan tidak
melakukan operasi yang bisa merusak hardware **sebelum** image di-boot.
Ini analisis statis, bukan pengganti boot test.

## 1. Metode

- Bandingkan setiap `.ko` hasil build dengan `.ko` stock X6871:
  - exported symbol sebenarnya (`__ksymtab_*`), bukan sekadar GLOBAL
  - imported symbol, alias DT, `depends`, license, vermagic
  - ukuran section `.text/.rodata/.data/.bss`
  - call graph per fungsi dari relokasi `objdump`
- Simulasi loader:
  - seluruh isi `staging/lib/modules/6.12.38-.../` (796 `.ko`)
  - `depmod -n` + `modules.dep` yang digenerate build
  - resolusi simbol dan CRC `modversions` terhadap `Module.symvers` vmlinux
  - fokus pada 237 modul yang ada di `modules.load`/`modules.load.recovery`
    stock + empat modul baru
- Audit hardware: ioremap, regulator, GPIO, SPI, pinctrl, register, dan
  salinan data userspace/DT.

Tool: `tools/ko-preflight.py`.

## 2. Hasil per modul

| Modul | Export asli built/fw | Import built/fw | Alias | `depends` |
|---|---|---|---|---|
| `tran_extcon_usb` | 0 / 0 | 47 / 47 | identik (`transsion,extcon-usb`) | identik (`tc_tcpc,tc_common_class`) |
| `tran_fp` | 0 / 2 | 90 / 145 | identik (`tran_fp_legacy`) | built `spi-mt65xx,mtk_disp_notify`; fw +`transsion_tranlog` |
| `tnek` | **9 / 9** | **24 / 24** | kosong | kosong |
| `tkv` | 0 / 0 | 24 / 23 | kosong | kosong |

Catatan penting: pengecekan sebelumnya memakai semua simbol GLOBAL, sehingga
tampak `tnek 17 == 17` dan `tkv 11 == 11`. Yang benar adalah `__ksymtab`:
firmware `tnek` mengekspor 9, `tkv` **tidak mengekspor apa pun**. Kelebihan
export sudah dihapus di commit `6334ce2b9910`.

- `tran_extcon_usb`: call graph sama; beda hanya `_printk`/`_dev_err`
  (logging).
- `tnek`: call graph sama; beda `__wake_up` (lokasi wake-up) dan
  `__arch_copy_to_user` vs inline copy. Layout node 0x418 / pesan user 0x408
  dijaga `_Static_assert`.
- `tkv`: beda `memchr` vs `strchr` dan tambahan `page_is_ram` (pengaman).
- `tran_fp`: 123 fungsi firmware tidak ada karena firmware membundel backend
  vendor (`gf_*`, `ff_*`, `anc_*`, ...). Port ini **common layer saja**.

## 3. Simulasi load — hasil

Basis: staging tree 796 `.ko` (795 nama unik; `mtk-socinfo.ko` muncul di dua
path). Firmware X6871: 237 `.ko`.

```
modul stock yang ada di staging : 217 / 237
impor tak terselesaikan          : 0
CRC modversions tak terpenuhi    : 0
export ambigu dipakai            : 0
duplikat export antar modul load : 0
```

20 nama stock yang tidak ada semuanya disengaja:

| Kelompok | Jumlah | Nama |
|---|---|---|
| Panel tidak direncanakan | 2 | `ili7838e...cl9`, `rm69220...cl8` |
| Panel X6871 (alias) | 1 | `rm69220...x6871` — sudah dicakup `panel-rm69220-vdo-x6871.ko` |
| MMC/SD tidak direncanakan | 3 | `mtk-mmc-mod`, `sd_tray`, `tran_mmc_block` |
| Storage fork ditunda | 7 | `tran-ufshcd-core`, `tran-ufshcd-pltfrm`, `tran_scsi_mod`, `tran_sd_mod`, `tran_block`, `tran-proc-bootdevice-mod`, `low_latency_sched` |
| Terblokir `transsion_tranlog` | 4 | `transsion_tranlog`, `tc_trancare`, `thd`, `tran_key_bigdata` |
| Fitur mandiri belum diport | 3 | `tkv_recovery`, `tran_rhi`, `tran_expand_key` |

`modules.dep` yang digenerate build untuk empat modul:

```
tran_extcon_usb: tc_tcpc tc_common_class tcpc_class pd_dbg_info tc_charger_class
tran_fp        : spi-mt65xx irq-dbg mtk_disp_notify
tnek           : (kosong)
tkv            : (kosong)
```

Tidak ada lagi `transsion_tranlog` sebagai dependency `tran_fp`.

## 4. Temuan yang diperbaiki

### 4.1 `charger_class.ko` tidak ada di stock X6871

Stock hanya mengirim `tc_charger_class.ko`. Build kita juga meng-install
`charger_class.ko`; keduanya mengekspor `charger_dev_*`/`get_charger_by_name`
dengan CRC berbeda. `tc_tcpc` dan `tc_misc_intf` mengharapkan CRC dari
`tc_charger_class` (`get_charger_by_name = 8bf3c90d`), sedangkan
`charger_class` mengekspor `eac04c96`. Kalau depmod memilih exporter yang
salah, rantai USB/charger gagal load.

Perbaikan: `charger_class` dihapus dari daftar install customer
(`kernel/kleaf/mgk_64.bzl`). Target build tetap ada. Setelah penghapusan:
0 CRC tak terpenuhi di seluruh 217 modul stock yang ada.

### 4.2 Export `tnek`/`tkv`

- `tnek`: buang export `strlcpy`, `tnek_create_node`,
  `tnek_wake_up_poll_and_read`, `tne_pollwait`, `tne_readwait`.
  Sisanya 9, sama dengan firmware.
- `tkv`: buang keenam export; firmware tidak mengekspor semuanya.
  Global tetap ada (ABI internal tidak berubah).

### 4.3 Pengaman hardware

| Modul | Risiko | Pengaman |
|---|---|---|
| `tran_fp` | kode vendor menyetel `regulator-max-microvolt`; pada regulator variabel ini bisa overvoltage | tolak jika `min != max` atau di luar 1,5–3,6 V |
| `tran_fp` | `strcpy` dari DT/user (`fod_location_xy`, `icname[10]`) | `strscpy` + NUL-terminasi |
| `tran_fp` | `memcpy` 128 byte dari netlink skb pendek | copy dibatasi `nlmsg_len`/`skb->len` |
| `tnek` | tag/name/data user tidak tentu NUL | terminasi paksa sebelum `strlcpy`/log |
| `tnek` | race `poll_wait` vs queue | `poll_wait` sebelum cek queue |
| `tkv` | `ioremap` + baca 32 KiB dari alamat bootloader sembarang | wajib page-aligned dan semua page `page_is_ram()`; kalau gagal, lewati `/proc/tkv` |
| `tkv` | `strchr` melewati akhir region | `memchr` dengan panjang terbatas |

`tran_extcon_usb` dan `tnek` tidak menyentuh MMIO/regulator/GPIO. `tkv`
hanya **membaca** region dan menulis `g_tkv` di RAM; tidak menulis balik ke
region bootloader.

### 4.4 Bukti tegangan `tran_fp` aman di X6871

DT `frag0.dts`:

```
fingerprint@0 { compatible = "tran_fp_legacy"; vmch-supply = <...>; };
```

Fixup `mt6368_vfp` mengarah ke node regulator VFP di `base.dts`:

```
regulator-min-microvolt = <0x325aa0>;   /* 3.300.000 uV */
regulator-max-microvolt = <0x325aa0>;
```

Jadi `min == max == 3,3 V`; guard baru lolos dan tetap menyetel 3,3 V.
Bukan vmch variabel 1,2–3,5 V.

## 5. Risiko yang masih tersisa

1. **`tran_fp` belum bisa transfer data SPI.** Common layer menangani
   power/reset/IRQ/SPI clock/netlink/sysfs, tetapi ioctl
   `TRAN_IOC_TRANSFER_CMD` (15), `TRAN_IOC_TRANSFER_RAW_CMD` (16), dan
   `TRAN_IOC_SPI_INIT_CFG_CMD` (17) tidak ditangani. Firmware mengimpor
   `spi_sync`; build kita tidak. Artinya jalur akuisisi fingerprint
   kemungkinan gagal sampai backend Goodix diport. Ini **bukan risiko
   hardware**, tetapi fitur fingerprint belum lengkap.
2. `tran_fasync_for_lcm_full_HBM` dan `yxy_test_func` diekspor firmware,
   tidak oleh build kita. Tidak ada modul lain yang mengimpornya; konfigurasi
   `CONFIG_TRAN_HBM_NOTIFY_FINGERPRINT` tidak aktif di build ini.
3. `tkv`: kalau region `tkv=` adalah reserved DRAM yang tidak ditandai
   System RAM, guard akan menolak dan `/proc/tkv` tidak muncul. Cek dmesg
   saat boot. Kalau itu terjadi, longgarkan guard hanya setelah dipastikan
   alamatnya DRAM, bukan MMIO.
4. `tran_extcon_usb` tidak ada di `modules.load` normal stock (hanya
   recovery). Stock juga begitu; normal boot mungkin mengandalkan alias DT
   `transsion,extcon-usb`/uevent. Kalau role USB tidak berubah, cek apakah
   modul ini benar-benar di-load.
5. `tnek`: `mcDrvModule.ko` hasil build kita **tidak** mengimpor
   `tnek_caller_api` (firmware mengimpor). Modulnya tersedia dan
   `/dev/tnek` bisa dibuka, tetapi normal boot mungkin tidak memakainya.
6. Tujuh fork storage tetap ditunda (Opsi A); baseline GKI/MTK yang dipakai.

## 6. Prasyarat packaging (WAJIB)

Gunakan `modules.dep`/`modules.alias` yang **digenerate build** di:

```
.../mgk_64_k612_customer_modules_install.user/staging/lib/modules/6.12.38-.../modules.dep
```

Jangan memakai `modules.dep` stock: path-nya `/lib/modules/*.ko` (flat),
sedangkan staging memakai `extra/kernel_device_modules-6.12/...`, dan stock
masih mencantumkan `transsion_tranlog.ko` sebagai dependency `tran_fp`.
Kalau image memakai `modules.dep` stock, `modprobe tran_fp` akan gagal karena
`transsion_tranlog.ko` tidak dibangun.

`modules.load` stock boleh dipertahankan (berisi nama modul, bukan path),
selama `modules.dep`/`modules.alias` diregenerasi untuk tree staging.

## 7. Checklist boot test

1. Pastikan image memakai tree staging + `modules.dep` hasil build.
2. `modprobe -n tran_fp`, `modprobe -n tran_extcon_usb` di device (dry-run).
3. Boot; cek dmesg:
   - tidak ada `Unknown symbol` / `disagrees about version of symbol`
   - `tran_extcon_usb` probe (`tran-extcon-usb`)
   - `tran_fp` probe, `/dev/tran_fp`, `/sys/kernel/tran_fp/{vendor_name,ic_name,fod_location_xy}`
   - `tran_fp`: `goodix chip id 0x...` + `ic_name=GOODIX_...`; kalau sensor
     tidak menjawab, probe tetap lanjut dan butuh ±6 s (3 percobaan × 5
     retry × timeout FIFO 200 ms). Untuk boot cepat:
     `tran_fp.tran_fp_detect_chip=0`
   - `tkv`: `/proc/tkv` ada; kalau tidak, cari log
     `tkv: ... is not System RAM, refusing to map`
   - `tnek`: `/dev/tnek` ada
4. Cek USB role switch/uevent (`SWITCH_NAME`/`SWITCH_STATE`) saat colok
   OTG/Type-C.
5. Fingerprint: uji kontrol power/reset/IRQ dulu. `TRAN_IOC_TRANSFER_CMD`
   (15) dan `_RAW_CMD` (16) mengembalikan `-EOPNOTSUPP` selama
   `tran_fp_allow_ree_transfer=0` (default) — itu disengaja.
6. Kalau ternyata HAL memakai jalur REE (bukan TEE), baru aktifkan
   `tran_fp.allow_ree_transfer=1` untuk uji terbatas.

## 8. Reproduksi

```bash
# build
cd /serverhive1/ramabondanp/w1vo
TMPDIR=/serverhive1/ramabondanp/tmp BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1 \
  ./tools/bazel --output_user_root="$PWD/out_bazel" build \
  --config=stamp --repo_manifest="$PWD/kernel_device_modules-6.12/fake_manifest.xml" \
  --experimental_writable_outputs --allow_ddk_unsafe_headers=1 \
  --user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers \
  --repo_env=KERNEL_VERSION=kernel-6.12 --repo_env=KERNEL_BUILD_VARIANT=user \
  --repo_env=DEFCONFIG_OVERLAYS=entry_level_legacy.config \
  --repo_env=SUPPORT_PLATFORM=mt6895 --repo_env=SOURCE_DATE_EPOCH=0 \
  --//build/bazel_mgk_rules:kernel_version=6.12 \
  "//kernel_device_modules-6.12:mgk_64_k612_customer_modules_install.user"

# bandingkan empat modul + seluruh staging tree
cd /serverhive1/ramabondanp/w1vo36-kernel-manifest
python3 tools/ko-preflight.py \
  --built <staging-tree-flat-symlinks> \
  --fw /serverhive1/ramabondanp/tmp/x6871/vr/root/lib/modules \
  --symvers <build>/mgk_64_k612_kernel_aarch64.user/Module.symvers \
  --json /serverhive1/ramabondanp/tmp/pretest-final.json \
  --markdown /serverhive1/ramabondanp/tmp/PRETEST-final.md
```

## 9. Update `tran_fp` — chip id lewat SPI (`29d21b5d018c`)

Modul stock X6871 **tidak** mengimplementasikan ioctl transfer (15/16/17)
dan tidak punya `write()`; yang dipakai userspace adalah `_IO('t',3)`
(`TRAN_FP_READ_FP_ID`) dan deteksi chip id saat probe. Port sebelumnya tidak
punya `spi_sync`, jadi `ic_name`/`vendor_name` kosong. Commit
`29d21b5d018c` menambahkan jalur itu.

Perbandingan ulang (staging 796 `.ko`, `Module.symvers` vmlinux build yang
sama):

| Modul | Export asli built/fw | Import built/fw | Impor tak terselesaikan | CRC mismatch |
|---|---|---|---|---|
| `tran_extcon_usb` | 0 / 0 | 47 / 47 | 0 | 0 |
| `tran_fp` | 0 / 2 | **94 / 145** | 0 | 0 |
| `tnek` | 9 / 9 | 24 / 24 | 0 | 0 |
| `tkv` | 0 / 0 | 24 / 23 | 0 | 0 |

- Satu grup vermagic untuk 795 modul:
  `6.12.38-android16-5-g2c4fd33ae6d8-4k ... modversions aarch64` — tidak ada
  modul `-maybe-dirty`.
- `tran_fp` sekarang mengimpor `spi_sync`; `fw-only-fn` turun ke 120 (sisa
  backend vendor yang tidak dipakai di REE).
- 13 modul lain punya impor tak terselesaikan (`bq2589x_charger`,
  `bt_drv_connac1x`, `gps_drv_stp`, `mtk_charger_framework`,
  `mtk_ufcs_adapter`, `wmt_chrdev_wifi`, `ufs-mediatek-mod-ise`,
  `ise-trusty`, ...). Semuanya modul platform/varian yang memang tidak ada di
  daftar install customer — bukan regresi dari perubahan ini.

Catatan perintah build (sempat salah dan menyebabkan kegagalan palsu di
`mrdump`/`tinysys-scmi`): nilai `DEFCONFIG_OVERLAYS` dan `SUPPORT_PLATFORM`
**wajib** diisi seperti §8. Tanpa `SUPPORT_PLATFORM=mt6895` semua platform
ikut dibangun; tanpa dua flag `unsafe_headers` header GKI privat hilang di
sandbox.

## 10. Simulasi ulang sebelum boot — build final `36e0f17945e8`

Dijalankan ulang 2026-11-19 atas staging 795 `.ko` hasil build terakhir
(`mgk_64_k612_customer_modules_install.user`, mt6895,
`entry_level_legacy.config`). Sumber angka:
`/serverhive1/ramabondanp/tmp/pretest-final2.json`.

### 10.1 Hasil loader

| Modul | Export (built/fw) | Import (built/fw) | Impor tak terselesaikan | CRC mismatch |
|---|---|---|---|---|
| `tran_extcon_usb` | 0 / 0 | 47 / 47 | 0 | 0 |
| `tran_fp` | 0 / 2 | 94 / 145 | 0 | 0 |
| `tnek` | 9 / 9 | 24 / 24 | 0 | 0 |
| `tkv` | 0 / 0 | 24 / 23 | 0 | 0 |

- **Satu** grup vermagic untuk 795 modul:
  `6.12.38-android16-5-g2c4fd33ae6d8-4k SMP preempt mod_unload modversions aarch64`.
- `stack_frames_over_1k` untuk `tran_fp`: kosong (tidak ada array besar di
  stack kernel).
- Import yang ada di build kita tapi tidak di firmware:
  `__check_object_size` (fortify usercopy), `sized_strscpy`, `strcmp`,
  `mtk_disp_notifier_unregister`. Semuanya benign; `spi_sync` **ada di
  keduanya**.
- 216 CRC mismatch dan 13 modul dengan impor tak terselesaikan
  (`bq2589x_charger`, `bt_drv_connac1x`, `gps_drv_stp`,
  `mtk_charger_framework`, `mtk_ufcs_adapter`, `wmt_chrdev_wifi`,
  `ufs-mediatek-mod-ise`, `ise-trusty`, `leds-mtk-disp`, `mtk_em`,
  `mtk_hvbpc`, `mtk_pep50p`, `fmradio_drv_mt6631_6635`) semuanya modul
  platform/varian yang tidak ada di daftar install customer. **Tidak satu pun
  menyentuh empat modul kita.**

### 10.2 Paritas akses SPI dengan stock

| Parameter | Stock (disasm `tran_fp.ko`) | Port ini |
|---|---|---|
| Urutan chip id | tulis `0xf0` (len 3), lalu `0xf1` (len 5) | sama |
| Posisi id | byte 5..8 dari respons kedua | sama |
| bits per word | 8 | 8 |
| Speed | 1 MHz (`tran_spi_speed` = 1000000 di `.data`) | 1 MHz (`tran_fp_spi_speed`) |
| Retry | 5 × `spi_sync` | 5 |
| Transfer per message | sampai 2 | sampai 2 |
| Tunggu | busy `udelay` | `msleep` (lebih ringan) |
| Urutan probe | power → pinctrl spi_default → spi_clk_on → chip id | sama |

### 10.3 `spi->controller_data` — dibuktikan, bukan diasumsikan

- `offsetof(struct spi_device, controller_data)` = **960**, dikonfirmasi dari
  `spi-mt65xx.ko` hasil build: `mtk_spi_setup` → `str x21,[x19,#960]`,
  `mtk_spi_cleanup` → `ldr x0,[x0,#960]` lalu `kfree`.
- Stock `tran_fp_spi_transfer` menulis `str x0,[spi,#960]` dengan
  `x0 = &tran_chip_config`, jadi stock **menimpa** `controller_data`.
- `tran_chip_config` stock = **32 byte, seluruhnya nol** (dump `.data`),
  sehingga `BUG_ON(chip_config->cs_setuptime | cs_holdtime | cs_idletime)`
  di `spi_dump_config()` tidak menyala. `BUG_ON` itu ada di build kita **dan**
  di `spi-mt65xx.ko` stock (masing-masing 1 `brk` di
  `mtk_spi_prepare_message`).
- Namun `mtk_spi_cleanup()` mem-`kfree()` pointer tersebut → stock menyimpan
  **invalid free laten** saat device dilepas / modul di-unload.
- Port ini **tidak** menulis `controller_data`; MTK driver memakai
  `mtk_chip_config` alokasinya sendiri (cs timing nol = default). Efek
  fungsional identik dengan stock, tanpa `BUG_ON` dan tanpa invalid free.

### 10.4 Audit API hardware pada diff

`git diff 6334ce2b9910 36e0f17945e8` — seluruh baris tambah hanya menyentuh:

`spi_sync`, `spi_message_init`/`spi_message_add_tail`, `kmalloc`/`kzalloc`/
`kfree`, `copy_from_user`/`copy_to_user`, `msleep`, `of_find_property`.

Tidak ada `ioremap`, `readl`/`writel`, `regulator_*`, `gpio_*`, `clk_*`,
`pinctrl_*`, `request_irq`, atau DMA mapping baru.

### 10.5 Batas kemampuan menulis register sensor

Satu-satunya jalur yang bisa menulis register dari userspace adalah ioctl
15/16, dan sekarang **opt-in**:

- `tran_fp_allow_ree_transfer=0` (default) → `-EOPNOTSUPP`, sensor tidak
  disentuh.
- Kalau diaktifkan: `len` ≤ 4096, alamat 16 bit big-endian, `speed_hz` ≤
  `spi-max-frequency`, payload di-bounce ke memori kernel.
- Stock tidak punya jalur ini sama sekali, jadi default-off tidak mengurangi
  fungsi apa pun di X6871.

### 10.6 Sisa risiko

1. Bila sensor tidak menjawab, probe `tran_fp` menambah ±6 s boot
   (3 percobaan × 5 retry × timeout FIFO 200 ms). Bounded, bukan hang.
   Matikan dengan `tran_fp.tran_fp_detect_chip=0`.
2. `tran_fp` masih tanpa backend vendor (`fw-only-fn` 120). Akuisisi gambar
   di X6871 berjalan di TEE; ini perlu dibuktikan saat boot, bukan sekarang.
3. 216 CRC mismatch / 13 unresolved modul lain: pre-existing, di luar scope.

## 11. Audit seluruh pengganti modul stock (`tools/preboot-audit.py`)

§1–§10 membandingkan empat modul fitur. Bagian ini memeriksa **setiap modul
stock yang digantikan build kita** — satu baris per `.ko` firmware, bukan per
`.ko` yang kebetulan ikut ter-build. Dijalankan atas staging
`6.12.38-android16-5-g2c4fd33ae6d8-4k` final.

```bash
python3 tools/preboot-audit.py \
  --built <staging>/lib/modules/6.12.38-android16-5-g2c4fd33ae6d8-4k \
  --fw /serverhive1/ramabondanp/tmp/x6871/vr/root/lib/modules \
  --symvers <build>/mgk_64_k612_kernel_aarch64.user/Module.symvers \
  --json /serverhive1/ramabondanp/tmp/preboot-audit.json \
  --markdown /serverhive1/ramabondanp/tmp/preboot-audit.md
```

### 11.1 Inventory

| Item | Nilai |
|---|---|
| modul stock (`.ko` di firmware) | 237 |
| punya pengganti di build | 217 |
| tidak ada di build | 20 (§11.5) |
| pengganti yang di-load stock (`modules.load`/`.recovery`) | 217 (semua) |
| vermagic set build | `6.12.38-android16-5-g2c4fd33ae6d8-4k` — **1 grup** |
| vermagic stock | `6.12.38-android16-5-gcc51d883045d-4k` — 1 grup, **beda commit** |
| basename duplikat di staging | `mtk-socinfo.ko` (§11.4) |

Release string vermagic stock (`gcc51d883045d`) berbeda dari build kita
(`g2c4fd33ae6d8`), tapi itu **bukan** penghalang: dengan
`CONFIG_MODVERSIONS`, `same_magic()` melewati token pertama vermagic
(`kernel/module/version.c`: "First part is kernel version, which we ignore if
module has crcs"). Yang menentukan hanya simbol + CRC. Untuk pasangan build
ini: 2174 simbol kernel dipakai keduanya, **2174/2174 CRC identik**, dan
795/795 modul build kita cocok CRC-nya dengan kernel stock.

### 11.2 Simulasi loader pada set pengganti

| Item | Jumlah |
|---|---|
| modul dengan impor tak terselesaikan | **0** |
| CRC mismatch (modversions) | **0** |
| export duplikat di dalam set | **0** |
| tabrakan simbol dengan vmlinux | **0** |

Angka ini dihitung hanya dari 217 modul yang menggantikan modul stock, dengan
`Module.symvers` vmlinux dari build yang sama. Simbol undefined ber-binding
`WEAK` dikecualikan karena resolve ke 0 dan tidak pernah menggagalkan load
(contoh: `leds-mtk-disp` → `mtk_drm_gateic_set_backlight`, tidak diekspor oleh
siapapun, stock maupun build).

### 11.3 Status struktural per modul

`0 fail`, `58 warn`, `159 ok`. Rincian warn:

| Kategori | Jumlah | Arti |
|---|---|---|
| `depends` drift | 31 | hampir semua **pengurangan**: stock bergantung pada modul yang tidak diport (`transsion_tranlog`, `thd`, `tran_mmc_block`, `tran-ufshcd-*`, `tran-proc-bootdevice-mod`, `tran_scsi_mod`, `tran_expand_key`, `tran_key_bigdata`). Build kita meng-gate ketergantungan itu saat compile. |
| export tidak diekspor ulang | 23 | tidak ada satu pun yang diimpor modul lain di set → aman |
| export baru | 12 | tambahan, tidak menimpa simbol vmlinux (kernel-collisions 0) |
| **API hardware baru** | 3 | lihat di bawah |
| license string | 3 | kosmetik (multi-license `GPL`/`GPL v2`), hanya memengaruhi taint flag |

Tiga modul yang menambah akses hardware dibanding stock:

| Modul | API baru | Catatan |
|---|---|---|
| `clk-common.ko` | `clk_enable`, `clk_set_rate` | source berbeda (commit stock lain); clock framework MTK, bukan register mentah |
| `tran_ldo.ko` | `regulator_enable`, `regulator_disable` | modul Transsion hasil port; LDO memang harus enable/disable lewat regulator framework |
| `tran_usb_ctrl.ko` | `gpio_request` | modul Transsion hasil port; meminta GPIO lewat API standar, bukan menulis register |

Ketiganya memakai API kernel (bukan `ioremap`/`writel` mentah), jadi kegagalan
akan berupa error probe, bukan akses alamat sembarangan. Tetap dicek di dmesg.

`depends` drift yang **menambah** dependensi hanya dua, keduanya modul yang ada
di set: `leds-mtk-disp` (+`mtk_panel_ext`) dan `tc_hl7139a` (+`tc_misc_intf`).

### 11.4 `mtk-socinfo.ko` ter-build dua kali

Staging berisi dua salinan:

- `kernel/drivers/soc/mediatek/mtk-socinfo.ko` (dari GKI/kernel image)
- `extra/kernel_device_modules-6.12/drivers/soc/mediatek/mtk-socinfo.ko`
  (dari target device `//.../drivers/soc/mediatek:mtk-socinfo`)

Keduanya mengekspor set yang sama (hanya `init_module`/`cleanup_module`) dan
tanpa `depends`, jadi **bukan penghalang boot**. `depmod` memilih yang GKI
(`modules.dep: kernel/drivers/soc/mediatek/mtk-socinfo.ko`), salinan `extra/`
ter-shadow. Kalau tree staging di-flatten dengan urutan copy yang berbeda,
pemenangnya bisa berbalik — karena itu sebaiknya salah satu dikecualikan
eksplisit saat packaging.

### 11.5 Dua puluh modul stock tanpa pengganti

Persis daftar yang sudah diputuskan di `HANDOFF.md`, bukan temuan baru:

- 2 panel yang tidak direncanakan + 1 alias panel
  (`rm69220_..._cl8`, `ili7838e_..._cl9`, `rm69220_..._x6871`)
- 3 modul MMC/SD (`mtk-mmc-mod`, `tran_mmc_block`, `sd_tray`)
- 7 fork storage/UFS (`tran-ufshcd-core`, `tran-ufshcd-pltfrm`, `tran_scsi_mod`,
  `tran_sd_mod`, `tran_block`, `tran-proc-bootdevice-mod`,
  `low_latency_sched`)
- 4 modul yang butuh `transsion_tranlog` (`tc_trancare`, `thd`,
  `tran_key_bigdata`, `transsion_tranlog`)
- 3 fitur independen (`tkv_recovery`, `tran_rhi`, `tran_expand_key`)

Konsekuensinya terlihat di §11.3: modul stock yang bergantung pada mereka
kehilangan dependensi itu di build kita, dan itu disengaja.

### 11.6 Kesimpulan audit

Untuk boot test, set pengganti 217 modul bersih di level loader: tidak ada
simbol menggantung, tidak ada CRC mismatch, tidak ada tabrakan simbol. Sisa
risiko ada di perilaku runtime, bukan di resolusi simbol — dan semuanya
tercakup checklist §7.

## 12. KMI / CRC lintas build (koreksi asumsi vermagic)

Asumsi awal yang salah: "release string vermagic berbeda → modul tidak bisa
load". `same_magic()` di `kernel/module/version.c`:

```c
/* First part is kernel version, which we ignore if module has crcs. */
int same_magic(const char *amagic, const char *bmagic, bool has_crcs)
{
	if (has_crcs) {                 /* CONFIG_MODVERSIONS + __versions */
		amagic += strcspn(amagic, " ");
		bmagic += strcspn(bmagic, " ");
	}
	return strcmp(amagic, bmagic) == 0;
}
```

Jadi dengan modversions, yang dibandingkan hanya sisa setelah spasi pertama
(` SMP preempt mod_unload modversions aarch64`). Kompatibilitas nyata
ditentukan oleh **keberadaan simbol + CRC per simbol**.

Pengukuran untuk build ini:

| Uji | Hasil |
|---|---|
| CRC kernel stock, dipanen dari `__versions` 237 modul stock | 3161 simbol |
| simbol diekspor vmlinux build kita | 18769 |
| simbol kernel yang dipakai kedua build | 2174 |
| CRC identik pada irisan itu | **2174 / 2174** |
| modul build kita yang seluruh impor-kernel-nya cocok CRC dengan stock | **795 / 795** |

Kesimpulan: modul kita dapat di-load pada kernel stock, dan sebaliknya —
release string tidak menghalangi.

Catatan supaya tidak salah baca: bila dibandingkan **tanpa** menyaring ke
simbol kernel, 126 modul tampak "CRC beda" (mis. `mtk_panel_ext_create`,
`cmdq_pkt_create`, `get_charger_by_name`, `tran_led_device_register`). Itu
simbol yang diekspor **modul lain**, bukan kernel. Karena kita mengganti
seluruh set modul sekaligus, CRC antar-modul konsisten di dalam set kita
(§2: 0 CRC mismatch), jadi perbedaan itu tidak relevan untuk boot.

Tetap disarankan memakai kernel + modul dari satu build: bukan karena ABI,
tetapi supaya perilaku kode (bukan hanya simbol) konsisten.

## 13. Kelas bug yang paling berbahaya: tabel ber-indeks DT

Boot kedua (`pstore2.txt`) berhenti bukan karena simbol atau CRC, tapi karena
**nomor power domain bergeser satu**. Pelajarannya berlaku umum untuk semua
tabel yang diakses DT lewat nomor, bukan lewat nama.

### Gejala

```
[DEVAPC]: Write Violation
[DEVAPC]: Vio Addr:0x15000008, High:0x0, Bus ID:0x2508, Dom ID:0x0
[DEVAPC]: Violation - master: MCU_AP_M access violation slave: IMG_APB_S
[DEVAPC]: Violation Type: "Decode error or way_en"
[DEVAPC]: [KE] Device APC Violation Issue/IMG_APB_S
kernel BUG at ../kernel_device_modules-6.12/drivers/soc/mediatek/devapc/devapc-mtk-multi-ao.c:1049!
pc : devapc_extra_handler+0x440/0x51c [device_apc_common]
```

`0x15000008` = CG register `syscon@15000000` (imgsys_main). Penulisnya
`mtk_smi_common_probe` untuk `smi-img-sub-comm0@15002000`, yang di DT punya
`power-domains = <&scpsys 7>` + `clocks = <&imgsys_main 0 0xd 0xe 0x11>`.
Power domain 7 di stock = `isp_main`; di build kita = `isp_vcore`, jadi
ISP_MAIN tidak pernah nyala sementara clock-nya di-enable → pelanggaran
DEVAPC → kebijakan KE → `BUG_ON`.

### Cara mendeteksi (tanpa hardware)

Ukuran dan urutan tabel dibaca langsung dari `.ko` stock vs build:

```bash
aarch64-linux-gnu-nm -S --defined-only stock/mtk-scpsys-mt6895.ko | grep scp_domain_data
# stock : 0x6ee8 = 28392 byte = 39 entri x 728
# build : 0x71c0 = 29120 byte = 40 entri x 728     <-- satu entri lebih
```

Nama tiap entri diambil dari relokasi `R_AARCH64_ABS64` di `.rela.rodata`
(field pertama setiap entri = pointer ke `.rodata.str1.1`):

```
stock : 0=md 1=conn 2=adsp_infra 3=audio ... 6=isp_vcore 7=isp_main 8=isp_dip1
build : 0=md 1=conn 2=ufs0_shutdown 3=adsp_infra ... 7=isp_vcore 8=isp_main
```

`ufs0_shutdown` disisipkan di indeks 2 (ada di binding header cabang kita,
tidak ada di build stock), sehingga **semua domain setelah indeks 1 bergeser
+1**.

### Perbaikan

Disamakan dengan stock (39 domain, tanpa `ufs0_shutdown`):

- `include/dt-bindings/power/mt6895-power.h`: entri dihapus, nomor sesudahnya
  diturunkan satu, `MT6895_POWER_DOMAIN_NR` = 39
- `drivers/soc/mediatek/mtk-scpsys-mt6895.c`: blok
  `[MT6895_POWER_DOMAIN_UFS0_SHUTDOWN]` dihapus
- `drivers/clk/mediatek/mtk-pd-chk-mt6895.c`: 3 referensi dihapus
- `arch/arm64/boot/dts/mediatek/mt6895.dts`: `power-domains` pada node
  `ufshci` dihapus — DT stock memang tidak punya properti itu

### Aturan untuk modul berikutnya

Untuk setiap tabel yang dipakai DT lewat indeks (power domain, clock,
IOMMU bank, GCE), **ukuran tabel di `.ko` build harus sama dengan stock**.
Selisih ukuran simbol data adalah tanda paling cepat; urutannya diverifikasi
lewat relokasi string seperti di atas. Tabel yang diakses lewat nama
(regulator, alias, `of_match`) tidak punya risiko ini.

## 14. Stub inline karena `CONFIG_TC_CLASS_SUPPORT` tidak aktif

Boot keempat (`pstore4.txt`) memuat 73 modul, tanpa `Unknown symbol`, lalu
panic di 1,77 detik:

```
[misc_intf] tc_misc_probe: register tc_misc device failed
[misc_intf] tc_get_misc_info: get tc_misc dev fail
Unable to handle kernel NULL pointer dereference at virtual address 0000000000000020
pc : tc_disable_hw_ovp+0x24/0x8c [tc_misc_intf]
```

### Bukti dari binari stock

`tc_common_class.h` memilih implementasi berdasarkan
`#if IS_ENABLED(CONFIG_TC_CLASS_SUPPORT)`: kalau makro itu tidak ada, semua
fungsi jadi `static inline` stub (`tran_device_register()` mengembalikan
`NULL`, `tran_get_by_name()` `NULL`, `tran_dev_set_prop()` `-ERROR_NO_IMPLEMENT`).

Perbandingan simbol impor stock vs build:

| modul | stock | build | hilang di build |
|---|---|---|---|
| `tc_misc_intf` | 4 | 0 | `tran_device_register`, `tran_get_by_name`, `tran_dev_set_prop`, `tran_dev_get_prop` |
| `mtk_battery_manager` | 4 | 0 | idem |
| `mt6375-battery` | 4 | 0 | idem |
| `rt6160-regulator` | 1 | 0 | `tran_device_register` |
| `tc_tfcp_ta` | 2 | 0 | `tran_dev_get_prop`, `tran_get_by_name` |
| `tcpc_class` | 2 | 0 | `tran_dev_get_prop`, `tran_get_by_name` |
| `tc_temp_forecast` | 4 | 2 | `tran_dev_get_prop`, `tran_get_by_name` |
| `tc_tcpc` | 0 | 1 | (build justru lebih banyak) |

Penyebabnya: di `drivers/power/supply/BUILD.bazel`, hampir semua target
`tc_*` punya `copts = ["-DCONFIG_TC_CLASS_SUPPORT=1"]`, tetapi
`tc_misc_intf`, `mtk_battery_manager`, dan dua target `*-battery` tidak.
`drivers/regulator/BUILD.bazel` untuk `rt6160-regulator` juga tidak.

Akibatnya `tc_misc_probe` memanggil `tran_device_register()` versi stub yang
selalu mengembalikan `NULL`, device `tc_misc` tidak pernah terdaftar, dan
`tc_disable_hw_ovp()` — yang tidak memeriksa hasil `tc_get_misc_info()` —
membaca `info->pmic_dev`. `pmic_dev` ada di offset 0x20 `struct misc_info`,
persis alamat fault di log.

### Perbaikan

Tambahkan `-DCONFIG_TC_CLASS_SUPPORT=1` ke copts target `tc_misc_intf`
(`drivers/power/supply/BUILD.bazel`). Setelah rebuild, `tc_misc_intf.ko`
mengimpor 4 simbol `tran_*` — **sama dengan stock** — sehingga device
`tc_misc` benar-benar terdaftar dan jalur `tc_disable_hw_ovp()` tidak lagi
menyentuh `NULL`.

Define yang sama juga ditambahkan ke `mtk_battery_manager`,
`{}_battery`/`{}-battery`, dan `rt6160-regulator`, tapi untuk empat modul itu
**tidak mengubah apa pun**: sumbernya di cabang ini (`mtk-battery-manager.c`,
`mtk_battery.c`, `rt6160-regulator.c`) tidak memanggil `tran_*` sama sekali.
Stock memanggilnya, jadi itu drift sumber, bukan config. Sama untuk
`tc_temp_forecast`, `tc_tfcp_ta`, `tcpc_class`, `tc_tcpc`.

### Aturan

Selisih **set simbol impor** terhadap stock adalah cara tercepat menemukan
fitur yang mati, sebelum menyentuh hardware. Untuk modul Transsion, periksa
khusus `tran_*`:

- stock impor, build tidak, **dan sumber build memang memanggil `tran_*`**
  → define config hilang (kasus `tc_misc_intf`)
- stock impor, build tidak, **dan sumber build tidak memanggilnya**
  → drift sumber; perlu porting kode stock, config tidak menolong

## 15. Modul yang namanya beda dari stock ikut terbuang filter

Boot kelima (`pstore5.txt`) berhasil memuat **214 modul** tanpa `NULL
dereference`, tetapi layar mati dan USB tidak siap. Penyebab layar:

```
mtk-dsi 14017000.dsi: Waiting for bridge or panel driver
platform 14017000.dsi: deferred probe pending: (reason unknown)
```

Panel untuk X6871 **ada** di build kita, hanya namanya berbeda dari stock
sehingga terbuang oleh filter "hanya modul yang dikirim stock":

| | nama file |
|---|---|
| stock | `rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.ko` |
| build | `panel-rm69220-vdo-x6871.ko` |

Keduanya driver yang sama — alias-nya identik:
`of:N*T*Crm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871`. Karena
`modules.load` stock menyebut nama stock, entri itu juga dibuang, jadi panel
tidak pernah dimuat dan DSI menunggu selamanya.

Perbaikan di `tools/pack-vendor-boot.sh`: peta `RENAME_MAP` yang menyebut
pasangan nama stock → nama build. Modul dengan padanan dipertahankan, dan
entri `modules.load`/`modules.load.recovery` milik stock diterjemahkan ke
nama file kita (posisi urutan tetap). Hasil: 218 modul,
`modules.load` 164 entri, `modules.load.recovery` 214 entri, panel ada di
keduanya.

Cara menemukan pasangan yang hilang tanpa hardware: bandingkan alias `of:`
dari `modinfo -F alias` antara `.ko` stock dan set build. Untuk 20 modul
stock yang tidak punya kembaran nama, hanya satu yang punya padanan alias —
panel X6871 di atas.

### Sisa masalah di log yang sama

- `ssusb_hwrscs_req timeout, spm_ctrl=0x5f, value=0x1f` — SPM tidak
  meng-ack bit `SSUSB_SPM_EMI_EN` (BIT 6). Muncul di semua boot (termasuk
  sebelum perbaikan apa pun), jadi bukan regresi dari modul kita.
- `is_usb_rdy: usb ready = 0` berulang — node USB di DT stock memang punya
  properti `cdp-block` (base.dts:9002), jadi `ready = !cdp-block` selalu 0.
  Deteksi BC1.2 menunggu, bukan berarti gadget mati.
- `deferred probe pending` juga menyebut `odm:rt5133-gpio1/gpio2` yang
  menunggu regulator `rt5133` LDO1.

## 16. Modul build kehilangan ekspor yang dimiliki stock

Boot TWRP (`pstore6.txt`) berhenti di modul ke-40:

```
tran_expand_key: Unknown symbol Mannual_hang (err -2)
tran_expand_key: Unknown symbol manual_two_key_hang (err -2)
init: Failed to insmod '/lib/modules/tran_expand_key.ko'
init: Loaded 40 modules from /lib/modules
init: Failed to load kernel modules -> InitFatalReboot
```

Penyebabnya bukan `tran_expand_key`, tapi `monitor_hang.ko`. Di stock,
`monitor_hang.ko` mengekspor dua variabel:

```
B Mannual_hang          (dan __ksymtab_Mannual_hang)
D manual_two_key_hang
```

Versi kita tidak punya keduanya — namanya bahkan tidak muncul di `.ko`.
Selama set kita dipakai sendiri (218 modul), tidak ada yang mengimpor simbol
itu sehingga aman. Begitu digabung dengan modul stock/TWRP (yang memuat
`tran_expand_key.ko`), modul itu gagal load dan init abort.

### Cara mendeteksi seluruhnya sekaligus

1. Untuk setiap modul yang kita ganti, hitung `ksymtab(stock) - ksymtab(build)`.
   Hasilnya 23 modul kehilangan ekspor.
2. Untuk setiap modul di set gabungan, cari yang mengimpor simbol-simbol itu.

Hasilnya tepat dua modul, dan cocok dengan log:

| modul | simbol hilang | penyedia di stock |
|---|---|---|
| `tran_expand_key.ko` | `Mannual_hang`, `manual_two_key_hang` | `monitor_hang.ko` |
| `ili7838e_...cl9.ko` | `g_lcm_connect_state`, `g_lcm_custom_info` | `mediatek_drm_v1.ko` |

Dua modul itu dibuang dari image TWRP (238 modul,
`modules.load`/`.recovery` 177/234 entri). `ili7838e` memang panel perangkat
lain; `tran_expand_key` hanya fitur tombol tambahan.

### Aturan

Set modul kita aman selama dipakai utuh. Begitu dicampur dengan `.ko` stock
(mis. untuk membangun image TWRP), **ekspor yang hilang berubah jadi
kegagalan load**. Selalu jalankan langkah 1–2 di atas untuk set campuran;
jangan hanya membandingkan impor (loader sim) dalam set kita sendiri.

## 17. TWRP boot bersih; sisa isu USB

`dmesg1.txt` (TWRP + 238 modul kita): **235 modul load, 0 `Unknown symbol`,
tanpa panic.**

- Layar: `mtk-dsi ... Waiting for bridge or panel driver` berhenti tepat
  setelah `panel-rm69220-vdo-x6871.ko` dimuat (2,044 s), lalu DSI init dan
  `mediatek-drm` bind seluruh komponen + CRTC enable.
- Sentuh: `gt9916` load, firmware PID terbaca.

USB tetap tidak enumerate. Urutan dari log:

```
9.894  mtu3: ssusb_set_mode device            <- role switch (tran_extcon_usb)
9.894  mtu3: port on (6)
9.914  mtu3: ssusb_hwrscs_req timeout, spm_ctrl=0x5f, value=0x1f
9.917  xsphy: u2/u3 phy power on + set_mode(6)
9.918  mtu3: gadget (high-speed) pullup D+
       ... tidak ada event USB apa pun setelah ini (tanpa reset/enumerasi)
```

Ditambah dari sisi charger:

```
9.875  tc_detect_do_bc12: usb_type:DCP
10.00+ do_bc12_pre_work: check CDP block  (berulang tiap 1 detik)
```

Catatan: mask SPM di mtu3 stock juga `0x5f` (EMI_EN ikut diminta), jadi
timeout `ssusb_hwrscs_req` bukan drift kita — kemungkinan memang perilaku
platform.

Yang berbeda dari stock justru hampir seluruh tumpukan USB:

| modul | ukuran build vs stock |
|---|---|
| `mtu3` | 271.784 vs 279.360 |
| `xhci-mtk-hcd-v2` | 544.688 vs 554.536 |
| `phy-mtk-xsphy` | 89.672 vs 95.296 |
| `tc_chg_type_det` | 53.520 vs 59.656 |
| `tran_extcon_usb` | 31.800 vs 31.928 |
| `usb_dp_selector` | 21.736 vs 21.864 |
| `tc_tcpc` | 31.904 vs 30.504 |
| `mux_switch` | sama byte-per-byte |

Karena itu dibuat image pembanding `twrp-vendor_boot-usbstock.img`: 238 modul,
tujuh modul USB di atas diganti versi stock, sisanya tetap modul kita. Kalau
adb hidup dengan image ini, bug ada di salah satu dari tujuh modul itu dan
biseksi bisa mulai dari `tc_chg_type_det` (DCP + loop 1 detik) lalu
`tran_extcon_usb` (role switch), baru `mtu3`/`phy-mtk-xsphy`.

## 18. USB mati karena `CONFIG_TC_CHARGER` tidak aktif

Biseksi pada image TWRP: seluruh 40 modul charger/typec dikembalikan ke stock
→ USB hidup. Lalu hanya 7 modul IC/PMIC (`mt6375-charger`, `mt6375-battery`,
`mtk_battery_manager`, `pca_tfcp_ta`, `pmic_lbat_service`,
`pmic_lvsys_notify`, `rt_pd_manager`) dikembalikan ke stock → USB tetap hidup.
Jadi biangnya di salah satu 7 itu.

Diff per fungsi `mt6375-charger.ko` build vs stock: hanya 3 fungsi beda, dan
yang menentukan identitas konfigurasi:

| fungsi | build | stock |
|---|---|---|
| `mt6375_fl_bc12_dn_handler` | 224 | **148** |
| `mt6375_chg_get_property` | 1756 | 1732 |
| `mt6375_get_vbus_gd_stat` | — | 192 |

Sumbernya punya dua implementasi:

```c
#if IS_ENABLED(CONFIG_TC_CHARGER)
	... ddata->tc_bc12_dn = true;        /* 148 byte, dipakai stock */
#else
	... atomic_read(&ddata->attach[0]);  /* 224 byte, dipakai build kita */
#endif
```

`drivers/power/supply/BUILD.bazel` untuk `mt6375-charger` hanya memberi
`-DCONFIG_TC_CLASS_SUPPORT=1`; `CONFIG_TC_CHARGER` tidak pernah didefinisikan.

Rantai ke USB: handler BC1.2 versi legacy tidak melaporkan D− seperti stock →
`tc_detect_do_bc12` menyimpulkan **DCP** → `do_bc12_pre_work` mengulang tiap
1 detik (`check CDP block`) dan memanggil `tcd_set_usbsw()` yang men-set U2
PHY ke mode BC1.2 → D+ pullup tidak pernah menetap → tidak ada enumerasi,
walau `gadget (high-speed) pullup D+` sudah dicetak.

Perbaikan: `-DCONFIG_TC_CHARGER=1` untuk target `mt6375-charger` dan
`tc_hl7139a` (modul terakhir juga memakai makro itu; sebelumnya 16 fungsi
beda dari stock). Setelah rebuild, `mt6375_fl_bc12_dn_handler` = 148 byte,
sama dengan stock.

Sisa drift yang diketahui pada modul ini: `mt6375_get_vbus_gd_stat` (192 byte)
ada di stock tapi tidak ada di sumber cabang ini.

### Pola yang berulang

Ini kasus ketiga setelah `CONFIG_TC_CLASS_SUPPORT` (§14) dan indeks power
domain (§13). Semuanya lolos dari audit ELF/CRC karena modulnya tetap bisa
dimuat — yang hilang adalah **perilaku**. Deteksi paling andal: bandingkan
ukuran/daftar fungsi `.ko` kita dengan stock per modul; fungsi yang hilang
atau berukuran jauh berbeda menunjuk langsung ke `#if` yang salah cabang.

## 19. Trim modul dlkm berdasarkan DT X6871

Sebelum mem-port 35 modul dlkm yang belum kita build, daftar itu dipangkas
memakai DT stock (`base.dtb` + satu fragmen `dtbo.img`). Caranya: ambil
`compatible` dari semua node, lalu cocokkan dengan alias `of:` tiap `.ko`.

Modul hardware yang benar-benar ada di board:

| Modul | Node DT | Sumber |
|---|---|---|
| `sgm37864_v4l2` | `sgm37864_v4l2@64` | donor 6.1 (sudah di-port) |
| `ocp81375_v4l2` | `ocp81375_v4l2@41` | donor 6.1 (sudah di-port) |
| `aw8601af` | `camera_af_main@0C` | ditulis ulang (lihat di bawah) |
| `snd-soc-fs1599` | `fs15xx_pa@34`, `@35` | donor 6.1 (sudah di-port) |
| `gt9916_common` | `goodix,gt9916` | donor 6.1 (sudah di-port) |
| `adaptive-ts` | core touch | donor 6.1 (sudah di-port) |
| `tran_richtap_haptic_hv` | `haptic_hv@5A` | donor 6.1 (sudah di-port) |

Tidak ada di DT, jadi tidak perlu di-port: `aw36515_v4l2`, `aw36515`,
`ak7316`, `dw9800k`, `dw9784ois`, `focaltech_ft3683g`,
`chipsemi_chsc5xxx_old`, `snd-soc-fs1894`, `snd-soc-aw87xxx`,
`snd-soc-oca72xxx`, `elliptic-ultrasound`.

17 modul software tidak punya alias/DT sama sekali dan dimuat lewat
`modules.load`: `thd`, `transsion_tranlog`, `tran_zram`, `trans_sched`,
`pages_prefilter`, `priority_allocate`, `tran_mm_collect`,
`tran_perf_util`, `tran_health_sched`, `tran_key_bigdata`,
`tran_audio_typec`, `tc_trancare`, `perf_common_v`, `game`,
`task_turbo_v`, `fpsgo`, `mtk-vcodec-sys-api`. `transsion_tranlog` dan
`thd` tetap wajib karena menjadi dependency `adaptive-ts`.

### Catatan port

- `snd-soc-fs1599`: perlu `-DCONFIG_SND_SOC_FS1599=1`, `ko_deps` ke
  `mtk-sp-spk-amp`, dan `no_llseek` -> `noop_llseek`. Daftar fungsi sama
  persis dengan stock (152/152).
- `tran_richtap_haptic_hv`: `probe` 6.12 dan `GPIOF_DIR_IN` -> `GPIOD_IN`.
  Daftar fungsi sama persis dengan stock (430/430).
- `aw8601af`: tidak ada sumber di donor. Driver v4l2 ditulis ulang dari
  disassembly stock: regulator `vin`/`vdd`, pinctrl `vcamaf_on`/`off`,
  alamat i2c `0x0c`, init `0x02=01, 0x02=00, 0x02=02, 0x06=40, 0x07=7b,
  0x03=01, 0x04=77`, posisi fokus ditulis ke reg `0x03` sebagai word
  byte-swapped, range 0..1023. `aw8601af_set_ctrl` sama ukuran dengan
  stock (0xa4).
- `adaptive-ts`/`gt9916_common`: donor 6.1 lebih kecil dari build stock
  X6871 (17 vs 189 dan 105 vs 186 fungsi). Fitur Transsion seperti
  bigdata, mistouch, dan edge restrain belum ada. Perlu penyesuaian
  6.12: `probe` i2c, `remove` platform mengembalikan void,
  `asm/unaligned.h` -> `linux/unaligned.h`, `strlcpy` -> `strscpy`, dan
  nilai enum `TRAN_DISP_BLANK_AOD_*` di `mtk_disp_notify.h`.

### Gambar uji TWRP untuk port hardware

`twrp-vendor_boot-hwports.img` (release `boottest-20261119`, md5
`cee1e5ad2716dd9ac6a5f0227d946b9e`) memakai set TWRP yang sama dengan
`twrp-vendor_boot-fixed.img`, tetapi tiga modul diganti hasil build kita:

- `adaptive-ts` (core touch, 39 simbol `.text` setelah strip)
- `gt9916_common` (Goodix, 109 simbol)
- `tran_richtap_haptic_hv` (AWINIC, 469 simbol)

Di TWRP yang bisa diuji: touch, haptic, dan tampilan. Flash (v4l2),
VCM `aw8601af`, dan `snd-soc-fs1599` tidak bisa diuji di TWRP karena
butuh userspace kamera/audio; itu menunggu boot ke system.

### Patch urutan match adaptive-ts

`adaptive-ts` dimuat sebelum driver vendor (`gt9916_common`), sedangkan
controller baru didaftarkan di `module_init` driver vendor. Di boot
recovery, work `controller_match_work` bisa berjalan sebelum registrasi
itu sehingga tidak ada controller yang match dan touch mati.

Perbaikan: match diulang sampai 10 kali (200 ms) dan work juga di-queue
dari `tpd_probe`. Gambar uji: `twrp-vendor_boot-hwports2.img`
(md5 `71ec1f89a8266182d1711bdd329c6c49`).

Catatan: `dmesg2.txt` berasal dari boot dengan **adaptive-ts stock**
(terbukti dari string `tran_tp_get_boot_mode`/`flod_main_device_init`
yang hanya ada di `.ko` stock), jadi log itu tidak menunjukkan perilaku
driver kita.

### Bus Goodix salah: i2c vs SPI

`dmesg3.txt` menunjukkan retry `adaptive-ts` bekerja (match sukses pada
percobaan kedua), tetapi `goodix_ts_init` memanggil
`goodix_i2c_bus_init()`. Akibatnya driver SPI tidak pernah didaftarkan,
perangkat `goodix,gt9916` di SPI tidak pernah probe, dan match menunggu
8 detik lalu timeout:

```
[tran_touch-INFO]match_tp_controller 119:start load controller vendor:goodix ic:gt9916
[GTP-INF][goodix_i2c_bus_init:255] Goodix i2c driver init
...
[tran_touch-ERROR]controller_match_work 289:init controller timeout!
```

Pemilihan bus dilakukan saat kompilasi:

```c
#ifdef CONFIG_TOUCHSCREEN_GOODIX_BRL_SPI
        ret = goodix_spi_bus_init();
#else
        ret = goodix_i2c_bus_init();
#endif
```

X6871 memakai SPI, jadi target `gt9916_common` harus diberi
`-DCONFIG_TOUCHSCREEN_GOODIX_BRL_SPI=1`. Setelah rebuild,
`goodix_ts_init` memanggil `goodix_spi_bus_init` (diverifikasi di
disassembly `.ko` dalam image).

Gambar uji: `twrp-vendor_boot-hwports3.img`
(md5 `d7cb32982f3dde01a5cc9d02c5269f07`).

## 20. Modul software: perf_common_v dan mtk-vcodec-sys-api

Dua modul vendor kecil sudah diganti versi sumber dan dibangun dengan
perintah build yang sama.

### perf_common_v

Modul stock hanya memasang fungsi format ke variabel hook yang
diekspor `mtk_perf_common`:

```c
format_sbin_data_hook = format_sbin_data;
```

`format_sbin_data()` direkonstruksi dari disassembly stock (0xdc byte):
menulis `ARRAY[`, lalu tiap word 32-bit sebagai empat byte hex
(`%02x,%02x,%02x,%02x,` dengan urutan byte 0,2,1,3), dan menimpa koma
terakhir dengan `]`. Fungsi kita 0xd0 byte dengan urutan operasi yang
sama; satu-satunya perbedaan adalah compiler meng-inline
`init_perf_common_hook()` ke `init_module`.

### mtk-vcodec-sys-api

Modul stock memasang tabel 5 pointer (`funcs`, 0x28 byte) lewat
`mtk_vcodec_set_sys_api_funcs(&funcs)`. Hanya slot ke-4
(`offset 0x18`) yang terisi, yaitu `set_task_priority` dari
`vip_engine.ko`; empat slot lain NULL. Reimplementasi kita menghasilkan
layout dan relokasi `.data` yang identik (`R_AARCH64_ABS64` di offset
0x18 ke `set_task_priority`).

Sisi konsumen juga disamakan dengan stock:

- `mtk-vcodec-common` sekarang mengimplementasikan dan mengekspor
  `mtk_vcodec_set_sys_api_funcs()` dan
  `mtk_vcodec_set_task_priority()`. Fallback tanpa hook memakai
  `sched_setscheduler_nocheck`/`set_user_nice` seperti stock.
- `mtk-vcodec-enc` memanggil `mtk_vcodec_set_task_priority()` (bukan
  `set_task_priority` langsung), sehingga dependensi `vip_engine`
  berpindah dari encoder ke modul sys-api — sama seperti `modules.dep`
  stock.

Verifikasi: `mtk-vcodec-enc.ko` hanya mengimpor
`mtk_vcodec_set_task_priority`; `mtk-vcodec-common.ko` mengekspor kedua
simbol baru; `mtk-vcodec-sys-api.ko` mengimpor
`mtk_vcodec_set_sys_api_funcs` dan `set_task_priority`, dengan
`depends=mtk-vcodec-common,vip_engine`.

## 21. Export ABI vendor untuk modul software stock

Tiga export yang membuat modul software stock bisa dimuat di atas modul
sumber kita sudah dilengkapi. Semua diverifikasi dengan membandingkan
simbol dan disassembly terhadap `.ko` stock.

### `g_trans_sched_interface` (scheduler)

Stock `scheduler.ko` mengekspor variabel `.bss` 0x110 byte; `trans_sched.ko`
mengisinya dengan 34 pointer fungsi saat init. Layout diambil dari
instruksi `stp` di `init_module` stock:

| offset | isi |
|---|---|
| 0x00, 0x08 | `android_rvh_enqueue_task_hook`, `..._dequeue_...` |
| 0x10, 0x18, 0x20, 0x28, 0x30 | fork, build_sched_domains, tick, replace_next_task_fair, check_preempt_wakeup |
| 0x38..0xa0 | hook binder, mutex, rwsem, free_task, rename, switch prev/next |
| 0xa8 | `tran_is_ux_task` (dipakai `tran_zram`/`priority_allocate`) |
| 0xb0, 0xb8 | `trans_should_honor_sync`, `balance_on_wakeup_ux` |
| 0xc0, 0xc8 | `trans_select_task_rq_rt`, `filterout_on_wakeup_rt` |
| 0xd0, 0xd8 | `android_rvh_find_lowest_rq_hook`, `adjust_rt_lowest_mask` |
| 0xe0, 0xe8 | `__trans_tick_balance`, `__trans_newidle_balance` |
| 0xf0..0x108 | `xmu_schedule`, `xmu_tick_entry`, `xmu_cpufreq_limit`, `xmu_is_runnable_boost_enabled` |

`scheduler.ko` kita sekarang punya `g_trans_sched_interface` berukuran
0x110 byte dan mengekspornya dengan nama yang sama. Artinya
`priority_allocate` (hanya butuh slot 0xa8), `tran_zram`, dan
`trans_sched` bisa dimuat tanpa `Unknown symbol`.

Catatan: scheduler kita baru memanggil slot 0x00/0x08 (enqueue/dequeue)
dan 0xb0 (`should_honor_sync`). Type id kCFI hasil build
(`0x6fc3696d` dan `0xdb9fd229`) sama dengan call-site stock, jadi
signature-nya cocok. Slot 0xb8/0xc0/0xc8/0xd0/0xd8/0xe8 (penempatan
task RT, newidle balance, EAS UX balance) belum disambungkan;
`trans_sched` tetap mengisi tabel dan mendaftarkan tracepoint-nya
sendiri, tetapi keputusan yang lewat scheduler belum aktif.

### Modul yang bisa dipangkas: `tran_audio_typec`

`tran_audio_typec.ko` hanya mendukung `mediatek,fsa4480-i2c`,
`mediatek,was4783-audioswitch`, dan `mediatek,hl1280-audioswitch`.
Tidak satu pun ada di DT X6871 (`base.dts`/`frag0.dts`); audio switch
board memakai `transsion,sliptswitch-gpio-audioswitch` (modul
`splitswitch-gpio`). Jadi modul ini tidak perlu diport untuk X6871.

### `engine_cooler_trigger_duration` (mtk_game)

Stock hanya mengembalikan `ec_duration * 1000`, dengan `ec_duration`
adalah module parameter bernilai 2000. Kita mengganti nama parameter
`yield_duration` menjadi `ec_duration` (agar sysfs sama dengan stock) dan
mengekspor `engine_cooler_trigger_duration()`. Disassembly kita identik:
`adrp/ldr/mul/ret`, ukuran 0x14 byte seperti stock.

### `dma_heap_emem_printk` (mtk_heap_debug)

Dipakai `tran_mm_collect.ko`. Rekonstruksi memakai helper yang sudah ada
(`get_dma_heap_buffer_total(NULL)` dan `get_dma_heap_pool_total()`):

```c
void dma_heap_emem_printk(long emem_kb)
{
        long buffer_kb = get_dma_heap_buffer_total(NULL) / 1024;
        long pool_kb = get_dma_heap_pool_total() / 1024;

        pr_info("[TranMemoryInfo] %s: dmabuf buffer total: %ld KB, page pool total: %ld KB, threshold : %ld kB.\n",
                __func__, buffer_kb, pool_kb, emem_kb);

        if (buffer_kb > emem_kb)
                dma_heap_default_show(NULL, NULL, 524);
}
```

Hasil kompilasi sama persis dengan stock: ukuran 0x150 byte dan urutan
instruksi identik (termasuk pemanggilan `dma_heap_total_cb` lewat
`kset_dma_buf_get_each`, penjumlahan page pool per heap, dan
`dma_heap_default_show` dengan flag 524).

Status: `perf_common_v` + `mtk-vcodec-sys-api` selesai; tiga export di
atas menutup celah `Unknown symbol` untuk modul software stock yang
tersisa selain keluarga Tranlog/Aegis.

## 22. Validasi simbol: seluruh modul software stock bisa dimuat

Setelah export `g_trans_sched_interface`, `engine_cooler_trigger_duration`,
dan `dma_heap_emem_printk`, dilakukan pengecekan closure: setiap simbol
yang di-import 14 modul software yang masih stock harus ada di salah
satu dari:

- `vmlinux.symvers` hasil build kernel kita,
- export 263 modul hasil build kita,
- export modul stock yang memang tetap dipakai (`transsion_tranlog`,
  `thd`, `tran_zram`, dan modul vendor_boot seperti
  `tran-ufshcd-core`).

Hasil: **tidak ada lagi `Unknown symbol`**. Satu-satunya yang sempat
menggantung adalah `tran_low_latency_sched_interface` untuk
`trans_sched`; simbol itu diekspor `tran-ufshcd-core.ko` di vendor_boot
(bukan `low_latency_sched.ko` — modul itu justru yang meng-import-nya).

Rantai dependensi yang tersisa:

| modul stock | butuh |
|---|---|
| `priority_allocate` | `g_trans_sched_interface` (kita) |
| `tran_zram` | `g_trans_sched_interface` (kita) + tranlog |
| `trans_sched` | `g_trans_sched_interface` (kita) + `tran_low_latency_sched_interface` (tran-ufshcd-core) |
| `tran_mm_collect` | tranlog + `zram_emem_printk` (tran_zram) |
| `tran_health_sched`, `tran_key_bigdata`, `thd` | tranlog / `startAegisK` (thd) |
| `pages_prefilter`, `tran_perf_util`, `tc_trancare` | tranlog |
| `game` | `engine_cooler_trigger_duration` (kita) |
| `fpsgo`, `task_turbo_v` | mtk_fpsgo_v8 / vip_engine (kita) |

Artinya sisi simbol sudah selesai; yang tersisa adalah perilaku
(hook scheduler yang belum disambungkan) dan penggantian sumber untuk
modul Tranlog/Aegis yang tidak punya donor.

## 23. TWRP 100% modul dari source (tanpa stock)

Sesuai keputusan baru: tidak ada modul stock yang dimuat. Set TWRP
dibangun ulang hanya dari hasil build kita.

### Yang dibuang (17 modul stock)

Storage Transsion: `tran-ufshcd-core`, `tran-ufshcd-pltfrm`,
`tran_scsi_mod`, `tran_sd_mod`, `tran_block`, `tran_mmc_block`,
`tran_rhi`, `tran-proc-bootdevice-mod`.
Layanan/perf Transsion: `low_latency_sched`, `sd_tray`, `tkv_recovery`,
`thd`, `transsion_tranlog`, `tran_key_bigdata`, `tc_trancare`.
Panel: `rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_cl8` (compatible-nya
`...,cl8`, bukan DT X6871).
MMC: `mtk-mmc-mod` diganti `mtk-mmc.ko` hasil build kita.

### Storage sekarang jalur MediaTek

`dmesg3.txt` membuktikan UFS sudah hidup sebelum modul Transsion dimuat:

```
[2.2218] ufs_mediatek_mod: Loading ...
[2.2279] scsi host0: ufshcd
[2.2834] sd 0:0:0:2: [sdc] 62480384 4096-byte logical blocks (256 GB)
[2.3294] sd 0:0:0:2: [sdc] Attached SCSI disk
[2.3398] init: Loading module /lib/modules/tran-ufshcd-core.ko
```

Jadi `ufshcd` core, SCSI, sd, dan mmc_block sudah built-in di kernel
kita; yang diperlukan hanya `ufs-mediatek-mod.ko` (MediaTek) dan
`mtk-mmc.ko` (MediaTek, tanpa dependensi `sd_tray`). Modul Transsion
datang belakangan dan redundan.

Panel: sumber kita `drivers/gpu/drm/panel/panel-rm69220-vdo-x6871.c`
punya alias `rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871` yang persis
sama dengan DT (`frag0.dts`), jadi panel stock tidak dipakai.

### Hasil

- Set: **222 modul**, semuanya ada di staging hasil build kita
  (`not-from-staging: []`).
- `modules.load`: 163 entri; `modules.load.recovery`: 214 entri.
  Semua file ada, tidak ada nama modul stock.
- `modules.dep` digenerate `depmod` lalu di-flatten ke
  `/lib/modules/<nama>.ko`; tidak ada unresolved symbol (hanya
  `mtk_drm_gateic_set_backlight` yang weak).
- `llvm-strip --strip-debug` sebelum packing (total 28 MB).

Fitur yang hilang karena sumbernya tidak ada: logging/Aegis Transsion
(`thd`, `transsion_tranlog`, `tran_key_bigdata`, `tc_trancare`), storage
latency logging, `sd_tray`/`tkv_recovery`/`tran-proc-bootdevice`, dan
tuning performa Transsion. Tidak ada dependensi kernel TWRP ke
modul-modul itu.

Gambar uji: `twrp-vendor_boot-allsrc.img`
(md5 `caef8ac1591999d625ecfe48f9f1cb13`), 222 modul, sudah diverifikasi
isi ramdisk-nya.

## 24. Set dlkm 100% source (final)

Selain vendor_boot TWRP, set modul untuk `vendor_dlkm` + `odm_dlkm`
disiapkan di `/serverhive1/ramabondanp/tmp/dlkm-src`. Isinya **269 modul,
semuanya dari staging build kita**.

Modul stock yang dikeluarkan (25):

- 10 hardware yang tidak ada source/DT X6871 (sengaja tidak diport):
  `ak7316`, `aw36515`, `dw9800k`, `dw9784ois`, `focaltech_ft3683g`,
  `chipsemi_chsc5xxx_old`, `snd-soc-fs1894`, `snd-soc-aw87xxx`,
  `snd-soc-oca72xxx`, `elliptic-ultrasound`.
- 15 software tanpa source: `fpsgo`, `game`, `pages_prefilter`,
  `priority_allocate`, `task_turbo_v`, `tc_trancare`, `thd`,
  `transsion_tranlog`, `tran_audio_typec` (tidak ada DT),
  `tran_health_sched`, `tran_key_bigdata`, `tran_mm_collect`,
  `tran_perf_util`, `trans_sched`, `tran_zram`.

Penggantian dari source:

- `tran_zram` → `zsmalloc.ko` + `zram.ko` (driver zram kernel, fitur
  Memfusion/tranlog hilang).
- `task_turbo_v` → `task_turbo.ko` (base MTK, mengekspor
  `launch_turbo_enable`/`tt_vip_enable_p` yang dibutuhkan `vip_engine`).
- Tambahan modul GKI/source yang sebelumnya disediakan stock:
  `rfkill.ko`, `bluetooth.ko` (untuk `bt_drv_6895`), `libarc4.ko`
  (untuk `mac80211`), dan `zsmalloc.ko`.

Load list hasil pruning:

- `vendor_dlkm`: 194 entri; `rfkill`/`bluetooth` sebelum `cfg80211`,
  `libarc4` sebelum `mac80211`, `task_turbo` sebelum `vip_engine`.
- `odm_dlkm`: 57 entri; `zsmalloc` + `zram` menggantikan `tran_zram`.

Validasi closure simbol (kernel `vmlinux.symvers` + 222 modul
vendor_boot + 269 modul dlkm): **0 unresolved symbol**. Semua file di
set dlkm berasal dari staging (`not-from-staging: []`).

Partisi dlkm sudah di-repack dari set ini; lihat §45 untuk image,
md5, dan cara flash. Boot system belum diuji.

## 25. Storage fork Transsion: hasil RE dan dua modul yang layak di-port

Fork storage Transsion di stock `.ko` berasal dari:

```text
kernel_device_modules-6.12/fs/atomic_storage/
  tran_block/ tran_scsi/ tran_mmc/ tran_ufs/
kernel_device_modules-6.12/fs/tran_rhi/
kernel_device_modules-6.12/drivers/bootdevice/bootdevice/
```

Ini bukan patch kecil. `tran_block` 1.237 fungsi/300 ekspor (fork block
layer penuh), `tran_scsi_mod` 313 fungsi/156 ekspor, `tran_sd_mod` fork
`sd`, `tran_mmc_block` fork `mmc_block`, dan `tran-ufshcd-core/pltfrm`
fork UFS core. Semua memakai prefix `tran_*` dan hook `__tran_*_hook`.

### Kenapa tidak dipakai di X6871

Kernel stock sudah built-in:

```text
CONFIG_SCSI_MOD=y
CONFIG_BLK_DEV_SD=y
CONFIG_SCSI_UFSHCD=y
CONFIG_SCSI_UFSHCD_PLATFORM=y
CONFIG_MMC_BLOCK=y
```

`ufs-mediatek-mod.ko` bind controller sebelum modul Tran dimuat:

```text
2.2279 scsi host0: ufshcd
2.3294 sd 0:0:0:2: [sdc] Attached SCSI disk
2.3341 tran_sd_mod: /odm/blkio not exit, donot enable blkio
2.3341 tran_sd_mod: block io disable, not ctled by cloudengine
2.3459 tran-ufshcd-core loaded
2.3596 tran_block loaded
```

Tidak ada `scsi host`/disk baru setelah `tran-*` dimuat. Node DT
`/odm/blkio` juga tidak ada di X6871, jadi BLK-IO/atomic storage,
`low_latency_sched`, dan hook Tran tidak aktif. Fork ini **bukan jalur
storage X6871**; jangan di-port kecuali ada bukti boot system stock
memakainya.

### Dua modul standalone yang layak dipertimbangkan

1. **`tran-proc-bootdevice-mod.ko`** — membuat `/proc/bootdevice` dan
   `/proc/tran_bootdevice`. Modul ini tetap jalan dengan UFS MTK/GKI
   karena hanya memanggil `ufshcd_query_attr_retry`,
   `ufshcd_query_descriptor_retry`, `ufshcd_query_flag`, dan
   `ufshcd_read_desc_param`. Isi node: `name`, `type`, `manfid`,
   `oemid`, `serial`, `rev`, `prv`, `fwrev`, `hwrev`, `size`, `cid`,
   `csd`, `ext_csd`, `ocr`, `erase_size`, `enhanced_area_offset/size`,
   `life_time_est`, `pre_eol_info`, `ffu_support`, `product_name`,
   `bootmode`, `boottype`. Dipakai tool factory/diagnostik Transsion.
   Implementasi ulang kecil; tidak perlu fork storage.

2. **`tran_rhi.ko`** — membuat `/proc/health_info`,
   `/proc/healthinfo_upload`, dan `/proc/healthinfo_upload_new`. Field
   `health_info.FlashID`, `health_info.FwRev`, `health_info.nand_uid`;
   ekspor `get_rom_life_time`, `get_total_gc_count`, dan
   `get_rom_avg_erase_tlc`. Ini procfs mandiri; datanya diisi userspace
   Transsion. Prioritas rendah, tapi mudah dibuat ulang kalau app health
   membutuhkannya.

Yang **tidak** perlu di-port: `tran_block`, `tran_scsi_mod`,
`tran_sd_mod`, `tran_mmc_block`, `tran-ufshcd-core`,
`tran-ufshcd-pltfrm`, dan `low_latency_sched`. Semuanya dorman di X6871
dan ukurannya besar (`tran_block` 1.1 MB, `tran-ufshcd-core` 563 KB,
`tran_scsi_mod` 434 KB).

Bukti: stock `.ko` di
`/serverhive1/ramabondanp/tmp/twrp-set2/lib/modules/6.12.38-android16-5-g2c4fd33ae6d8-4k/`,
`/serverhive1/ramabondanp/dmesg3.txt`, dan config kernel stock
`/serverhive1/ramabondanp/tmp/bootRE_ikconfig`.

## 26. Audit stack kamera: driver sensor tidak ada di source mana pun

Ringkas: **kamera satu-satunya stack yang source-nya benar-benar tidak
lengkap.** Beda dengan storage (§25, fork dorman) atau charging
(bloat modul tapi kode identik), di kamera kita tidak punya driver
sensor X6871 sama sekali. Tanpa port, kamera **mati total**, bukan
sekadar kehilangan fitur.

### Metode

Perbandingan lapis tiga, semua modul kandidat stock (`vendor_dlkm` +
`odm_dlkm`) vs hasil build kita:

1. hash per section yang dimuat: `.text`, `.init.text`, `.exit.text`,
   `.rodata*`, `.data`, `.bss`, `__versions`, `.modinfo`,
   `.gnu.linkonce.this_module`;
2. tabel simbol (nama, section, offset, size, tipe, binding);
3. relokasi section kode + `modinfo` (`name`/`depends`/`vermagic`).

Hasil untuk 221 modul yang ada di kedua sisi: **identik semua**, bukan
hanya `.text`. Disassembly `.text`/`.init.text`/`.exit.text` juga sama
karakter-per-karakter (beda hanya baris header path `objdump`). Contoh
level fungsi: `mediatek_drm_v1` 3411/3411 fungsi, `mtk-mml` 893/893,
`mtu3` 293/293, `tcpc_class` 707/707 — signature simbol (alamat+size+nama)
sama.

Artinya tree kita = revisi source yang sama dengan vendor. Kalau ada
patch Transsion, ia **wajib** muncul sebagai delta section/simbol. Dan
memang muncul, semuanya terkonsentrasi di kamera.

Skrip pembandingnya ada di repo: `tools/stock-vs-src.py`.

```sh
./tools/stock-vs-src.py <dir-stock> <dir-src> [-v] [--vermagic]
```

### Batas metode: set vendor_boot vs set dlkm

221 modul identik di atas berasal dari set **vendor_boot** stock, yang
`vermagic`-nya persis sama dengan build kita:

```text
stock vendor_boot : 6.12.38-android16-5-g2c4fd33ae6d8-4k
build kita        : 6.12.38-android16-5-g2c4fd33ae6d8-4k
stock dlkm        : 6.12.38-android16-5-gcc51d883045d-4k   (beda build)
```

Jadi untuk `vendor_dlkm`/`odm_dlkm`, perbandingan byte **tidak**
apple-to-apple:

```text
vendor_dlkm : 208 modul ada di kedua sisi -> 97 identik, 93 beda
odm_dlkm    :  55 modul ada di kedua sisi ->  3 identik, 52 beda
```

Sebagian besar perbedaan itu artefak build (vermagic/localversion,
`__versions` CRC, `depends` hasil konfigurasi), bukan patch vendor. Karena
itu penilaian delta kamera di bawah memakai **nama fungsi, ekspor, dan
string sensor**, ditambah disassembly titik tertentu — bukan hash
`.text`. Untuk modul dlkm, hash `.text` hanya dipakai kalau hasilnya
"sama" (bukti kuat), bukan sebaliknya.

### Modul kamera yang identik (aman)

```text
camera_af_media            clk-mt6895-cam
clk-mt6895-ccu             imgsensor-glue
mtk-cam-plat-mt6895        mtk-cam-plat-util
mtk_hcp_isp71              mtk_imgsys_isp71
mtk_imgsys_v4l2            mtk-vmm-isp71-regulator
```

`camera_dpe_isp70` dan `mtk_imgsys_cmdq_isp71` juga identik di
`.text`/`.rodata`/`.data`; yang beda hanya `__versions` (CRC simbol kernel
karena stock dlkm dibangun di build kernel lain).

### Modul kamera yang BEDA

| Modul | Delta terukur |
|---|---|
| `imgsensor` | stock 12 sensor vs kita 26 sensor; **0 sensor X6871 di sisi kita** |
| `camera_eeprom_v4l2` | +46 fungsi kalibrasi per-sensor Transsion; 119 fungsi sama, 9 beda ukuran |
| `mtk-cam-isp` | 750 vs 721 fungsi; 32 fungsi stock-only, 3 source-only; 961 fungsi sama, **158 beda ukuran** |
| `flashlight` | 60 vs 54 fungsi; 11 stock-only, 5 source-only; 49 sama, 15 beda ukuran |
| `aw36515_v4l2` | 30 vs 26 fungsi (prefix `_v4l2_`), +`get_hw_fault` |
| `ocp81375_v4l2` | 31 vs 27 fungsi (prefix `_v4l2_`) |
| `sgm37864_v4l2` | 31 vs 25 fungsi (prefix `_v4l2_`), +`get_hw_fault`, +`resume`/`suspend` |
| `mtk_ccuv` | 47 fungsi, hanya `mtk_ccu_probe` beda 16 byte (kita **lebih baru**: ada `mtk_ccu_deallocate_mem` di probe) |
| `aw8601af` | 7 fungsi sama nama; `open`/`close`/`probe`/`remove` beda ukuran 8–84 byte (implementasi kita sendiri, bukan port donor) |

### Blocker utama: driver sensor

DT X6871 (`frag0.dts` fragment@58–61):

```text
sensor0@10  s5khm6sx_mipi_raw      + camera_eeprom0@50 + camera_af_main aw8601af
sensor1@4A  gc32e1_mipi_raw        + camera_eeprom1@51
sensor2@10  gc02m3_mipi_raw
sensor3@10  gc02m3macro_mipi_raw
```

Keempatnya tidak ada di tree kita:

```text
$ grep -r s5khm6sx w1vo/kernel_device_modules-6.12   -> 0 hasil
$ ls w1vo/vendor/mediatek/kernel_modules/mtkcam/imgsensor/src-v4l2/common
  gc13a2 imx214 imx258 imx334 imx334sub imx481 imx499 imx519 imx576
  imx586 imx598lite imx598 imx709 imx758lite imx758 imx766dual imx766
  imx866 imx966 imx989lite imx989 ov48b ov64b s5k3m5sx s5k3p9sp s5khp3sp
```

Framework yang dipakai stock **memang `src-v4l2`** dari
`vendor/mediatek/kernel_modules/mtkcam/imgsensor` (bukti: `imgsensor-glue`
berisi path `.../imgsensor/src-v4l2/imgsensor-glue/imgsensor-glue.c`, dan
`imgsensor.ko` `depends=aee_aed,mtk_ccuv,imgsensor-glue` di kedua sisi).
Jadi target port jelas: `src-v4l2/common/`.

### Yang tersedia di donor 6.1 (port realistis, bukan RE)

Lokasi sama persis dengan tree 6.12 kita:

```text
/serverhive1/ramabondanp/tmp/mt6897/vendor/mediatek/kernel_modules/mtkcam/
  imgsensor/src-v4l2/common/s5khm6sx_mipi_raw/
  imgsensor/src-v4l2/common/gc32e1_mipi_raw/
  imgsensor/src-v4l2/common/gc02m3macro_mipi_raw/
```

(ada juga di `/serverhive1/ramabondanp/tmp/ts61-full/...`)

| Sensor | Isi donor | Ukuran |
|---|---|---|
| `s5khm6sx_mipi_raw` | `*mipiraw_Sensor.c/.h`, `s5khm6sx_Sensor_setting.h`, `s5khm6sx_ana_gain_table.h`, `Makefile` | 27.965 baris (25.328 baris tabel setting) |
| `gc32e1_mipi_raw` | set sama | 5.766 baris |
| `gc02m3macro_mipi_raw` | set sama | 2.430 baris |
| `gc02m3_mipi_raw` | **tidak ada** — harus diturunkan dari versi macro (chip GC02M3 sama) | — |

Tabel register lengkap ada di donor, jadi **tidak perlu bongkar `.rodata`
stock**. Driver memakai API standar `subdrv_*` yang sudah ada di header
6.12 kita (`subdrv_i2c_wr_regs` di 11 file, `subdrv_i2c_rd_u8` di 25
file). Diff header adaptor 6.1 → 6.12 kecil:

```text
adaptor-ctrls.h  identik
adaptor.h        5 baris beda
adaptor-def.h    8 baris beda
adaptor-subdrv.h 20 baris beda
```

Catatan: donor 6.1 punya folder `src-v4l2/camera_project/tran_*` berisi
override per-proyek (mis. `tran_x6873/s5khm6sx_mipi_raw`). Tree 6.12 kita
`camera_project` kosong. Kalau ada nilai tuning proyek X6871, ia tidak
dipublikasikan; mulai dari driver `common` dulu.

### Yang harus RE atau diterima hilang

1. **`camera_eeprom_v4l2` — kalibrasi OTP per sensor.** Fungsi stock yang
   tidak ada di sisi kita:

   ```text
   do_2a_gain_{gc32e1,s5khm6sx,hi5022q,imx890,s5kjn1sub,s5kjn1teleaiisp,...}
   do_pdaf_*          do_single_lsc_*        do_preisp_lsc_*
   do_OISread_OTPdata_{hm6sx,imx890,s5kjn1teleaiisp}
   do_readMultiCam_data / imx890_do_readMultiCam_data / s5khm6sx_do_readMultiCam_data
   iWriteData_CAM_CAL / write_data / write_data_region / checkSumPreIspLSC
   get_cal_OIS_data / get_cal_preisp_data
   ```

   Source modul ini = `mtkcam/cam_cal/src_v4l2/common/v2/eeprom_driver.c`
   + `custom/cam_cal_config.c`. Di tree 6.12 kita, `cam_cal` custom hanya
   punya layout 30 sensor lama (imx586, imx766, s5k3p9sp, s5kjn1, …);
   donor 6.1 pun tidak punya `s5khm6sx`/`gc32e1`/`gc02m3`. Jadi format OTP
   Transsion untuk sensor X6871 **tidak dipublikasikan** — harus RE
   46 fungsi (ada fixed-point) atau terima kamera tanpa kalibrasi.

2. **`mtk-cam-isp` Ext-ISP/fake-sensor.** Delta terbukti murni cabang
   extisp:

   ```text
   stock  mtk_cam_ctx_stream_on -> mtk_cam_is_ext_isp_ext_sensor_signal,
                                   prepare_fake_sensor_vsync
   source mtk_cam_ctx_stream_on -> (tidak ada; hanya mtk_cam_extisp_prepare_meta)
   ```

   Fungsi tambahan stock: `mtk_cam_extisp_cb_register` (diekspor),
   `mtk_cam_extisp_all_sof_coming`, `mtk_cam_event_extisp_camsys_ready`,
   `mtk_cam_extisp_*`, `*_device_buf_*`, `*fake_sensor_vsync*`,
   `mtk_cam_sv_vf_reset`, `mtk_cam_raw_vf_reset`.

   X6871 **tidak memakai** ini: tidak ada node DT `extisp`/`aiisp`, dan
   tidak ada satu pun modul stock lain yang mereferensikan
   `mtk_cam_extisp_cb_register`. Aman dilewati.

3. **`flashlight` core (portable dari donor).** Stock punya sysfs
   `sub_torch_level`, `tele_torch_level`, `sysfs_strobe`, timer thermal;
   tree kita 6.12 hanya `g_sysfs_strobe_level[2]` + `flashlight_pt_*`.
   Donor 6.1 `drivers/misc/mediatek/flashlight/flashlight-core.c` (2.464
   baris) **punya** tambahan itu (`g_sysfs_strobe_level[3]`,
   `sub_torch_level_store/show`, `tele_torch_level_store/show`,
   `sysfs_strobe_store`), jadi tinggal port diff 6.1 → 6.12. Relevan
   karena X6871 punya dua LED: `ocp81375_v4l2@63` (part 0) +
   `sgm37864_v4l2@64` (part 1), keduanya `flashledno = <1>`.

4. **Trio flashlight v4l2.** Tree kita
   `drivers/misc/mediatek/flashlight/v4l2/*.c` praktis sama dengan donor
   6.1 (diff 3 baris), tapi kalah dari stock: penamaan fungsi di stock
   diberi infix `_v4l2_` (mis. `sgm37864_v4l2_probe` vs `sgm37864_probe`)
   dan ada `get_hw_fault`, `thermal_timer_func`, `resume`/`suspend`.
   `thermal_timer_func` + `get_hw_fault` tidak ada di donor → RE kecil
   (puluhan byte per fungsi). `resume`/`suspend` kemungkinan hanya
   perbedaan config PM saat build, perlu dicek saat port.

   **Sudah diperbaiki (2026-11-20):** DT X6871 memakai compatible
   `mediatek,ocp81375_v4l2` dan `mediatek,sgm37864_v4l2`, sedangkan
   source kita hanya punya `mediatek,ocp81375` / `mediatek,sgm37864`
   sehingga **driver tidak bind**. Entri `_v4l2` ditambahkan di
   `*_of_table` (ketiganya, termasuk `aw36515`), build ulang sudah
   diverifikasi: alias modul sekarang memuat kedua bentuk. Detail di
   `DEVICES.md`.

5. **`aw8601af` (VCM AF cam0) — sudah ditulis sendiri.** Nama fungsi sama
   (7 fungsi), tapi `open`/`close`/`probe`/`remove` beda 8–84 byte dari
   stock; sequencing power/clock kita berbeda. Perlu diuji AF-nya saat
   boot system pertama.

### Dampak kalau tidak dikerjakan

- `imgsensor` tanpa 4 driver itu → tidak bisa probe sensor → HAL tidak
  dapat `/dev/video*` → **kamera mati total** di system.
- Eeprom tanpa kalibrasi → kamera hidup tapi tanpa LSC/PDAF/OIS/AWB
  calibration (shading, tint, AF kurang presisi).
- TWRP **tidak terpengaruh** (kamera tidak dipakai di recovery).

### Rencana port (urutan yang disarankan)

1. Copy 3 direktori sensor donor 6.1 → `src-v4l2/common/`, adaptasi
   header adaptor, daftarkan di Kconfig/Makefile/BUILD.bazel, build
   `imgsensor.ko`, verifikasi `SENSOR_DRVNAME_*` muncul.
2. Turunkan `gc02m3_mipi_raw` dari `gc02m3macro`, verifikasi tabel
   register terhadap stock `imgsensor.ko`.
3. Port diff `flashlight-core.c` 6.1 → 6.12 + tambahan trio v4l2.
4. Putuskan eeprom: RE 46 fungsi, atau rilis tanpa kalibrasi dulu.
5. Skip `mtk-cam-isp` extisp dan `mtk_ccuv` (kita lebih baru).

Baseline pengukuran ulang: pakai `tools/stock-vs-src.py` (lihat §26
bagian metode). Daftar fungsi per modul kamera tersimpan di
`/serverhive1/ramabondanp/cmp-out/` (`f-<modul>-stock.txt` vs
`f-<modul>-src.txt`).

## 27. Layar mati di TWRP: `tran_ldo` tidak dimuat (bukan bug build)

Gejala: TWRP boot, adb hidup, tapi layar tidak pernah menyala
(`dmesg4.txt`).

```text
mtk-dsi 14017000.dsi: Waiting for bridge or panel driver   (68x, sampai 17,9 s)
mediatek-drm 14000000.dispsys_config: Adding component ... (53 komponen)
mediatek-drm ... : bound ...                               (0 -- tidak pernah)
```

Panel tidak pernah diprobe sama sekali:

```text
dmesg3 (stock, layar hidup) : lcm_probe+ / device node name:panel1 / lcm_probe-
dmesg4 (build kita)         : (tidak ada)
```

`lcm_probe()` mencetak `pr_info` paling awal, jadi kalau tidak ada cetakan
sama sekali berarti probe tidak dipanggil, bukan gagal di regulator.

### Sebabnya: supplier regulator tidak pernah ada

DT panel (`frag0.dts` frag@19):

```text
dvdd-supply = <0x2a>;   /* 0x2a = TRANLDO26 (frag@5/tran_ldo@28) */
vci-supply  = <...>;    /* dari base DT (mt6368) */
```

`TRANLDO16/26/36/46` hanya didaftarkan oleh `tran,tran_ldo`:

```text
/tmp/x6871/frag0.dts:382  tran_ldo@28 { compatible = "tran,tran_ldo"; ... }
```

`tran_ldo.ko` ada di dalam image (dan **byte-identik** dengan stock,
md5 `e84f8cb8f6`) tetapi **tidak ada di `modules.load` maupun
`modules.load.recovery`**. Akibatnya device panel punya supplier yang
tidak pernah ready; `device_links_check_suppliers()` mengembalikan
`-EPROBE_DEFER` **sebelum** `lcm_probe()` dipanggil, jadi tidak ada log
apa pun dan DSI terus menunggu panel.

Bukti terkuat: d3 (stock) memuat `tran_ldo.ko` di 2,373 s tepat sebelum
`panel-rm69220...ko` (2,406 s), dan `lcm_probe+` muncul 2,412 s.

### Perbaikan

Tambahkan `tran_ldo.ko` sebelum `mtk_panel_ext.ko` di kedua daftar
(mengikuti urutan stock: 147/148 -> 150/151):

```text
modules.load          : 163 -> 164 -> 165
modules.load.recovery : 214 -> 215 -> 216
```

### Audit yang harus diulang

Bandingkan isi image dengan daftar muat; jangan hanya percaya daftar.

```sh
comm -23 <(ls $SET/*.ko | xargs -n1 basename | sort) \
         <(sort -u $SET/modules.load.recovery)
```

Hasil audit saat itu: 7 modul ada tapi tidak dimuat —
`tran_ldo` (wajib, lihat di atas), `mtk-dvfsrc-devfreq`,
`mtk-dvfsrc-helper`, `mtk_slbc`, `slbc_ipi`, `slbc_mt6895`,
`slbc_trace` (stock juga tidak memuatnya di recovery).

## 28. Vibrator mati di recovery: guard boot-mode di driver haptic

Gejala: TWRP boot, layar hidup, tapi getaran tidak ada. Di `dmesg5.txt`
hanya terlihat:

```text
<haptic_hv>aw_i2c_init: aw_haptic driver version v1.5.0
[haptic_hv][4327]tran_get_boot_mode: tran_tp_get_boot_mode is 2
init: Loaded kernel module /lib/modules/tran_richtap_haptic_hv.ko
```

`aw_i2c_probe()` mencetak `pr_info("<%s>%s: enter")` paling awal, jadi
tidak adanya baris itu berarti probe **tidak pernah dipanggil**.

### Bukti RE: stock pun sama

Disassembly `init_module` pada `tran_richtap_haptic_hv.ko` **stock**:

```text
bl  tran_get_boot_mode
cmp w0, #0x9
mov w8, #1
mov w9, #0x304        ; bit 2, 8, 9 -> recovery (2), KPOC (8/9)
lsl w8, w8, w0
tst w8, w9
b.eq <i2c_register_driver>
mov w19, wzr          ; return 0 tanpa registrasi
```

Log recovery menunjukkan `tran_tp_get_boot_mode is 2` -> stock juga
melewati registrasi. Ini bukan efek samping port kita.

TWRP sendiri memang mengharapkan node `vibrator_single`:

```text
libtwrpminui.so : /sys/class/leds/vibrator_single/duration
                  /sys/class/leds/vibrator/duration          (fallback)
                  /sys/class/timed_output/vibrator/enable    (fallback)
init.recovery.mt6895.rc: write /sys/class/leds/vibrator_single/ram_update 1
```

Karena `vibrator_single` tidak ada, TWRP jatuh ke `/sys/class/leds/vibrator`
milik `regulator-vibrator` (stub PMIC), sehingga tidak ada getaran.

Device tree TWRP untuk X6871 sudah punya patch biner untuk ini:
`tools/patch_haptic_ko.py` (ubah immediate `0x304` -> `0x300`, jadi mode 2
tidak lagi di-skip).

### Perbaikan di source

Guard yang sama ada di `haptic_hv.c`:

```c
/* sebelum */
if (boot_mode == KERNEL_POWER_OFF_CHARGING_BOOT ||
    boot_mode == LOW_POWER_OFF_CHARGING_BOOT ||
    boot_mode == RECOVERY_BOOT)
        return 0;

/* sesudah */
if (boot_mode == KERNEL_POWER_OFF_CHARGING_BOOT ||
    boot_mode == LOW_POWER_OFF_CHARGING_BOOT)
        return 0;
```

Hasil kompilasi (setara patch biner di atas):

```text
and  w9, w0, #0xfffffffe      ; boot_mode & ~1
cmp  w9, #0x8                 ; hanya 8/9 (KPOC) yang skip
b.ne <i2c_register_driver>
```

Commit kernel `e6fe27871d2f`. Tidak perlu perubahan lain: nama LED tetap
`vibrator_single` (KERNEL_OVER_5_10) sehingga tidak bentrok dengan
`regulator-vibrator`.

### Masih terbuka: layar tidak menyala setelah screen off

Bukan modul: seluruh modul jalur display (panel, `mediatek_drm_v1`,
`mtk_panel_ext`, `pwm-mtk-disp`, `leds-mtk*`, `cmdq*`, `mtk-smi`,
`mtk_iommu`, `mtk-mminfra*`) **byte-identik** dengan stock dan urutan
muatnya sama. Di `dmesg5.txt` terlihat jalur doze MTK:

```text
[DISP][E]mtk_atomic_doze_preparation connector has no crtc
[DISP]mtk_output_dsi_disable, underrun force release:1
[DISP][E][IRQ] DSI0: buffer underrun        (berulang setelah unblank)
```

Perlu uji A/B dengan image berisi set modul stock untuk memastikan apakah
gejala ini juga ada di stock (bukan asumsi).

## 29. Layar tidak menyala setelah screen off: panel driver yang salah

`normal.txt` (boot stock yang normal) membongkar akarnya. Modul panel yang
dipakai boot sehat **bukan** yang kita build:

```text
normal.txt  : /lib/modules/rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.ko
              (ada di /tmp/x6871/vr/root/lib/modules, 279.672 byte)
build kita  : /lib/modules/panel-rm69220-vdo-x6871.ko
              (dari drivers/gpu/drm/panel/panel-rm69220-vdo-x6871.c)
```

Keduanya mengklaim compatible yang sama
(`rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871`), tetapi isinya driver
berbeda. Log-nya pun beda:

```text
normal : [LCM] lcm_probe lcm_doze_backlight:3;5;7;27;
         [LCM]lcm_regulator_power_init start/end
         [LCM] lcm_setbacklight_cmdq level = 2047, mapped_level = 1658
dmesg5 : lcm_probe+ / device node name:panel1 / lcm_probe-
         lcm_setbacklight_cmdq level = 2047, mapped_level = 1757 dimming_status = 1
```

Perbandingan simbol:

```text
vendor-only : panel_hbm_set_cmdq_switch, dimming_modify_setting,
              bl_tb0, brightness_mapped_to_alpha_low_light,
              panel_ext_lcm_power_set, iris_parse_is_factory_bootmode, ...
milik kita  : aod_mode_enter_setting, aod_mode_exit_setting, ext_params,
              fhd_default_mode, fhd_mode_120, ...
```

### Penyebab langsung: blok doze tidak pernah dikompilasi

Di tree 6.12, Kconfig `TRANSSION_DOZE_BRIGHTNESS_SUPPORT` **tidak ada**
(di donor 6.1 ada di `mediatek_v2/Kconfig`, di-set `=m` oleh
`tran_custom.config`). Akibatnya semua

```c
#if IS_ENABLED(CONFIG_TRANSSION_DOZE_BRIGHTNESS_SUPPORT)
```

di driver panel ikut mati, termasuk `panel_doze_enable`,
`panel_doze_disable`, `g_lcm_doze_backlight`, dan
`.set_aod_light_mode`. Modul kita sebelum perbaikan tidak punya satu pun
simbol doze itu; modul vendor punya ketiganya.

Tanpa hook doze, transisi layar mati -> nyala yang lewat
`mtk_atomic_doze_preparation/finish` (lihat `dmesg5.txt`) berakhir dengan
panel tetap gelap walau backlight 2047 sudah diset, disertai
`DSI0: buffer underrun` berulang.

### Perbaikan

1. Definisikan macro di driver (tree 6.12 tidak punya Kconfig-nya):

   ```c
   #ifndef CONFIG_TRANSSION_DOZE_BRIGHTNESS_SUPPORT
   #define CONFIG_TRANSSION_DOZE_BRIGHTNESS_SUPPORT 1
   #endif
   ```

2. Pindahkan `struct lcm_doze_backlight` (dan typedef
   `tran_lcm_doze_backlight`) ke atas `g_lcm_doze_backlight`. Blok itu
   belum pernah ikut dikompilasi, jadi urutan deklarasinya rusak.

Setelah rebuild, simbol modul panel kita sama dengan vendor:

```text
panel_doze_enable, panel_doze_disable, g_lcm_doze_backlight
```

Commit kernel `a31d53a3603b`.

### Kalau masih gelap

Langkah berikutnya adalah menyelaraskan sisa callback yang hanya dimiliki
vendor (`panel_hbm_set_cmdq_switch`, `dimming_modify_setting`,
`panel_ext_lcm_power_set`) dan tabel backlight (`mapped_level` vendor 1658
vs kita 1757). Kandidat jangka panjang: port driver
`rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.c` milik vendor (source
tidak dipublikasikan) atau samakan perilakunya dari hasil RE.

## 30. dmesg6: vibrator beres, layar tetap gelap — akarnya beda revisi modul

Vibrator sudah normal (`haptic_hv` probe jalan, `vibrator_single` ada).
Layar masih gelap. Analisis `dmesg6.txt` vs `normal.txt` (boot sehat)
membongkar satu hal besar yang sebelumnya salah diasumsikan.

### Koreksi penting: `tmp/twrp-set2` bukan modul stock ponsel ini

Verifikasi lama ("221/221 identik dengan stock") membandingkan build kita
dengan `tmp/twrp-set2`. Set itu **bukan** isi `vendor_boot.img` ponsel,
melainkan build dari revisi yang sama dengan tree kita:

```text
tmp/x6871/vr/root/lib/modules/mediatek_drm_v1.ko   (vendor_boot asli)
    vermagic 6.12.38-android16-5-gcc51d883045d-4k
    esd_check_switch dicetak di baris :1064
tmp/twrp-set2/.../mediatek_drm_v1.ko               (build revisi kita)
    vermagic 6.12.38-android16-5-g2c4fd33ae6d8-4k
    esd_check_switch dicetak di baris :784  (sama dengan build kita)
```

Perbandingan terhadap vendor_boot ASLI dengan `tools/stock-vs-src.py`:

```text
modul di kedua sisi : 217
identik             : 80
beda                : 137
   contoh: aee_aed, clk-common, cmdq-platform-mt6895, cmdq_helper_inf,
           cqhci, emi, i2c-mt65xx, xhci-mtk-hcd-v2, ufs-mediatek-mod, ...
```

Jadi tree kita = **revisi lain** dari firmware yang dipakai ponsel. Ini
juga sebabnya driver panel berbeda:

```text
vendor_boot asli : rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.ko
build kita       : panel-rm69220-vdo-x6871.ko
```

`rm69220_..._x6871.c` tidak ada di tree kita, di `tmp/ts61-full`, di
`tmp/mt6897`, maupun di branch `alps/android16` (sudah dicek). Ia berasal
dari source Transsion yang tidak dipublikasikan (kelas yang sama dengan
`camera_eeprom_v4l2`).

### Yang terlihat di dmesg6

DTB identik (`ead6a965b0aa`), bootconfig identik, jadi bukan DT.

| Kejadian | dmesg6 (kita) | normal.txt (vendor_boot asli) |
|---|---|---|
| resume layar | lewat jalur idlemgr/low-power: `mtk_crtc_config_default_path`, `mtk_dsi_set_mmclk_by_datarate_V2` (7x) | jalur biasa `drm_panel_prepare` |
| hook power panel | `panel_ext_lcm_power_set` **tidak ada** di modul kita (di-`__maybe_unused`, tidak didaftarkan di `ext_funcs`), 0x dipanggil | 8x dipanggil (`status=0/1 begin/end`) |
| konfigurasi DSC | `bit_per_channel = 10` → `bpc:10`, `num_extra_mux_bits 270`, `slice_bits 302400` | `bpc:8`, `num_extra_mux_bits 246`, `slice_bits 51840` |
| backlight | `mapped_level = 1757` | `mapped_level = 1658` |
| saat layar mati | `mtk_output_dsi_disable, underrun force release:1` (underrun_cnt>0, v-idle aktif) | tidak pernah |
| DSI0 buffer underrun | 6x (mulai tepat saat unblank) | 0x |

Catatan: `_mtk_dsi_host_transfer` 0x di dmesg6 BUKAN bukti tidak ada DCS —
string log itu hanya ada di binary vendor, revisi kita tidak mencetaknya.

Artinya: di stack kita, saat bangun layar panel tidak melewati
power-up/init ulang (rail `vddi/dvdd/vci` tidak disentuh karena hook-nya
tidak terdaftar), sementara DDP tetap men-scan ke DSI yang baru
di-start ulang → `DSI0: buffer underrun`, backlight 2047, gambar hitam.

### Dua image diagnostik (bukan kandidat final)

Dibuat untuk memastikan siapa yang salah: panel atau DRM core.

```text
twrp-vendor_boot-diag-panelvendor.img
  md5 bfa4f21986abda1dfa4e8cf01080f024
  isi: 222 modul (semua source) tetapi panel diganti
       rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.ko (vendor)

twrp-vendor_boot-diag-drmvendor.img
  md5 1b5dd4e5e0b12c6a275e6efb62dc20fe
  isi: seperti di atas + mediatek_drm_v1.ko dari vendor_boot asli
```

Cara baca hasilnya:

```text
panelvendor OK      -> DRM core kita kompatibel; yang perlu diperbaiki
                       hanya konfigurasi driver panel kita (DSC 8bpc,
                       hook power_set, tabel backlight 1658)
panelvendor gelap   -> bukan panel; lanjut drmvendor
drmvendor OK        -> DRM core revisi kita yang jadi biang
keduanya gelap      -> bukan dua modul itu; sisa stack display
                       (cmdq/ovl/rdma/leds) juga beda revisi
```

Konsekuensi aturan "100% source": driver panel + DRM yang benar berasal
dari revisi firmware `gcc51d883045d` yang source-nya tidak kita miliki.
Kalau `drmvendor` yang benar, opsinya hanya (a) dapatkan source revisi
itu, atau (b) pertahankan modul display vendor sebagai pengecualian
terdokumentasi sampai source tersedia.

## 31. Modul display tidak boleh dicampur antar revisi (dua image diag gagal boot)

### `diag-drmvendor` -> bootloop ke bootloader

Penyebabnya bukan crash, tapi modul gagal dimuat dan `init` langsung
fatal (setiap modul yang gagal = reboot ke bootloader):

```text
mediatek_drm_v1: Unknown symbol update_tran_brightness (err -2)
mediatek_drm_v1: Unknown symbol tranlog_local (err -2)
mediatek_drm_v1: Unknown symbol startAegisK (err -2)
mediatek_drm_v1: Unknown symbol set_disp_freq_by_regulator (err -2)
init: Failed to insmod '/lib/modules/mediatek_drm_v1.ko'
init: Failed to load kernel modules
init: InitFatalReboot: signal 6   -> reboot reason: bootloader
```

Asal simbol (semuanya di set vendor):

```text
update_tran_brightness        <- leds-mtk.ko (versi vendor)
tranlog_local                 <- transsion_tranlog.ko   (dibuang, tanpa source)
startAegisK                   <- thd.ko                 (dibuang, tanpa source)
set_disp_freq_by_regulator    <- mmqos-common.ko        (versi vendor)
```

Jadi "pakai DRM vendor" pun menyeret 2 modul Transsion tanpa source
(`transsion_tranlog`, `thd`) plus hook Transsion di `leds-mtk` dan
`mmqos-common`. Bukan jalan pintas.

### `diag-panelvendor` -> juga bootloop: ABI `mtk_panel_funcs` beda

Walaupun semua simbol panel vendor tersedia (`iris_*`, `find_panel_*`,
`mtk_panel_*`, `cmdq_pkt_sleep` semuanya ada di set kita), ukuran
struktur tabelnya beda:

```text
panel vendor (gcc51d88) : ext_funcs 0x258 (600 B), ext_params 0x10958
panel kita  (g2c4fd33)  : ext_funcs 0x1e8 (488 B), ext_params 0x10368
```

`mtk_panel_ext_create()` dari core kita membaca tabel 600 byte itu dengan
layout 488 byte -> pointer callback salah -> gagal muat/crash -> bootloop.
Artinya **modul display tidak bisa dicampur antar revisi**, harus satu set.

### Kabar baik: ada firmware revisi yang cocok dengan tree kita

`vendor_boot-new.img` ternyata image revisi **sama** dengan tree kita
(`gcc51d883045d` bukan, melainkan `g2c4fd33ae6d8`), lengkap dengan
`modules.load` + `modules.load.recovery`. Modul panel-nya
(`panel-rm69220-vdo-x6871.ko`, md5 `f4900300b5`, 272.368 B) punya offset
simbol dan ukuran `ext_funcs`/`ext_params` yang sama dengan hasil build
kita, dan sudah memuat `panel_doze_enable/disable`. Jadi driver panel kita
= driver yang dipakai firmware revisi ini; kita punya referensi biner
persis untuk pembanding.

### Image berikutnya

```text
twrp-vendor_boot-diag-stockB.img
  md5 d04a30ca00cd0710e1fe83b071c4a10a
  ramdisk kita + SELURUH 218 modul stock revisi g2c4fd33 (dari
  vendor_boot-new.img). Tanpa adaptive-ts/gt9916/haptic, jadi sentuh dan
  vibrator tidak akan jalan; yang dinilai hanya layar + wake.

twrp-vendor_boot-dbg-paneltrace.img
  md5 c6ea6866e883c65f4d83f34c3499def6
  set kita + trace `[LCMDBG]` di lcm_prepare/unprepare/enable/disable,
  lcm_panel_init, panel_doze_enable/disable.
```

Bacaan hasil:

```text
stockB wake OK  -> revisi g2c4fd33 memang bisa; build source kita yang
                   beda -> diff per modul terhadap set stockB
stockB gelap    -> revisi g2c4fd33 tidak cocok dengan HP/kernel ini, dan
                   satu-satunya jalan = source revisi gcc51d88
```

Temuan sampingan saat menyiapkan trace: di `lcm_probe()` driver panel
kita menyetel `ctx->prepared = true` dan `ctx->enabled = true`, sehingga
`drm_panel_prepare()`/`enable()` jadi no-op selama flag itu tidak
di-reset. Layar hanya hidup karena bootloader sudah menginisialisasi
panel; setelah blank yang melewati `unprepare` (jalur doze), tidak ada
yang mengirim ulang init sequence.

## 32. Config Transsion: tidak ada yang tertinggal di tree 6.12

Tree 6.12 kita **tidak punya** `kernel/configs/tran_custom.config` sama
sekali, dan build hanya memakai overlay `entry_level_legacy.config`.

Isi `tran_custom.config` donor 6.1: 71 `CONFIG_*`. Setelah dicek:

```text
punya Kconfig di tree 6.12 : 2   (AAC_HAPTIC_HV, NXP_NFC_SNXXX_DEVICE)
tanpa Kconfig              : 69
```

Tapi 6.12 MGK memakai Bazel, jadi patokannya bukan Kconfig melainkan
apakah makro itu **dirujuk di source**. Untuk display, dari 71 config 6.1
hanya 3 yang ada rujukannya di tree kita:

```text
CONFIG_TRANSSION_DOZE_BRIGHTNESS_SUPPORT  panel-rm69220-vdo-x6871.c  (kita aktifkan)
CONFIG_TRAN_GET_VREFRESH_SUPPORT          panel-rm69220-vdo-x6871.c  (tidak dipakai build)
CONFIG_TRAN_LHBM_NOTIFY_FINGERPRINT       transsion_fp_cust.c
```

Sisanya (TRAN_CWB_SUPPORT, TRAN_ALWAYS_NOTIFY_LCM_COLOR_MODE,
TRAN_LCD_AOD_ENTER_NOTIFY_SUPPORT, TRAN_DYNAMIC_WCG,
TRAN_PANEL_I2C_LCD_BIAS_SUPPORT, ...) **nol rujukan** di tree 6.12 —
mengaktifkannya tidak mengubah apa pun karena kodenya tidak ada.

Bukti tambahan bahwa build kita setara config dengan stock revisi B:

```text
symbol g_tran_get_vrefresh_main / g_lcm_fresh_mode
  panel stockB : tidak ada
  panel kita   : tidak ada          -> dua-duanya tanpa TRAN_GET_VREFRESH
section .data (ext_params + ext_funcs + tabel AOD)
  md5 5505711998f3f7388f2a1cf4640bcc20 identik
```

Dan poin penentu: `diag-stockB` memakai 218 modul **hasil build
Transsion** (yang jelas memakai `tran_custom.config` lengkap) dan tetap
tidak bisa bangun. Jadi config build kita bukan penyebab.

### Kesimpulan arah: panel revisi B memang tidak cocok dengan panel HP ini

- DTB `vendor_boot-new.img` identik dengan milik kita (`ead6a965b0aa`) —
  jadi bukan proyek/DT yang berbeda.
- Selisih nyata ada di driver panel: revisi A `bit_per_channel = 8`
  (`bpc:8`, `slice_bits 51840`), revisi B `bit_per_channel = 10`
  (`bpc:10`, `slice_bits 302400`), tabel backlight beda (1658 vs 1757).
- Saat boot layar benar karena panel diinisialisasi bootloader; driver
  kernel revisi B baru meng-init panel pada wake, dan hasilnya gelap.

### Eksperimen: jangan re-init panel

`twrp-vendor_boot-dbg-skipunprep.img` (`77740333d8c71f3763ca2a49bd1f999d`)
= set kita + `LCMDBG_SKIP_UNPREPARE`: `lcm_unprepare()` tidak mengirim
sleep-in, jadi panel dibiarkan pada state hasil init bootloader; wake
hanya menyalakan ulang DSI + backlight.

```text
layar nyala  -> init sequence revisi B memang tidak cocok untuk panel ini
                (workaround sah untuk TWRP; perbaikan benar = port config
                revisi A: bpc 8, tabel backlight 1658, init table A)
layar gelap  -> bukan init table; sisa kandidat: clock/DSC DDP atau
                timing DSI
```

### Koreksi: image skipunprep pertama gagal karena tabel dep/alias, bukan eksperimen

`pstore8.txt` (image `dbg-skipunprep`) berhenti di:

```text
init: Loaded kernel module /lib/modules/mtk-mmc-dbg.ko
init: LoadWithAliases was unable to load mtk_mmc, tried: mtk_mmc
init: Loaded 149 modules from /lib/modules
init: Failed to load kernel modules
init: InitFatalReboot: signal 6  -> reboot reason: bootloader
```

TWRP memang mengambil daftar dari `modules.load.recovery` (216 entri), dan
daftar itu **tidak berubah** antara image gagal dan image sehat
(md5 `81576cbc59` di keduanya). Yang saya tinggalkan saat restore setelah
eksperimen stockB adalah tabel pendampingnya:

```text
image gagal  : modules.dep / modules.alias milik set stockB
image sehat  : modules.dep / modules.alias milik set kita
```

Dan set stockB tidak punya modul `mtk-mmc.ko` sama sekali, jadi
`modules.dep`-nya tidak punya baris untuk modul itu:

```text
vib2 (sehat) : /lib/modules/mtk-mmc.ko: rpmb-mtk.ko ufs-mediatek-mod.ko ...
stockB       : (tidak ada baris mtk-mmc)
```

Init memakai daftar dari `modules.load.recovery`, tetapi resolusi nama
modul tetap lewat tabel dep/alias; karena `mtk-mmc.ko` tidak ada di tabel,
init mencoba `mtk_mmc` dan gagal -> fatal -> bootloader.

Image perbaikan:

```text
twrp-vendor_boot-dbg-skipunprep2.img
  md5 89d94cac8c311070890e769aade31759
  Beda dengan image sehat vib2 HANYA di panel-rm69220-vdo-x6871.ko
  (per-file md5 semua modul + load list + dep/alias identik dengan vib2).
```

## 33. Layar nyala tapi rusak -> konfigurasi DSC revisi B salah untuk panel ini

`dmesg7.txt` (image `dbg-skipunprep2`): layar **hidup** setelah wake, hanya
gambarnya rusak. Trace membuktikan panel tidak pernah di-reinit:

```text
[LCMDBG] lcm_disable enter enabled=1 prepared=1
[LCMDBG] lcm_unprepare enter prepared=1
[LCMDBG] lcm_unprepare skipped (LCMDBG_SKIP_UNPREPARE)
[LCMDBG] lcm_enable enter enabled=0 prepared=1
(1x sebagai ganti jalur post_bl); panel tidak mati, DSI0 buffer underrun hanya 3x
```

Jadi panel memang bisa menyala; isi gambarnya yang salah. Penyebabnya
ditemukan dengan membandingkan modul kita terhadap modul panel vendor
revisi A (`rm69220_..._x6871.ko`) yang di-RE:

### Beda parameter DSC (sama di blok 144/120/60Hz)

```text
field                  revisi B (kita)   revisi A (vendor, jalan)
bit_per_channel        10                8
slice_height           70                12
chunk_size             630               540
ver                    18                17
dsc_cfg                40                34
line_buf_depth         16                9
dec_delay              650               526
increment_interval     1658              287
decrement_interval     8                 7
line_bpg_offset        15                12
nfl_bpg_offset         446               2235
slice_bpg_offset       319               2170
flatness_minqp         7                 3
flatness_maxqp         16                12
rc_quant_incr_limit0/1 15                11
dsc_param_load_mode    2                 0
```

DSC 10bpc/302.400 bit per slice vs 8bpc/51.840 bit per slice: DDP
mengirim stream yang tidak bisa didekode panel -> hitam (kalau panel
di-init ulang) atau rusak (kalau panel dibiarkan dalam state bootloader).

### Beda init sequence

Driver vendor memakai tabel `lcm_initialization_setting` di `.data`:
126 entri, stride 128 byte, layout `{u32 cmd; u8 count; u8 para_list[]}`
(dibuktikan dari disassembly `push_table_cb`: `add x8, x19, x23, lsl #7`,
`ldrb w0, [x8, #4]`). Isinya 63 penulisan register dengan page switch
eksplisit (`0xfe 0x00`, `0xfe 0x60`, `0xfe 0x62`, ...), diakhiri
`0x11` + 120 ms + `0x29` + 20 ms. Driver kita sebelumnya memakai
sequence lain (63 entri tanpa page switch lengkap).

### Perbaikan (kernel `91640cdaead6`)

1. 17 field DSC di ketiga blok `ext_params` disamakan dengan vendor A.
2. Init sequence diganti dengan tabel vendor A yang diekstrak apa adanya
   (`lcm_init_table_a`, 126 entri) + helper `push_init_table_cpu()`;
   urutan reset GPIO disamakan (1 - 5ms - 0 - 5ms - 1 - 35ms).

Verifikasi: `.data` modul hasil build kini 0 field DSC yang beda dengan
modul vendor A.

Image: `twrp-vendor_boot-panelA.img` (md5 `de52dbcb8ae8c7642e6d7abd4919aab3`),
beda dengan image sehat `allsrc-vib2` hanya di modul panel.

## 34. DSC sudah benar, layar tetap gelap: panel butuh jalur iris

`dmesg8.txt` (image `panelA`): semua yang berhubungan dengan stream sudah
sesuai modul vendor, tapi layar tidak menyala.

```text
mtk_rdma_cal_golden_setting ... bpc:8      <- sama dengan vendor
RCT_ON = 0x1, num_extra_mux_bits = 246->240, slice_bits = 51840
                                           <- sama dengan vendor
DSI0 buffer underrun : 0x                  <- sebelumnya 6x
[LCM] lcm_prepare enter prepared=0
[LCM] lcm_panel_init begin/end error=0     <- 195 ms, tabel vendor A jalan
leds_mtk ... L:2047                        <- backlight diminta maksimum
lcm_setbacklight_cmdq level = 2047, mapped_level = 1757
```

Jadi init table lengkap, DSC cocok, tidak ada underrun, backlight 2047 —
tetap gelap.

### Beda yang tersisa: subsistem iris

Log vendor yang sehat memuat 20 baris `IRIS_LOG`, log kita **0**:

```text
normal.txt (vendor)
  IRIS_LOG I iris_init()
  IRIS_LOG I iris_init_timing_switch()
  IRIS_LOG I _iris_find_lightup_node(), failed to find pxlw,iris-lightup-config node
  IRIS_LOG I iris_reset() / _iris_reset_chip() reset start/end
  IRIS_LOG I iris_enable() pcfg->is_prepared = 0.
  IRIS_LOG I iris_lightoff() pcfg->is_prepared = 0.
  IRIS_LOG I iris_set_valid:set:4, real:1

dmesg8 (kita)
  (tidak ada)
```

Driver panel vendor memanggil `iris_reset()` lalu `iris_enable(NULL)`
sebelum push tabel init (terlihat di disassembly `lcm_prepare`), dan
`iris_lightoff()`/`iris_disable()` saat unprepare. `iris_*` diekspor oleh
`mediatek_drm_v1`; driver kita tidak pernah memanggilnya (0 rujukan).

Artinya: jalur `0x10` sleep-in yang dikirim `lcm_unprepare` mematikan
panel, dan tanpa `iris_enable()` panel tidak pernah dinyalakan lagi.
Layar boot tetap hidup karena bootloader sudah menyalakan iris.

### Image uji: panelA + skip_unprepare

`twrp-vendor_boot-panelA-skipsleep.img` (md5 `aa97ed759d5c50f406257ac3433fd49b`)
= image `panelA` + `skip_unprepare=1` (parameter modul, default 1).
Unprepare tidak mengirim sleep-in, panel dibiarkan pada state bootloader,
dan DSC yang dikirim sekarang 8bpc seperti vendor.

```text
gambar benar  -> kunci masalahnya memang iris; langkah berikutnya
                 tambahkan iris_reset/iris_enable/iris_lightoff ke driver
                 (perlu mediatek_drm_v1 dimuat sebelum modul panel karena
                 simbolnya diimpor) lalu balikkan skip_unprepare=0
masih gelap   -> ada faktor lain di sisi panel power (rail vddi/dvdd/vci
                 lewat panel_ext_lcm_power_set yang juga tidak dipanggil
                 driver kita)
```

## 35. Iris bukan penyebabnya; yang belum ada adalah rail panel

### Iris: tidak perlu di-RE

`iris_enable()` di `mediatek_v2/v1/iris_lightup.c` langsung keluar kalau
config belum disiapkan:

```c
if (!pcfg->is_prepared) {
        IRIS_LOGI("%s(), pcfg->is_prepared = %d.", __func__, pcfg->is_prepared);
        goto exit;
}
```

Dan log vendor yang sehat memuat persis pesan itu:

```text
IRIS_LOG I iris_enable() pcfg->is_prepared = 0.
IRIS_LOG I iris_lightoff() pcfg->is_prepared = 0.
```

Ditambah `IRIS_LOG E _iris_find_lightup_node(), failed to find pxlw,iris-lightup-config node`
pada boot. Artinya di perangkat ini iris tidak mengerjakan apa pun.

Selain itu source iris **sudah ada** di tree kita:
`drivers/gpu/drm/mediatek/mediatek_v2/v1/iris_lightup.c` dan
`iris_cmds.c`, dan simbol `iris_*` diekspor `mediatek_drm_v1` (sudah
dibuktikan waktu image `diag-panelvendor`). Jadi tidak perlu port/RE
iris; yang perlu hanya memanggilnya kalau memang dibutuhkan.

### Yang benar-benar belum ada: rail vddi/dvdd/vci

Log vendor memanggil hook rail di setiap siklus, log kita 0x:

```text
normal.txt (vendor)
  [LCM] panel_ext_lcm_power_set status=1 begin/end   (sebelum lcm_prepare)
  [LCM] lcm_prepare begin ... end
  ...
  [LCM] lcm_unprepare begin ... end
  [LCM] panel_ext_lcm_power_set status=0 begin/end   (sesudah lcm_unprepare)
```

Hook itu tidak pernah jalan di kita karena DRM revisi ini tidak punya
callback `lcm_power_set` (`mtk_panel_funcs` kita 0x1e8 = 488 byte,
vendor 0x258 = 600 byte). Akibatnya panel tidak pernah di-power-cycle:
`0x10` sleep-in dikirim, rail tetap hidup, dan panel tidak mau bangkit
lagi pada init berikutnya.

### Perbaikan (kernel `ad96798c52f0`)

`panel_ext_lcm_power_set()` (sudah ada di source tapi mati) dipanggil
langsung dari `lcm_prepare()` (sebelum pulse reset) dan dari
`lcm_unprepare()` (setelah sleep-in), urutannya sama dengan vendor.
`skip_unprepare` sekarang default 0 (siklus penuh) dan tetap tersedia
sebagai parameter modul untuk uji A/B.

Image: `twrp-vendor_boot-panelA-rails.img`
(md5 `ea51c7190c6db999656831e15fdf824d`), beda dengan image sehat
`allsrc-vib2` hanya di modul panel.

## 36. Akar sebenarnya: DSI data rate kita 1420, panel minta 1056

Perbandingan langsung `ext_params` modul vendor tidak berhenti di DSC.
Delapan u32 pertama ketiga blok (144/120/60Hz):

```text
vendor A : 0, 528, 1056, 0, 0, 1, 0, 0
kita     : 710, 1420, 0, 0, 0, 0, 0, 0     (sebelum perbaikan)
```

Pasangan `x, 2x` yang berdampingan di awal struct = `pll_clk` dan
`data_rate`:

```text
vendor A : pll_clk 528 MHz, data_rate 1056 Mbps
kita     : pll_clk 710 MHz, data_rate 1420 Mbps   (34% lebih tinggi)
```

Panel di-konfigurasi oleh init table-nya sendiri untuk rate tertentu
(register `0x2f` di page 0 dan page `0x60`). Kalau DSI dikirim 1420 saat
panel di-set untuk 1056, panel tidak bisa mendekode stream:

- panel dibiarkan dalam state bootloader (tidak sleep) -> gambar rusak
  (dmesg7, DSC juga masih 10bpc saat itu)
- panel di-power-cycle penuh (rail + reset + init table) -> hitam
  (dmesg8 dan dmesg9), walau DDP melaporkan bpc 8, 246 extra mux bits,
  51840 slice bits, dan 0 underrun

Layar saat boot tetap normal karena PLL DSI masih memakai nilai dari
bootloader sampai resume pertama.

### Perbaikan (kernel `ad6be249ea2a`)

`PLL_CLOCK_144/120/60` diubah 710 -> 528, sehingga `pll_clk = 528` dan
`data_rate = 528 * 2 = 1056`. Verifikasi `.data` hasil build: delapan u32
pertama `ext_params` sekarang `528, 1056, 0, 0` seperti vendor.

Image: `twrp-vendor_boot-panelA-528.img`
(md5 `f053c7b4c322f40a8e21f1ae40df5b95`), beda dengan image sehat
`allsrc-vib2` hanya di modul panel.

Cara cek di dmesg: baris `mtk_dsi_set_mmclk_by_datarate_V2` harus
menunjukkan `data_rate=1056` (sebelumnya 1420).

## 37. Layar menyala tapi rusak: tabel PPS min_qp/max_qp/bpg_ofs

`dmesg10.txt` (image `panelA-528`): semua parameter stream sudah benar dan
layar **menyala**, hanya gambarnya rusak.

```text
mtk_dsi_set_mmclk_by_datarate_V2, data_rate=1056   <- sesuai vendor
mtk_rdma_cal_golden_setting ... bpc:8              <- sesuai vendor
RCT_ON = 0x1, num_extra_mux_bits = 246->240, slice_bits = 51840
DSI0 buffer underrun : 0x
[LCM] lcm_panel_init begin/end error=0
```

### Donor 6.1 rm6xxx: bukan sumber konfigurasi 8bpc

Panel rm6xxx di donor 6.1 (`rm692j0_fhdp_dsi_cmd_dsc_boe*_144hz_*.c`,
ada di `tmp/ts61-src`, `tmp/ts61-tar`, `tmp/mt6897`, `tmp/cfg-x`) memakai
blok DSC yang **sama dengan konfigurasi lama kita**:

```text
.ver = 18, .dsc_cfg = 40, .bit_per_channel = 10, .slice_height = 70,
.chunk_size = 630, .dec_delay = 650, .increment_interval = 1658, ...
```

Jadi nilai 10bpc kita memang berasal dari keluarga donor itu, dan donor
tidak menyediakan varian 8bpc untuk panel ini.

### Yang berbeda: isi `ext_pps_cfg`

Dari `.data` modul vendor A (offset `0x4f04`):

```text
rc_tgt_offset (0x4f04) = 0
ext_pps_cfg.enable     = 1
rc_buf_thresh          -> .data+0x42e0  (14 nilai: 896, 1792, ... 8064
                                        = sama persis dengan tabel kita)
range_min_qp           = NULL
range_max_qp           = NULL
range_bpg_ofs          = NULL
```

Driver kita mengisi ketiganya dengan tabel 10bpc
(`min_qp = 0,4,5,5,7,7,7,7,7,7,9,9,9,13,16`). `mtk_disp_dsc.c` menulis
grup register PPS itu hanya kalau pointer-nya tidak NULL:

```c
if (dsc_param_load_mode == 1) { ... tabel tpc_* bawaan ... }
else {
        rc_buf_thresh = dsc_params->ext_pps_cfg.rc_buf_thresh;
        range_min_qp  = dsc_params->ext_pps_cfg.range_min_qp;
        ...
}
if (rc_buf_thresh) { ... }   /* per grup */
```

Jadi DDP mengirim tabel kuantiser 10bpc padahal panel mendekode 8bpc →
gambar rusak.

### Perbaikan (kernel `f9a9ae52f076`)

`range_min_qp`, `range_max_qp`, `range_bpg_ofs` di ketiga blok parameter
(144/120/60Hz) di-set `NULL`, `rc_buf_thresh` tetap. Hasilnya
`ext_pps_cfg` identik dengan modul vendor.

Image: `twrp-vendor_boot-panelA-pps.img`
(md5 `e675830b69e5394e2c8d96a4559e2d57`).

## 38. Gambar rusak: mode DSI burst, seharusnya sync-pulse

Modul vendor menyimpan `0xc05` ke `dsi->mode_flags` (disasm `lcm_probe`:
`mov w8, #0xc05` lalu `str x8, [x20, #960]`):

```text
0xc05 = MIPI_DSI_MODE_VIDEO            (0x001)
      | MIPI_DSI_MODE_VIDEO_SYNC_PULSE (0x004)
      | MIPI_DSI_CLOCK_NON_CONTINUOUS  (0x400)
      | MIPI_DSI_MODE_LPM              (0x800)
```

Driver kita memakai:

```text
VIDEO | VIDEO_BURST | LPM | NO_EOT_PACKET = 0xa03
```

Donor 6.1 mengonfirmasi konvensi panel VDO di platform ini — semuanya
sync-pulse, tidak ada yang burst:

```text
nt37703a_fhdp_dsi_vdo_tm_tm_144hz_x6870.c
ft8725_fhdp_dsi_vdo_txd_boe_144hz_lj7.c
panel-alpha-jdi-nt36672e-vdo-120hz/144hz.c
panel-himax-hx83121a-vdo.c
  -> MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_SYNC_PULSE | ...
```

Dengan DSC 8bpc, PPS, init table, rail, dan DSI rate 1056 sudah sama
dengan vendor, burst framing inilah yang membuat gambar tampil tapi
rusak.

### Perbaikan (kernel `6a6db548a43c`)

```c
dsi->mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_SYNC_PULSE |
                  MIPI_DSI_CLOCK_NON_CONTINUOUS | MIPI_DSI_MODE_LPM;
```

Verifikasi biner modul hasil build: `mov w8, #0xc05` + `str x8, [x19, #960]`.

Image: `twrp-vendor_boot-panelA-syncpulse.img`
(md5 `8775055b79a3408563e02091e861e532`).

## 39. Crosscheck donor Transsion: tabel PPS 8bpc bawaan MTK

Donor Transsion memang meng-commonize helper antar HP, jadi dicek langsung
ke source-nya:

```text
tmp/ts61-src/.../panel-alpha-jdi-nt36672e-vdo-120hz.c:1073
    .dsc_param_load_mode = 0,
    //0: default flow; 1: key param only; 2: full control

tmp/ts61-src/.../nt37703a_fhdp_dsi_vdo_tm_tm_144hz_x6870.c  (saudara x6871)
    DSC_VER 17, DSC_SLICE_HEIGHT 12, DSC_CHUNK_SIZE 540,
    DSC_DEC_DELAY 526, DSC_INCREMENT_INTERVAL 287   <- sama dengan nilai
    vendor A yang sudah kita port
```

Dan `mtk_disp_dsc.c` punya dua set tabel kuantiser 8bpp yang lengkap:

```text
tpc_range_8bpp_8bpc_*  : min_qp 0,0,1,1,3,3,3,3,3,3,5,5,5,9,12
tpc_range_8bpp_10bpc_* : min_qp 0,4,5,5,7,7,7,7,7,7,9,9,9,13,16  <- tabel
                         yang dipakai driver kita sebelumnya
```

Jadi tabel lama kita adalah set 10bpc. Dengan `dsc_param_load_mode = 1`,
DDP memilih set tabel dari `bit_per_channel`/`bit_per_pixel`; untuk
8bpc/8bpp hasilnya `tpc_range_8bpp_8bpc_*` plus `tpc_rc_buf_thresh` yang
identik dengan tabel `rc_buf_thresh` panel.

### Perbaikan (kernel `400b51ff9b30`)

`dsc_param_load_mode` di ketiga blok parameter: 0 -> 1, sehingga tidak ada
lagi tabel PPS yang dibawa manual oleh driver panel.

Image: `twrp-vendor_boot-panelA-mode1.img`
(md5 `227c49b8980a62dd3bb37b4f23d24b41`).

## 40. Layar mati -> nyala: SELESAI (dmesg12)

Hasil akhir `dmesg12.txt`, siklus layar mati -> nyala bersih:

```text
mtk_dsi_set_mmclk_by_datarate_V2 ... data_rate=1056, mmclk=213 pixclk_min=193
mtk_rdma_cal_golden_setting ... bpc:8
RCT_ON = 0x1, num_extra_mux_bits = 246->240, slice_bits = 51840
DSI0 buffer underrun : 0x
[LCM] lcm_prepare enter prepared=0
[LCM] lcm_panel_init begin/end error=0
```

### Rangkaian perbaikan yang diperlukan (semuanya dari modul stock)

| # | Perbaikan | Commit kernel |
|---|---|---|
| 1 | init sequence: tabel `lcm_initialization_setting` vendor (126 entri) + urutan reset | `91640cdaead6` |
| 2 | parameter DSC vendor: bpc 8, dsc_cfg 34, ver 17, slice 12, chunk 540, dec 526, incr 287, dst | `91640cdaead6` |
| 3 | rail `panel_ext_lcm_power_set` dipanggil di prepare/unprepare | `ad96798c52f0` |
| 4 | DSI rate 528 MHz / 1056 Mbps (bukan 710/1420) | `ad6be249ea2a` |
| 5 | `ext_pps_cfg` hanya `rc_buf_thresh` (tabel lain NULL) | `f9a9ae52f076` |
| 6 | `mode_flags` 0xc05: sync-pulse + non-continuous clock (bukan burst) | `6a6db548a43c` |
| 7 | `dsc_param_load_mode = 1` -> tabel PPS 8bpc bawaan MTK | `400b51ff9b30` |
| 8 | buang parameter diagnostik `skip_unprepare` | `28f523738d7a` |

### Varian final

```text
twrp-vendor_boot-allsrc-display.img
  md5 e7014d7273da2b7310ce1da1c947caf7
  222 modul (semua dari source), load 165, recovery 216
  beda dengan image sehat allsrc-vib2 hanya di panel-rm69220-vdo-x6871.ko
```

Varian ini adalah final **layar** saat itu; image final sekarang adalah
`allsrc-display-usb` (§43/§44) yang menambahkan perbaikan USB.

Catatan yang masih terbuka: `lcm_probe()` masih menyetel `prepared = true`
dan `enabled = true`, jadi init pertama setelah boot tetap mengandalkan
state dari bootloader. Perilaku ini tidak diubah karena boot dan wake
sudah benar, dan tidak ada keluhan layar saat boot.

## 41. Cabut-colok USB: tumpukan stock = revisi lebih baru dari donor & tree kita

Gejala: adb hidup saat boot (kabel sudah tercolok), tapi setelah kabel
dicabut lalu dicolok lagi USB tidak enumerate sama sekali.

### Crosscheck donor 6.1 (tidak menjawab)

`tran_usb_ctrl.c`, `tc_tcpc.c`, `tc_chg_type_det.c` donor 6.1 **identik
secara fungsi** dengan tree kita; bedanya hanya adaptasi API 6.12:

```text
tran_usb_ctrl.c   21 baris : -#include <linux/pinctrl/consumer.h>, remove() -> int
tc_tcpc.c         22 baris : const char *const, remove() -> int
tc_chg_type_det.c 62 baris : usb_types BIT() bitmask -> array enum (6.12),
                             remove() -> int
```

Jadi donor tidak punya jawaban untuk kasus ini.

### Yang dipakai stock ternyata revisi lebih baru

Perbandingan string biner `.ko` stock (vendor A) vs build kita, modul tumpukan
USB/charger:

| modul | fitur yang hanya ada di stock |
|---|---|
| `tc_tcpc` | `[TC_TCPC] %s: %s dr_swap, new role=%d` |
| `tc_chg_type_det` | `stop bc12 due to dr swap`, `data role swap to DFP`, `pd detected!!!`, `tcd_set_bc12_complete`, `wireless is still working, wait for it to stop`, `wireless has stopped working, start BC1.2 detection`, `charger_dev_pd_set_hiz_flag/_charge_flag`, `charger_dev_set_input_current`, `check_wireless_to_wired`, `get_tadapter_by_name` (+ `depends=...tc_adapter_class`) |
| `mtu3` | `depends=tcpc_class`, `set usb config = %d`, `pe_ready=%d, explicit_contract=%d`, `is_usb_pd`, `mtu3_suspend_reset_work`, `ssusb_get_platform_driver`, `ssusb_remap_axi_domain` |
| `tran_extcon_usb` | `do_tran_otg_uevent` |
| `phy-mtk-xsphy` | `mediatek,host-discth`, `mediatek,rev4`, debugfs `dual_val_show` |

Ukuran fungsi (.text per simbol, stock dibanding build kita):

```text
tc_chg_type_det : tc_detect_bc12_work        2052 vs 1240   (-812)
                  tc_pd_tcp_notifier_call    1032 vs  760   (-272)
                  tc_detect_bc12_retry_work  1072 vs  840   (-232)
                  tc_detect_charger_set_property 492 vs 352 (-140)
tc_tcpc         : tc_pd_tcp_notifier_call    1580 vs 1396  (-184)
mtu3            : mtu3_ep0_isr               2404 vs 1980  (-424)
                  mtu3_probe                 5072 vs 4680  (-392)
                  ssusb_gadget_init          2300 vs 1976  (-324)
mt6375-charger  : mt6375_get_vbus_gd_stat     192 vs   0   (hilang, lihat 18)
```

Semua simbol yang dibutuhkan modul stock tersedia di set kita
(`charger_dev_pd_set_hiz_flag`, `get_tadapter_by_name`,
`wireless_manager_reverse_state`, `tc_get_boot_mode`, dst. ada di
`tc_charger_class`/`tc_adapter_class`/`tc_misc_intf`), jadi modul stock bisa
dipasang sebagai biseksi.

### Image biseksi (satu variabel per image, sisanya tetap build kita)

```text
twrp-vendor_boot-usb-bisect-chgdet.img      md5 515b93aa1a3d278087e3f76d80965e8d
twrp-vendor_boot-usb-bisect-tcpc.img        md5 2732185317e6b53ec732e3af549b8eb7
twrp-vendor_boot-usb-bisect-chgdet-tcpc.img md5 fbdf780a32c812b93356a8eb6db54a06
twrp-vendor_boot-usb-bisect-mtu3.img        md5 702fe8d2d1d9c89f1ef66e1ebe66f187
```

Diverifikasi: hanya `.ko` yang dimaksud yang berbeda dari baseline
`allsrc-display` (222 modul). Urutan tes: chgdet -> tcpc -> chgdet+tcpc ->
mtu3. Kalau salah satu lolos uji cabut-colok, modul itu yang harus di-RE.

## 42. Cabut-colok USB: akar masalah di event `tran_extcon_usb`

`dmesg13` merekam satu siklus penuh cabut (12,3 s) lalu colok lagi (14,3 s).
Rantainya:

```text
CABUT  12.327  event:7  (USB_PLUG_OUT)      -> tidak ditangani
       12.328  event:2  (TC_PD_TYPE, pd_type=0) -> "switch role to host"
       12.330  cur_dr(2) new_dr(0) lalu new_dr(1)
       12.331  mtu3: ssusb_set_mode host
COLOK  14.311  event:6  (USB_PLUG_IN)       -> tidak ditangani
       14.519  psy: online=1, type=4          -> c_role==HOST, bukan NONE,
                                                 jadi psy detector tidak
                                                 menyetel DEVICE
       16.751  event:2  (pd_type=5)           -> "Delay for swap..." lalu
                                                 menyerah
```

Jadi setelah cabut, peran USB ditinggal di **HOST**, dan `psy_detector`
hanya mau menyetel DEVICE kalau `c_role == USB_ROLE_NONE`.

### Biner stock: nomor event berbeda 2

RE `tran_extcon_usb.ko` stock (yang jalan di `normal.txt`) menunjukkan
cabang yang dipakai:

| event stock | aksi stock |
|---|---|
| 8 | `Type-C SINK plug in` -> role **DEVICE** (di-skip kalau `bypss_typec_sink`) |
| 9 | `Type-C plug out` -> role **NONE** |
| 10 | `Type-C SRC plug in` -> role **HOST** |
| 11 | `Type-C plug out` -> role **NONE** |

Dan `tc_tcpc` stock mengirim `USB_PLUG_IN` sebagai **8**, `SNK_VBUS`
sebagai **14** — sedangkan header di tree ini punya 6 dan 12. Artinya
stock memakai enum yang bergeser 2, dan source driver extcon yang
sekarang ada di tree ini memakai nomor enum yang **salah** (menganggap
`OTG_PLUG_IN`=8 sebagai `SINK plug in`).

Selain itu, di stock `tc_tcpc` menulis `pd_type` di `noti+0xc`, tapi
`tran_extcon_usb` stock membacanya di `noti+0x10`; jadi seluruh logika
"switch role berdasarkan pd_type" di sana adalah **dead code**. Di tree
ini logika itu hidup, dan justru itulah yang mengubah setiap cabut
kabel menjadi "switch role to host".

### Perbaikan (kernel `af55c9c00426`)

1. `tran_extcon_pd_tcpc_notifier()` memakai enum tree ini dengan benar:
   `USB_PLUG_IN` (=6) -> DEVICE, `USB_PLUG_OUT` (=7) / `OTG_PLUG_OUT`
   (=9) -> NONE, `OTG_PLUG_IN` (=8) -> HOST. Blok `pd_type` dihapus
   (dead code di stock).
2. `usb_is_online()` membaca `POWER_SUPPLY_PROP_USB_TYPE` dan menerima
   SDP/CDP, sama seperti stock (sebelumnya `POWER_SUPPLY_PROP_TYPE`).

Hasil yang diharapkan: cabut -> role NONE (bukan HOST), colok ->
psy detector (c_role==NONE) menyetel DEVICE lagi.

Image: `twrp-vendor_boot-usb-replug.img`
(md5 `8233c66d7b09aefd2e5b0fe5f4ca4c2e`), 222 modul, beda dengan
`allsrc-display` hanya di `tran_extcon_usb.ko`.

### 42.1 Verifikasi: dmesg14 (cabut-colok berulang)

`dmesg14.txt` merekam tiga siklus colok dan dua siklus cabut. Semua
siklus berakhir dengan enumerasi ulang yang bersih:

```text
8.837   online=1, type=1  (SDP)
8.837   Type-C SINK plug in of psy -> cur_dr(0) new_dr(2)
8.837   ssusb_set_mode device / pullup D+
9.186   gadget RESET / ep1out+ep1in enable          (enumerasi #1)

12.640  event:7 USB_PLUG_OUT -> "Type-C plug out"
12.642  cur_dr(2) new_dr(0) -> ssusb_set_mode none / pullup D-
        (event:2 pd_type=0 diabaikan, sesuai dead-code stock)

14.375  online=1, type=1 -> cur_dr(0) new_dr(2)
14.375  ssusb_set_mode device / pullup D+
14.834  gadget RESET / ep1out+ep1in enable          (enumerasi #2)

16.030  event:7 -> "Type-C plug out" -> cur_dr(2) new_dr(0)
19.017  online=1, type=1 -> cur_dr(0) new_dr(2)
19.426  gadget RESET / ep1out+ep1in enable          (enumerasi #3)
```

Catatan penting:

- `type=1` sekarang muncul, sama persis dengan log stock (`normal.txt`),
  membuktikan pembacaan `POWER_SUPPLY_PROP_USB_TYPE` (SDP) benar.
- Tidak ada lagi `switch role to host` saat cabut; role berakhir NONE
  sehingga psy detector bisa menyetel DEVICE lagi.
- 0 buffer underrun, tiga kali `gadget (high-speed) pullup D+` diikuti
  `gadget RESET` dan enable endpoint — adb hidup lagi di setiap colok.

Status: **cabut-colok USB selesai**. Image `twrp-vendor_boot-usb-replug.img`
(md5 `8233c66d7b09aefd2e5b0fe5f4ca4c2e`) kemudian terbukti memakai
driver panel lama sehingga gagal bangun dari mati layar; lihat §43.
Image penggantinya: `twrp-vendor_boot-allsrc-display-usb.img`
(md5 `0ecdaa1edb3d405954331539b24c911b`).

## 43. dmesg15: layar hitam saat bangun — image `usb-replug` memakai panel driver lama

Gejala: setelah layar mati lalu dinyalakan lagi, panel tetap hitam.
`dmesg15` (image `twrp-vendor_boot-usb-replug.img`) menunjukkan:

```text
17.996  backlight 0 / screen off
        TIDAK ADA lcm_unprepare, TIDAK ADA panel_ext_lcm_power_set status=0
20.430  CRTC resume, data_rate=1420, bpc:10, RCT slice_bits=302400
        TIDAK ADA panel_ext_lcm_power_set status=1
        TIDAK ADA lcm_prepare / lcm_panel_init
20.486  DSI0: buffer underrun
```

Bandingkan dengan stock `normal.txt`:

```text
11.523  backlight 0 / screen off
11.530  [LCM] lcm_unprepare begin ... end
11.649  [LCM] panel_ext_lcm_power_set status=0
13.355  CRTC resume, bpc:8, RCT slice_bits=51840
13.365  [LCM] panel_ext_lcm_power_set status=1
13.379  [LCM] lcm_prepare begin
13.379  [LCM] lcm_panel_init begin ... 13.580 end
13.581  screen on / backlight 2047
```

dan dengan `dmesg13` (image `allsrc-display`) yang memang bisa mati->nyala:

```text
 6.572  panel_ext_lcm_power_set status=0
 8.001  data_rate=1056, bpc:8
 8.007  [LCM] lcm_prepare enter prepared=0
 8.007  panel_ext_lcm_power_set status=1
 8.016  [LCM] lcm_panel_init begin ... 8.212 end error=0
 8.215  backlight 2047 / 0 underrun
```

### Akar masalah: baseline packing yang basi

`cmp-out/vbverify5` dibuat **12:49**, yaitu salinan modul dari
`twrp-vendor_boot-allsrc-vib2.img` — sebelum perbaikan layar (15:09).
Perbandingan md5 modul panel:

| Sumber | md5 `panel-rm69220-vdo-x6871.ko` |
|---|---|
| `allsrc-vib2` / `vbverify5` / `usb-replug` | `466219a6e7cf99a818cb8e5d1ef3ccfd` |
| `allsrc-display` / build tree sekarang | `19507dee2cf1de89bbec3d8128ef7589` |

Modul lama tidak punya simbol/log `panel_ext_lcm_power_set`, memakai
mode 10bpc (`data_rate=1420`, `bpc:10`, RCT `302400`), dan tidak
menjalankan init panel saat resume. Modul final memakai 8bpc
(`data_rate=1056`, `bpc:8`, RCT `51840`) dan memanggil
`panel_ext_lcm_power_set` + `lcm_panel_init` saat resume — persis stock.

Jadi ini **bukan bug baru** dan bukan efek perubahan `tran_extcon_usb`:
image `usb-replug` memang salah memuat driver panel lama. `dmesg14`
tidak menangkapnya karena tidak ada siklus layar mati->nyala.

### Perbaikan

Repack ulang memakai seluruh modul dari `allsrc-display`, lalu ganti
hanya `tran_extcon_usb.ko` dengan versi `usb-replug`:

- `twrp-vendor_boot-allsrc-display-usb.img`
- md5 `0ecdaa1edb3d405954331539b24c911b`
- 222 modul; diff terhadap `allsrc-display` hanya `tran_extcon_usb.ko`,
  diff terhadap `usb-replug` hanya `panel-rm69220-vdo-x6871.ko`
- md5 panel di image = `19507dee...`, md5 USB = `5c196dec...`
- build tree sekarang (di-strip) menghasilkan md5 panel yang sama

`twrp-vendor_boot-usb-replug.img` **deprecated** untuk uji layar; pakai
image di atas.

## 44. Bersih-bersih artefak dan repack otomatis dari build terbaru

Setelah §43, semua baseline hasil unpack lama dihapus supaya tidak ada
lagi sumber modul yang bisa basi:

- dihapus: `cmp-out/vbverify*`, `cmp-out/vfy-*`, `cmp-out/xcmp`,
  `cmp-out/chk-*`, `cmp-out/hdr-*`, `cmp-out/dtb-cmp`, `cmp-out/dtb-new`,
  `cmp-out/px-*`, seluruh `twrp-*.img` lama di `cmp-out` dan
  `tmp/x6871` kecuali image final, serta image percobaan
  `vendor_boot-{abie,roundtrip,script,new}.img`
- disimpan: `tmp/x6871/twrp-vendor_boot-allsrc-display-usb.img`
  (md5 `0ecdaa1edb3d405954331539b24c911b`), stock `vendor_boot.img`,
  `boot.img`, `dtbo.img`, dan firmware referensi `tmp/x6871/vr`
- hasil: `cmp-out` 12G -> 682M, `tmp/x6871` 3.0G -> 458M

Workflow repack baru (commit manifest `88b6a03`):

```bash
./tools/repack-vendor-boot-latest.sh
```

1. build Bazel dengan perintah resmi (`HANDOFF.md` §Perintah build),
2. cari staging `mgk_64_k612_customer_modules_install.user` terbaru,
3. stage 222 modul dari `tools/recovery-modules.txt` (bukan dari image),
4. `llvm-strip --strip-debug` + `depmod` untuk metadata,
5. pack dengan `tmp/vbwork-twrp`,
6. unpack hasil dan gagal kalau ada `.ko` yang md5-nya beda dari staging,
7. tulis `<out>.buildinfo` berisi commit kernel, jumlah modul, md5 image.

Uji: staging dari build `af55c9c00426` menghasilkan 222 modul yang
**sama persis** dengan image final (metadata teks `modules.dep`,
`modules.alias`, `modules.softdep`, `modules.load`, `modules.load.recovery`
juga identik), jadi workflow ini tidak mengubah isi modul yang sudah
terbukti jalan. Image uji otomatis dibuat lalu dihapus lagi; image final
tetap `twrp-vendor_boot-allsrc-display-usb.img`.

## 45. DLKM repack: vendor_dlkm + odm_dlkm 100% source

Stock image diperoleh dari filebin (`gj6uxkeye4syth9x`, `Archive.zip`):
`vendor_dlkm.img` 24.551.424 byte dan `odm_dlkm.img` 4.206.592 byte,
keduanya EROFS + AVB hashtree footer. Diekstrak dengan
`android_tools/bin/extract.erofs`; hasil `config/*_fs_options` memuat
perintah build stock yang persis:

```text
mkfs.erofs -zlz4hc -T 1230768000 -U <uuid> \
  --mount-point=/vendor_dlkm \
  --fs-config-file=./config/vendor_dlkm_fs_config \
  --file-contexts=./config/vendor_dlkm_file_contexts \
  <out> ./vendor_dlkm
```

Sebagai validasi, tree stock dibangun ulang dengan perintah itu lalu
ditambah AVB footer yang sama (salt, partition size, props, release
string) menghasilkan image **byte-identik** dengan stock. Pipeline
repack karena itu tidak menebak format.

### Hasil

| Partisi | Modul | `modules.load` | `modules.dep` | Ukuran | md5 |
|---|---|---|---|---|---|
| `vendor_dlkm` | 212 | 194 | 212 | 24.551.424 | `c329bbb8a465e32dc5bfd4cdcaede45f` |
| `odm_dlkm` | 57 | 57 | 57 | 4.206.592 | `0ffbb42985d445f7c12808df3b50960e` |

- Total **269 modul, semuanya dari staging build source** (bukan `.ko`
  stock). Modul diambil dari staging terbaru, `llvm-strip --strip-debug`,
  lalu md5 dicek ulang dari image hasil ekstrak: 0 beda.
- `modules.dep`/`alias`/`softdep` digenerate `depmod`; path memakai
  `/vendor_dlkm/lib/modules/...` dan `/odm_dlkm/lib/modules/...`.
- `modules.load` sudah difilter: 194/57 entri, 0 referensi menggantung.
- Closure simbol kernel + 222 modul vendor_boot + 269 modul dlkm: hanya
  weak `mtk_drm_gateic_set_backlight` (tidak menghambat load).
- SELinux label dan permission modul baru (`bluetooth`, `rfkill`,
  `libarc4`, `task_turbo`, `zram`, `zsmalloc`) ditambahkan ke
  fs_config/file_contexts; hasil ekstrak image menunjukkan
  `vendor_file` + 0644 root.
- AVB hashtree footer dipertahankan: salt image, partition name, ukuran,
  FEC roots 2, dan props sama seperti stock. Top-level `vbmeta` stock
  memakai salt berbeda dan sudah dipatch untuk boot modified system
  (sesuai keputusan user), jadi tidak diubah.

### Reproduksi

- Stock image + tree hasil ekstrak: `/serverhive1/ramabondanp/tmp/dlkm-img/`
  (`vendor_dlkm.img`, `odm_dlkm.img`, `vendor_dlkm/`, `odm_dlkm/`,
  `config/`).
- `mkfs.erofs`/`extract.erofs`: `/serverhive1/ramabondanp/tmp/android_tools/bin/`.
- AVB: `/serverhive1/ramabondanp/tmp/dlkm-build/avbtool.py` (avbtool
  1.3.0) + `fec` di `tmp/vbwork-twrp/aosp/plugged/bin`, dengan
  `LD_LIBRARY_PATH=tmp/vbwork-twrp/aosp/plugged/lib`.
- Builder prototipe yang dipakai: `/serverhive1/ramabondanp/work/build_dlkm_images.py`.

### Artefak

```text
/serverhive1/ramabondanp/tmp/dlkm-out/vendor_dlkm.img
/serverhive1/ramabondanp/tmp/dlkm-out/odm_dlkm.img
/serverhive1/ramabondanp/tmp/dlkm-out/twrp-dlkm-source-20261120.zip
  md5 5ae77a5b98cb99491eccabb635d22370
release: dlkm-20261120
```

Cara flash:

1. **TWRP**: Install zip `twrp-dlkm-source-20261120.zip`.
2. **fastbootd** (kalau tersedia): `fastboot flash vendor_dlkm
   vendor_dlkm.img` lalu `fastboot flash odm_dlkm odm_dlkm.img`.
3. Rollback: flash balik stock `vendor_dlkm`/`odm_dlkm`.

Zip TWRP memetakan logical partition yang sudah ada (`lptools map`),
mengecek ukuran, lalu `dd` image ke `/dev/block/mapper/<part>`; tidak
menghapus/membuat ulang partition. Rollback: flash balik image stock
`vendor_dlkm`/`odm_dlkm`.

### Catatan / belum diuji

- **System boot belum diuji.** Yang sudah diverifikasi baru isi image,
  ukuran partisi, AVB footer, metadata modul, dan closure simbol.
- 25 nama stock tidak dimasukkan karena tidak ada source
  (`transsion_tranlog`, `thd`, varian touch alternatif, dll). Framework
  `imgsensor.ko`/`flashlight.ko` tetap dibangun dari source; driver sensor
  X6871 sendiri belum ada. Rincian di HANDOFF.
- Kalau system tetap menolak mount karena verity, penyebabnya top-level
  `vbmeta`, bukan image ini; sesuai keputusan user, vbmeta sudah dipatch
  dan tidak diubah.

## 46. dmesg1: panic SCP karena `SCP_IPI_COUNT` 56 vs stock 59

`dmesg1` berhenti di 5,11 s dengan:

```text
scp 1c400000.scp: error -EINVAL: invalid resource (null)
MBOX 0..4 can't find send/recv status reg
Internal error: Oops - BRK: 00000000f2000001
pc : mtk_ipi_device_register+0x340/0x3c4 [mtk_tinysys_ipi]
lr : mtk_ipi_device_register+0x1e0/0x3c4 [mtk_tinysys_ipi]
...
scp_device_probe+0x9f4/0xb94 [scp]
```

BRK itu adalah bounds check di loop `pin_send_table[]`/`pin_recv_table[]`:
`chan_id` harus `< ipi_chan_count` yang diteruskan `scp_device_probe()`.
DT X6871 `scp@1c700000` memakai:

```text
send-table: ... 0x38 ...     (chan_id 56)
recv-table: ... 0x39 ...     (chan_id 57)
```

sedangkan `SCP_IPI_COUNT` di tree 6.12 hanya 56 (ID 0..55). Stock
`scp.ko` memanggil `mtk_ipi_device_register()` dengan **`w3 = 0x3b`
(59)** — dibuktikan dari disassembly:

```text
34dc:  mov  w3, #0x3b
34e0:  bl   mtk_ipi_device_register
```

### 6.1 donor tidak menjawab

`tmp/ts61-src/.../scp/include/scp.h` adalah enum SCP yang lebih tua
(tidak punya ID touch 52..55, dan `SCP_IPI_COUNT`-nya bukan 59). Jadi
sesuai aturan: donor tidak memuat perubahan X6871 ini, lalu RE biner
stock yang dipakai. `mtk_tinysys_ipi.c` donor juga punya fitur timeout
tambahan yang tidak ada di 6.12, tetapi bukan penyebab panic ini.

### Perbaikan (kernel `5ba6fb6559ab`)

`SCP_IPI_COUNT` diubah menjadi **59** (ID 56..58 dicadangkan, sama
seperti stock). Tidak ada nama IPI baru yang dikarang; komentar di
header menjelaskan asal angka dari biner stock.

Karena header ini dipakai beberapa modul, rebuild menghasilkan perubahan
pada `scp.ko`, `ccci_fsm_scp.ko`, `connscp.ko`, `mtk-scp-audiocommon.ko`,
`mtk-scp-vow.ko`, dan `mtk-vow.ko` — semuanya di `vendor_dlkm`. Sesuai
permintaan, **hanya `vendor_dlkm` yang di-repack**; `odm_dlkm` tidak
disentuh.

### Artefak

```text
vendor_dlkm.img                 md5 5b7472dea26b60dd8eef5370a2cd13a9
odm_dlkm.img (tidak berubah)    md5 0ffbb42985d445f7c12808df3b50960e
twrp-dlkm-scpfix-20261120.zip   md5 a9daf0c469810ec32a673e3ecda6bb4a
release                         dlkm-scpfix-20261120
```

Flash zip TWRP di atas (hanya menulis `vendor_dlkm`); `odm_dlkm` tetap
dari release `dlkm-20261120`. Boot system belum diuji setelah fix ini.

Catatan cakupan: kedua image tetap **269 modul 100% source** (212 vendor
+ 57 odm); 25 nama stock tanpa source tidak ada. `imgsensor.ko` dan
`flashlight.ko` yang ada di image adalah hasil build source, bukan `.ko`
stock.

## 47. dmesg2: panic Mali — pakai GPU stack donor OPPO (r54p1-11eac0)

SCP sudah lolos (`dmesg2` berlanjut ke userspace/apexd), tetapi berhenti
di GPU:

```text
kbase_backend_gpuprops_get,illegal shader present , HW: 0x130013, SW: 0x0
kernel BUG at .../mali_kbase_gpuprops_backend.c:60!
kbase_backend_gpuprops_get
kbase_gpuprops_init
kbase_device_early_init
kbase_platform_device_probe [mali_kbase_mt6895_a16w]
```

Penyebabnya `gpufreq_get_shader_present()` mengembalikan 0 saat Mali
probe, sehingga `BUG_ON(1)` di jalur `CONFIG_MTK_GPUFREQ_V2 &&
!CONFIG_MTK_GPU_LEGACY` aktif.

### Sumber: donor 6.1 tidak punya GPU, donor OPPO 6.12 punya versi stock

- `tmp/ts61-src` tidak memuat tree `vendor/mediatek/kernel_modules/gpu`.
- Donor OPPO mt6896 6.12 memuat `mali_avalon/a16w` dengan
  `MALI_RELEASE_NAME="r54p1-11eac0"` — **sama dengan stock X6871**
  (`modinfo` stock: r54p1-11eac0, UK 1.38).
- Tree Moto kita sebelumnya r54p1-08bet0, dan `mtk_gpufreq_wrapper.ko`
  belum mengekspor `gpufreq_driver_ready` seperti stock.

### Config OPPO yang dicek

- `entry_level_legacy.config` OPPO identik dengan kita (tidak ada
  perbedaan GPU).
- `a16w/config/fragment/mt6895.fragment` donor menambah config Mali
  (`CONFIG_MALI_MTK_PROTECTED_PATCH`, `PREVENT_PRINTK_TOO_MUCH`,
  `KBASE_THREAD_DEBUG`, `KCPUQ_PRIORITZED`, `SCHEDULER_KTHREAD_PATCH`);
  fragment ini ikut diimpor.
- Config efektif tetap `CONFIG_MTK_GPUFREQ_V2=y`,
  `CONFIG_MTK_GPU_LEGACY=n`; jadi bukan sekadar mematikan jalur BUG.

### Perubahan sumber

- `kernel_device_modules-6.12`: seluruh `drivers/gpu/mediatek` diganti
  versi donor OPPO (ged, gpufreq/v2, gpueb, gpu_pdma, gpu_bm, hal,
  mt-plat). Kernel commit `5462a6d118a6` (English, pushed ke `alps`).
- `vendor/mediatek/kernel_modules/gpu`: seluruh `mali_avalon/a16w`
  diganti donor OPPO (`475324b` di repo lokal; repo ini tidak punya
  remote `alps`).
- Dua dependency OPPO-only `oplus_bsp_mm_osvelte` dan
  `osvelte_public_headers` dihapus dari `midgard/BUILD.bazel`;
  `CONFIG_OPLUS_FEATURE_MM_OSVELTE` tidak aktif.
- `conditional_defines` GED hanya untuk `k6993v1_64`, dihapus karena
  skema build kita belum mendukung argumen itu.

Hasil build:
- `mali_kbase`: **r54p1-11eac0 (UK 1.38)**, sama dengan stock.
- `mtk_gpufreq_wrapper`: mengekspor `gpufreq_driver_ready`.
- `ged`: mengekspor `ged_dvfs_get_util_active/3d/ta/comp` yang dipakai
  Mali donor.

### Artefak (hanya vendor_dlkm)

```text
vendor_dlkm.img                 md5 72f7e6dae2c25e0274008e69c2cf7fd1
odm_dlkm.img (tidak berubah)    md5 0ffbb42985d445f7c12808df3b50960e
twrp-dlkm-gpufix-20261120.zip   md5 5ca615ac2b342f4430baba640168efe8
release                         dlkm-gpufix-20261120
```

Zip/flash hanya menulis `vendor_dlkm`; `odm_dlkm` tetap dari
`dlkm-20261120`. Boot setelah fix ini belum diuji.

## 48. dmesg3: shared-status gpufreq beda 8 byte dari stock

Setelah GPU donor OPPO dipasang, `dmesg3` tetap panic di
`kbase_backend_gpuprops_get()` dengan Mali **r54p1-11eac0** (versi stock).
Jadi versi Mali bukan penyebabnya.

Perbandingan getter `mtk_gpufreq_wrapper.ko` stock vs build kita:

| Getter | Offset stock | Offset kita | Selisih |
|---|---|---|---|
| `gpufreq_get_cur_temperature` | 0x38 | 0x30 | +8 |
| `gpufreq_get_cur_freq` | 0x50 | 0x48 | +8 |
| `gpufreq_get_cur_out_freq` | 0x58 | 0x50 | +8 |
| `gpufreq_get_cur_power` | 0x88 | 0x80 | +8 |
| `gpufreq_get_dvfs_state` | 0xdc | 0xd4 | +8 |
| `gpufreq_get_shader_present` | 0xe0 | 0xd8 | +8 |
| `gpufreq_get_segment_id` | 0x11c | 0x114 | +8 |
| `gpufreq_get_cur_oppidx` | 0x8 | 0x8 | sama |
| `gpufreq_get_opp_num` | 0x10 | 0x10 | sama |

Artinya `struct gpufreq_shared_status` stock punya **dua field 4-byte
tambahan**. GPUEB firmware menulis `shader_present` di 0xe0; wrapper
kita membacanya di 0xd8 (field lain yang bernilai 0), sehingga Mali
melihat `SW: 0x0` dan memanggil `BUG_ON(1)`. Posisi persis kedua field
dikoreksi di §48.1: keduanya berada **sebelum `power_count`**, bukan
setelah `active_count`.

### Perbaikan (kernel `974ef93c0c1f`)

Tambahkan dua field reserved di posisi yang sama. Setelah rebuild,
seluruh getter wrapper memakai offset stock (0x38/0x50/0x58/0x88/0xdc/
0xe0/0x11c). Ini bukan mematikan BUG; layout shared memory sekarang
sama dengan firmware stock.

### Artefak (hanya vendor_dlkm)

```text
vendor_dlkm.img                md5 f926ab750f16b1ef29002a336cf2eda9
odm_dlkm.img (tidak berubah)   md5 0ffbb42985d445f7c12808df3b50960e
twrp-dlkm-gpu2-20261121.zip    md5 8b211f609d6c9744d29fc89ee362510f
release                        dlkm-gpu2-20261121
```

Boot setelah fix ini belum diuji.

## 48.1 Koreksi §48: padding ada sebelum `power_count`

Perbaikan §48 menaruh dua field reserved setelah `active_count`. Itu
membuat semua field mulai `temperature` (0x38) selaras dengan stock,
tetapi **lima counter di depannya tetap meleset 8 byte**. Getter yang
menunjukkan hal ini adalah `gpufreq_get_power_state`:

```text
stock  b9402508  ldr w8, [x8, #0x24]
kita   b9401d08  ldr w8, [x8, #0x1c]     (setelah 974ef93c0c1f)
```

`gpufreq_status_proc_show` stock membaca counter untuk format
`PowerCount/Active/CG/MTCMOS/BUCK` di 0x24/0x34/0x30/0x2c/0x28. Jadi
layout stock adalah:

| field | offset stock | §48 (salah) | 07eb1dab07c2 |
|---|---|---|---|
| `reserved0` | 0x1c | 0x30 | 0x1c |
| `reserved1` | 0x20 | 0x34 | 0x20 |
| `power_count` | 0x24 | 0x1c | 0x24 |
| `buck_count` | 0x28 | 0x20 | 0x28 |
| `mtcmos_count` | 0x2c | 0x24 | 0x2c |
| `cg_count` | 0x30 | 0x28 | 0x30 |
| `active_count` | 0x34 | 0x2c | 0x34 |
| `temperature` | 0x38 | 0x38 | 0x38 |
| `shader_present` | 0xe0 | 0xe0 | 0xe0 |

Dua field 0x1c/0x20 hanya ditulis GPUEB; stock wrapper tidak punya
satu pun `str` ke offset itu, jadi field tersebut tetap dinamai
`reserved`.

### Perbaikan (kernel `07eb1dab07c2`)

Padding dipindah ke antara `signed_opp_num_stack` dan `power_count`.
Verifikasi terhadap `mtk_gpufreq_wrapper.ko` stock:

- seluruh getter shared-status memakai offset yang sama
  (0x24/0x28/0x2c/0x30/0x34/0x38/0xdc/0xe0/0x11c);
- `gpufreq_get_power_state` **byte-identik** dengan stock;
- 88 dari 99 fungsi yang sama byte-identik. Sisa 11 berbeda karena
  virtual OPP table, tabel histori, dan CFI pada jalur `fix_*`, bukan
  layout shared status (offset shared-status di
  `gpufreq_status_proc_show` juga identik).

### Artefak (hanya vendor_dlkm)

```text
vendor_dlkm.img               md5 d68e9a2b95c56e3e0cac17143b1dd412
odm_dlkm.img (tidak berubah)  md5 0ffbb42985d445f7c12808df3b50960e
twrp-dlkm-gpu3-20261121.zip   md5 28b43f8b8c169289a1d4451a7d43ac14
release                       dlkm-gpu3-20261121
```

Zip TWRP hanya menulis `vendor_dlkm`. Boot system setelah fix ini belum
diuji.

## 49. dmesg4: Android boot sampai launcher + Wi-Fi; spam battery OC & mode switch panel

Dengan `dlkm-gpu3-20261121`, **Android berhasil boot penuh** (userspace,
Mali r54p1-11eac0, Wi-Fi, touch, haptic, charger hidup melewati `t=109 s`).
Dua masalah ditemukan dari `dmesg4.txt` dan pengamatan layar:

### 49.1 Spam log 65 Hz (`mtk_battery_oc_throttling` + `mt6375-battery`)

21.696 dari 26.223 baris (~83%) dalam 37 detik adalah osilasi IRQ
over-current baterai (`battery_oc_level=1 <-> 0`, `md_pt_over_current_cb`,
dan `ocp81375_*` PT disable) yang menimpa awal ring buffer (`dmesg4.txt`
baru mulai di `t=72,66 s`).

Akar masalah (DT `merged.dts` + RE biner stock):
- DT X6871 mengisi `r-fg-value = <50>` (sudah ×10 = 5,0 mΩ) dan properti
  Transsion `rfg-mtk-tran-conf-diff = <15>`.
- Stock `mtk_battery_oc_throttling.ko` (`battery_oc_parse_dt`) dan
  `mt6375-battery.ko` (`fg_custom_init_from_dts`) sama-sama membaca
  `rfg-mtk-tran-conf-diff` (default 15) dan hanya mengalikan
  `r_fg_value *= 10` bila `r_fg_value < r_fg_diff`.
- Driver kita mengalikan tanpa syarat (`50 * 10 = 500`), sehingga
  `to_fg_code()` overflow 16-bit dan memprogram threshold OC yang salah
  (IRQ ping-pong 65 Hz), sementara gauge melaporkan arus 10× terlalu kecil
  (`I=-69`).

Perbaikan:
- Kernel `8d38cd08a65c`: hormati `rfg-mtk-tran-conf-diff` di
  `mtk_battery_oc_throttling.c` (`battery_oc_parse_dt` 305 == 305 instruksi
  dengan stock).
- Kernel `0f7ce1ce8f7e`: hormati `rfg-mtk-tran-conf-diff` di
  `mtk_battery.c` (`mt6375-battery.ko`).

### 49.2 Layar setengah kanan pink: bug timing & mode switch 120/60 Hz panel

TWRP selalu bertahan di mode 0 (144 Hz), sedangkan Android SurfaceFlinger
berpindah-pindah antara mode 1 (120 Hz) dan mode 2 (60 Hz). Perbandingan
`panel-rm69220-vdo-x6871.ko` kita dengan stock
`rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.ko`:

- Mode 120 Hz kita memakai `clk=336660, HFP=24, VFP=40` (stock:
  `clk=368928, HFP=120, VFP=64`).
- Mode 60 Hz kita memakai `clk=168330, HFP=24, VFP=40` sehingga `mmclk`
  turun ke 88 MHz (< `pixclk_min=193`; stock: `clk=368928, HFP=120,
  VFP=2584`). Mode 40 Hz (`clk=368732, HFP=120, VFP=5100`) belum ada.
- `change_fps_by_vfp_send_cmd` sebelumnya 0 (stock: 1); `mode_switch` kita
  mengirim `0x2F 0x05` untuk 144 Hz dan `0x2F 0x00` untuk 120 Hz
  (**terbalik** dari stock) tanpa page select `{0xFE, 0x00}`, dan
  `cmd_null_pkt_len` diset 400/700 (sisa panel CMD; stock: 0 di semua mode).

Perbaikan (kernel `e6d0ab2fb66a`):
- Pasang 4 `drm_display_mode` persis stock (`144/120/60/40 Hz`, diverifikasi
  **byte-identik** dengan `.rodata` stock).
- Aktifkan `change_fps_by_vfp_send_cmd = 1` + `dyn_fps.dfps_cmd_table`
  (`{0xFE, 0x00}` lalu `{0x2F, 0x00 / 0x05 / 0x06}`), `cmd_null_pkt_len = 0`,
  tabel QP 8bpc persis stock, dan hapus callback `mode_switch`/`ext_param_get`
  non-stock.

Catatan: bila setelah fix ini separuh kanan layar masih pink, `dmesg` dari
`t=0 s` (yang sekarang bebas spam OC) akan dipakai untuk memeriksa jalur
dual-pipe PQ (`disp_c3d`/`disp_ccorr`/`disp_gamma` di `mediatek_drm_v1.ko`).

### Artefak (ketiga partisi terdampak modul yang diubah)

- `vendor_dlkm`: `mtk_battery_oc_throttling.ko`
- `odm_dlkm`: `mt6375-battery.ko` (boot normal Android memuatnya dari
  `odm_dlkm`, bukan `vendor_boot`)
- `vendor_boot`: `panel-rm69220-vdo-x6871.ko` + `mt6375-battery.ko`

```text
twrp-vendor_boot-allsrc-display-usb-v2.img  md5 e3a1fbe803361749d7fd28f1049d1ffa  67.108.864 B
vendor_dlkm.img                             md5 ec627a474d09bb3303408e52211b6437  24.551.424 B
odm_dlkm.img                                md5 c2c312b3374ebdb0e835db396663e924   4.206.592 B
twrp-dlkm-ocfix-20261121.zip                md5 6fce24575faacd85164de86fc775495a
release                                     dlkm-ocfix-20261121
```

## 50. dmesg5: spam OC hilang 100%, akar layar setengah kanan pink/hijau = C3D dual-pipe SRAM (`mediatek_drm_v1.ko`)

Dengan `dlkm-ocfix-20261121`, spam IRQ OC 65 Hz hilang total (`battery_oc_level
count: 0`, `r_fg=50 car_tune=1000 DEFAULT_RFG=50`), dan `dmesg5.txt` merekam
sejak `t=5,02 s`. Layar setengah kanan berganti warna dari **pink** (`dmesg4`)
menjadi **hijau** (`dmesg5`) — ciri khas SRAM belum terinisialisasi pada
right pipe (`mt6895` dual-pipe: kiri 540px = `C3D0`, kanan 540px = `C3D1`).

Dua baris penentu di `dmesg5.txt`:

```text
[   14.702534] [DISP]mtk_drm_ioctl_pq_proxy cmd 900 usize 12, ksize 128 not match!
[   14.715977] disp_c3d_flip_3dlut_sram: sram_apb = sram_int = 0, skip flip!
```

### 50.1 C3D right pipe tidak pernah dicek/di-flip (`v1/mtk_disp_c3d.c`)

- Di `drivers/gpu/drm/mediatek/mediatek_v2/v1/mtk_disp_c3d.c` baris 509,
  `disp_c3d_set_3dlut()` hanya memanggil `disp_c3d_check_sram(comp, true)`
  untuk `C3D0` (left pipe), tidak pernah untuk `comp_c3d1` (`C3D1`, right
  pipe).
- Padahal disassembly `disp_c3d_cfg_set_lut` pada `mediatek_drm_v1.ko` stock
  memanggil `disp_c3d_check_sram` **dua kali** (`0x1b1e4` untuk `comp`,
  `0x1b204` untuk `comp_c3d1`, lalu `and w8, w25, w0`).
- Tanpa `disp_c3d_check_sram(comp_c3d1, true)`, `C3D1` tetap pada
  `sram_apb == sram_int == 0` (bukan ping-pong), sehingga
  `disp_c3d_flip_3dlut_sram(comp_c3d1)` mencetak `skip flip!` dan keluar.
  Ketika `disp_c3d_bypass(comp, 0)` melepas relay kedua pipe, `C3D0` memakai
  3D LUT valid sedangkan `C3D1` membaca bank SRAM power-on acak → separuh
  kanan layar pink/hijau.
- Cek donor 6.1 (`mt6897`): masih memakai `disp_c3d_update_sram()` lama per
  pipe, sehingga regresi ini khusus hasil refactor 6.12 di `v1/mtk_disp_c3d.c`.

Perbaikan (kernel `1799bf13b78b`): panggil `disp_c3d_check_sram(comp_c3d1, true)`
tanpa short-circuit ketika `is_dual_pipe && comp_c3d1` lalu gabungkan hasilnya.
Verifikasi disassembly `disp_c3d_cfg_set_lut` hasil build: dua panggilan
`bl <disp_c3d_check_sram>` (`0x50d54` dan `0x50d78`), cocok dengan stock.

### 50.2 Ukuran `PQ_VIRTUAL_SET_PROPERTY` (`v1/mtk_disp_pq_helper.c`)

- Userspace dan stock `mediatek_drm_v1.ko` memakai `12` byte (`3 * u32` =
  `DISP_PQ_PROPERTY_MAX`) untuk `cmd 900` (`PQ_VIRTUAL_SET_PROPERTY`),
  sedangkan `v1/mtk_disp_pq_helper.c` memakai `sizeof(unsigned int) * 32`
  (128 byte).
- Perbaikan (kernel `e84137d0e2aa`): pakai `DISP_PQ_PROPERTY_MAX` di
  `g_pq_cmd_map` dan buffer lokal `disp_pq_proxy_virtual_get_persist_property`.
  Verifikasi `.rodata` `g_pq_cmd_map`: `cmd 900` = `(12, 1)` identik stock.

Catatan: `WARNING: rcu_note_context_switch` di `t=26,268 s` berasal dari modul
eksternal `susfs_guard_lkm` (`sus_mount_learn_work`), bukan modul build kita.

### Artefak (hanya `vendor_boot`, karena `mediatek_drm_v1.ko` hanya di `vendor_boot`)

```text
twrp-vendor_boot-allsrc-display-usb-v3.img  md5 c4362d3312ab41356bc6eb2cc6f509b8  67.108.864 B
release                                     vendor-boot-c3dfix-20261121
```

`vendor_dlkm.img` dan `odm_dlkm.img` dari `dlkm-ocfix-20261121` tidak berubah.
**Hasil uji:** layar normal penuh (separuh kanan tidak lagi pink/hijau).

## 51. Port driver kamera X6871 (`imgsensor.ko` + `camera_eeprom_v4l2.ko`)

Dari `dmesg5.txt`, keempat sensor DT X6871 gagal probe (`not found`) dan kedua
EEPROM kamera gagal dengan `-EINVAL` (`-22`):

```text
imgsensor 2-0010: [search_sensor] gc02m3macro_mipi_raw not found
imgsensor 4-004a: [search_sensor] gc32e1_mipi_raw not found
imgsensor 8-0010: [search_sensor] gc02m3_mipi_raw not found
imgsensor 9-0010: [search_sensor] s5khm6sx_mipi_raw not found
mediatek,camera_eeprom 4-0051: probe ... failed with error -22
mediatek,camera_eeprom 9-0050: probe ... failed with error -22
```

### 51.1 Empat subdriver sensor (`imgsensor.ko`)

- **ID & nama sensor** di `kd_imgsensor.h` (kernel `75ca1ac4a1ae`):
  - `S5KHM6SX_SENSOR_ID = 0x1AD6` (`s5khm6sx_mipi_raw`, i2c9 `@0x10`)
  - `GC32E1_SENSOR_ID = 0x32E1` (`gc32e1_mipi_raw`, i2c4 `@0x4A`)
  - `GC02M3_SENSOR_ID = 0x0202` (`gc02m3_mipi_raw`, i2c8 `@0x10`)
  - `GC02M3MACRO_SENSOR_ID = 0x0203` (`gc02m3macro_mipi_raw`, i2c2 `@0x10`)
- Tiga subdriver (`s5khm6sx_mipi_raw`, `gc32e1_mipi_raw`, `gc02m3macro_mipi_raw`)
  diport dari donor 6.1 `mt6897` (`vendor/mediatek/kernel_modules/mtkcam/imgsensor/src-v4l2/common/`),
  ditambah helper `i2c_table_cntinuburst_write()` di `adaptor-subdrv-ctrl.c/.h`
  (burst write I2C 252 byte untuk tabel init S5KHM6SX).
- `gc02m3_mipi_raw` diturunkan dari `gc02m3macro_mipi_raw` setelah verifikasi
  biner `imgsensor.ko` stock:
  - `pw_seq` dan tabel init identik (baris `(0x0100, 0x00)` sudah dikomentari);
  - `get_imgsensor_id` stock `gc02m3` (`0x3a3bc..0x3a3c8`) memakai
    `(*sensor_id & 0xFFFC) == 0x0200` agar chip GC02M3 (`0x0203`) cocok di slot
    `gc02m3_mipi_raw` (`0x0202`).
- Verifikasi biner `imgsensor.ko` hasil build: keempat `*_mipi_raw_entry` ada
  dengan ID `0x1ad6`/`0x32e1`/`0x202`/`0x203` dan `i2c_table_cntinuburst_write`
  terkompilasi.

### 51.2 `camera_eeprom_v4l2.ko`

- `eeprom_driver.c`: prefix DT kita `"camera-eeprom"` (tanda hubung), sedangkan
  DT X6871 & stock memakai `"camera_eeprom"` (`camera_eeprom0@50`,
  `camera_eeprom1@51`), sehingga `retrieve_index()` mengembalikan `-EINVAL`.
  Diperbaiki agar menerima keduanya (`"camera_eeprom"` dan `"camera-eeprom"`).
- `cam_cal_list.c`: tambahkan entri stock `g_camCalList`:
  - `{GC32E1_SENSOR_ID, 0xA2, Common_read_region, MAX_EEPROM_SIZE_16K}`
  - `{S5KHM6SX_SENSOR_ID, 0xA0, Common_read_region, MAX_EEPROM_SIZE_16K}`
- Reproduksibilitas: `add-camera-x6871.sh` +
  `tools/patches/mtkcam-x6871-camera.patch` di repo manifest (karena
  `vendor/mediatek/kernel_modules/mtkcam` memakai remote `moto`).

### Artefak (hanya `vendor_dlkm`)

```text
vendor_dlkm.img              md5 bfd96feb71d3f53fcc0c045b896809e6  24.551.424 B
twrp-dlkm-cam1-20261121.zip  md5 41e402b08f61576e1a5acd6e0622b188
release                      dlkm-cam1-20261121
```

`vendor_boot` (`v3`) dan `odm_dlkm` (`ocfix`) tidak berubah.

## 52. Fix `dmesg6`: Audio (FS1599 + `mt6895-mt6368`), AOD/screen-on (`panel-rm69220-vdo-x6871`), dan Camera ISP ABI (`mtk-cam-isp`)

Hasil uji `vendor-boot-c3dfix-20261121` + `dlkm-cam1-20261121` (`dmesg6.txt`):
layar utama normal, `s5khm6sx_mipi_raw` sudah probe dan dipanggil userspace,
namun ada tiga keluhan baru: **audio mati**, **AOD rusak lalu layar tidak mau
menyala lagi**, dan **kamera masih gagal**.

### 52.1 Audio (`tran_audio_control.ko` + `mt6895-mt6368.ko`, `vendor_dlkm`)

- `adspsys@1e000000` berstatus `disabled` di DT X6871, sehingga
  `adsp_system_bootup fail ret(-14)` adalah normal. Dual speaker PA
  `foursemi,fs15xx` (`6-0034`, `6-0035`) sudah probe lewat `snd-soc-fs1599.ko`.
- Dua mata rantai yang hilang dibandingkan stock:
  1. `sound/soc/transsion/tran_audio_control/BUILD.bazel` belum mendefinisikan
     `CONFIG_SND_SOC_FS1599=1` dan `ko_deps` ke `snd-soc-fs1599`, sehingga
     seluruh callback PA di `tran_audio_control.ko` terkompilasi kosong.
     Fix: kernel `7aa967a7ba5a`. Verifikasi simbol `tran_audio_control.ko`:
     mengimpor `fsm_add_card_controls`, `fsm_set_scene`, `fsm_speaker_off`,
     `fsm_speaker_onn` (identik stock).
  2. `sound/soc/mediatek/mt6895/mt6895-mt6368.c` + `BUILD.bazel` belum
     memanggil `tran_audio_add_card_controls(card)` sesudah
     `devm_snd_soc_register_card()` dan `tran_audio_pa_switch(true/false)` di
     `mt6895_mt6368_spk_amp_event()`.
     Fix: kernel `b86a4c8cdca3`. Verifikasi simbol `mt6895-mt6368.ko`:
     mengimpor `tran_audio_add_card_controls` dan `tran_audio_pa_switch`
     (identik stock).

### 52.2 AOD / layar tidak mau menyala lagi (`panel-rm69220-vdo-x6871.ko`, `vendor_boot`)

- Disassembly stock `rm69220_fhdp_dsi_vdo_dsc_csot_csot_144hz_x6871.ko`
  (`panel_doze_enable` `0x196c`, `panel_doze_disable` `0x19d8`,
  `panel_set_aod_light_mode` `0x1598`) menunjukkan stock **tidak** mengirim
  perintah idle-mode `0x39`/`0x38` saat masuk/keluar doze (hanya menyetel
  `g_aod_enable = 1/0`); mengirim `0x39` mengunci panel VDO sehingga gagal
  bangun dari AOD.
- `panel_set_aod_light_mode()` stock mengirim `{0xFE, 0x00}` lalu
  `{0x51, hi, lo}` dengan tier kecerahan `1..99 -> 0x03e`,
  `100..299 -> 0x057`, lainnya `0x158`.
- Fix: kernel `a765870ac11f`. Verifikasi disassembly `panel-rm69220-vdo-x6871.ko`:
  0 panggilan `push_table_cb` di `panel_doze_enable`/`panel_doze_disable`.

### 52.3 Camera ISP ABI (`mtk-cam-isp.ko`, `vendor_dlkm`) & temuan `s5khm6sx`

- Di `dmesg6.txt`: `mtk_cam_res_copy_fmt_from_user: copy_from_user on sink_fmt
  failed (48)` disertai garbage `raw_res` dan warning vb2 `plane size is too
  small`. Disassembly `mtk-cam-isp.ko` stock (`cfg_res_ctrl` +
  `mtk_cam_raw_res_store`) menunjukkan `sizeof(struct mtk_cam_resource)` stock
  adalah `0x68` (bukan `0x60`), dengan field `interval` di `+0x0c`,
  `pixel_rate` di `+0x20`, `raw_res.feature` di `+0x38`, `hw_mode` di `+0x50`.
- Fix (`vendor/mediatek/kernel_modules/mtkcam/include/mtk_camera-v4l2-controls.h`,
  direkam di `tools/patches/mtkcam-x6871-camera.patch`): tambah `__u32 reserved;`
  di awal `struct mtk_cam_resource_sensor`. Verifikasi biner `mtk-cam-isp.ko`:
  `cfg_res_ctrl.elem_size == 0x68` (identik stock).
- **Temuan lanjutan (kamera belakang 108MP `s5khm6sx_mipi_raw`)**:
  - `s5khm6sx` dari donor 6.1 (baik `common/` maupun `camera_project/tran_x6873/`)
    menggunakan **C-PHY 3-lane** (`MIPI_CPHY`, `SENSOR_MIPI_3_LANE`), yang
    menghasilkan `SENINF4_PkCnt(0x0)` (0 paket, watchdog timeout) dan
    `check_stream_off: stream off fail!`.
  - Disassembly `imgsensor.ko` stock (`s5khm6sx` `get_info` `0x521d8` +
    `.data+0x40380`) membuktikan `s5khm6sx` stock X6871 memakai **D-PHY 4-lane**
    (`MIPI_OPHY_NCSI2`, `SENSOR_MIPI_4_LANE`, `SensorMIPILaneNumber = 4`).
  - Kamera depan (`gc32e1_mipi_raw`) dan macro/depth (`gc02m3*`) sudah D-PHY,
    sehingga siap diuji setelah fix `mtk-cam-isp.ko`; kamera belakang 108MP
    `s5khm6sx` masih membutuhkan tabel register D-PHY 4-lane di iterasi berikut.

### Artefak (hanya `vendor_boot` v4 + `vendor_dlkm`; `odm_dlkm` tidak berubah)

```text
twrp-vendor_boot-allsrc-display-usb-v4.img  md5 85d6451c42478fc83bf12ea77af9fba5  67.108.864 B
vendor_dlkm.img                             md5 e6218bbd27315969523d637e91fe0396  24.551.424 B
twrp-dlkm-audio-cam2-20261121.zip           md5 e35bed55b35c613e801935ec39151947
release                                     audio-aod-cam2-20261121
```

**Hasil uji (`dmesg7.txt`):** Audio dan AOD/screen-on **FIXED**.

## 53. Fix `dmesg7`: Camera (`mtk-cam-isp` inline `sink_fmt` + `s5khm6sx` D-PHY 4-lane), Flashlight (`flashlight-core`), dan DT2W/FOD Touch (`adaptive-ts` + `gt9916_common`)

1. **Camera ISP ABI (`mtk-cam-isp.ko`, `vendor_dlkm`)**:
   - Di `dmesg7.txt`, `mtk_cam_raw_res_store` sudah membaca parameter sensor secara
     bersih (`6219/1864/1492114286/0/300/10`), namun `mtk_cam_res_copy_fmt_from_user`
     masih gagal dengan `(48)` karena disassembly `mtk_raw_try_ctrl` (`0x21860`) &
     `mtk_raw_s_ctrl` (`0x21bf0`) stock menunjukkan `struct mtk_cam_resource`
     **tidak** memakai pointer `struct v4l2_mbus_framefmt *sink_fmt`; tiga field
     awal (`+0x00`, `+0x04`, `+0x08`) adalah `width`, `height`, `code` inline di
     `struct mtk_cam_resource_sensor`.
   - Fix (`mtk_camera-v4l2-controls.h` + `mtk_cam-raw.c`, terekam di
     `tools/patches/mtkcam-x6871-camera.patch`): ganti `sink_fmt` pointer dengan
     `width`/`height`/`code` inline (tetap `sizeof == 0x68`). Verifikasi biner
     `mtk-cam-isp.ko`: 0 string `copy_from_user on sink_fmt`.
2. **Kamera belakang 108MP `s5khm6sx_mipi_raw` D-PHY 4-lane (`imgsensor.ko`, `vendor_dlkm`)**:
   - Ekstrak seluruh 32 tabel register D-PHY 4-lane `*hm6*` (`addr_data_pair_init_hm6_*`,
     `init_data_hm6_*`, `fmc_init_data_hm6`, `pre`/`cap`/`video`/`hs`/`slim`/`cus1..3`
     plus varian `sf_*`) dari biner stock `imgsensor.ko` ke `s5khm6sx_Sensor_setting.h`.
   - Ubah `s5khm6sxmipiraw_Sensor.c` ke `MIPI_OPHY_NCSI2`, `SENSOR_MIPI_4_LANE`,
     `mipi_pixel_rate = 953600000`, dan urutan `s5khm6sx_sensor_init()` identik stock.
3. **Flashlight (`flashlight.ko`, `vendor_dlkm`)**:
   - Di `dmesg7.txt`, `ocp81375_ioctl` menolak perintah `110`/`130`/`131`/`210`/`225`/`251`
     karena `flashlight-core.c` masih versi MTK polos (mengirim `FLASH_IOC_SET_DUTY`),
     sedangkan `ocp81375_v4l2.ko` memakai `FLASH_IOC_SET_CURRENT` (`21`) dari
     `flashlight-core.c` Transsion.
   - Fix (kernel `1d3f17a21434`): port `flashlight-core.c`, `flashlight-core.h`,
     `flashlight.h`, `tran_flash_custom.h` dari donor 6.1 `mt6897` +
     `CONFIG_TRAN_FLASHLIGHT_TELE_SUPPORT=1`. Verifikasi simbol `flashlight.ko`:
     `fl_set_current`, `torch_level_store`, `sub_torch_level_store`,
     `tele_torch_level_store`, `sysfs_strobe_store`.
4. **DT2W & FOD-touch (`adaptive-ts.ko` + `gt9916_common.ko`, `odm_dlkm`)**:
   - Di `dmesg7.txt`, `goodix_ts_suspend()` masuk deep sleep tanpa mode gesture
     karena `gt9916_common` tidak memiliki `goodix_ts_gesture.c` maupun
     `/proc/fingerprint_status`, dan `adaptive-ts` tidak membuat proc node gesture.
   - Fix (kernel `466e4c1731c1`): tambah proc node `main_gesture_function`,
     `main_gesture_state`, `main_gesture_flag`, `gesture_function`, `gesture_state`,
     `gesture_flag`, `touch_gesture` di `adaptive-ts`, serta `goodix_ts_gesture.c`
     (`KEY_WAKEUP` untuk double-tap `0xCC`/single-tap `0x4C`, FOD `0x46`/`0x55`,
     `/proc/fingerprint_status`, `enable_irq_wake`) di `gt9916_common`.

### Artefak (hanya `vendor_dlkm` + `odm_dlkm`; `vendor_boot` v4 tetap)

```text
vendor_dlkm.img                   md5 48d318d18e95b43c700774f6fce06169  24.551.424 B
odm_dlkm.img                      md5 96af18e1bdb9f2eaafa648f28902cfa8   4.206.592 B
twrp-dlkm-cam3-dt2w-20261121.zip  md5 43e64846fc2b332b37dda65bf69a29db
release                           dlkm-cam3-dt2w-20261121
```

**Hasil uji (`dmesg8.txt` + `logcat1.txt`):** Foto kamera & flashlight **WORKING**.

## 54. Fix `dmesg8`/`logcat1`: Video kamera (`s5khm6sx` `4000x2248`), FOD (`tran_fp` `goodix_opt_tee`), dan DT2W/FOD keycodes (`190`/`195`/`198`)

1. **Kamera video hang (`s5khm6sx_mipi_raw` di `imgsensor.ko`, `vendor_dlkm`)**:
   - Di `dmesg8.txt` (`t=80,888 s`), switch ke mode video (`sid:2`) mengatur
     `SENINF` ke `4000x2252` (donor 6.1), sedangkan tabel register stock
     `addr_data_pair_video_hm6` mengeluarkan `4000x2248` (beda 4 baris,
     sehingga frame ditolak/hang).
   - Fix (`s5khm6sxmipiraw_Sensor.c`, terekam di `mtkcam-x6871-camera.patch`):
     samakan `frame_desc_vid` (`4000x2248`, PDAF `2000x1124`), `WINSIZE_INFO_VID`
     & `mode_struct[2]` (`4000x2248`), `hs_video` (`1920x1080`, `ll=5728`,
     `fl=2384`, `120 fps`), `slim_video` (`ll=5728`, `fl=1192`, `240 fps`), dan
     `custom3` 108MP (`ll=22200`, `fl=9228`, `8 fps`) dengan `imgsensor_info_struct`
     stock.
2. **FOD Fingerprint (`tran_fp.ko`, `vendor_boot` v5)**:
   - `logcat1.txt` menampilkan `vendor.fingerprint.init.error` saat boot dan
     `AcquisitionClient: onErrorInternal code: 8` (`FINGERPRINT_ERROR_VENDOR`).
   - Disassembly `tran_get_fp_sensor_chip_id` di `tran_fp.ko` stock menunjukkan
     `/sys/kernel/tran_fp/vendor_name` harus berisi **`goodix_opt_tee`** untuk
     sensor optikal FOD (`GW9578`/`GW9598`) dan **`goodix_tee`** untuk
     kapasitif (`GF3956`/`GF3976`/`GF3986`), bukan `common_goodix`.
   - Fix (kernel `6432a8d60ee7`): perbarui `setVendorName()` di `tran_fp_ext.c`
     ke nama TEE stock (`goodix_opt_tee`, `goodix_tee`, `silead_opt_tee`,
     `anc_opt_tee`, `focaltech_tee`).
3. **DT2W & FOD Touch (`gt9916_common.ko`, `odm_dlkm`)**:
   - Disassembly `GestureHandle` di `adaptive-ts.ko` stock membuktikan Android
     Transsion mendengarkan keycode **`190` (`0xbe`)** untuk double-tap to wake,
     **`195` (`0xc3`)** down/up untuk FOD (`0x46`/`0x55`), dan **`198` (`0xc6`)**
     untuk single-tap (`0x4c`) — bukan `KEY_WAKEUP` (`143`).
   - Selain itu `gsx_gesture_ist` gagal baca SPI pertama sesaat bangun tidur
     (`failed get gesture data`).
   - Fix (kernel `831ee7ca4762`): daftarkan bit `190`/`195`/`198` di
     `input_dev->keybit`, kirim keycode stock tersebut di `gsx_gesture_ist`, dan
     tambahkan `pm_wakeup_event(2000)` + 5x retry (`msleep(10)`).

### Artefak (`vendor_boot` v5 + `vendor_dlkm` + `odm_dlkm`)

```text
twrp-vendor_boot-allsrc-display-usb-v5.img  md5 6b9db37f101262c220696321d5fda896  67.108.864 B
vendor_dlkm.img                             md5 fabc4903098905d793af5cc7985608f0  24.551.424 B
odm_dlkm.img                                md5 5add223fe6599a2014de88e6c7e45166   4.206.592 B
twrp-dlkm-cam4-fod-dt2w-20261121.zip        md5 0605a3b4529ef7640436fa4a39893cac
release                                     cam4-fod-dt2w-20261121
```



## 55. Fix `dmesg9`/`logcat2`: layar separuh hijau permanen (C3D), video tidak tersimpan (`mtk-vcodec-enc`), flashlight, DT2W

Status uji user sebelum fix: foto OK, video tidak hang tapi tidak tersimpan, flashlight dan DT2W masih rusak, layar separuh hijau muncul lagi sesekali (hilang setelah 2x reboot).

1. **Layar separuh hijau intermiten** (`mediatek_drm_v1.ko`, `vendor_boot` v6):
   - `mediatek_drm_v1.ko` dan `panel-rm69220-vdo-x6871.ko` byte-identik antara v4 dan v5, jadi penyebabnya race runtime.
   - `disp_c3d_cfg_set_lut()` mengabaikan return `disp_c3d_set_3dlut()` (yang mengembalikan `false`=0 saat `disp_c3d_check_sram()` gagal) lalu tetap un-bypass C3D0/C3D1 saat SRAM C3D1 kanan belum init. Stock hanya un-bypass bila return 0.
   - Fix (kernel `d46c6e7de494`): `disp_c3d_set_3dlut()` mengembalikan `-EAGAIN`; `disp_c3d_cfg_set_lut()` hanya un-bypass dan set `c3d_sram_hw_init` bila ret == 0.
2. **Video tidak tersimpan** (`mtk-vcodec-enc.ko`): dmesg9 menunjukkan `mtk_venc_encode_header: venc_if_encode failed=0` (`enc_result.bs_va == 0`). Pembandingan disassembly `venc_vcp_set_param` stock vs source: offset field `struct venc_vsi`/`venc_vcu_config` bergeser 16 byte setelah `max_qp`. Di stock `max_qp` dan `min_qp` adalah array `[3]`, di source skalar. Fix (`79cacb884584`): ubah ke `__u32 max_qp[3]; __u32 min_qp[3]` dan isi ketiga elemen di `venc_vcp_if.c` + `venc_common_if.c`. Offset `0xaf0/0xaf8` pada `venc_vcp_encode` kini sama dengan stock.
3. **Flashlight** (`ocp81375_v4l2.ko`): nama subdev stock `ocp81375_v4l2-led0/-led1(-f)` dan prefix log `ocp81375_v4l2`; `FLASH_IOC_IS_CHARGER_READY` (210) kini ditangani (sebelumnya `No such command`). Fix `b2de4bc7507e`. Belum terbukti menghilangkan `Find no flashlight device`; perlu verifikasi di perangkat.
4. **DT2W** (`adaptive-ts.ko`, `gt9916_common.ko`): disassembly `GestureHandle` stock: keycode `190` (`0xbe`) = single-tap, `198` (`0xc6`, `KEY_F26`) = gestur double-tap/`0xcc`, `195` = FOD. Rilis sebelumnya menukar 190 dan 198. `/proc/gesture_function` stock mengembalikan karakter gestur (`0xcc` -> `f`); kini diimplementasikan lewat `tran_gesture_set_code()`. Fix `3c5e64704b34`. Log dmesg9 mulai t=211s sehingga siklus suspend/tap belum terlihat; perlu dmesg penuh dari t=0.
5. **FOD** (`tran_fp`): tidak diubah; `vendor.fingerprint.init.error` masih ada di logcat2. Perlu bandingkan `tran_fp_probe`/`tran_fp_ioctl` dengan stock.

### Artefak (`vendor_boot` v6 + `vendor_dlkm` + `odm_dlkm`)

```text
twrp-vendor_boot-allsrc-display-usb-v6.img  md5 993a8cfe970e9b8a21a4e61ed9d229a9  67.108.864 B
vendor_dlkm.img                             md5 78a047fe3de5541abd3a956862862552  24.551.424 B
odm_dlkm.img                                md5 67af71ce2301af658b94f445257b054a   4.206.592 B
twrp-dlkm-vid-fl-dt2w5-20261121.zip         md5 4d188e48956d0fd698083a7dc6b83ae9
release                                     vid-fl-dt2w5-20261121
```
