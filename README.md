# Deli DL-880D Pro – CUPS Driver für macOS

Ein einfacher, nativer CUPS-Treiber (Filter + PPD) für den Deli
**DL-880D Pro** Thermo-Etikettendrucker. Der Filter wandelt den
1-Bit-CUPS-Raster in **TSPL/TSPL2**-Befehle um – das Protokoll, das
diese Geräte (und die meisten Deli/TSC-kompatiblen 203-dpi-Label-
printer) verstehen.

> Hinweis: Ich habe den Treiber ohne Zugriff auf die offizielle
> Deli-SDK-Dokumentation geschrieben. Die Befehle basieren auf dem
> öffentlich dokumentierten TSPL2-Standard, den der DL-880D Pro
> verwendet. Wenn der Druck schräg, invertiert oder leer erscheint,
> siehe Abschnitt **Tuning**.

## Dateien

| Datei              | Zweck                                      |
|--------------------|--------------------------------------------|
| `deli-dl880d.ppd`  | CUPS PPD (Größen, Auflösung, Density, Gap) |
| `rastertotspl.c`   | CUPS-Raster→TSPL-Filter in C               |
| `Makefile`         | Baut & installiert den Filter              |
| `install.sh`       | Komfort-Wrapper mit USB-Auto-Detect        |

## Voraussetzungen

- macOS (getestet gegen die Standard-CUPS-Installation)
- Xcode Command Line Tools (`xcode-select --install`) – liefert
  `cc`, `make`, und die CUPS-Header (`libcups`, `libcupsimage`)

## Bauen & installieren

```bash
cd /tmp/deli-dl880d
chmod +x install.sh
sudo ./install.sh --add-usb     # baut, installiert, fügt USB-Drucker hinzu
```

Oder Schritt-für-Schritt:

```bash
make
sudo make install
# dann im Systemeinstellungen → Drucker & Scanner → "+" hinzufügen,
# "Software auswählen…" → "Deli DL-880D Pro (TSPL)"
```

## Testdruck

```bash
# Einfacher Textdruck
echo "Hallo von macOS" | lp -d Deli_DL880D_Pro

# PDF
lp -d Deli_DL880D_Pro -o media=w288h432 label.pdf
```

## Unterstützte Optionen (PPD)

- **PageSize**: 40×30, 60×40, 80×40, 100×67, 100×150 mm + Custom
- **Resolution**: 203 dpi (nativ)
- **Density**: 1 – 15 (Schwärze)
- **Speed**: 2 – 6 ips
- **MediaGap**: 2 mm / 3 mm Gap, Continuous, Black Mark

Alles über CUPS abrufbar:

```bash
lpoptions -p Deli_DL880D_Pro -l
```

## Deinstallation

```bash
sudo ./install.sh --remove
```

## Tuning / Troubleshooting

| Symptom                         | Abhilfe                                                  |
|---------------------------------|----------------------------------------------------------|
| Ausdruck komplett invertiert    | In `rastertotspl.c` das `~line[i]` durch `line[i]` ersetzen und neu kompilieren. |
| Nur leere Labels                | Medientyp prüfen – bei Endlospapier `MediaGap=Continuous`. |
| Etikett verschoben              | `GAP 2 mm,0 mm` an tatsächliche Lücke anpassen (PPD-Option). |
| Drucker zieht zu viele Labels   | In `emit_page_header()` `REFERENCE 0,0` ggf. auf `REFERENCE 0,16` setzen. |
| Schwacher Druck                 | `Density` in den Druckoptionen erhöhen.                  |
| USB nicht gefunden              | `lpinfo -v` → URI manuell mit `lpadmin -v <URI>` setzen. |

## Architektur in 30 Sekunden

```
App → Quartz/PDF → CUPS-Pipeline → pstoraster → rastertotspl → USB → Drucker
                                                 ↑
                                        liest 1-Bit-CUPS-Raster,
                                        emittiert TSPL-Bytes:
                                          SIZE w,h
                                          GAP  g
                                          DENSITY/SPEED
                                          CLS
                                          BITMAP 0,0,wb,h,0,<bytes>
                                          PRINT  1,copies
```

Die Bildinvertierung (`~b`) ist nötig, weil CUPS 1-Bit-K mit
`1 = Tinte` arbeitet, TSPL-BITMAP-Mode 0 aber `0 = Punkt setzen`
erwartet.
