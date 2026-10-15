#!/bin/sh
set -eu

if test "$#" -ne 2
then
	echo "usage: $0 <bmk> <output-root>" >&2
	exit 1
fi

bmk_dir=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)
bmk="$bmk_dir/$(basename -- "$1")"
output_root=$2
fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")/fixtures" && pwd)
application="$output_root/ConfiguredApp"
bundle="$application.app"
plist="$bundle/Contents/Info.plist"
plist_buddy=/usr/libexec/PlistBuddy

test ! -e "$output_root"
mkdir -p "$output_root"
"$bmk" makeapp -r -t gui -hi -o "$application" "$fixture_dir/macos_configuration_app.bmx"

plutil -lint "$plist"
test "$("$plist_buddy" -c 'Print :CFBundleIdentifier' "$plist")" = "org.example.macos-configuration"
test "$("$plist_buddy" -c 'Print :CFBundleName' "$plist")" = "Configured & Tested"
test "$("$plist_buddy" -c 'Print :CFBundleShortVersionString' "$plist")" = "2.3.4"
test "$("$plist_buddy" -c 'Print :CFBundleVersion' "$plist")" = "17"
test "$("$plist_buddy" -c 'Print :LSApplicationCategoryType' "$plist")" = "public.app-category.games"
test "$("$plist_buddy" -c 'Print :NSHighResolutionCapable' "$plist")" = "false"
test -n "$("$plist_buddy" -c 'Print :LSMinimumSystemVersion' "$plist")"
cmp "$bundle/Contents/Resources/AppIcon.icns" "$fixture_dir/../../macos.icns"
cmp "$bundle/Contents/embedded.provisionprofile" "$fixture_dir/macos_configuration.provisionprofile"
codesign --verify --strict "$bundle"
codesign -d --entitlements - "$bundle" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'

"$bmk" makeapp -r -t gui -o "$application" "$fixture_dir/macos_unsigned_app.bmx"
test ! -e "$bundle/Contents/_CodeSignature"
test ! -e "$bundle/Contents/embedded.provisionprofile"
if codesign --verify "$bundle" >/dev/null 2>&1
then
	echo "macOS bundle retained a stale signature" >&2
	exit 1
fi

echo "bmk macOS application configuration tests passed"
