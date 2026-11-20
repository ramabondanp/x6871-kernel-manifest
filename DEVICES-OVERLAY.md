# Perangkat X6871 yang hanya ada di fragment overlay (DTBO)

Tabel ini hanya memuat node yang **datang dari overlay** (`frag0.dts`,
hasil decompile `dtbo.img`, `fragment@0`–`fragment@73`), dan bukan dari
base DTB (`base.dts`, 916 node ber-`compatible`).

```text
overlay saja         : 62 node (status okay)
  unik (tidak ada di base) : 57
  juga ada di base         :  5  (regulator-fixed x4, lk_charger)
```

Isi overlay praktis semua hal yang **spesifik X6871**: panel, touch,
kamera + sensor + eeprom + flash, fingerprint, NFC, audio amp, LED
indikator, haptic, dan seluruh stack charging/fast-charging Transsion.

Kolom **Asal**:

| Asal | Arti |
|---|---|
| `source` | ada modul `.ko` hasil build kita yang mengklaim (alias `of:` cocok) |
| `built-in` | driver ada di source, di-link ke kernel |
| `node platform` | node data/flag, tidak punya driver sendiri |
| `**stock**` | hanya modul stock yang mengklaim |
| `**MISMATCH**` | stock punya `of_match`, build kita tidak -> driver tidak akan bind |
| `tidak ada` | tidak ada driver |

Cara regenerasi:

```sh
cd /serverhive1/ramabondanp
M=w1vo36-kernel-manifest/tools
./$M/dts-devices.py tmp/x6871/frag0.dts > cmp-out/dev-overlay.tsv
./$M/dts-devices.py tmp/x6871/base.dts > cmp-out/dev-base.tsv
BASE_TSV=cmp-out/dev-base.tsv ./$M/dt-device-table.py \
    cmp-out/dev-overlay.tsv cmp-out/compat-map.tsv \
    cmp-out/compat-src.txt cmp-out/src-module.tsv cmp-out/compat-dtsi.txt
```

## Ringkasan

```text
module=50, builtin=6, dt=2, tidak ada=4     (tanpa MISMATCH)
```

- `frag@53` flash LED (`ocp81375_v4l2`, `sgm37864_v4l2`): sempat `MISMATCH`
  karena `of_match` tidak memakai sufiks `_v4l2`. Sudah diperbaiki di tree
  kernel (commit `7cdb969799b3`).
- 4 node tanpa driver (`tc_adapter_control`, `tc_trancare`, `tc_pe5`,
  `md1_sim1_hot_plug_eint-eint`) dibahas di `DEVICES.md` §Temuan 2;
  hanya `tc,trancare` yang benar-benar kehilangan fitur.
- `frag@45/pixelworks@22` dan `@26`: chip Pixelworks iris (display
  processing) — drivernya built-in di `mediatek_drm_v1`, tidak ada `.ko`.

## Tabel

### USB / Type-C / Charging

| Node | compatible | Driver | Asal | juga di base |
|---|---|---|---|---|
| `frag@1/sliptswitch_gpio_audioswitch` | `transsion,sliptswitch-gpio-audioswitch` | `splitswitch-gpio` | source | **tidak** |
| `frag@22` | `transsion,extcon-usb` | `tran_extcon_usb` | source | **tidak** |
| `frag@27/hl7139_master@55` | `richtek,hl7139a` | `tc_hl7139a` | source | **tidak** |
| `frag@28/hl7139_slave_change@55` | `richtek,hl7139a` | `tc_hl7139a` | source | **tidak** |
| `frag@29/usb_control` | `transsion, usb_control` | `tran_usb_ctrl` | source | **tidak** |
| `frag@32/pca_tfcp_ta` | `tc,pca_tfcp_ta` | `pca_tfcp_ta` | source | **tidak** |
| `frag@32/tc_pd_adapter` | `tc,pd_adapter` | `tc_pd_adapter` | source | **tidak** |
| `frag@33/tfcp_ta@1b` | `tc,tfcp_ta` | `tc_tfcp_ta` | source | **tidak** |
| `frag@37/ambient_detect` | `tc,ambient_detect` | `tc_ambient_temp_det` | source | **tidak** |
| `frag@37/pid_chg` | `tc,pid_chg_algo` | `tc_pid_chg_algo` | source | **tidak** |
| `frag@37/tc_30` | `transsion,tc30_charger` | `tc_tc30_algo` | source | **tidak** |
| `frag@37/tc_adapter_control` | `transsion, adapter_control` | — | tidak ada | **tidak** |
| `frag@37/tc_auto_test` | `tc,auto_test` | `tc_auto_test` | source | **tidak** |
| `frag@37/tc_chgtype` | `tc_chgtype` | `tc_chg_type_det` | source | **tidak** |
| `frag@37/tc_gauge` | `tc_gauge` | `tc_gauge` | source | **tidak** |
| `frag@37/tc_hvdcp20` | `transsion,hvdcp20_charger` | `tc_hvdcp20_algo` | source | **tidak** |
| `frag@37/tc_lcd` | `tc,lcd` | `tc_lcd_notify` | source | **tidak** |
| `frag@37/tc_misc` | `tc,misc_intf` | `tc_misc_intf` | source | **tidak** |
| `frag@37/tc_pd` | `transsion,pd_charger` | `tc_pd_algo` | source | **tidak** |
| `frag@37/tc_pe2` | `transsion,pe20_charger` | `tc_pe20_algo` | source | **tidak** |
| `frag@37/tc_pmic` | `tc_pmic` | `tc_pmic` | source | **tidak** |
| `frag@37/tc_tcpc` | `tc_tcpc` | `tc_tcpc` | source | **tidak** |
| `frag@37/tc_trancare` | `tc,trancare` | — | tidak ada | **tidak** |
| `frag@37/temp_forecast` | `tc,temp_forecast` | `tc_temp_forecast` | source | **tidak** |
| `frag@37/tran_otg` | `tran,otg_fun` | `tc_otg_ctrl` | source | **tidak** |
| `frag@38` | `tc,charger` | `tc_charger_framework` | source | **tidak** |
| `frag@43` | `mediatek,lk_charger` | — | node platform | ya |
| `frag@5/tran_ldo@28` | `tran,tran_ldo` | `tran_ldo` | source | **tidak** |
| `frag@63/tran_ldo@28` | `tran,tran_ldo` | `tran_ldo` | source | **tidak** |

### Display / Touch / LED

| Node | compatible | Driver | Asal | juga di base |
|---|---|---|---|---|
| `frag@1/led@6` | `mediatek,lcd-backlight` | — | node platform | **tidak** |
| `frag@19/panel1@0` | `rm69220,fhdp,dsi,vdo,dsc,csot,csot,144hz,x6871` | `panel_rm69220_vdo_x6871` | source | **tidak** |
| `frag@2` | `mediatek,disp-leds` | `leds_mtk_disp` | source | **tidak** |
| `frag@24/tran_led_core` | `tran,led_core` | `tran_led_core` | source | **tidak** |
| `frag@25/aw22xxx_led@6a` | `awinic,aw22xxx_led` | `leds-aw22xxx` | source | **tidak** |
| `frag@45/pixelworks@22` | `pixelworks,iris-i2c` | `drivers/gpu/drm/mediatek/mediatek_v2/v1/iris_i2c.c` | built-in | **tidak** |
| `frag@45/pixelworks@26` | `pixelworks,iris` | `drivers/gpu/drm/mediatek/mediatek_v2/v1/iris_i3c.c` | built-in | **tidak** |
| `frag@47/touch@0` | `goodix,gt9916` | `gt9916_common` | source | **tidak** |

### Kamera / Flash

| Node | compatible | Driver | Asal | juga di base |
|---|---|---|---|---|
| `frag@51/seninf_csi_port_0` | `mediatek,seninf` | `mtk_cam_isp` | source | **tidak** |
| `frag@51/seninf_csi_port_1` | `mediatek,seninf` | `mtk_cam_isp` | source | **tidak** |
| `frag@51/seninf_csi_port_2` | `mediatek,seninf` | `mtk_cam_isp` | source | **tidak** |
| `frag@51/seninf_csi_port_3` | `mediatek,seninf` | `mtk_cam_isp` | source | **tidak** |
| `frag@58/camera_af_main@0C` | `mediatek,aw8601af` | `aw8601af` | source | **tidak** |
| `frag@58/camera_eeprom0@50` | `mediatek,camera_eeprom` | `camera_eeprom_v4l2` | source | **tidak** |
| `frag@58/sensor0@10` | `mediatek,imgsensor` | `imgsensor` | source | **tidak** |
| `frag@59/camera_eeprom1@51` | `mediatek,camera_eeprom` | `camera_eeprom_v4l2` | source | **tidak** |
| `frag@59/sensor1@4A` | `mediatek,imgsensor` | `imgsensor` | source | **tidak** |
| `frag@60/sensor2@10` | `mediatek,imgsensor` | `imgsensor` | source | **tidak** |
| `frag@61/sensor3@10` | `mediatek,imgsensor` | `imgsensor` | source | **tidak** |

### Audio

| Node | compatible | Driver | Asal | juga di base |
|---|---|---|---|---|
| `frag@1/tran_audio_controller` | `tran-audio-controller` | `tran_audio_control` | source | **tidak** |
| `frag@5/fs15xx_pa@34` | `foursemi,fs15xx` | `snd_soc_fs1599` | source | **tidak** |
| `frag@5/fs15xx_pa@35` | `foursemi,fs15xx` | `snd_soc_fs1599` | source | **tidak** |

### Connectivity (WiFi/BT/GPS/NFC/FM)

| Node | compatible | Driver | Asal | juga di base |
|---|---|---|---|---|
| `frag@9/nfc_nxp@28` | `nxp,pn544` | `nfc_i2c` | source | **tidak** |

### Fingerprint / Secure / TrustZone

| Node | compatible | Driver | Asal | juga di base |
|---|---|---|---|---|
| `frag@13/fingerprint@0` | `tran_fp_legacy` | `tran_fp` | source | **tidak** |

### PMIC / Regulator / Thermal

| Node | compatible | Driver | Asal | juga di base |
|---|---|---|---|---|
| `frag@6/LDOEN6` | `regulator-fixed` | `kernel-6.12/drivers/regulator/fixed.c` | built-in | ya |
| `frag@64/gpioldo_iovdd` | `regulator-fixed` | `kernel-6.12/drivers/regulator/fixed.c` | built-in | ya |
| `frag@64/ldoid7en` | `regulator-fixed` | `kernel-6.12/drivers/regulator/fixed.c` | built-in | ya |
| `frag@64/vs2pmu` | `regulator-fixed` | `kernel-6.12/drivers/regulator/fixed.c` | built-in | ya |

### Modem / Jaringan seluler

| Node | compatible | Driver | Asal | juga di base |
|---|---|---|---|---|
| `frag@73` | `mediatek,md1_sim1_hot_plug_eint-eint` | — | tidak ada | **tidak** |

### Lain-lain

| Node | compatible | Driver | Asal | juga di base |
|---|---|---|---|---|
| `frag@31` | `tc_pe5` | — | tidak ada | **tidak** |
| `frag@50/haptic_hv@5A` | `awinic,haptic_hv` | `tran_richtap_haptic_hv` | source | **tidak** |
| `frag@53/ocp81375_v4l2@63` | `mediatek,ocp81375_v4l2` | `ocp81375_v4l2` | source | **tidak** |
| `frag@53/sgm37864_v4l2@64` | `mediatek,sgm37864_v4l2` | `sgm37864_v4l2` | source | **tidak** |
