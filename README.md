# ROOTSUNNYLAB VM Manager — NOKVM

A full-featured, **animated** Bash control panel for creating and managing QEMU virtual machines from Linux cloud images. It runs entirely in the terminal: gradient logo, travelling shimmer, a live equalizer, arrow-key menus, an 11-step creation wizard, a real-time build stepper and coloured VM cards — with a fully static fallback for pipes, `NO_COLOR` and `--plain`.

> **See it in action:** open [`preview/index.html`](preview/index.html) in a browser. It is a real pseudo-terminal recording of `nokvm.sh`, not a mockup — with play/pause, scrubbing and speed controls.

```
╭──────────────────────────────────────────────────────────────────────────────╮
│  NOKVM  //  V M   C O N T R O L   C E N T E R                      v2.0.0  │
│  rootsunnylab  |  ● fabric online                                 10:42:07  │
╰──────────────────────────────────────────────────────────────────────────────╯
╭─ FLEET OVERVIEW  /  2 MACHINE(S) ───────────────────────────────────────────╮
│   01  lab-ci                [ STOPPED ]   debian bookworm                   │
│        RAM 4096 MB   CPU 4   DISK 40G   SSH 2223                             │
╰──────────────────────────────────────────────────────────────────────────────╯
╭─ MAIN MENU  /  CONTROL DECK ────────────────────────────────────────────────╮
│   >   1  [+]  Create a new VM                                               │
│        2  [>]  Start a VM                                                   │
│        3  [#]  Stop a VM                                                    │
│        4  [i]  Show VM information                                          │
│        ...                                                                  │
│    Oo:.oOO:.:OOo.:oOo:.   Up/Down + Enter  |  1-9 jump  |  0 / q exit        │
╰──────────────────────────────────────────────────────────────────────────────╯
```

## What's in the interface

- **Boot splash** — animated `NOKVM` pixel logo with a travelling gradient, a typewriter tagline and a dependency checklist that fills in live.
- **Living frame** — the header gradient, pulse dot, clock and ASCII equalizer keep moving even while you are deciding; every screen redraws in place without flicker.
- **Keyboard-driven menus** — Up/Down or `j`/`k`, Enter to select, `1`–`9` to jump, `0`/`q` to leave. Highlighted rows get a full-width colour wash.
- **Fleet dashboard** — VM cards with `[ RUNNING ]` / `[ STOPPED ]` badges, OS, RAM, CPU, disk and SSH port, plus a friendly empty state.
- **Creation wizard** — distro picker, progress bar, live summary of every field, inline validation errors, a review card and an animated 6-step build screen (download byte counter, spinner steps, progress bar).
- **Detail screens** — telemetry with CPU/memory bars, a red danger zone for deletion, a pre-flight launch countdown and a success banner.
- **Degrades gracefully** — no TTY, `NO_COLOR`, `--plain` and `--no-anim` all fall back to clean, scriptable text.

## Features

- Create VMs from Ubuntu 22.04/24.04, Debian 11/12, Fedora 40, CentOS Stream 9, AlmaLinux 9 and Rocky Linux 9.
- Configure guest hostname, username, password, RAM, CPU cores, virtual disk capacity, host SSH port, graphical display and extra TCP host-to-guest port forwards.
- Cloud-init first-boot provisioning; the created user's password is written as a SHA-512 hash in the `users:` block (the seed also carries a `chpasswd` block). VM config files are written with mode `0600` and hold the chosen password in plaintext, so keep `~/vms` private. The password is also shown on the VM details and pre-flight screens.
- Start VMs with QEMU; KVM acceleration when `/dev/kvm` is writable, software emulation (`qemu64`) otherwise. Non-graphical mode attaches QEMU's serial monitor (`Ctrl+A`, `X` to quit).
- Stop VMs gracefully (with a forced-kill fallback), view configuration and host-side process/memory/disk statistics.
- Edit settings, regenerate cloud-init credentials, grow virtual disks and delete VMs.
- Safer deletion confirmation and an explicit warning before shrinking a disk.
- Existing `~/vms/*.conf` files from earlier releases load unchanged.

## Requirements

Linux, Bash 4+, and:

| Tool | Used for |
| --- | --- |
| `qemu-system-x86_64` | running VMs |
| `qemu-img` | disk resize |
| `cloud-localds` | cloud-init seed ISO |
| `wget` | downloading cloud images |
| `openssl` | SHA-512 password hashing |

Optional: `ss` (host port conflict check), `numfmt` (human-readable download sizes), `tput`/`stty` (terminal size and keyboard setup).

On Ubuntu/Debian:

```bash
sudo apt update
sudo apt install qemu-system-x86 qemu-utils cloud-image-utils wget openssl coreutils
```

## Install and run

```bash
git clone https://github.com/ROOTSUNNYLAB1/ROOTSUNNYLAB-VM-Manager.git
cd ROOTSUNNYLAB-VM-Manager
chmod +x nokvm.sh
./nokvm.sh
```

### Keyboard

| Key | Action |
| --- | --- |
| `↑` / `↓` or `k` / `j` | move through a menu |
| `Enter` | select |
| `1`–`9`, `0` | jump to an option / exit |
| `q` | go back |

### Options and environment

| Flag / variable | Effect |
| --- | --- |
| `--plain` | classic numbered prompts, no screen redraws (good for pipes and logs) |
| `--no-anim` | keep colours, skip motion |
| `-h`, `--help` | usage |
| `-v`, `--version` | version |
| `VM_DIR` | VM store (default `~/vms`) |
| `NO_COLOR` | disable colours (Unicode frames remain) |
| `NOKVM_NO_ANIM=1` | same as `--no-anim` |
| `NOKVM_NO_INTRO=1` | skip the boot splash |

## SSH access

Use the host port and guest username chosen during creation, for example:

```bash
ssh -p 2222 ubuntu@127.0.0.1
```

## Notes

- Cloud images are downloaded directly from the listed distribution providers; the first VM creation can take a while.
- Disk growth changes the virtual disk capacity only — grow the partition and filesystem inside the guest separately. If the provider image refuses `qemu-img resize`, the original image size is kept and the build continues.
- Starting a VM hands the terminal to QEMU's serial monitor; the menu returns when QEMU exits.
- VM deletion is irreversible and removes the disk image, seed image and configuration.
- This is an independent community project, not affiliated with QEMU or the listed Linux distributions. Review scripts before running them on a host.

## Validation

The `Shell validation` GitHub Actions workflow runs `bash -n nokvm.sh` and `shellcheck -S error nokvm.sh` on pushes and pull requests to `main`. The current script is clean under ShellCheck with default severity.

## License

No license has been specified for this repository. All rights remain with their respective owners.
