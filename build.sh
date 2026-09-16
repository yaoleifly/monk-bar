#!/bin/bash
# 编译 + 打包 Monk 用量.app（Universal 2 架构，原生支持 macOS 13 至 macOS Tahoe 27+）
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MonkUsage.app"
BIN="$APP/Contents/MacOS/monk-usage"
RES="$APP/Contents/Resources"

# 1. 生成 App 图标 (.icns 与高清素材)
python3 generate_icons.py

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$RES"

# 2. 拷贝图标素材至 App Bundle Resources
cp build/AppIcon.icns "$RES/AppIcon.icns"
cp build/AppIcon_128.png "$RES/AppIcon_128.png"

# 3. 编译跨架构 Universal 2 二进制 (arm64 + x86_64)
# 支持 Apple Silicon (M1/M2/M3/M4/M5) 与 Intel，原生兼容 macOS 13+ 至 macOS Tahoe (macOS 27+)
echo "编译 Universal 2 通用二进制 (arm64 + x86_64)..."
swiftc -target arm64-apple-macos13.0 -O -o "/tmp/monk-arm64" main.swift
swiftc -target x86_64-apple-macos13.0 -O -o "/tmp/monk-x86_64" main.swift
lipo -create -output "$BIN" "/tmp/monk-arm64" "/tmp/monk-x86_64"
rm -f "/tmp/monk-arm64" "/tmp/monk-x86_64"

# 4. 生成规范 Info.plist（包含 AppIcon、LSUIElement、macOS Tahoe 现代化渲染属性）
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>monk-usage</string>
  <key>CFBundleIdentifier</key><string>party.monk.usage</string>
  <key>CFBundleName</key><string>Monk 用量</string>
  <key>CFBundleDisplayName</key><string>Monk 用量</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>1.4.0</string>
  <key>CFBundleVersion</key><string>140</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSSupportsSuddenTermination</key><true/>
  <key>NSRequiresAquaSystemAppearance</key><false/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Yaolei. All rights reserved.</string>
</dict>
</plist>
PLIST

# 5. 本地 ad-hoc 签名
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

# 6. 执行内置自检（保证核心逻辑与数据流完好）
"$BIN" --selfcheck

echo
echo "✓ 已成功构建并打包 Universal 2 应用：$APP"
echo "  - 架构：Universal 2 (arm64 + x86_64)，原生适配 macOS Tahoe (macOS 27) 及早期版本"
echo "  - 图标：根据 monk.party 冥想火焰与 Apple HIG 设计，已内嵌 AppIcon.icns"
echo "  - 状态栏：内嵌 18x18 矢量自适应模板图标，支持 ⌘-Drag 自定义排列与防抖等宽排版"
echo "  - 设置界面：SwiftUI 原生 Bento Grid 风格，支持即时配置与查看限流状态"
echo
echo "启动菜单栏：       open $APP"
echo "命令行一行输出：   $BIN --text"
