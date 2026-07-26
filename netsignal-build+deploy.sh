#!/bin/bash
#===============================================================================
# NetSignal Build + Deploy Pipeline
# 编译源码 → 打包 DMG → 杀掉旧进程 → 卸载旧版 → 安装新版 → 启动
#===============================================================================
set -euo pipefail

# --- Config ------------------------------------------------------------------
APP_NAME="NetSignal"
APP_PATH="/Applications/${APP_NAME}.app"
VERSION="${1:-}"              # 可传版本号，如: ./netsignal-build+deploy.sh 1.0.2

# --- Functions ---------------------------------------------------------------
log()   { echo "[$(date '+%H:%M:%S')] $*"; }
err()   { echo "[ERROR] $*" >&2; exit 1; }
ask_sudo() {
    # 先试探是否需要 sudo
    if [ ! -w "/Applications" ]; then
        log "需要管理员权限来安装到 /Applications"
        sudo -v || err "权限获取失败"
    fi
}

cleanup() {
    if [ -d "/Volumes/${APP_NAME}" ]; then
        hdiutil detach "/Volumes/${APP_NAME}" -quiet 2>/dev/null || true
    fi
    rm -rf /tmp/netsignal-staging 2>/dev/null || true
}

# --- Pre-checks --------------------------------------------------------------
trap cleanup EXIT

# 切换到项目目录
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

if [ ! -f "Package.swift" ]; then
    err "未找到 Package.swift，请在 NetSignal 项目根目录运行"
fi

# 如果未传版本号，从现有的 .dmg 推断或默认
if [ -z "$VERSION" ]; then
    # 尝试从已有的 .dmg 文件名提取
    LATEST_DMG=$(ls -t NetSignal-*.dmg 2>/dev/null | head -1)
    if [ -n "$LATEST_DMG" ]; then
        VERSION=$(echo "$LATEST_DMG" | sed 's/NetSignal-\(.*\)\.dmg/\1/')
        log "从 DMG 文件推断版本号: $VERSION"
    else
        # 从 Package.swift 或 Info.plist 模板取
        VERSION=$(grep 'let version' Sources/NetSignal/App.swift 2>/dev/null | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "1.0.0")
        log "使用默认版本号: $VERSION"
    fi
fi

DMG_NAME="NetSignal-${VERSION}.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"

# =============================================================================
# STEP 1: 编译 Release 版本
# =============================================================================
log "========== 步骤 1/6: 编译 ${APP_NAME} v${VERSION} =========="
swift build --disable-sandbox -c release
log "编译完成 ✓"

# =============================================================================
# STEP 2: 打包为 .app 并签名
# =============================================================================
log "========== 步骤 2/6: 打包 .app 并签名 =========="
rm -rf "${APP_NAME}.app"
mkdir -p "${APP_NAME}.app/Contents/MacOS"
mkdir -p "${APP_NAME}.app/Contents/Resources"

cp ".build/release/${APP_NAME}" "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

# Info.plist
sed "s/VERSION_PLACEHOLDER/${VERSION}/g" <<'PLIST' > "${APP_NAME}.app/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>NetSignal</string>
    <key>CFBundleExecutable</key>
    <string>NetSignal</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.netsignal.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>NetSignal</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>VERSION_PLACEHOLDER</string>
    <key>CFBundleVersion</key>
    <string>VERSION_PLACEHOLDER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 NetSignal. All rights reserved.</string>
</dict>
</plist>
PLIST

# Icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "${APP_NAME}.app/Contents/Resources/"
fi
if [ -f "Resources/AppIcon.png" ]; then
    cp Resources/AppIcon.png "${APP_NAME}.app/Contents/Resources/"
fi

# Ad-hoc 签名
codesign --force --deep --sign - "${APP_NAME}.app" 2>/dev/null || log "⚠ 签名失败，不影响本地安装"
log ".app 打包完成 ✓"

# =============================================================================
# STEP 3: 生成 .dmg
# =============================================================================
log "========== 步骤 3/6: 生成 DMG =========="
STAGING="/tmp/netsignal-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "${APP_NAME}.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# 若旧 .dmg 存在则删除
[ -f "$DMG_PATH" ] && rm "$DMG_PATH"

hdiutil create -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"

rm -rf "${APP_NAME}.app" "$STAGING"
log "DMG 生成: $DMG_PATH ✓"

# =============================================================================
# STEP 4: 杀掉旧进程
# =============================================================================
log "========== 步骤 4/6: 关闭旧版本 =========="
if pgrep -x "${APP_NAME}" &>/dev/null; then
    log "${APP_NAME} 正在运行，强制退出..."
    pkill -9 -x "${APP_NAME}" 2>/dev/null || true
    sleep 1
    pgrep -x "${APP_NAME}" &>/dev/null && osascript -e "tell app \"${APP_NAME}\" to quit" 2>/dev/null || true
    sleep 1
    log "旧进程已关闭 ✓"
fi

# =============================================================================
# STEP 5: 卸载旧版 → 安装新版
# =============================================================================
log "========== 步骤 5/6: 卸载旧版 → 安装新版 =========="
ask_sudo

if [ -d "$APP_PATH" ]; then
    log "删除旧版: $APP_PATH"
    sudo rm -rf "$APP_PATH"
    log "旧版已卸载 ✓"
fi

log "挂载 DMG ..."
hdiutil attach "$DMG_PATH" -nobrowse -quiet

VOL="/Volumes/${APP_NAME}"
[ ! -d "$VOL" ] && VOL=$(hdiutil info | grep "/Volumes/${APP_NAME}" | head -1 | awk '{$1=$2=$3=""; print $0}' | xargs)

log "复制到 /Applications ..."
sudo cp -R "${VOL}/${APP_NAME}.app" "/Applications/"
log "新版本已安装 ✓"

sleep 1
hdiutil detach "$VOL" -quiet 2>/dev/null || true

# =============================================================================
# STEP 6: 启动
# =============================================================================
log "========== 步骤 6/6: 启动 ${APP_NAME} =========="
open -a "${APP_NAME}"
log "=================================================="
log "🎉 NetSignal v${VERSION} 编译 → 安装 → 启动 全流程完成！"
log "DMG 文件: $DMG_PATH"
