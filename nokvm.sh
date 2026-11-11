#!/usr/bin/env bash
set -euo pipefail

# ROOTSUNNYLAB Edition launcher
# Original project: hopingboyz/vms (nokvm.sh)
# Downloads the upstream script, changes only its display header, then runs it.

UPSTREAM_URL="https://raw.githubusercontent.com/hopingboyz/vms/main/nokvm.sh"
WORK_FILE="$(mktemp "${TMPDIR:-/tmp}/rootsunny-vm.XXXXXX.sh")"
trap 'rm -f "$WORK_FILE"' EXIT

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required."; exit 1; }

echo -e "\033[1;96m[ROOTSUNNYLAB]\033[0m Fetching original VM manager..."
curl -fsSL "$UPSTREAM_URL" -o "$WORK_FILE"

python3 - "$WORK_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
source = path.read_text()

pattern = re.compile(
    r'(?ms)^# Function to display header\n'
    r'display_header\(\) \{\n.*?^\}\n'
    r'(?=# Function to display colored output)'
)

replacement = r'''# Function to display header
display_header() {
    clear
    local c1='\033[1;96m'
    local c2='\033[1;94m'
    local c3='\033[1;95m'
    local gold='\033[1;93m'
    local white='\033[1;97m'
    local reset='\033[0m'

    echo -e "${c1}╔══════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${c1}║${c2}  ██████╗  ██████╗  ██████╗ ████████╗███████╗██╗   ██╗███╗   ██╗${c1}      ║${reset}"
    echo -e "${c1}║${c2}  ██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝██╔════╝╚██╗ ██╔╝████╗  ██║${c1}      ║${reset}"
    echo -e "${c1}║${c3}  ██████╔╝██║   ██║██║   ██║   ██║   ███████╗ ╚████╔╝ ██╔██╗ ██║${c1}      ║${reset}"
    echo -e "${c1}║${c3}  ██╔══██╗██║   ██║██║   ██║   ██║   ╚════██║  ╚██╔╝  ██║╚██╗██║${c1}      ║${reset}"
    echo -e "${c1}║${c2}  ██║  ██║╚██████╔╝╚██████╔╝   ██║   ███████║   ██║   ██║ ╚████║${c1}      ║${reset}"
    echo -e "${c1}║${c2}  ╚═╝  ╚═╝ ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝   ╚═╝   ╚═╝  ╚═══╝${c1}      ║${reset}"
    echo -e "${c1}║                                                                      ║${reset}"
    echo -e "${c1}║${white}                    VM MANAGEMENT CONSOLE                             ${c1}║${reset}"
    echo -e "${c1}║${gold}              ✦ POWERED BY ROOTSUNNYLAB ✦                              ${c1}║${reset}"
    echo -e "${c1}║${white}           Original project credits: HOPINGBOYZ                        ${c1}║${reset}"
    echo -e "${c1}╚══════════════════════════════════════════════════════════════════════╝${reset}"
    echo
}
'''
source, count = pattern.subn(replacement, source, count=1)
if count != 1:
    raise SystemExit("Expected upstream header not found; refusing to modify the script.")
path.write_text(source)
PY

echo -e "\033[1;92m[OK]\033[0m ROOTSUNNYLAB branding applied. Starting VM Manager..."
bash "$WORK_FILE"
