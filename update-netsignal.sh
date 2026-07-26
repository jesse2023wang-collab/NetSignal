#!/bin/bash
#===============================================================================
# NetSignal Update Script
# Description: Unmount -> Kill -> Remove Old -> Copy New -> Launch
# Usage:       ./update-netsignal.sh /path/to/NetSignal-X.Y.Z.dmg
# Author:      Generated for NetSignal project
# Date:        2026-07-16
#===============================================================================

set -euo pipefail

# --- Config ------------------------------------------------------------------
APP_NAME="NetSignal"
APP_PATH="/Applications/${APP_NAME}.app"
DMG_PATH="${1:-}"

# --- Functions ---------------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }
cleanup() {
    if [ -d "/Volumes/${APP_NAME}" ]; then
        log "卸除残留镜像..."
        hdiutil detach "/Volumes/${APP_NAME}" -quiet 2>/dev/null || true
    fi
}

# --- Pre-checks --------------------------------------------------------------
trap cleanup EXIT

# Check DMG argument
if [ -z "$DMG_PATH" ]; then
    err "用法: $0 /path/to/${APP_NAME}-X.Y.Z.dmg"
fi
if [ ! -f "$DMG_PATH" ]; then
    err "文件不存在: $DMG_PATH"
fi

# --- Step 1: Kill running app ------------------------------------------------
log "检查 ${APP_NAME} 是否在运行..."
if pgrep -x "${APP_NAME}" &>/dev/null; then
    log "检测到 ${APP_NAME} 正在运行，强制退出..."
    pkill -9 -x "${APP_NAME}" 2>/dev/null || true
    sleep 1
    # 二次确认
    if pgrep -x "${APP_NAME}" &>/dev/null; then
        log "通过 osascript 发送退出指令..."
        osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
        sleep 1
        pkill -9 -x "${APP_NAME}" 2>/dev/null || true
    fi
    log "${APP_NAME} 已退出 ✓"
fi

# --- Step 2: Mount DMG -------------------------------------------------------
log "挂载 DMG: $(basename "$DMG_PATH")"
hdiutil attach "$DMG_PATH" -nobrowse -quiet 2>/dev/null || {
    err "挂载 DMG 失败"
}

VOLUME_PATH="/Volumes/${APP_NAME}"
if [ ! -d "$VOLUME_PATH" ]; then
    # Fallback: 扫描挂载卷
    VOLUME_PATH=$(hdiutil info | grep "/Volumes/${APP_NAME}" | head -1 | awk '{print $NF}')
fi
log "镜像路径: ${VOLUME_PATH:-/Volumes/${APP_NAME}} ✓"

# --- Step 3: Remove old version ----------------------------------------------
if [ -d "$APP_PATH" ]; then
    log "删除旧版本: ${APP_PATH}"
    rm -rf "$APP_PATH" || {
        log "无权限删除，尝试 sudo..."
        sudo rm -rf "$APP_PATH" || err "删除旧版本失败，请手动执行: sudo rm -rf ${APP_PATH}"
    }
    log "旧版本已删除 ✓"
fi

# --- Step 4: Copy new app ----------------------------------------------------
log "安装新版本..."
cp -R "${VOLUME_PATH:-/Volumes/${APP_NAME}}/${APP_NAME}.app" "/Applications/" || {
    log "无权限复制，尝试 sudo..."
    sudo cp -R "${VOLUME_PATH:-/Volumes/${APP_NAME}}/${APP_NAME}.app" "/Applications/" || {
        err "安装失败"
    }
}
log "新版本已安装到 /Applications ✓"

# --- Step 5: Eject DMG -------------------------------------------------------
log "卸除 DMG..."
hdiutil detach "${VOLUME_PATH:-/Volumes/${APP_NAME}}" -quiet 2>/dev/null || true
log "DMG 已卸除 ✓"

# --- Step 6: Launch ----------------------------------------------------------
log "启动 ${APP_NAME}..."
open -a "${APP_NAME}" &
log "✅ 更新完成！${APP_NAME} 已启动！"
