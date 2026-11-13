<div align="center">

# ROOTSUNNYLAB Virtual Machine Manager

**A single-file, terminal-based multi-VM manager built on QEMU and cloud-init.**
Create, run and manage Linux virtual machines from one clean, animated, auto-fitting terminal UI.

`Bash` · `QEMU` · `cloud-init` · `No other dependencies`

*Powered by ROOTSUNNY*

</div>

---

## Features

- **One script, no framework.** Everything lives in `rsl-vm-manager.sh`.
- **18 ready-made systems.** Ubuntu, Debian, Fedora, CentOS Stream, AlmaLinux, Rocky Linux, Arch, openSUSE and Proxmox VE.
- **Console in the same terminal.** The VM's serial console opens right where you are. No extra window pops up.
- **Smart acceleration.** Uses KVM when it really works, otherwise falls back to software mode (NO KVM). If KVM is present but fails at start, it retries automatically without KVM.
- **Auto-fit interface.** The banner, VM table, bars and menus adapt to your terminal size, and the banner is centered.
- **Classic professional look.** Muted palette (no neon), animated banner shimmer, loading bars, spinners and a live performance monitor.
- **Cloud-init provisioning.** Hostname, user and password are set up on first boot. You can also install packages and run a startup script automatically.
- **Fast networking.** Modern virtio-net NIC with IPv6 turned off in the user network, plus a tuned software (TCG) mode when KVM is not available.
- **Safe handling of your VMs.** Disks are grow-only, config files are private (`chmod 600`), and a VM must be stopped before its disk is resized.
- **Image cache.** Each base image is downloaded once and reused for every new VM.

## Supported systems

| # | System | Type |
|---|--------|------|
| 1 | Ubuntu 20.04 | cloud image |
| 2 | Ubuntu 22.04 | cloud image |
| 3 | Ubuntu 24.04 | cloud image |
| 4 | Ubuntu 25.04 | cloud image |
| 5 | Ubuntu 26.04 | cloud image |
| 6 | Debian 11 | cloud image |
| 7 | Debian 12 | cloud image |
| 8 | Debian 13 | cloud image |
| 9 | Fedora 40 | cloud image |
| 10 | CentOS Stream 9 | cloud image |
| 11 | AlmaLinux 8 | cloud image |
| 12 | AlmaLinux 9 | cloud image |
| 13 | Rocky Linux 8 | cloud image |
| 14 | Rocky Linux 9 | cloud image |
| 15 | Arch Linux | cloud image |
| 16 | openSUSE Leap 15.6 | cloud image |
| 17 | openSUSE Tumbleweed | cloud image |
| 18 | Proxmox VE | installer ISO (latest ISO is detected automatically) |

> Image links are taken from each distribution's official download servers. If a distribution moves or renames a file, the download fails with a clear message. Update the matching line in the `OS_OPTIONS` block at the top of the script.

## Requirements

A Linux host with a Bash shell and these tools:

| Tool | Purpose |
|------|---------|
| `qemu-system-x86_64`, `qemu-img` | run and manage the VMs |
| `cloud-localds` | build the cloud-init seed image |
| `wget` | download base images |
| `openssl` | hash the VM password |

**Debian / Ubuntu**

```bash
sudo apt install qemu-system-x86 qemu-utils cloud-image-utils wget openssl
```

For hardware acceleration the user running the script needs read/write access to `/dev/kvm`. This is optional. Without it everything still works, only slower.

## Installation

```bash
git clone https://github.com/ROOTSUNNYLAB1/ROOTSUNNYLAB-VM-Manager.git
cd ROOTSUNNYLAB-VM-Manager
chmod +x rsl-vm-manager.sh
./rsl-vm-manager.sh
```

## Usage

Run the script and pick an option from the menu:

| Option | What it does |
|--------|--------------|
| **Create a new VM** | Choose a system, set name, hostname, user, password, disk, RAM, CPUs, SSH port, extra port forwards, and optional packages and startup script |
| **Start a VM** | Boots the VM and attaches its console to your terminal |
| **Stop a VM** | Clean shutdown, with a forced stop if it does not respond |
| **Show VM info** | Status, OS, resources, ports, files |
| **Edit VM configuration** | Hostname, user, password, SSH port, port forwards, RAM, CPUs, disk size, packages, startup script |
| **Delete a VM** | Removes the VM and all its data (asks for confirmation) |
| **Resize VM disk** | Grow the disk of a stopped VM |
| **Live performance monitor** | Real-time CPU and RAM bars. Press `q` to return |

### Leaving the VM console

Press **Ctrl+A**, then **X**. The terminal is restored automatically.

### Logging in

- **SSH:** `ssh -p <SSH_PORT> <user>@localhost` (the default SSH port is `2222`).
- **Console:** log in with the username and password you chose.
- Default users and passwords come from the system you pick (for example `ubuntu` / `ubuntu`, `debian` / `debian`). **Change them when you create the VM.**

### Port forwarding

At creation (or later through the edit menu) you can forward extra ports as `host:guest` pairs, separated by commas:

```
8080:80,8443:443
```

### Cloud-init extras (password login)

When you create a cloud-image VM you can optionally add:

- **Packages to install**, for example `htop git curl`.
- **A startup script**, either a path to a script file or a one-line command such as `apt install -y nginx`.

Both run once on the first boot. Login uses the username and password you set (no SSH key needed). If something fails, check `/var/log/cloud-init-output.log` inside the VM. Package names differ between distributions.

### Proxmox VE

Proxmox is installed from its ISO, so it works a little differently:

1. Create the VM. Defaults are 4096 MB RAM, 32G disk and port `8006` forwarded.
2. On start, answer **y** to "Boot the installer ISO?".
3. In the installer menu choose **Install Proxmox VE (Terminal UI, Serial Console)**.
4. After installing, start the VM again and answer **n** to boot from the disk.
5. Open the web interface at `https://localhost:8006`.

KVM is strongly recommended for Proxmox. Without it the system is very slow.

## Configuration

Everything is optional and set through environment variables:

| Variable | Default | Meaning |
|----------|---------|---------|
| `VM_DIR` | `~/vms` | Where VM disks, configs and the image cache are stored |
| `NO_ANIM=1` | off | Disable animations |
| `NO_COLOR=1` | off | Disable colors |
| `RSL_GUI=1` | off | Open a separate QEMU window instead of the terminal console |

Example:

```bash
VM_DIR=/data/vms NO_ANIM=1 ./rsl-vm-manager.sh
```

### Files

```
$VM_DIR/
├── <name>.conf        VM settings (private, mode 600)
├── <name>.img         VM disk (qcow2)
├── <name>-seed.iso    cloud-init seed
├── <name>.pid         present while the VM runs
└── .cache/            downloaded base images / ISOs
```

> The `.conf` file stores the VM password in plain text, so keep `VM_DIR` private.

## Troubleshooting

| Problem | What to check |
|---------|---------------|
| `Missing dependencies` | Install the packages listed in [Requirements](#requirements) |
| VM feels slow | Look at the "Acceleration" line at start. **NO KVM** means software mode. Check access to `/dev/kvm` |
| `Failed to download` | The image link may have changed. Update its URL in `OS_OPTIONS` |
| SSH port already in use | Pick another SSH port when creating or editing the VM |
| Terminal looks odd after a crash | Run `stty sane` or `reset` |
| Banner or table wraps | Widen the terminal. The layout re-fits on the next screen |

## Contributing

Issues and pull requests are welcome. To add another system, add a line to `OS_ORDER` and a matching entry in `OS_OPTIONS`:

```
type|codename|image-url|default-hostname|default-user|default-password
```

## Credits

Built by **ROOTSUNNYLAB**. Powered by **ROOTSUNNY**.
