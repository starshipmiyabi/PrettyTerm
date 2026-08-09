#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
plist="$project_dir/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
app_dir="$project_dir/dist/PrettyTerm Beta.app"
dmg_name="PrettyTerm-Beta-${version}-build${build}-macOS.dmg"
dmg_path="$project_dir/dist/$dmg_name"
checksum_path="$project_dir/dist/SHA256SUMS.txt"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/prettyterm-dmg.XXXXXX")"

cleanup() {
  [[ -n "$staging_dir" && -d "$staging_dir" ]] && rm -rf "$staging_dir"
}
trap cleanup EXIT

"$project_dir/build-app.command"
ditto "$app_dir" "$staging_dir/PrettyTerm Beta.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
  -volname "PrettyTerm Beta $version" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -ov \
  "$dmg_path"

(
  cd "$project_dir/dist"
  shasum -a 256 "$dmg_name" > "${checksum_path:t}"
)
hdiutil verify "$dmg_path"
print "Packaged: $dmg_path"
print "Checksum: $checksum_path"
