#!/bin/bash
#
# 04 Diagnose.command
#
# Gathers everything needed to debug a bad print. Writes a single
# report file to the Desktop and opens it at the end. Paste the
# content into a GitHub issue or send it to me.

set -u
REPORT="$HOME/Desktop/deli-diagnose-$(date +%Y%m%d-%H%M%S).txt"

{
    echo "Deli DL-888D PRO Driver — Diagnostic Report"
    echo "==========================================="
    echo "Date:    $(date)"
    echo "Host:    $(hostname)"
    echo "macOS:   $(sw_vers -productVersion)   Build: $(sw_vers -buildVersion)"
    echo "Arch:    $(uname -m)"
    echo

    echo "## 1. Installed filter binary"
    if [[ -f /usr/libexec/cups/filter/rastertotspl ]]; then
        ls -la /usr/libexec/cups/filter/rastertotspl
        file    /usr/libexec/cups/filter/rastertotspl
        echo "Version embedded in binary:"
        /usr/libexec/cups/filter/rastertotspl --version 2>/dev/null || \
            strings /usr/libexec/cups/filter/rastertotspl 2>/dev/null | grep "rastertotspl v" | head -1
    else
        echo "!! /usr/libexec/cups/filter/rastertotspl does NOT exist"
    fi
    echo

    echo "## 2. Installed PPD"
    if [[ -f /Library/Printers/PPDs/Contents/Resources/deli-dl888d-pro.ppd ]]; then
        ls -la /Library/Printers/PPDs/Contents/Resources/deli-dl888d-pro.ppd
        grep -E "FileVersion|ModelName|HWResolution|HWMargins" \
             /Library/Printers/PPDs/Contents/Resources/deli-dl888d-pro.ppd
    else
        echo "!! PPD not found"
    fi
    echo

    echo "## 3. CUPS queues for this printer"
    lpstat -v 2>&1 | grep -i deli || echo "(no Deli queues)"
    echo
    lpstat -p Deli_DL888D_PRO     2>&1 || true
    lpstat -p Deli_DL888D_PRO_Raw 2>&1 || true
    echo

    echo "## 4. Printer options"
    lpoptions -p Deli_DL888D_PRO     2>&1 || true
    echo
    lpoptions -p Deli_DL888D_PRO -l  2>&1 | head -20 || true
    echo

    echo "## 5. USB devices detected by CUPS"
    lpinfo -v 2>/dev/null | grep -iE "usb|deli|label|thermal" || true
    echo

    echo "## 6. USB info from macOS (system_profiler)"
    system_profiler SPUSBDataType 2>/dev/null | \
        awk '/Deli|DL-88|Label|Thermal/{p=15} p>0{print; p--}' | \
        head -40 || echo "(no match)"
    echo

    echo "## 7. Last 50 CUPS error log lines"
    if [[ -r /var/log/cups/error_log ]]; then
        tail -50 /var/log/cups/error_log
    else
        echo "(not readable — try: sudo cat /var/log/cups/error_log | tail -50)"
        log show --style compact --last 10m --predicate 'process == "cupsd"' 2>/dev/null | tail -50
    fi
    echo

    echo "## 8. Recent [deli-driver] install log entries"
    grep "\[deli-driver\]" /var/log/install.log 2>/dev/null | tail -30 || echo "(none)"
    echo

    echo "## 9. Dry-run filter on synthetic input"
    # Build a minimal PostScript that declares 60x30 mm media and draws
    # a simple frame + text. Run it through cupsfilter to see what
    # TSPL the filter emits. Hexdump the first 400 bytes so we can
    # verify SIZE syntax without plaintext-leaking large binary blobs.
    TMPPS="$(mktemp /tmp/deli-diag.ps.XXXXXX)"
    TMPOUT="$(mktemp /tmp/deli-diag.out.XXXXXX)"
    cat > "$TMPPS" <<'EOF'
%!PS-Adobe-3.0
%%BoundingBox: 0 0 170 85
%%Pages: 1
%%EndComments
<< /PageSize [170 85] >> setpagedevice
/Helvetica findfont 12 scalefont setfont
0.5 setlinewidth
5 5 moveto 165 5 lineto 165 80 lineto 5 80 lineto closepath stroke
15 55 moveto (Deli TEST 60x30) show
15 35 moveto (300 dpi) show
showpage
EOF

    if command -v cupsfilter >/dev/null 2>&1 ; then
        cupsfilter -p /Library/Printers/PPDs/Contents/Resources/deli-dl888d-pro.ppd \
                   -t diag -o media=w170h85 "$TMPPS" > "$TMPOUT" 2>>"$REPORT.stderr" \
            || echo "!! cupsfilter exited non-zero"
        echo "cupsfilter output size: $(wc -c < "$TMPOUT") bytes"
        echo "First 400 bytes as hexdump:"
        xxd "$TMPOUT" | head -25
        echo "..."
        echo "First 400 bytes as text (control chars escaped):"
        head -c 400 "$TMPOUT" | cat -v
        echo
        if [[ -s "$REPORT.stderr" ]]; then
            echo "cupsfilter stderr:"
            cat "$REPORT.stderr"
        fi
    else
        echo "(cupsfilter not available)"
    fi
    rm -f "$TMPPS" "$TMPOUT" "$REPORT.stderr"
    echo

    echo "== end of report =="
} > "$REPORT" 2>&1

echo "Report saved to:"
echo "  $REPORT"
echo
echo "Opening it now — please paste the content to me so I can see"
echo "exactly what your system is doing."
open -t "$REPORT" 2>/dev/null || open "$REPORT"
read -r -p "Enter to close."
