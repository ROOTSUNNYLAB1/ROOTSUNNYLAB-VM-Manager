# ROOTSUNNYLAB VM Manager

A standalone Bash-based menu for managing Linux cloud-image virtual machines with QEMU.

## Features

- Create VMs from Ubuntu 22.04/24.04, Debian 11/12, AlmaLinux 9 and Rocky Linux 9 cloud images.
- Configure hostname, Linux username, password, RAM, CPU cores, disk size and host SSH port.
- Optional graphical display and additional TCP port forwarding.
- Start, stop, inspect, resize and delete virtual machines.
- Uses cloud-init for first-boot provisioning.
- Stores VM data under the user's home directory with restrictive permissions.
- Uses KVM acceleration when /dev/kvm is accessible; otherwise runs without KVM.

## Requirements

Linux, Bash, QEMU, qemu-img, cloud-localds, wget and OpenSSL.

On Ubuntu/Debian:

```bash
sudo apt update
sudo apt install qemu-system-x86 qemu-utils cloud-image-utils wget openssl
```

## Install and run

```bash
git clone https://github.com/ROOTSUNNYLAB1/ROOTSUNNYLAB-VM-Manager.git
cd ROOTSUNNYLAB-VM-Manager
chmod +x nokvm.sh
./nokvm.sh
```

## Storage locations

- VM disks, cloud-init seed images and configuration: `~/.local/share/rootsunny-vm-manager/vms`
- QEMU PID files and logs: `~/.local/state/rootsunny-vm-manager`

You can override these paths with `VM_DIR` and `STATE_DIR`.

## Connect over SSH

Use the host port and username configured during VM creation. For example:

```bash
ssh -p 2222 ubuntu@127.0.0.1
```

## Important notes

- VM disk resizing changes the virtual disk capacity. You may also need to grow the partition and filesystem inside the guest.
- Deleting a VM removes its virtual disk and is irreversible.
- Cloud images are downloaded from their respective project providers. Only use trusted sources.
- This is an unofficial independent rewrite based on the supplied earlier VM-manager script. It is not affiliated with QEMU or the Linux distributions listed above.
- Review scripts before running them on a host.

## License

No license has been specified for this repository. All rights remain with their respective owners.
