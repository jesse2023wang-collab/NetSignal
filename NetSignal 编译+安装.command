#!/bin/bash
#===============================================================================
# NetSignal 编译 → 安装 → 启动 一键脚本（双击运行版）
# 使用方法：双击此文件，或终端执行
# 可选参数：./netsignal-build+deploy.command 1.0.5
#===============================================================================

# 确保在项目目录
cd "$(cd "$(dirname "$0")" && pwd)"

APP_NAME="NetSignal"
APP_PATH="/Applications/${APP_NAME}.app"
VERSION="${1:-}"

log()   { echo "[$(date '+%H:%M:%S')] $*"; }
err()   { echo "[ERROR] $*" >&2; }

cleanup() {
    [ -d "/Volumes/${APP_NAME}" ] && hdiutil detach "/Volumes/${APP_NAME}" -quiet 2>/dev/null || true
    rm -rf /tmp/netsignal-staging 2>/dev/null || true
}

trap cleanup EXIT

echo ""
echo "=============================================="
echo "  NetSignal 编译 → 安装 → 启动"
echo "=============================================="

# --- 版本号 ---
[ ! -f "Package.swift" ] && { err "请在 NetSignal 项目目录运行"; read -p "按回车键退出..."; exit 1; }

if [ -z "$VERSION" ]; then
    LATEST_DMG=$(ls -t NetSignal-*.dmg 2>/dev/null | head -1)
    if [ -n "$LATEST_DMG" ]; then
        VERSION=$(echo "$LATEST_DMG" | sed 's/NetSignal-\(.*\)\.dmg/\1/')
    else
        VERSION=$(sed -n 's/.*CFBundleShortVersionString.*<string>\(.*\)<\/string>.*/\1/p' Sources/NetSignal/Resources/Info.plist 2>/dev/null || echo "1.0.0")
    fi
    log "版本号: $VERSION"
fi

DMG_PATH="$PWD/NetSignal-${VERSION}.dmg"

# ====== 1. 编译 ======
echo ""
log "===== 1/6: 编译 ====="
swift build --disable-sandbox -c release || { err "编译失败"; read -p "按回车键退出..."; exit 1; }
log "✓ 编译完成"

# ====== 2. 打包 .app ======
echo ""
log "===== 2/6: 打包 .app ====="
rm -rf "${APP_NAME}.app"
mkdir -p "${APP_NAME}.app/Contents/MacOS" "${APP_NAME}.app/Contents/Resources"
cp ".build/release/${APP_NAME}" "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

sed "s/VERSION_PLACEHOLDER/${VERSION}/g" <<'PLIST' > "${APP_NAME}.app/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>NetSignal</string>
    <key>CFBundleExecutable</key><string>NetSignal</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.netsignal.app</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>NetSignal</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>VERSION_PLACEHOLDER</string>
    <key>CFBundleVersion</key><string>VERSION_PLACEHOLDER</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2025 NetSignal.</string>
</dict>
</plist>
PLIST

[ -f "Resources/AppIcon.icns" ] && cp Resources/AppIcon.icns "${APP_NAME}.app/Contents/Resources/"
[ -f "Resources/AppIcon.png" ]  && cp Resources/AppIcon.png  "${APP_NAME}.app/Contents/Resources/"
codesign --force --deep --sign - "${APP_NAME}.app" 2>/dev/null || log "⚠ 签名跳过"
log "✓ .app 打包完成"

# ====== 3. 生成 .dmg ======
echo ""
log "===== 3/6: 生成 DMG ====="
STAGING="/tmp/netsignal-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "${APP_NAME}.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "${APP_NAME} ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "${APP_NAME}.app" "$STAGING"
log "✓ DMG: $DMG_PATH"

# ====== 4. 关旧进程 ======
echo ""
log "===== 4/6: 关闭旧版本 ====="
if pgrep -x "${APP_NAME}" &>/dev/null; then
    log "正在关闭 ${APP_NAME} ..."
    pkill -9 -x "${APP_NAME}" 2>/dev/null || true
    sleep 1
    log "✓ 已关闭"
fi

# ====== 5. 安装 ======
echo ""
log "===== 5/6: 卸载旧版 → 安装新版 ====="
if [ ! -w "/Applications" ]; then
    echo "⚠ 需要管理员权限，请输入密码："
    sudo -v || { err "权限获取失败"; read -p "按回车键退出..."; exit 1; }
fi
[ -d "$APP_PATH" ] && sudo rm -rf "$APP_PATH" && log "✓ 旧版已卸载"
hdiutil attach "$DMG_PATH" -nobrowse -quiet
VOL="/Volumes/${APP_NAME}"
[ ! -d "$VOL" ] && VOL=$(hdiutil info | grep "/Volumes/${APP_NAME}" | head -1 | awk '{$1=$2=$3=""; print $0}' | xargs)
sudo cp -R "${VOL}/${APP_NAME}.app" "/Applications/"
hdiutil detach "$VOL" -quiet 2>/dev/null || true
log "✓ 安装完成"

# ====== 6. 启动 ======
echo ""
log "===== 6/6: 启动 ====="
open -a "${APP_NAME}"
echo ""
echo "=============================================="
echo "🎉 NetSignal v${VERSION} 完成！"
echo "=============================================="
echo ""
read -p "按回车键退出..."
