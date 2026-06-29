#!/bin/bash
set -uo pipefail
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BASE_DIR="/home/medu-vps"
ENV_FILE=".vps_env"
IMG_PATH="${BASE_DIR}/ubuntu22.qcow2"
SEED_IMG="seed.img"
USER_DATA="user-data"
if [ "$(id -u)" -eq 0 ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi
type_effect() {
    local text="$1" delay="${2:-0.02}"
    for (( i=0; i<${#text}; i++ )); do
        echo -n "${text:$i:1}"
        sleep "$delay"
    done
    echo ""
}
loading_bar() {
    local title="$1"
    echo -ne "${YELLOW}⏳ ${title}${NC} ["
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        echo -ne "="
        sleep 0.05
    done
    echo -e "] ${GREEN}done${NC}"
}
pause_menu() {
    sleep "${1:-2}"
    show_menu
}
require_cmd() {
    command -v "$1" >/dev/null 2>&1
}
show_menu() {
    clear
    echo -e "${RED}==========================================================${NC}"
    echo -e "${WHITE}              MEDU · VPS CONTROL DASHBOARD               ${NC}"
    echo -e "${RED}==========================================================${NC}"
    echo -e "${CYAN}  __  __ ____ ___  _   _ ${NC}"
    echo -e "${CYAN} |  \/  | ___|  _ \| | | |${NC}   ${WHITE}built & maintained by medu${NC}"
    echo -e "${CYAN} | |\/| |  _| | | | | | |${NC}"
    echo -e "${CYAN} | |  | | |___| |_| | |_| |${NC}"
    echo -e "${CYAN} |_|  |_|_____|____/ \___/ ${NC}"
    echo -e "${RED}==========================================================${NC}"
    echo ""
    echo -e "${YELLOW}Select an option:${NC}"
    echo -e "  ${CYAN}[1]${NC} Create & boot a new Ubuntu VPS instance"
    echo -e "  ${CYAN}[2]${NC} Restart existing VPS instance"
    echo -e "  ${CYAN}[3]${NC} Configure TCP port forward rules"
    echo -e "  ${CYAN}[4]${NC} Clean up VPS files / cache"
    echo -e "  ${CYAN}[5]${NC} Exit"
    echo ""
    echo -e "${RED}==========================================================${NC}"
    echo -ne "${WHITE}Choice [1-5]: ${NC}"
    read -r CHOICE
    case "$CHOICE" in
        1) create_vps ;;
        2) restart_vps ;;
        3) configure_tcp ;;
        4) clean_vps ;;
        5) echo -e "${GREEN}Goodbye — medu VPS dashboard.${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice. Pick 1-5.${NC}"; pause_menu 1 ;;
    esac
}
create_vps() {
    clear
    echo -e "${RED}==========================================================${NC}"
    echo -e "${WHITE}  CONFIGURE NEW VM — medu VPS dashboard${NC}"
    echo -e "${RED}==========================================================${NC}"
    echo ""
    read -rp "$(echo -e "${BLUE}RAM in GB [default 4]: ${NC}")" RAM_GB
    RAM_GB=${RAM_GB:-4}
    read -rp "$(echo -e "${BLUE}CPU cores [default 2]: ${NC}")" CPU_CORES
    CPU_CORES=${CPU_CORES:-2}
    read -rp "$(echo -e "${BLUE}Disk space to add, in GB [default 10]: ${NC}")" DISK_ADD
    DISK_ADD=${DISK_ADD:-10}
    read -rp "$(echo -e "${BLUE}Username [default ubuntu]: ${NC}")" USER_NAME
    USER_NAME=${USER_NAME:-ubuntu}
    while true; do
        read -rsp "$(echo -e "${BLUE}Set a password for ${USER_NAME}: ${NC}")" USER_PASS
        echo ""
        read -rsp "$(echo -e "${BLUE}Confirm password: ${NC}")" USER_PASS_CONFIRM
        echo ""
        if [ -z "$USER_PASS" ]; then
            echo -e "${RED}Password cannot be empty.${NC}"
        elif [ "$USER_PASS" != "$USER_PASS_CONFIRM" ]; then
            echo -e "${RED}Passwords do not match. Try again.${NC}"
        else
            break
        fi
    done
    TCP_HOST_PORT=${TCP_HOST_PORT:-2222}
    TCP_GUEST_PORT=22
    echo ""
    echo -e "${YELLOW}Installing core dependencies...${NC}"
    $SUDO_CMD apt-get update -y >/dev/null 2>&1
    $SUDO_CMD apt-get install -y qemu-system-x86 qemu-utils wget cloud-image-utils curl >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Dependency install failed. Check apt/network and re-run.${NC}"
        pause_menu 3
        return
    fi
    $SUDO_CMD mkdir -p "$BASE_DIR"
    if [ ! -f "$IMG_PATH" ]; then
        echo -e "${YELLOW}Downloading Ubuntu 22.04 cloud image to ${BASE_DIR}...${NC}"
        $SUDO_CMD wget -q --show-progress \
            https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
            -O "$IMG_PATH"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Image download failed.${NC}"
            pause_menu 3
            return
        fi
        $SUDO_CMD chown "$(id -u)":"$(id -g)" "$IMG_PATH" 2>/dev/null
        $SUDO_CMD chmod 600 "$IMG_PATH"
    else
        echo -e "${GREEN}Existing cached image found at ${IMG_PATH}.${NC}"
    fi
    loading_bar "Generating cloud-init config"
    cat <<EOF > "$USER_DATA"
ssh_pwauth: True
chpasswd:
  list: |
    ${USER_NAME}:${USER_PASS}
  expire: False
EOF
    unset USER_PASS USER_PASS_CONFIRM
    cloud-localds "$SEED_IMG" "$USER_DATA" >/dev/null 2>&1
    loading_bar "Resizing virtual disk (+${DISK_ADD}G)"
    $SUDO_CMD qemu-img resize "$IMG_PATH" "+${DISK_ADD}G" >/dev/null 2>&1
    save_env
    boot_qemu
}
configure_tcp() {
    clear
    echo -e "${YELLOW}==========================================================${NC}"
    echo -e "${WHITE}  TCP PORT FORWARDING — medu VPS dashboard${NC}"
    echo -e "${YELLOW}==========================================================${NC}"
    echo ""
    [ -f "$ENV_FILE" ] && source "$ENV_FILE"
    echo -e "Current host port  : ${CYAN}${TCP_HOST_PORT:-2222}${NC}"
    echo -e "Current guest port : ${CYAN}${TCP_GUEST_PORT:-22}${NC}"
    echo ""
    read -rp "$(echo -e "${BLUE}New external host port [default 2222]: ${NC}")" NEW_HOST_PORT
    TCP_HOST_PORT=${NEW_HOST_PORT:-2222}
    read -rp "$(echo -e "${BLUE}New internal guest port [default 22]: ${NC}")" NEW_GUEST_PORT
    TCP_GUEST_PORT=${NEW_GUEST_PORT:-22}
    save_env
    echo ""
    echo -e "${GREEN}Port rule updated.${NC}"
    pause_menu 2
}
save_env() {
    {
        echo "RAM_GB=${RAM_GB:-4}"
        echo "CPU_CORES=${CPU_CORES:-2}"
        echo "USER_NAME=${USER_NAME:-ubuntu}"
        echo "TCP_HOST_PORT=${TCP_HOST_PORT:-2222}"
        echo "TCP_GUEST_PORT=${TCP_GUEST_PORT:-22}"
    } > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}
boot_qemu() {
    [ -f "$ENV_FILE" ] && source "$ENV_FILE"
    TCP_HOST_PORT=${TCP_HOST_PORT:-2222}
    TCP_GUEST_PORT=${TCP_GUEST_PORT:-22}
    RAM_VALUE="${RAM_GB:-4}G"
    clear
    echo -e "${GREEN}==========================================================${NC}"
    type_effect "medu VPS — synchronizing tunnels and launching VM..." 0.015
    echo -e "${GREEN}==========================================================${NC}"
    echo ""
    SSHX_URL=""
    if require_cmd curl; then
        sshx_log=$(mktemp)
        curl -sSf https://sshx.io/get | sh -s run > "$sshx_log" 2>&1 &
        sleep 5
        SSHX_URL=$(grep -oE 'https://sshx\.io/s/[a-zA-Z0-9]*' "$sshx_log" | head -n1)
        rm -f "$sshx_log"
    fi
    clear
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${WHITE}   VM NETWORK ACTIVE — medu VPS dashboard${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${WHITE}Username   : ${CYAN}${USER_NAME:-ubuntu}${NC}"
    echo -e "${WHITE}Resources  : ${CYAN}${RAM_VALUE} RAM | ${CPU_CORES:-2} cores${NC}"
    echo -e "${WHITE}Port rule  : ${YELLOW}host ${TCP_HOST_PORT} -> guest ${TCP_GUEST_PORT}${NC}"
    echo -e "${RED}----------------------------------------------------------${NC}"
    if [ -n "$SSHX_URL" ]; then
        echo -e "${YELLOW}Live shareable terminal link:${NC}"
        echo -e "${GREEN}${SSHX_URL}${NC}"
    else
        echo -e "${RED}sshx tunnel unavailable — use the local port instead.${NC}"
    fi
    echo -e "${RED}----------------------------------------------------------${NC}"
    echo -e "${WHITE}Connect with: ssh ${USER_NAME:-ubuntu}@localhost -p ${TCP_HOST_PORT}${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${WHITE}              powered by medu's VPS dashboard${NC}"
    echo ""
    qemu-system-x86_64 \
        -hda "$IMG_PATH" \
        -m "$RAM_VALUE" \
        -smp "${CPU_CORES:-2}" \
        -drive file="$SEED_IMG",format=raw \
        -nographic \
        -netdev user,id=net0,hostfwd=tcp::${TCP_HOST_PORT}-:${TCP_GUEST_PORT} \
        -device e1000,netdev=net0
}
restart_vps() {
    if [ -f "$IMG_PATH" ] && [ -f "$SEED_IMG" ]; then
        echo -e "${GREEN}Restarting existing VM...${NC}"
        sleep 1
        boot_qemu
    else
        echo -e "${RED}No existing VPS config found. Use option 1 first.${NC}"
        pause_menu 3
    fi
}
clean_vps() {
    echo -e "${RED}Removing VPS files and configuration...${NC}"
    $SUDO_CMD rm -f "$USER_DATA" "$SEED_IMG" "$ENV_FILE"
    $SUDO_CMD rm -f "$IMG_PATH"
    pkill -f sshx >/dev/null 2>&1
    echo -e "${GREEN}Workspace wiped.${NC}"
    pause_menu 2
}
show_menu
