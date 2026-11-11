# ROOTSUNNYLAB VM Manager

A full-featured, interactive Bash control panel for creating and managing QEMU virtual machines from Linux cloud images. Built for a clean terminal experience with a restrained blue/slate interface.

## Features

- Create VMs from Ubuntu 22.04/24.04, Debian 11/12, Fedora 40, CentOS Stream 9, AlmaLinux 9 and Rocky Linux 9.
- Configure guest hostname, username, password, RAM, CPU cores, virtual disk capacity and host SSH port.
- Cloud-init first-boot provisioning with password hashes; plaintext passwords are not written to VM configuration files.
- Start and stop VMs in the background with per-VM PID and log files.
- Optional graphical display and multiple TCP host-to-guest port forwards.
- View VM configuration and live host-side process, memory and disk statistics.
- Edit VM settings, regenerate cloud-init credentials, expand virtual disks and delete VMs.
- KVM acceleration when /dev/kvm is accessible; software emulation fallback otherwise.
- Safer deletion confirmation and disk expansion only (shrinking is intentionally disabled to protect data).

## Requirements

Linux, Bash 4+, QEMU, qemu-img, cloud-localds, wget, OpenSSL, Python 3 and GNU numfmt.

On Ubuntu/Debian:

```bash
sudo apt update
sudo apt install qemu-system-x86 qemu-utils cloud-image-utils wget openssl python3 coreutils
```

## Install and run

```bash
git clone https://github.com/ROOTSUNNYLAB1/ROOTSUNNYLAB-VM-Manager.git
cd ROOTSUNNYLAB-VM-Manager
chmod +x nokvm.sh
./nokvm.sh
```

## SSH access

Use the host port and guest username selected during VM creation. For example:

```bash
ssh -p 2222 ubuntu@127.0.0.1
```

## Notes

- Disk expansion changes the virtual disk capacity; grow the partition and filesystem inside the guest separately when needed.
- VM deletion is irreversible and removes its disk image, seed image, configuration and log.
- Cloud images are downloaded directly from the listed distribution providers.
- This is an independent community project, not affiliated with QEMU or the listed Linux distributions.
- Review scripts before running them on a host.

## License

No license has been specified for this repository. All rights remain with their respective owners.
