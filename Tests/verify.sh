#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/PrettyTerm Beta.app"
contents_dir="$app_dir/Contents"
resources_dir="$contents_dir/Resources"
mkdir -p "$project_dir/.build"

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  -I"$project_dir/Sources" \
  "$project_dir/Sources/PTFilePreview.m" \
  "$project_dir/Tests/PTFilePreviewTests.m" \
  -o "$project_dir/.build/PTFilePreviewTests"
"$project_dir/.build/PTFilePreviewTests"

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -framework AppKit \
  -I"$project_dir/Sources" \
  "$project_dir/Sources/PTAppearance.m" \
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
  -framework ImageIO \
  -framework UniformTypeIdentifiers \
  "$project_dir/Sources/PTAgentState.m" \
  "$project_dir/Sources/PTAppearance.m" \
  "$project_dir/Sources/PTFilePreview.m" \
  "$project_dir/Sources/PTFrontendBridge.m" \
  "$project_dir/Sources/PTGitReview.m" \
  "$project_dir/Sources/PTUsageMetrics.m" \
  "$project_dir/Tests/PTSessionParserTests.m" \
  -o "$project_dir/.build/PTSessionParserTests"
"$project_dir/.build/PTSessionParserTests"

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -Wno-nullability-completeness \
  -framework AppKit -framework WebKit -framework UniformTypeIdentifiers -framework ImageIO \
  "$project_dir/Sources/PTAgentState.m" \
  "$project_dir/Sources/PTAppearance.m" \
  "$project_dir/Sources/PTFilePreview.m" \
  "$project_dir/Sources/PTFrontendBridge.m" \
  "$project_dir/Sources/PTGitReview.m" \
  "$project_dir/Sources/PTUsageMetrics.m" \
  "$project_dir/Tests/PTClaudeLaunchTests.m" \
  -o "$project_dir/.build/PTClaudeLaunchTests"
"$project_dir/.build/PTClaudeLaunchTests"

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -Wno-nullability-completeness \
  -framework AppKit -framework WebKit -framework UniformTypeIdentifiers -framework ImageIO \
  "$project_dir/Sources/PTAgentState.m" \
  "$project_dir/Sources/PTAppearance.m" \
  "$project_dir/Sources/PTFilePreview.m" \
  "$project_dir/Sources/PTFrontendBridge.m" \
  "$project_dir/Sources/PTGitReview.m" \
  "$project_dir/Sources/PTUsageMetrics.m" \
  "$project_dir/Tests/PTHomeTests.m" \
  -o "$project_dir/.build/PTHomeTests"
"$project_dir/.build/PTHomeTests"

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -Wno-nullability-completeness \
  -framework AppKit -framework WebKit -framework UniformTypeIdentifiers -framework ImageIO \
  "$project_dir/Sources/PTAgentState.m" \
  "$project_dir/Sources/PTAppearance.m" \
  "$project_dir/Sources/PTFilePreview.m" \
  "$project_dir/Sources/PTFrontendBridge.m" \
  "$project_dir/Sources/PTGitReview.m" \
  "$project_dir/Sources/PTUsageMetrics.m" \
  "$project_dir/Tests/PTRenameTests.m" \
  -o "$project_dir/.build/PTRenameTests"
"$project_dir/.build/PTRenameTests"

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
  -framework ImageIO \
  -framework UniformTypeIdentifiers \
  "$project_dir/.build/PrettyTermForInteractionTests.o" \
  "$project_dir/.build/PTWindowInteractionTests.o" \
  "$project_dir/Sources/PTAgentState.m" \
  "$project_dir/Sources/PTAppearance.m" \
  "$project_dir/Sources/PTFilePreview.m" \
  "$project_dir/Sources/PTFrontendBridge.m" \
  "$project_dir/Sources/PTGitReview.m" \
  "$project_dir/Sources/PTUsageMetrics.m" \
  -o "$project_dir/.build/PTWindowInteractionTests"
"$project_dir/.build/PTWindowInteractionTests"

"$project_dir/build-app.command"

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -framework AppKit \
  -framework WebKit \
  -I"$project_dir/Sources" \
  "$project_dir/Sources/PTFrontendBridge.m" \
  "$project_dir/Tests/PTFrontendBridgeTests.m" \
  -o "$project_dir/.build/PTFrontendBridgeTests"
"$project_dir/.build/PTFrontendBridgeTests" "$project_dir"

clang -fobjc-arc -fmodules -mmacosx-version-min=13.0 \
  -framework AppKit \
  -framework WebKit \
  -I"$project_dir/Sources" \
  "$project_dir/Sources/PTFrontendBridge.m" \
  "$project_dir/Tests/PTRenderingPerformanceTests.m" \
  -o "$project_dir/.build/PTRenderingPerformanceTests"
"$project_dir/.build/PTRenderingPerformanceTests" "$project_dir" "$resources_dir" --assert

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

for resource in PrettyTerm.icns PrettyTermLogo.png; do
  packaged_resource="$resources_dir/$resource"
  [[ -s "$packaged_resource" ]] || {
    print -u2 "Missing packaged resource: $packaged_resource"
    exit 1
  }
  cmp "$project_dir/Resources/$resource" "$packaged_resource"
done

diff -qr "$project_dir/.build/frontend" "$resources_dir/frontend"
python3 - "$resources_dir/frontend" <<'PYTHON'
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / ".vite/manifest.json").read_text())
assert manifest and any(entry.get("isEntry") for entry in manifest.values())

class Entrypoint(HTMLParser):
    scripts = []
    assets = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "script":
            path = attrs.get("src") or attrs.get("data-src")
            if path:
                assert attrs.get("type") != "module"
                assert "crossorigin" not in attrs
                self.scripts.append(path)
        if tag == "link" and attrs.get("rel") == "stylesheet":
            self.assets.append(attrs["href"])

page = Entrypoint()
page.feed((root / "index.html").read_text())
assert page.scripts, "missing SystemJS entry scripts"
boot_css = root / "assets/boot.css"
assert "--lh-stylex" in boot_css.read_text(), "missing StyleX boot stylesheet"
for path in page.scripts + page.assets:
    assert (root / path).is_file(), path
for entry in manifest.values():
    for path in [entry["file"], *entry.get("css", []), *entry.get("assets", [])]:
        assert (root / path).is_file(), path
    chunk = root / entry["file"]
    if chunk.suffix == ".js":
        for stylesheet in re.findall(r'new URL\("([^"]+\.css)",', chunk.read_text()):
            assert (chunk.parent / stylesheet).is_file(), stylesheet
PYTHON
