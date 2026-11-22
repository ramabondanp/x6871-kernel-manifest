#!/bin/bash
# Recreate branch mtk-base dan mtk-base-latest dari repo Motorola.
#
# Hasil:
#   mtk-base        = 30a0466a2be7 (tree MTK murni, 0 file Moto)
#   mtk-base-latest = mtk-base + 12 patch MTK (header GKI + platform)
#
# Pemakaian:
#   ./scripts/reproduce-cleanup.sh [dir-tujuan]
#
# Butuh: git, python3, ~3 GB disk.
set -e

DEST=${1:-kernel-kernel_device_modules-6.12}
BASE=30a0466a2be7
URL=https://github.com/MotorolaMobilityLLC/kernel-kernel_device_modules-6.12

if [ ! -d "$DEST/.git" ]; then
  echo "== clone $URL"
  git clone "$URL" "$DEST"
fi
cd "$DEST"

# Cherry-pick butuh identitas git. Di server bersih ini sering belum di-set,
# dan git melaporkannya sebagai "Commiter identity unknown" (mirip konflik).
if ! git config user.email >/dev/null; then
  git config user.email "w1vo-cleanup@localhost"
  git config user.name  "w1vo cleanup"
  echo "== set git identity lokal: w1vo cleanup <w1vo-cleanup@localhost>"
fi

echo "== mtk-base"
git branch -f mtk-base "$BASE"

echo "== mtk-base-latest"
git checkout -B mtk-base-latest "$BASE"

KEPT="
fb615de2bb88
91ce1f5c9dfd
9051d6953575
79250785b80c
64ae591edd11
3022b2737530
25d069c09d80
eafd39c4b64c
17ef8004643f
803db3b99f8a
c188c78edaba
4000205a644b
"

CONFLICT_LOG=.git/w1vo-cherry-pick.err
trap 'rm -f "$CONFLICT_LOG"' EXIT
for c in $KEPT; do
  echo "== cherry-pick $c $(git log -1 --format='%s' $c)"
  if git cherry-pick -x "$c" >"$CONFLICT_LOG" 2>&1; then
    continue
  fi

  # Satu-satunya konflik: tcpc 2.0.32_MTK.
  # Ambil versi MTK lalu buang sisa kode Moto (MMI + pd_vdm_verify_state).
  if [ "$c" = "3022b2737530" ]; then
    echo "   resolve tcpc conflict"
    git checkout 3022b2737530 -- \
      drivers/misc/mediatek/typec/tcpc/inc/pd_core.h \
      drivers/misc/mediatek/typec/tcpc/inc/pd_dpm_core.h
    python3 - <<'PY'
p='drivers/misc/mediatek/typec/tcpc/inc/pd_core.h'
s=open(p).read()
s=s.replace("#define USB_VID_MMI_ADAPTER  \t0x22b8\n","")
s=s.replace("\tuint8_t pd_vdm_verify_state;\n\n","")
s=s.replace("""
#ifdef CONFIG_SUPPORT_MMI_ADAPTER
\tuint8_t mmi_adapter_state;
#endif /* CONFIG_SUPPORT_MMI_ADAPTER */
""","")
s=s.replace("int pd_update_vdm_verify_state(struct pd_port *pd_port, uint8_t state);\n","")
open(p,'w').write(s)

p='drivers/misc/mediatek/typec/tcpc/inc/pd_dpm_core.h'
s=open(p).read()
s=s.replace("""#ifdef CONFIG_SUPPORT_MMI_ADAPTER
extern bool mmi_dfp_u_notify_discover_svid(
\tstruct pd_port *pd_port, struct svdm_svid_data *svid_data, bool ack);
extern bool mmi_dfp_notify_uvdm(struct pd_port *pd_port,
\t\tstruct svdm_svid_data *svid_data, bool ack);
extern bool mmi_notify_pe_ready(struct pd_port *pd_port,
\t\tstruct svdm_svid_data *svid_data);
extern bool mmi_dfp_notify_pe_startup(
\tstruct pd_port *pd_port, struct svdm_svid_data *svid_data);
#endif /* CONFIG_SUPPORT_MMI_ADAPTER */

""","")
open(p,'w').write(s)
PY
    git add drivers/misc/mediatek/typec/tcpc/inc/pd_core.h \
            drivers/misc/mediatek/typec/tcpc/inc/pd_dpm_core.h
    git -c core.editor=true cherry-pick --continue >/dev/null
  else
    echo "   ERROR: konflik tak terduga pada $c"
    echo "   --- output git ---"
    sed 's/^/   /' "$CONFLICT_LOG"
    git cherry-pick --abort 2>/dev/null || true
    exit 1
  fi
done

echo
echo "== hasil"
echo "commit di atas base: $(git rev-list --count $BASE..HEAD)"
echo "file bogota/taipei/moto: $(git ls-files | grep -icE 'bogota|taipei|moto' || true)"
echo "ack_headers module/nvhe: $(grep -c 'module/nvhe' kernel/kleaf/ack_headers.bzl)"
git log --oneline $BASE..HEAD | cat
