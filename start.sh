#!/bin/bash

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

killall -9 wireshark linphone
# --- 1. Vérification des privilèges ROOT ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERREUR] Ce script doit être lancé en tant que root (sudo).${NC}" 
   exit 1
fi
DEFAULT_IP=$(hostname -I | awk '{print $1}')
read -p "Enter Local Host IP (Default: $DEFAULT_IP): " USER_IP
USER_IP=${USER_IP:-$DEFAULT_IP}

DEFAULT_ARFCN=3350
read -p "Enter ARFCN (Default: 3350): " USER_ARFCN
ARFCN=${DEFAULT_ARFCN:-$USER_ARFCN}


echo -e "\n\033[0;33m--- MNO Configuration (for srsRAN / LTE) ---\033[0m"

DEFAULT_MNO_MCC="208"
DEFAULT_MNO_MNC="01"
DEFAULT_TAC="7"

read -p "Enter MNO MCC (e.g., 208 for France) [${DEFAULT_MNO_MCC}]: " MNO_MCC
MNO_MCC="${MNO_MCC:-$DEFAULT_MNO_MCC}"

read -p "Enter MNO MNC (e.g., 01 for Orange) [${DEFAULT_MNO_MNC}]: " MNO_MNC
MNO_MNC="${MNO_MNC:-$DEFAULT_MNO_MNC}"

read -p "Enter LTE TAC (e.g., 7) [${DEFAULT_TAC}]: " USER_TAC
USER_TAC="${USER_TAC:-$DEFAULT_TAC}"

# Configuration du MVNO (Target EDGE)
echo -e "\n\033[0;33m--- MVNO Configuration (for Osmocom / EDGE) ---\033[0m"

DEFAULT_MVNO_MCC="208"
DEFAULT_MVNO_MNC="26"

read -p "Enter MVNO MCC (e.g., 208) [${DEFAULT_MVNO_MCC}]: " MVNO_MCC
MVNO_MCC="${MVNO_MCC:-$DEFAULT_MVNO_MCC}"

read -p "Enter MVNO MNC (e.g., 26 for NRJ Mobile) [${DEFAULT_MVNO_MNC}]: " MVNO_MNC
MVNO_MNC="${MVNO_MNC:-$DEFAULT_MVNO_MNC}"

echo -e "\n\033[0;32m[*] Injecting configurations via sed...\033[0m"

# 1. Remplacement de l'IP globale
find ./configs ./scripts -type f -exec sed -i "s/192.168.1.101/$USER_IP/g" {} +

# 2. Application de l'identité MVNO sur Osmocom (EDGE)
sed -i "s/mobile country code [0-9]*/mobile country code $MVNO_MCC/g" configs/osmo-bsc.cfg configs/osmo-msc.cfg 2>/dev/null || true
sed -i "s/mobile network code [0-9]*/mobile network code $MVNO_MNC/g" configs/osmo-bsc.cfg configs/osmo-msc.cfg 2>/dev/null || true

# 3. Application de l'identité MNO sur srsRAN (LTE)
sed -i "s/dl_earfcn = 3350/dl_earfcn = $ARFCN/g" configs/srsran/enb.conf 2>/dev/null || true
sed -i "s/mcc = [0-9]*/mcc = $MNO_MCC/g" configs/srsran/epc.conf configs/srsran/enb.conf 2>/dev/null || true
sed -i "s/mnc = [0-9]*/mnc = $MNO_MNC/g" configs/srsran/epc.conf configs/srsran/enb.conf 2>/dev/null || true
sed -i "s/tac = [0-9]*/tac = $USER_TAC/g" configs/srsran/epc.conf configs/srsran/rr.conf 2>/dev/null || true


# --- 3. Build & Run ---
echo -e "\033[0;32m[*] Starting Build and Container...\033[0m"


touch /tmp/pcu_bts
chmod 777 /tmp/pcu_bts
# --- 2. Nettoyage : Stop si déjà lancé ---
echo -e "${GREEN}[*] Nettoyage de l'environnement...${NC}"
[ "$(sudo docker inspect -f '{{.State.Running}}' egprs 2>/dev/null)" = "true" ] && sudo docker stop egprs

# --- 3. Préparation du noyau sur l'hôte ---
echo -e "${GREEN}[*] Configuration du module TUN sur l'hôte...${NC}"
modprobe tun
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
c    chmod 666 /dev/net/tun
fi
ip l del apn0
echo nameserver 192.168.1.254 > /etc/resolv.conf
ip tuntap add dev apn0 mode tun
ip addr add 176.16.32.0/24 dev apn0
ip link set apn0 up

# --- 4. Option Multi-Mobile (Avant de lancer le container) ---
# --- 5. Lancement du Docker ---
echo -e "${GREEN}[*] Lancement du conteneur egprs (Image: osmocom-nitb)...${NC}"
docker build -f Dockerfile.run -t redirection_poc .
# Lancement en mode détaché avec privilèges réseau totaux
docker run -d \
    --rm \
    --name redirection \
    --privileged \
    --cap-add NET_ADMIN \
    --cap-add SYS_ADMIN \
    --cgroupns host \
    --net host \
    --device /dev/net/tun:/dev/net/tun \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
    redirection_poc

echo -e "${GREEN}[*] Attente du démarrage des services systemd (SS7/SIGTRAN)...${NC}"
sleep 3

export XDG_RUNTIME_DIR="/tmp/runtime-root"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
TARGET_UID="$(id -u "$TARGET_USER")"

# Reprendre une session graphique si besoin
DISPLAY="${DISPLAY:-:0}"
XAUTHORITY="${XAUTHORITY:-/home/$TARGET_USER/.Xauthority}"

sudo -u "$TARGET_USER" \
  env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
  nohup linphone >/dev/null 2>&1 &

wireshark -k -i any -f "udp port 4729" >/dev/null 2>&1 &
# --- 6. Exécution de l'orchestration interne (Tmux) ---
# On passe la variable DUAL_MOBILE au script interne
docker exec -it redirection /bin/bash -c "/root/run.sh"
docker stop redirection
