# PRETEST — simulasi & perbandingan sebelum boot X6871

Dibuat 2026-11-19. Kernel `w1vo36-6.12-port` HEAD **`6334ce2b9910`**.
Empat modul fitur: `tran_extcon_usb`, `tran_fp`, `tnek`, `tkv`.

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

## 24. Set dlkm 100% source (siap untuk repack nanti)

Selain vendor_boot TWRP, set modul untuk `vendor_dlkm` + `odm_dlkm`
disiapkan di `/serverhive1/ramabondanp/tmp/dlkm-src`. Isinya **269 modul,
semuanya dari staging build kita**.

Modul stock yang dikeluarkan (25):

- 10 hardware yang tidak ada di DT X6871 (sengaja tidak diport):
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

Catatan: partisi dlkm (`vendor_dlkm`/`odm_dlkm` di `super`) belum
di-repack. Set ini adalah bahan siap pakai untuk tahap itu; boot system
belum diuji.

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
