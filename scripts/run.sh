#!/bin/bash
set -euo pipefail

SESSION="osmocom"
GREEN='\033[0;32m'
NC='\033[0m'

# ---- Config injection (from host via docker -e) ----
: "${USER_IP:=192.168.1.101}"
: "${ARFCN:=3350}"
: "${MNO_MCC:=208}"
: "${MNO_MNC:=01}"
: "${USER_TAC:=7}"
: "${MVNO_MCC:=208}"
: "${MVNO_MNC:=26}"

echo -e "${GREEN}=== Injection configs (Osmocom + srsRAN) ===${NC}"

# 1) IP replacement everywhere in container configs
# Use '|' delimiter to avoid escaping dots in IPs.
find /etc/osmocom /root/.config/srsran -type f -print0 2>/dev/null | \
  xargs -0 -r sed -i "s|192.168.1.101|${USER_IP}|g" || true

# 2) MVNO identity (EDGE) in Osmocom configs
sed -i -E "s/(mobile country code) [0-9]+/\\1 ${MVNO_MCC}/g" /etc/osmocom/osmo-bsc.cfg /etc/osmocom/osmo-msc.cfg 2>/dev/null || true
sed -i -E "s/(mobile network code) [0-9]+/\\1 ${MVNO_MNC}/g" /etc/osmocom/osmo-bsc.cfg /etc/osmocom/osmo-msc.cfg 2>/dev/null || true

# 3) MNO identity + LTE params in srsRAN configs
sed -i -E "s/(mcc\\s*=\\s*)[0-9]+/\\1${MNO_MCC}/g" /root/.config/srsran/epc.conf /root/.config/srsran/enb.conf 2>/dev/null || true
sed -i -E "s/(mnc\\s*=\\s*)[0-9]+/\\1${MNO_MNC}/g" /root/.config/srsran/epc.conf /root/.config/srsran/enb.conf 2>/dev/null || true
sed -i -E "s/(tac\\s*=\\s*)[0-9]+/\\1${USER_TAC}/g" /root/.config/srsran/epc.conf /root/.config/srsran/rr.conf 2>/dev/null || true
sed -i -E "s/(dl_earfcn\\s*=\\s*)[0-9]+/\\1${ARFCN}/g" /root/.config/srsran/enb.conf 2>/dev/null || true


echo -e "${GREEN}=== Démarrage Core Osmocom ===${NC}"
/etc/osmocom/osmo-start.sh
sleep 3

echo -e "${GREEN}=== Démarrage Asterisk ===${NC}"
# tente systemd, sinon fallback CLI
if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
  systemctl restart asterisk || true
else
  # kill un ancien asterisk si présent, puis lance en arrière-plan
  pkill -x asterisk 2>/dev/null || true
  asterisk -f -U root -G root -vvv >/var/log/asterisk/console.log 2>&1 &
fi
sleep 2

echo -e "${GREEN}=== Reset tmux ===${NC}"
tmux kill-server 2>/dev/null || true
tmux start-server
sleep 1

#################################
# Fenêtre 0 : FakeTRX
#################################
tmux new-session -d -s "$SESSION" -n "CORE LTE/NSA"
tmux send-keys -t "$SESSION:0" "srsepc" C-m
sleep 2

#################################
# Fenêtre 1 : MS1 (trxcon + mobile)
#################################
tmux new-window -t "$SESSION:1" -n "TRX LTE/NSA"
tmux send-keys -t "$SESSION:1" "srsenb" C-m
sleep 2

#################################
# Fenêtre 2 : Asterisk CLI
#################################
tmux new-window -t "$SESSION:2" -n asterisk
tmux send-keys -t "$SESSION:2" "asterisk -rvvv" C-m

#################################
# Fenêtre 2 : Asterisk CLI
#################################
tmux new-window -t "$SESSION:3" -n "CORE EDGE"
tmux send-keys -t "$SESSION:3" "/etc/osmocom/status.sh" C-m

#################################
# Fenêtre 2 : Asterisk CLI
#################################
tmux new-window -t "$SESSION:4" -n "TRX EDGE"
tmux send-keys -t "$SESSION:4" "osmo-trx-uhd" C-m

#################################
# Final
#################################
tmux select-window -t "$SESSION:1"
echo -e "${GREEN}=== Orchestration prête ===${NC}"
tmux attach-session -t "$SESSION"
