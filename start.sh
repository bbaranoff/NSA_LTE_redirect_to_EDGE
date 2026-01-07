#!/bin/bash

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

killall -9 wireshark linphone 2>/dev/null
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
ip l del apn0 2>/dev/null || true
echo nameserver 192.168.1.254 > /etc/resolv.conf
ip tuntap add dev apn0 mode tun
ip addr add 176.16.32.0/24 dev apn0
ip link set apn0 up

# --- 4. Configuration dynamique IP / MCC / MNC / TAC ---
echo -e "${GREEN}[?] Configuration du réseau :${NC}"

# Détection de l'IP locale pour aider l'utilisateur
DEFAULT_IP=$(hostname -I | awk '{print $1}')
read -p "Entrez l'IP locale de l'hôte (Défaut: $DEFAULT_IP): " USER_IP
USER_IP=${USER_IP:-$DEFAULT_IP}

read -p "Entrez le MCC (ex: 208): " USER_MCC
read -p "Entrez le MNC (ex: 10): " USER_MNC
read -p "Entrez le TAC (ex: 7): " USER_TAC

echo -e "${GREEN}[*] Application des configurations (sed)...${NC}"

# Remplacement de l'IP 192.168.1.69 par l'IP utilisateur dans tous les fichiers de config
# On cible les dossiers configs/ et les fichiers de scripts
find ./configs ./scripts -type f -exec sed -i "s/192.168.1.69/$USER_IP/g" {} +

# Application spécifique MCC/MNC sur Osmocom
if [ -d "configs" ]; then
    sed -i "s/mcc [0-9]*/mcc $USER_MCC/g" configs/osmo-bsc.cfg
    sed -i "s/mnc [0-9]*/mnc $USER_MNC/g" configs/osmo-bsc.cfg
    sed -i "s/mcc [0-9]*/mcc $USER_MCC/g" configs/osmo-msc.cfg
    sed -i "s/mnc [0-9]*/mnc $USER_MNC/g" configs/osmo-msc.cfg
fi

# Application spécifique srsRAN (IP, MCC, MNC, TAC)
if [ -d "configs/srsran" ]; then
    # Mise à jour des adresses de bind et des adresses MME/EPC
    sed -i "s/mcc = [0-9]*/mcc = $USER_MCC/g" configs/srsran/*.conf
    sed -i "s/mnc = [0-9]*/mnc = $USER_MNC/g" configs/srsran/*.conf
    sed -i "s/tac = [0-9]*/tac = $USER_TAC/g" configs/srsran/epc.conf
    sed -i "s/tac = [0-9]*/tac = $USER_TAC/g" configs/srsran/rr.conf
fi

# --- 5. Lancement du Docker ---
echo -e "${GREEN}[*] Lancement du conteneur egprs...${NC}"
# On utilise le Dockerfile corrigé (sans le double RUN)
docker build -f Dockerfile -t redirection_poc .

docker run -d \
    --rm \
    --name egprs \
    --privileged \
    --cap-add NET_ADMIN \
    --cap-add SYS_ADMIN \
    --cgroupns host \
    --net host \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
    redirection_poc

# Attente et exécution de l'orchestration tmux
sleep 3
docker exec -it egprs /bin/bash -c "/root/run.sh"
