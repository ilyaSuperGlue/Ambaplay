#!/bin/sh
# Build the small native bootstrap without Wine, GPTK or the product payload, as a ZIP with
# the app, READ ME FIRST.html (how to get past Gatekeeper) and the licence files: LICENSE,
# NOTICE and OFL-Geist.txt for the Geist font the page embeds. A downloaded DMG is
# checked by Gatekeeper on its own, then the app in it again: two Open Anyway prompts. A ZIP
# is not, so the app is the only one.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
identity=${AMBAPLAY_SIGN_IDENTITY:--}
configuration=${CONFIGURATION:-release}
out="$repo/out/native-installer"
app="$out/Ambaplay Installer.app"
zip="$repo/out/Ambaplay-Setup.zip"

swift build --package-path app -c "$configuration" --product AmbaplayInstaller --arch arm64
bin=$(swift build --package-path app -c "$configuration" --show-bin-path --arch arm64)
[ -x "$bin/AmbaplayInstaller" ] || { echo 'Installer executable missing' >&2; exit 1; }
mkdir -p "$out"
stage=$(mktemp -d "$out/.package.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
bundle="$stage/Ambaplay Installer.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin/AmbaplayInstaller" "$bundle/Contents/MacOS/AmbaplayInstaller"
for resource in AmbaplayApp_AmbaplayUI.bundle AmbaplayApp_AmbaplayInstaller.bundle; do
    ditto "$bin/$resource" "$bundle/Contents/Resources/$resource"
done
python3 - "$repo/app/Sources/AmbaplayInstaller/Resources/Localization/Localizable.xcstrings" "$bundle/Contents/Resources/AmbaplayApp_AmbaplayInstaller.bundle" <<'PYTHON'
import json
import pathlib
import sys
catalog = json.loads(pathlib.Path(sys.argv[1]).read_text())
bundle = pathlib.Path(sys.argv[2])
root = bundle / "Contents" / "Resources" if (bundle / "Contents" / "Resources").is_dir() else bundle
for language in ("en", "it", "zh-Hans"):
    folder = root / (language + ".lproj")
    folder.mkdir(exist_ok=True)
    values = []
    for key, entry in sorted(catalog["strings"].items()):
        value = key if language == "en" else entry["localizations"][language]["stringUnit"]["value"]
        values.append(json.dumps(key, ensure_ascii=False) + " = " + json.dumps(value, ensure_ascii=False) + ";")
    (folder / "Localizable.strings").write_text("\n".join(values) + "\n", encoding="utf-16")
(root / "Localizable.xcstrings").unlink(missing_ok=True)
PYTHON
"$bin/AmbaplayInstaller" --icon "$stage/icon.png"
mkdir "$stage/Ambaplay.iconset"
for points in 16 32 128 256 512; do
    sips -z "$points" "$points" "$stage/icon.png" --out "$stage/Ambaplay.iconset/icon_${points}x${points}.png" >/dev/null
    pixels=$((points * 2))
    sips -z "$pixels" "$pixels" "$stage/icon.png" --out "$stage/Ambaplay.iconset/icon_${points}x${points}@2x.png" >/dev/null
done
iconutil -c icns "$stage/Ambaplay.iconset" -o "$bundle/Contents/Resources/Ambaplay.icns"
rm -rf "$stage/icon.png" "$stage/Ambaplay.iconset"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ambaplay.Installer</string>
<key>CFBundleName</key><string>Ambaplay Installer</string>
<key>CFBundleDisplayName</key><string>Ambaplay Installer</string>
<key>CFBundleExecutable</key><string>AmbaplayInstaller</string>
<key>CFBundleIconFile</key><string>Ambaplay</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>it</string><string>zh-Hans</string></array>
<key>NSDownloadsFolderUsageDescription</key><string>Moves this installer disk image to Trash after you choose Finish.</string>
</dict></plist>
PLIST
cp LICENSE "$bundle/Contents/Resources/LICENSE"
codesign --force --sign "$identity" "$bundle"
codesign --verify --strict --deep "$bundle"
# Only replace previous local packaging outputs after a complete bundle is available.
rm -rf "$app"
ditto "$bundle" "$app"
# READ ME FIRST.html carries its Geist font inline, so it is one file.
package="$stage/package"
mkdir -p "$package"
ditto "$app" "$package/Ambaplay Installer.app"
python3 - "$repo/installer/native/READ ME FIRST.html" "$repo/app/Sources/AmbaplayUI/Resources/Fonts" "$package/READ ME FIRST.html" <<'PYTHON'
import base64
import pathlib
import re
import sys
page, fonts, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
def font(match):
    return "data:font/woff2;base64," + base64.b64encode((fonts / (match.group(1) + ".woff2")).read_bytes()).decode()
out.write_text(re.sub(r"\{\{font:(\w+)\}\}", font, page.read_text()))
PYTHON
cp LICENSE NOTICE app/Sources/AmbaplayUI/Resources/Fonts/OFL-Geist.txt "$package/"
rm -f "$zip"
(cd "$package" && ditto -c -k --norsrc --noextattr . "$zip")
size=$(stat -f '%z' "$zip")
limit=${AMBAPLAY_INSTALLER_MAX_BYTES:-5242880}
if [ "$size" -gt "$limit" ]; then
    echo "Installer ZIP exceeds size budget: $size > $limit bytes" >&2
    exit 1
fi
printf 'ZIP: %s\nSize: %s bytes (budget %s)\n' "$zip" "$size" "$limit"
shasum -a 256 "$zip"
