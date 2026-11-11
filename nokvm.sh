#!/usr/bin/env bash
# =============================================================================
#   NOKVM  -  ROOTSUNNYLAB VM Manager
#   An animated, keyboard-driven terminal control center for QEMU cloud VMs.
#
#   The VM logic (config files, cloud-init, QEMU command line) is deliberately
#   kept compatible with earlier releases: existing ~/vms/*.conf files load
#   unchanged. Everything around it is a fresh coat of paint and motion.
# =============================================================================
set -euo pipefail

VERSION="2.0.0"

# -----------------------------------------------------------------------------
# 0. Command line
# -----------------------------------------------------------------------------
FORCE_PLAIN=0
FORCE_NO_ANIM=0
for _arg in "$@"; do
    case "$_arg" in
        --plain)      FORCE_PLAIN=1 ;;
        --no-anim)    FORCE_NO_ANIM=1 ;;
        -h|--help)    SHOW_HELP=1 ;;
        -v|--version) printf 'NOKVM %s - ROOTSUNNYLAB VM Manager\n' "$VERSION"; exit 0 ;;
        *) printf 'Unknown option: %s (try --help)\n' "$_arg" >&2; exit 2 ;;
    esac
done

usage() {
    cat <<'EOF'
NOKVM - ROOTSUNNYLAB VM Manager (animated terminal UI)

Usage:  ./nokvm.sh [options]

Options:
  --plain      Classic numbered prompts, no screen redraws (pipes / tmux logs)
  --no-anim    Keep the colours, skip the motion
  -h, --help   Show this help
  -v, --version

Environment:
  VM_DIR            Where VM configs and disks live (default: ~/vms)
  NO_COLOR          Disable all colours
  NOKVM_NO_ANIM=1   Same as --no-anim
  NOKVM_NO_INTRO=1  Skip the boot splash

Keyboard (interactive mode):
  Up/Down or j/k   Move through a menu
  Enter            Select
  1..9 / 0         Jump straight to an option
  q                Go back
EOF
    exit 0
}
if [[ ${SHOW_HELP:-0} -eq 1 ]]; then usage; fi

# -----------------------------------------------------------------------------
# 1. Terminal capabilities + palette
# -----------------------------------------------------------------------------
IS_TTY=0
PLAIN=0
ANIM=1
COLOR=1
TRUECOLOR=0
UTF8=1
FANCY=0
W=80
FRAME=0
BG_PID=""
SAVED_STTY=""
TMP_DIR=""
PRE_HOOK=""
CHOSEN=-1
PICKED_VM=""
VALIDATION_MSG=""
BUILD_NOTE=""
BUILD_TITLE="CREATING"
WIZ_STEP=1
WIZ_TOTAL=11
WIZ_ERROR=""

ui_init() {
    if [[ -t 0 && -t 1 && -n ${TERM:-} && ${TERM:-} != dumb ]]; then IS_TTY=1; fi
    if [[ $FORCE_PLAIN -eq 1 || $IS_TTY -eq 0 ]]; then PLAIN=1; fi
    if [[ -n ${NO_COLOR:-} || ${CLICOLOR:-1} == 0 || ${TERM:-} == dumb || $IS_TTY -eq 0 ]]; then COLOR=0; fi
    if [[ $FORCE_NO_ANIM -eq 1 || ${NOKVM_NO_ANIM:-0} == 1 || $IS_TTY -eq 0 || $PLAIN -eq 1 ]]; then ANIM=0; fi
    if [[ ${COLORTERM:-} =~ truecolor|24bit || ${TERM:-} =~ 256color ]]; then TRUECOLOR=1; fi

    # UTF-8 is needed for the box drawing glyphs. Coerce LC_CTYPE only when the
    # current locale cannot represent them, and only if C.UTF-8 is available.
    if ! locale charmap 2>/dev/null | grep -qiE 'utf-?8'; then
        if locale -a 2>/dev/null | grep -qiE '^C\.(utf8|UTF-8)$'; then
            export LC_CTYPE=C.UTF-8
            UTF8=1
        else
            UTF8=0
        fi
    fi

    if [[ $IS_TTY -eq 1 ]]; then
        local cols
        cols=$(tput cols 2>/dev/null || printf '80')
        if [[ $cols =~ ^[0-9]+$ ]]; then W=$cols; else W=80; fi
    fi
    if (( W < 64 )); then W=64; fi
    if (( W > 100 )); then W=100; fi
    # Unicode frames on real terminals (even with NO_COLOR), ASCII in logs.
    if [[ $UTF8 -eq 1 && $IS_TTY -eq 1 && ${TERM:-} != dumb ]]; then FANCY=1; fi
}

setup_palette() {
    RST=$'\033[0m'
    if [[ $TRUECOLOR -eq 1 ]]; then
        C_TEXT=$'\033[38;2;226;232;240m'
        C_MUTED=$'\033[38;2;132;148;170m'
        C_LINE=$'\033[38;2;62;78;108m'
        C_DIM=$'\033[38;2;50;60;82m'
        C_TITLE=$'\033[38;2;167;139;250m'
        C_ACCENT=$'\033[38;2;86;212;221m'
        C_BLUE=$'\033[38;2;108;140;255m'
        C_VIOLET=$'\033[38;2;167;139;250m'
        C_GREEN=$'\033[38;2;74;222;128m'
        C_RED=$'\033[38;2;251;113;133m'
        C_BG_SEL=$'\033[48;2;34;45;76;38;2;240;246;255m'
        BADGE_INFO=$'\033[48;2;30;58;110;38;2;191;219;254m'
        BADGE_OK=$'\033[48;2;20;66;46;38;2;167;243;208m'
        BADGE_WARN=$'\033[48;2;78;56;12;38;2;253;230;138m'
        BADGE_ERR=$'\033[48;2;86;26;42;38;2;254;202;202m'
        BADGE_INPUT=$'\033[48;2;12;64;72;38;2;165;243;252m'
        BADGE_DIM=$'\033[48;2;36;44;60;38;2;148;163;184m'
        BADGE_RUN=$'\033[48;2;16;68;48;38;2;134;239;172m'
        BADGE_STOP=$'\033[48;2;42;48;64;38;2;148;163;184m'
    else
        C_TEXT=$'\033[97m'; C_MUTED=$'\033[90m'; C_LINE=$'\033[34m'
        C_DIM=$'\033[90m';  C_TITLE=$'\033[95m'; C_ACCENT=$'\033[96m'; C_BLUE=$'\033[94m'
        C_VIOLET=$'\033[95m'; C_GREEN=$'\033[92m'; C_RED=$'\033[91m'
        C_BG_SEL=$'\033[44;97m'
        BADGE_INFO=$'\033[44;97m';   BADGE_OK=$'\033[42;97m'
        BADGE_WARN=$'\033[43;30m';  BADGE_ERR=$'\033[41;97m'
        BADGE_INPUT=$'\033[46;30m'; BADGE_DIM=$'\033[100;37m'
        BADGE_RUN=$'\033[42;97m';   BADGE_STOP=$'\033[100;37m'
    fi

    if [[ $COLOR -eq 0 ]]; then
        local _n
        for _n in RST C_TEXT C_MUTED C_LINE C_DIM C_TITLE C_ACCENT C_BLUE \
                  C_VIOLET C_GREEN C_RED C_BG_SEL \
                  BADGE_INFO BADGE_OK BADGE_WARN BADGE_ERR BADGE_INPUT \
                  BADGE_DIM BADGE_RUN BADGE_STOP; do
            printf -v "$_n" '%s' ''
        done
    fi

    if [[ $FANCY -eq 1 ]]; then
        B_TL='╭'; B_TR='╮'; B_BL='╰'; B_BR='╯'
        B_H='─'; B_V='│'; B_LT='├'; B_RT='┤'
        BAR_ON='█'; BAR_OFF='░'
        SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
        PULSE=('·' 'o' 'O' 'o')
    else
        B_TL='+'; B_TR='+'; B_BL='+'; B_BR='+'
        B_H='-'; B_V='|'; B_LT='+'; B_RT='+'
        BAR_ON='#'; BAR_OFF='.'
        SPIN=('-' '|' '/' '+')
        PULSE=('.' 'o' 'O' 'o')
    fi
}

# -----------------------------------------------------------------------------
# 2. Low level drawing helpers
# -----------------------------------------------------------------------------
repeat_str() {
    local ch=$1 n=$2 out="" i
    for (( i=0; i<n; i++ )); do out+="$ch"; done
    printf '%s' "$out"
}

# Visible length of a string: drop ANSI CSI sequences, then drop UTF-8
# continuation bytes and count the remaining (one per codepoint) bytes.
vlen() {
    local s
    s=$(printf '%s' "$1" | sed -E $'s/\033\\[[0-9;?]*[A-Za-z]//g')
    s=$(printf '%s' "$s" | LC_ALL=C sed $'s/[\200-\277]//g' | wc -c)
    printf '%s' "${s//[[:space:]]/}"
}

fg_rgb() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }

# Per-character travelling gradient. ASCII-only input keeps this locale-proof.
gradient() {
    local text=$1 r1=$2 g1=$3 b1=$4 r2=$5 g2=$6 b2=$7 off=${8:-0}
    if [[ $COLOR -eq 0 || $TRUECOLOR -eq 0 ]]; then
        printf '%s%s%s' "$C_ACCENT" "$text" "$RST"
        return 0
    fi
    local n=${#text} i ch pos t r g b esc out=""
    for (( i=0; i<n; i++ )); do
        ch=${text:i:1}
        pos=$(( (i + off) % 32 ))
        if (( pos > 16 )); then pos=$(( 32 - pos )); fi
        t=$(( pos * 100 / 16 ))
        r=$(( r1 + (r2 - r1) * t / 100 ))
        g=$(( g1 + (g2 - g1) * t / 100 ))
        b=$(( b1 + (b2 - b1) * t / 100 ))
        printf -v esc '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
        out+="$esc$ch"
    done
    printf '%s%s' "$out" "$RST"
}

# A thick rule whose colour sweeps violet -> cyan -> pink.
gradient_rule() {
    local w=${1:-$W} chunks=20 base rem i n t r g b esc out=""
    base=$(( w / chunks )); rem=$(( w % chunks ))
    if [[ $COLOR -eq 0 || $TRUECOLOR -eq 0 ]]; then
        printf '%s%s%s\n' "$C_LINE" "$(repeat_str "$B_H" "$w")" "$RST"
        return 0
    fi
    for (( i=0; i<chunks; i++ )); do
        n=$base; if (( i < rem )); then n=$(( n + 1 )); fi
        t=$(( i * 100 / (chunks - 1) ))
        if (( t <= 50 )); then
            local u=$(( t * 2 ))
            r=$(( 167 + (86 - 167) * u / 100 ))
            g=$(( 139 + (212 - 139) * u / 100 ))
            b=$(( 250 + (221 - 250) * u / 100 ))
        else
            local u=$(( (t - 50) * 2 ))
            r=$(( 86 + (244 - 86) * u / 100 ))
            g=$(( 212 + (114 - 212) * u / 100 ))
            b=$(( 221 + (182 - 221) * u / 100 ))
        fi
        printf -v esc '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
        out+="$esc$(repeat_str "$B_H" "$n")"
    done
    printf '%s%s\n' "$out" "$RST"
}

panel_top() {
    local title=${1:-} lw fill
    lw=$(( 4 + ${#title} ))
    fill=$(( W - 1 - lw ))
    if (( fill < 1 )); then fill=1; fi
    printf '%s%s%s %s%s%s %s%s%s\n' \
        "$C_LINE" "$B_TL" "$B_H" "$C_TITLE" "$title" "$C_LINE" \
        "$(repeat_str "$B_H" "$fill")" "$B_TR" "$RST"
}

panel_bottom() {
    printf '%s%s%s%s%s\n' "$C_LINE" "$B_BL" \
        "$(repeat_str "$B_H" "$(( W - 2 ))")" "$B_BR" "$RST"
}

panel_sep() {
    printf '%s%s%s%s%s\n' "$C_LINE" "$B_LT" \
        "$(repeat_str "$B_H" "$(( W - 2 ))")" "$B_RT" "$RST"
}

panel_row() {
    local content=${1:-} len pad
    len=$(vlen "$content")
    pad=$(( W - 4 - len ))
    if (( pad < 0 )); then pad=0; fi
    printf '%s%s %s%s %s%s\n' "$C_LINE" "$B_V" "$content" \
        "$(repeat_str ' ' "$pad")" "$B_V" "$RST"
}

panel_blank() { panel_row ''; }

chip() { printf '%s %s %s' "$2" "$1" "$RST"; }

progress_bar() {
    local pct=$1 width=${2:-24} filled out=""
    if (( pct < 0 )); then pct=0; fi
    if (( pct > 100 )); then pct=100; fi
    filled=$(( pct * width / 100 ))
    out+="$C_BLUE$(repeat_str "$BAR_ON" "$filled")"
    out+="$C_LINE$(repeat_str "$BAR_OFF" "$(( width - filled ))")"
    out+="$RST ${C_TEXT}${pct}%${RST}"
    printf '%s' "$out"
}

# A little ASCII equalizer that moves on every rendered frame.
activity_line() {
    local out="" i v ch r g b esc
    for (( i=0; i<28; i++ )); do
        v=$(( (FRAME * 2 + i * 3) % 16 ))
        if (( v > 8 )); then v=$(( 16 - v )); fi
        case $v in
            0|1) ch='.' ;;
            2|3) ch=':' ;;
            4|5) ch='o' ;;
            *)   ch='O' ;;
        esac
        if [[ $TRUECOLOR -eq 1 && $COLOR -eq 1 ]]; then
            r=$(( 70 + v * 12 )); g=$(( 120 + v * 14 )); b=$(( 200 + v * 6 ))
            printf -v esc '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
            out+="$esc$ch"
        else
            out+="$ch"
        fi
    done
    printf '%s%s' "$out" "$RST"
}

# -----------------------------------------------------------------------------
# 3. Screen primitives
# -----------------------------------------------------------------------------
render_begin() {
    FRAME=$(( FRAME + 1 ))
    if [[ $IS_TTY -eq 1 && $PLAIN -eq 0 ]]; then printf '\033[H'; fi
}

render_end() {
    if [[ $IS_TTY -eq 1 && $PLAIN -eq 0 ]]; then printf '\033[J'; fi
}

hide_cursor() { if [[ $IS_TTY -eq 1 && $COLOR -eq 1 ]]; then printf '\033[?25l'; fi; }
show_cursor() { if [[ $IS_TTY -eq 1 && $COLOR -eq 1 ]]; then printf '\033[?25h'; fi; }
clear_screen() { if [[ $IS_TTY -eq 1 && $PLAIN -eq 0 ]]; then printf '\033[2J\033[H'; fi; }

term_prepare() {
    if [[ $IS_TTY -eq 1 ]]; then
        SAVED_STTY=$(stty -g 2>/dev/null || true)
        hide_cursor
    fi
}

term_restore() {
    if [[ $IS_TTY -eq 1 ]]; then
        show_cursor
        if [[ -n $SAVED_STTY ]]; then stty "$SAVED_STTY" 2>/dev/null || true; fi
    fi
}

draw_header() {
    local logo pulse clock
    logo=$(gradient 'NOKVM' 108 140 255 244 114 182 "$(( FRAME * 2 ))")
    pulse=${PULSE[$(( FRAME % 4 ))]}
    clock=$(date '+%H:%M:%S' 2>/dev/null || printf 'clock')
    gradient_rule "$W"
    printf '  %s %s %s\n' "$logo" "${C_MUTED}//  V M   C O N T R O L   C E N T E R${RST}" \
        "${C_LINE}v${VERSION}${RST}"
    printf '  %s%s%s  %s  %s%s%s  %s  %s\n' \
        "$C_MUTED" 'rootsunnylab' "$RST" "${C_DIM}|${RST}" \
        "$C_GREEN" "$pulse" "$RST" "${C_MUTED}fabric online${RST}" "$C_LINE$clock${RST}"
    gradient_rule "$W"
}

status() {
    local type=$1 msg=$2 badge
    case $type in
        INFO)    badge=$(chip ' INFO ' "$BADGE_INFO") ;;
        WARN)    badge=$(chip ' WARN ' "$BADGE_WARN") ;;
        ERROR)   badge=$(chip ' ERROR ' "$BADGE_ERR") ;;
        SUCCESS) badge=$(chip ' OK ' "$BADGE_OK") ;;
        INPUT)   badge=$(chip ' INPUT ' "$BADGE_INPUT") ;;
        *)       badge=$(chip " $type " "$BADGE_DIM") ;;
    esac
    printf '  %s %s%s%s\n' "$badge" "$C_TEXT" "$msg" "$RST"
}

typewriter() {
    local text=$1 delay=${2:-0.012} i
    if [[ $ANIM -eq 0 ]]; then printf '  %s\n' "$text"; return 0; fi
    for (( i=0; i<${#text}; i++ )); do
        printf '%s' "${text:i:1}"
        sleep "$delay"
    done
    printf '\n'
}

nap() { if [[ $ANIM -eq 1 ]]; then sleep "${1:-0.05}"; fi; }

press_enter() {
    show_cursor
    printf '  %s %s\n' "${C_MUTED}press${RST}" "${C_ACCENT}[ENTER]${RST}${C_MUTED} to continue${RST}"
    if ! IFS= read -r _unused; then farewell; fi
    hide_cursor
}

prompt_value() {
    local label=$1 default=$2 var=$3 silent=${4:-0} value=''
    show_cursor
    if (( silent == 1 )); then
        printf '  %s %s%s%s  %s(%s)%s  %s' \
            "$(chip ' INPUT ' "$BADGE_INPUT")" "$C_TEXT" "$label" "$RST" \
            "$C_MUTED" "$default" "$RST" "${C_ACCENT}>${RST} "
        if ! IFS= read -rs value; then farewell; fi
        printf '\n'
    else
        printf '  %s %s%s%s  %s[%s]%s  %s' \
            "$(chip ' INPUT ' "$BADGE_INPUT")" "$C_TEXT" "$label" "$RST" \
            "$C_MUTED" "$default" "$RST" "${C_ACCENT}>${RST} "
        if ! IFS= read -r value; then farewell; fi
    fi
    value=${value:-$default}
    printf -v "$var" '%s' "$value"
    hide_cursor
}

prompt_confirm() {
    local label=$1 default=${2:-n} ans=''
    show_cursor
    printf '  %s %s%s%s  %s(%s)%s  %s' \
        "$(chip ' CONFIRM ' "$BADGE_WARN")" "$C_TEXT" "$label" "$RST" \
        "$C_MUTED" "$default" "$RST" "${C_ACCENT}>${RST} "
    if ! IFS= read -r ans; then farewell; fi
    hide_cursor
    if [[ -z $ans ]]; then ans=$default; fi
    if [[ $ans =~ ^[Yy] ]]; then return 0; fi
    return 1
}

# -----------------------------------------------------------------------------
# 4. Boot splash
# -----------------------------------------------------------------------------
LOGO=(
'#   #  ###  #   # #   # #   #'
'##  # #   # #  #  #   # ## ##'
'# # # #   # # #   #   # # # #'
'#  ## #   # ##    #   # #   #'
'#   # #   # # #   #   # #   #'
'#   # #   # #  #   # #  #   #'
'#   #  ###  #   #   #   #   #'
)

draw_logo_frame() {
    local f=$1 i
    for i in "${!LOGO[@]}"; do
        printf '   %s\033[K\n' "$(gradient "${LOGO[$i]}" 108 140 255 244 114 182 "$(( f * 3 + i * 2 ))")"
    done
}

play_intro() {
    if [[ $ANIM -eq 0 || ${NOKVM_NO_INTRO:-0} == 1 || $PLAIN -eq 1 ]]; then return 0; fi
    clear_screen
    hide_cursor
    local i
    for (( i=0; i<11; i++ )); do
        printf '\033[H'
        draw_logo_frame "$i"
        printf '\033[K\n'
        printf '  %s\033[K\n' "$(gradient 'R O O T S U N N Y L A B   /   V M   C O N T R O L   C E N T E R' 167 139 250 86 212 221 "$(( i * 4 ))")"
        printf '  %s%s%s\033[K\n' "$C_MUTED" "$(repeat_str '-' 66)" "$RST"
        printf '\033[K\n'
        nap 0.055
    done
    printf '\033[H'
    draw_logo_frame 6
    printf '\033[K\n'
    printf '  %s\033[K\n' "$(gradient 'R O O T S U N N Y L A B   /   V M   C O N T R O L   C E N T E R' 167 139 250 86 212 221 20)"
    printf '  %s%s%s\033[K\n' "$C_MUTED" "$(repeat_str '-' 66)" "$RST"
    printf '\033[K\n'
    printf '  '; typewriter 'booting the control deck ...' 0.014
    printf '  %s%s%s\n' "$C_ACCENT" "$(gradient_rule "$W")" "$RST"
    nap 0.25
}

# -----------------------------------------------------------------------------
# 5. Menu engine (animated, arrow keys with a plain fallback)
# -----------------------------------------------------------------------------
MENU_TITLE=''
MENU_HINT=''
declare -a MENU_ITEMS=()

menu_row() {
    local i=$1 sel=$2
    local label=${MENU_ITEMS[$i]} text pad spark
    if (( i == sel )); then
        spark=${SPIN[$(( FRAME % ${#SPIN[@]} ))]}
        text="  ${spark}  $(printf '%2d' $(( i + 1 )))  ${label}"
        pad=$(( W - 4 - $(vlen "$text") ))
        if (( pad < 0 )); then pad=0; fi
        printf '%s%s%s%s' "$C_BG_SEL" "$text" "$(repeat_str ' ' "$pad")" "$RST"
    else
        printf '    %s%2d%s  %s%s%s' "$C_MUTED" "$(( i + 1 ))" "$RST" "$C_TEXT" "$label" "$RST"
    fi
}

render_menu_frame() {
    local sel=$1 i
    render_begin
    draw_header
    if [[ -n $PRE_HOOK ]]; then "$PRE_HOOK"; fi
    panel_top "$MENU_TITLE"
    for (( i=0; i<${#MENU_ITEMS[@]}; i++ )); do
        panel_row "$(menu_row "$i" "$sel")"
    done
    panel_blank
    panel_row "  $(activity_line)  ${C_MUTED}${MENU_HINT}${RST}"
    panel_bottom
    render_end
}

choose() {
    local title=$1 hint=$2
    shift 2
    MENU_TITLE=$title
    MENU_HINT=$hint
    MENU_ITEMS=("$@")
    local n=${#MENU_ITEMS[@]} sel=0 key='' rest='' idx raw='' rc=0
    CHOSEN=-1
    if (( n == 0 )); then return 0; fi

    if [[ $PLAIN -eq 1 || $IS_TTY -eq 0 ]]; then
        render_menu_frame 0
        show_cursor
        printf '  %s ' "$(chip ' SELECT ' "$BADGE_INPUT")"
        local ans=''
        if ! IFS= read -r ans; then farewell; fi
        if [[ $ans =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= n )); then
            CHOSEN=$(( ans - 1 ))
        fi
        hide_cursor
        return 0
    fi

    raw=$(stty -g 2>/dev/null || true)
    stty -echo -icanon min 1 time 0 2>/dev/null || true
    hide_cursor
    while true; do
        render_menu_frame "$sel"
        # The timeout is what keeps the header shimmer / equalizer alive while
        # the user is just looking at the screen.
        if IFS= read -rsn1 -t 0.9 key; then
            case "$key" in
                $'\033')
                    rest=''
                    IFS= read -rsn2 -t 0.15 rest || rest=''
                    case "$rest" in
                        '[A') sel=$(( (sel - 1 + n) % n )) ;;
                        '[B') sel=$(( (sel + 1) % n )) ;;
                        '[H') sel=0 ;;
                        '[F') sel=$(( n - 1 )) ;;
                        *) ;;
                    esac
                    ;;
                ''|$'\n'|$'\r')
                    CHOSEN=$sel; break ;;
                k|K) sel=$(( (sel - 1 + n) % n )) ;;
                j|J) sel=$(( (sel + 1) % n )) ;;
                q|Q) CHOSEN=-1; break ;;
                [1-9])
                    idx=$(( key - 1 ))
                    if (( idx < n )); then CHOSEN=$idx; break; fi
                    ;;
                0)
                    if [[ ${MENU_ITEMS[$(( n - 1 ))]} == *Exit* || ${MENU_ITEMS[$(( n - 1 ))]} == *Back* ]]; then
                        CHOSEN=$(( n - 1 )); break
                    fi
                    ;;
                *) ;;
            esac
        else
            rc=$?
            # read returns 142 on timeout (that is our animation tick) and 1
            # on EOF. On EOF we do not spin forever - leave gracefully.
            if (( rc != 142 )); then
                show_cursor
                if [[ -n $raw ]]; then stty "$raw" 2>/dev/null || true; fi
                farewell
            fi
        fi
    done
    show_cursor
    if [[ -n $raw ]]; then stty "$raw" 2>/dev/null || true; fi
    return 0
}

# -----------------------------------------------------------------------------
# 6. VM data layer (compatible with the original .conf format)
# -----------------------------------------------------------------------------
get_vm_list() {
    find "$VM_DIR" -maxdepth 1 -name '*.conf' -exec basename {} .conf \; 2>/dev/null | sort
}

load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf" quiet=${2:-0}
    if [[ ! -f $config_file ]]; then
        if (( quiet == 0 )); then status ERROR "Configuration for VM '$vm_name' not found"; fi
        return 1
    fi
    unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD \
          DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE \
          SEED_FILE CREATED
    # shellcheck disable=SC1090
    source "$config_file"
    VM_NAME=${VM_NAME:-$vm_name}
    OS_TYPE=${OS_TYPE:-unknown}
    CODENAME=${CODENAME:-}
    IMG_URL=${IMG_URL:-}
    HOSTNAME=${HOSTNAME:-$vm_name}
    USERNAME=${USERNAME:-}
    PASSWORD=${PASSWORD:-}
    DISK_SIZE=${DISK_SIZE:-0G}
    MEMORY=${MEMORY:-0}
    CPUS=${CPUS:-0}
    SSH_PORT=${SSH_PORT:-2222}
    GUI_MODE=${GUI_MODE:-false}
    PORT_FORWARDS=${PORT_FORWARDS:-}
    IMG_FILE=${IMG_FILE:-$VM_DIR/$vm_name.img}
    SEED_FILE=${SEED_FILE:-$VM_DIR/$vm_name-seed.iso}
    CREATED=${CREATED:-unknown}
    return 0
}

save_vm_config() {
    local quiet=${1:-0} config_file="$VM_DIR/$VM_NAME.conf"
    # %q keeps values with spaces, quotes or shell metacharacters source-able.
    {
        printf 'VM_NAME=%q\n'        "$VM_NAME"
        printf 'OS_TYPE=%q\n'        "$OS_TYPE"
        printf 'CODENAME=%q\n'       "$CODENAME"
        printf 'IMG_URL=%q\n'        "$IMG_URL"
        printf 'HOSTNAME=%q\n'       "$HOSTNAME"
        printf 'USERNAME=%q\n'       "$USERNAME"
        printf 'PASSWORD=%q\n'       "$PASSWORD"
        printf 'DISK_SIZE=%q\n'      "$DISK_SIZE"
        printf 'MEMORY=%q\n'         "$MEMORY"
        printf 'CPUS=%q\n'           "$CPUS"
        printf 'SSH_PORT=%q\n'       "$SSH_PORT"
        printf 'GUI_MODE=%q\n'       "$GUI_MODE"
        printf 'PORT_FORWARDS=%q\n'  "$PORT_FORWARDS"
        printf 'IMG_FILE=%q\n'       "$IMG_FILE"
        printf 'SEED_FILE=%q\n'      "$SEED_FILE"
        printf 'CREATED=%q\n'        "$CREATED"
    } > "$config_file"
    chmod 600 "$config_file" 2>/dev/null || true
    if (( quiet == 0 )); then
        status SUCCESS "Configuration saved to $config_file"
    fi
}

is_vm_running() {
    local vm_name=$1
    if pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null 2>&1; then return 0; fi
    return 1
}

status_badge() {
    if is_vm_running "$1"; then
        chip ' RUNNING ' "$BADGE_RUN"
    else
        chip ' STOPPED ' "$BADGE_STOP"
    fi
}

validate_input() {
    local type=$1 value=$2
    VALIDATION_MSG=''
    case $type in
        number)
            if ! [[ $value =~ ^[0-9]+$ ]]; then VALIDATION_MSG='Must be a number'; fi ;;
        size)
            if ! [[ $value =~ ^[0-9]+[GgMm]$ ]]; then VALIDATION_MSG='Must be a size with unit (e.g. 100G, 512M)'; fi ;;
        port)
            if ! [[ $value =~ ^[0-9]+$ ]] || (( 10#$value < 23 || 10#$value > 65535 )); then
                VALIDATION_MSG='Must be a valid port number (23-65535)'
            fi ;;
        name)
            if ! [[ $value =~ ^[a-zA-Z0-9_-]+$ ]]; then
                VALIDATION_MSG='Only letters, numbers, hyphens and underscores are allowed'
            fi ;;
        username)
            if ! [[ $value =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                VALIDATION_MSG='Must start with a letter or underscore, then letters, numbers, - or _'
            fi ;;
        yesno)
            if ! [[ $value =~ ^[YyNn]$ ]]; then VALIDATION_MSG='Please answer y or n'; fi ;;
    esac
    if [[ -n $VALIDATION_MSG ]]; then return 1; fi
    return 0
}

# -----------------------------------------------------------------------------
# 7. Fleet overview (hook drawn above the main menu)
# -----------------------------------------------------------------------------
declare -a VMS=()

render_fleet() {
    local i vm shown=0 extra
    if (( ${#VMS[@]} == 0 )); then
        panel_top "FLEET OVERVIEW  /  0 MACHINES"
        panel_blank
        panel_row "        .-~~~~-.        ${C_MUTED}Nothing in orbit yet.${RST}"
        panel_row "      .'  ${C_ACCENT}NOKVM${C_MUTED}  '.      ${C_TEXT}Your first VM is one keystroke away.${RST}"
        panel_row "     /   .-~~-.   \\       ${C_ACCENT}[+] Create a new VM${C_MUTED} to begin.${RST}"
        panel_row "     '.        .'        ${C_MUTED}Cloud images are fetched for you.${RST}"
        panel_row "       '~~~~~~'         ${C_MUTED}Disks live in ${VM_DIR}${RST}"
        panel_blank
        panel_bottom
        return 0
    fi
    panel_top "FLEET OVERVIEW  /  ${#VMS[@]} MACHINE(S)"
    for i in "${!VMS[@]}"; do
        if (( shown >= 3 )); then break; fi
        vm=${VMS[$i]}
        if ! load_vm_config "$vm" 1; then continue; fi
        panel_row "  ${C_VIOLET}$(printf '%02d' $(( i + 1 )))${RST}  ${C_TEXT}$(printf '%-18s' "$vm")${RST}  $(status_badge "$vm")  ${C_MUTED}${OS_TYPE} ${CODENAME}${RST}"
        panel_row "       ${C_MUTED}RAM${RST} ${C_TEXT}${MEMORY} MB${RST}   ${C_MUTED}CPU${RST} ${C_TEXT}${CPUS}${RST}   ${C_MUTED}DISK${RST} ${C_TEXT}${DISK_SIZE}${RST}   ${C_MUTED}SSH${RST} ${C_ACCENT}${SSH_PORT}${RST}"
        shown=$(( shown + 1 ))
    done
    extra=$(( ${#VMS[@]} - shown ))
    if (( extra > 0 )); then
        panel_row "       ${C_MUTED}+ $extra more machine(s) in ${VM_DIR}${RST}"
    fi
    panel_bottom
}

# -----------------------------------------------------------------------------
# 8. Build screen - animated stepper
# -----------------------------------------------------------------------------
BUILD_LABELS=(
    'Prepare workspace'
    'Fetch cloud image'
    'Provision cloud-init'
    'Build seed image'
    'Size virtual disk'
    'Write VM manifest'
)
declare -a BUILD_STATE=()

build_init() {
    BUILD_STATE=(pending pending pending pending pending pending)
    BUILD_NOTE=''
}

build_set() { BUILD_STATE[$1]=$2; }

build_row() {
    local i=$1
    local s=${BUILD_STATE[$1]} label=${BUILD_LABELS[$1]} mark
    case $s in
        'done')
            printf '  %s[+]%s  %-22s %s  %sdone%s' "$C_GREEN" "$RST" "$label" "$C_MUTED" "$C_GREEN" "$RST" ;;
        running)
            mark=${SPIN[$(( FRAME % ${#SPIN[@]} ))]}
            printf '  %s[%s]%s  %-22s %s  %sworking%s' "$C_ACCENT" "$mark" "$RST" "$label" "$C_MUTED" "$C_ACCENT" "$RST" ;;
        fail)
            printf '  %s[x]%s  %-22s %s  %sfailed%s' "$C_RED" "$RST" "$label" "$C_MUTED" "$C_RED" "$RST" ;;
        *)
            printf '  %s[ ]  %-22s %s  queued%s' "$C_MUTED" "$label" "$C_MUTED" "$RST" ;;
    esac
}

build_frame() {
    local i done_count=0 pct
    for i in "${!BUILD_STATE[@]}"; do
        if [[ ${BUILD_STATE[$i]} == 'done' ]]; then done_count=$(( done_count + 1 )); fi
    done
    pct=$(( done_count * 100 / ${#BUILD_STATE[@]} ))
    render_begin
    draw_header
    panel_top "$BUILD_TITLE"
    for i in "${!BUILD_LABELS[@]}"; do
        panel_row "$(build_row "$i")"
    done
    panel_blank
    panel_row "  $(progress_bar "$pct" 30)   ${C_MUTED}$(activity_line)${RST}"
    if [[ -n $BUILD_NOTE ]]; then
        panel_row "  ${C_MUTED}${BUILD_NOTE}${RST}"
    fi
    panel_bottom
    render_end
}

human_bytes() {
    local b=$1
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec --suffix=B "$b" 2>/dev/null || printf '%s B' "$b"
    else
        awk -v b="$b" 'BEGIN { printf "%.1f MiB", b/1048576 }'
    fi
}

download_image() {
    local url=$1 dest=$2 log="$TMP_DIR/wget.log" pid bytes start=$SECONDS
    wget --quiet --tries=2 --timeout=30 -O "$dest" "$url" > "$log" 2>&1 &
    pid=$!
    BG_PID=$pid
    while kill -0 "$pid" 2>/dev/null; do
        bytes=$(stat -c %s "$dest" 2>/dev/null || printf '0')
        BUILD_NOTE="$(human_bytes "$bytes") fetched   |   $(( SECONDS - start ))s elapsed"
        build_frame
        nap 0.13
        if [[ $ANIM -eq 0 ]]; then sleep 0.3; fi
    done
    if ! wait "$pid"; then
        BG_PID=''
        status ERROR "Download failed - see $log"
        return 1
    fi
    BG_PID=''
    bytes=$(stat -c %s "$dest" 2>/dev/null || printf '0')
    BUILD_NOTE="$(human_bytes "$bytes") ready   |   image verified"
    build_frame
    return 0
}

run_step() {
    local idx=$1 label=$2 log="$TMP_DIR/step.log" pid start=$SECONDS
    shift 2
    build_set "$idx" running
    build_frame
    "$@" > "$log" 2>&1 &
    pid=$!
    BG_PID=$pid
    while kill -0 "$pid" 2>/dev/null; do
        BUILD_NOTE="$label   |   $(( SECONDS - start ))s"
        build_frame
        nap 0.12
        if [[ $ANIM -eq 0 ]]; then sleep 0.3; fi
    done
    if wait "$pid"; then
        BG_PID=''
        build_set "$idx" 'done'
        build_frame
        return 0
    fi
    BG_PID=''
    build_set "$idx" fail
    build_frame
    status ERROR "$label failed"
    if [[ -s $log ]]; then sed 's/^/      /' "$log"; fi
    return 1
}

write_cloud_init() {
    local hash
    hash=$(openssl passwd -6 "$PASSWORD" | tr -d '\n')
    cat > "$TMP_DIR/user-data" <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $hash
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
EOF
    cat > "$TMP_DIR/meta-data" <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF
}

setup_vm_image() {
    build_init
    BUILD_TITLE="CREATING  /  ${VM_NAME:-vm}"

    build_set 0 running; build_frame
    mkdir -p "$VM_DIR"
    nap 0.18
    build_set 0 'done'; build_frame

    if [[ -f $IMG_FILE ]]; then
        build_set 1 'done'
        BUILD_NOTE='cached provider image reused'
        build_frame
    else
        build_set 1 running; build_frame
        if ! download_image "$IMG_URL" "$IMG_FILE.tmp"; then
            rm -f "$IMG_FILE.tmp"
            return 1
        fi
        if ! mv "$IMG_FILE.tmp" "$IMG_FILE"; then
            status ERROR "Could not move downloaded image into place"
            return 1
        fi
        build_set 1 'done'; build_frame
    fi

    if ! run_step 2 'Generating cloud-init profile' write_cloud_init; then return 1; fi
    if ! run_step 3 'Building seed ISO' cloud-localds "$SEED_FILE" "$TMP_DIR/user-data" "$TMP_DIR/meta-data"; then
        return 1
    fi

    build_set 4 running; build_frame
    if qemu-img resize "$IMG_FILE" "$DISK_SIZE" > "$TMP_DIR/resize.log" 2>&1; then
        BUILD_NOTE="disk grown to $DISK_SIZE"
    else
        BUILD_NOTE='resize unavailable - kept the provider image size'
    fi
    build_set 4 'done'; build_frame
    return 0
}

# -----------------------------------------------------------------------------
# 9. Dependency checklist
# -----------------------------------------------------------------------------
DEPS=(qemu-system-x86_64 qemu-img cloud-localds wget openssl)
DEP_LABELS=('QEMU system emulator' 'Disk image tools' 'cloud-init seed tools' 'Image downloader' 'Password hashing')
declare -a CHECK_STATE=()

check_row() {
    local i=$1
    local s=${CHECK_STATE[$i]} label=${DEP_LABELS[$i]} mark
    case $s in
        done)
            printf '  %s[+]%s  %-26s %s%s%s' "$C_GREEN" "$RST" "$label" "$C_GREEN" "${DEPS[$i]}" "$RST" ;;
        running)
            mark=${SPIN[$(( FRAME % ${#SPIN[@]} ))]}
            printf '  %s[%s]%s  %-26s %sprobing%s' "$C_ACCENT" "$mark" "$RST" "$label" "$C_ACCENT" "$RST" ;;
        fail)
            printf '  %s[x]%s  %-26s %sMISSING%s' "$C_RED" "$RST" "$label" "$C_RED" "$RST" ;;
        *)
            printf '  %s[ ]  %-26s queued%s' "$C_MUTED" "$label" "$RST" ;;
    esac
}

check_screen() {
    local i done_count=0
    for i in "${!CHECK_STATE[@]}"; do
        if [[ ${CHECK_STATE[$i]} == 'done' ]]; then done_count=$(( done_count + 1 )); fi
    done
    render_begin
    draw_header
    panel_top 'SYSTEM CHECK  /  BOOT'
    for i in "${!DEPS[@]}"; do panel_row "$(check_row "$i")"; done
    panel_blank
    panel_row "  $(progress_bar "$(( done_count * 100 / ${#DEPS[@]} ))" 30)"
    panel_row "  ${C_MUTED}store${RST}  ${C_TEXT}${VM_DIR}${RST}"
    panel_bottom
    render_end
}

check_dependencies() {
    local i missing=0
    CHECK_STATE=(pending pending pending pending pending)
    for i in "${!DEPS[@]}"; do
        CHECK_STATE[i]='running'
        check_screen
        nap 0.11
        if command -v "${DEPS[$i]}" >/dev/null 2>&1; then
            CHECK_STATE[i]='done'
        else
            CHECK_STATE[i]='fail'
            missing=$(( missing + 1 ))
        fi
        check_screen
    done
    if (( missing > 0 )); then
        printf '\n'
        status ERROR "$missing required tool(s) not found"
        status INFO 'On Ubuntu/Debian:  sudo apt install qemu-system-x86 qemu-utils cloud-image-utils wget openssl'
        term_restore
        exit 1
    fi
    nap 0.2
}

# -----------------------------------------------------------------------------
# 10. Create VM wizard
# -----------------------------------------------------------------------------
wizard_summary() {
    local os=${OS_TYPE:-'-'} nm=${VM_NAME:-'-'} hn=${HOSTNAME:-'-'}
    local un=${USERNAME:-'-'} ds=${DISK_SIZE:-'-'} mem=${MEMORY:-'-'}
    local cpu=${CPUS:-'-'} port=${SSH_PORT:-'-'} gui=${GUI_MODE:-'-'}
    local fw=${PORT_FORWARDS:-'none'}
    panel_row "  ${C_MUTED}distro${RST}    ${C_TEXT}$(printf '%-16s' "$os")${RST} ${C_MUTED}name${RST}     ${C_ACCENT}${nm}${RST}"
    panel_row "  ${C_MUTED}host${RST}      ${C_TEXT}$(printf '%-16s' "$hn")${RST} ${C_MUTED}user${RST}     ${C_TEXT}${un}${RST}"
    panel_row "  ${C_MUTED}disk${RST}      ${C_TEXT}$(printf '%-16s' "$ds")${RST} ${C_MUTED}ram${RST}      ${C_TEXT}${mem} MB${RST}"
    panel_row "  ${C_MUTED}cpus${RST}      ${C_TEXT}$(printf '%-16s' "$cpu")${RST} ${C_MUTED}ssh${RST}      ${C_TEXT}${port}${RST}"
    panel_row "  ${C_MUTED}gui${RST}       ${C_TEXT}$(printf '%-16s' "$gui")${RST} ${C_MUTED}forwards${RST}  ${C_TEXT}${fw}${RST}"
}

wizard_frame() {
    local pct=$(( WIZ_STEP * 100 / WIZ_TOTAL ))
    render_begin
    draw_header
    panel_top "NEW VIRTUAL MACHINE  /  WIZARD"
    panel_row "  $(progress_bar "$pct" 28)   ${C_MUTED}step ${WIZ_STEP} of ${WIZ_TOTAL}${RST}"
    panel_sep
    wizard_summary
    panel_sep
    if [[ -n $WIZ_ERROR ]]; then
        panel_row "  $(chip ' ! ' "$BADGE_ERR")  ${C_RED}${WIZ_ERROR}${RST}"
    fi
    panel_row "  $(activity_line)  ${C_MUTED}type a value, or press Enter for the default${RST}"
    panel_bottom
    render_end
}

wizard_step() {
    local n=$1
    WIZ_STEP=$n
    WIZ_ERROR=''
    wizard_frame
}

review_frame() {
    WIZ_STEP=$WIZ_TOTAL
    render_begin
    draw_header
    panel_top "REVIEW  /  ${VM_NAME}"
    panel_row "  $(progress_bar 100 30)   ${C_GREEN}all set${RST}"
    panel_sep
    wizard_summary
    panel_sep
    panel_row "  ${C_MUTED}image${RST}   ${C_TEXT}${IMG_URL}${RST}"
    panel_row "  ${C_MUTED}disk${RST}    ${C_TEXT}${IMG_FILE}${RST}"
    panel_row "  ${C_MUTED}seed${RST}    ${C_TEXT}${SEED_FILE}${RST}"
    panel_blank
    panel_row "  $(activity_line)  ${C_MUTED}this will download a cloud image and build a seed ISO${RST}"
    panel_bottom
    render_end
}

celebrate() {
    local i
    for (( i=0; i<4; i++ )); do
        render_begin
        draw_header
        panel_top "READY  /  ${VM_NAME}"
        panel_blank
        panel_row "$(gradient '         *   *   *      V M   R E A D Y      *   *   *' 74 222 128 86 212 221 "$(( FRAME * 4 + i * 5 ))")"
        panel_blank
        panel_row "  $(chip ' SUCCESS ' "$BADGE_OK")  ${C_TEXT}VM '${VM_NAME}' is staged and ready.${RST}"
        panel_row "  ${C_MUTED}connect${RST}  ${C_ACCENT}ssh -p ${SSH_PORT} ${USERNAME}@localhost${RST}"
        panel_row "  ${C_MUTED}password${RST} ${C_TEXT}${PASSWORD}${RST}"
        panel_blank
        panel_bottom
        render_end
        nap 0.11
    done
}

create_new_vm() {
    local os gui_input='' fw=''
    local -a os_labels=()

    # Step 1 - distro picker
    for os in "${OS_NAMES[@]}"; do os_labels+=("$os"); done
    PRE_HOOK=''
    choose 'STEP 01  /  CHOOSE A DISTRIBUTION' 'Up/Down to browse  -  Enter to pick' "${os_labels[@]}"
    if (( CHOSEN < 0 )); then return 0; fi
    os=${OS_NAMES[$CHOSEN]}
    IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"

    VM_NAME=''; HOSTNAME=''; USERNAME=''; PASSWORD=''; DISK_SIZE=''
    MEMORY=''; CPUS=''; SSH_PORT=''; PORT_FORWARDS=''; GUI_MODE='false'

    # Step 2 - name
    while true; do
        wizard_step 2
        prompt_value 'VM name' "$DEFAULT_HOSTNAME" VM_NAME
        if ! validate_input name "$VM_NAME"; then WIZ_ERROR=$VALIDATION_MSG; continue; fi
        if [[ -f $VM_DIR/$VM_NAME.conf ]]; then WIZ_ERROR='A VM with that name already exists'; continue; fi
        break
    done

    # Step 3 - hostname
    while true; do
        wizard_step 3
        prompt_value 'Hostname' "$VM_NAME" HOSTNAME
        if validate_input name "$HOSTNAME"; then break; fi
        WIZ_ERROR=$VALIDATION_MSG
    done

    # Step 4 - username
    while true; do
        wizard_step 4
        prompt_value 'Username' "$DEFAULT_USERNAME" USERNAME
        if validate_input username "$USERNAME"; then break; fi
        WIZ_ERROR=$VALIDATION_MSG
    done

    # Step 5 - password
    while true; do
        wizard_step 5
        prompt_value 'Password' "$DEFAULT_PASSWORD" PASSWORD 1
        if [[ -n $PASSWORD ]]; then break; fi
        WIZ_ERROR='Password cannot be empty'
    done

    # Step 6 - disk
    while true; do
        wizard_step 6
        prompt_value 'Disk size' '20G' DISK_SIZE
        if validate_input size "$DISK_SIZE"; then break; fi
        WIZ_ERROR=$VALIDATION_MSG
    done

    # Step 7 - memory
    while true; do
        wizard_step 7
        prompt_value 'Memory (MB)' '2048' MEMORY
        if validate_input number "$MEMORY"; then break; fi
        WIZ_ERROR=$VALIDATION_MSG
    done

    # Step 8 - CPUs
    while true; do
        wizard_step 8
        prompt_value 'CPU cores' '2' CPUS
        if validate_input number "$CPUS"; then break; fi
        WIZ_ERROR=$VALIDATION_MSG
    done

    # Step 9 - SSH port
    while true; do
        wizard_step 9
        prompt_value 'Host SSH port' '2222' SSH_PORT
        if ! validate_input port "$SSH_PORT"; then WIZ_ERROR=$VALIDATION_MSG; continue; fi
        if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
            WIZ_ERROR="Port $SSH_PORT is already in use on this host"
            continue
        fi
        break
    done

    # Step 10 - GUI
    while true; do
        wizard_step 10
        prompt_value 'Enable graphical display? (y/n)' 'n' gui_input
        if ! validate_input yesno "$gui_input"; then WIZ_ERROR=$VALIDATION_MSG; continue; fi
        if [[ $gui_input =~ ^[Yy] ]]; then GUI_MODE='true'; else GUI_MODE='false'; fi
        break
    done

    # Step 11 - extra forwards
    wizard_step 11
    prompt_value 'Extra port forwards (8080:80, ...)' 'none' fw
    if [[ $fw == none ]]; then fw=''; fi
    PORT_FORWARDS=$fw

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    review_frame
    if ! prompt_confirm 'Build this virtual machine?' 'Y'; then
        status INFO 'Creation cancelled - nothing was changed'
        press_enter
        return 0
    fi

    if ! setup_vm_image; then
        status ERROR 'VM creation did not finish - see the messages above'
        press_enter
        return 1
    fi

    build_set 5 running; build_frame
    save_vm_config 1
    build_set 5 'done'
    BUILD_NOTE="manifest written to $VM_DIR/$VM_NAME.conf"
    build_frame
    nap 0.2
    celebrate
    press_enter
}

# -----------------------------------------------------------------------------
# 11. VM actions
# -----------------------------------------------------------------------------
kv_row() {
    local label=$1 value=$2 color=${3:-$C_TEXT}
    printf '  %s%-12s%s %s%s%s' "$C_MUTED" "$label" "$RST" "$color" "$value" "$RST"
}

show_vm_info() {
    local vm_name=$1
    if ! load_vm_config "$vm_name"; then press_enter; return 1; fi
    render_begin
    draw_header
    panel_top "VM DETAILS  /  ${VM_NAME}"
    panel_row "  $(status_badge "$VM_NAME")   ${C_TEXT}${OS_TYPE} ${CODENAME}${RST}"
    panel_sep
    panel_row "$(kv_row 'HOSTNAME' "$HOSTNAME")"
    panel_row "$(kv_row 'USERNAME' "$USERNAME" "$C_ACCENT")"
    panel_row "$(kv_row 'PASSWORD' "$PASSWORD")"
    panel_row "$(kv_row 'SSH PORT' "$SSH_PORT" "$C_ACCENT")"
    panel_row "$(kv_row 'MEMORY' "${MEMORY} MB")"
    panel_row "$(kv_row 'CPU CORES' "$CPUS")"
    panel_row "$(kv_row 'DISK' "$DISK_SIZE")"
    panel_row "$(kv_row 'GUI MODE' "$GUI_MODE")"
    panel_row "$(kv_row 'FORWARDS' "${PORT_FORWARDS:-none}")"
    panel_row "$(kv_row 'CREATED' "$CREATED" "$C_MUTED")"
    panel_sep
    panel_row "  ${C_MUTED}image${RST}  ${C_TEXT}${IMG_FILE}${RST}"
    panel_row "  ${C_MUTED}seed${RST}   ${C_TEXT}${SEED_FILE}${RST}"
    panel_blank
    panel_row "  ${C_MUTED}connect${RST}   ${C_GREEN}ssh -p ${SSH_PORT} ${USERNAME}@localhost${RST}"
    panel_bottom
    render_end
    press_enter
}

start_vm() {
    local vm_name=$1 n
    if ! load_vm_config "$vm_name"; then press_enter; return 1; fi

    for n in 3 2 1; do
        render_begin
        draw_header
        panel_top "PRE-FLIGHT  /  ${VM_NAME}"
        panel_row "  $(chip ' LAUNCH ' "$BADGE_INFO")   ${C_TEXT}powering up in ${n}${RST}"
        panel_sep
        panel_row "$(kv_row 'SSH' "ssh -p ${SSH_PORT} ${USERNAME}@localhost" "$C_ACCENT")"
        panel_row "$(kv_row 'PASSWORD' "$PASSWORD")"
        panel_row "$(kv_row 'MEMORY' "${MEMORY} MB")"
        panel_row "$(kv_row 'CPUS' "$CPUS")"
        panel_row "$(kv_row 'GUI' "$GUI_MODE")"
        panel_blank
        panel_row "  $(progress_bar "$(( (4 - n) * 33 ))" 30)   $(activity_line)"
        panel_bottom
        render_end
        nap 0.45
    done

    if [[ ! -f $IMG_FILE ]]; then
        status ERROR "VM image file not found: $IMG_FILE"
        press_enter
        return 1
    fi
    if [[ ! -f $SEED_FILE ]]; then
        status WARN 'Seed file missing - rebuilding it'
        if ! setup_vm_image; then press_enter; return 1; fi
    fi

    # shellcheck disable=SC2054  # commas are part of QEMU's drive syntax
    local -a qemu_cmd=(
        qemu-system-x86_64
        -name "guest=${VM_NAME}"
        -m "$MEMORY"
        -smp "$CPUS"
        -drive "file=${IMG_FILE},format=qcow2,if=virtio"
        -drive "file=${SEED_FILE},format=raw,if=virtio"
        -boot order=c
        -device virtio-net-pci,netdev=n0
        -netdev "user,id=n0,hostfwd=tcp::${SSH_PORT}-:22"
    )

    if [[ -w /dev/kvm ]]; then
        qemu_cmd+=(-enable-kvm -cpu host)
    else
        qemu_cmd+=(-cpu qemu64)
    fi

    if [[ -n $PORT_FORWARDS ]]; then
        local -a forwards=()
        local forward host_port guest_port netid=1
        IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
        for forward in "${forwards[@]}"; do
            IFS=':' read -r host_port guest_port <<< "$forward"
            if [[ -z ${host_port:-} || -z ${guest_port:-} ]]; then continue; fi
            qemu_cmd+=(-device "virtio-net-pci,netdev=n${netid}")
            qemu_cmd+=(-netdev "user,id=n${netid},hostfwd=tcp::${host_port}-:${guest_port}")
            netid=$(( netid + 1 ))
        done
    fi

    if [[ $GUI_MODE == true ]]; then
        # shellcheck disable=SC2054
        qemu_cmd+=(-vga virtio -display gtk,gl=on)
    else
        qemu_cmd+=(-nographic -serial mon:stdio)
    fi
    # shellcheck disable=SC2054
    qemu_cmd+=(
        -device virtio-balloon-pci
        -object rng-random,filename=/dev/urandom,id=rng0
        -device virtio-rng-pci,rng=rng0
    )

    # QEMU owns the terminal from here on, so hand it back a sane tty.
    term_restore
    clear_screen
    printf '  %sNOKVM%s  /  %s  -  serial console attached\n' "$C_ACCENT" "$RST" "$VM_NAME"
    printf '  %sQEMU monitor: Ctrl+A then X to quit%s\n\n' "$C_MUTED" "$RST"
    if "${qemu_cmd[@]}"; then
        status INFO "VM ${VM_NAME} has shut down"
    else
        status WARN "QEMU exited with a non-zero status for ${VM_NAME}"
    fi
    term_prepare
    printf '\n'
    press_enter
}

stop_vm() {
    local vm_name=$1 n
    if ! load_vm_config "$vm_name"; then press_enter; return 1; fi
    if ! is_vm_running "$vm_name"; then
        status INFO "VM ${vm_name} is not running"
        press_enter
        return 0
    fi
    for n in 1 2 3 4 5; do
        render_begin
        draw_header
        panel_top "POWERING DOWN  /  ${VM_NAME}"
        panel_row "  $(chip ' STOP ' "$BADGE_WARN")   ${C_TEXT}sending ACPI shutdown${RST}"
        panel_blank
        panel_row "  $(progress_bar "$(( n * 20 ))" 30)   $(activity_line)"
        panel_bottom
        render_end
        nap 0.1
        if (( n == 2 )); then
            pkill -f "qemu-system-x86_64.*${IMG_FILE}" 2>/dev/null || true
        fi
        if (( n == 4 )) && is_vm_running "$vm_name"; then
            pkill -9 -f "qemu-system-x86_64.*${IMG_FILE}" 2>/dev/null || true
        fi
    done
    sleep 1
    if is_vm_running "$vm_name"; then
        status WARN "VM ${vm_name} is still running"
    else
        status SUCCESS "VM ${vm_name} stopped"
    fi
    press_enter
}

delete_vm() {
    local vm_name=$1 n
    if ! load_vm_config "$vm_name"; then press_enter; return 1; fi
    render_begin
    draw_header
    panel_top "DANGER ZONE  /  ${VM_NAME}"
    panel_row "  $(chip ' IRREVERSIBLE ' "$BADGE_ERR")  ${C_RED}This permanently removes the VM and all its data.${RST}"
    panel_blank
    panel_row "$(kv_row 'IMAGE' "$IMG_FILE" "$C_RED")"
    panel_row "$(kv_row 'SEED' "$SEED_FILE" "$C_RED")"
    panel_row "$(kv_row 'CONFIG' "$VM_DIR/$vm_name.conf" "$C_RED")"
    panel_blank
    panel_row "  $(activity_line)  ${C_MUTED}no undo, no recycle bin${RST}"
    panel_bottom
    render_end
    if ! prompt_confirm "Really delete '${vm_name}'?" 'n'; then
        status INFO 'Deletion cancelled'
        press_enter
        return 0
    fi
    for n in 1 2 3 4 5; do
        render_begin
        draw_header
        panel_top "DELETING  /  ${VM_NAME}"
        panel_row "  $(chip ' WORKING ' "$BADGE_WARN")   ${C_TEXT}removing virtual disks${RST}"
        panel_blank
        panel_row "  $(progress_bar "$(( n * 20 ))" 30)   $(activity_line)"
        panel_bottom
        render_end
        nap 0.09
    done
    rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
    status SUCCESS "VM '${vm_name}' has been deleted"
    press_enter
}

edit_vm_config() {
    local vm_name=$1 choice new_value='' gui_input=''
    if ! load_vm_config "$vm_name"; then press_enter; return 1; fi
    local -a labels=(
        'Hostname' 'Username' 'Password' 'Host SSH port' 'GUI mode'
        'Extra port forwards' 'Memory (MB)' 'CPU cores' 'Disk size'
        'Back to main menu'
    )
    PRE_HOOK=''
    while true; do
        choose "EDIT  /  ${VM_NAME}" 'Up/Down to browse  -  Enter to edit' "${labels[@]}"
        if (( CHOSEN < 0 )); then return 0; fi
        choice=$(( CHOSEN + 1 ))
        if (( choice == 10 )); then return 0; fi

        case $choice in
            1)  prompt_value 'New hostname' "$HOSTNAME" new_value
                if validate_input name "$new_value"; then HOSTNAME=$new_value; else status ERROR "$VALIDATION_MSG"; fi ;;
            2)  prompt_value 'New username' "$USERNAME" new_value
                if validate_input username "$new_value"; then USERNAME=$new_value; else status ERROR "$VALIDATION_MSG"; fi ;;
            3)  prompt_value 'New password' "$PASSWORD" new_value 1
                if [[ -n $new_value ]]; then PASSWORD=$new_value; else status ERROR 'Password cannot be empty'; fi ;;
            4)  prompt_value 'New SSH port' "$SSH_PORT" new_value
                if validate_input port "$new_value"; then
                    if [[ $new_value != "$SSH_PORT" ]] && ss -tln 2>/dev/null | grep -q ":$new_value "; then
                        status ERROR "Port $new_value is already in use"
                    else
                        SSH_PORT=$new_value
                    fi
                else
                    status ERROR "$VALIDATION_MSG"
                fi ;;
            5)  prompt_value 'Enable GUI mode? (y/n)' "$GUI_MODE" gui_input
                if [[ $gui_input =~ ^[YyNn]$ ]]; then
                    if [[ $gui_input =~ ^[Yy] ]]; then GUI_MODE='true'; else GUI_MODE='false'; fi
                elif [[ -n $gui_input && $gui_input != true && $gui_input != false ]]; then
                    status ERROR 'Please answer y or n'
                fi ;;
            6)  prompt_value 'Extra port forwards' "${PORT_FORWARDS:-none}" new_value
                if [[ $new_value == none ]]; then new_value=''; fi
                PORT_FORWARDS=$new_value ;;
            7)  prompt_value 'New memory (MB)' "$MEMORY" new_value
                if validate_input number "$new_value"; then MEMORY=$new_value; else status ERROR "$VALIDATION_MSG"; fi ;;
            8)  prompt_value 'New CPU count' "$CPUS" new_value
                if validate_input number "$new_value"; then CPUS=$new_value; else status ERROR "$VALIDATION_MSG"; fi ;;
            9)  prompt_value 'New disk size' "$DISK_SIZE" new_value
                if validate_input size "$new_value"; then DISK_SIZE=$new_value; else status ERROR "$VALIDATION_MSG"; fi ;;
        esac

        if (( choice == 1 || choice == 2 || choice == 3 )); then
            status INFO 'Updating cloud-init credentials'
            if ! setup_vm_image; then press_enter; return 1; fi
        fi
        save_vm_config
        if ! prompt_confirm 'Keep editing this VM?' 'n'; then return 0; fi
    done
}

resize_vm_disk() {
    local vm_name=$1 new_size='' cur_num new_num cur_unit new_unit
    if ! load_vm_config "$vm_name"; then press_enter; return 1; fi
    while true; do
        render_begin
        draw_header
        panel_top "RESIZE DISK  /  ${VM_NAME}"
        panel_row "  $(chip ' CURRENT ' "$BADGE_INFO")   ${C_TEXT}${DISK_SIZE}${RST}"
        panel_row "  ${C_MUTED}Only growing a disk is safe; shrinking can destroy data.${RST}"
        panel_blank
        panel_row "  $(activity_line)  ${C_MUTED}uses qemu-img resize${RST}"
        panel_bottom
        render_end
        prompt_value 'New disk size (e.g. 50G)' "$DISK_SIZE" new_size
        if ! validate_input size "$new_size"; then
            status ERROR "$VALIDATION_MSG"
            continue
        fi
        if [[ $new_size == "$DISK_SIZE" ]]; then
            status INFO 'Same size as before - nothing to do'
            press_enter
            return 0
        fi
        cur_num=${DISK_SIZE%[GgMm]}; new_num=${new_size%[GgMm]}
        cur_unit=${DISK_SIZE: -1}; new_unit=${new_size: -1}
        if [[ $cur_unit =~ [Gg] ]]; then cur_num=$(( 10#$cur_num * 1024 )); fi
        if [[ $new_unit =~ [Gg] ]]; then new_num=$(( 10#$new_num * 1024 )); fi
        if (( new_num < cur_num )); then
            status WARN 'Shrinking a disk can cause data loss'
            if ! prompt_confirm 'Continue anyway?' 'n'; then
                status INFO 'Disk resize cancelled'
                press_enter
                return 0
            fi
        fi
        break
    done
    status INFO "Resizing disk to ${new_size}"
    if qemu-img resize "$IMG_FILE" "$new_size"; then
        DISK_SIZE=$new_size
        save_vm_config
        status SUCCESS "Disk resized to ${new_size}"
    else
        status ERROR 'Failed to resize disk'
    fi
    press_enter
}

show_vm_performance() {
    local vm_name=$1 pid cpu='0' mem='0' rss='0' cpui memi line
    if ! load_vm_config "$vm_name"; then press_enter; return 1; fi
    render_begin
    draw_header
    panel_top "TELEMETRY  /  ${VM_NAME}"
    if is_vm_running "$vm_name"; then
        panel_row "  $(chip ' LIVE ' "$BADGE_RUN")   ${C_MUTED}sampled from the host${RST}"
        panel_sep
        pid=$(pgrep -f "qemu-system-x86_64.*${IMG_FILE}" | head -n1 || true)
        if [[ -n $pid ]]; then
            read -r cpu mem rss < <(ps -p "$pid" -o %cpu=,%mem=,rss= 2>/dev/null || printf '0 0 0') || true
            cpui=${cpu%%.*}; memi=${mem%%.*}
            [[ $cpui =~ ^[0-9]+$ ]] || cpui=0
            [[ $memi =~ ^[0-9]+$ ]] || memi=0
            panel_row "  ${C_MUTED}CPU${RST}    $(progress_bar "$cpui" 24)   ${C_TEXT}${cpu}%${RST}"
            panel_row "  ${C_MUTED}MEM${RST}    $(progress_bar "$memi" 24)   ${C_TEXT}${mem}%${RST}"
            panel_row "  ${C_MUTED}PID${RST}    ${C_TEXT}${pid}${RST}   ${C_MUTED}RSS${RST} ${C_TEXT}${rss} KB${RST}"
            panel_sep
            while IFS= read -r line; do panel_row "  ${C_MUTED}${line}${RST}"; done < <(free -h 2>/dev/null || true)
            panel_sep
            while IFS= read -r line; do panel_row "  ${C_MUTED}${line}${RST}"; done < <(df -h "$IMG_FILE" 2>/dev/null || du -h "$IMG_FILE" 2>/dev/null || true)
        else
            panel_row "  ${C_RED}Could not find the QEMU process for this VM${RST}"
        fi
    else
        panel_row "  $(chip ' IDLE ' "$BADGE_STOP")   ${C_MUTED}VM is not running - showing configuration${RST}"
        panel_sep
        panel_row "$(kv_row 'MEMORY' "${MEMORY} MB")"
        panel_row "$(kv_row 'CPUS' "$CPUS")"
        panel_row "$(kv_row 'DISK' "$DISK_SIZE")"
        panel_row "$(kv_row 'SSH' "$SSH_PORT")"
    fi
    panel_blank
    panel_row "  $(activity_line)  ${C_MUTED}host-side statistics${RST}"
    panel_bottom
    render_end
    press_enter
}

pick_vm() {
    local action=$1 vm
    local -a labels=()
    for vm in "${VMS[@]}"; do
        if ! load_vm_config "$vm" 1; then continue; fi
        labels+=("$(printf '%-18s  %-14s  %s  %s' "$vm" "${OS_TYPE}" "${MEMORY}MB/${CPUS}cpu" "$(status_badge "$vm")")")
    done
    PRE_HOOK=''
    choose "SELECT A MACHINE  /  ${action}" 'Up/Down to browse  -  Enter to select  -  q to go back' "${labels[@]}"
    if (( CHOSEN < 0 || CHOSEN >= ${#VMS[@]} )); then return 1; fi
    PICKED_VM=${VMS[$CHOSEN]}
    return 0
}

# -----------------------------------------------------------------------------
# 12. Main menu + exit
# -----------------------------------------------------------------------------
farewell() {
    term_restore
    if [[ $IS_TTY -eq 1 && $PLAIN -eq 0 && $ANIM -eq 1 ]]; then
        clear_screen
        local i
        for i in "${!LOGO[@]}"; do
            printf '   %s\n' "$(gradient "${LOGO[$i]}" 86 212 221 167 139 250 "$(( i * 3 ))")"
        done
        printf '\n'
        printf '  '; typewriter 'thanks for flying with ROOTSUNNYLAB  *  *  *' 0.012
        printf '  %s\n' "$(gradient "$(repeat_str '-' 66)" 167 139 250 86 212 221 0)"
        printf '\n'
    else
        printf '\n'
        status INFO 'Goodbye!'
        printf '\n'
    fi
    exit 0
}

main_menu() {
    local -a labels=() codes=() action
    local vm_count
    while true; do
        mapfile -t VMS < <(get_vm_list)
        vm_count=${#VMS[@]}
        labels=(); codes=()
        labels+=('[+]  Create a new VM');                 codes+=('create')
        if (( vm_count > 0 )); then
            labels+=('[>]  Start a VM');                codes+=('start')
            labels+=('[#]  Stop a VM');                 codes+=('stop')
            labels+=('[i]  Show VM information');       codes+=('info')
            labels+=('[~]  Edit VM configuration');     codes+=('edit')
            labels+=('[x]  Delete a VM');               codes+=('delete')
            labels+=('[=]  Resize VM disk');            codes+=('resize')
            labels+=('[%]  Show VM performance');       codes+=('perf')
        fi
        labels+=('[q]  Exit');                          codes+=('exit')

        PRE_HOOK='render_fleet'
        choose 'MAIN MENU  /  CONTROL DECK' 'Up/Down + Enter   |   1-9 jump   |   0 / q exit' "${labels[@]}"
        PRE_HOOK=''
        if (( CHOSEN < 0 )); then action='exit'; else action=${codes[$CHOSEN]}; fi

        # Every action reports its own errors; a failure must never take the
        # whole control panel down (we run under `set -e`).
        case $action in
            create) create_new_vm || true ;;
            start)
                if pick_vm 'START'; then start_vm "$PICKED_VM" || true; fi ;;
            stop)
                if pick_vm 'STOP'; then stop_vm "$PICKED_VM" || true; fi ;;
            info)
                if pick_vm 'DETAILS'; then show_vm_info "$PICKED_VM" || true; fi ;;
            edit)
                if pick_vm 'EDIT'; then edit_vm_config "$PICKED_VM" || true; fi ;;
            delete)
                if pick_vm 'DELETE'; then delete_vm "$PICKED_VM" || true; fi ;;
            resize)
                if pick_vm 'RESIZE'; then resize_vm_disk "$PICKED_VM" || true; fi ;;
            perf)
                if pick_vm 'TELEMETRY'; then show_vm_performance "$PICKED_VM" || true; fi ;;
            exit) farewell ;;
            *) ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# 13. Bootstrap
# -----------------------------------------------------------------------------
cleanup() {
    if [[ -n $BG_PID ]] && kill -0 "$BG_PID" 2>/dev/null; then
        kill "$BG_PID" 2>/dev/null || true
    fi
    if [[ -n $TMP_DIR && -d $TMP_DIR ]]; then rm -rf -- "$TMP_DIR"; fi
}
trap 'term_restore; cleanup' EXIT
trap 'term_restore; cleanup; exit 130' INT TERM

ui_init
setup_palette
term_prepare

VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nokvm.XXXXXX")

# Ordered list keeps the distro picker stable (associative arrays are not).
OS_NAMES=(
    'Ubuntu 22.04' 'Ubuntu 24.04' 'Debian 11' 'Debian 12'
    'Fedora 40' 'CentOS Stream 9' 'AlmaLinux 9' 'Rocky Linux 9'
)
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

play_intro
check_dependencies
main_menu
