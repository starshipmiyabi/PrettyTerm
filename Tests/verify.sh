#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/PrettyTerm Beta.app"
contents_dir="$app_dir/Contents"
resources_dir="$contents_dir/Resources"
mkdir -p "$project_dir/.build"

if [[ -f "$project_dir/Tests/test_renderer.js" ]]; then
  node "$project_dir/Tests/test_renderer.js"
fi
if [[ -f "$project_dir/Tests/test_appearance.js" ]]; then
  node "$project_dir/Tests/test_appearance.js"
fi
if [[ -f "$project_dir/Tests/test_floating_window.js" ]]; then
  node "$project_dir/Tests/test_floating_window.js"
fi

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -framework AppKit \
  -I"$project_dir/Sources" \
  "$project_dir/Sources/PTGitReview.m" \
  "$project_dir/Tests/PTGitReviewTests.m" \
  -o "$project_dir/.build/PTGitReviewTests"
"$project_dir/.build/PTGitReviewTests"

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
  -Wno-nullability-completeness \
  -framework AppKit \
  -framework WebKit \
  -framework UniformTypeIdentifiers \
  "$project_dir/Sources/PTAgentState.m" \
  "$project_dir/Sources/PTGitReview.m" \
  "$project_dir/Sources/PTUsageMetrics.m" \
  "$project_dir/Tests/PTSessionParserTests.m" \
  -o "$project_dir/.build/PTSessionParserTests"
"$project_dir/.build/PTSessionParserTests"

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -Dmain=PrettyTermApplicationMain \
  -c "$project_dir/Sources/PrettyTerm.m" \
  -o "$project_dir/.build/PrettyTermForInteractionTests.o"
clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -c "$project_dir/Tests/PTWindowInteractionTests.m" \
  -o "$project_dir/.build/PTWindowInteractionTests.o"
clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -framework AppKit \
  -framework WebKit \
  -framework UniformTypeIdentifiers \
  "$project_dir/.build/PrettyTermForInteractionTests.o" \
  "$project_dir/.build/PTWindowInteractionTests.o" \
  "$project_dir/Sources/PTAgentState.m" \
  "$project_dir/Sources/PTGitReview.m" \
  "$project_dir/Sources/PTUsageMetrics.m" \
  -o "$project_dir/.build/PTWindowInteractionTests"
"$project_dir/.build/PTWindowInteractionTests"

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -framework AppKit \
  -framework WebKit \
  "$project_dir/Tests/PTViewportAnchorTests.m" \
  -o "$project_dir/.build/PTViewportAnchorTests"
"$project_dir/.build/PTViewportAnchorTests" "$project_dir"

"$project_dir/build-app.command"

codesign --verify --deep --strict --verbose=2 "$app_dir"
codesign_details="$(codesign -dvv "$app_dir" 2>&1)"
[[ "$codesign_details" == *runtime* ]]
entitlements="$(codesign -d --entitlements :- "$app_dir" 2>/dev/null | plutil -p -)"
[[ "$entitlements" == *'"com.apple.security.automation.apple-events" => 1'* ]]
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

for language in zh-Hans en; do
  packaged_strings="$resources_dir/$language.lproj/InfoPlist.strings"
  [[ -s "$packaged_strings" ]] || {
    print -u2 "Missing packaged localization: $packaged_strings"
    exit 1
  }
  cmp "$project_dir/Resources/$language.lproj/InfoPlist.strings" "$packaged_strings"
done

[[ "$(plutil -extract CFBundleIdentifier raw -o - "$contents_dir/Info.plist")" == "com.yuuka.prettyterm.beta" ]]
[[ "$(plutil -extract CFBundleDisplayName raw -o - "$contents_dir/Info.plist")" == "PrettyTerm Beta" ]]
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$contents_dir/Info.plist")" == "0.9.1" ]]
[[ "$(plutil -extract CFBundleVersion raw -o - "$contents_dir/Info.plist")" == "28" ]]
[[ "$(plutil -extract PTReleaseChannel raw -o - "$contents_dir/Info.plist")" == "beta" ]]
[[ "$(plutil -extract CFBundleDevelopmentRegion raw -o - "$contents_dir/Info.plist")" == "zh-Hans" ]]
[[ "$(plutil -extract CFBundleIconFile raw -o - "$contents_dir/Info.plist")" == "PrettyTerm.icns" ]]

print "Verification passed: $app_dir"
