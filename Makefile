# Makefile for the Deli DL-880D Pro CUPS filter (macOS)
#
# Targets:
#   make            - builds rastertotspl
#   sudo make install - installs filter + PPD into CUPS
#   sudo make uninstall

CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c11
LDFLAGS ?=
LIBS     = -lcupsimage -lcups

# macOS CUPS paths
CUPS_FILTER_DIR ?= /usr/libexec/cups/filter
CUPS_PPD_DIR    ?= /Library/Printers/PPDs/Contents/Resources

FILTER = rastertotspl
PPD    = deli-dl880d.ppd

all: $(FILTER)

$(FILTER): rastertotspl.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LIBS)

install: $(FILTER) $(PPD)
	install -d $(CUPS_FILTER_DIR)
	install -m 0755 $(FILTER) $(CUPS_FILTER_DIR)/$(FILTER)
	install -d $(CUPS_PPD_DIR)
	install -m 0644 $(PPD) $(CUPS_PPD_DIR)/$(PPD)
	@echo ""
	@echo "Installed. Now add the printer:"
	@echo "  System Settings > Printers & Scanners > Add Printer"
	@echo "  Use 'Select Software...' and pick 'Deli DL-880D Pro (TSPL)'"
	@echo ""

uninstall:
	rm -f $(CUPS_FILTER_DIR)/$(FILTER)
	rm -f $(CUPS_PPD_DIR)/$(PPD)

clean:
	rm -f $(FILTER) *.o

.PHONY: all install uninstall clean
