#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
app_dir="$project_dir/dist/PrettyTerm Beta.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
build_dir="$project_dir/.build"

mkdir -p "$macos_dir" "$resources_dir" "$build_dir"

clang \
  -fobjc-arc \
  -fmodules \
  -O2 \
  -Wall -Wextra \
  -mmacosx-version-min=13.0 \
  -framework AppKit \
  -framework WebKit \
  -framework UniformTypeIdentifiers \
  "$project_dir/Sources/PTAgentState.m" \
  "$project_dir/Sources/PTUsageMetrics.m" \
  "$project_dir/Sources/PrettyTerm.m" \
  -o "$macos_dir/PrettyTerm"

cp "$project_dir/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Resources/tex-svg.js" "$resources_dir/tex-svg.js"
cp "$project_dir/Resources/index.html" "$resources_dir/index.html"
cp "$project_dir/Resources/PrettyTerm.icns" "$resources_dir/PrettyTerm.icns"
if [[ -f "$project_dir/Resources/app.js" ]]; then
  cp "$project_dir/Resources/app.js" "$resources_dir/app.js"
fi

# 注意：ad-hoc 签名（--sign -）每次重新构建都会换 cdhash，
# 这会让系统认为这是"新 app"，之前授予的"允许 PrettyTerm 控制 Terminal"权限要重新弹窗。
# 想要跨重建保留权限，需要在钥匙串里建一个自签名证书，改用 --sign "证书名"。
codesign --force --sign - "$app_dir"

# Finder 会长时间缓存同一路径下旧 bundle 的占位图标。构建完成后主动更新
# bundle 时间戳并重新交给 LaunchServices 注册，避免新 icns 已在包内却仍显示默认图标。
touch "$app_dir"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$lsregister" ]]; then
  "$lsregister" -f "$app_dir" >/dev/null 2>&1 || true
fi
echo "Built: $app_dir"
