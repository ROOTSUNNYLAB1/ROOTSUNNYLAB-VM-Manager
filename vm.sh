#!/usr/bin/env bash
# ==============================================================================
#  ROOTSUNNYLAB Virtual Machine Manager
#  Powered by ROOTSUNNY
#
#  Multi-VM manager on top of QEMU + cloud-init.
#  Env:  VM_DIR=<path>  (default ~/vms)    NO_ANIM=1  (disable animations)
#        NO_COLOR=1     (disable colors)
# ==============================================================================
set -uo pipefail

APP_BRAND="ROOTSUNNYLAB"
APP_SUB="Virtual Machine Manager"
APP_VER="2.0"
IW=68; COLS=80; BARW=34; PADS='  '   # recomputed from the terminal size by layout()

# ------------------------------------------------------------------------------
#  Terminal / theme  (muted classic palette, no neon)
# ------------------------------------------------------------------------------
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;; *) export LC_ALL=C.UTF-8 ;; esac
TTY=0; [[ -t 1 ]] && TTY=1
ANIM=$TTY; [[ "${NO_ANIM:-0}" == "1" ]] && ANIM=0
ESC=$'\033'
if (( TTY )) && [[ -z "${NO_COLOR:-}" ]]; then
    C_RST="${ESC}[0m";            C_B="${ESC}[1m"
    C_DIM="${ESC}[38;5;244m";     C_TXT="${ESC}[38;5;252m";  C_HI="${ESC}[38;5;231m"
    C_ACC="${ESC}[38;5;180m";     C_OK="${ESC}[38;5;108m";   C_WARN="${ESC}[38;5;179m"
    C_ERR="${ESC}[38;5;167m";     C_INF="${ESC}[38;5;109m";  C_BAR="${ESC}[38;5;239m"
else
    C_RST=""; C_B=""; C_DIM=""; C_TXT=""; C_HI=""; C_ACC=""
    C_OK=""; C_WARN=""; C_ERR=""; C_INF=""; C_BAR=""
fi

WORK="$(mktemp -d)"
LOG="$(mktemp)"

nap()         { (( ANIM )) && sleep "$1"; return 0; }
hide_cursor() { (( TTY )) && printf '%s[?25l' "$ESC"; return 0; }
show_cursor() { (( TTY )) && printf '%s[?25h' "$ESC"; return 0; }
rep()         { local s; printf -v s '%*s' "$2" ''; printf '%s' "${s// /$1}"; }
center()      { local t=$1 w=$2 l; l=$(( (w - ${#t}) / 2 )); (( l < 0 )) && l=0; printf '%*s%s' "$l" '' "$t"; }

# Auto-fit: read the real terminal size and derive every width from it.
layout() {
    local c=0 r
    if [[ -n "${RSL_COLS:-}" ]]; then c=$RSL_COLS
    elif (( TTY )); then read -r r c < <(stty size </dev/tty 2>/dev/null) || c=0; fi
    [[ $c =~ ^[0-9]+$ ]] && (( c >= 20 )) || c=${COLUMNS:-80}
    [[ $c =~ ^[0-9]+$ ]] && (( c >= 20 )) || c=80
    COLS=$c
    IW=$(( COLS - 6 )); (( IW > 68 )) && IW=68; (( IW < 24 )) && IW=24
    local pad=$(( (COLS - IW - 2) / 2 )); (( pad < 2 )) && pad=2
    printf -v PADS '%*s' "$pad" ''
    BARW=$(( COLS - 42 )); (( BARW > 34 )) && BARW=34; (( BARW < 8 )) && BARW=8
}
trap layout WINCH
layout

cleanup() { rm -rf "$WORK" "$LOG" 2>/dev/null; show_cursor; }
trap cleanup EXIT
trap 'show_cursor; echo; exit 130' INT TERM

# ------------------------------------------------------------------------------
#  Banner
# ------------------------------------------------------------------------------
box_row() {
    local t=$1 col=${2:-$C_TXT} n=${3:-${#1}} l r
    l=$(( (IW - n) / 2 )); r=$(( IW - n - l ))
    printf '%s%s║%s%*s%s%s%s%*s%s║%s\n' "$PADS" "$C_DIM" "$C_RST" "$l" "" "$col" "$t" "$C_RST" "$r" "" "$C_DIM" "$C_RST"
}

title_row() {   # $1 = shimmer position (any value outside the text = no shimmer)
    local hl=$1 t="R O O T S U N N Y   L A B" i ch col out="" pl pr
    (( IW < ${#t} + 4 )) && t="ROOTSUNNYLAB"
    pl=$(( (IW - ${#t}) / 2 )); pr=$(( IW - ${#t} - pl ))
    for (( i = 0; i < ${#t}; i++ )); do
        ch=${t:i:1}; col=$C_ACC
        (( i >= hl - 2 && i <= hl )) && col=$C_HI
        out+="${C_B}${col}${ch}"
    done
    printf '\r%s%s║%s%*s%s%s%*s%s║%s' "$PADS" "$C_DIM" "$C_RST" "$pl" "" "$out" "$C_RST" "$pr" "" "$C_DIM" "$C_RST"
}

header() {
    local animate=${1:-0} line i foot
    layout
    (( TTY )) && clear
    line=$(rep '═' "$IW")
    echo
    printf '%s%s╔%s╗%s\n' "$PADS" "$C_DIM" "$line" "$C_RST"; nap 0.02
    box_row "";                                        nap 0.02
    if (( animate && ANIM )); then
        hide_cursor
        for (( i = -3; i <= 27; i++ )); do title_row "$i"; sleep 0.03; done
        show_cursor
    fi
    title_row -99; printf '\n';                        nap 0.02
    box_row "$(rep '─' $(( IW > 30 ? 24 : IW - 8 )))" "$C_DIM" $(( IW > 30 ? 24 : IW - 8 ));                  nap 0.02
    box_row "$APP_SUB" "$C_TXT";                       nap 0.02
    box_row "Powered by ROOTSUNNY" "$C_DIM";           nap 0.02
    box_row "";                                        nap 0.02
    printf '%s%s╚%s╝%s\n' "$PADS" "$C_DIM" "$line" "$C_RST"
    foot="v$APP_VER  ·  QEMU  ·  cloud-init  ·  © $APP_BRAND"
    (( ${#foot} > IW + 2 )) && foot="v$APP_VER  ·  © $APP_BRAND"
    (( ${#foot} > IW + 2 )) && foot="© $APP_BRAND"
    printf '%s%s%s%s\n\n' "$PADS" "$C_DIM" "$(center "$foot" $((IW + 2)))" "$C_RST"
}

# ------------------------------------------------------------------------------
#  Output helpers
# ------------------------------------------------------------------------------
print_status() {
    local type=$1; shift
    local msg=$* col tag=$type
    case $type in
        INFO)    col=$C_INF ;;
        WARN)    col=$C_WARN ;;
        ERROR)   col=$C_ERR ;;
        SUCCESS) col=$C_OK ;;
        INPUT)   col=$C_ACC ;;
        *)       col=$C_DIM ;;
    esac
    printf '  %s%-9s%s %s%s%s\n' "$col" "[$tag]" "$C_RST" "$C_TXT" "$msg" "$C_RST"
}

section() {
    local n=$(( IW - ${#1} - 2 )); (( n < 2 )) && n=2
    printf '\n  %s── %s %s%s\n\n' "$C_ACC" "$1" "$(rep '─' "$n")" "$C_RST"
}

menu_item() {
    printf '   %s%2s%s   %s%s%s\n' "$C_ACC" "$1" "$C_RST" "$C_TXT" "$2" "$C_RST"
    nap 0.012
}

kv() {
    printf '  %s│%s %s%-16s%s %s%s%s\n' "$C_DIM" "$C_RST" "$C_DIM" "$1" "$C_RST" "$C_TXT" "$2" "$C_RST"
    nap 0.02
}

typewrite() {
    local s=$1 d=${2:-0.01} i
    for (( i = 0; i < ${#s}; i++ )); do printf '%s' "${s:i:1}"; nap "$d"; done
}

draw_bar() {    # $1 = percent, $2 = width
    local pct=$1 w=${2:-$BARW} f e fb eb
    (( pct > 100 )) && pct=100; (( pct < 0 )) && pct=0
    f=$(( pct * w / 100 )); e=$(( w - f ))
    printf -v fb '%*s' "$f" ''; printf -v eb '%*s' "$e" ''
    printf '%s%s%s%s%s' "$C_ACC" "${fb// /█}" "$C_BAR" "${eb// /░}" "$C_RST"
}

progress_anim() {   # $1 = label, $2 = steps
    local label=$1 steps=${2:-24} i p
    (( ANIM )) || return 0
    hide_cursor
    for (( i = 0; i <= steps; i++ )); do
        p=$(( i * 100 / steps ))
        printf '\r  %s%-22s%s %s %s%3d%%%s' "$C_TXT" "${label:0:22}" "$C_RST" "$(draw_bar "$p" $(( BARW - 2 )))" "$C_DIM" "$p" "$C_RST"
        sleep 0.025
    done
    printf '\n'; show_cursor
}

spin() {        # $1 = pid to watch, $2 = message
    local pid=$1 msg=$2 i=0 f='|/-\'
    hide_cursor
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %s%s%s  %s%s%s' "$C_ACC" "${f:i%4:1}" "$C_RST" "$C_TXT" "$msg" "$C_RST"
        i=$(( i + 1 )); sleep 0.1
    done
    printf '\r%s[K' "$ESC"; show_cursor
}

run_task() {    # $1 = message, rest = external command
    local msg=$1 rc pid; shift
    if (( TTY )); then
        "$@" >"$LOG" 2>&1 &
        pid=$!
        spin "$pid" "$msg"
        wait "$pid"; rc=$?
    else
        "$@" >"$LOG" 2>&1; rc=$?
    fi
    if (( rc == 0 )); then
        print_status SUCCESS "$msg"
    else
        print_status ERROR "$msg failed"
        tail -n 5 "$LOG" | sed 's/^/             /'
    fi
    return $rc
}

pause() { printf '\n  %sPress Enter to continue...%s' "$C_DIM" "$C_RST"; IFS= read -r _ || exit 0; }

# ------------------------------------------------------------------------------
#  Input helpers
# ------------------------------------------------------------------------------
validate_input() {
    local type=$1 value=$2
    case $type in
        number)
            [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 )) || { print_status ERROR "Must be a positive number"; return 1; } ;;
        size)
            [[ "$value" =~ ^[0-9]+[GgMm]$ ]] || { print_status ERROR "Must be a size with unit (e.g., 100G, 512M)"; return 1; } ;;
        port)
            [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 23 && value <= 65535 )) || { print_status ERROR "Must be a valid port number (23-65535)"; return 1; } ;;
        name)
            [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || { print_status ERROR "Only letters, numbers, hyphens and underscores are allowed"; return 1; } ;;
        username)
            [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]] || { print_status ERROR "Must start with a letter or underscore; lowercase letters, numbers, - and _ only"; return 1; } ;;
        yesno)
            [[ "$value" =~ ^[YyNn]$ ]] || { print_status ERROR "Please answer y or n"; return 1; } ;;
        forwards)
            [[ -z "$value" || "$value" =~ ^[0-9]+:[0-9]+(,[0-9]+:[0-9]+)*$ ]] || { print_status ERROR "Use host:guest pairs, comma separated (e.g., 8080:80,8443:443)"; return 1; } ;;
        nonempty)
            [[ -n "$value" ]] || { print_status ERROR "This field cannot be empty"; return 1; } ;;
    esac
    return 0
}

ask() {         # ask VAR "Label" "default" [type]
    local __v=$1 label=$2 def=${3:-} type=${4:-} val hint=""
    [[ -n $def ]] && hint=" ${C_DIM}[$def]${C_RST}"
    while true; do
        printf '  %s›%s %s%s%s%s: ' "$C_ACC" "$C_RST" "$C_TXT" "$label" "$C_RST" "$hint"
        IFS= read -r val || exit 0
        val=${val:-$def}
        if [[ -z $type ]] || validate_input "$type" "$val"; then
            printf -v "$__v" '%s' "$val"; return 0
        fi
    done
}

ask_secret() {  # ask_secret VAR "Label" "default"
    local __v=$1 label=$2 def=${3:-} val hint=""
    [[ -n $def ]] && hint=" ${C_DIM}[default: $def]${C_RST}"
    while true; do
        printf '  %s›%s %s%s%s%s: ' "$C_ACC" "$C_RST" "$C_TXT" "$label" "$C_RST" "$hint"
        IFS= read -rs val || exit 0; echo
        val=${val:-$def}
        if validate_input nonempty "$val"; then printf -v "$__v" '%s' "$val"; return 0; fi
    done
}

confirm() {
    local a
    printf '  %s?%s %s%s%s %s[y/N]%s: ' "$C_WARN" "$C_RST" "$C_TXT" "$1" "$C_RST" "$C_DIM" "$C_RST"
    IFS= read -r a || exit 0
    [[ "$a" =~ ^[Yy]$ ]]
}

port_in_use() { ss -tln 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$1\$"; }

# ------------------------------------------------------------------------------
#  Dependencies / paths / OS catalog
# ------------------------------------------------------------------------------
check_dependencies() {
    local deps=(qemu-system-x86_64 qemu-img wget cloud-localds openssl) missing=() d
    for d in "${deps[@]}"; do command -v "$d" &>/dev/null || missing+=("$d"); done
    if (( ${#missing[@]} )); then
        print_status ERROR "Missing dependencies: ${missing[*]}"
        print_status INFO  "Ubuntu/Debian: sudo apt install qemu-system-x86 qemu-utils cloud-image-utils wget openssl"
        exit 1
    fi
}

VM_DIR="${VM_DIR:-$HOME/vms}"
CACHE_DIR="$VM_DIR/.cache"

OS_ORDER=("Ubuntu 22.04" "Ubuntu 24.04" "Ubuntu 25.04" "Ubuntu 26.04" "Debian 11" "Debian 12" "Debian 13" "Fedora 40" "CentOS Stream 9" "AlmaLinux 9" "Rocky Linux 9")
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Ubuntu 25.04"]="ubuntu|plucky|https://cloud-images.ubuntu.com/releases/plucky/release/ubuntu-25.04-server-cloudimg-amd64.img|ubuntu25|ubuntu|ubuntu"
    ["Ubuntu 26.04"]="ubuntu|resolute|https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img|ubuntu26|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Debian 13"]="debian|trixie|https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2|debian13|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

# ------------------------------------------------------------------------------
#  VM config storage
# ------------------------------------------------------------------------------
CFG_KEYS=(VM_NAME OS_TYPE CODENAME IMG_URL VM_HOSTNAME USERNAME PASSWORD DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED)

get_vm_list() {
    find "$VM_DIR" -maxdepth 1 -name '*.conf' -printf '%f\n' 2>/dev/null | sed 's/\.conf$//' | sort
}

load_vm_config() {
    local f="$VM_DIR/$1.conf" k
    if [[ ! -f $f ]]; then print_status ERROR "Configuration for VM '$1' not found"; return 1; fi
    for k in "${CFG_KEYS[@]}" HOSTNAME; do unset "$k"; done
    # shellcheck disable=SC1090
    source "$f"
    VM_HOSTNAME="${VM_HOSTNAME:-${HOSTNAME:-$VM_NAME}}"   # old configs used HOSTNAME
    PORT_FORWARDS="${PORT_FORWARDS:-}"
    return 0
}

save_vm_config() {
    local f="$VM_DIR/$VM_NAME.conf" k
    : > "$f"; chmod 600 "$f"
    for k in "${CFG_KEYS[@]}"; do printf '%s=%q\n' "$k" "${!k-}" >> "$f"; done
    print_status SUCCESS "Configuration saved"
}

# ------------------------------------------------------------------------------
#  Runtime state
# ------------------------------------------------------------------------------
pid_of() { local f="$VM_DIR/$1.pid"; [[ -s $f ]] && cat "$f"; }

is_vm_running() {
    local p; p=$(pid_of "$1") || return 1
    [[ -n $p ]] && kill -0 "$p" 2>/dev/null && ps -p "$p" -o comm= 2>/dev/null | grep -q qemu
}

# ------------------------------------------------------------------------------
#  Image + cloud-init
# ------------------------------------------------------------------------------
download_image() {  # $1 = url, $2 = output
    local url=$1 out=$2 total size pct pid i=0 f='|/-\' mb tmb
    total=$(wget --spider --server-response "$url" 2>&1 | awk 'tolower($1)=="content-length:"{v=$2} END{print v+0}')
    print_status INFO "Downloading base image"
    wget -q -O "$out.part" "$url" &
    pid=$!
    hide_cursor
    while kill -0 "$pid" 2>/dev/null; do
        size=$(stat -c %s "$out.part" 2>/dev/null || echo 0); mb=$(( size / 1048576 ))
        if (( total > 0 )); then
            pct=$(( size * 100 / total )); tmb=$(( total / 1048576 ))
            printf '\r  %s %s%3d%%%s  %s%d / %d MB%s ' "$(draw_bar "$pct")" "$C_DIM" "$pct" "$C_RST" "$C_DIM" "$mb" "$tmb" "$C_RST"
        else
            printf '\r  %s%s%s  %s%d MB%s ' "$C_ACC" "${f:i%4:1}" "$C_RST" "$C_DIM" "$mb" "$C_RST"
        fi
        i=$(( i + 1 )); sleep 0.2
    done
    show_cursor; printf '\r%s[K' "$ESC"
    if wait "$pid"; then
        mv "$out.part" "$out"; print_status SUCCESS "Base image downloaded"
    else
        rm -f "$out.part"; print_status ERROR "Failed to download $url"; return 1
    fi
}

prepare_image() {
    mkdir -p "$VM_DIR" "$CACHE_DIR"
    local base="$CACHE_DIR/${OS_TYPE}-${CODENAME}.img"
    if [[ -f $IMG_FILE ]]; then
        print_status INFO "VM disk already exists, keeping it"; return 0
    fi
    if [[ -s $base ]]; then
        print_status INFO "Using cached base image"
    else
        download_image "$IMG_URL" "$base" || return 1
    fi
    run_task "Creating VM disk" cp -- "$base" "$IMG_FILE" || return 1
    run_task "Resizing disk to $DISK_SIZE" qemu-img resize "$IMG_FILE" "$DISK_SIZE" \
        || print_status WARN "Resize skipped (requested size may be smaller than the base image)"
    return 0
}

build_seed() {
    local ud="$WORK/user-data" md="$WORK/meta-data" hash
    hash=$(openssl passwd -6 "$PASSWORD") || { print_status ERROR "openssl failed"; return 1; }
    cat > "$ud" <<EOF
#cloud-config
hostname: $VM_HOSTNAME
manage_etc_hosts: true
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: '$hash'
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
EOF
    cat > "$md" <<EOF
instance-id: iid-$VM_NAME-$(date +%s)
local-hostname: $VM_HOSTNAME
EOF
    run_task "Building cloud-init seed" cloud-localds "$SEED_FILE" "$ud" "$md"
}

# ------------------------------------------------------------------------------
#  KVM auto-detect (real probe, not just a /dev/kvm check)
# ------------------------------------------------------------------------------
kvm_ok() {
    [[ -r /dev/kvm && -w /dev/kvm ]] || return 1
    command -v timeout &>/dev/null || return 0
    timeout 5 qemu-system-x86_64 -machine none,accel=kvm -display none -nodefaults -S >/dev/null 2>&1
    [[ $? -eq 124 ]]    # still alive after 5s = KVM works
}

# ------------------------------------------------------------------------------
#  Actions
# ------------------------------------------------------------------------------
create_new_vm() {
    header; section "Create a new virtual machine"
    local i=1 os choice
    for os in "${OS_ORDER[@]}"; do menu_item "$i" "$os"; i=$(( i + 1 )); done
    echo
    while true; do
        ask choice "Select an OS (1-${#OS_ORDER[@]})" "1" number
        (( choice >= 1 && choice <= ${#OS_ORDER[@]} )) && break
        print_status ERROR "Invalid selection"
    done
    os="${OS_ORDER[choice-1]}"
    local DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD
    IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
    echo

    while true; do
        ask VM_NAME "VM name" "$DEFAULT_HOSTNAME" name
        if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then print_status ERROR "VM '$VM_NAME' already exists"; continue; fi
        break
    done
    ask VM_HOSTNAME "Hostname"      "$VM_NAME"         name
    ask USERNAME    "Username"      "$DEFAULT_USERNAME" username
    ask_secret PASSWORD "Password"  "$DEFAULT_PASSWORD"
    ask DISK_SIZE   "Disk size"     "20G"              size
    ask MEMORY      "Memory (MB)"   "2048"             number
    ask CPUS        "CPU cores"     "2"                number
    while true; do
        ask SSH_PORT "SSH port" "2222" port
        if port_in_use "$SSH_PORT"; then print_status ERROR "Port $SSH_PORT is already in use"; continue; fi
        break
    done
    GUI_MODE=false
    ask PORT_FORWARDS "Extra port forwards (host:guest,...)" "" forwards

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M')"

    section "Provisioning"
    prepare_image || { print_status ERROR "VM creation aborted"; return 1; }
    build_seed    || { print_status ERROR "VM creation aborted"; return 1; }
    save_vm_config
    print_status SUCCESS "VM '$VM_NAME' is ready"
}

start_vm() {
    local name=$1
    load_vm_config "$name" || return 1
    if is_vm_running "$name"; then print_status WARN "VM '$name' is already running"; return 1; fi
    [[ -f $IMG_FILE ]] || { print_status ERROR "VM image not found: $IMG_FILE"; return 1; }
    if [[ ! -f $SEED_FILE ]]; then print_status WARN "Seed file missing, rebuilding"; build_seed || return 1; fi

    local accel="NO KVM (software)" use_kvm=0
    kvm_ok && { use_kvm=1; accel="KVM (hardware)"; }

    local hostfwd="hostfwd=tcp::${SSH_PORT}-:22" fw fws=()
    if [[ -n $PORT_FORWARDS ]]; then
        IFS=',' read -ra fws <<< "$PORT_FORWARDS"
        for fw in "${fws[@]}"; do hostfwd+=",hostfwd=tcp::${fw%%:*}-:${fw##*:}"; done
    fi

    local cmd=(
        qemu-system-x86_64
        -m "$MEMORY" -smp "$CPUS"
        -drive "file=$IMG_FILE,format=qcow2,if=virtio"
        -drive "file=$SEED_FILE,format=raw,if=virtio"
        -boot order=c
        -device virtio-net-pci,netdev=n0
        -netdev "user,id=n0,$hostfwd"
        -device virtio-balloon-pci
        -object rng-random,filename=/dev/urandom,id=rng0
        -device virtio-rng-pci,rng=rng0
        -pidfile "$VM_DIR/$name.pid"
    )
    # Console always runs inside THIS terminal (serial). A separate window only if RSL_GUI=1 is set explicitly.
    local gui=false; [[ "${RSL_GUI:-0}" == "1" ]] && gui=true
    if [[ $gui == true ]]; then cmd+=(-vga virtio -display gtk); else cmd+=(-nographic -serial mon:stdio); fi

    section "Launching $name"
    kv "Acceleration" "$accel"
    kv "Resources"    "$CPUS vCPU  ·  $MEMORY MB RAM  ·  $DISK_SIZE disk"
    kv "SSH"          "ssh -p $SSH_PORT $USERNAME@localhost"
    kv "Password"     "$PASSWORD"
    kv "Console"      "this terminal (serial)"
    kv "Exit console" "Ctrl+A, then X"
    echo
    progress_anim "Starting QEMU" 26
    local rc=0 t0=$SECONDS
    if (( use_kvm )); then
        "${cmd[@]}" -accel kvm -cpu host; rc=$?
        if (( rc != 0 && SECONDS - t0 < 25 )); then
            (( TTY )) && stty sane 2>/dev/null
            echo; print_status WARN "KVM failed (exit $rc) - falling back to NO KVM (software)"
            rm -f "$VM_DIR/$name.pid"; sleep 1
            "${cmd[@]}" -accel tcg -cpu max
        fi
    else
        "${cmd[@]}" -accel tcg -cpu max
    fi
    (( TTY )) && stty sane 2>/dev/null
    rm -f "$VM_DIR/$name.pid"
    echo; print_status INFO "VM '$name' has been shut down"
}

stop_vm() {
    local name=$1 pid t=0 f='|/-\'
    load_vm_config "$name" || return 1
    if ! is_vm_running "$name"; then print_status INFO "VM '$name' is not running"; return 0; fi
    pid=$(pid_of "$name")
    kill -TERM "$pid" 2>/dev/null
    hide_cursor
    while kill -0 "$pid" 2>/dev/null && (( t < 60 )); do
        printf '\r  %s%s%s  %sStopping %s%s' "$C_ACC" "${f:t%4:1}" "$C_RST" "$C_TXT" "$name" "$C_RST"
        t=$(( t + 1 )); sleep 0.15
    done
    printf '\r%s[K' "$ESC"; show_cursor
    if kill -0 "$pid" 2>/dev/null; then print_status WARN "Not responding, forcing termination"; kill -KILL "$pid" 2>/dev/null; sleep 1; fi
    rm -f "$VM_DIR/$name.pid"
    print_status SUCCESS "VM '$name' stopped"
}

show_vm_info() {
    local name=$1 st="Stopped"
    load_vm_config "$name" || return 1
    is_vm_running "$name" && st="Running"
    section "VM information · $name"
    kv "Status"        "$st"
    kv "OS"            "$OS_TYPE $CODENAME"
    kv "Hostname"      "$VM_HOSTNAME"
    kv "Username"      "$USERNAME"
    kv "Password"      "********"
    kv "SSH port"      "$SSH_PORT"
    kv "Memory"        "$MEMORY MB"
    kv "CPUs"          "$CPUS"
    kv "Disk"          "$DISK_SIZE"
    kv "Console"       "terminal (serial)"
    kv "Port forwards" "${PORT_FORWARDS:-None}"
    kv "Created"       "$CREATED"
    kv "Image file"    "$IMG_FILE"
    kv "Seed file"     "$SEED_FILE"
}

to_mb() { local n=${1%[GgMm]} u=${1: -1}; [[ $u =~ [Gg] ]] && n=$(( n * 1024 )); echo "$n"; }

resize_vm_disk() {
    local name=$1 new
    load_vm_config "$name" || return 1
    if is_vm_running "$name"; then print_status ERROR "Stop the VM before resizing its disk"; return 1; fi
    section "Resize disk · $name"
    print_status INFO "Current disk size: $DISK_SIZE"
    ask new "New disk size" "" size
    if [[ "$new" == "$DISK_SIZE" ]]; then print_status INFO "Same size, nothing to do"; return 0; fi
    if (( $(to_mb "$new") < $(to_mb "$DISK_SIZE") )); then
        print_status ERROR "Shrinking is not supported (risk of data loss)"; return 1
    fi
    if run_task "Resizing disk to $new" qemu-img resize "$IMG_FILE" "$new"; then
        DISK_SIZE="$new"; save_vm_config
        print_status INFO "The guest grows its partition automatically on next boot (cloud-init)"
    fi
}

edit_vm_config() {
    local name=$1 c tmp
    load_vm_config "$name" || return 1
    is_vm_running "$name" && print_status WARN "VM is running: changes apply on next start"
    while true; do
        section "Edit · $name"
        menu_item 1 "Hostname"; menu_item 2 "Username"; menu_item 3 "Password"
        menu_item 4 "SSH port"; menu_item 5 "Port forwards"
        menu_item 6 "Memory (RAM)"; menu_item 7 "CPU count"; menu_item 8 "Disk size"
        menu_item 0 "Back"
        echo
        ask c "Choice" "" 
        case $c in
            1) ask VM_HOSTNAME "New hostname" "$VM_HOSTNAME" name ;;
            2) ask USERNAME "New username" "$USERNAME" username ;;
            3) ask_secret PASSWORD "New password" "$PASSWORD" ;;
            4) while true; do
                   ask tmp "New SSH port" "$SSH_PORT" port
                   if [[ "$tmp" != "$SSH_PORT" ]] && port_in_use "$tmp"; then print_status ERROR "Port $tmp is already in use"; continue; fi
                   SSH_PORT=$tmp; break
               done ;;
            5) ask PORT_FORWARDS "Port forwards (host:guest,...)" "$PORT_FORWARDS" forwards ;;
            6) ask MEMORY "Memory (MB)" "$MEMORY" number ;;
            7) ask CPUS "CPU cores" "$CPUS" number ;;
            8) resize_vm_disk "$name"; load_vm_config "$name"; continue ;;
            0) return 0 ;;
            *) print_status ERROR "Invalid selection"; continue ;;
        esac
        save_vm_config
        if [[ "$c" =~ ^[123]$ ]]; then build_seed; print_status INFO "Identity changes apply on next boot"; fi
        confirm "Continue editing?" || break
    done
}

delete_vm() {
    local name=$1
    load_vm_config "$name" || return 1
    print_status WARN "This permanently deletes VM '$name' and all of its data"
    confirm "Are you sure?" || { print_status INFO "Deletion cancelled"; return 0; }
    is_vm_running "$name" && stop_vm "$name"
    rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$name.conf" "$VM_DIR/$name.pid"
    print_status SUCCESS "VM '$name' deleted"
}

show_vm_performance() {
    local name=$1 pid cpu rss etime rss_mb mem_pct cpu_pct vsize key=""
    load_vm_config "$name" || return 1
    if ! is_vm_running "$name"; then
        section "Performance · $name"
        print_status INFO "VM is not running. Configured resources:"
        kv "Memory" "$MEMORY MB"; kv "CPUs" "$CPUS"; kv "Disk" "$DISK_SIZE"
        return 0
    fi
    pid=$(pid_of "$name")
    (( TTY )) && clear
    hide_cursor
    while kill -0 "$pid" 2>/dev/null; do
        layout
        read -r cpu rss etime < <(ps -p "$pid" -o %cpu=,rss=,etime= 2>/dev/null) || break
        cpu=${cpu%%.*}; cpu=${cpu:-0}
        rss_mb=$(( ${rss:-0} / 1024 ))
        cpu_pct=$(( cpu / CPUS )); mem_pct=$(( rss_mb * 100 / MEMORY ))
        vsize=$(du -h "$IMG_FILE" 2>/dev/null | cut -f1)
        (( TTY )) && printf '%s[H' "$ESC"
        printf '\n  %s── Live performance · %s %s%s%s[K\n\n' "$C_ACC" "$name" "$(rep '─' $(( IW - 24 - ${#name} > 2 ? IW - 24 - ${#name} : 2 )))" "$C_RST" "$ESC"
        printf '  %sCPU %s  %s %s%3d%%%s%s[K\n'  "$C_TXT" "      " "$(draw_bar "$cpu_pct" "$BARW")" "$C_DIM" "$cpu_pct" "$C_RST" "$ESC"
        printf '  %sRAM %s  %s %s%d / %d MB%s%s[K\n' "$C_TXT" "      " "$(draw_bar "$mem_pct" "$BARW")" "$C_DIM" "$rss_mb" "$MEMORY" "$C_RST" "$ESC"
        printf '\n'
        printf '  %s│%s %s%-12s%s %s%s%s[K\n' "$C_DIM" "$C_RST" "$C_DIM" "PID"       "$C_RST" "$C_TXT" "$pid"    "$C_RST$ESC"
        printf '  %s│%s %s%-12s%s %s%s%s[K\n' "$C_DIM" "$C_RST" "$C_DIM" "Uptime"    "$C_RST" "$C_TXT" "$etime"  "$C_RST$ESC"
        printf '  %s│%s %s%-12s%s %s%s%s[K\n' "$C_DIM" "$C_RST" "$C_DIM" "Disk used" "$C_RST" "$C_TXT" "$vsize / $DISK_SIZE" "$C_RST$ESC"
        printf '\n  %sPress q to return%s%s[J' "$C_DIM" "$C_RST" "$ESC"
        key=""; read -rs -t 1 -n 1 key || true
        [[ "$key" == "q" || "$key" == "Q" ]] && break
    done
    show_cursor; echo
}

# ------------------------------------------------------------------------------
#  Main menu
# ------------------------------------------------------------------------------
VMS=(); PICKED=""

pick_vm() {
    local num
    ask num "$1" "" 
    if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#VMS[@]} )); then PICKED="${VMS[num-1]}"; return 0; fi
    print_status ERROR "Invalid selection"; return 1
}

vm_table() {
    local n=${#VMS[@]} i v st sc info mem cpus port os c out cell avail=$(( COLS - 4 ))
    if (( n == 0 )); then
        printf '  %sNo virtual machines yet. Choose 1 to create your first one.%s\n\n' "$C_DIM" "$C_RST"; return
    fi
    local -a act=(num name status sys res ssh)
    local -A W=([num]=3 [name]=18 [status]=9 [sys]=15 [res]=12 [ssh]=5)
    local -A H=([num]="#" [name]="NAME" [status]="STATUS" [sys]="SYSTEM" [res]="RESOURCES" [ssh]="SSH")
    tw()   { local t=1 k; for k in "${act[@]}"; do t=$(( t + W[$k] + 3 )); done; echo "$t"; }
    has()  { local k; for k in "${act[@]}"; do [[ $k == "$1" ]] && return 0; done; return 1; }
    drop() { local k keep=(); for k in "${act[@]}"; do [[ $k == "$1" ]] || keep+=("$k"); done; act=("${keep[@]}"); }
    while (( $(tw) > avail )); do
        if   (( W[name] > 12 )); then W[name]=$(( W[name] - 2 ))
        elif has sys;            then drop sys
        elif (( W[name] > 8 ));  then W[name]=$(( W[name] - 2 ))
        elif has res;            then drop res
        elif has ssh;            then drop ssh
        elif (( W[name] > 5 ));  then W[name]=$(( W[name] - 1 ))
        else break; fi
    done
    # use spare room on wide terminals
    while (( $(tw) < avail && W[name] < 26 )); do W[name]=$(( W[name] + 1 )); done

    border() {
        local l=$1 m=$2 r=$3 k idx=0 last=$(( ${#act[@]} - 1 )) o="$1"
        for k in "${act[@]}"; do
            o+="$(rep '─' $(( W[$k] + 2 )))"
            if (( idx == last )); then o+="$r"; else o+="$m"; fi
            idx=$(( idx + 1 ))
        done
        printf '  %s%s%s\n' "$C_DIM" "$o" "$C_RST"
    }
    border '┌' '┬' '┐'; nap 0.015
    out="${C_DIM}│${C_RST}"
    for c in "${act[@]}"; do printf -v cell '%-*s' "${W[$c]}" "${H[$c]:0:${W[$c]}}"; out+=" ${C_ACC}${cell}${C_RST} ${C_DIM}│${C_RST}"; done
    printf '  %s\n' "$out"
    border '├' '┼' '┤'
    for (( i = 0; i < n; i++ )); do
        v=${VMS[i]}
        info=$( load_vm_config "$v" 2>/dev/null && echo "$MEMORY|$CPUS|$SSH_PORT|$OS_TYPE $CODENAME" )
        IFS='|' read -r mem cpus port os <<< "$info"
        if is_vm_running "$v"; then st="Running"; sc=$C_OK; else st="Stopped"; sc=$C_DIM; fi
        out="${C_DIM}│${C_RST}"
        for c in "${act[@]}"; do
            case $c in
                num)    printf -v cell '%-*s' "${W[num]}" "$(( i + 1 ))" ;;
                name)   printf -v cell '%-*s' "${W[name]}" "${v:0:${W[name]}}" ;;
                status) printf -v cell '%-*s' "$(( W[status] - 2 ))" "$st"; cell="${sc}●${C_RST}${C_TXT} ${cell}" ;;
                sys)    printf -v cell '%-*s' "${W[sys]}" "${os:0:${W[sys]}}" ;;
                res)    printf -v cell '%-*s' "${W[res]}" "${cpus}c / ${mem}M" ;;
                ssh)    printf -v cell '%-*s' "${W[ssh]}" "$port" ;;
            esac
            out+=" ${C_TXT}${cell}${C_RST} ${C_DIM}│${C_RST}"
        done
        printf '  %s\n' "$out"; nap 0.02
    done
    border '└' '┴' '┘'; echo
}

main_menu() {
    local choice
    while true; do
        header
        mapfile -t VMS < <(get_vm_list)
        vm_table
        section "Main menu"
        menu_item 1 "Create a new VM"
        if (( ${#VMS[@]} )); then
            menu_item 2 "Start a VM"
            menu_item 3 "Stop a VM"
            menu_item 4 "Show VM info"
            menu_item 5 "Edit VM configuration"
            menu_item 6 "Delete a VM"
            menu_item 7 "Resize VM disk"
            menu_item 8 "Live performance monitor"
        fi
        menu_item 0 "Exit"
        echo
        ask choice "Select an option" ""
        case $choice in
            1) create_new_vm ;;
            2) (( ${#VMS[@]} )) && pick_vm "VM number to start"    && start_vm "$PICKED" ;;
            3) (( ${#VMS[@]} )) && pick_vm "VM number to stop"     && stop_vm "$PICKED" ;;
            4) (( ${#VMS[@]} )) && pick_vm "VM number for info"    && show_vm_info "$PICKED" ;;
            5) (( ${#VMS[@]} )) && pick_vm "VM number to edit"     && edit_vm_config "$PICKED" ;;
            6) (( ${#VMS[@]} )) && pick_vm "VM number to delete"   && delete_vm "$PICKED" ;;
            7) (( ${#VMS[@]} )) && pick_vm "VM number to resize"   && resize_vm_disk "$PICKED" ;;
            8) (( ${#VMS[@]} )) && pick_vm "VM number to monitor"  && show_vm_performance "$PICKED" ;;
            0) echo; printf '  %s' "$C_ACC"; typewrite "Thank you for using $APP_BRAND." 0.02; printf '%s\n\n' "$C_RST"; exit 0 ;;
            *) print_status ERROR "Invalid option" ;;
        esac
        pause
    done
}

# ------------------------------------------------------------------------------
#  Entry point
# ------------------------------------------------------------------------------
check_dependencies
mkdir -p "$VM_DIR"

if (( ANIM )); then
    header 1
    progress_anim "Loading modules" 22
    progress_anim "Checking environment" 22
    printf '\n  %s' "$C_DIM"; typewrite "Welcome to $APP_BRAND · by ROOTSUNNY" 0.015; printf '%s\n' "$C_RST"
    sleep 0.5
fi

main_menu
