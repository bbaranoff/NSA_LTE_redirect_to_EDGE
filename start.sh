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

touch /tmp/pcu_bts
chmod 777 /tmp/pcu_bts

# --- 2. Nettoyage ---
echo -e "${GREEN}[*] Nettoyage de l'environnement...${NC}"
[ "$(sudo docker inspect -f '{{.State.Running}}' egprs 2>/dev/null)" = "true" ] && sudo docker stop egprs

# --- 3. Préparation du noyau ---
modprobe tun
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
    chmod 666 /dev/net/tun
fi
ip l del apn0 2>/dev/null
echo nameserver 192.168.1.254 > /etc/resolv.conf
ip tuntap add dev apn0 mode tun
ip addr add 176.16.32.0/24 dev apn0
ip link set apn0 up

# --- 4. Configuration dynamique MCC/MNC/TAC ---
echo -e "${GREEN}[?] Configuration du réseau GSM/LTE :${NC}"
read -p "Entrez le MCC (ex: 208): " USER_MCC
read -p "Entrez le MNC (ex: 10): " USER_MNC
read -p "Entrez le TAC (ex: 7): " USER_TAC

echo -e "${GREEN}[*] Application des configurations (sed)...${NC}"

# Application sur les fichiers de configuration Osmocom 
# Note : On modifie les fichiers locaux AVANT le build/copy dans Docker
sed -i "s/mcc [0-9]*/mcc $USER_MCC/g" configs/osmo-bsc.cfg
sed -i "s/mnc [0-9]*/mnc $USER_MNC/g" configs/osmo-bsc.cfg
sed -i "s/mcc [0-9]*/mcc $USER_MCC/g" configs/osmo-msc.cfg
sed -i "s/mnc [0-9]*/mnc $USER_MNC/g" configs/osmo-msc.cfg

# Application sur les fichiers srsRAN (enb.conf, epc.conf, rr.conf)
# On suppose que ces fichiers sont dans votre répertoire de build actuel
if [ -d "configs/srsran" ]; then
    sed -i "s/mcc = [0-9]*/mcc = $USER_MCC/g" configs/srsran/enb.conf
    sed -i "s/mnc = [0-9]*/mnc = $USER_MNC/g" configs/srsran/enb.conf
    sed -i "s/mcc = [0-9]*/mcc = $USER_MCC/g" configs/srsran/epc.conf
    sed -i "s/mnc = [0-9]*/mnc = $USER_MNC/g" configs/srsran/epc.conf
    sed -i "s/tac = [0-9]*/tac = $USER_TAC/g" configs/srsran/epc.conf
    # Pour rr.conf (souvent format hex ou dec selon la version)
    sed -i "s/tac = [0-9]*/tac = $USER_TAC/g" configs/srsran/rr.conf
fi

# --- 5. Lancement du Docker ---
echo -e "${GREEN}[*] Lancement du conteneur egprs...${NC}"
docker build -f Dockerfile -t redirection_poc . [cite: 1]

# Lancement avec les paramètres système nécessaires pour systemd et Osmocom [cite: 17, 18]
docker run -d \
    --rm \
    --name redirect \
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
docker exec -it redirect /bin/bash -c "/root/run.sh"
