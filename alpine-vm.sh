#!/bin/bash
set -euo pipefail

# ============================================================
# alpine-vm.sh — Fully automated Alpine Linux VM installation
# Pure keyboard + SSH (no serial console dependency)
# ============================================================

# === Configurable defaults (override via env vars) ===
VERBOSE=false
DRY_RUN=false
VM_DIR="${VM_DIR:-/Volumes/EXT1TB/VMS}"
VM_NAME="${VM_NAME:-alpine}"
ISO_PATH="${ISO_PATH:-$VM_DIR/vmimages/alpine-virt-3.24.1-x86_64.iso}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"
VM_MEMORY="${VM_MEMORY:-16384}"
VM_CPUS="${VM_CPUS:-2}"
VM_DISK_SIZE="${VM_DISK_SIZE:-20480}"
SSH_PORT="${SSH_PORT:-2222}"

# Answerfile customization
VM_KEYMAP="${VM_KEYMAP:-us us}"
VM_HOSTNAME="${VM_HOSTNAME:-alpine}"
VM_TIMEZONE="${VM_TIMEZONE:-UTC}"
VM_DISK="${VM_DISK:-sda}"
VM_DISK_MODE="${VM_DISK_MODE:-sys}"
VM_SSHD="${VM_SSHD:-openssh}"

# === Timing constants (all integers — bash can't do float arithmetic) ===
MAX_RETRIES_FAST=300
SLEEP_FAST=1
SSH_TIMEOUT=300
SETUP_TIMEOUT="${SETUP_TIMEOUT:-180}"

# === Internal state ===
RUN_ID=$(date +%s)
VDI_PATH="$VM_DIR/$VM_NAME/${VM_NAME}_${RUN_ID}.vdi"
LOG_FILE="$VM_DIR/$VM_NAME/Logs/VBox.log"
SSH_KEY_DIR=$(mktemp -d /tmp/alpine-vm-key.XXXXXX 2>/dev/null) || SSH_KEY_DIR=""
CLEANUP_NEEDED=true
VM_CREATED=false

# ============================================================
# Helper functions
# ============================================================

die() {
    echo "ERROR: $*"
    exit 1
}

info() {
    echo "==> $*"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found on PATH"
}

VBoxManage() {
    if [ "$VERBOSE" = true ] || [ "$DRY_RUN" = true ]; then
        echo "  VBoxManage $*"
    fi
    [ "$DRY_RUN" != true ] || return 0
    command VBoxManage "$@"
}

cleanup() {
    local rc=$?
    [ "$DRY_RUN" = true ] && info "Dry-run: skipping cleanup" && return 0
    if [ -n "$SSH_KEY_DIR" ] && [ -d "$SSH_KEY_DIR" ]; then
        rm -rf "$SSH_KEY_DIR" 2>/dev/null || true
    fi
    if [ "$VM_CREATED" = true ] && [ "$CLEANUP_NEEDED" = true ]; then
        echo ""
        info "Cleaning up VM '$VM_NAME' (exit code $rc)..."
        VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
        sleep 1
        VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true
        info "Cleanup complete."
    fi
}

wait_for_log() {
    local pattern="$1" label="$2"
    local max="${3:-$MAX_RETRIES_FAST}" interval="${4:-$SLEEP_FAST}"
    local total_sec=$(( max * interval ))
    local retry=0

    info "Waiting for $label (up to ${total_sec}s)..."
    [ "$DRY_RUN" = true ] && info "  (dry-run: skipped)" && return 0
    while [ $retry -lt "$max" ]; do
        if [ -f "$LOG_FILE" ] && grep -q "$pattern" "$LOG_FILE" 2>/dev/null; then
            info "$label detected."
            return 0
        fi
        retry=$((retry + 1))
        sleep "$interval"
    done
    die "$label not detected after ${total_sec}s. Check $LOG_FILE"
}

send_line() {
    VBoxManage controlvm "$VM_NAME" keyboardputstring "$1"
    sleep 0.3
    VBoxManage controlvm "$VM_NAME" keyboardputscancode 1c 9c
    sleep 0.3
}

# ============================================================
# Argument parsing
# ============================================================

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            cat <<'HELP'
Usage: ./alpine-vm.sh [OPTIONS]

Fully automated Alpine Linux VM creation and provisioning in VirtualBox.
Uses keyboard input (tty1) for installation, SSH for post-config.

Options:
  -v, --verbose    Show each VBoxManage command as it runs
  --dry-run        Print commands without executing anything
  --help, -h       Show this help message

Environment variables (all optional):
  VM_DIR           VM storage directory           (default: /Volumes/EXT1TB/VMS)
  VM_NAME          VM name                        (default: alpine)
  ISO_PATH         Alpine ISO path                (default: <VM_DIR>/vmimages/...)
  ROOT_PASSWORD    Root password                  (default: auto-generated)
  VM_MEMORY        RAM in MB                      (default: 16384)
  VM_CPUS          CPU count                      (default: 2)
  VM_DISK_SIZE     Disk size in MB                (default: 20480)
  SSH_PORT         Host SSH port forwarding       (default: 2222)
  VM_KEYMAP        Keyboard layout                (default: us us)
  VM_HOSTNAME      VM hostname                    (default: alpine)
  VM_TIMEZONE      Timezone                       (default: UTC)
  VM_DISK          Target disk device             (default: sda)
  VM_DISK_MODE     Disk setup mode (sys/data)     (default: sys)
  VM_SSHD          SSH server package             (default: openssh)
  SETUP_TIMEOUT    Max seconds to wait for setup  (default: 180)

Requires: VBoxManage, ssh-keygen, ssh, nc
HELP
            exit 0
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1. Use --help for usage."
            exit 1
            ;;
    esac
done

# ============================================================
# Prerequisites
# ============================================================

require_cmd VBoxManage
require_cmd nc
[ -f "$ISO_PATH" ] || die "Alpine ISO not found: $ISO_PATH"
[ -d "$(dirname "$VM_DIR/$VM_NAME")" ] || mkdir -p "$(dirname "$VM_DIR/$VM_NAME")"

[ -n "$ROOT_PASSWORD" ] || ROOT_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 12) || true

# ============================================================
# Clean previous artifacts
# ============================================================

info "Killing stale VirtualBox processes..."
VBoxManage list runningvms 2>/dev/null | while IFS= read -r line; do
    name=$(echo "$line" | grep -o '"[^"]*"' | tr -d '"') || name=""
    [ -n "$name" ] && VBoxManage controlvm "$name" acpipowerbutton 2>/dev/null || true
done || true
sleep 1
for p in VBoxSVC VBoxHeadless VirtualBoxVM VBoxManage; do
    [ "$DRY_RUN" = true ] || killall -9 "$p" 2>/dev/null || true
done
sleep 1

if [ "$DRY_RUN" = true ]; then
    info "Dry-run: preserving existing VM directory $VM_DIR/$VM_NAME"
else
    rm -rf "$VM_DIR/$VM_NAME"
fi
VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true

# ============================================================
# Generate SSH key for the answerfile's ROOTSSHKEY
# ============================================================

if [ "$DRY_RUN" = true ]; then
    info "Dry-run: generating dummy SSH key..."
    SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINgjQ... dry-run-key"
else
    info "Generating temporary SSH key for VM access..."
    require_cmd ssh-keygen
    require_cmd ssh
    ssh-keygen -t ed25519 -f "$SSH_KEY_DIR/$VM_NAME-priv" -N "" -q
    mv "$SSH_KEY_DIR/$VM_NAME-priv.pub" "$SSH_KEY_DIR/$VM_NAME-pub"
    SSH_PUBKEY=$(cat "$SSH_KEY_DIR/$VM_NAME-pub")
fi

info "Answerfile and SSH key ready."

# ============================================================
# Create VM
# ============================================================

info "Creating VM '$VM_NAME'..."
VBoxManage createvm --name "$VM_NAME" --basefolder "$VM_DIR" --ostype "Linux_64" --register
VM_CREATED=true
trap cleanup EXIT

VBoxManage modifyvm "$VM_NAME" \
    --memory "$VM_MEMORY" --cpus "$VM_CPUS" \
    --boot1 disk --boot2 dvd \
    --nic1 nat --nictype1 virtio \
    --natpf1 "ssh,tcp,,$SSH_PORT,,22"

# ============================================================
# Create and attach storage
# ============================================================

info "Creating ${VM_DISK_SIZE}MB system disk..."
VBoxManage createmedium disk --filename "$VDI_PATH" --size "$VM_DISK_SIZE" --format VDI

VBoxManage storagectl "$VM_NAME" --name "SATA Controller" --add sata --controller IntelAhci

info "Attaching disk to SATA port 0..."
VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$VDI_PATH"

info "Attaching ISO to SATA port 1..."
VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 1 --device 0 --type dvddrive --medium "$ISO_PATH"

# ============================================================
# Start VM
# ============================================================

info "Booting VM (headless)..."
VBoxManage startvm "$VM_NAME" --type headless

if [ "$DRY_RUN" = true ]; then
    CLEANUP_NEEDED=false
    echo ""

    echo "  Dry-run complete. Pass --help for full option list."
    exit 0
fi

# ============================================================
# Wait for CD-ROM initialization
# ============================================================

wait_for_log "Booting from CD-ROM" "CD-ROM initialization"

# ============================================================
# Wait for kernel to boot (vboxguest driver = kernel is up)
# ============================================================

wait_for_log "vboxguest: host-version" "kernel initialization"
[ "$DRY_RUN" = true ] || sleep 5

# ============================================================
# Keyboard provisioning (tty1 — the only reliable channel)
# ============================================================

info "Waiting for Alpine boot to complete..."
sleep 35

info "Keyboard login as root on tty1..."
send_line "root"
sleep 2
send_line ""
sleep 3

info "Bringing up network (eth0)..."
send_line "ip link set eth0 up"
sleep 1
send_line "udhcpc -i eth0 -q"
sleep 5

info "Writing answerfile..."
send_line "echo 'KEYMAPOPTS=\"us us\"' > /tmp/answers"
sleep 0.3
send_line "echo 'HOSTNAMEOPTS=\"-n alpine\"' >> /tmp/answers"
sleep 0.3
send_line "echo 'TIMEZONEOPTS=\"-z UTC\"' >> /tmp/answers"
sleep 0.3
send_line "echo 'INTERFACESOPTS=\"auto lo' >> /tmp/answers"
sleep 0.3
send_line "echo 'iface lo inet loopback' >> /tmp/answers"
sleep 0.3
send_line "echo 'auto eth0' >> /tmp/answers"
sleep 0.3
send_line "echo 'iface eth0 inet dhcp\"' >> /tmp/answers"
sleep 0.3
send_line "echo 'PROXYOPTS=\"none\"' >> /tmp/answers"
sleep 0.3
send_line "echo 'NTPOPTS=\"busybox\"' >> /tmp/answers"
sleep 0.3
send_line "echo 'APKREPOSOPTS=\"https://dl-cdn.alpinelinux.org/alpine/v3.24/main\"' >> /tmp/answers"
sleep 0.3
send_line "echo 'USEROPTS=\"none\"' >> /tmp/answers"
sleep 0.3
send_line "echo 'SSHDOPTS=\"openssh\"' >> /tmp/answers"
sleep 0.3
send_line "echo 'ROOTSSHKEY=\"${SSH_PUBKEY}\"' >> /tmp/answers"
sleep 0.3
send_line "echo 'DISKOPTS=\"-m sys /dev/sda\"' >> /tmp/answers"
sleep 0.3

info "Running setup-alpine with answerfile (auto-answer with yes)..."
send_line "yes | setup-alpine -ef /tmp/answers"
info "Waiting ${SETUP_TIMEOUT}s for installation to complete..."
sleep "$SETUP_TIMEOUT"

info "Waiting for VM to reboot and SSH to come up..."
# The live ISO SSH accepts TCP but doesn't respond with a banner,
# so we use actual SSH connection attempt to detect real SSH.
# Phase 1: wait for live ISO SSH to go away (port close)
for i in $(seq 1 90); do
    if ! nc -z -w 1 localhost "$SSH_PORT" 2>/dev/null; then
        info "Port closed — VM is rebooting"
        break
    fi
    sleep 2
done

# Phase 2: wait for installed system SSH (actual banner exchange)
# Each attempt takes ~5s (ConnectTimeout) + 5s sleep = 10s, so 40 iterations ≈ 400s max.
ssh_ready=false
for i in $(seq 1 40); do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
        -i "$SSH_KEY_DIR/$VM_NAME-priv" root@localhost -p "$SSH_PORT" "exit" \
        2>/dev/null; then
        ssh_ready=true
        info "SSH connection successful"
        break
    fi
    sleep 5
done

if [ "$ssh_ready" = false ]; then
    echo ""
    echo "========================================================"
    echo "  SSH port not detected within ${SSH_TIMEOUT}s."
    echo "  The VM may still be booting. Check manually:"
    echo "  ssh -i $SSH_KEY_DIR/$VM_NAME-priv root@localhost -p $SSH_PORT"
    echo "========================================================"
    exit 1
fi

# ============================================================
# SSH-based post-install (belt-and-suspenders: ensure config)
# ============================================================

info "Verifying SSH config via SSH..."
ssh -i "$SSH_KEY_DIR/$VM_NAME-priv" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    root@localhost -p "$SSH_PORT" \
    "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && echo 'root:${ROOT_PASSWORD}' | chpasswd && rc-service sshd restart" \
    2>/dev/null || true
sleep 2

# ============================================================
# Cleanup: eject ISO now that system is running from disk
# ============================================================

info "Ejecting installation media..."
VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 1 --device 0 --type dvddrive --medium none 2>/dev/null || true

# ============================================================
# Print success
# ============================================================

CLEANUP_NEEDED=false

echo ""
echo "========================================================"
echo "  Alpine Linux VM is ready!"
echo "  VM name:     $VM_NAME"
echo "  SSH:         ssh root@localhost -p $SSH_PORT"
echo "  Password:    $ROOT_PASSWORD"
echo "========================================================"
