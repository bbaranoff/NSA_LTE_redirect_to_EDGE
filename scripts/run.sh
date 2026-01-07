#!/bin/bash
set -euo pipefail

SESSION="osmocom"
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}=== Démarrage Core Osmocom ===${NC}"
/etc/osmocom/osmo-start.sh
sleep 3

echo -e "${GREEN}=== Démarrage Asterisk ===${NC}"
if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
  systemctl restart asterisk || true
else
  pkill -x asterisk 2>/dev/null || true
  asterisk -f -U root -G root -vvv >/var/log/asterisk/console.log 2>&1 &
fi
sleep 2

echo -e "${GREEN}=== Reset tmux ===${NC}"
tmux kill-server 2>/dev/null || true
tmux new-session -d -s "$SESSION" -n "osmo-logs" # Création de la session initiale
sleep 1

#################################
# Fenêtre 1 : srsEPC
#################################
# On utilise la fenêtre 1 (déjà créée par new-session) pour l'EPC
tmux rename-window -t "$SESSION:1" "srsEPC"
tmux send-keys -t "$SESSION:1" "srsepc /root/.srsran/epc.conf" C-m

#################################
# Fenêtre 2 : srsENB
#################################
tmux new-window -t "$SESSION:2" -n "srsENB"
tmux send-keys -t "$SESSION:2" "srsenb /root/.srsran/enb.conf" C-m

#################################
# Fenêtre 3 : Asterisk CLI
#################################
tmux new-window -t "$SESSION:3" -n "asterisk"
tmux send-keys -t "$SESSION:3" "asterisk -rvvv" C-m

#################################
# Final
#################################
# On se place par défaut sur la fenêtre de l'eNodeB pour surveiller les connexions mobiles
tmux select-window -t "$SESSION:2"
echo -e "${GREEN}=== Orchestration prête (EPC, ENB, Asterisk) ===${NC}"
tmux attach-session -t "$SESSION"
