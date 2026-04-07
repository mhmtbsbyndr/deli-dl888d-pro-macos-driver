#!/bin/bash
#
# 02 Test ZPL.command
#
# Sends a raw ZPL (Zebra Programming Language) test label using only
# printer-internal fonts. Some Chinese thermal printers, including
# parts of the Deli PRO line, speak ZPL instead of TSPL.
#
# Expected output: ONE 60x30 mm label with text lines.

set -u
RAW_QUEUE="Deli_DL888D_PRO_Raw"

echo "==> Sending ZPL test label to $RAW_QUEUE"

if ! lpstat -p "$RAW_QUEUE" >/dev/null 2>&1; then
    echo "!! Raw queue '$RAW_QUEUE' not found. Install the .pkg first."
    read -r -p "Enter to close."; exit 1
fi

# 60 mm x 30 mm @ 300 dpi = 708 x 354 dots
lp -d "$RAW_QUEUE" -o raw <<'ZPL'
^XA
^MMT
^PW708
^LL354
^LS0
^FO20,20^GB668,314,4^FS
^FT50,90^A0N,50,50^FDZPL TEST^FS
^FT50,160^A0N,40,40^FD60 x 30 mm^FS
^FT50,220^A0N,30,30^FDDeli DL-888D PRO^FS
^PQ1,0,1,Y
^XZ
ZPL

echo
echo "Job submitted. Check the printer."
echo " - If ONE label with text comes out: ZPL WORKS."
echo "   → The printer is NOT a TSPL device. Tell me, and I'll"
echo "     rewrite the filter to emit ZPL instead of TSPL."
echo " - If nothing/multiple blanks: the printer is neither ZPL."
echo "   Run 04 Diagnose.command and send the report."
echo
read -r -p "Enter to close."
