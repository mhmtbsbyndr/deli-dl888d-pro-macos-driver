#!/bin/bash
#
# Test Print.command
#
# Sends a known-good raw TSPL label to the diagnostic queue
# (Deli_DL888D_PRO_Raw). This bypasses rastertotspl entirely — if
# this prints correctly but normal printing doesn't, the filter is
# at fault. If this prints wrong too, the printer needs physical
# calibration (hold FEED while powering on).
#
# Double-click this file in Finder to run.

set -u
cd "$(dirname "$0")"

RAW_QUEUE="Deli_DL888D_PRO_Raw"
MAIN_QUEUE="Deli_DL888D_PRO"

say() { printf "%s\n" "$*"; }

say "==> Checking queues..."
if ! lpstat -p "$RAW_QUEUE" >/dev/null 2>&1; then
    say "!! Raw queue '$RAW_QUEUE' not found."
    say "   Install the .pkg from this DMG first, then re-run."
    read -r -p "Press enter to close."
    exit 1
fi

say "==> Sending raw TSPL test label (60 x 30 mm) to $RAW_QUEUE"

# Notes on the TSPL below:
#   - SIZE in integer mm (locale-safe)
#   - Built-in printer fonts (no BITMAP), so this exercises the
#     USB + TSPL parser without touching the raster filter
#   - BOX draws a frame so misaligned labels are obvious
lp -d "$RAW_QUEUE" -o raw <<'TSPL'
SIZE 60 mm,30 mm
GAP 2 mm,0 mm
DIRECTION 1
REFERENCE 0,0
SHIFT 0
OFFSET 0 mm
DENSITY 8
SPEED 3
SET CUTTER OFF
SET TEAR ON
SET PEEL OFF
CLS
BOX 10,10,700,345,4
TEXT 40,40,"4",0,1,1,"DELI TEST"
TEXT 40,130,"3",0,1,1,"60 x 30 mm"
TEXT 40,200,"2",0,1,1,"raw TSPL OK"
PRINT 1,1
TSPL

rc=$?
if [[ $rc -eq 0 ]]; then
    say
    say "Job submitted. Watch the printer."
    say
    say "Expected: one 60 x 30 mm label with a border and three text lines."
    say
    say "If you see blank labels instead of content:"
    say "  1. The printer needs gap calibration. Do this:"
    say "     - Power OFF the printer."
    say "     - Hold the FEED button while powering ON."
    say "     - Keep holding until the LED blinks red twice, then release."
    say "     - The printer feeds 2-3 labels to learn the gap."
    say "     - Power cycle the printer."
    say "  2. Re-run this test."
    say
    say "If this test prints correctly but normal printing (from"
    say "Preview/Pages/etc) does not, the rastertotspl filter is"
    say "misbehaving. Capture the debug line from the CUPS log:"
    say "     log show --style compact --last 5m --predicate 'process == \"cupsd\"' | grep DEBUG"
else
    say "!! lp returned exit code $rc"
fi

say
read -r -p "Press enter to close."
