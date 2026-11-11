# ROOTSUNNYLAB VM Manager

A ROOTSUNNYLAB-branded launcher for the upstream VM management script.

## Features

- Clean, colorful terminal header with a dark-terminal-friendly ANSI palette.
- Fetches the upstream VM manager at launch time.
- Applies ROOTSUNNYLAB branding to the display header before starting it.
- Keeps the original project's attribution visible.

## Requirements

- Bash
- curl
- Python 3

## Run

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ROOTSUNNYLAB1/ROOTSUNNYLAB-VM-Manager/main/nokvm.sh)
```

Or clone this repository and run:

```bash
chmod +x nokvm.sh
./nokvm.sh
```

## Important notes

This repository currently provides a **launcher/customization**, not an independently maintained fork of the upstream VM manager. It downloads the upstream script from:

https://github.com/hopingboyz/vms

The launcher expects the upstream script to contain the documented header-function markers. If the upstream layout changes, the branding step will stop with an error rather than silently modifying an unexpected section.

Review the upstream script before running it, especially because VM-management scripts can make system-level changes.

## Credits and attribution

- Original project and VM-management implementation: [hopingboyz/vms](https://github.com/hopingboyz/vms)
- ROOTSUNNYLAB edition: terminal branding and launcher customization by ROOTSUNNYLAB.

This project is an unofficial community customization and is not presented as the original author's work. Please follow the upstream project's license and attribution requirements.
