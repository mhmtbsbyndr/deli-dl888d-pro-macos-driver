# Deli DL-888D PRO – macOS CUPS Driver

A tiny, native CUPS driver (PPD + TSPL2 raster filter) for the
**Deli DL-888D PRO** thermal label printer. The filter converts
CUPS 1-bit raster output into **TSPL/TSPL2** – the command language
the printer speaks natively.

Distributed as a signed-free `.pkg` installer inside a `.dmg`.

## Download

Grab the latest `Deli-DL888D-PRO-Driver.dmg` from
[GitHub Releases](https://github.com/mhmtbsbyndr/deli-dl888d-pro-macos-driver/releases).

## Install (GUI)

1. Open the DMG.
2. Double-click **Install Deli DL-888D PRO Driver.pkg**.
   - macOS will say the package is from an unidentified developer.
     Right-click → **Open** → **Open Anyway** in
     *System Settings → Privacy & Security*.
3. Follow the installer.
4. Done. If the printer is plugged in over USB, a CUPS queue named
   `Deli_DL888D_PRO` has already been created for you.

## Test print

```bash
echo "Hallo von macOS" | lp -d Deli_DL888D_PRO
lpoptions -p Deli_DL888D_PRO -l   # show density/speed/gap options
```

## What the installer does

| Step | Action |
|---|---|
| 1 | Copies `rastertotspl` → `/usr/libexec/cups/filter/` |
| 2 | Copies `deli-dl888d-pro.ppd` → `/Library/Printers/PPDs/Contents/Resources/` |
| 3 | Reloads CUPS via `launchctl kickstart` |
| 4 | Runs `lpinfo -v` to find a connected Deli printer and creates queue `Deli_DL888D_PRO` via `lpadmin` |
| 5 | Logs everything to `/var/log/install.log` (grep for `[deli-driver]`) |

## Supported options (via PPD)

- **PageSize**: 40×30, 60×40, 80×40, 100×67, 100×150 mm + Custom
- **Resolution**: 203 dpi (native)
- **Density**: 1 – 15 (darkness)
- **Speed**: 2 – 6 ips
- **MediaGap**: 2 mm / 3 mm gap, Continuous, Black Mark

## Build from source

```bash
# Build just the filter binary
make

# Build the full DMG (filter + pkg + dmg)
./build-dmg.sh
# → output/Deli-DL888D-PRO-Driver.dmg
```

Requires Xcode Command Line Tools (`xcode-select --install`).

## Uninstall

```bash
sudo lpadmin -x Deli_DL888D_PRO 2>/dev/null
sudo rm -f /usr/libexec/cups/filter/rastertotspl
sudo rm -f /Library/Printers/PPDs/Contents/Resources/deli-dl888d-pro.ppd
sudo launchctl kickstart -k system/org.cups.cupsd
```

## Architecture

```
App → Quartz/PDF → CUPS pipeline → pstoraster → rastertotspl → USB → printer
                                                    │
                                                    ▼
                                        Reads 1-bit CUPS raster,
                                        emits TSPL:
                                          SIZE  w mm, h mm
                                          GAP   2 mm,0 mm
                                          DENSITY 8
                                          SPEED   4
                                          CLS
                                          BITMAP  0,0,wb,h,0,<bytes>
                                          PRINT   1,copies
```

The bit inversion (`~b`) in `rastertotspl.c` is required because
CUPS 1-bit-K encodes `1 = ink`, while TSPL `BITMAP` mode 0 wants
`0 = dot`.

## Files

| Path | Purpose |
|---|---|
| `rastertotspl.c` | CUPS raster → TSPL filter (C) |
| `deli-dl888d-pro.ppd` | PPD with paper sizes, density, speed, gap |
| `Makefile` | Builds filter + `make install` dev path |
| `install.sh` | CLI installer (dev path) |
| `build-dmg.sh` | Builds the distributable .pkg + .dmg |
| `pkg/scripts/postinstall` | Runs at install time: reload CUPS, add queue |
| `pkg/distribution.xml` | Installer UI (title, welcome, conclusion) |
| `pkg/resources/` | Installer HTML pages + license |

## License

MIT – see `LICENSE`.
