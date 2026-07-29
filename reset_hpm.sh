#!/bin/bash
#==============================================================================
# HPM Reset Monitor — RoboParty EtherCAT CANFD Master
#
# 功能: 后台持续监测 HPM (roboto_usb4can, 1209:2323) 的 USB 枚举状态。
#       如果 USB 设备掉线 / 未枚举，通过 GPIO1_B7 脉冲复位 HPM。
#
# 设备:  roboto_usb4can (wentytwenty)
#       VID=1209, PID=2323
#       内核驱动: gs_usb
#
# GPIO1_B7 on RK3588:
#   sysfs GPIO 编号 = Bank1 * 32 + B(1) * 8 + 7 = 32 + 8 + 7 = 47
#   对应: /sys/class/gpio/gpio47
#
# 连接: RK3588 GPIO1_B7 → HPM RST 引脚 (高有效复位)
#==============================================================================

set -e

# ---- 可配置参数 (通过 systemd Environment= 覆盖) -------------------------------
RESET_GPIO="${RESET_GPIO:-47}"            # GPIO1_B7 sysfs 编号
CHECK_INTERVAL="${CHECK_INTERVAL:-5}"     # 检测间隔 (秒)
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"     # 连续失败次数阈值
RESET_HOLD_TIME="${RESET_HOLD_TIME:-0.5}" # 复位脉冲保持时间 (秒)
RESET_ACTIVE_HIGH="${RESET_ACTIVE_HIGH:-0}" # 1=高电平有效, 0=低电平有效
POST_RESET_WAIT="${POST_RESET_WAIT:-15}"  # 复位后等待时间 (秒)
LOG_TAG="hpm-reset-monitor"

# USB 设备匹配 (roboto_usb4can)
HPM_VID="${HPM_VID:-1209}"
HPM_PID="${HPM_PID:-2323}"

# ---- 日志函数 ----------------------------------------------------------------
log_msg() {
    local level="${1:-INFO}"
    shift
    logger -t "$LOG_TAG" -p "daemon.${level}" "$*"
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

# ---- sysfs GPIO 操作 ---------------------------------------------------------
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
            usleep 100000
        done
    fi

    if [ ! -d "$gpio_dir" ]; then
        log_msg "ERR" "无法 export GPIO ${RESET_GPIO} (GPIO1_B7), 检查设备树是否冲突"
        return 1
    fi

    echo "out" > "${gpio_dir}/direction" 2>/dev/null || true

    if [ "$RESET_ACTIVE_HIGH" -eq 1 ]; then
        echo 0 > "${gpio_dir}/value"
    else
        echo 1 > "${gpio_dir}/value"
    fi

    log_msg "INFO" "GPIO${RESET_GPIO} (GPIO1_B7) 初始化完成, 方向=out, 初始=无效电平"
    return 0
}

gpio_set_active() {
    local gpio_dir
    gpio_dir="$(gpio_path)"
    if [ ! -d "$gpio_dir" ]; then
        log_msg "ERR" "GPIO${RESET_GPIO} 不存在, 无法操作"
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

# ---- HPM USB 枚举检测 --------------------------------------------------------
# 返回 0 = HPM USB 设备正常枚举
# 返回 1 = HPM 设备未找到 (需要复位)
check_hpm_usb() {
    # 方法 1: lsusb — 最可靠
    if command -v lsusb &>/dev/null; then
        if lsusb -d "${HPM_VID}:${HPM_PID}" 2>/dev/null | grep -q .; then
            return 0
        fi
    fi

    # 方法 2: sysfs usb 设备树 — 无需额外工具
    # 遍历 /sys/bus/usb/devices/ 查找 idVendor/idProduct
    for dev in /sys/bus/usb/devices/*/; do
        local vid pid
        vid="$(cat "${dev}idVendor" 2>/dev/null || true)"
        pid="$(cat "${dev}idProduct" 2>/dev/null || true)"
        if [ "$vid" = "$HPM_VID" ] && [ "$pid" = "$HPM_PID" ]; then
            return 0
        fi
    done

    # 方法 3: /proc/bus/usb/devices (兼容旧内核)
    if [ -f /proc/bus/usb/devices ]; then
        if grep -q "Vendor=${HPM_VID}.*ProdID=${HPM_PID}" /proc/bus/usb/devices 2>/dev/null; then
            return 0
        fi
    fi

    log_msg "WARN" "HPM USB 设备 ${HPM_VID}:${HPM_PID} (roboto_usb4can) 未枚举"
    return 1
}

# ---- 复位操作 ----------------------------------------------------------------
pulse_reset() {
    log_msg "WARN" "=== 触发 HPM 复位: GPIO${RESET_GPIO} (GPIO1_B7) ==="

    gpio_set_active
    sleep "$RESET_HOLD_TIME"
    gpio_set_inactive

    log_msg "INFO" "复位脉冲完成 (${RESET_HOLD_TIME}s), 等待 ${POST_RESET_WAIT}s 让 HPM 重新枚举..."
    sleep "$POST_RESET_WAIT"
}

# ---- 清理 --------------------------------------------------------------------
cleanup() {
    log_msg "INFO" "HPM Reset Monitor 正在退出..."
    gpio_set_inactive 2>/dev/null || true
    if [ -d "$(gpio_path)" ]; then
        echo "$RESET_GPIO" > /sys/class/gpio/unexport 2>/dev/null || true
    fi
    log_msg "INFO" "HPM Reset Monitor 已停止"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# ---- 主循环 ------------------------------------------------------------------
main() {
    log_msg "INFO" "=============================================="
    log_msg "INFO" "HPM Reset Monitor 启动"
    log_msg "INFO" "  HPM 设备:  USB ${HPM_VID}:${HPM_PID} (roboto_usb4can)"
    log_msg "INFO" "  GPIO1_B7  → sysfs GPIO${RESET_GPIO}"
    log_msg "INFO" "  检测间隔:  ${CHECK_INTERVAL}s"
    log_msg "INFO" "  失败阈值:  ${FAIL_THRESHOLD} 次连续失败后复位"
    log_msg "INFO" "  复位脉宽:  ${RESET_HOLD_TIME}s (${RESET_ACTIVE_HIGH:-高}电平有效)"
    log_msg "INFO" "  复位后等待: ${POST_RESET_WAIT}s"
    log_msg "INFO" "=============================================="

    if ! gpio_setup; then
        log_msg "ERR" "GPIO 初始化失败, 退出"
        exit 1
    fi

    local fail_count=0

    while true; do
        if check_hpm_usb; then
            if [ "$fail_count" -gt 0 ]; then
                log_msg "INFO" "HPM USB 已恢复枚举 (之前连续失败 ${fail_count} 次)"
            fi
            fail_count=0
        else
            fail_count=$((fail_count + 1))
            log_msg "WARN" "HPM USB 未枚举 (${fail_count}/${FAIL_THRESHOLD})"

            if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                log_msg "ERR" "连续 ${FAIL_THRESHOLD} 次未检测到 HPM USB 设备 — 执行硬件复位"
                pulse_reset
                fail_count=0
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

main "$@"