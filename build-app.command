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
  "$project_dir/Sources/PTFilePreview.m" \
  "$project_dir/Sources/PTGitReview.m" \
  "$project_dir/Sources/PTUsageMetrics.m" \
  "$project_dir/Sources/PrettyTerm.m" \
  -o "$macos_dir/PrettyTerm"

cp "$project_dir/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Resources/tex-svg.js" "$resources_dir/tex-svg.js"
cp "$project_dir/Resources/index.html" "$resources_dir/index.html"
cp "$project_dir/Resources/PrettyTerm.icns" "$resources_dir/PrettyTerm.icns"
cp "$project_dir/Resources/PrettyTermLogo.png" "$resources_dir/PrettyTermLogo.png"
if [[ -f "$project_dir/Resources/app.js" ]]; then
  cp "$project_dir/Resources/app.js" "$resources_dir/app.js"
fi
for localization in zh-Hans.lproj en.lproj; do
  if [[ -d "$project_dir/Resources/$localization" ]]; then
    ditto "$project_dir/Resources/$localization" "$resources_dir/$localization"
  fi
done

# 正式发布时传入 Developer ID Application 身份：
# PRETTYTERM_SIGNING_IDENTITY="Developer ID Application: ..." ./build-app.command
# 未提供身份时保留可复现的本地 ad-hoc 构建，但仍启用 Hardened Runtime 与最小权限。
signing_identity="${PRETTYTERM_SIGNING_IDENTITY:--}"
codesign_args=(
  --force
  --options runtime
  --entitlements "$project_dir/PrettyTerm.entitlements"
  --sign "$signing_identity"
)
if [[ "$signing_identity" != "-" ]]; then
  codesign_args+=(--timestamp)
else
  codesign_args+=(--timestamp=none)
  # 本地 ad-hoc 的默认身份只含每次变化的 cdhash，重构建会使辅助功能授权失效。
  # 指定稳定的 bundle 身份，使重新授予的权限继续匹配后续本地构建。
  local_bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$project_dir/Info.plist")"
  codesign_args+=(--requirements "=designated => identifier \"$local_bundle_identifier\"")
  print -u2 "warning: ad-hoc signing is for local beta builds; Developer ID is required for stable distributed trust"
fi
codesign "${codesign_args[@]}" "$app_dir"

# Finder 会长时间缓存同一路径下旧 bundle 的占位图标。构建完成后主动更新
# bundle 时间戳并重新交给 LaunchServices 注册，避免新 icns 已在包内却仍显示默认图标。
touch "$app_dir"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$lsregister" ]]; then
  "$lsregister" -f "$app_dir" >/dev/null 2>&1 || true
fi
echo "Built: $app_dir"
