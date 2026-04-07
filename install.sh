#!/usr/bin/env bash
# install.sh - Build & install the Deli DL-888D PRO CUPS driver on macOS.
#
# This is the developer / CLI install path. End users should use the
# .pkg inside the .dmg instead (see build-dmg.sh).
#
# Usage:
#   sudo ./install.sh             # build, install, no queue creation
#   sudo ./install.sh --add-usb   # also auto-add USB printer queue
#   sudo ./install.sh --remove    # uninstall

set -euo pipefail

FILTER_DIR="/usr/libexec/cups/filter"
PPD_DIR="/Library/Printers/PPDs/Contents/Resources"
PPD_FILE="deli-dl888d-pro.ppd"
FILTER_BIN="rastertotspl"
PRINTER_NAME="Deli_DL888D_PRO"

here="$(cd "$(dirname "$0")" && pwd)"

need_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This action requires sudo." >&2
        exit 1
    fi
}

build() {
    echo "==> Building $FILTER_BIN"
    (cd "$here" && make)
}

install_files() {
    need_root
    echo "==> Installing filter to $FILTER_DIR"
    install -d "$FILTER_DIR"
    install -m 0755 "$here/$FILTER_BIN" "$FILTER_DIR/$FILTER_BIN"

    echo "==> Installing PPD to $PPD_DIR"
    install -d "$PPD_DIR"
    install -m 0644 "$here/$PPD_FILE" "$PPD_DIR/$PPD_FILE"

    echo "==> Restarting CUPS"
    launchctl kickstart -k system/org.cups.cupsd || true
}

detect_usb_uri() {
    /usr/sbin/lpinfo -v 2>/dev/null \
        | awk '/^direct usb:\/\// { print $2 }' \
        | grep -iE 'deli|dl[-_]?8[0-9]{2}' \
        | head -n1
}

add_printer() {
    need_root
    local uri
    uri="$(detect_usb_uri || true)"
    if [[ -z "${uri:-}" ]]; then
        echo "!! Could not auto-detect a USB Deli printer." >&2
        echo "   Run: lpinfo -v    and pass the URI manually:" >&2
        echo "   lpadmin -p $PRINTER_NAME -E -v <URI> -P $PPD_DIR/$PPD_FILE" >&2
        exit 2
    fi
    echo "==> Adding printer $PRINTER_NAME at $uri"

    /usr/sbin/lpadmin -x "$PRINTER_NAME" 2>/dev/null || true
    /usr/sbin/lpadmin -p "$PRINTER_NAME" -E \
        -v "$uri" \
        -P "$PPD_DIR/$PPD_FILE" \
        -o printer-is-shared=false
    /usr/bin/cupsenable "$PRINTER_NAME"
    /usr/sbin/cupsaccept "$PRINTER_NAME"
    echo "==> Done. Test with:"
    echo "     lp -d $PRINTER_NAME /etc/hosts"
}

remove_all() {
    need_root
    echo "==> Removing printer queue (if present)"
    /usr/sbin/lpadmin -x "$PRINTER_NAME" 2>/dev/null || true
    echo "==> Removing filter + PPD"
    rm -f "$FILTER_DIR/$FILTER_BIN"
    rm -f "$PPD_DIR/$PPD_FILE"
    launchctl kickstart -k system/org.cups.cupsd || true
    echo "==> Done."
}

case "${1:-}" in
    --remove|-r)       remove_all ;;
    --add-usb|-u)      build; install_files; add_printer ;;
    ""|--install|-i)   build; install_files ;;
    *)
        echo "Usage: $0 [--install|--add-usb|--remove]" >&2
        exit 1
        ;;
esac
