#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/PrettyTerm Beta.app"
contents_dir="$app_dir/Contents"
resources_dir="$contents_dir/Resources"
expected_send_hash="1b89cc7a9a8a65ee322a9b0c939ad7fba10cef551c1233406a76f8fce3e76c46"
send_start="$(
  awk '/^\/\/ 在同一段 AppleScript 执行内完成/ { print NR; exit }' \
    "$project_dir/Sources/PrettyTerm.m"
)"
[[ "$send_start" == <-> ]] || {
  print -u2 "sendToTerminal protection marker is missing"
  exit 1
}
send_end=$((send_start + 49))
actual_send_hash="$(
  sed -n "${send_start},${send_end}p" "$project_dir/Sources/PrettyTerm.m" |
    shasum -a 256 |
    awk '{print $1}'
)"

if [[ "$actual_send_hash" != "$expected_send_hash" ]]; then
  print -u2 "sendToTerminal protection changed: expected $expected_send_hash, got $actual_send_hash"
  exit 1
fi

if [[ -f "$project_dir/Tests/test_renderer.js" ]]; then
  node "$project_dir/Tests/test_renderer.js"
fi
if [[ -f "$project_dir/Tests/test_appearance.js" ]]; then
  node "$project_dir/Tests/test_appearance.js"
fi
if [[ -f "$project_dir/Tests/test_floating_window.js" ]]; then
  node "$project_dir/Tests/test_floating_window.js"
fi

mkdir -p "$project_dir/.build"
clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -framework Foundation \
  "$project_dir/Sources/PTAgentState.m" \
  "$project_dir/Tests/PTAgentStateTests.m" \
  -o "$project_dir/.build/PTAgentStateTests"
"$project_dir/.build/PTAgentStateTests"

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -framework Foundation \
  -I"$project_dir/Sources" \
  "$project_dir/Sources/PTUsageMetrics.m" \
  "$project_dir/Tests/PTUsageMetricsTests.m" \
  -o "$project_dir/.build/PTUsageMetricsTests"
"$project_dir/.build/PTUsageMetricsTests"

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -Dmain=PrettyTermApplicationMain \
  -c "$project_dir/Sources/PrettyTerm.m" \
  -o "$project_dir/.build/PrettyTermForInteractionTests.o"
clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -c "$project_dir/Tests/PTWindowInteractionTests.m" \
  -o "$project_dir/.build/PTWindowInteractionTests.o"
clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -framework AppKit \
  -framework ApplicationServices \
  -framework WebKit \
  -framework UniformTypeIdentifiers \
  "$project_dir/.build/PrettyTermForInteractionTests.o" \
  "$project_dir/.build/PTWindowInteractionTests.o" \
  "$project_dir/Sources/PTAgentState.m" \
  "$project_dir/Sources/PTUsageMetrics.m" \
  -o "$project_dir/.build/PTWindowInteractionTests"
"$project_dir/.build/PTWindowInteractionTests"

"$project_dir/build-app.command"

codesign --verify --deep --strict --verbose=2 "$app_dir"
plutil -lint "$project_dir/Info.plist" "$contents_dir/Info.plist"
cmp "$project_dir/Info.plist" "$contents_dir/Info.plist"

[[ -x "$contents_dir/MacOS/PrettyTerm" ]] || {
  print -u2 "Missing executable: $contents_dir/MacOS/PrettyTerm"
  exit 1
}

for resource in PrettyTerm.icns app.js; do
  packaged_resource="$resources_dir/$resource"
  [[ -s "$packaged_resource" ]] || {
    print -u2 "Missing packaged resource: $packaged_resource"
    exit 1
  }
  cmp "$project_dir/Resources/$resource" "$packaged_resource"
done

[[ "$(plutil -extract CFBundleIdentifier raw -o - "$contents_dir/Info.plist")" == "com.yuuka.prettyterm.beta" ]]
[[ "$(plutil -extract CFBundleDisplayName raw -o - "$contents_dir/Info.plist")" == "PrettyTerm Beta" ]]
[[ "$(plutil -extract PTReleaseChannel raw -o - "$contents_dir/Info.plist")" == "beta" ]]
[[ "$(plutil -extract CFBundleIconFile raw -o - "$contents_dir/Info.plist")" == "PrettyTerm.icns" ]]

print "Verification passed: $app_dir"
