#!/bin/bash
# Generate Assets.xcassets (AppIcon set + AppLogo) from the logo masters in assets/.
# Idempotent — safe to run on every build.
set -euo pipefail
cd "$(dirname "$0")/.."

ICON_SRC="assets/appicon/fadeo-appicon-1024.png"   # padded squircle (correct for macOS)
LOGO_SRC="assets/logo/fadeo-logo.png"              # tight logo (for in-app)
XCA="Fadeo/Resources/Assets.xcassets"
ICONSET="$XCA/AppIcon.appiconset"
LOGOSET="$XCA/AppLogo.imageset"

mkdir -p "$ICONSET" "$LOGOSET"

# Top-level catalog metadata
cat > "$XCA/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON

# --- AppIcon: render every required pixel size from the 1024 master ---
for px in 16 32 64 128 256 512 1024; do
  sips -z "$px" "$px" "$ICON_SRC" --out "$ICONSET/icon_${px}.png" >/dev/null
done

cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "size" : "16x16",   "scale" : "1x", "filename" : "icon_16.png" },
    { "idiom" : "mac", "size" : "16x16",   "scale" : "2x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "1x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "2x", "filename" : "icon_64.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "1x", "filename" : "icon_128.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "2x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "1x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "2x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "1x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "2x", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# --- AppLogo: single-scale universal image for in-app use ---
cp "$LOGO_SRC" "$LOGOSET/fadeo-logo.png"
cat > "$LOGOSET/Contents.json" <<'JSON'
{
  "images" : [ { "idiom" : "universal", "filename" : "fadeo-logo.png" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "assets: AppIcon (7 sizes) + AppLogo generated → $XCA"
