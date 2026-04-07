# Deli DL-888D PRO — macOS CUPS Driver

Native CUPS driver (PPD + TSPL2 raster filter) for the **Deli DL-888D PRO**
thermal label printer. Distributed as a `.pkg` installer inside a `.dmg`.

[![latest](https://img.shields.io/github/v/release/mhmtbsbyndr/deli-dl888d-pro-macos-driver)](https://github.com/mhmtbsbyndr/deli-dl888d-pro-macos-driver/releases/latest)
[![license](https://img.shields.io/github/license/mhmtbsbyndr/deli-dl888d-pro-macos-driver)](LICENSE)

## Download

Grab the latest `Deli-DL888D-PRO-Driver.dmg` from the
[Releases page](https://github.com/mhmtbsbyndr/deli-dl888d-pro-macos-driver/releases/latest).

## Install

1. Open the DMG.
2. Double-click **Install Deli DL-888D PRO Driver.pkg**.
3. Gatekeeper will refuse the first time — right-click → **Open** →
   **Open** (or approve via *System Settings → Privacy & Security →
   Open Anyway*).
4. Follow the installer.

The installer creates **two** CUPS queues:

| Queue | Purpose |
|---|---|
| `Deli_DL888D_PRO`     | Normal print path: filter + PPD, 28 paper presets, 300 dpi |
| `Deli_DL888D_PRO_Raw` | Raw TSPL passthrough for diagnostics (no filter, no PPD) |

If the printer is connected over USB at install time, the queue is
auto-populated via `lpadmin` — no manual "Add Printer" dialog needed.

## Print

From any app (Preview, Pages, TextEdit, Safari, …):

```bash
echo "Hallo von macOS" | lp -d Deli_DL888D_PRO
lpoptions -p Deli_DL888D_PRO -l   # show density/speed/gap options
```

## Paper sizes

All 28 presets are native **300 dpi**:

| | | | |
|---|---|---|---|
| 15×30 | 20×30 | 25×15 | 30×20 |
| 30×30 | 40×20 | **40×30** | 40×40 |
| 50×20 | 50×30 | 50×40 | 50×50 |
| **60×30** | **60×40** | 60×50 | **70×30** |
| 70×40 | 70×50 | 75×50 | **80×30** |
| 80×40 | 80×50 | 80×60 | 100×50 |
| 100×60 | 100×70 | 100×100 | **100×150** |

## Options exposed via PPD

- **Resolution** — 300 dpi (native)
- **Density** — 1–15 darkness (default 8)
- **Speed** — 2–6 ips (default 3)
- **MediaGap** — 2 mm, 3 mm, Continuous, Black Mark

## Troubleshooting

The DMG ships with four double-clickable scripts for diagnosing a
misbehaving printer:

| Script | What it does |
|---|---|
| `01 Test TSPL.command` | Raw TSPL label using printer-internal fonts. If this works, the printer speaks TSPL and the filter pipeline should work too. |
| `02 Test ZPL.command`  | Raw ZPL (Zebra) label. If only this works, the printer is ZPL-dialect and the filter needs a rewrite. |
| `03 Calibrate.command` | Sends `GAPDETECT` / `SET GAP AUTO` to trigger software gap calibration. |
| `04 Diagnose.command`  | Gathers driver version, PPD info, queue state, USB enumeration, 50 lines of CUPS error_log, and a dry-run of the filter against a synthetic 60×30 mm input (hex-dumps the emitted TSPL). Writes a single report to `~/Desktop/deli-diagnose-*.txt`. |

If Gatekeeper kills a `.command` script on first run, clear the
quarantine attribute on the mounted DMG once:

```bash
xattr -cr "/Volumes/Deli DL-888D PRO Driver"
```

See [`Troubleshooting.txt`](pkg/dmg-extras/Troubleshooting.txt) in the
DMG for a full decision tree.

## The story of the 4-blank-2-half bug

The first four releases (v1.0 – v1.4) all missed the real cause of
the most reported issue — "I select 60×30 mm but the printer feeds
4 blank labels and prints the content split across labels 5 and 6".
Each version fixed a real issue that turned out not to be the one:

| Version | Fix | Was it the bug? |
|---|---|---|
| v1.1.0 | Switched to native 300 dpi (was incorrectly 203) | No |
| v1.2.0 | Derive SIZE from PPD PageSize instead of raster pixels | No |
| v1.3.0 | `setlocale(LC_NUMERIC, "C")` + integer mm — fixes German locale printf emitting `60,0` instead of `60.0` | No (real bug, not *the* bug) |
| v1.4.0 | Diagnostic tooling: raw queue, four test scripts, Diagnose.command | Enables finding it |
| **v1.5.0** | **`INITIALPRINTER` as the first TSPL command of every job** | **Yes.** |

**Root cause**: the Deli firmware retains stale `SIZE`/`GAP` state
between jobs. Factory default is 100×150 mm, which coincidentally
equals **5 × 30 mm** label advance — explaining the exact symptom
down to the number of blank labels. Without `INITIALPRINTER`, the
subsequent `SIZE 60 mm,30 mm` is silently ignored.

Empirical bisection via three raw TSPL tests:

| Test | TSPL prologue | Result |
|---|---|---|
| A | `SIZE` + `GAPDETECT` | nothing visible |
| B | `SIZE` + `AUTODETECT 32 mm` + `PRINT` | nothing visible |
| C | **`INITIALPRINTER`** + `SIZE` + `PRINT` | correct single label |

One command, one line of C — shipped in v1.5.0.

## Architecture

```
App → Quartz/PDF → CUPS pipeline → cgpdftoraster → rastertotspl → usb backend → printer
                                                       │
                                                       ▼
                                     INITIALPRINTER            ← v1.5.0: reset stale state
                                     SIZE   <w> mm,<h> mm      ← from hdr->PageSize, %ld
                                     GAP    2 mm,0 mm
                                     DIRECTION / REFERENCE / …
                                     DENSITY / SPEED
                                     CLS
                                     BITMAP 0,0,<wb>,<h>,0,<binary>
                                     PRINT  1,<copies>
```

Key design decisions in `rastertotspl.c`:

- **`setlocale(LC_NUMERIC, "C")`** as the first line of `main()`,
  so printf always emits `.` as decimal separator.
- **SIZE in integer mm** (`%ld` — never `%f`). One-millimeter
  precision is plenty for physical label dimensions.
- **SIZE derived from `hdr->PageSize`** (authoritative PPD value
  in points), not from `cupsWidth/cupsHeight` (canvas pixels).
- **BITMAP dimensions** = `PageSize × HWResolution`, clamped down
  to `cupsWidth/cupsHeight`. Oversized rasters from buggy upstream
  filters are drained but not forwarded — one logical job always
  maps to one physical label.
- **Bit polarity**: CUPS 1-bit-K has `1 = ink`; TSPL `BITMAP` mode 0
  has `0 = dot`. Every byte is inverted via `~b` on output.
- **Per-page DEBUG line** to stderr, captured by CUPS in
  `/var/log/cups/error_log` — trivial to spot size/resolution
  mismatches after the fact:
  ```
  DEBUG: page=1 PageSize=[170,85]pt->60.0x30.0mm raster=708x354@300x300dpi out=708x354px wb=89 copies=1
  ```

## Build from source

```bash
make                 # just the filter binary
./build-dmg.sh       # full end-to-end: filter + pkg + dmg
# → output/Deli-DL888D-PRO-Driver.dmg
```

Requires Xcode Command Line Tools (`xcode-select --install`).
No sudo needed — everything happens in the source tree. Install
the resulting DMG via double-click, or use the CLI developer path:

```bash
sudo ./install.sh --add-usb
```

## Uninstall

```bash
sudo lpadmin -x Deli_DL888D_PRO
sudo lpadmin -x Deli_DL888D_PRO_Raw
sudo rm -f /usr/libexec/cups/filter/rastertotspl
sudo rm -f /Library/Printers/PPDs/Contents/Resources/deli-dl888d-pro.ppd
sudo launchctl kickstart -k system/org.cups.cupsd
```

## Files

| Path | Purpose |
|---|---|
| `rastertotspl.c` | CUPS raster → TSPL filter (C) |
| `deli-dl888d-pro.ppd` | PPD: 28 sizes, 300 dpi, density/speed/gap |
| `Makefile` | Builds filter |
| `install.sh` | CLI dev install path |
| `build-dmg.sh` | Full .pkg + .dmg pipeline (pkgbuild → productbuild → hdiutil) |
| `pkg/distribution.xml` | Installer UI metadata |
| `pkg/scripts/postinstall` | Runs as root at install time: filter perms, CUPS reload, auto-queue via lpadmin (normal + raw) |
| `pkg/resources/` | welcome.html + conclusion.html |
| `pkg/dmg-extras/` | The four `.command` test scripts + Troubleshooting.txt bundled into the DMG |

## Tested hardware

- **Deli DL-888D PRO** (USB, idVendor 0x353D, "Deli LabelPrinter")
  with die-cut labels 60×30 mm, 300 dpi direct thermal.

## License

MIT — see [LICENSE](LICENSE).
