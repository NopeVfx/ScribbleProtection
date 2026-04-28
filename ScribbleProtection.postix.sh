#!/bin/sh
PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Colors and status helpers
ESC=$(printf '\033')
R="${ESC}[1;31m"
G="${ESC}[1;32m"
Y="${ESC}[1;33m"
C="${ESC}[1;36m"
W="${ESC}[1;37m"
DIM="${ESC}[2m"
BOLD="${ESC}[1m"
RST="${ESC}[0m"

ok()   { printf "%s[  OK  ]%s %s\n" "$G" "$RST" "$1"; }
warn() { printf "%s[ WARN ]%s %s\n" "$Y" "$RST" "$1"; }
err()  { printf "%s[ FAIL ]%s %s\n" "$R" "$RST" "$1"; }
info() { printf "%s[ INFO ]%s %s\n" "$C" "$RST" "$1"; }
sep()  { printf "%s%s%s\n" "$DIM" "----------------------------------------------------------" "$RST"; }
pause() {
    printf "\n%s[enter to continue]%s" "$DIM" "$RST"
    read -r _dummy
}
confirm() {
    printf "%s%s [y/N]: %s" "$Y" "$1" "$RST"
    read -r _a
    [ "$_a" = "y" ] || [ "$_a" = "Y" ]
}

if [ "$(id -u)" -ne 0 ]; then
    printf "%snot running as root - privileged commands (gsctool/crossystem) will fail.%s\n" "$Y" "$RST"
    printf "%scontinuing anyway so you can browse the walkthrough.%s\n" "$DIM" "$RST"
    sleep 1
fi

# Logo and step-screen header
print_logo() {
    printf "%s" "$C"
    cat <<'LOGO'
  ____  ____
 / ___||  _ \
 \___ \| |_) |
  ___) |  __/
 |____/|_|
LOGO
    printf "%s" "$RST"
    printf "  %sScribble Protection  |  WP Walkthrough%s\n" "$DIM" "$RST"
    sep
}

step_header() {
    clear 2>/dev/null || printf "\n\n"
    print_logo
    printf "\n  %s%s%s%s\n\n" "$BOLD" "$W" "$1" "$RST"
    sep
    printf "\n"
}

# Numeric menu helper (POSIX, no arrays, no raw reads)
# Usage: numeric_menu "Title" "Item 1" "Item 2" ... ; menu_choice holds 1-based index, or 0 for back/quit
numeric_menu() {
    _title=$1
    shift
    menu_choice=0
    while :; do
        clear 2>/dev/null || printf "\n\n"
        print_logo
        printf "\n  %s%s%s%s\n\n" "$BOLD" "$W" "$_title" "$RST"
        printf "  %stype a number and press enter, q to go back%s\n\n" "$DIM" "$RST"

        _i=1
        for _it in "$@"; do
            printf "  %s%d)%s %s\n" "$BOLD" "$_i" "$RST" "$_it"
            _i=$((_i + 1))
        done
        _max=$((_i - 1))
        printf "\n  %s>%s " "$BOLD" "$RST"
        read -r _ans || { menu_choice=0; return; }

        case "$_ans" in
            q|Q|"") menu_choice=0; return ;;
            *[!0-9]*) continue ;;
            *)
                if [ "$_ans" -ge 1 ] 2>/dev/null && [ "$_ans" -le "$_max" ]; then
                    menu_choice=$_ans
                    return
                fi
                ;;
        esac
    done
}

# GSC detection and WP read
detect_gsc() {
    _r="unknown"
    if command -v gsctool >/dev/null 2>&1; then
        _o=$(gsctool -a -v 2>/dev/null)
        if echo "$_o" | grep -qiE 'ti50|dauntless|0\.2\.'; then _r="ti50"; fi
        if echo "$_o" | grep -qiE 'cr50|h1|0\.6\.|0\.5\.'; then _r="cr50"; fi
    fi
    [ "$_r" = "unknown" ] && ls /dev/ti50* >/dev/null 2>&1 && _r="ti50"
    [ "$_r" = "unknown" ] && ls /dev/cr50* >/dev/null 2>&1 && _r="cr50"
    [ "$_r" = "unknown" ] && [ -d /sys/bus/platform/devices/ti50 ] && _r="ti50"
    [ "$_r" = "unknown" ] && [ -d /sys/bus/platform/devices/cr50 ] && _r="cr50"
    if [ "$_r" = "unknown" ] && [ -f /sys/class/tpm/tpm0/device/description ]; then
        grep -qi 'ti50' /sys/class/tpm/tpm0/device/description 2>/dev/null && _r="ti50"
        grep -qi 'cr50' /sys/class/tpm/tpm0/device/description 2>/dev/null && _r="cr50"
    fi
    echo "$_r"
}

check_wp() {
    crossystem wpsw_cur 2>/dev/null
}

# CR50 - Battery disconnect screen
cr50_battery_disconnect() {
    step_header "CR50 - Battery Disconnect"
    printf "  WP on CR50 is tied to battery presence. Pull the battery,\n"
    printf "  run on AC only, and wpsw_cur drops to 0.\n\n"
    printf "  %s1.%s Full power off - hold power button until dead.\n\n" "$BOLD" "$RST"
    printf "  %s2.%s Open the bottom cover.\n\n" "$BOLD" "$RST"
    printf "  %s3.%s %sDisconnect the battery connector.%s\n" "$BOLD" "$RST" "$R" "$RST"
    printf "     Pull straight up, don't yank the wires.\n\n"
    printf "  %s4.%s Plug in AC power.\n\n" "$BOLD" "$RST"
    printf "  %s5.%s Boot into VT2 and verify:\n" "$BOLD" "$RST"
    printf "     %scrossystem wpsw_cur%s  ->  %s0%s\n\n" "$DIM" "$RST" "$G" "$RST"
    sep
    printf "\n"
    warn "Do all flash ops before reconnecting the battery."
    printf "\n"

    _wp=$(check_wp)
    if [ "$_wp" = "0" ]; then
        ok "wpsw_cur=0  WP is off"
    else
        warn "wpsw_cur=${_wp}  WP still on - disconnect the battery first"
    fi
    printf "\n"
    pause
}

# CR50 - CCD via SuzyQ screen
cr50_ccd_suzyq() {
    step_header "CR50 - CCD via SuzyQ"
    printf "  Needs a SuzyQable and a second machine.\n"
    printf "  Debug port is usually the left USB-C, furthest from power.\n\n"
    printf "  %s1.%s Plug SuzyQ into the debug port.\n\n" "$BOLD" "$RST"
    printf "  %s2.%s On the host:\n" "$BOLD" "$RST"
    printf "     %sls /dev/ttyUSB*%s\n" "$DIM" "$RST"
    printf "     ttyUSB0=AP  ttyUSB1=EC  ttyUSB2=CR50\n\n"
    printf "  %s3.%s Open CR50 console on host:\n" "$BOLD" "$RST"
    printf "     %sminicom -D /dev/ttyUSB2 -b 115200%s\n\n" "$DIM" "$RST"
    printf "  %s4.%s In CR50 console:\n" "$BOLD" "$RST"
    printf "     %sccd%s             check current state\n" "$DIM" "$RST"
    printf "     %sccd open%s        start 5min PP window\n\n" "$DIM" "$RST"
    printf "  %s5.%s Press power button on target when CR50 asks.\n\n" "$BOLD" "$RST"
    printf "  %s6.%s After open:\n" "$BOLD" "$RST"
    printf "     %swp disable atboot%s    persists across reboots\n" "$DIM" "$RST"
    printf "     %swp disable%s           current session only\n\n" "$DIM" "$RST"
    printf "  %s7.%s Verify on target:\n" "$BOLD" "$RST"
    printf "     %scrossystem wpsw_cur%s  ->  %s0%s\n\n" "$DIM" "$RST" "$G" "$RST"
    sep
    printf "\n"
    warn "CCD open resets on 'ccd lock' or factory reset."
    printf "\n"
    pause
}

# CR50 - CCD via gsctool screen
cr50_ccd_gsctool() {
    step_header "CR50 - CCD via gsctool (on-device)"
    printf "  No cable needed. Uses the internal AP<->CR50 path.\n\n"
    printf "  %s1.%s Check state:\n" "$BOLD" "$RST"
    printf "     %sgsctool -a -I%s\n\n" "$DIM" "$RST"
    printf "  %s2.%s Start CCD open:\n" "$BOLD" "$RST"
    printf "     %sgsctool -a -o%s\n\n" "$DIM" "$RST"
    printf "  %s3.%s Press power button when prompted. 5min window.\n" "$BOLD" "$RST"
    printf "     Device may reboot - that's fine, come back to VT2.\n\n"
    printf "  %s4.%s Set flags:\n" "$BOLD" "$RST"
    printf "     %sgsctool -a -I AllowUnverifiedRo:always%s\n" "$DIM" "$RST"
    printf "     %sgsctool -a -I AllowAnySlot:always%s\n\n" "$DIM" "$RST"
    printf "  %s5.%s Kill WP:\n" "$BOLD" "$RST"
    printf "     %sgsctool -a -w 0%s\n\n" "$DIM" "$RST"
    printf "  %s6.%s Verify:\n" "$BOLD" "$RST"
    printf "     %scrossystem wpsw_cur%s  ->  %s0%s\n\n" "$DIM" "$RST" "$G" "$RST"
    sep
    printf "\n"

    _wp=$(check_wp)
    if [ "$_wp" = "0" ]; then
        ok "wpsw_cur=0  WP is off"
    else
        warn "wpsw_cur=${_wp}  WP on"
        printf "\n"
        if confirm "Run gsctool -a -o now?"; then
            warn "Device may reboot. Re-run sp.sh after."
            gsctool -a -o 2>&1 | while IFS= read -r l; do printf "  %s\n" "$l"; done
        fi
    fi
    printf "\n"
    pause
}

# CR50 - WP status screen
cr50_wp_status() {
    step_header "WP Status"
    _wp=$(check_wp)
    sep
    printf "  wpsw_cur = %s%s%s\n\n" "$BOLD" "$_wp" "$RST"
    if [ "$_wp" = "0" ]; then ok "WP off"; else warn "WP on"; fi
    printf "\n"
    if command -v gsctool >/dev/null 2>&1; then
        gsctool -a -I 2>/dev/null | grep -i 'wp\|write\|state' | while IFS= read -r l; do
            printf "  %s\n" "$l"
        done
    fi
    sep
    pause
}

# CR50 menu
menu_cr50() {
    while :; do
        numeric_menu "CR50 - WP Method" \
            "Battery disconnect" \
            "CCD via SuzyQ (needs 2nd machine + cable)" \
            "CCD via gsctool (on-device, no cable)" \
            "Check WP status" \
            "Back"
        case "$menu_choice" in
            1) cr50_battery_disconnect ;;
            2) cr50_ccd_suzyq ;;
            3) cr50_ccd_gsctool ;;
            4) cr50_wp_status ;;
            5|0) return ;;
        esac
    done
}

# TI50 - CCD via gsctool screen
ti50_ccd_gsctool() {
    step_header "TI50 - CCD via gsctool (on-device)"
    printf "  Battery disconnect does NOT work on TI50.\n"
    printf "  CCD open via gsctool is the main path.\n\n"
    printf "  %s1.%s Confirm TI50:\n" "$BOLD" "$RST"
    printf "     %sgsctool -a -v%s   look for dauntless or 0.2.x\n\n" "$DIM" "$RST"
    printf "  %s2.%s Check state:\n" "$BOLD" "$RST"
    printf "     %sgsctool -a -I%s\n\n" "$DIM" "$RST"
    printf "  %s3.%s Start CCD open:\n" "$BOLD" "$RST"
    printf "     %sgsctool -a -o%s\n\n" "$DIM" "$RST"
    printf "  %s4.%s Press power button as TI50 asks. 5min window.\n" "$BOLD" "$RST"
    printf "     %sDevice will reboot.%s Come back to VT2 after.\n\n" "$R" "$RST"
    printf "  %s5.%s Confirm open:\n" "$BOLD" "$RST"
    printf "     %sgsctool -a -I%s   look for State: Open\n\n" "$DIM" "$RST"
    printf "  %s6.%s Set flags:\n" "$BOLD" "$RST"
    printf "     %sgsctool -a -I AllowUnverifiedRo:always%s\n" "$DIM" "$RST"
    printf "     %sgsctool -a -I AllowAnySlot:always%s\n\n" "$DIM" "$RST"
    printf "  %s7.%s Kill WP:\n" "$BOLD" "$RST"
    printf "     %sgsctool -a -w 0%s\n\n" "$DIM" "$RST"
    printf "  %s8.%s Verify:\n" "$BOLD" "$RST"
    printf "     %scrossystem wpsw_cur%s  ->  %s0%s\n\n" "$DIM" "$RST" "$G" "$RST"
    sep
    printf "\n"

    _wp=$(check_wp)
    if [ "$_wp" = "0" ]; then
        ok "wpsw_cur=0  WP is off"
        printf "\n"
        gsctool -a -I 2>/dev/null | grep -i 'state\|ccd' | while IFS= read -r l; do printf "  %s\n" "$l"; done
    else
        warn "wpsw_cur=${_wp}  WP on"
        printf "\n"
        if confirm "Run gsctool -a -o now?"; then
            warn "Device will reboot. Re-run sp.sh after."
            gsctool -a -o 2>&1 | while IFS= read -r l; do printf "  %s\n" "$l"; done
        fi
    fi
    printf "\n"
    pause
}

# TI50 - CCD via SuzyQ screen
ti50_ccd_suzyq() {
    step_header "TI50 - CCD via SuzyQ"
    printf "  Same cable as CR50. Same port. Connects to Ti50 serial.\n\n"
    printf "  %s1.%s Plug SuzyQ into the debug USB-C port.\n" "$BOLD" "$RST"
    printf "     Check mrchromebox.tech for your board's port location.\n\n"
    printf "  %s2.%s On host:\n" "$BOLD" "$RST"
    printf "     %sls /dev/ttyUSB*%s   ttyUSB2 = GSC console\n\n" "$DIM" "$RST"
    printf "  %s3.%s Connect:\n" "$BOLD" "$RST"
    printf "     %sminicom -D /dev/ttyUSB2 -b 115200%s\n\n" "$DIM" "$RST"
    printf "  %s4.%s In TI50 console:\n" "$BOLD" "$RST"
    printf "     %sccd%s              check state\n" "$DIM" "$RST"
    printf "     %sccd open%s         start PP window\n\n" "$DIM" "$RST"
    printf "  %s5.%s Press power button on target when asked.\n\n" "$BOLD" "$RST"
    printf "  %s6.%s After open:\n" "$BOLD" "$RST"
    printf "     %swp disable atboot%s\n" "$DIM" "$RST"
    printf "     %sccd set AllowUnverifiedRo always%s\n" "$DIM" "$RST"
    printf "     %sccd set AllowAnySlot always%s\n\n" "$DIM" "$RST"
    sep
    printf "\n"
    pause
}

# TI50 - Verify state screen
ti50_verify() {
    step_header "TI50 - Verify State"
    sep
    _wp=$(check_wp)
    printf "  wpsw_cur = %s%s%s\n" "$BOLD" "$_wp" "$RST"
    if [ "$_wp" = "0" ]; then ok "WP off"; else warn "WP on"; fi
    printf "\n"

    if command -v gsctool >/dev/null 2>&1; then
        info "gsctool -a -I:"
        gsctool -a -I 2>/dev/null | while IFS= read -r l; do printf "  %s\n" "$l"; done
        printf "\n"
        info "gsctool -a -v:"
        gsctool -a -v 2>/dev/null | while IFS= read -r l; do printf "  %s\n" "$l"; done
    else
        warn "gsctool not found"
    fi
    sep
    pause
}

# TI50 vs CR50 differences screen
ti50_vs_cr50() {
    step_header "TI50 vs CR50"
    sep
    printf "  %-26s %sNO - does not work on TI50%s\n" "Battery disconnect WP" "$R" "$RST"
    printf "  %-26s %s\n" "CCD open"           "same - gsctool -a -o or console"
    printf "  %-26s %s\n" "Physical presence"  "still needed (power button)"
    printf "  %-26s %s\n" "Reboot during open" "TI50 reboots - expected"
    printf "  %-26s %s\n" "Version prefix"     "0.2.x=TI50  0.6.x=CR50"
    printf "  %-26s %s\n" "Device node"        "/dev/ti50  vs  /dev/cr50"
    printf "  %-26s %s\n" "gsctool flags"      "same flags, same syntax"
    printf "  %-26s %s\n" "SuzyQ"              "same cable, same process"
    sep
    printf "\n"
    pause
}

# TI50 menu
menu_ti50() {
    while :; do
        numeric_menu "TI50 (Dauntless) - WP Method" \
            "CCD via gsctool (on-device, no cable)" \
            "CCD via SuzyQ (needs 2nd machine + cable)" \
            "Verify CCD + WP state" \
            "TI50 vs CR50 differences" \
            "Back"
        case "$menu_choice" in
            1) ti50_ccd_gsctool ;;
            2) ti50_ccd_suzyq ;;
            3) ti50_verify ;;
            4) ti50_vs_cr50 ;;
            5|0) return ;;
        esac
    done
}

GSC_TYPE=""

# Startup detection screen
startup_detect() {
    step_header "Detecting GSC..."
    GSC_TYPE=$(detect_gsc)
    _wp=$(check_wp)

    if [ "$GSC_TYPE" = "cr50" ]; then
        ok "CR50 (H1)"
    elif [ "$GSC_TYPE" = "ti50" ]; then
        ok "TI50 (Dauntless)"
    else
        warn "GSC not detected - you'll pick manually"
    fi

    printf "\n"
    if [ "$_wp" = "0" ]; then
        ok "wpsw_cur=0  WP already off"
    else
        warn "wpsw_cur=${_wp:-?}  WP on"
    fi
    printf "\n"
    sleep 1
    pause
}

# Main menu
main() {
    startup_detect
    while :; do
        if [ "$GSC_TYPE" = "cr50" ]; then
            numeric_menu "Scribble Protection  [CR50]" \
                "CR50 write-protect methods" \
                "Exit"
            case "$menu_choice" in
                1) menu_cr50 ;;
                2|0) break ;;
            esac
        elif [ "$GSC_TYPE" = "ti50" ]; then
            numeric_menu "Scribble Protection  [TI50]" \
                "TI50 write-protect methods" \
                "Exit"
            case "$menu_choice" in
                1) menu_ti50 ;;
                2|0) break ;;
            esac
        else
            numeric_menu "Scribble Protection  [select chip]" \
                "CR50  (pre-2022, H1)" \
                "TI50  (post-2022, Dauntless)" \
                "Exit"
            case "$menu_choice" in
                1) GSC_TYPE="cr50"; menu_cr50 ;;
                2) GSC_TYPE="ti50"; menu_ti50 ;;
                3|0) break ;;
            esac
        fi
    done
    clear 2>/dev/null || printf "\n"
    printf "\n"
}

main
