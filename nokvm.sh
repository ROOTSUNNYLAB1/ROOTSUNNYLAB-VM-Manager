#!/usr/bin/env bash
# ROOTSUNNYLAB VM Manager — standalone QEMU cloud-image manager
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="3.0.0"
VM_DIR="${VM_DIR:-$HOME/.local/share/rootsunny-vm-manager/vms}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/rootsunny-vm-manager}"
declare -A OS=(
 ["Ubuntu 24.04"]="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu"
 ["Ubuntu 22.04"]="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu"
 ["Debian 12"]="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian"
 ["Debian 11"]="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian"
 ["Fedora 40"]="https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora"
 ["CentOS Stream 9"]="https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|cloud-user"
 ["AlmaLinux 9"]="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux"
 ["Rocky Linux 9"]="https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky"
)
info(){ printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
good(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
fail(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; }
pause(){ read -r -p "Press Enter to continue..." _ || true; }
header(){
 clear 2>/dev/null || true
 printf '\033[1;34m'
 cat <<'EOF'
  ____   ___   ___ _____ _   _ _   _ _   _ _   _
 |  _ \ / _ \ / _ \_   _| | | | \ | | \ | | \ | |
 | |_) | | | | | | || | | | | |  \| |  \| |  \| |
 |  _ <| |_| | |_| || | | |_| | |\  | |\  | |\  |
 |_| \_\\___/ \___/ |_|  \___/|_| \_|_| \_|_| \_|
EOF
 printf '\033[0m  ROOTSUNNYLAB  /  VM MANAGER  •  v%s\n\n' "$VERSION"
}
deps(){
 local x miss=()
 for x in qemu-system-x86_64 qemu-img cloud-localds wget openssl python3 numfmt; do command -v "$x" >/dev/null 2>&1 || miss+=("$x"); done
 if (("${#miss[@]}")); then
  fail "Missing: ${miss[*]}"
  info "Ubuntu/Debian: sudo apt install qemu-system-x86 qemu-utils cloud-image-utils wget openssl"
  exit 1
 fi
}
valid_name(){ [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,47}$ ]]; }
valid_user(){ [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
valid_size(){ [[ "$1" =~ ^[1-9][0-9]*[GgMm]$ ]]; }
port_free(){
 local p="$1"
 [[ "$p" =~ ^[0-9]+$ ]] && ((p>=1024 && p<=65535)) || return 1
 command -v ss >/dev/null 2>&1 || return 0
 ! ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\])${p}$"
}
cfg(){ printf '%s/%s.conf' "$VM_DIR" "$1"; }
disk(){ printf '%s/%s.qcow2' "$VM_DIR" "$1"; }
seed(){ printf '%s/%s-seed.iso' "$VM_DIR" "$1"; }
pidfile(){ printf '%s/%s.pid' "$STATE_DIR" "$1"; }
running(){
 local p; [[ -f "$(pidfile "$1")" ]] || return 1
 read -r p < "$(pidfile "$1")" || return 1
 [[ "$p" =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null && ps -p "$p" -o args= 2>/dev/null | grep -Fq -- "-name $1"
}
load(){
 valid_name "$1" || { fail "Invalid VM name."; return 1; }
 [[ -f "$(cfg "$1")" ]] || { fail "VM '$1' not found."; return 1; }
 # Configs are written by this script using printf %q.
 # shellcheck disable=SC1090
 source "$(cfg "$1")"
}
save(){
 local t; t="$(mktemp "$(cfg "$VM_NAME").XXXXXX")"
 {
  printf 'VM_NAME=%q\nOS_NAME=%q\nIMAGE_URL=%q\nHOSTNAME=%q\nUSERNAME=%q\n' "$VM_NAME" "$OS_NAME" "$IMAGE_URL" "$HOSTNAME" "$USERNAME"
  printf 'MEMORY=%q\nCPUS=%q\nDISK_SIZE=%q\nSSH_PORT=%q\nGUI_MODE=%q\nPORT_FORWARDS=%q\nCREATED=%q\n' "$MEMORY" "$CPUS" "$DISK_SIZE" "$SSH_PORT" "$GUI_MODE" "$PORT_FORWARDS" "$CREATED"
 } > "$t"
 chmod 600 "$t"; mv "$t" "$(cfg "$VM_NAME")"
}
forwards_ok(){
 local pair h g
 [[ -z "$1" ]] && return 0
 IFS=',' read -ra items <<< "$1"
 for pair in "${items[@]}"; do
  [[ "$pair" == *:* ]] || return 1
  h="${pair%%:*}"; g="${pair##*:}"
  [[ "$h" =~ ^[0-9]+$ && "$g" =~ ^[0-9]+$ ]] || return 1
  ((h>=1024 && h<=65535 && g>=1 && g<=65535)) || return 1
  port_free "$h" || return 1
 done
}
make_seed(){
 local n="$1" hash="$2" tmp
 tmp="$(mktemp -d)"
 cat > "$tmp/user-data" <<EOF
#cloud-config
hostname: $HOSTNAME
manage_etc_hosts: true
ssh_pwauth: true
users:
  - default
  - name: $USERNAME
    groups: [sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: '$hash'
chpasswd:
  expire: false
EOF
 printf 'instance-id: iid-%s\nlocal-hostname: %s\n' "$n" "$HOSTNAME" > "$tmp/meta-data"
 cloud-localds "$(seed "$n")" "$tmp/user-data" "$tmp/meta-data"
 chmod 600 "$(seed "$n")"
 rm -rf "$tmp"
}
create_vm(){
 header; echo "Operating systems:"
 local -a names=(); local x n default password hash
 while IFS= read -r x; do names+=("$x"); done < <(printf '%s\n' "${!OS[@]}" | sort)
 for x in "${!names[@]}"; do printf ' %d) %s\n' "$((x+1))" "${names[$x]}"; done
 read -r -p "OS [1]: " n; n="${n:-1}"
 [[ "$n" =~ ^[0-9]+$ ]] && ((n>=1 && n<=${#names[@]})) || { fail "Invalid OS choice."; return; }
 OS_NAME="${names[$((n-1))]}"; IFS='|' read -r IMAGE_URL default <<< "${OS[$OS_NAME]}"
 read -r -p "VM name [$default]: " VM_NAME; VM_NAME="${VM_NAME:-$default}"
 valid_name "$VM_NAME" || { fail "Invalid VM name."; return; }
 [[ ! -e "$(cfg "$VM_NAME")" ]] || { fail "VM already exists."; return; }
 read -r -p "Hostname [$VM_NAME]: " HOSTNAME; HOSTNAME="${HOSTNAME:-$VM_NAME}"
 valid_name "$HOSTNAME" || { fail "Invalid hostname."; return; }
 read -r -p "Username [$default]: " USERNAME; USERNAME="${USERNAME:-$default}"
 valid_user "$USERNAME" || { fail "Invalid username."; return; }
 read -r -s -p "Password (hidden): " password; echo
 [[ -n "$password" ]] || { fail "Password cannot be empty."; return; }
 read -r -p "RAM MB [2048]: " MEMORY; MEMORY="${MEMORY:-2048}"
 [[ "$MEMORY" =~ ^[1-9][0-9]*$ ]] || { fail "RAM must be a positive number."; return; }
 read -r -p "CPU cores [2]: " CPUS; CPUS="${CPUS:-2}"
 [[ "$CPUS" =~ ^[1-9][0-9]*$ ]] || { fail "CPU count must be a positive number."; return; }
 read -r -p "Disk size [20G]: " DISK_SIZE; DISK_SIZE="${DISK_SIZE:-20G}"
 valid_size "$DISK_SIZE" || { fail "Use e.g. 20G or 512M."; return; }
 read -r -p "Host SSH port [2222]: " SSH_PORT; SSH_PORT="${SSH_PORT:-2222}"
 port_free "$SSH_PORT" || { fail "SSH port unavailable or invalid (1024-65535)."; return; }
 read -r -p "Enable GUI? [y/N]: " answer; GUI_MODE=false; [[ "$answer" =~ ^[Yy]$ ]] && GUI_MODE=true
 read -r -p "Extra TCP forwards host:guest, comma-separated [none]: " PORT_FORWARDS
 forwards_ok "$PORT_FORWARDS" || { fail "Invalid or busy forwarded host port."; return; }
 CREATED="$(date -Is)"
 mkdir -p "$VM_DIR" "$STATE_DIR"; chmod 700 "$VM_DIR" "$STATE_DIR"
 if [[ ! -s "$(disk "$VM_NAME")" ]]; then
  info "Downloading $OS_NAME image..."
  wget --https-only --show-progress -O "$(disk "$VM_NAME").part" "$IMAGE_URL" || { rm -f "$(disk "$VM_NAME").part"; fail "Download failed."; return; }
  qemu-img info "$(disk "$VM_NAME").part" >/dev/null || { rm -f "$(disk "$VM_NAME").part"; fail "Invalid downloaded image."; return; }
  mv "$(disk "$VM_NAME").part" "$(disk "$VM_NAME")"
 fi
 qemu-img resize "$(disk "$VM_NAME")" "$DISK_SIZE"
 hash="$(openssl passwd -6 "$password")"; unset password
 make_seed "$VM_NAME" "$hash"; unset hash
 save; good "VM '$VM_NAME' created successfully."
}
start_vm(){
 local name="$1" net="user,id=net0" pair h g pid
 load "$name" || return
 running "$name" && { warn "Already running."; return; }
 [[ -s "$(disk "$name")" && -s "$(seed "$name")" ]] || { fail "Disk or cloud-init seed missing."; return; }
 port_free "$SSH_PORT" || { fail "SSH port $SSH_PORT is unavailable."; return; }
 if [[ -n "$PORT_FORWARDS" ]]; then
  IFS=',' read -ra items <<< "$PORT_FORWARDS"
  for pair in "${items[@]}"; do h="${pair%%:*}"; g="${pair##*:}"; net+=",hostfwd=tcp::$h-:$g"; done
 fi
 net+=",hostfwd=tcp::$SSH_PORT-:22"
 local -a cmd=(qemu-system-x86_64 -name "$name" -m "$MEMORY" -smp "$CPUS"
  -drive "file=$(disk "$name"),if=virtio,format=qcow2"
  -drive "file=$(seed "$name"),if=virtio,format=raw"
  -device virtio-net-pci,netdev=net0 -netdev "$net"
  -device virtio-balloon-pci -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0
  -daemonize -pidfile "$(pidfile "$name")" -D "$STATE_DIR/$name.log")
 if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then cmd+=(-enable-kvm -cpu host); fi
 if [[ "$GUI_MODE" == true ]]; then cmd+=(-vga virtio); else cmd+=(-display none -serial none -monitor none); fi
 "${cmd[@]}" || { fail "QEMU failed. See $STATE_DIR/$name.log"; return 1; }
 sleep 1
 running "$name" || { fail "QEMU did not remain running. See $STATE_DIR/$name.log"; return 1; }
 good "Started $name. SSH: ssh -p $SSH_PORT $USERNAME@127.0.0.1"
}
stop_vm(){
 local name="$1" p
 load "$name" || return
 running "$name" || { warn "VM is not running."; rm -f "$(pidfile "$name")"; return; }
 read -r p < "$(pidfile "$name")"
 kill -TERM "$p" 2>/dev/null || true
 for _ in {1..10}; do kill -0 "$p" 2>/dev/null || break; sleep 1; done
 kill -0 "$p" 2>/dev/null && { warn "Graceful stop timed out; forcing stop."; kill -KILL "$p" 2>/dev/null || true; }
 rm -f "$(pidfile "$name")"; good "Stopped $name."
}
list_vms(){ find "$VM_DIR" -maxdepth 1 -type f -name '*.conf' -printf '%f\n' 2>/dev/null | sed 's/\.conf$//' | sort; }
select_vm(){
 local action="$1" n; local -a vms=()
 mapfile -t vms < <(list_vms)
 (("${#vms[@]}")) || { info "No VMs found."; pause; return; }
 local i; for i in "${!vms[@]}"; do printf ' %d) %s [%s]\n' "$((i+1))" "${vms[$i]}" "$(running "${vms[$i]}" && echo running || echo stopped)"; done
 read -r -p "VM number: " n
 [[ "$n" =~ ^[0-9]+$ ]] && ((n>=1 && n<=${#vms[@]})) || { fail "Invalid selection."; pause; return; }
 local name="${vms[$((n-1))]}"
 case "$action" in
  start) start_vm "$name";;
  stop) stop_vm "$name";;
  info) show_info "$name";;
  edit) edit_vm_config "$name";;
  performance) show_vm_performance "$name";;
  resize) resize_vm "$name";;
  delete) delete_vm "$name";;
 esac
 pause
}
show_info(){
 load "$1" || return
 printf '\nName: %s\nOS: %s\nHostname: %s\nUsername: %s\nRAM: %s MB\nCPUs: %s\nDisk: %s\nSSH port: %s\nGUI: %s\nExtra forwards: %s\nCreated: %s\nStatus: %s\nDisk image: %s\nLog: %s\n\n' "$VM_NAME" "$OS_NAME" "$HOSTNAME" "$USERNAME" "$MEMORY" "$CPUS" "$DISK_SIZE" "$SSH_PORT" "$GUI_MODE" "${PORT_FORWARDS:-none}" "$CREATED" "$(running "$VM_NAME" && echo Running || echo Stopped)" "$(disk "$VM_NAME")" "$STATE_DIR/$VM_NAME.log"
}
resize_vm(){
 load "$1" || return
 running "$VM_NAME" && { fail "Stop VM before resizing."; return; }
 read -r -p "New disk size (current $DISK_SIZE): " size
 valid_size "$size" || { fail "Invalid size."; return; }
 local old_bytes new_bytes
 old_bytes="$(qemu-img info --output=json "$(disk "$VM_NAME")" | python3 -c 'import json,sys;print(json.load(sys.stdin)["virtual-size"])')" || return
 new_bytes="$(numfmt --from=auto "$size" 2>/dev/null)" || { fail "Could not parse disk size."; return; }
 ((new_bytes >= old_bytes)) || { fail "Disk shrinking is disabled to protect VM data. Only expansion is supported."; return; }
 qemu-img resize "$(disk "$VM_NAME")" "$size" && { DISK_SIZE="$size"; save; good "Disk expanded. Grow the guest filesystem separately if needed."; }
}
delete_vm(){
 load "$1" || return
 running "$VM_NAME" && { fail "Stop VM before deleting."; return; }
 warn "This permanently removes the VM disk and configuration."
 read -r -p "Type DELETE to confirm: " answer
 [[ "$answer" == DELETE ]] || { info "Cancelled."; return; }
 rm -f "$(disk "$VM_NAME")" "$(seed "$VM_NAME")" "$(cfg "$VM_NAME")" "$STATE_DIR/$VM_NAME.log" "$(pidfile "$VM_NAME")"
 good "Deleted $VM_NAME."
}
edit_vm_config(){
 local name="$1" choice value password hash="" refresh_seed=false
 load "$name" || return
 while true; do
  header
  printf '  EDIT VM CONFIGURATION — %s\n\n' "$name"
  cat <<'EOF'
  1) Hostname
  2) Username
  3) Password
  4) SSH port
  5) GUI mode
  6) Port forwards
  7) RAM
  8) CPU cores
  9) Save changes
  0) Cancel
EOF
  read -r -p "  Select: " choice || return
  case "$choice" in
   1) read -r -p "  New hostname [$HOSTNAME]: " value; value="${value:-$HOSTNAME}"; valid_name "$value" || { fail "Invalid hostname."; pause; continue; }; HOSTNAME="$value"; refresh_seed=true;;
   2) read -r -p "  New username [$USERNAME]: " value; value="${value:-$USERNAME}"; valid_user "$value" || { fail "Invalid username."; pause; continue; }; USERNAME="$value"; refresh_seed=true;;
   3) read -r -s -p "  New password (hidden): " password; echo; [[ -n "$password" ]] || { fail "Password cannot be empty."; pause; continue; }; hash="$(openssl passwd -6 "$password")"; unset password; refresh_seed=true;;
   4) read -r -p "  New SSH port [$SSH_PORT]: " value; value="${value:-$SSH_PORT}"; port_free "$value" || { fail "Port unavailable or invalid."; pause; continue; }; SSH_PORT="$value";;
   5) read -r -p "  Enable GUI? (y/N): " value; GUI_MODE=false; [[ "$value" =~ ^[Yy]$ ]] && GUI_MODE=true;;
   6) read -r -p "  Extra forwards host:guest: " value; forwards_ok "$value" || { fail "Invalid or busy port forward."; pause; continue; }; PORT_FORWARDS="$value";;
   7) read -r -p "  RAM MB [$MEMORY]: " value; value="${value:-$MEMORY}"; [[ "$value" =~ ^[1-9][0-9]*$ ]] || { fail "Invalid RAM value."; pause; continue; }; MEMORY="$value";;
   8) read -r -p "  CPU cores [$CPUS]: " value; value="${value:-$CPUS}"; [[ "$value" =~ ^[1-9][0-9]*$ ]] || { fail "Invalid CPU count."; pause; continue; }; CPUS="$value";;
   9)
    if [[ "$refresh_seed" == true ]]; then
     if [[ -z "$hash" ]]; then
      read -r -s -p "  Re-enter guest password to rebuild cloud-init (hidden): " password; echo
      [[ -n "$password" ]] || { fail "Password required to update cloud-init."; pause; continue; }
      hash="$(openssl passwd -6 "$password")"; unset password
     fi
     make_seed "$name" "$hash" || { pause; continue; }
    fi
    save; good "VM configuration saved."; return;;
   0) warn "Changes discarded."; return;;
   *) warn "Invalid option.";;
  esac
 done
}

show_vm_performance(){
 local name="$1" pid
 load "$name" || return
 echo
 echo "PERFORMANCE MONITOR — $name"
 echo "------------------------------------------------------------"
 if running "$name"; then
  read -r pid < "$(pidfile "$name")"
  echo "QEMU process:"
  ps -p "$pid" -o pid=,pcpu=,pmem=,rss=,etime=,stat=,comm=
  echo
  echo "Host memory:"
  free -h
  echo
  echo "VM disk file:"
  du -h "$(disk "$name")"
  echo
  echo "QEMU command:"
  ps -p "$pid" -o args=
 else
  info "VM is stopped."
  printf 'Configured RAM: %s MB | CPUs: %s | Disk: %s\n' "$MEMORY" "$CPUS" "$DISK_SIZE"
 fi
 echo "------------------------------------------------------------"
}

main(){
 deps; mkdir -p "$VM_DIR" "$STATE_DIR"; chmod 700 "$VM_DIR" "$STATE_DIR"
 while true; do
  header; echo "Configured VMs:"
  local found=0 name
  while IFS= read -r name; do [[ -n "$name" ]] || continue; found=1; printf ' • %-22s %s\n' "$name" "$(running "$name" && echo Running || echo Stopped)"; done < <(list_vms)
  ((found)) || echo " (none)"
  cat <<'EOF'

  1) Create VM
  2) Start VM
  3) Stop VM
  4) VM information
  5) Edit VM configuration
  6) Delete VM
  7) Resize disk
  8) Show VM performance
  0) Exit
EOF
  read -r -p "Select: " choice || break
  case "$choice" in
   1) create_vm; pause;;
   2) select_vm start;;
   3) select_vm stop;;
   4) select_vm info;;
   5) select_vm edit;;
   6) select_vm delete;;
   7) select_vm resize;;
   8) select_vm performance;;
   0) info "Goodbye."; break;;
   *) warn "Invalid option."; sleep 1;;
  esac
 done
}
main "$@"
