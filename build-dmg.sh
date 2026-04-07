#!/usr/bin/env bash
#
# build-dmg.sh - Build the end-user installer.
#
# Pipeline:
#   1. make clean && make                               (compile filter)
#   2. stage payload + scripts in pkg-build/
#   3. pkgbuild  → component pkg
#   4. productbuild (with distribution.xml) → product pkg
#   5. hdiutil create → output/Deli-DL888D-PRO-Driver.dmg
#
# No sudo required, everything happens in the source tree.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

VERSION="1.4.0"
IDENTIFIER="com.mhmtbsbyndr.deli.dl888d.driver"
PRODUCT_NAME="Deli DL-888D PRO Driver"
DMG_VOLNAME="Deli DL-888D PRO Driver"
DMG_BASENAME="Deli-DL888D-PRO-Driver"

FILTER_BIN="rastertotspl"
PPD_FILE="deli-dl888d-pro.ppd"

BUILD_DIR="$HERE/pkg-build"
PAYLOAD_DIR="$BUILD_DIR/payload"
SCRIPTS_DIR="$BUILD_DIR/scripts"
OUTPUT_DIR="$HERE/output"
DMG_STAGE="$BUILD_DIR/dmg-stage"

COMPONENT_PKG="$BUILD_DIR/${DMG_BASENAME}-component.pkg"
PRODUCT_PKG="$DMG_STAGE/Install ${PRODUCT_NAME}.pkg"
DMG_FILE="$OUTPUT_DIR/${DMG_BASENAME}.dmg"

say() { printf "\n==> %s\n" "$*"; }

# 1) Clean + build filter
say "Cleaning previous build"
rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$PAYLOAD_DIR" "$SCRIPTS_DIR" "$OUTPUT_DIR" "$DMG_STAGE"

say "Compiling $FILTER_BIN"
make clean >/dev/null
make

# 2) Stage payload (mirrors target filesystem)
say "Staging payload"
install -d "$PAYLOAD_DIR/usr/libexec/cups/filter"
install -m 0755 "$FILTER_BIN" "$PAYLOAD_DIR/usr/libexec/cups/filter/$FILTER_BIN"

install -d "$PAYLOAD_DIR/Library/Printers/PPDs/Contents/Resources"
install -m 0644 "$PPD_FILE" "$PAYLOAD_DIR/Library/Printers/PPDs/Contents/Resources/$PPD_FILE"

# postinstall script
cp "$HERE/pkg/scripts/postinstall" "$SCRIPTS_DIR/postinstall"
chmod 0755 "$SCRIPTS_DIR/postinstall"

# 3) Component pkg
say "Building component package"
pkgbuild \
    --root "$PAYLOAD_DIR" \
    --scripts "$SCRIPTS_DIR" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --install-location "/" \
    "$COMPONENT_PKG"

# 4) Distribution pkg with UI resources
say "Building product package"
RESOURCES_DIR="$BUILD_DIR/resources"
mkdir -p "$RESOURCES_DIR"
cp "$HERE/pkg/resources/welcome.html"    "$RESOURCES_DIR/"
cp "$HERE/pkg/resources/conclusion.html" "$RESOURCES_DIR/"
cp "$HERE/LICENSE"                        "$RESOURCES_DIR/LICENSE.txt"

# Rewrite distribution.xml so pkgref matches our component filename
sed "s|deli-dl888d-pro-driver-component.pkg|$(basename "$COMPONENT_PKG")|" \
    "$HERE/pkg/distribution.xml" > "$BUILD_DIR/distribution.xml"

productbuild \
    --distribution "$BUILD_DIR/distribution.xml" \
    --resources "$RESOURCES_DIR" \
    --package-path "$BUILD_DIR" \
    "$PRODUCT_PKG"

# 5) DMG
say "Creating DMG"
# Extras inside the DMG: README, troubleshooting, protocol test scripts
cp "$HERE/README.md"                              "$DMG_STAGE/README.md"
cp "$HERE/pkg/dmg-extras/Troubleshooting.txt"     "$DMG_STAGE/Troubleshooting.txt"
cp "$HERE/pkg/dmg-extras/01 Test TSPL.command"    "$DMG_STAGE/01 Test TSPL.command"
cp "$HERE/pkg/dmg-extras/02 Test ZPL.command"     "$DMG_STAGE/02 Test ZPL.command"
cp "$HERE/pkg/dmg-extras/03 Calibrate.command"    "$DMG_STAGE/03 Calibrate.command"
cp "$HERE/pkg/dmg-extras/04 Diagnose.command"     "$DMG_STAGE/04 Diagnose.command"
chmod +x "$DMG_STAGE"/*.command

hdiutil create \
    -volname "$DMG_VOLNAME" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    "$DMG_FILE" >/dev/null

say "Done"
printf "\n"
ls -lh "$DMG_FILE"
printf "\nSHA-256: "
shasum -a 256 "$DMG_FILE" | awk '{print $1}'
