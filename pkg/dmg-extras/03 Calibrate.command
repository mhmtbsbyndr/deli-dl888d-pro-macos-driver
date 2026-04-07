#!/bin/bash
#
# 03 Calibrate.command
#
# Sends a TSPL auto-calibration command to the printer. This makes
# the printer feed 2-3 labels while measuring the gap between them,
# then stores the measurement internally so subsequent SIZE commands
# land correctly.
#
# This is the SOFTWARE equivalent of the 'hold FEED while powering on'
# physical calibration procedure.

set -u
RAW_QUEUE="Deli_DL888D_PRO_Raw"

echo "==> Sending auto-calibration command to $RAW_QUEUE"

if ! lpstat -p "$RAW_QUEUE" >/dev/null 2>&1; then
    echo "!! Raw queue '$RAW_QUEUE' not found. Install the .pkg first."
    read -r -p "Enter to close."; exit 1
fi

# AUTODETECT with a paper length hint in mm — printer feeds a few
# labels, measures the gap between them, stores the result.
# GAPDETECT without arguments triggers auto-detection.
lp -d "$RAW_QUEUE" -o raw <<'TSPL'
SIZE 60 mm,30 mm
GAP 2 mm,0 mm
DIRECTION 1
REFERENCE 0,0
GAPDETECT
SET GAP AUTO
SET HEAD ON
HOME
TSPL

echo
echo "Job submitted. The printer should now feed 2-3 blank labels"
echo "while it measures the gap, then stop."
echo
echo "After this, try '01 Test TSPL.command' again. The calibration"
echo "is persistent until power cycle."
echo
echo "If the printer does NOT feed any labels at all, it either"
echo "doesn't speak TSPL or needs the physical calibration procedure:"
echo "  1. Power OFF"
echo "  2. Hold FEED while powering ON"
echo "  3. Keep holding until the LED blinks red twice, release"
echo
read -r -p "Enter to close."
