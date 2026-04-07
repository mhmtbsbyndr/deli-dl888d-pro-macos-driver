#!/bin/bash
#
# 01 Test TSPL.command
#
# Sends a raw TSPL/TSPL2 test label (Deli, TSC, Godex ...) using only
# printer-internal fonts (no BITMAP). Bypasses rastertotspl entirely.
#
# Expected output: ONE 60x30 mm label with a frame and three lines of text.

set -u
RAW_QUEUE="Deli_DL888D_PRO_Raw"

echo "==> Sending TSPL test label to $RAW_QUEUE"

if ! lpstat -p "$RAW_QUEUE" >/dev/null 2>&1; then
    echo "!! Raw queue '$RAW_QUEUE' not found. Install the .pkg first."
    read -r -p "Enter to close."; exit 1
fi

lp -d "$RAW_QUEUE" -o raw <<'TSPL'
SIZE 60 mm,30 mm
GAP 2 mm,0 mm
DIRECTION 1
REFERENCE 0,0
DENSITY 8
SPEED 3
SET CUTTER OFF
SET TEAR ON
SET PEEL OFF
CLS
BOX 10,10,700,345,4
TEXT 40,40,"4",0,1,1,"TSPL TEST"
TEXT 40,130,"3",0,1,1,"60 x 30 mm"
TEXT 40,200,"2",0,1,1,"Deli DL-888D PRO"
PRINT 1,1
TSPL

echo
echo "Job submitted. Check the printer."
echo " - If ONE label with frame + text comes out: TSPL WORKS. ✓"
echo " - If multiple blank labels come out: try 02 Test ZPL.command"
echo " - If nothing comes out: run 04 Diagnose.command and send the report."
echo
read -r -p "Enter to close."
