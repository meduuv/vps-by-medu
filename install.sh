#!/bin/bash
# ==========================================================
#   MEDU VPS DASHBOARD
#   QEMU-based disposable Ubuntu/Debian VPS provisioner
#   Choice of Ubuntu 22.04 or Debian 12, Intel/AMD CPU selection, KVM acceleration, virtio networking
#   Max: 32GB RAM | 8 cores | 128GB disk
#   Author: medu
# ==========================================================
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
ENV_FILE="${BASE_DIR}/.vps_env"
SEED_IMG="${BASE_DIR}/seed.img"
USER_DATA="${BASE_DIR}/user-data"
PID_FILE="${BASE_DIR}/.vps.pid"
RESIZED_FLAG="${BASE_DIR}/.disk_resized"

UBUNTU_IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
UBUNTU_SHA_URL="https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS"
UBUNTU_SHA_FILE="jammy-server-cloudimg-amd64.img"

DEBIAN_IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
DEBIAN_SHA_URL="https://cloud.debian.org/images/cloud/bookworm/latest/SHA512SUMS"
DEBIAN_SHA_FILE="debian-12-generic-amd64.qcow2"

if [ "$(id -u)" -eq 0 ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

# ----------------------------------------------------------
# helpers
# ----------------------------------------------------------
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
    echo -ne "${YELLOW}Loading: ${title}${NC} ["
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

vm_is_running() {
    [ -f "$PID_FILE" ] || return 1
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# ----------------------------------------------------------
# menu
# ----------------------------------------------------------
show_menu() {
    clear
    echo -e "${RED}==========================================================${NC}"
    echo -e "${WHITE}              MEDU . VPS CONTROL DASHBOARD               ${NC}"
    echo -e "${RED}==========================================================${NC}"
    echo -e "${CYAN}  __  __ ____ ___  _   _ ${NC}"
    echo -e "${CYAN} |  \/  | ___|  _ \| | | |${NC}   ${WHITE}built & maintained by medu${NC}"
    echo -e "${CYAN} | |\/| |  _| | | | | | |${NC}"
    echo -e "${CYAN} | |  | | |___| |_| | |_| |${NC}"
    echo -e "${CYAN} |_|  |_|_____|____/ \___/ ${NC}"
    echo -e "${RED}==========================================================${NC}"
    echo ""
    if vm_is_running; then
        echo -e "${GREEN}VM status: running (pid $(cat "$PID_FILE"))${NC}"
    else
        echo -e "${YELLOW}VM status: stopped${NC}"
    fi
    echo ""
    echo -e "${YELLOW}Select an option:${NC}"
    echo -e "  ${CYAN}[1]${NC} Create & boot a new Ubuntu VPS instance"
    echo -e "  ${CYAN}[2]${NC} Restart existing VPS instance"
    echo -e "  ${CYAN}[3]${NC} Configure TCP port forward rules"
    echo -e "  ${CYAN}[4]${NC} Clean up VPS files / cache"
    echo -e "  ${CYAN}[5]${NC} Show current config / status"
    echo -e "  ${CYAN}[6]${NC} Exit"
    echo ""
    echo -e "${RED}==========================================================${NC}"
    echo -ne "${WHITE}Choice [1-6]: ${NC}"
    read -r CHOICE

    case "$CHOICE" in
        1) create_vps ;;
        2) restart_vps ;;
        3) configure_tcp ;;
        4) clean_vps ;;
        5) show_status ;;
        6) echo -e "${GREEN}Goodbye - medu VPS dashboard.${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice. Pick 1-6.${NC}"; pause_menu 1 ;;
    esac
}

# ----------------------------------------------------------
# status
# ----------------------------------------------------------
show_status() {
    clear
    echo -e "${CYAN}==========================================================${NC}"
    echo -e "${WHITE}  CURRENT CONFIG - medu VPS dashboard${NC}"
    echo -e "${CYAN}==========================================================${NC}"
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
        echo -e "${WHITE}OS           : ${CYAN}${OS_NAME:-ubuntu}${NC}"
        echo -e "${WHITE}Username     : ${CYAN}${USER_NAME:-ubuntu}${NC}"
        echo -e "${WHITE}RAM          : ${CYAN}${RAM_GB:-4} GB${NC}"
        echo -e "${WHITE}CPU cores    : ${CYAN}${CPU_CORES:-2}${NC}"
        echo -e "${WHITE}CPU type     : ${CYAN}${CPU_TYPE:-host}${NC}"
        echo -e "${WHITE}Port rule    : ${CYAN}host ${TCP_HOST_PORT:-2222} -> guest ${TCP_GUEST_PORT:-22}${NC}"
        echo -e "${WHITE}SSH key auth : ${CYAN}${SSH_KEY_USED:-no}${NC}"
    else
        echo -e "${YELLOW}No saved config found. Use option 1 to create a VPS.${NC}"
    fi
    echo -e "${CYAN}----------------------------------------------------------${NC}"
    if vm_is_running; then
        echo -e "${GREEN}VM is currently running (pid $(cat "$PID_FILE")).${NC}"
    else
        echo -e "${YELLOW}VM is not running.${NC}"
    fi
    if [ -f "$IMG_PATH" ]; then
        local img_size
        img_size=$(du -h "$IMG_PATH" 2>/dev/null | cut -f1)
        echo -e "${WHITE}Disk image   : ${CYAN}${IMG_PATH} (${img_size:-unknown})${NC}"
    else
        echo -e "${YELLOW}No disk image present yet.${NC}"
    fi
    echo -e "${CYAN}==========================================================${NC}"
    pause_menu 3
}

# ----------------------------------------------------------
# create
# ----------------------------------------------------------
create_vps() {
    clear
    echo -e "${RED}==========================================================${NC}"
    echo -e "${WHITE}  CONFIGURE NEW VM - medu VPS dashboard${NC}"
    echo -e "${RED}==========================================================${NC}"
    echo ""

    if vm_is_running; then
        echo -e "${RED}A VM is already running (pid $(cat "$PID_FILE")).${NC}"
        echo -e "${YELLOW}Stop it before creating a new one, or use option 2 to restart it.${NC}"
        pause_menu 3
        return
    fi

    echo -e "${BLUE}Operating system:${NC}"
    echo -e "  ${CYAN}[1]${NC} Ubuntu 22.04 LTS (jammy)"
    echo -e "  ${CYAN}[2]${NC} Debian 12 (bookworm)"
    read -rp "$(echo -e "${BLUE}Choice [1-2, default 1]: ${NC}")" OS_CHOICE
    case "$OS_CHOICE" in
        2)
            OS_NAME="debian"
            IMG_URL="$DEBIAN_IMG_URL"
            SHA_URL="$DEBIAN_SHA_URL"
            SHA_FILE_MATCH="$DEBIAN_SHA_FILE"
            SHA_ALGO="sha512sum"
            DEFAULT_USER="debian"
            ;;
        1|"")
            OS_NAME="ubuntu"
            IMG_URL="$UBUNTU_IMG_URL"
            SHA_URL="$UBUNTU_SHA_URL"
            SHA_FILE_MATCH="$UBUNTU_SHA_FILE"
            SHA_ALGO="sha256sum"
            DEFAULT_USER="ubuntu"
            ;;
        *)
            OS_NAME="ubuntu"
            IMG_URL="$UBUNTU_IMG_URL"
            SHA_URL="$UBUNTU_SHA_URL"
            SHA_FILE_MATCH="$UBUNTU_SHA_FILE"
            SHA_ALGO="sha256sum"
            DEFAULT_USER="ubuntu"
            ;;
    esac
    IMG_PATH="${BASE_DIR}/${OS_NAME}.qcow2"
    RESIZED_FLAG="${BASE_DIR}/.disk_resized_${OS_NAME}"

    while true; do
        read -rp "$(echo -e "${BLUE}RAM in GB [default 4, max 32]: ${NC}")" RAM_GB
        RAM_GB=${RAM_GB:-4}
        if ! [[ "$RAM_GB" =~ ^[0-9]+$ ]] || [ "$RAM_GB" -lt 1 ] || [ "$RAM_GB" -gt 32 ]; then
            echo -e "${RED}RAM must be a number between 1 and 32.${NC}"
        else
            break
        fi
    done

    while true; do
        read -rp "$(echo -e "${BLUE}CPU cores [default 2, max 8]: ${NC}")" CPU_CORES
        CPU_CORES=${CPU_CORES:-2}
        if ! [[ "$CPU_CORES" =~ ^[0-9]+$ ]] || [ "$CPU_CORES" -lt 1 ] || [ "$CPU_CORES" -gt 8 ]; then
            echo -e "${RED}Cores must be a number between 1 and 8.${NC}"
        else
            break
        fi
    done

    while true; do
        read -rp "$(echo -e "${BLUE}Disk space to add, in GB [default 10, max 128]: ${NC}")" DISK_ADD
        DISK_ADD=${DISK_ADD:-10}
        if ! [[ "$DISK_ADD" =~ ^[0-9]+$ ]] || [ "$DISK_ADD" -lt 1 ] || [ "$DISK_ADD" -gt 128 ]; then
            echo -e "${RED}Disk must be a number between 1 and 128.${NC}"
        else
            break
        fi
    done

    DETECTED_VENDOR=$(grep -m1 -oE 'GenuineIntel|AuthenticAMD' /proc/cpuinfo 2>/dev/null)
    echo -e "${WHITE}Detected host CPU vendor: ${CYAN}${DETECTED_VENDOR:-unknown}${NC}"
    echo -e "${BLUE}CPU emulation type:${NC}"
    echo -e "  ${CYAN}[1]${NC} Intel (Nehalem feature set)"
    echo -e "  ${CYAN}[2]${NC} AMD (EPYC feature set)"
    echo -e "  ${CYAN}[3]${NC} host passthrough (best perf, needs KVM)"
    read -rp "$(echo -e "${BLUE}Choice [1-3, default 3]: ${NC}")" CPU_CHOICE
    case "$CPU_CHOICE" in
        1) CPU_TYPE="Nehalem" ;;
        2) CPU_TYPE="EPYC" ;;
        3|"") CPU_TYPE="host" ;;
        *) CPU_TYPE="host" ;;
    esac

    read -rp "$(echo -e "${BLUE}Username [default ${DEFAULT_USER}]: ${NC}")" USER_NAME
    USER_NAME=${USER_NAME:-$DEFAULT_USER}

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

    SSH_KEY_USED="no"
    SSH_PUBKEY=""
    read -rp "$(echo -e "${BLUE}Add an SSH public key for ${USER_NAME}? [y/N]: ${NC}")" ADD_KEY
    if [[ "$ADD_KEY" =~ ^[Yy]$ ]]; then
        read -rp "$(echo -e "${BLUE}Path to public key file [default ~/.ssh/id_rsa.pub]: ${NC}")" KEY_PATH
        KEY_PATH=${KEY_PATH:-$HOME/.ssh/id_rsa.pub}
        if [ -f "$KEY_PATH" ]; then
            SSH_PUBKEY=$(cat "$KEY_PATH")
            SSH_KEY_USED="yes"
            echo -e "${GREEN}Key loaded from ${KEY_PATH}.${NC}"
        else
            echo -e "${RED}Key file not found at ${KEY_PATH} - continuing with password auth only.${NC}"
        fi
    fi

    TCP_HOST_PORT=${TCP_HOST_PORT:-2222}
    TCP_GUEST_PORT=22

    echo ""
    echo -e "${YELLOW}Installing core dependencies...${NC}"
    $SUDO_CMD apt-get update -y >/dev/null 2>&1
    $SUDO_CMD apt-get install -y qemu-system-x86 qemu-utils wget cloud-image-utils curl coreutils >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Dependency install failed. Check apt/network and re-run.${NC}"
        pause_menu 3
        return
    fi

    $SUDO_CMD mkdir -p "$BASE_DIR"

    if [ ! -f "$IMG_PATH" ]; then
        echo -e "${YELLOW}Downloading ${OS_NAME} cloud image to ${BASE_DIR}...${NC}"
        $SUDO_CMD wget -q --show-progress "$IMG_URL" -O "$IMG_PATH"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Image download failed.${NC}"
            pause_menu 3
            return
        fi

        echo -e "${YELLOW}Verifying image checksum...${NC}"
        SHA_TMP=$(mktemp)
        if curl -sSf "$SHA_URL" -o "$SHA_TMP" 2>/dev/null; then
            EXPECTED_SHA=$(grep "$SHA_FILE_MATCH" "$SHA_TMP" | awk '{print $1}')
            ACTUAL_SHA=$($SHA_ALGO "$IMG_PATH" | awk '{print $1}')
            if [ -n "$EXPECTED_SHA" ] && [ "$EXPECTED_SHA" = "$ACTUAL_SHA" ]; then
                echo -e "${GREEN}Checksum verified.${NC}"
            else
                echo -e "${RED}Checksum mismatch - downloaded image may be corrupt or tampered with.${NC}"
                rm -f "$IMG_PATH"
                rm -f "$SHA_TMP"
                pause_menu 3
                return
            fi
        else
            echo -e "${YELLOW}Could not fetch checksum manifest - skipping verification.${NC}"
        fi
        rm -f "$SHA_TMP"

        $SUDO_CMD chown "$(id -u)":"$(id -g)" "$IMG_PATH" 2>/dev/null
        $SUDO_CMD chmod 600 "$IMG_PATH"

        echo -e "${YELLOW}Validating disk image integrity...${NC}"
        if ! qemu-img check "$IMG_PATH" >/dev/null 2>&1; then
            echo -e "${RED}Downloaded image failed integrity check - it may be truncated or corrupted.${NC}"
            rm -f "$IMG_PATH"
            pause_menu 3
            return
        fi
    else
        echo -e "${GREEN}Existing cached ${OS_NAME} image found at ${IMG_PATH}.${NC}"
    fi

    loading_bar "Generating cloud-init config"
    {
        echo "#cloud-config"
        echo "ssh_pwauth: True"
        echo "chpasswd:"
        echo "  list: |"
        echo "    ${USER_NAME}:${USER_PASS}"
        echo "  expire: False"
        if [ "$SSH_KEY_USED" = "yes" ]; then
            echo "users:"
            echo "  - default"
            echo "  - name: ${USER_NAME}"
            echo "    ssh_authorized_keys:"
            echo "      - ${SSH_PUBKEY}"
            echo "    sudo: ALL=(ALL) NOPASSWD:ALL"
            echo "    shell: /bin/bash"
        fi
    } > "$USER_DATA"
    unset USER_PASS USER_PASS_CONFIRM SSH_PUBKEY

    cloud-localds "$SEED_IMG" "$USER_DATA"
    if [ $? -ne 0 ]; then
        echo -e "${RED}cloud-localds failed to build the seed image.${NC}"
        shred -u "$USER_DATA" 2>/dev/null || rm -f "$USER_DATA"
        pause_menu 3
        return
    fi
    shred -u "$USER_DATA" 2>/dev/null || rm -f "$USER_DATA"

    if [ ! -f "$RESIZED_FLAG" ]; then
        loading_bar "Resizing virtual disk (+${DISK_ADD}G)"
        $SUDO_CMD qemu-img resize "$IMG_PATH" "+${DISK_ADD}G"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Disk resize failed.${NC}"
            pause_menu 3
            return
        fi
        if ! qemu-img check "$IMG_PATH" >/dev/null 2>&1; then
            echo -e "${RED}Image failed integrity check after resize.${NC}"
            pause_menu 3
            return
        fi
        touch "$RESIZED_FLAG"
    else
        echo -e "${YELLOW}Disk already resized previously - skipping (use cleanup to reset).${NC}"
    fi

    save_env
    boot_qemu
}

# ----------------------------------------------------------
# tcp config
# ----------------------------------------------------------
configure_tcp() {
    clear
    echo -e "${YELLOW}==========================================================${NC}"
    echo -e "${WHITE}  TCP PORT FORWARDING - medu VPS dashboard${NC}"
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
    if vm_is_running; then
        echo -e "${YELLOW}VM is currently running - restart it (option 2) for this change to take effect.${NC}"
    fi
    pause_menu 2
}

save_env() {
    {
        echo "OS_NAME=${OS_NAME:-ubuntu}"
        echo "IMG_PATH=${IMG_PATH:-${BASE_DIR}/ubuntu.qcow2}"
        echo "RAM_GB=${RAM_GB:-4}"
        echo "CPU_CORES=${CPU_CORES:-2}"
        echo "CPU_TYPE=${CPU_TYPE:-host}"
        echo "USER_NAME=${USER_NAME:-ubuntu}"
        echo "TCP_HOST_PORT=${TCP_HOST_PORT:-2222}"
        echo "TCP_GUEST_PORT=${TCP_GUEST_PORT:-22}"
        echo "SSH_KEY_USED=${SSH_KEY_USED:-no}"
    } > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

# ----------------------------------------------------------
# boot
# ----------------------------------------------------------
boot_qemu() {
    [ -f "$ENV_FILE" ] && source "$ENV_FILE"

    TCP_HOST_PORT=${TCP_HOST_PORT:-2222}
    TCP_GUEST_PORT=${TCP_GUEST_PORT:-22}
    CPU_TYPE=${CPU_TYPE:-host}
    RAM_VALUE="${RAM_GB:-4}G"

    KVM_FLAGS=""
    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        KVM_FLAGS="-enable-kvm"
    else
        echo -e "${YELLOW}KVM not available - falling back to software emulation (slower).${NC}"
        if [ "$CPU_TYPE" = "host" ]; then
            CPU_TYPE="qemu64"
        fi
    fi

    clear
    echo -e "${GREEN}==========================================================${NC}"
    type_effect "medu VPS - synchronizing tunnels and launching VM..." 0.015
    echo -e "${GREEN}==========================================================${NC}"
    echo ""

    SSHX_URL=""
    if require_cmd curl; then
        sshx_log=$(mktemp)
        curl -sSf https://sshx.io/get | sh -s run > "$sshx_log" 2>&1 &
        for _ in $(seq 1 20); do
            SSHX_URL=$(grep -oE 'https://sshx\.io/s/[a-zA-Z0-9]*' "$sshx_log" | head -n1)
            [ -n "$SSHX_URL" ] && break
            sleep 0.5
        done
        rm -f "$sshx_log"
    fi

    clear
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${WHITE}   VM NETWORK ACTIVE - medu VPS dashboard${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${WHITE}OS         : ${CYAN}${OS_NAME:-ubuntu}${NC}"
    echo -e "${WHITE}Username   : ${CYAN}${USER_NAME:-ubuntu}${NC}"
    echo -e "${WHITE}Resources  : ${CYAN}${RAM_VALUE} RAM | ${CPU_CORES:-2} cores | CPU: ${CPU_TYPE}${NC}"
    echo -e "${WHITE}Port rule  : ${YELLOW}host ${TCP_HOST_PORT} -> guest ${TCP_GUEST_PORT}${NC}"
    echo -e "${WHITE}SSH key    : ${CYAN}${SSH_KEY_USED:-no}${NC}"
    echo -e "${RED}----------------------------------------------------------${NC}"
    if [ -n "$SSHX_URL" ]; then
        echo -e "${YELLOW}Live shareable terminal link:${NC}"
        echo -e "${GREEN}${SSHX_URL}${NC}"
    else
        echo -e "${RED}sshx tunnel unavailable - use the local port instead.${NC}"
    fi
    echo -e "${RED}----------------------------------------------------------${NC}"
    echo -e "${WHITE}Connect with: ssh ${USER_NAME:-ubuntu}@localhost -p ${TCP_HOST_PORT}${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${WHITE}              powered by medu's VPS dashboard${NC}"
    echo ""

    qemu-system-x86_64 \
        $KVM_FLAGS \
        -cpu "$CPU_TYPE" \
        -machine type=pc,accel=kvm:tcg \
        -boot order=c,menu=off \
        -drive file="$IMG_PATH",format=qcow2,if=virtio,cache=writeback \
        -m "$RAM_VALUE" \
        -smp "${CPU_CORES:-2}" \
        -drive file="$SEED_IMG",format=raw,if=virtio \
        -nographic \
        -netdev user,id=net0,hostfwd=tcp::${TCP_HOST_PORT}-:${TCP_GUEST_PORT},dns=8.8.8.8 \
        -device virtio-net-pci,netdev=net0 \
        -pidfile "$PID_FILE"
}

# ----------------------------------------------------------
# restart / clean
# ----------------------------------------------------------
restart_vps() {
    if vm_is_running; then
        echo -e "${RED}VM is already running (pid $(cat "$PID_FILE")). Stop it first.${NC}"
        pause_menu 3
        return
    fi
    [ -f "$ENV_FILE" ] && source "$ENV_FILE"
    if [ -f "${IMG_PATH:-}" ] && [ -f "$SEED_IMG" ]; then
        echo -e "${GREEN}Restarting existing ${OS_NAME:-} VM...${NC}"
        sleep 1
        boot_qemu
    else
        echo -e "${RED}No existing VPS config found. Use option 1 first.${NC}"
        pause_menu 3
    fi
}

clean_vps() {
    if vm_is_running; then
        echo -e "${RED}VM is currently running (pid $(cat "$PID_FILE")). Stop it before cleaning up.${NC}"
        pause_menu 3
        return
    fi
    [ -f "$ENV_FILE" ] && source "$ENV_FILE"
    echo -e "${RED}Removing VPS files and configuration...${NC}"
    $SUDO_CMD rm -f "$USER_DATA" "$SEED_IMG" "$ENV_FILE" "$PID_FILE"
    $SUDO_CMD rm -f "${BASE_DIR}"/.disk_resized*
    $SUDO_CMD rm -f "${IMG_PATH:-}"
    $SUDO_CMD rm -f "${BASE_DIR}"/ubuntu.qcow2 "${BASE_DIR}"/debian.qcow2
    pkill -f sshx >/dev/null 2>&1
    echo -e "${GREEN}Workspace wiped.${NC}"
    pause_menu 2
}

# ----------------------------------------------------------
show_menu
