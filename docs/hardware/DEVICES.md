# Tabel perangkat X6871 (dari DTBO + base DTB)

Sumber: hasil decompile DT yang dipakai X6871.

```text
base DTB : ~/tmp/x6871/base.dts
overlay  : ~/tmp/x6871/frag0.dts   (dtbo.img, fragment@0-73)
```

Kolom **Asal** dihasilkan otomatis:

| Asal | Arti |
|---|---|
| `source` | ada modul `.ko` hasil build kita yang mengklaim compatible ini (alias `of:` cocok) |
| `**stock**` | hanya modul stock yang mengklaim; source kita belum punya |
| `built-in` | driver ada di source tapi di-link ke kernel (tidak ada `.ko`) |
| `node platform` | node DT murni (syscon/simple-mfd) atau hanya dideklarasikan di `.dtsi` |
| `**MISMATCH**` | stock punya `of_match` ini, build kita tidak -> driver **tidak akan bind** |
| `tidak ada` | tidak ada driver, baik di source maupun di modul |

## Cara regenerasi

Contoh ini mereproduksi snapshot KMI 5 dengan dump DT dan direktori modul
lokal; input tersebut tidak disertakan di repo. Untuk memetakan build lain,
sesuaikan `W`, `KD`, dan direktori modul dengan artefak yang ingin diaudit.
Tabel ini memetakan driver, bukan hasil uji runtime (lihat [riwayat hasil uji](../archive/6.12/HANDOFF-HISTORY.md)).

```sh
cd ~
M=x6871-kernel-manifest/tools
W=w1vo  # workspace kernel untuk snapshot ini; sesuaikan dengan checkout lokal
L=tmp
KD=6.12.38-android16-5-g2c4fd33ae6d8-4k
mkdir -p cmp-out

# 1. node DT -> compatible
./$M/dts-devices.py tmp/x6871/base.dts tmp/x6871/frag0.dts > cmp-out/devices-raw.tsv
cut -f2 cmp-out/devices-raw.tsv | tr '|' '\n' | sort -u > cmp-out/allcompat.txt

# 2. compatible -> modul (alias of: di .ko)
./$M/dt-compat-map.py $L/twrp-src/lib/modules/$KD \
    $L/dlkm-src/vendor_dlkm/lib/modules/$KD \
    $L/dlkm-src/odm_dlkm/lib/modules/$KD \
    $L/twrp-set2/lib/modules/$KD \
    $L/stock-dlkm/vendor_dlkm/lib/modules \
    $L/stock-dlkm/odm_dlkm/lib/modules > cmp-out/compat-map.tsv

# 3. compatible -> berkas sumber
./$M/compat-source-index.py cmp-out/allcompat.txt \
    $W/kernel_device_modules-6.12 $W/kernel-6.12 $W/vendor/mediatek/kernel_modules \
    > cmp-out/compat-src.txt
./$M/compat-source-index.py cmp-out/allcompat.txt \
    $W/kernel_device_modules-6.12 $W/kernel-6.12 $W/vendor/mediatek/kernel_modules \
    --ext .dtsi,.dts > cmp-out/compat-dtsi.txt

# 4. berkas sumber -> nama modul
./$M/src-to-module.py $W/kernel_device_modules-6.12 \
    $W/vendor/mediatek/kernel_modules > cmp-out/src-module.tsv

# 5. susun tabel
./$M/dt-device-table.py cmp-out/devices-raw.tsv cmp-out/compat-map.tsv \
    cmp-out/compat-src.txt cmp-out/src-module.tsv cmp-out/compat-dtsi.txt
```

## Ringkasan

Node dengan `compatible` dan status `okay`: **978**. Sebaran:

```text
module=470, dt=371, builtin=130, ?=7
```

## Perangkat penting

| Fungsi | Node | compatible | Driver | Asal |
|---|---|---|---|---|
| SoC | `/` | `mediatek,MT6895` | — | node platform |
| Display (DRM) | `/dispsys_config@14000000` | `mediatek,mt6895-disp` | `mediatek_drm_v1` | source |
| Display (IOMMU) | `/soc/iommu@1e802000` | `mediatek,mt6895-disp-iommu` | `mtk_iommu` | source |
| Panel | `frag@19/panel1@0` | `rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871` | `panel_rm69220_vdo_x6871` | source |
| Touch | `frag@47/touch@0` | `goodix,gt9916` | `gt9916_common` | source |
| Storage UFS | `/ufshci@112b0000` | `mediatek,mt8183-ufshci` | `kernel-6.12/drivers/ufs/host/ufs-mediatek.c` | built-in |
| Storage MMC/eMMC | `/soc/mmc@11240000` | `mediatek,common-mmc-v2` | `mtk_mmc` | source |
| USB DRD 0 | `/usb0@11201000` | `mediatek,mtu3|mediatek,mt6895-mtu3` | `mtu3` | source |
| USB DRD 1 | `/usb1@11211000` | `mediatek,mtu3` | `mtu3` | source |
| Type-C (TCPC) | `/soc/i2c@11280000/mt6375@34/tcpc` | `mediatek,mt6375-tcpc` | `tcpc_mt6375` | source |
| PMIC utama (MT6375) | `/soc/i2c@11280000/mt6375@34` | `mediatek,mt6375` | `mt6375` | source |
| PMIC sekunder (MT6368) | `/spmi@1c804000/second_pmic@5` | `mediatek,mt6368` | `mtk_spmi_pmic` | source |
| Framework charging | `/charger` | `mediatek,charger` | `drivers/power/supply/mtk_charger.c` | built-in |
| Audio card | `/sound` | `mediatek,mt6895-mt6368-sound` | `mt6895-mt6368` | source |
| Audio codec | `/spmi@1c804000/second_pmic@5/mt6368codec` | `mediatek,mt6368-sound` | `snd_soc_mt6368` | source |
| Audio amp (FS15xx) | `frag@5/fs15xx_pa@34` | `foursemi,fs15xx` | `snd_soc_fs1599` | source |
| SCP | `/scp@1c700000` | `mediatek,scp` | `scp` | source |
| ADSP | `/soc/adsp-core0@1e020000` | `mediatek,mt6895-adsp_core_0` | `drivers/misc/mediatek/adsp/v2/adsp_driver_v2.c` | built-in |
| WiFi | `/wifi@18000000` | `mediatek,wifi` | `connectivity/wlan/core/gen4m/os/linux/hif/axi/axi.c` | built-in |
| NFC | `frag@9/nfc_nxp@28` | `nxp,pn544` | `nfc_i2c` | source |
| Fingerprint | `frag@13/fingerprint@0` | `tran_fp_legacy` | `tran_fp` | source |
| Kamera sensor0 (utama) | `frag@58/sensor0@10` | `mediatek,imgsensor` | `imgsensor` | source |
| Kamera sensor1 | `frag@59/sensor1@4A` | `mediatek,imgsensor` | `imgsensor` | source |
| Kamera sensor2 | `frag@60/sensor2@10` | `mediatek,imgsensor` | `imgsensor` | source |
| Kamera sensor3 (makro) | `frag@61/sensor3@10` | `mediatek,imgsensor` | `imgsensor` | source |
| EEPROM cam0 | `frag@58/camera_eeprom0@50` | `mediatek,camera_eeprom` | `camera_eeprom_v4l2` | source |
| EEPROM cam1 | `frag@59/camera_eeprom1@51` | `mediatek,camera_eeprom` | `camera_eeprom_v4l2` | source |
| AF cam0 (VCM) | `frag@58/camera_af_main@0C` | `mediatek,aw8601af` | `aw8601af` | source |
| Flash LED 1 | `frag@53/ocp81375_v4l2@63` | `mediatek,ocp81375_v4l2` | `ocp81375_v4l2` | source |
| Flash LED 2 | `frag@53/sgm37864_v4l2@64` | `mediatek,sgm37864_v4l2` | `sgm37864_v4l2` | source |
| Haptic | `frag@50/haptic_hv@5A` | `awinic,haptic_hv` | `tran_richtap_haptic_hv` | source |
| LED indikator | `frag@25/aw22xxx_led@6a` | `awinic,aw22xxx_led` | `leds-aw22xxx` | source |
| LED core Transsion | `frag@24/tran_led_core` | `tran,led_core` | `tran_led_core` | source |

## Temuan

### 1. Bug `of_match` flash LED tidak cocok dengan DT (sudah diperbaiki)

DT X6871 memakai compatible bersufiks `_v4l2`:

```text
frag@53/ocp81375_v4l2@63   compatible = "mediatek,ocp81375_v4l2"
frag@53/sgm37864_v4l2@64   compatible = "mediatek,sgm37864_v4l2"
```

Modul stock memakai string itu (`alias=of:N*T*Cmediatek,ocp81375_v4l2`),
tetapi source 6.12 kita hanya punya `mediatek,ocp81375` dan
`mediatek,sgm37864`, sehingga **driver tidak bind** dan flash/torch kamera mati.

Perbaikan di `kernel_device_modules-6.12/drivers/misc/mediatek/flashlight/v4l2/`:
tambahkan compatible bersufiks `_v4l2` pada `ocp81375_of_table`,
`sgm37864_of_table`, dan `aw36515_of_table` (entri lama dipertahankan untuk 6.1).
Sudah diverifikasi: alias modul hasil build sekarang memuat kedua bentuk.

### 2. Node tanpa driver sendiri (7) — mana yang penting

Ketujuhnya **bukan** node yang butuh driver baru. Rinciannya:

| Node | compatible | Yang memakai | Dampak | Perlu tindakan? |
|---|---|---|---|---|
| `frag@37/tc_trancare` | `tc,trancare` | `tc_trancare.ko` (stock, tidak ada source) | battery health/`bat_cycle`, `tc_upload_battery_health_percent_msg` hilang | ya, kalau fitur battery care dibutuhkan |
| `/tran_sensor_cust` | `mediatek,tran_sensor` | `sensorhub.ko` versi Transsion | patch sensorhub (`tran-cwb-support`, `un_als_support`, `ml_lcm_info`, brightness/vrefresh ke sensor) hilang -> auto-brightness/true-tone kurang akurat | bisa, tapi patch tidak ada di donor 6.1 |
| `frag@37/tc_adapter_control` | `transsion, adapter_control` | `tc_misc_intf.c` (`of_find_compatible_node`), `tc_basic_charger.c`, `tc_auto_test.c` | **tidak ada** — node data, konsumennya sudah ada di source kita | tidak |
| `frag@31` | `tc_pe5` | `tc_pep50.ko` (kita build) | **tidak ada** — DT vendor menulis `tc_pe5` tanpa koma, sedangkan driver (stock maupun source kita) mencocokkan `tc,pe5`; jadi perilakunya sama dengan stock | tidak |
| `frag@73` | `mediatek,md1_sim1_hot_plug_eint-eint` | eint controller (`mediatek,eint`) | **tidak ada** — node anak EINT, ditangani induknya | tidak |
| `/spmi@1c804000/mtee_svp/MTEE` | `mediatek,mtk_svp_on_mtee_support` | TEE/userspace (tidak ada di kernel tree) | **tidak ada** — node flag; cukup keberadaannya di DT | tidak |
| `/spmi@1c804000/mtee_svp/SecureVideoPath` | `mediatek,mtk_sec_video_path_support` | TEE/userspace | **tidak ada** — node flag | tidak |

Jadi hanya dua yang benar-benar kehilangan fitur: `tc,trancare` (battery
health/battery care) dan patch `mediatek,tran_sensor` di `sensorhub`.
Sisanya node data/flag yang sudah dikonsumsi kode yang kita punya, atau
memang tidak pernah bind sejak stock (`tc_pe5`).

### 3. Batas akurasi

- Pemetaan utama memakai alias `of:` pada `.ko` hasil build kita -> akurat.
- Driver tanpa alias `of:` (mis. `mt6368-accdet`) dipetakan lewat pencocokan
  string di source; kolom Driver menunjuk berkas yang memuat `.compatible`.
- Modul yang dibangun lewat Makefile khusus (mis. `wlan_drv_gen4m_6895`) bisa
  tampil sebagai `built-in` walau sebenarnya `.ko`.
- Node `syscon`/`simple-mfd` sengaja diberi label `node platform`.

## Tabel lengkap per subsistem

Total node device (status okay): 978
module=470, dt=371, builtin=130, ?=7


### Storage / UFS / MMC

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/disable_unused/disable-unused-clk-ufs_ao_config` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-ufs_pdn_cfg` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/soc/mmc@11240000` | `mediatek,common-mmc-v2` | `mtk_mmc` | source |
| `/soc/mmc@11242000` | `mediatek,common-mmc-v2` | `mtk_mmc` | source |
| `/soc/syscon@112b8000` | `mediatek,mt6895-ufs_ao_config|syscon|simple-mfd` | — | node platform |
| `/soc/syscon@112bc000` | `mediatek,mt6895-ufs_pdn_cfg|syscon|simple-mfd` | — | node platform |
| `/ufshci@112b0000` | `mediatek,mt8183-ufshci` | `kernel-6.12/drivers/ufs/host/ufs-mediatek.c` | built-in |

### USB / Type-C / Charging

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/battery-manager` | `mediatek,battery manager` | `mtk_battery_manager` | source |
| `/charger` | `mediatek,charger` | `drivers/power/supply/mtk_charger.c` | built-in |
| `/charger-cooler` | `mediatek,mt6375-charger-cooler` | `drivers/thermal/mediatek/charger_cooling.c` | built-in |
| `/disable_unused/disable-unused-pd-adsp_infra` | `mediatek,scpsys-disable-unused` | `mtk_pm_domain_disable_unused` | source |
| `/disable_unused/disable-unused-pd-adsp_top_dormant` | `mediatek,scpsys-disable-unused` | `mtk_pm_domain_disable_unused` | source |
| `/disable_unused/disable-unused-pd-audio` | `mediatek,scpsys-disable-unused` | `mtk_pm_domain_disable_unused` | source |
| `/disable_unused/disable-unused-pd-disp` | `mediatek,scpsys-disable-unused` | `mtk_pm_domain_disable_unused` | source |
| `/disable_unused/disable-unused-pd-disp1` | `mediatek,scpsys-disable-unused` | `mtk_pm_domain_disable_unused` | source |
| `/disable_unused/disable-unused-pd-mdp0` | `mediatek,scpsys-disable-unused` | `mtk_pm_domain_disable_unused` | source |
| `/disable_unused/disable-unused-pd-mdp1` | `mediatek,scpsys-disable-unused` | `mtk_pm_domain_disable_unused` | source |
| `/disable_unused/disable-unused-pd-mm_infra` | `mediatek,scpsys-disable-unused` | `mtk_pm_domain_disable_unused` | source |
| `/disable_unused/disable-unused-pd-mm_proc_dormant` | `mediatek,scpsys-disable-unused` | `mtk_pm_domain_disable_unused` | source |
| `/extcon_usb` | `mediatek,extcon-usb` | `drivers/misc/mediatek/extcon/extcon-mtk-usb.c` | built-in |
| `/extcon_usb1` | `mediatek,extcon-usb` | `drivers/misc/mediatek/extcon/extcon-mtk-usb.c` | built-in |
| `/lk-charger` | `mediatek,lk_charger` | — | node platform |
| `/low-battery-throttling` | `mediatek,low_battery_throttling` | `mtk_low_battery_throttling` | source |
| `/pd-adapter` | `mediatek,pd_adapter` | `drivers/power/supply/mtk_pd_adapter.c` | built-in |
| `/pdc` | `mediatek,charger,pd` | `drivers/power/supply/mtk_pd.c` | built-in |
| `/pe` | `mediatek,charger,pe` | `drivers/power/supply/mtk_pe.c` | built-in |
| `/pe2` | `mediatek,charger,pe2` | `drivers/power/supply/mtk_pe2.c` | built-in |
| `/pe45` | `mediatek,charger,pe45` | `drivers/power/supply/mtk_pe4_5.c` | built-in |
| `/pe5` | `mediatek,charger,pe5` | `drivers/power/supply/mtk_pe5.c` | built-in |
| `/rt-pd-manager` | `mediatek,rt-pd-manager` | `rt_pd_manager` | source |
| `/soc/i2c@11280000/mt6375@34/chg` | `mediatek,mt6375-chg` | `mt6375_charger` | source |
| `/soc/i2c@11280000/mt6375@34/mtk-gauge` | `mediatek,mt6375-gauge` | `mt6375_battery` | source |
| `/soc/i2c@11280000/mt6375@34/mtk_battery_oc_throttling` | `mediatek,mt6375-battery_oc_throttling` | `mtk_battery_oc_throttling` | source |
| `/soc/i2c@11280000/mt6375@34/tcpc` | `mediatek,mt6375-tcpc` | `tcpc_mt6375` | source |
| `/soc/smi-pd-cam-main` | `mediatek,smi-pd` | `mtk-smi` | source |
| `/soc/smi-pd-cam-mraw` | `mediatek,smi-pd` | `mtk-smi` | source |
| `/soc/smi-pd-cam-suba` | `mediatek,smi-pd` | `mtk-smi` | source |
| `/soc/smi-pd-cam-subb` | `mediatek,smi-pd` | `mtk-smi` | source |
| `/soc/smi-pd-cam-subc` | `mediatek,smi-pd` | `mtk-smi` | source |
| `/soc/smi-pd-dip1` | `mediatek,smi-pd` | `mtk-smi` | source |
| `/soc/smi-pd-ipe` | `mediatek,smi-pd` | `mtk-smi` | source |
| `/soc/smi-pd-isp-main` | `mediatek,smi-pd` | `mtk-smi` | source |
| `/soc/syscon@11201000` | `mediatek,mt6895-ssusb_device|syscon` | — | node platform |
| `/soc/syscon@11203e00` | `mediatek,mt6895-ssusb_sifslv_ippc|syscon` | — | node platform |
| `/soc/syscon@11213e00` | `mediatek,mt6895-ssusb_sifslv_ippc_p1|syscon` | — | node platform |
| `/typec_mux_switch` | `mediatek,typec_mux_switch` | `mux_switch` | source |
| `/usb-boost-manager` | `mediatek,usb-boost|mediatek,mt6895-usb-boost` | `usb_boost` | source |
| `/usb-meta` | `mediatek,usb-meta` | `usb_meta` | source |
| `/usb-phy` | `mediatek,fpga-u3phy` | `drivers/phy/mediatek/phy-mtk-fpgaphy.c` | built-in |
| `/usb-phy0@11e40000` | `mediatek,xsphy` | `phy_mtk_xsphy` | source |
| `/usb-phy1@11e30000` | `mediatek,xsphy` | `phy_mtk_xsphy` | source |
| `/usb0@11201000` | `mediatek,mtu3|mediatek,mt6895-mtu3` | `mtu3` | source |
| `/usb0@11201000/xhci0@11200000` | `mediatek,mtk-xhci` | `xhci_mtk_hcd_v2` | source |
| `/usb1@11211000` | `mediatek,mtu3` | `mtu3` | source |
| `/usb1@11211000/xhci1@11210000` | `mediatek,mtk-xhci-p1` | `xhci_mtk_hcd_v2` | source |
| `/usb_dp_selector@10005600` | `mediatek,usb_dp_selector` | `usb_dp_selector` | source |
| `frag@1/sliptswitch_gpio_audioswitch` | `transsion,sliptswitch-gpio-audioswitch` | `splitswitch-gpio` | source |
| `frag@22` | `transsion,extcon-usb` | `tran_extcon_usb` | source |
| `frag@29/usb_control` | `transsion, usb_control` | `tran_usb_ctrl` | source |
| `frag@37/pid_chg` | `tc,pid_chg_algo` | `tc_pid_chg_algo` | source |
| `frag@37/tc_30` | `transsion,tc30_charger` | `tc_tc30_algo` | source |
| `frag@37/tc_chgtype` | `tc_chgtype` | `tc_chg_type_det` | source |
| `frag@37/tc_gauge` | `tc_gauge` | `tc_gauge` | source |
| `frag@37/tc_hvdcp20` | `transsion,hvdcp20_charger` | `tc_hvdcp20_algo` | source |
| `frag@37/tc_pd` | `transsion,pd_charger` | `tc_pd_algo` | source |
| `frag@37/tc_pe2` | `transsion,pe20_charger` | `tc_pe20_algo` | source |
| `frag@37/tc_tcpc` | `tc_tcpc` | `tc_tcpc` | source |
| `frag@37/tran_otg` | `tran,otg_fun` | `tc_otg_ctrl` | source |
| `frag@38` | `tc,charger` | `tc_charger_framework` | source |
| `frag@43` | `mediatek,lk_charger` | — | node platform |

### Display / Touch / LED

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/backlight-cooler` | `mediatek,backlight-cooler` | `backlight_cooling` | source |
| `/disp_aal@1400d000` | `mediatek,disp_aal0|mediatek,mt6895-disp-aal` | `mediatek_drm_v1` | source |
| `/disp_aal@1440d000` | `mediatek,disp_aal1|mediatek,mt6895-disp-aal` | `mediatek_drm_v1` | source |
| `/disp_c3d@14008000` | `mediatek,disp_c3d0|mediatek,mt6895-disp-c3d` | `mediatek_drm_v1` | source |
| `/disp_c3d@14408000` | `mediatek,disp_c3d1|mediatek,mt6895-disp-c3d` | `mediatek_drm_v1` | source |
| `/disp_ccorr@1400a000` | `mediatek,disp_ccorr0|mediatek,mt6895-disp-ccorr` | `mediatek_drm_v1` | source |
| `/disp_ccorr@1400b000` | `mediatek,disp_ccorr0|mediatek,mt6895-disp-ccorr` | `mediatek_drm_v1` | source |
| `/disp_ccorr@1440a000` | `mediatek,disp_ccorr2|mediatek,mt6895-disp-ccorr` | `mediatek_drm_v1` | source |
| `/disp_ccorr@1440b000` | `mediatek,disp_ccorr3|mediatek,mt6895-disp-ccorr` | `mediatek_drm_v1` | source |
| `/disp_chist@14011000` | `mediatek,disp_chist0|mediatek,mt6895-disp-chist` | `mediatek_drm_v1` | source |
| `/disp_chist@14012000` | `mediatek,disp_chist1|mediatek,mt6895-disp-chist` | `mediatek_drm_v1` | source |
| `/disp_chist@14411000` | `mediatek,disp_chist2|mediatek,mt6895-disp-chist` | `mediatek_drm_v1` | source |
| `/disp_chist@14412000` | `mediatek,disp_chist3|mediatek,mt6895-disp-chist` | `mediatek_drm_v1` | source |
| `/disp_cm@14013000` | `mediatek,disp_cm0|mediatek,mt6895-disp-cm` | `mediatek_drm_v1` | source |
| `/disp_cm@14413000` | `mediatek,disp_cm1|mediatek,mt6895-disp-cm` | `mediatek_drm_v1` | source |
| `/disp_color@14009000` | `mediatek,disp_color0|mediatek,mt6895-disp-color` | `mediatek_drm_v1` | source |
| `/disp_color@14409000` | `mediatek,disp_color1|mediatek,mt6895-disp-color` | `mediatek_drm_v1` | source |
| `/disp_dither@14010000` | `mediatek,disp_dither0|mediatek,mt6895-disp-dither` | `mediatek_drm_v1` | source |
| `/disp_dither@14410000` | `mediatek,disp_dither1|mediatek,mt6895-disp-dither` | `mediatek_drm_v1` | source |
| `/disp_dp_intf0@1441d000` | `mediatek,dp_intf|mediatek,mt6895-dp-intf` | `mediatek_drm_v1` | source |
| `/disp_dsc1_wrap@14415000` | `mediatek,disp_dsc1_wrap|mediatek,mt6895-disp-dsc` | `mediatek_drm_v1` | source |
| `/disp_dsc_wrap@14015000` | `mediatek,disp_dsc_wrap|mediatek,mt6895-disp-dsc` | `mediatek_drm_v1` | source |
| `/disp_gamma@1400e000` | `mediatek,disp_gamma0|mediatek,mt6895-disp-gamma` | `mediatek_drm_v1` | source |
| `/disp_gamma@1440e000` | `mediatek,disp_gamma1|mediatek,mt6895-disp-gamma` | `mediatek_drm_v1` | source |
| `/disp_mdp_aal@1400c000` | `mediatek,disp_mdp_aal0|mediatek,mt6895-dmdp-aal` | `mediatek_drm_v1` | source |
| `/disp_mdp_aal@1440c000` | `mediatek,disp_mdp_aal1|mediatek,mt6895-dmdp-aal` | `mediatek_drm_v1` | source |
| `/disp_merge@14016000` | `mediatek,disp_merge0|mediatek,mt6895-disp-merge` | `mediatek_drm_v1` | source |
| `/disp_merge@14416000` | `mediatek,disp_merge1|mediatek,mt6895-disp-merge` | `mediatek_drm_v1` | source |
| `/disp_mutex@14001000` | `mediatek,disp_mutex0|mediatek,mt6895-disp-mutex` | `mediatek_drm_v1` | source |
| `/disp_ovl@14002000` | `mediatek,disp_ovl0|mediatek,mt6895-disp-ovl` | `mediatek_drm_v1` | source |
| `/disp_ovl@14003000` | `mediatek,disp_ovl0_2l|mediatek,mt6895-disp-ovl` | `mediatek_drm_v1` | source |
| `/disp_ovl@14004000` | `mediatek,disp_ovl1_2l|mediatek,mt6895-disp-ovl` | `mediatek_drm_v1` | source |
| `/disp_ovl@14402000` | `mediatek,disp_ovl1|mediatek,mt6895-disp-ovl` | `mediatek_drm_v1` | source |
| `/disp_ovl@14403000` | `mediatek,disp_ovl2_2l|mediatek,mt6895-disp-ovl` | `mediatek_drm_v1` | source |
| `/disp_ovl@14404000` | `mediatek,disp_ovl3_2l|mediatek,mt6895-disp-ovl` | `mediatek_drm_v1` | source |
| `/disp_postmask0@1400f000` | `mediatek,disp_postmask0|mediatek,mt6895-disp-postmask` | `drivers/gpu/drm/mediatek/mediatek_v2/mtk_disp_postmask.c` | built-in |
| `/disp_postmask0@1440f000` | `mediatek,disp_postmask1|mediatek,mt6895-disp-postmask` | `drivers/gpu/drm/mediatek/mediatek_v2/mtk_disp_postmask.c` | built-in |
| `/disp_pwm0@1100e000` | `mediatek,disp_pwm0|mediatek,mt6895-disp-pwm0` | `pwm_mtk_disp` | source |
| `/disp_rdma@14006000` | `mediatek,disp_rdma0|mediatek,mt6895-disp-rdma` | `mediatek_drm_v1` | source |
| `/disp_rdma@1401c000` | `mediatek,disp_rdma1|mediatek,mt6895-disp-rdma` | `mediatek_drm_v1` | source |
| `/disp_rdma@14406000` | `mediatek,disp_rdma2|mediatek,mt6895-disp-rdma` | `mediatek_drm_v1` | source |
| `/disp_rdma@1441c000` | `mediatek,disp_rdma3|mediatek,mt6895-disp-rdma` | `mediatek_drm_v1` | source |
| `/disp_rsz0@14005000` | `mediatek,disp_rsz0|mediatek,mt6895-disp-rsz` | `mediatek_drm_v1` | source |
| `/disp_rsz0@14405000` | `mediatek,disp_rsz1|mediatek,mt6895-disp-rsz` | `mediatek_drm_v1` | source |
| `/disp_spr@14014000` | `mediatek,disp_spr0|mediatek,mt6895-disp-SPR` | `mediatek_drm_v1` | source |
| `/disp_spr@14414000` | `mediatek,disp_spr1|mediatek,mt6895-disp-SPR` | `mediatek_drm_v1` | source |
| `/disp_tdshp@14007000` | `mediatek,disp_tdshp0|mediatek,mt6895-disp-tdshp` | `mediatek_drm_v1` | source |
| `/disp_tdshp@14407000` | `mediatek,disp_tdshp1|mediatek,mt6895-disp-tdshp` | `mediatek_drm_v1` | source |
| `/disp_ufbc_wdma0@14419000` | `mediatek,disp_ufbc_wdma0` | — | node platform |
| `/disp_wdma0@14018000` | `mediatek,disp_wdma0|mediatek,mt6895-disp-wdma` | `mediatek_drm_v1` | source |
| `/disp_wdma0@14418000` | `mediatek,disp_wdma2|mediatek,mt6895-disp-wdma` | `mediatek_drm_v1` | source |
| `/disp_wdma1@1401f000` | `mediatek,disp_wdma1|mediatek,mt6895-disp-wdma` | `mediatek_drm_v1` | source |
| `/disp_wdma1@1441f000` | `mediatek,disp_wdma3|mediatek,mt6895-disp-wdma` | `mediatek_drm_v1` | source |
| `/dispsys_config@14000000` | `mediatek,mt6895-disp` | `mediatek_drm_v1` | source |
| `/drm_wv` | `mediatek,drm_wv` | `widevine_driver` | source |
| `/dsi@14017000` | `mediatek,dsi0|mediatek,mt6895-dsi` | `drivers/gpu/drm/mediatek/mediatek_v2/mtk_dsi.c` | built-in |
| `/dsi_te` | `mediatek, dsi_te-eint` | — | node platform |
| `/gateic@0` | `mediatek,mtk-drm-gateic-drv` | — | node platform |
| `/inlinerot@14020000` | `mediatek,inlinerot|mediatek,mt6895-disp-inlinerotate` | `mediatek_drm_v1` | source |
| `/inlinerot@14420000` | `mediatek,inlinerot|mediatek,mt6895-disp-inlinerotate` | `mediatek_drm_v1` | source |
| `/mipi_tx_config@11f70000` | `mediatek,mipi_tx_config0|mediatek,mt6895-mipi-tx` | `drivers/gpu/drm/mediatek/mediatek_v2/mtk_mipi_tx.c` | built-in |
| `/soc/disp_sec` | `mediatek,disp_sec` | `drivers/gpu/drm/mediatek/mediatek_v2/mtk_disp_sec.c` | built-in |
| `/soc/drm@1000d000` | `mediatek,dbgtop-drm` | `dbgtop-drm` | source |
| `/soc/iommu@1e802000` | `mediatek,mt6895-disp-iommu` | `mtk_iommu` | source |
| `/soc/iommu@1e803000` | `mediatek,common-disp-iommu-bank1` | `iommu_secure` | source |
| `/soc/iommu@1e804000` | `mediatek,common-disp-iommu-bank2` | `iommu_secure` | source |
| `/soc/iommu@1e805000` | `mediatek,common-disp-iommu-bank3` | `iommu_secure` | source |
| `/soc/iommu@1e806000` | `mediatek,common-disp-iommu-bank4` | `iommu_secure` | source |
| `/soc/irtx_pwm` | `mediatek,irtx-pwm` | `drivers/misc/mediatek/irtx/mtk_irtx_pwm.c` | built-in |
| `/soc/opp-table-disp0` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/soc/opp-table-disp1` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/soc/pwm@11008000` | `mediatek,pwm` | `drivers/misc/mediatek/pwm/mtk_pwm.c` | built-in |
| `/soc/smi-disp-comm@1e801000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon` | — | node platform |
| `/soc/smi-infra-disp-subcomm0@1e809000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi-infra-disp-subcomm1@1e80a000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/touch` | `mediatek,touch` | `adaptive-ts` | source |
| `frag@1/led@6` | `mediatek,lcd-backlight` | — | node platform |
| `frag@19/panel1@0` | `rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871` | `panel_rm69220_vdo_x6871` | source |
| `frag@2` | `mediatek,disp-leds` | `leds_mtk_disp` | source |
| `frag@24/tran_led_core` | `tran,led_core` | `tran_led_core` | source |
| `frag@25/aw22xxx_led@6a` | `awinic,aw22xxx_led` | `leds-aw22xxx` | source |
| `frag@47/touch@0` | `goodix,gt9916` | `gt9916_common` | source |

### Kamera / Flash

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/cam_raw_a@1a030000` | `mediatek,cam-raw` | `mtk_cam_isp` | source |
| `/cam_raw_b@1a070000` | `mediatek,cam-raw` | `mtk_cam_isp` | source |
| `/cam_raw_c@1a0b0000` | `mediatek,cam-raw` | `mtk_cam_isp` | source |
| `/cam_yuv_a@1a050000` | `mediatek,cam-yuv` | `mtk_cam_isp` | source |
| `/cam_yuv_b@1a090000` | `mediatek,cam-yuv` | `mtk_cam_isp` | source |
| `/cam_yuv_c@1a0d0000` | `mediatek,cam-yuv` | `mtk_cam_isp` | source |
| `/camera-fsync-ccu` | `mediatek,camera-fsync-ccu` | — | node platform |
| `/camera_camsys_ccu` | `mediatek,camera_camsys_ccu` | — | node platform |
| `/camera_imgsys_ccu` | `mediatek,camera_imgsys_ccu` | — | node platform |
| `/camisp@1a000000` | `mediatek,camisp` | `mtk_cam_isp` | source |
| `/camisp_l13` | `mediatek,camisp-larb` | `mtkcam/camsys/isp8/cam/mtk_cam-larb.c` | built-in |
| `/camisp_l14` | `mediatek,camisp-larb` | `mtkcam/camsys/isp8/cam/mtk_cam-larb.c` | built-in |
| `/camisp_l25` | `mediatek,camisp-larb` | `mtkcam/camsys/isp8/cam/mtk_cam-larb.c` | built-in |
| `/camisp_l26` | `mediatek,camisp-larb` | `mtkcam/camsys/isp8/cam/mtk_cam-larb.c` | built-in |
| `/camsv10@1a181000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv11@1a182000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv12@1a183000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv13@1a184000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv14@1a185000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv15@1a186000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv16@1a187000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv1@1a110000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv2@1a111000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv3@1a112000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv4@1a113000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv5@1a114000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv6@1a115000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv7@1a116000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv8@1a117000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/camsv9@1a180000` | `mediatek,camsv` | `mtk_cam_isp` | source |
| `/disable_unused/disable-unused-clk-cam_main_r1a` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-camsys_mraw` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-camsys_rawa` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-camsys_rawb` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-camsys_rawc` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-camsys_yuva` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-camsys_yuvb` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-camsys_yuvc` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-dip_nr_dip1` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-dip_top_dip1` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-imgsys_main` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-wpe1_dip1` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-wpe2_dip1` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-wpe3_dip1` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/flashlight_core` | `mediatek,flashlight_core` | `flashlight` | source |
| `/imgsys-cmdq@15002000` | `mediatek,imgsys-cmdq` | `mtk_imgsys_cmdq_isp71` | source |
| `/imgsys_fw@15000000` | `mediatek,imgsys-isp71` | `mtk_imgsys_isp71` | source |
| `/mraw1@1a130000` | `mediatek,mraw` | `mtk_cam_isp` | source |
| `/mraw2@1a140000` | `mediatek,mraw` | `mtk_cam_isp` | source |
| `/mraw3@1a150000` | `mediatek,mraw` | `mtk_cam_isp` | source |
| `/mraw4@1a160000` | `mediatek,mraw` | `mtk_cam_isp` | source |
| `/opp-table-cam` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/seninf_top@1a010000` | `mediatek,seninf-core` | `mtk_cam_isp` | source |
| `/soc/pda@1a100000` | `mediatek,camera-pda` | `pda_drv_mt6895` | source |
| `/soc/syscon@15000000` | `mediatek,mt6895-imgsys_main|syscon` | — | node platform |
| `/soc/syscon@15110000` | `mediatek,mt6895-dip_top_dip1|syscon` | — | node platform |
| `/soc/syscon@15130000` | `mediatek,mt6895-dip_nr_dip1|syscon` | — | node platform |
| `/soc/syscon@15220000` | `mediatek,mt6895-wpe1_dip1|syscon` | — | node platform |
| `/soc/syscon@15520000` | `mediatek,mt6895-wpe2_dip1|syscon` | — | node platform |
| `/soc/syscon@15620000` | `mediatek,mt6895-wpe3_dip1|syscon` | — | node platform |
| `/soc/syscon@1a000000` | `mediatek,mt6895-cam_main_r1a|syscon` | — | node platform |
| `/soc/syscon@1a04f000` | `mediatek,mt6895-camsys_rawa|syscon` | — | node platform |
| `/soc/syscon@1a06f000` | `mediatek,mt6895-camsys_yuva|syscon` | — | node platform |
| `/soc/syscon@1a08f000` | `mediatek,mt6895-camsys_rawb|syscon` | — | node platform |
| `/soc/syscon@1a0af000` | `mediatek,mt6895-camsys_yuvb|syscon` | — | node platform |
| `/soc/syscon@1a0cf000` | `mediatek,mt6895-camsys_rawc|syscon` | — | node platform |
| `/soc/syscon@1a0ef000` | `mediatek,mt6895-camsys_yuvc|syscon` | — | node platform |
| `/soc/syscon@1a170000` | `mediatek,mt6895-camsys_mraw|syscon` | — | node platform |
| `frag@51/seninf_csi_port_0` | `mediatek,seninf` | `mtk_cam_isp` | source |
| `frag@51/seninf_csi_port_1` | `mediatek,seninf` | `mtk_cam_isp` | source |
| `frag@51/seninf_csi_port_2` | `mediatek,seninf` | `mtk_cam_isp` | source |
| `frag@51/seninf_csi_port_3` | `mediatek,seninf` | `mtk_cam_isp` | source |
| `frag@58/camera_af_main@0C` | `mediatek,aw8601af` | `aw8601af` | source |
| `frag@58/camera_eeprom0@50` | `mediatek,camera_eeprom` | `camera_eeprom_v4l2` | source |
| `frag@58/sensor0@10` | `mediatek,imgsensor` | `imgsensor` | source |
| `frag@59/camera_eeprom1@51` | `mediatek,camera_eeprom` | `camera_eeprom_v4l2` | source |
| `frag@59/sensor1@4A` | `mediatek,imgsensor` | `imgsensor` | source |
| `frag@60/sensor2@10` | `mediatek,imgsensor` | `imgsensor` | source |
| `frag@61/sensor3@10` | `mediatek,imgsensor` | `imgsensor` | source |

### Audio

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/atf_logger` | `mediatek,tfa_debug` | `atf_logger` | source |
| `/audio_sram@1e102000` | `mediatek,audio_sram` | — | node platform |
| `/mt6895-afe-pcm@1e100000` | `mediatek,mt6895-sound` | `snd_soc_mt6895_afe` | source |
| `/mtk-btcvsd-snd@18830000` | `mediatek,mtk-btcvsd-snd` | `mtk_btcvsd` | source |
| `/snd-audio-dsp` | `mediatek,snd-audio-dsp` | `snd_soc_audiodsp_common` | source |
| `/snd-scp-ultra` | `mediatek,snd-scp-ultra` | `snd_soc_mtk_scp_ultra` | source |
| `/soc/adsp-core0@1e020000` | `mediatek,mt6895-adsp_core_0` | `drivers/misc/mediatek/adsp/v2/adsp_driver_v2.c` | built-in |
| `/soc/adsp-core1@1e090000` | `mediatek,mt6895-adsp_core_1` | `drivers/misc/mediatek/adsp/v2/adsp_driver_v2.c` | built-in |
| `/soc/adspsys@1e000000` | `mediatek,mt6895-adspsys` | `drivers/misc/mediatek/adsp/v2/adsp_driver_v2.c` | built-in |
| `/sound` | `mediatek,mt6895-mt6368-sound` | `mt6895-mt6368` | source |
| `/spmi@1c804000/second_pmic@5/accdet` | `mediatek,mt6368-accdet` | `mt6368-accdet` | source |
| `/spmi@1c804000/second_pmic@5/mt6368codec` | `mediatek,mt6368-sound` | `snd_soc_mt6368` | source |
| `/vdec@16000000` | `mediatek,vcodec-dec` | `mtk_vcodec_dec` | source |
| `/venc@17020000` | `mediatek,vcodec-enc` | `mtk_vcodec_enc` | source |
| `frag@1/tran_audio_controller` | `tran-audio-controller` | `tran_audio_control` | source |
| `frag@5/fs15xx_pa@34` | `foursemi,fs15xx` | `snd_soc_fs1599` | source |
| `frag@5/fs15xx_pa@35` | `foursemi,fs15xx` | `snd_soc_fs1599` | source |

### Connectivity (WiFi/BT/GPS/NFC/FM)

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/connfem@18000000` | `mediatek,mt6895-connfem` | — | node platform |
| `/connscp` | `mediatek,mt6895-conn_scp` | `connscp` | source |
| `/consys@18000000` | `mediatek,mt6895-consys` | `connectivity/conninfra/conn_drv/connv2/platform/consys_hw_plat_data.c` | built-in |
| `/soc/gps@18c00000` | `mediatek,mt6895-gps` | — | node platform |
| `/soc/interconnect` | `mediatek,mt6895-mmqos` | `mmqos_mt6895` | source |
| `/spmi@1c804000/mt6685_mfd/mt6685_consys` | `mediatek,mt6685-consys` | `mt6685-core` | source |
| `/spmi@1c804000/pmic@4/mt6363-consys` | `mediatek,mt6363-consys` | `drivers/mfd/mtk-spmi-pmic.c` | built-in |
| `/spmi@1c804000/second_pmic@5/mt6368-consys` | `mediatek,mt6368-consys` | `drivers/mfd/mtk-spmi-pmic.c` | built-in |
| `/wifi@18000000` | `mediatek,wifi` | `connectivity/wlan/core/gen4m/os/linux/hif/axi/axi.c` | built-in |
| `frag@9/nfc_nxp@28` | `nxp,pn544` | `nfc_i2c` | source |

### Sensor (IMU/ALSPS/MAG/BARO)

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/tran_sensor_cust` | `mediatek,tran_sensor` | — | tidak ada |

### Fingerprint / Secure / TrustZone

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/fpsgo` | `mediatek,fpsgo` | `drivers/misc/mediatek/performance/fpsgo_v3/fbt/platform/fbt_cpu_platform.c` | built-in |
| `/hwrng` | `arm,sec-rng` | `sec_rng` | source |
| `/nebula/nebula-gz-log` | `android,nebula-gz-log-v1` | — | node platform |
| `/soc/dmaheap_test0` | `mediatek, mtk_dmabufheap, iommu0` | — | node platform |
| `/soc/dmaheap_test1` | `mediatek, mtk_dmabufheap, iommu1` | — | node platform |
| `/soc/fingerprint` | `mediatek,goodix-fp` | — | node platform |
| `/soc/iommu-test-ktf1` | `mediatek,mm-iommu-test-ktf1` | — | node platform |
| `/soc/iommu@19010000` | `mediatek,mt6895-apu-iommu0` | `mtk_iommu` | source |
| `/soc/iommu@19011000` | `mediatek,common-apu-iommu0-bank1` | `iommu_secure` | source |
| `/soc/iommu@19012000` | `mediatek,common-apu-iommu0-bank2` | `iommu_secure` | source |
| `/soc/iommu@19013000` | `mediatek,common-apu-iommu0-bank3` | `iommu_secure` | source |
| `/soc/iommu@19014000` | `mediatek,common-apu-iommu0-bank4` | `iommu_secure` | source |
| `/soc/iommu@19015000` | `mediatek,mt6895-apu-iommu1` | `mtk_iommu` | source |
| `/soc/iommu@19016000` | `mediatek,common-apu-iommu1-bank1` | `iommu_secure` | source |
| `/soc/iommu@19017000` | `mediatek,common-apu-iommu1-bank2` | `iommu_secure` | source |
| `/soc/iommu@19018000` | `mediatek,common-apu-iommu1-bank3` | `iommu_secure` | source |
| `/soc/iommu@19019000` | `mediatek,common-apu-iommu1-bank4` | `iommu_secure` | source |
| `/soc/iommu@1e810000` | `mediatek,mt6895-mdp-iommu` | `mtk_iommu` | source |
| `/soc/iommu@1e811000` | `mediatek,common-mdp-iommu-bank1` | `iommu_secure` | source |
| `/soc/iommu@1e812000` | `mediatek,common-mdp-iommu-bank2` | `iommu_secure` | source |
| `/soc/iommu@1e813000` | `mediatek,common-mdp-iommu-bank3` | `iommu_secure` | source |
| `/soc/iommu@1e814000` | `mediatek,common-mdp-iommu-bank4` | `iommu_secure` | source |
| `/soc/iommu_test` | `mediatek,ktf-iommu-test` | — | node platform |
| `/soc/mtk_iommu_debug` | `mediatek,mt6895-iommu-debug` | `iommu_debug` | source |
| `/soc/mtk_iommu_test0` | `mediatek,iommu-test-dom0` | `iommu_test` | source |
| `/soc/mtk_iommu_test1` | `mediatek,iommu-test-dom1` | `iommu_test` | source |
| `/soc/mtk_iommu_test2` | `mediatek,iommu-test-dom2` | `iommu_test` | source |
| `/soc/mtk_iommu_test3` | `mediatek,iommu-test-dom3` | `iommu_test` | source |
| `/soc/mtk_iommu_test4` | `mediatek,iommu-test-dom4` | `iommu_test` | source |
| `/soc/mtk_iommu_test5` | `mediatek,iommu-test-dom5` | `iommu_test` | source |
| `/soc/mtk_iommu_test6` | `mediatek,iommu-test-dom6` | `iommu_test` | source |
| `/soc/mtk_iommu_test7` | `mediatek,iommu-test-dom7` | `iommu_test` | source |
| `/soc/mtk_iommu_test8` | `mediatek,iommu-test-dom8` | `iommu_test` | source |
| `/soc/mtk_iommu_test9` | `mediatek,iommu-test-dom9` | `iommu_test` | source |
| `/soc/mtk_iommu_test_dmaheap_ccu0` | `mediatek,dmaheap-sec-ccu0` | `iommu_test` | source |
| `/soc/mtk_iommu_test_dmaheap_normal` | `mediatek,dmaheap-normal` | `iommu_test` | source |
| `/soc/mtk_iommu_test_dmaheap_normal_region` | `mediatek,dmaheap-sec-normal-region` | `iommu_test` | source |
| `/soc/mtk_iommu_test_dmaheap_pa` | `mediatek,dmaheap-sec-pa` | `iommu_test` | source |
| `/soc/mtk_iommu_test_dmaheap_up` | `mediatek,dmaheap-sec-up` | `iommu_test` | source |
| `/soc/mtk_iommu_test_dmaheap_vdec` | `mediatek,dmaheap-sec-vdec` | `iommu_test` | source |
| `/soc/mtkheap-page-prot` | `mediatek,dmaheap-mtk-sec-page` | `mtk_sec_heap` | source |
| `/soc/mtkheap-page-svp` | `mediatek,dmaheap-mtk-sec-page` | `mtk_sec_heap` | source |
| `/soc/mtkheap-page-wfd` | `mediatek,dmaheap-mtk-sec-page` | `mtk_sec_heap` | source |
| `/soc/mtkheap-region-prot` | `mediatek,dmaheap-mtk-sec-region` | `mtk_sec_heap` | source |
| `/soc/mtkheap-region-svp` | `mediatek,dmaheap-mtk-sec-region` | `mtk_sec_heap` | source |
| `/soc/mtkheap-region-wfd` | `mediatek,dmaheap-mtk-sec-region` | `mtk_sec_heap` | source |
| `/spmi@1c804000/mtee_svp` | `medaitek,svp` | — | node platform |
| `/spmi@1c804000/mtee_svp/MTEE` | `mediatek,mtk_svp_on_mtee_support` | — | tidak ada |
| `/spmi@1c804000/mtee_svp/SecureVideoPath` | `mediatek,mtk_sec_video_path_support` | — | tidak ada |
| `/teeperf` | `mediatek,teeperf` | — | node platform |
| `/trusty` | `android,trusty-smc-v1` | `gz_trusty_mod` | source |
| `/trusty/mtee` | `mediatek,trusty-mtee-v1` | `gz_main_mod` | source |
| `/trusty/trusty-gz-log` | `android,trusty-gz-log-v1` | `gz_log_mod` | source |
| `/trusty/trusty-irq` | `android,trusty-irq-v1` | `gz_irq_mod` | source |
| `/trusty/trusty-virtio` | `android,trusty-virtio-v1` | `gz_virtio_mod` | source |
| `/trusty/tz-system` | `mediatek,trusty-tz` | `gz_tz_system` | source |
| `/vcp-iommu-sec` | `mediatek,vcp-io-sec` | `drivers/misc/mediatek/vcp/rv/vcp_helper.c` | built-in |
| `/vcp-iommu-vdec` | `mediatek,vcp-io-vdec` | `drivers/misc/mediatek/vcp/rv/vcp_helper.c` | built-in |
| `/vcp-iommu-venc` | `mediatek,vcp-io-venc` | `drivers/misc/mediatek/vcp/rv/vcp_helper.c` | built-in |
| `/vcp-iommu-work` | `mediatek,vcp-io-work` | `drivers/misc/mediatek/vcp/rv/vcp_helper.c` | built-in |
| `/vcp_iommu_ube_core` | `mediatek,vcp-io-ube-core` | `drivers/misc/mediatek/vcp/rv/vcp_helper.c` | built-in |
| `/vcp_iommu_ube_lat` | `mediatek,vcp-io-ube-lat` | `drivers/misc/mediatek/vcp/rv/vcp_helper.c` | built-in |
| `/vcu_iommu_venc` | `mediatek,vcu-io-venc` | `drivers/media/platform/mtk-vcu/mtk_vcu.c` | built-in |
| `frag@13/fingerprint@0` | `tran_fp_legacy` | `tran_fp` | source |

### PMIC / Regulator / Thermal

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/mt6363_temp` | `mediatek,mt6363-pmic-temp` | `pmic_temp` | source |
| `/mt6368_temp` | `mediatek,mt6368-pmic-temp` | `pmic_temp` | source |
| `/odm/rt5133-gpio1` | `regulator-fixed` | `kernel-6.12/drivers/regulator/fixed.c` | built-in |
| `/odm/rt5133-gpio2` | `regulator-fixed` | `kernel-6.12/drivers/regulator/fixed.c` | built-in |
| `/odm/rt5133-gpio3` | `regulator-fixed` | `kernel-6.12/drivers/regulator/fixed.c` | built-in |
| `/pmic-oc-debug` | `mediatek,mt6895-oc-debug` | `drivers/misc/mediatek/pmic_protect/mtk-pmic-oc-debug.c` | built-in |
| `/soc/i2c@11280000/mt6375@34` | `mediatek,mt6375` | `mt6375` | source |
| `/soc/i2c@11280000/mt6375@34/adc` | `mediatek,mt6375-adc` | `mt6375_adc` | source |
| `/soc/i2c@11280000/mt6375@34/auxadc` | `mediatek,pmic-auxadc|mediatek,mt6375-auxadc` | `mt6375_auxadc` | source |
| `/soc/i2c@11280000/mt6375@34/dbg` | `mediatek,mt6375-dbg` | `drivers/misc/mediatek/subpmic/subpmic-dbg.c` | built-in |
| `/soc/i2c@11280000/mt6375@34/lbat_service` | `mediatek,mt6375-lbat-service` | `pmic_lbat_service` | source |
| `/soc/i2c@11280000/rt5133@18` | `richtek,rt5133` | `rt5133_regulator` | source |
| `/soc/md-auxadc` | `mediatek,md_auxadc` | `ccci_auxadc` | source |
| `/soc/regulator-vibrator` | `regulator-vibrator` | `regulator-vibrator` | source |
| `/spmi@1c804000/mt6319@6` | `mediatek,mt6319` | `mtk_spmi_pmic` | source |
| `/spmi@1c804000/mt6319@6/extbuck_debug` | `mediatek,spmi-pmic-debug` | `mtk_spmi_pmic_debug` | source |
| `/spmi@1c804000/mt6319@6/mt6319-6-regulator` | `mediatek,mt6315_6-regulator` | `mt6315_regulator` | source |
| `/spmi@1c804000/mt6319@7` | `mediatek,mt6319` | `mtk_spmi_pmic` | source |
| `/spmi@1c804000/mt6319@7/extbuck_debug` | `mediatek,spmi-pmic-debug` | `mtk_spmi_pmic_debug` | source |
| `/spmi@1c804000/mt6319@7/mt6319-7-regulator` | `mediatek,mt6315_7-regulator` | `mt6315_regulator` | source |
| `/spmi@1c804000/mt6685_mfd` | `mediatek,mt6685` | `mt6685_core` | source |
| `/spmi@1c804000/mt6685_mfd/mt6685-audclk` | `mediatek,mt6685-audclk` | `mt6685-audclk`, `mt6685-core` | source |
| `/spmi@1c804000/mt6685_mfd/mt6685-clkbuf` | `mediatek,mt6685-clkbuf` | `mt6685-core` | source |
| `/spmi@1c804000/mt6685_mfd/mt6685_clock_buffer` | `mediatek,clock_buffer` | `drivers/mfd/mtk-spmi-pmic.c` | built-in |
| `/spmi@1c804000/mt6685_mfd/mt6685_rtc` | `mediatek,mt6685-rtc` | `rtc_mt6685` | source |
| `/spmi@1c804000/pmic@4` | `mediatek,mt6363` | `mtk_spmi_pmic` | source |
| `/spmi@1c804000/pmic@4/mt6363-auxadc` | `mediatek,mt6363-auxadc` | `mtk_spmi_pmic_adc` | source |
| `/spmi@1c804000/pmic@4/mt6363-efuse` | `mediatek,mt6363-efuse` | `nvmem-mt635x-efuse` | source |
| `/spmi@1c804000/pmic@4/mt6363-pinctrl` | `mediatek,mt6363-pinctrl` | `drivers/pinctrl/mediatek/pinctrl-mt6363.c` | built-in |
| `/spmi@1c804000/pmic@4/mt6363keys` | `mediatek,mt6363-keys` | `mtk_pmic_keys` | source |
| `/spmi@1c804000/pmic@4/mtk-spmi-pmic-debug` | `mediatek,spmi-pmic-debug` | `mtk_spmi_pmic_debug` | source |
| `/spmi@1c804000/pmic@4/mtk_dynamic_loading_throttling` | `mediatek,mt6363-dynamic_loading_throttling` | `mtk_dynamic_loading_throttling` | source |
| `/spmi@1c804000/pmic@4/regulators` | `mediatek,mt6363-regulator` | `drivers/mfd/mtk-spmi-pmic.c` | built-in |
| `/spmi@1c804000/second_pmic@5` | `mediatek,mt6368` | `mtk_spmi_pmic` | source |
| `/spmi@1c804000/second_pmic@5/mt6368-auxadc` | `mediatek,mt6368-auxadc` | `mtk_spmi_pmic_adc` | source |
| `/spmi@1c804000/second_pmic@5/mt6368-efuse` | `mediatek,mt6368-efuse` | `nvmem-mt635x-efuse` | source |
| `/spmi@1c804000/second_pmic@5/mtk-spmi-pmic-debug` | `mediatek,spmi-pmic-debug` | `mtk_spmi_pmic_debug` | source |
| `/spmi@1c804000/second_pmic@5/regulators` | `mediatek,mt6368-regulator` | `drivers/mfd/mtk-spmi-pmic.c` | built-in |
| `/thermal-ntc1` | `mediatek,mt6685-tia-ntc` | `board_temp` | source |
| `/thermal-ntc2` | `mediatek,mt6685-tia-ntc` | `board_temp` | source |
| `/thermal-ntc3` | `mediatek,mt6685-tia-ntc` | `board_temp` | source |
| `frag@37/tc_pmic` | `tc_pmic` | `tc_pmic` | source |
| `frag@5/tran_ldo@28` | `tran,tran_ldo` | `tran_ldo` | source |
| `frag@6/LDOEN6` | `regulator-fixed` | `kernel-6.12/drivers/regulator/fixed.c` | built-in |
| `frag@63/tran_ldo@28` | `tran,tran_ldo` | `tran_ldo` | source |
| `frag@64/gpioldo_iovdd` | `regulator-fixed` | `kernel-6.12/drivers/regulator/fixed.c` | built-in |
| `frag@64/ldoid7en` | `regulator-fixed` | `kernel-6.12/drivers/regulator/fixed.c` | built-in |
| `frag@64/vs2pmu` | `regulator-fixed` | `kernel-6.12/drivers/regulator/fixed.c` | built-in |

### Power / PM / Clock / Debug

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/clk_ao` | `simple-bus` | — | node platform |
| `/clkchk` | `mediatek,mt6895-clkchk` | `drivers/clk/mediatek/clkchk-mt6895.c` | built-in |
| `/clkitg` | `simple-bus` | — | node platform |
| `/clkitg/bring-up` | `mediatek,clk-bring-up` | `clk-bringup` | source |
| `/clocks/clk13m` | `fixed-clock` | `kernel-6.12/drivers/clk/clk-fixed-rate.c` | built-in |
| `/clocks/clk26m` | `fixed-clock` | `kernel-6.12/drivers/clk/clk-fixed-rate.c` | built-in |
| `/clocks/clk32k` | `fixed-clock` | `kernel-6.12/drivers/clk/clk-fixed-rate.c` | built-in |
| `/clocks/ulposc` | `fixed-clock` | `kernel-6.12/drivers/clk/clk-fixed-rate.c` | built-in |
| `/cpu_power_throttling` | `mediatek,cpu-power-throttling` | `mtk_cpu_power_throttling` | source |
| `/disable_unused/disable-unused-clk-afe` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-apmixedsys` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-apupll1_pll_ctrl` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-apupll_pll_ctrl` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-ccu` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-imp_iic_wrap_c` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-imp_iic_wrap_s` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-imp_iic_wrap_w` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-infracfg_ao` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-ipesys` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-mdpsys` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-mdpsys1` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-mminfra_config` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-mmsys0` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-mmsys1` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-npupll_pll_ctrl` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-pericfg_ao` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-topckgen` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-vdec_gcon_base` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-vdec_soc_gcon_base` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-vencsys` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/disable_unused/disable-unused-clk-vencsys_c1` | `mediatek,clk-disable-unused` | `clk_disable_unused` | source |
| `/efuse@11f10000` | `mediatek,devinfo` | `nvmem_mtk_devinfo` | source |
| `/gpu-power-throttling` | `mediatek,gpu-power-throttling` | `mtk_gpu_power_throttling` | source |
| `/gpufreq` | `mediatek,gpufreq` | `mtk_gpufreq_mt6895` | source |
| `/gpufreq_wrapper` | `mediatek,gpufreq_wrapper` | `mtk_gpufreq_wrapper` | source |
| `/ktf-clkmgr-test` | `mediatek,ktf-clkmgr-test` | — | node platform |
| `/mali@13000000` | `mediatek,mali|arm,mali-valhall` | `mali_kbase_mt6895_a16w` | source |
| `/mcupm@c540000` | `mediatek,mcupm` | `mcupm` | source |
| `/md_power_throttling` | `mediatek,md-power-throttling` | `mtk_md_power_throttling` | source |
| `/mmdvfs-debug` | `mediatek,mmdvfs-debug` | `drivers/misc/mediatek/mmdvfs/mtk-mmdvfs-debug-v3.c` | built-in |
| `/mtk_lpm/cpupm-sysram@0011b000` | `mediatek,cpupm-sysram` | — | node platform |
| `/mtk_lpm/lpm_sysram@0011b500` | `mediatek,lpm-sysram` | — | node platform |
| `/peak-power-budget@117780` | `mediatek,peak_power_budget` | `mtk_peak_power_budget` | source |
| `/scp-dvfs` | `mediatek,scp-dvfs` | `scp` | source |
| `/scp@1c700000` | `mediatek,scp` | `scp` | source |
| `/scp_clk_ctrl@1c721000` | `mediatek,scp_clk_ctrl|syscon` | — | node platform |
| `/scp_gpio@10005000` | `mediatek,scp_gpio|syscon` | — | node platform |
| `/soc` | `mediatek,mminfra-debug` | `drivers/misc/mediatek/mminfra/mtk-mminfra-debug.c` | built-in |
| `/soc/ccci-scp` | `mediatek,ccci_md_scp` | `ccci_fsm_scp` | source |
| `/soc/ccu_rproc1@1b180000` | `mediatek,ccu_rproc1` | `mtk_ccuv` | source |
| `/soc/ccu_rproc@1b080000` | `mediatek,ccu_rproc` | `mtk_ccuv` | source |
| `/soc/clock-buffer-ctrl` | `mediatek,mt6895-clkbuf` | `clkbuf` | source |
| `/soc/cpuhvfs@00114400` | `mediatek,cpufreq-hybrid` | — | node platform |
| `/soc/g3d_gpueb@13c40000` | `mediatek,g3d_gpueb` | — | node platform |
| `/soc/g3d_gpueb@13c60200` | `mediatek,g3d_gpueb` | — | node platform |
| `/soc/g3d_gpueb@13c60300` | `mediatek,g3d_gpueb` | — | node platform |
| `/soc/g3d_gpueb@13c60400` | `mediatek,g3d_gpueb` | — | node platform |
| `/soc/g3d_gpueb@13c60800` | `mediatek,g3d_gpueb` | — | node platform |
| `/soc/g3d_gpueb@13c62000` | `mediatek,g3d_gpueb` | — | node platform |
| `/soc/gpu_fdvfs@00112000` | `mediatek,gpu_fdvfs` | — | node platform |
| `/soc/gpueb@13c00000` | `mediatek,gpueb` | `mtk_gpueb` | source |
| `/soc/mminfra_debug_ctl@1e825000` | `mediatek,mminfra_debug_ctl` | — | node platform |
| `/soc/performance-controller@0011bc00` | `mediatek,cpufreq-hw` | `mediatek-cpufreq-hw` | source |
| `/soc/power-controller@1c001000` | `mediatek,mt6895-scpsys|syscon` | — | node platform |
| `/soc/scp_infra@10001000` | `mediatek,scpinfra` | `scp` | source |
| `/soc/sleep_sram@1001e000` | `mediatek,sleep_sram` | — | node platform |
| `/soc/sleep_sram@1001f000` | `mediatek,sleep_sram` | — | node platform |
| `/soc/sleep_sram@10020000` | `mediatek,sleep_sram` | — | node platform |
| `/soc/sleep_sram@10021000` | `mediatek,sleep_sram` | — | node platform |
| `/soc/smi-sysram-comm@1e80b000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon` | — | node platform |
| `/soc/smi-sysram-subcomm2@1e80c000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi-sysram-subcomm3@1e80d000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi-sysram-subcomm4@1e80e000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/sramrom@10214000` | `mediatek,sramrom` | — | node platform |
| `/soc/srclken-rc@1c00d000` | `mediatek,srclken-rc` | — | node platform |
| `/soc/syscon@13f91000` | `mediatek,mt6895-gpu_eb_rpc_bus|syscon` | — | node platform |
| `/soc/syscon@13fa0800` | `mediatek,mt6895-gpuebpll_pll_ctrl|syscon` | — | node platform |
| `/soc/syscon@13fa0c00` | `mediatek,mt6895-mfgscpll_pll_ctrl|syscon` | — | node platform |
| `/sspm@1C340000` | `mediatek,sspm` | `sspm_v3` | source |
| `/ssram1@1C350000` | `mmio-sram_1` | — | node platform |
| `/ssram1@1C350000/tiny_mbox@0` | `arm,scmi-shmem` | — | node platform |
| `/ssram2@1C360000` | `mmio-sram_2` | — | node platform |
| `/ssram2@1C360000/tiny_mbox@1` | `arm,scmi-shmem` | — | node platform |
| `/syscon@50000000` | `mediatek,ktf-clkmgr-clk|syscon` | — | node platform |

### Modem / Jaringan seluler

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/cmdq-test` | `mediatek,cmdq-test` | `drivers/misc/mediatek/cmdq/mailbox/cmdq-test.c` | built-in |
| `/disable_unused` | `simple-bus` | — | node platform |
| `/hre_top_mdpsys@1f817000` | `mediatek,hre_top_mdpsys` | — | node platform |
| `/ktf-cmdq-test` | `mediatek,ktf-cmdq-test` | — | node platform |
| `/ktf-mmdvfs-test` | `mediatek,ktf-mmdvfs-test` | — | node platform |
| `/md-cooler` | `mediatek,mt6298-md-cooler` | `md_cooling_all` | source |
| `/mdp-aal@1f007000` | `mediatek,mdp_aal0` | — | node platform |
| `/mdp-aal@1f008000` | `mediatek,mdp_aal1` | — | node platform |
| `/mdp-color@1f00d000` | `mediatek,mdp_color0` | — | node platform |
| `/mdp-color@1f00e000` | `mediatek,mdp_color1` | — | node platform |
| `/mdp-fg@1f011000` | `mediatek,mdp_fg0` | — | node platform |
| `/mdp-fg@1f012000` | `mediatek,mdp_fg1` | — | node platform |
| `/mdp-hdr@1f005000` | `mediatek,mdp_hdr0` | — | node platform |
| `/mdp-hdr@1f006000` | `mediatek,mdp_hdr1` | — | node platform |
| `/mdp-mutex@1f001000` | `mediatek,mdp_mutex0` | — | node platform |
| `/mdp-rdma@1f003000` | `mediatek,mdp_rdma0` | — | node platform |
| `/mdp-rdma@1f004000` | `mediatek,mdp_rdma1` | — | node platform |
| `/mdp-rsz@1f009000` | `mediatek,mdp_rsz0` | — | node platform |
| `/mdp-rsz@1f00a000` | `mediatek,mdp_rsz1` | — | node platform |
| `/mdp-tdshp@1f00b000` | `mediatek,mdp_tdshp0` | — | node platform |
| `/mdp-tdshp@1f00c000` | `mediatek,mdp_tdshp1` | — | node platform |
| `/mdp-wrot@1f00f000` | `mediatek,mdp_wrot0` | — | node platform |
| `/mdp-wrot@1f010000` | `mediatek,mdp_wrot1` | — | node platform |
| `/mdp@1f000000` | `mediatek,mdp` | `drivers/misc/mediatek/mdp/mdp_driver.c` | built-in |
| `/mdpm` | `mediatek,mt6895-mdpm` | `mtk_mdpm` | source |
| `/mdpsys-config@1f000000` | `mediatek,mdpsys_config` | `drivers/misc/mediatek/mdp/mdp_ioctl_ex.c` | built-in |
| `/mmdvfs` | `mediatek,mmdvfs` | `mtk-mmdvfs` | source |
| `/odm` | `simple-bus` | — | node platform |
| `/reserved-memory/ccci-dpmaif-cache-memory` | `mediatek,dpmaif-resv-cache-mem` | — | node platform |
| `/reserved-memory/ccci-dpmaif-nocache-memory` | `mediatek,dpmaif-resv-nocache-mem` | — | node platform |
| `/soc` | `simple-bus` | — | node platform |
| `/soc/ap_ccif0@10209000` | `mediatek,ap_ccif0` | — | node platform |
| `/soc/ap_ccif1@1020b000` | `mediatek,ap_ccif1` | — | node platform |
| `/soc/ap_ccif2@1023c000` | `mediatek,ap_ccif2` | — | node platform |
| `/soc/ap_ccif3@1023e000` | `mediatek,ap_ccif3` | — | node platform |
| `/soc/ap_ccif4@1024c000` | `mediatek,ap_ccif4` | — | node platform |
| `/soc/ap_ccif5@1025c000` | `mediatek,ap_ccif5` | — | node platform |
| `/soc/apusys_rv/apu_mdw_rpmsg` | `mediatek,apu-mdw-rpmsg-v2` | `drivers/misc/mediatek/apusys/midware/2.0/mdw_drv.c` | built-in |
| `/soc/apusys_rv/mdla_rx_rpmsg` | `mediatek,mdla-rx-rpmsg` | `drivers/misc/mediatek/apusys/mdla/utilities/mdla_ipi.c` | built-in |
| `/soc/apusys_rv/mdla_tx_rpmsg` | `mediatek,mdla-tx-rpmsg` | `drivers/misc/mediatek/apusys/mdla/utilities/mdla_ipi.c` | built-in |
| `/soc/ccifdriver@10209000` | `mediatek,ccci_ccif` | `ccci_ccif` | source |
| `/soc/dbg_mdsys1@0d100000` | `mediatek,dbg_mdsys1` | — | node platform |
| `/soc/devapc_ao_md@10019000` | `mediatek,devapc_ao_md` | — | node platform |
| `/soc/dpmaif@10014000` | `mediatek,dpmaif` | `ccci_dpmaif` | source |
| `/soc/infra_dpmaif@1022c000` | `mediatek,infra_dpmaif` | — | node platform |
| `/soc/infra_dpmaif@1022d000` | `mediatek,infra_dpmaif` | — | node platform |
| `/soc/infra_dpmaif@1022e000` | `mediatek,infra_dpmaif` | — | node platform |
| `/soc/infra_dpmaif@1022f000` | `mediatek,infra_dpmaif` | — | node platform |
| `/soc/infra_md@1021d000` | `mediatek,infra_md` | — | node platform |
| `/soc/md2md_md1_ccif0@10211000` | `mediatek,md2md_md1_ccif0` | — | node platform |
| `/soc/md2md_md2_ccif0@10213000` | `mediatek,md2md_md2_ccif0` | — | node platform |
| `/soc/md_ccif0@1020a000` | `mediatek,md_ccif0` | — | node platform |
| `/soc/md_ccif1@1020c000` | `mediatek,md_ccif1` | — | node platform |
| `/soc/md_ccif2@1023d000` | `mediatek,md_ccif2` | — | node platform |
| `/soc/md_ccif3@1023f000` | `mediatek,md_ccif3` | — | node platform |
| `/soc/md_ccif4@1024d000` | `mediatek,md_ccif4` | — | node platform |
| `/soc/md_ccif5@1025d000` | `mediatek,md_ccif5` | — | node platform |
| `/soc/mdcldmain@1021c000` | `mediatek,mdcldmain` | — | node platform |
| `/soc/mddriver` | `mediatek,mddriver` | `drivers/misc/mediatek/eccci/fsm/md_sys1_platform.c` | built-in |
| `/soc/mdla` | `mediatek, mdla-rv` | `apusys` | source |
| `/soc/mdp_rsi0@1e815000` | `mediatek,mdp_rsi0` | — | node platform |
| `/soc/mdp_rsi1@1e816000` | `mediatek,mdp_rsi1` | — | node platform |
| `/soc/modem_temp_share@10018000` | `mediatek,modem_temp_share` | — | node platform |
| `/soc/opp-table-mdp0` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/soc/opp-table-mdp1` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/soc/radio_md_cfg` | `mediatek,radio_md_cfg` | — | node platform |
| `/soc/sleep_reg_md@1000f000` | `mediatek,sleep_reg_md` | — | node platform |
| `/soc/smi-mdp-comm@1e80f000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon` | — | node platform |
| `/soc/smi-mdp-subcomm4@1e817000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi-mdp-subcomm5@1e818000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi_mdp_m0_rsi_regs@1e815000` | `mediatek,smi-rsi` | — | node platform |
| `/soc/smi_mdp_m1_rsi_regs@1e816000` | `mediatek,smi-rsi` | — | node platform |
| `/soc/syscon@10001000` | `mediatek,mt6895-infracfg_ao|syscon|simple-mfd` | — | node platform |
| `/soc/watchdog@1c007000` | `mediatek,mt6895-wdt|mediatek,mt6589-wdt|syscon|simple-mfd` | — | node platform |
| `/syscon@1f000000` | `mediatek,mt6895-mdpsys|syscon` | — | node platform |
| `/syscon@1f800000` | `mediatek,mt6895-mdpsys1|syscon` | — | node platform |
| `/vmmdbg` | `mediatek,vmm_dbg` | — | node platform |
| `frag@73` | `mediatek,md1_sim1_hot_plug_eint-eint` | — | tidak ada |

### Lain-lain

| Node | compatible | Driver | Asal |
|---|---|---|---|
| `/` | `mediatek,MT6895` | — | node platform |
| `/aie@15310000` | `mediatek,mt8195-aie|mediatek,aie-hw3.0` | `mtk_aie_71` | source |
| `/apu_top_3` | `mt6895,apu_top_3` | `drivers/misc/mediatek/apusys/power/3.0/aputop_drv.c` | built-in |
| `/bp_thl` | `mediatek,mtk-bp-thl` | `mtk_bp_thl` | source |
| `/bt@18000000` | `mediatek,bt` | — | node platform |
| `/btif@1100c000` | `mediatek,btif` | `btif_drv` | source |
| `/cm_mgr@0c530000` | `mediatek,mt6895-cm_mgr` | `mtk_cm_mgr_mt6895` | source |
| `/cpus/cpu@000` | `arm,cortex-a55` | — | node platform |
| `/cpus/cpu@001` | `arm,cortex-a55` | — | node platform |
| `/cpus/cpu@002` | `arm,cortex-a55` | — | node platform |
| `/cpus/cpu@003` | `arm,cortex-a55` | — | node platform |
| `/cpus/cpu@100` | `arm,cortex-a78` | — | node platform |
| `/cpus/cpu@101` | `arm,cortex-a78` | — | node platform |
| `/cpus/cpu@102` | `arm,cortex-a78` | — | node platform |
| `/cpus/cpu@200` | `arm,cortex-a78` | — | node platform |
| `/cpus/idle-states/clusteroff_b` | `arm,idle-state` | `kernel-6.12/drivers/cpuidle/cpuidle-arm.c` | built-in |
| `/cpus/idle-states/clusteroff_l` | `arm,idle-state` | `kernel-6.12/drivers/cpuidle/cpuidle-arm.c` | built-in |
| `/cpus/idle-states/cpuoff_b` | `arm,idle-state` | `kernel-6.12/drivers/cpuidle/cpuidle-arm.c` | built-in |
| `/cpus/idle-states/cpuoff_l` | `arm,idle-state` | `kernel-6.12/drivers/cpuidle/cpuidle-arm.c` | built-in |
| `/cpus/idle-states/mcusysoff` | `arm,idle-state` | `kernel-6.12/drivers/cpuidle/cpuidle-arm.c` | built-in |
| `/cpus/idle-states/s2idle` | `arm,idle-state` | `kernel-6.12/drivers/cpuidle/cpuidle-arm.c` | built-in |
| `/cpus/idle-states/system_bus` | `arm,idle-state` | `kernel-6.12/drivers/cpuidle/cpuidle-arm.c` | built-in |
| `/cpus/idle-states/system_mem` | `arm,idle-state` | `kernel-6.12/drivers/cpuidle/cpuidle-arm.c` | built-in |
| `/cpus/idle-states/system_pll` | `arm,idle-state` | `kernel-6.12/drivers/cpuidle/cpuidle-arm.c` | built-in |
| `/dp-tx@14800000` | `mediatek,mt6895-dp_tx|mediatek,dp_tx` | `drivers/gpu/drm/mediatek/mediatek_v2/mtk_dp.c` | built-in |
| `/dsu-pmu-0` | `arm,dsu-pmu` | `arm_dsu_pmu` | source |
| `/dvp@15300800` | `mediatek,dvp` | `mtkcam/mtk-dpe/isp_8/camera_dpe.c` | built-in |
| `/dvs@15300000` | `mediatek,dvs` | `mtkcam/mtk-dpe/isp_8/camera_dpe.c` | built-in |
| `/firmware/scmi` | `arm,scmi` | `kernel-6.12/drivers/firmware/arm_scmi/transports/mailbox.c` | built-in |
| `/fm@18000000` | `mediatek,fm` | — | node platform |
| `/gce-mbox-m-sec@1e990000` | `mediatek,mailbox-gce-sec` | `cmdq-sec-drv` | source |
| `/gce-mbox-sec@1e980000` | `mediatek,mailbox-gce-sec` | `cmdq-sec-drv` | source |
| `/gce@1e980000` | `mediatek,mt6895-gce` | `mtk-cmdq-drv-ext` | source |
| `/gce@1e990000` | `mediatek,mt6895-gce` | `mtk-cmdq-drv-ext` | source |
| `/ged` | `mediatek,ged` | `%s u0=%u u1=%u u2=%u u3=%u u4=%u u5=%u u6=%u u7=%u t0=%u t1=%u t2=%u t3=%u t4=%u t5=%u t6=%u t7=%u` | source |
| `/hcp@0` | `mediatek,hcp71` | `mtk_hcp_isp71` | source |
| `/hypervisor` | `mediatek,geniezone-hyp|mediatek,geniezone` | `kernel-6.12/drivers/virt/geniezone/gzvm_main.c` | built-in |
| `/interrupt-controller` | `arm,gic-v3` | — | node platform |
| `/ipesys_me@15320000` | `mediatek,ipesys-me` | `mtk_ipesys_me` | source |
| `/ispdvfs` | `mediatek,ispdvfs` | `mtk-vmm-isp71-regulator` | source |
| `/jpgdec0@17040000` | `mediatek,jpgdec` | `jpeg-driver` | source |
| `/jpgenc@17030000` | `mediatek,mtk-jpgenc` | `mtk_jpeg` | source |
| `/jpgenc@17830000` | `mediatek,mtk-jpgenc_c1` | `mtk_jpeg` | source |
| `/lastbus` | `mediatek,lastbus` | `last_bus` | source |
| `/lvts@10315000` | `mediatek,mt6895-lvts` | `soc_temp_lvts` | source |
| `/mbist@17060000` | `mediatek,mbist` | — | node platform |
| `/mbist@17860000` | `mediatek,mbist` | — | node platform |
| `/memory-ssmr-features` | `mediatek,memory-ssmr-features` | — | node platform |
| `/met/met-emi` | `mediatek,met_emi` | — | node platform |
| `/met/met-res-ram` | `mediatek,met_res_ram` | — | node platform |
| `/mml-aal0@1f807000` | `mediatek,mt6895-mml_aal0` | `mtk_mml` | source |
| `/mml-aal1@1f808000` | `mediatek,mt6895-mml_aal1` | `mtk_mml` | source |
| `/mml-ait` | `mediatek,mml-ait` | — | node platform |
| `/mml-color0@1f80d000` | `mediatek,mt6895-mml_color|mediatek,mml-tuning-mml_color` | `mtk_mml` | source |
| `/mml-color1@1f80e000` | `mediatek,mt6895-mml_color|mediatek,mml-tuning-mml_color` | `mtk_mml` | source |
| `/mml-hdr0@1f805000` | `mediatek,mt6895-mml_hdr` | `mtk_mml` | source |
| `/mml-hdr1@1f806000` | `mediatek,mt6895-mml_hdr` | `mtk_mml` | source |
| `/mml-mutex0@1f801000` | `mediatek,mt6895-mml_mutex` | `mtk_mml` | source |
| `/mml-rdma0@1f803000` | `mediatek,mt6895-mml_rdma0` | `mtk_mml` | source |
| `/mml-rdma1@1f804000` | `mediatek,mt6895-mml_rdma1` | `mtk_mml` | source |
| `/mml-rsz0@1f809000` | `mediatek,mt6895-mml_rsz0` | `mtk_mml` | source |
| `/mml-rsz1@1f80a000` | `mediatek,mt6895-mml_rsz1` | `mtk_mml` | source |
| `/mml-rsz2@1f813000` | `mediatek,mt6895-mml_rsz2` | `mtk_mml` | source |
| `/mml-rsz3@1f814000` | `mediatek,mt6895-mml_rsz3` | `mtk_mml` | source |
| `/mml-tdshp0@1f80b000` | `mediatek,mt6895-mml_tdshp|mediatek,mml-tuning-mml_tdshp` | `mtk_mml` | source |
| `/mml-tdshp1@1f80c000` | `mediatek,mt6895-mml_tdshp|mediatek,mml-tuning-mml_tdshp` | `mtk_mml` | source |
| `/mml-test` | `mediatek,mml-test` | `drivers/gpu/drm/mediatek/mml/mtk-mml-test.c` | built-in |
| `/mml-wrot0@1f80f000` | `mediatek,mt6895-mml_wrot` | `mtk_mml` | source |
| `/mml-wrot1@1f810000` | `mediatek,mt6895-mml_wrot` | `mtk_mml` | source |
| `/mml-wrot2@1f815000` | `mediatek,mt6895-mml_wrot` | `mtk_mml` | source |
| `/mml-wrot3@1f816000` | `mediatek,mt6895-mml_wrot` | `mtk_mml` | source |
| `/mmlsys-config@1f800000` | `mediatek,mt6895-mml` | `mtk_mml` | source |
| `/mobicore` | `trustonic,mobicore` | — | node platform |
| `/mrdump_ext_rst` | `mediatek, mrdump_ext_rst-eint` | — | node platform |
| `/mt-soc-offload-common` | `mediatek,mt-soc-offload-common` | `mtk_soc_offload_common` | source |
| `/mtk-ctd` | `mediatek,mtk_ctd` | `drivers/power/supply/mtk_chg_type_det.c` | built-in |
| `/mtk_composite_v4l2_1` | `mediatek,mtk_composite_v4l2_1` | `mtk_composite` | source |
| `/mtk_composite_v4l2_2` | `mediatek,mtk_composite_v4l2_2` | `camera_af_media` | source |
| `/mtk_lpm` | `mediatek,mtk-lpm` | `mtk_lpm_dbg_common_v1_legacy` | source |
| `/mtk_lpm/mcusys-ctrl@0c53a000` | `mediatek,mcusys-ctrl` | — | node platform |
| `/nebula` | `android,nebula-smc-v1` | `gz_trusty_mod` | source |
| `/nebula-log` | `android,nebula-log-v1` | — | node platform |
| `/nebula/nebula-irq` | `android,nebula-irq-v1` | `gz_irq_mod` | source |
| `/nebula/nebula-virtio` | `android,nebula-virtio-v1` | `gz_virtio_mod` | source |
| `/opp-table-ccu` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/opp-table-img` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/opp-table-ipe` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/opp-table0` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/pbm` | `mediatek,pbm` | `mtk_pbm` | source |
| `/pdchk` | `mediatek,mt6895-pdchk` | `drivers/clk/mediatek/mtk-pd-chk-mt6895.c` | built-in |
| `/pmu` | `arm,armv8-pmuv3` | `kernel-6.12/drivers/perf/arm_pmuv3.c` | built-in |
| `/protected-memory-allocator` | `arm,protected-memory-allocator` | `mali_prot_alloc_mt6895_a16w` | source |
| `/psci` | `arm,psci-1.0` | `kernel-6.12/drivers/firmware/psci/psci.c` | built-in |
| `/qos@0011bb00` | `mediatek,mt6893-qos` | `mtk_qos` | source |
| `/remoteproc_ccd@1a030000` | `mediatek,ccd` | `mtk_ccd_remoteproc` | source |
| `/reserved-memory/reserve-memory-vcp_share` | `mediatek,reserve-memory-vcp_share` | — | node platform |
| `/reserved-memory/ssheap-reserved-cma_memory` | `shared-dma-pool` | `kernel-6.12/drivers/of/of_reserved_mem.c` | built-in |
| `/reserved-memory/ssmr-reserved-cma_memory` | `shared-dma-pool` | `kernel-6.12/drivers/of/of_reserved_mem.c` | built-in |
| `/sleep@1C001000` | `mediatek,sleep` | `drivers/misc/mediatek/spm/plat_k68/mtk_spm.c` | built-in |
| `/smi-larb2@1f002000` | `mediatek,smi_larb2|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/smi-larb3@1f802000` | `mediatek,smi_larb3|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/smi-test` | `mediatek,smi-testcase` | — | node platform |
| `/soc/aes_top0@10016000` | `mediatek,aes_top0` | — | node platform |
| `/soc/apcldmain@1021f000` | `mediatek,apcldmain` | — | node platform |
| `/soc/apcldmain_ao@10014000` | `mediatek,apcldmain_ao` | — | node platform |
| `/soc/apcldmamisc@1021b800` | `mediatek,apcldmamisc` | — | node platform |
| `/soc/apcldmamisc@1021bc00` | `mediatek,apcldmamisc` | — | node platform |
| `/soc/apcldmamisc_ao@10014800` | `mediatek,apcldmamisc_ao` | — | node platform |
| `/soc/apcldmamisc_ao@10014c00` | `mediatek,apcldmamisc_ao` | — | node platform |
| `/soc/apcldmaout@1021b400` | `mediatek,apcldmaout` | — | node platform |
| `/soc/apcldmaout_ao@10014400` | `mediatek,apcldmaout_ao` | — | node platform |
| `/soc/apdma@10220000` | `mediatek,apdma` | — | node platform |
| `/soc/apirq@11e50000` | `mediatek,mt6983-eint` | — | node platform |
| `/soc/apusys_hw_logger` | `mediatek,apusys_hw_logger` | `drivers/misc/mediatek/apusys/hw_logger/hw_logger.c` | built-in |
| `/soc/apusys_reviser@1903c000` | `mediatek, rv-reviser` | `apusys` | source |
| `/soc/apusys_rv` | `mediatek,mt6895-apusys_rv` | `drivers/misc/mediatek/apusys/apusys_rv/apu_rproc.c` | built-in |
| `/soc/apusys_rv/apu_ctrl` | `mediatek,apu-ctrl-rpmsg` | — | node platform |
| `/soc/apusys_rv/apu_edma` | `mediatek,apu-edma-rpmsg` | `drivers/misc/mediatek/apusys/edma/edma_rv.c` | built-in |
| `/soc/apusys_rv/apu_mnoc` | `mediatek,apu-mnoc-rpmsg` | `drivers/misc/mediatek/apusys/mnoc/1.5/common/mnoc_rv.c` | built-in |
| `/soc/apusys_rv/apu_reviser` | `mediatek,apu-reviser-rpmsg` | `drivers/misc/mediatek/apusys/apu_mem/reviser/2.0/common/reviser_drv.c` | built-in |
| `/soc/apusys_rv/apu_top_rpmsg` | `mediatek,aputop-rpmsg` | `drivers/misc/mediatek/apusys/power/3.0/aputop_rpmsg.c` | built-in |
| `/soc/apusys_rv/mvpu_rx_rpmsg` | `mediatek,mvpu-rx-rpmsg` | `drivers/misc/mediatek/apusys/mvpu/platform/v2/2.0/mvpu20_ipi.c` | built-in |
| `/soc/apusys_rv/mvpu_tx_rpmsg` | `mediatek,mvpu-tx-rpmsg` | `drivers/misc/mediatek/apusys/mvpu/platform/v2/2.0/mvpu20_ipi.c` | built-in |
| `/soc/bpi_bsi_slv0@1021e000` | `mediatek,bpi_bsi_slv0` | — | node platform |
| `/soc/bpi_bsi_slv1@1021f000` | `mediatek,bpi_bsi_slv1` | — | node platform |
| `/soc/bpi_bsi_slv2@10225000` | `mediatek,bpi_bsi_slv2` | — | node platform |
| `/soc/bus_dbg@10208000` | `mediatek,bus_dbg` | — | node platform |
| `/soc/bus_parity` | `mediatek,bus-parity` | `drivers/misc/mediatek/sda/bus-parity.c` | built-in |
| `/soc/bus_tracer@0d040000` | `mediatek,bus_tracer-v1` | `drivers/misc/mediatek/sda/bus-parity.c` | built-in |
| `/soc/cache-parity` | `mediatek,mt6873-cache-parity` | `cache-parity` | source |
| `/soc/cq_dma@10212000` | `mediatek,cqdma` | `mtk_cqdma` | source |
| `/soc/dbg_cti@0d020000` | `mediatek,dbg_cti` | — | node platform |
| `/soc/dbg_dem@0d0a0000` | `mediatek,dbg_dem` | — | node platform |
| `/soc/dbg_etr@0d030000` | `mediatek,dbg_etr` | — | node platform |
| `/soc/dbg_tracker2@10218000` | `mediatek,dbg_tracker2` | — | node platform |
| `/soc/dcm@10001000` | `mediatek,mt6895-dcm` | — | node platform |
| `/soc/devapc@10207000` | `mediatek,mt6895-devapc` | `device-apc-mt6895` | source |
| `/soc/devapc_ao_infra_peri@1000e000` | `mediatek,devapc_ao_infra_peri` | — | node platform |
| `/soc/devapc_ao_infra_peri@10022000` | `mediatek,devapc_ao_infra_peri` | — | node platform |
| `/soc/devapc_ao_infra_peri@10023000` | `mediatek,devapc_ao_infra_peri` | — | node platform |
| `/soc/devapc_ao_infra_peri@10024000` | `mediatek,devapc_ao_infra_peri` | — | node platform |
| `/soc/devapc_ao_infra_peri@10025000` | `mediatek,devapc_ao_infra_peri` | — | node platform |
| `/soc/devapc_ao_mm@1001c000` | `mediatek,devapc_ao_mm` | — | node platform |
| `/soc/devapc_mpu_ao@10015000` | `mediatek,devapc_mpu_ao` | — | node platform |
| `/soc/dfd-mcu@c530000` | `mediatek,dfd_mcu` | — | node platform |
| `/soc/dfd@0c600000` | `mediatek,dfd` | — | node platform |
| `/soc/dfd@13d00000` | `mediatek,dfd` | — | node platform |
| `/soc/dfd@13e00000` | `mediatek,dfd` | — | node platform |
| `/soc/dma-controller@11300800` | `mediatek,mt6779-uart-dma` | `mtk_uart_apdma` | source |
| `/soc/dramc@10230000` | `mediatek,mt6895-dramc|mediatek,common-dramc` | `mtk_dramc` | source |
| `/soc/dramc_ch0_rsv@10236000` | `mediatek,dramc_ch0_rsv` | — | node platform |
| `/soc/dramc_ch0_rsv@10238000` | `mediatek,dramc_ch0_rsv` | — | node platform |
| `/soc/dramc_ch0_rsv@1023a000` | `mediatek,dramc_ch0_rsv` | — | node platform |
| `/soc/dramc_ch0_top0@10230000` | `mediatek,dramc_ch0_top0` | — | node platform |
| `/soc/dramc_ch0_top1@10232000` | `mediatek,dramc_ch0_top1` | — | node platform |
| `/soc/dramc_ch0_top2@10234000` | `mediatek,dramc_ch0_top2` | — | node platform |
| `/soc/dramc_ch0_top3@10235000` | `mediatek,dramc_ch0_top3` | — | node platform |
| `/soc/dramc_ch1_rsv@10246000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10248000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@1024a000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10256000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10258000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@1025a000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10266000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10268000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@1026a000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10900000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10940000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10a00000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10a40000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10b00000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10b40000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10c00000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_rsv@10c40000` | `mediatek,dramc_ch1_rsv` | — | node platform |
| `/soc/dramc_ch1_top0@10240000` | `mediatek,dramc_ch1_top0` | — | node platform |
| `/soc/dramc_ch1_top0@10250000` | `mediatek,dramc_ch1_top0` | — | node platform |
| `/soc/dramc_ch1_top0@10260000` | `mediatek,dramc_ch1_top0` | — | node platform |
| `/soc/dramc_ch1_top1@10242000` | `mediatek,dramc_ch1_top1` | — | node platform |
| `/soc/dramc_ch1_top1@10252000` | `mediatek,dramc_ch1_top1` | — | node platform |
| `/soc/dramc_ch1_top1@10262000` | `mediatek,dramc_ch1_top1` | — | node platform |
| `/soc/dramc_ch1_top2@10244000` | `mediatek,dramc_ch1_top2` | — | node platform |
| `/soc/dramc_ch1_top2@10254000` | `mediatek,dramc_ch1_top2` | — | node platform |
| `/soc/dramc_ch1_top2@10264000` | `mediatek,dramc_ch1_top2` | — | node platform |
| `/soc/dramc_ch1_top3@10245000` | `mediatek,dramc_ch1_top3` | — | node platform |
| `/soc/dramc_ch1_top3@10255000` | `mediatek,dramc_ch1_top3` | — | node platform |
| `/soc/dramc_ch1_top3@10265000` | `mediatek,dramc_ch1_top3` | — | node platform |
| `/soc/dvfsrc@1c00f000` | `mediatek,mt6895-dvfsrc` | `mtk_dvfsrc_regulator`, `mtk_emi` | source |
| `/soc/dvfsrc@1c00f000/dvfsrc-helper` | `mediatek,dvfsrc-helper` | `mtk-dvfsrc-helper` | source |
| `/soc/dvfsrc@1c00f000/dvfsrc-met` | `mediatek,dvfsrc-met` | `drivers/misc/mediatek/dvfsrc/dvfsrc-met.c` | built-in |
| `/soc/dxcc_sec@10210000` | `mediatek,dxcc_sec` | — | node platform |
| `/soc/eas-info` | `mediatek,eas-info` | — | node platform |
| `/soc/emi-fake-eng@1026c000` | `mediatek,emi-fake-engine` | `drivers/memory/mediatek/mtk-emi-fake-eng.c` | built-in |
| `/soc/emicen@10219000` | `mediatek,mt6877-emicen|mediatek,common-emicen` | `drivers/memory/mediatek/emicen.c` | built-in |
| `/soc/emichn@10235000` | `mediatek,mt6877-emichn|mediatek,common-emichn` | — | node platform |
| `/soc/emiisu` | `mediatek,mt6983-emiisu|mediatek,common-emiisu` | `drivers/memory/mediatek/emiisu.c` | built-in |
| `/soc/emimpu@10226000` | `mediatek,mt6983-emimpu` | `emi_mpu_v2` | source |
| `/soc/emislb@10342000` | `mediatek,common-emislb` | `emi_slb` | source |
| `/soc/fhctl@1000ce00` | `mediatek,mt6895-fhctl` | `drivers/clk/mediatek/clk-fhctl.c` | built-in |
| `/soc/g3d_brisket@13bfee00` | `mediatek,g3d_brisket` | — | node platform |
| `/soc/g3d_config@13f90000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fa0000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fa0400` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fa0800` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fa0c00` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fb6000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fb7000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fb9c00` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fbb000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fbd000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fbf000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fca000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fcb000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fcc000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fcd000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fce000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fcf000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fd9000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fda000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fdd000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fde000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_config@13fdf000` | `mediatek,g3d_config` | — | node platform |
| `/soc/g3d_dvfs@13fbc000` | `mediatek,g3d_dvfs` | — | node platform |
| `/soc/g3d_mpu@13bff000` | `mediatek,g3d_mpu` | — | node platform |
| `/soc/gic500@0c000000` | `mediatek,gic500` | — | node platform |
| `/soc/gic_cpu@0c400000` | `mediatek,gic_cpu` | — | node platform |
| `/soc/gpio` | `mediatek,gpio_usage_mapping` | — | node platform |
| `/soc/gpio@10005000` | `mediatek,gpio` | — | node platform |
| `/soc/i2c@11280000` | `mediatek,mt6983-i2c` | `i2c_mt65xx` | source |
| `/soc/i2c@11280000/rt6160@75` | `richtek,rt6160` | `rt6160_regulator` | source |
| `/soc/i2c@11280000/rt6160@75/dbg` | `richtek,rt6160-dbg` | `drivers/misc/mediatek/subpmic/subpmic-dbg.c` | built-in |
| `/soc/i2c@11281000` | `mediatek,mt6983-i2c` | `i2c_mt65xx` | source |
| `/soc/i2c@11281000/gate_ic@11` | `mediatek,gate-ic-i2c` | `rt4831a_drv` | source |
| `/soc/i2c@11281000/ps5170@28` | `parade,ps5170` | `ps5170` | source |
| `/soc/i2c@11d00000` | `mediatek,mt6983-i2c` | `i2c_mt65xx` | source |
| `/soc/i2c@11d01000` | `mediatek,mt6983-i2c` | `i2c_mt65xx` | source |
| `/soc/i2c@11d02000` | `mediatek,mt6983-i2c` | `i2c_mt65xx` | source |
| `/soc/i2c@11d03000` | `mediatek,mt6983-i2c` | `i2c_mt65xx` | source |
| `/soc/i2c@11d04000` | `mediatek,mt6983-i2c` | `i2c_mt65xx` | source |
| `/soc/i2c@11d05000` | `mediatek,mt6983-i2c` | `i2c_mt65xx` | source |
| `/soc/i2c@11d06000` | `mediatek,mt6983-i2c` | `i2c_mt65xx` | source |
| `/soc/i2c@11f40000` | `mediatek,mt6983-i2c` | `i2c_mt65xx` | source |
| `/soc/infra_bcrm@10215000` | `mediatek,infra_bcrm` | — | node platform |
| `/soc/infra_device_mpu@1021a000` | `mediatek,infra_device_mpu` | — | node platform |
| `/soc/infra_device_mpu@1021b000` | `mediatek,infra_device_mpu` | — | node platform |
| `/soc/infra_device_mpu@1021d000` | `mediatek,infra_device_mpu` | — | node platform |
| `/soc/infra_device_mpu@1021e000` | `mediatek,infra_device_mpu` | — | node platform |
| `/soc/infra_device_mpu@10225000` | `mediatek,infra_device_mpu` | — | node platform |
| `/soc/infra_mbist@1020d000` | `mediatek,infra_mbist` | — | node platform |
| `/soc/infracfg@1020e000` | `mediatek,infracfg` | — | node platform |
| `/soc/infracfg_ao@10001000` | `mediatek,infracfg_ao` | `scp` | source |
| `/soc/infracfg_ao_mem@10002000` | `mediatek,infracfg_ao_mem` | — | node platform |
| `/soc/infracfg_ao_mem@10270000` | `mediatek,infracfg_ao_mem` | — | node platform |
| `/soc/infracfg_mem@1021c000` | `mediatek,infracfg_mem` | — | node platform |
| `/soc/iocfg_bl@11d10000` | `mediatek,iocfg_bl` | — | node platform |
| `/soc/iocfg_bm@11d30000` | `mediatek,iocfg_bm` | — | node platform |
| `/soc/iocfg_br@11d40000` | `mediatek,iocfg_br` | — | node platform |
| `/soc/iocfg_brr@11d50000` | `mediatek,iocfg_brr` | — | node platform |
| `/soc/iocfg_lb@11d60000` | `mediatek,iocfg_lb` | — | node platform |
| `/soc/iocfg_lm@11e10000` | `mediatek,iocfg_lm` | — | node platform |
| `/soc/iocfg_lt@11f30000` | `mediatek,iocfg_lt` | — | node platform |
| `/soc/iocfg_rm@11c20000` | `mediatek,iocfg_rm` | — | node platform |
| `/soc/iocfg_rmm@11c40000` | `mediatek,iocfg_rmm` | — | node platform |
| `/soc/iocfg_rt@11c30000` | `mediatek,iocfg_rt` | — | node platform |
| `/soc/iocfg_rtt@11ea0000` | `mediatek,iocfg_rtt` | — | node platform |
| `/soc/iocfg_tl@11f20000` | `mediatek,iocfg_tl` | — | node platform |
| `/soc/iocfg_tr@11eb0000` | `mediatek,iocfg_tr` | — | node platform |
| `/soc/kp@1c00e000` | `mediatek,kp` | `mtk-kpd` | source |
| `/soc/lkg@00114400` | `mediatek,mtk-lkg` | `drivers/misc/mediatek/sched/mtk_energy_model/v1/static_power.c` | built-in |
| `/soc/masp@1c009000` | `mediatek,masp` | `sec` | source |
| `/soc/mbist_ao@10013000` | `mediatek,mbist_ao` | — | node platform |
| `/soc/mcucfg@10200000` | `mediatek,mcucfg` | — | node platform |
| `/soc/mcucfg@10201000` | `mediatek,mcucfg` | — | node platform |
| `/soc/mcucfg@10202000` | `mediatek,mcucfg` | — | node platform |
| `/soc/mcucfg@10203000` | `mediatek,mcucfg` | — | node platform |
| `/soc/miu_kp@10350000` | `mediatek,common-miukp` | — | node platform |
| `/soc/miu_mpu@10352000` | `mediatek,common-miumpu` | — | node platform |
| `/soc/mm_m0_rsi@1e807000` | `mediatek,mm_m0_rsi` | — | node platform |
| `/soc/mm_m1_rsi@1e808000` | `mediatek,mm_m1_rsi` | — | node platform |
| `/soc/mm_vpu_m0_sub_common@1025e000` | `mediatek,mm_vpu_m0_sub_common` | — | node platform |
| `/soc/mm_vpu_m0_sub_common@10309000` | `mediatek,mm_vpu_m0_sub_common` | — | node platform |
| `/soc/mm_vpu_m1_sub_common@1025f000` | `mediatek,mm_vpu_m1_sub_common` | — | node platform |
| `/soc/mm_vpu_m1_sub_common@1030a000` | `mediatek,mm_vpu_m1_sub_common` | — | node platform |
| `/soc/mm_vpu_m1_sub_common@1030b000` | `mediatek,mm_vpu_m1_sub_common` | — | node platform |
| `/soc/mm_vpu_m1_sub_common@1030c000` | `mediatek,mm_vpu_m1_sub_common` | — | node platform |
| `/soc/mm_vpu_m1_sub_common@1030d000` | `mediatek,mm_vpu_m1_sub_common` | — | node platform |
| `/soc/mminfra_bcrm_ao@1e824000` | `mediatek,mminfra_bcrm_ao` | — | node platform |
| `/soc/mminfra_bcrm_pdn@1e827000` | `mediatek,mminfra_bcrm_pdn` | — | node platform |
| `/soc/mminfra_config@1e800000` | `mediatek,mminfra_config` | — | node platform |
| `/soc/mminfra_devapc_ao@1e820000` | `mediatek,mminfra_devapc_ao` | — | node platform |
| `/soc/mminfra_devapc_pdn@1e826000` | `mediatek,mminfra_devapc_pdn` | — | node platform |
| `/soc/mmqos-wrapper` | `mediatek,mt6895-mmqos-wrapper` | `mmqos_wrapper` | source |
| `/soc/mtk_apu_mem_code` | `mediatek, apu_mem_code` | `drivers/misc/mediatek/apusys/apu_mem/apu_sysmem_drv.c` | built-in |
| `/soc/mtk_apu_mem_data` | `mediatek, apu_mem_data` | `drivers/misc/mediatek/apusys/apu_mem/apu_sysmem_drv.c` | built-in |
| `/soc/mtk_ssc@1c01f000` | `mediatek,ssc` | `mtk-ssc` | source |
| `/soc/mtkfb@0` | `mediatek,mtkfb` | — | node platform |
| `/soc/mvpu` | `mediatek, mt6895-mvpu` | `apusys` | source |
| `/soc/opp-table-mminfra` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/soc/opp-table-vdec` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/soc/opp-table-venc` | `operating-points-v2` | `kernel-6.12/drivers/of/platform.c` | built-in |
| `/soc/peri_ptp_therm@10315000` | `mediatek,peri_ptp_therm` | — | node platform |
| `/soc/peri_ptp_therm@10316000` | `mediatek,peri_ptp_therm` | — | node platform |
| `/soc/pericfg@10003000` | `mediatek,pericfg` | `drivers/clk/mediatek/clk-mt6768.c` | built-in |
| `/soc/pinctrl` | `mediatek,mt6895-pinctrl` | `pinctrl-mt6895` | source |
| `/soc/security_ao@1c00b000` | `mediatek,security_ao` | `sec` | source |
| `/soc/sej@1000a000` | `mediatek,sej` | — | node platform |
| `/soc/serial@11001000` | `mediatek,mt6577-uart` | `8250_mtk` | source |
| `/soc/serial@11002000` | `mediatek,mt6577-uart` | `8250_mtk` | source |
| `/soc/slbc@00113c00` | `mediatek,mtk-slbc` | `drivers/misc/mediatek/slbc/slbc_mt6893.c` | built-in |
| `/soc/smi-5x1-sub-comm0@1a005000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi-5x1-sub-comm1@1a007000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi-8x1-sub-comm0@1a006000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi-dbg` | `mediatek,mtk-smi-dbg` | `mtk-smi-dbg` | source |
| `/soc/smi-img-sub-comm0@15002000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi-img-sub-comm1@15003000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi-larb0@14021000` | `mediatek,smi_larb0|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb10@15120000` | `mediatek,smi_larb10|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb11@15230000` | `mediatek,smi_larb11|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb12@15340000` | `mediatek,smi_larb12|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb13@1a001000` | `mediatek,smi_larb13|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb14@1a002000` | `mediatek,smi_larb14|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb15@15140000` | `mediatek,smi_larb15|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb16@1a008000` | `mediatek,smi_larb16|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb17@1a009000` | `mediatek,smi_larb17|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb18@15004000` | `mediatek,smi_larb18|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb19@1b201000` | `mediatek,smi_larb19|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb1@14022000` | `mediatek,smi_larb1|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb20@14421000` | `mediatek,smi_larb20|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb21@14422000` | `mediatek,smi_larb21|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb22@15530000` | `mediatek,smi_larb22|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb23@15630000` | `mediatek,smi_larb23|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb25@1a003000` | `mediatek,smi_larb25|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb26@1a004000` | `mediatek,smi_larb26|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb27@1a00a000` | `mediatek,smi_larb27|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb28@1a00c000` | `mediatek,smi_larb28|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb29@1a00b000` | `mediatek,smi_larb29|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb30@1a00d000` | `mediatek,smi_larb28|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb4@1602e000` | `mediatek,vdec|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb5@1600d000` | `mediatek,vdec|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb6@16009000` | `mediatek,vdec|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb7@17010000` | `mediatek,smi_larb7|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb8@17810000` | `mediatek,smi_larb8|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-larb9@15001000` | `mediatek,smi_larb9|mediatek,mt6895-smi-larb|mediatek,smi-larb` | `mtk-smi` | source |
| `/soc/smi-sub-comm0@14023000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi-sub-comm1@14423000` | `mediatek,mt6895-smi-common|mediatek,smi-common|syscon|mediatek,smi-sub-common` | — | node platform |
| `/soc/smi_mm_m0_rsi_regs@1e807000` | `mediatek,smi-rsi` | — | node platform |
| `/soc/smi_mm_m1_rsi_regs@1e808000` | `mediatek,smi-rsi` | — | node platform |
| `/soc/spi0@11010000` | `mediatek,mt6983-spi` | `spi_mt65xx` | source |
| `/soc/spi1@11011000` | `mediatek,mt6983-spi` | `spi_mt65xx` | source |
| `/soc/spi2@11012000` | `mediatek,mt6983-spi` | `spi_mt65xx` | source |
| `/soc/spi3@11013000` | `mediatek,mt6983-spi` | `spi_mt65xx` | source |
| `/soc/spi4@11014000` | `mediatek,mt6983-spi` | `spi_mt65xx` | source |
| `/soc/spi5@11015000` | `mediatek,mt6983-spi` | `spi_mt65xx` | source |
| `/soc/spi6@11016000` | `mediatek,mt6983-spi` | `spi_mt65xx` | source |
| `/soc/spi7@11017000` | `mediatek,mt6983-spi` | `spi_mt65xx` | source |
| `/soc/sub_infra_bcrm@10216000` | `mediatek,sub_infra_bcrm` | — | node platform |
| `/soc/swpm` | `mediatek,mtk-swpm` | — | node platform |
| `/soc/sys_cirq@10204000` | `mediatek,sys_cirq` | — | node platform |
| `/soc/sys_cirq@10312000` | `mediatek,sys_cirq` | — | node platform |
| `/soc/sys_cirq@10313000` | `mediatek,sys_cirq` | — | node platform |
| `/soc/sys_cirq@10314000` | `mediatek,sys_cirq` | — | node platform |
| `/soc/sys_cirq@10350000` | `mediatek,sys_cirq` | — | node platform |
| `/soc/sys_cirq@10351000` | `mediatek,sys_cirq` | — | node platform |
| `/soc/sys_cirq@10352000` | `mediatek,sys_cirq` | — | node platform |
| `/soc/sys_cirq@10354000` | `mediatek,sys_cirq` | — | node platform |
| `/soc/sys_cirq@10355000` | `mediatek,sys_cirq` | — | node platform |
| `/soc/sys_cirq@10356000` | `mediatek,sys_cirq` | — | node platform |
| `/soc/syscon@10000000` | `mediatek,mt6895-topckgen|syscon` | — | node platform |
| `/soc/syscon@10001000/reset-controller` | `ti,syscon-reset` | `reset_ti_syscon` | source |
| `/soc/syscon@1000c000` | `mediatek,mt6895-apmixedsys|syscon` | — | node platform |
| `/soc/syscon@10270000` | `mediatek,mt6985-nemi_bus|syscon` | — | node platform |
| `/soc/syscon@1030e000` | `mediatek,mt6985-semi_bus|syscon` | — | node platform |
| `/soc/syscon@10320000` | `mediatek,mt6895-hwv|syscon` | — | node platform |
| `/soc/syscon@11036000` | `mediatek,mt6895-pericfg_ao|syscon` | — | node platform |
| `/soc/syscon@11282000` | `mediatek,mt6895-imp_iic_wrap_c|syscon` | — | node platform |
| `/soc/syscon@112b8000/reset-controller` | `ti,syscon-reset` | `reset_ti_syscon` | source |
| `/soc/syscon@112bc000/reset-controller` | `ti,syscon-reset` | `reset_ti_syscon` | source |
| `/soc/syscon@11d07000` | `mediatek,mt6895-imp_iic_wrap_s|syscon` | — | node platform |
| `/soc/syscon@11f41000` | `mediatek,mt6895-imp_iic_wrap_w|syscon` | — | node platform |
| `/soc/syscon@13fa0000` | `mediatek,mt6895-mfgpll_pll_ctrl|syscon` | — | node platform |
| `/soc/syscon@13fbf000` | `mediatek,mt6895-mfg|syscon` | — | node platform |
| `/soc/syscon@14000000` | `mediatek,mt6895-mmsys0|syscon` | — | node platform |
| `/soc/syscon@14400000` | `mediatek,mt6895-mmsys1|syscon` | — | node platform |
| `/soc/syscon@15330000` | `mediatek,mt6895-ipesys|syscon` | — | node platform |
| `/soc/syscon@1600f000` | `mediatek,mt6895-vdec_soc_gcon_base|syscon` | — | node platform |
| `/soc/syscon@1602f000` | `mediatek,mt6895-vdec_gcon_base|syscon` | — | node platform |
| `/soc/syscon@17000000` | `mediatek,mt6895-vencsys|syscon` | — | node platform |
| `/soc/syscon@17800000` | `mediatek,mt6895-vencsys_c1|syscon` | — | node platform |
| `/soc/syscon@190f3000` | `mediatek,mt6895-apupll_pll_ctrl|syscon` | — | node platform |
| `/soc/syscon@190f3400` | `mediatek,mt6895-npupll_pll_ctrl|syscon` | — | node platform |
| `/soc/syscon@190f3800` | `mediatek,mt6895-apupll1_pll_ctrl|syscon` | — | node platform |
| `/soc/syscon@1b200000` | `mediatek,mt6895-ccu|syscon` | — | node platform |
| `/soc/syscon@1c00c000` | `mediatek,mt6895-vlpcfg_bus|syscon` | — | node platform |
| `/soc/syscon@1c013000` | `mediatek,mt6895-vlp_cksys|syscon` | — | node platform |
| `/soc/syscon@1e100000` | `mediatek,mt6895-afe|syscon` | — | node platform |
| `/soc/syscon@1e800000` | `mediatek,mt6895-mminfra_config|syscon` | — | node platform |
| `/soc/systimer@1c011000` | `mediatek,mt6895-timer|mediatek,mt6765-timer` | `drivers/clocksource/timer-mediatek.c` | built-in |
| `/soc/topckgen_ao@1001b000` | `mediatek,topckgen_ao` | — | node platform |
| `/soc/topmisc@10011000` | `mediatek,topmisc` | — | node platform |
| `/soc/trng@1020f000` | `mediatek,trng` | — | node platform |
| `/soc/videogo` | `mediatek,videogo` | `videogo` | source |
| `/soc/watchdog@1c007000/reboot-mode` | `syscon-reboot-mode` | `syscon_reboot_mode` | source |
| `/speech-usip-mem` | `mediatek,speech-usip-mem` | `sound/soc/mediatek/common/mtk-usip.c` | built-in |
| `/spmi@1c804000` | `mediatek,mt6895-spmi` | `spmi_mtk_pmif` | source |
| `/spmi_pmif_mpu@1c804900` | `mediatek,mt6895-spmi_pmif_mpu` | `spmi_mtk_mpu` | source |
| `/spmtwam@1c001000` | `mediatek,spmtwam` | — | node platform |
| `/ssheap` | `mediatek,trusted_mem_ssheap` | `trusted_mem` | source |
| `/ssmr` | `mediatek,trusted_mem` | `trusted_mem` | source |
| `/therm_intf@00114000` | `mediatek,therm_intf` | `thermal_interface` | source |
| `/timer` | `arm,armv8-timer` | `kernel-6.12/drivers/clocksource/arm_arch_timer.c` | built-in |
| `/tinysys_mbox@1C351000` | `mediatek,tinysys_mbox` | `mtk-mbox-mailbox` | source |
| `/utos` | `microtrust,utos` | `drivers/tee/teei/510/tz_driver/teei_client_main.c` | built-in |
| `/utos_tester` | `microtrust,tester-v1` | `isee` | source |
| `/vcp@1ec00000` | `mediatek,vcp` | `drivers/misc/mediatek/vcp/rv/vcp_helper.c` | built-in |
| `/vcu@16000000` | `mediatek-vcu` | `drivers/media/platform/mtk-vcu/mtk_vcu.c` | built-in |
| `/vdec-fmt@16005000` | `mediatek-vdec-fmt` | `vdec-fmt` | source |
| `/vdec@1600d000` | `mediatek,vdec` | — | node platform |
| `/vdec@1600f000` | `mediatek,vdec` | — | node platform |
| `/vdec@1600f800` | `mediatek,vdec` | — | node platform |
| `/vdec@16020000` | `mediatek,vdec` | — | node platform |
| `/vdec@1602e000` | `mediatek,vdec` | — | node platform |
| `/vdec@1602f000` | `mediatek,vdec` | — | node platform |
| `/vdec@1602f800` | `mediatek,vdec` | — | node platform |
| `/vdec_gcon@16010000` | `mediatek,vdec_gcon` | `mtk_vcodec_dec` | source |
| `/venc@17820000` | `mediatek,venc` | — | node platform |
| `/venc_gcon@17000000` | `mediatek,venc_gcon` | `mtk_vcodec_enc` | source |
| `/venc_gcon@17800000` | `mediatek,venc_gcon` | `mtk_vcodec_enc` | source |
| `/vmmspm` | `mediatek,vmm_spm` | `drivers/misc/mediatek/vmm_spm/mtk-vmm-spm.c` | built-in |
| `frag@27/hl7139_master@55` | `richtek,hl7139a` | `tc_hl7139a` | source |
| `frag@28/hl7139_slave_change@55` | `richtek,hl7139a` | `tc_hl7139a` | source |
| `frag@31` | `tc_pe5` | — | tidak ada |
| `frag@32/pca_tfcp_ta` | `tc,pca_tfcp_ta` | `pca_tfcp_ta` | source |
| `frag@32/tc_pd_adapter` | `tc,pd_adapter` | `tc_pd_adapter` | source |
| `frag@33/tfcp_ta@1b` | `tc,tfcp_ta` | `tc_tfcp_ta` | source |
| `frag@37/ambient_detect` | `tc,ambient_detect` | `tc_ambient_temp_det` | source |
| `frag@37/tc_adapter_control` | `transsion, adapter_control` | — | tidak ada |
| `frag@37/tc_auto_test` | `tc,auto_test` | `tc_auto_test` | source |
| `frag@37/tc_lcd` | `tc,lcd` | `tc_lcd_notify` | source |
| `frag@37/tc_misc` | `tc,misc_intf` | `tc_misc_intf` | source |
| `frag@37/tc_trancare` | `tc,trancare` | — | tidak ada |
| `frag@37/temp_forecast` | `tc,temp_forecast` | `tc_temp_forecast` | source |
| `frag@45/pixelworks@22` | `pixelworks,iris-i2c` | `drivers/gpu/drm/mediatek/mediatek_v2/v1/iris_i2c.c` | built-in |
| `frag@45/pixelworks@26` | `pixelworks,iris` | `drivers/gpu/drm/mediatek/mediatek_v2/v1/iris_i3c.c` | built-in |
| `frag@50/haptic_hv@5A` | `awinic,haptic_hv` | `tran_richtap_haptic_hv` | source |
| `frag@53/ocp81375_v4l2@63` | `mediatek,ocp81375_v4l2` | `ocp81375_v4l2` | source |
| `frag@53/sgm37864_v4l2@64` | `mediatek,sgm37864_v4l2` | `sgm37864_v4l2` | source |
