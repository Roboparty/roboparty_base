#!/bin/bash
#==============================================================================
# HPM Reset Monitor — RoboParty EtherCAT CANFD Master
#
# Continuously monitors the USB enumeration state of the HPM device
# (roboto_usb4can, 1209:2323). If the USB device drops offline or fails
# to enumerate, pulses GPIO1_B7 to hardware-reset the HPM.
#
# Device:  roboto_usb4can (wentytwenty)
#          VID=1209, PID=2323
#          Kernel driver: gs_usb
#
# GPIO1_B7 on RK3588:
#   sysfs GPIO number = Bank1 * 32 + B(1) * 8 + 7 = 32 + 8 + 7 = 47
#   Maps to: /sys/class/gpio/gpio47
#
# Connection: RK3588 GPIO1_B7 → HPM RST pin (active-high reset)
#==============================================================================

set -e

# ---- Configurable parameters (overridable via systemd Environment=) ----------
RESET_GPIO="${RESET_GPIO:-47}"              # GPIO1_B7 sysfs number
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"       # Check interval (seconds)
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"       # Consecutive failure threshold
RESET_HOLD_TIME="${RESET_HOLD_TIME:-0.5}"   # Reset pulse duration (seconds)
RESET_ACTIVE_HIGH="${RESET_ACTIVE_HIGH:-0}" # 1=active-high, 0=active-low
POST_RESET_WAIT="${POST_RESET_WAIT:-15}"    # Wait time after reset (seconds)
LOG_TAG="hpm-reset-monitor"

# USB device identification (roboto_usb4can)
HPM_VID="${HPM_VID:-1209}"
HPM_PID="${HPM_PID:-2323}"

# ---- Logging -----------------------------------------------------------------
log_msg() {
    local level="${1:-INFO}"
    shift
    logger -t "$LOG_TAG" -p "daemon.${level}" "$*"
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

# ---- sysfs GPIO operations ---------------------------------------------------
gpio_path() {
    echo "/sys/class/gpio/gpio${RESET_GPIO}"
}

gpio_setup() {
    local gpio_dir
    gpio_dir="$(gpio_path)"

    if [ ! -d "$gpio_dir" ]; then
        echo "$RESET_GPIO" > /sys/class/gpio/export 2>/dev/null || true
        for _ in $(seq 1 10); do
            [ -d "$gpio_dir" ] && break
            sleep 0.1
        done
    fi

    if [ ! -d "$gpio_dir" ]; then
        log_msg "ERR" "Cannot export GPIO ${RESET_GPIO} (GPIO1_B7), check device tree conflicts"
        return 1
    fi

    echo "out" > "${gpio_dir}/direction" 2>/dev/null || true

    if [ "$RESET_ACTIVE_HIGH" -eq 1 ]; then
        echo 0 > "${gpio_dir}/value"
    else
        echo 1 > "${gpio_dir}/value"
    fi

    log_msg "INFO" "GPIO${RESET_GPIO} (GPIO1_B7) initialized, direction=out, initial=inactive"
    return 0
}

gpio_set_active() {
    local gpio_dir
    gpio_dir="$(gpio_path)"
    if [ ! -d "$gpio_dir" ]; then
        log_msg "ERR" "GPIO${RESET_GPIO} not found, cannot operate"
        return 1
    fi
    if [ "$RESET_ACTIVE_HIGH" -eq 1 ]; then
        echo 1 > "${gpio_dir}/value"
    else
        echo 0 > "${gpio_dir}/value"
    fi
}

gpio_set_inactive() {
    local gpio_dir
    gpio_dir="$(gpio_path)"
    if [ ! -d "$gpio_dir" ]; then
        return 1
    fi
    if [ "$RESET_ACTIVE_HIGH" -eq 1 ]; then
        echo 0 > "${gpio_dir}/value"
    else
        echo 1 > "${gpio_dir}/value"
    fi
}

# ---- HPM USB enumeration detection -------------------------------------------
# Returns 0 = HPM USB device enumerated
# Returns 1 = HPM device not found (needs reset)
check_hpm_usb() {
    # Method 1: lsusb — most reliable
    if command -v lsusb &>/dev/null; then
        if lsusb -d "${HPM_VID}:${HPM_PID}" 2>/dev/null | grep -q .; then
            return 0
        fi
    fi

    # Method 2: sysfs USB device tree — no extra tools needed
    # Search /sys/bus/usb/devices/ for matching idVendor/idProduct
    for dev in /sys/bus/usb/devices/*/; do
        local vid pid
        vid="$(cat "${dev}idVendor" 2>/dev/null || true)"
        pid="$(cat "${dev}idProduct" 2>/dev/null || true)"
        if [ "$vid" = "$HPM_VID" ] && [ "$pid" = "$HPM_PID" ]; then
            return 0
        fi
    done

    # Method 3: /proc/bus/usb/devices (legacy kernel compatibility)
    if [ -f /proc/bus/usb/devices ]; then
        if grep -q "Vendor=${HPM_VID}.*ProdID=${HPM_PID}" /proc/bus/usb/devices 2>/dev/null; then
            return 0
        fi
    fi

    log_msg "WARN" "HPM USB device ${HPM_VID}:${HPM_PID} (roboto_usb4can) not enumerated"
    return 1
}

# ---- Reset operation ---------------------------------------------------------
pulse_reset() {
    log_msg "WARN" "=== Triggering HPM reset: GPIO${RESET_GPIO} (GPIO1_B7) ==="

    gpio_set_active
    sleep "$RESET_HOLD_TIME"
    gpio_set_inactive

    log_msg "INFO" "Reset pulse complete (${RESET_HOLD_TIME}s), waiting ${POST_RESET_WAIT}s for HPM re-enumeration..."
    sleep "$POST_RESET_WAIT"
}

# ---- Cleanup -----------------------------------------------------------------
cleanup() {
    log_msg "INFO" "HPM Reset Monitor shutting down..."
    gpio_set_inactive 2>/dev/null || true
    if [ -d "$(gpio_path)" ]; then
        echo "$RESET_GPIO" > /sys/class/gpio/unexport 2>/dev/null || true
    fi
    log_msg "INFO" "HPM Reset Monitor stopped"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# ---- Main loop ---------------------------------------------------------------
main() {
    log_msg "INFO" "=============================================="
    log_msg "INFO" "HPM Reset Monitor starting"
    log_msg "INFO" "  HPM device:      USB ${HPM_VID}:${HPM_PID} (roboto_usb4can)"
    log_msg "INFO" "  GPIO1_B7      →  sysfs GPIO${RESET_GPIO}"
    log_msg "INFO" "  Check interval:   ${CHECK_INTERVAL}s"
    log_msg "INFO" "  Failure threshold: ${FAIL_THRESHOLD} consecutive failures"
    log_msg "INFO" "  Reset pulse:      ${RESET_HOLD_TIME}s (active-${RESET_ACTIVE_HIGH:-high})"
    log_msg "INFO" "  Post-reset wait:  ${POST_RESET_WAIT}s"
    log_msg "INFO" "=============================================="

    if ! gpio_setup; then
        log_msg "ERR" "GPIO initialization failed, exiting"
        exit 1
    fi

    local fail_count=0

    while true; do
        if check_hpm_usb; then
            if [ "$fail_count" -gt 0 ]; then
                log_msg "INFO" "HPM USB re-enumerated (${fail_count} previous failure(s))"
            fi
            fail_count=0
        else
            fail_count=$((fail_count + 1))
            log_msg "WARN" "HPM USB not enumerated (${fail_count}/${FAIL_THRESHOLD})"

            if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                log_msg "ERR" "${FAIL_THRESHOLD} consecutive HPM USB detection failures — triggering hardware reset"
                pulse_reset
                fail_count=0
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

main "$@"
