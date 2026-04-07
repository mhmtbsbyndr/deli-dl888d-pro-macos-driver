/*
 * rastertotspl - CUPS raster filter for Deli DL-880D Pro
 *
 * Converts CUPS 1-bit raster output into TSPL/TSPL2 commands understood
 * by Deli thermal label printers (DL-880, DL-880D, DL-886 and compatibles).
 *
 * Build: cc -O2 -Wall -o rastertotspl rastertotspl.c -lcupsimage -lcups
 *
 * Invoked by CUPS as:
 *   rastertotspl job user title copies options [filename]
 *
 * Spec references:
 *   - TSC TSPL/TSPL2 Programming Manual (SIZE, GAP, CLS, BITMAP, PRINT)
 *   - CUPS Raster API (cups/raster.h)
 */

#include <cups/cups.h>
#include <cups/raster.h>
#include <cups/ppd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>

/* ---- CLI options parsed from PPD ---- */
static int opt_density = 8;       /* 0..15          */
static int opt_speed   = 4;       /* ips            */
static const char *opt_gap = "2 mm,0 mm";

/* ---- Global cancel flag ---- */
static volatile int job_canceled = 0;

static void cancel_handler(int sig) { (void)sig; job_canceled = 1; }

/* Parse CUPS PPD options for Density/Speed/MediaGap */
static void parse_options(int num_options, cups_option_t *options)
{
    const char *v;

    if ((v = cupsGetOption("Density", num_options, options)) != NULL)
        opt_density = atoi(v);
    if ((v = cupsGetOption("Speed", num_options, options)) != NULL)
        opt_speed = atoi(v);
    if ((v = cupsGetOption("MediaGap", num_options, options)) != NULL) {
        if (!strcmp(v, "Gap2mm"))       opt_gap = "2 mm,0 mm";
        else if (!strcmp(v, "Gap3mm"))  opt_gap = "3 mm,0 mm";
        else if (!strcmp(v, "Continuous")) opt_gap = "0 mm,0 mm";
        else if (!strcmp(v, "BlackMark")) opt_gap = "0 mm,0 mm"; /* use BLINE below */
    }
}

/* Emit TSPL header for one page. Dimensions from CUPS header in points. */
static void emit_page_header(const cups_page_header2_t *hdr,
                             int num_options, cups_option_t *options)
{
    double w_mm = (double)hdr->cupsWidth  / (double)hdr->HWResolution[0] * 25.4;
    double h_mm = (double)hdr->cupsHeight / (double)hdr->HWResolution[1] * 25.4;

    printf("SIZE %.1f mm,%.1f mm\r\n", w_mm, h_mm);

    const char *gap = cupsGetOption("MediaGap", num_options, options);
    if (gap && !strcmp(gap, "BlackMark"))
        printf("BLINE 3 mm,0 mm\r\n");
    else
        printf("GAP %s\r\n", opt_gap);

    printf("DIRECTION 1\r\n");
    printf("REFERENCE 0,0\r\n");
    printf("DENSITY %d\r\n", opt_density);
    printf("SPEED %d\r\n", opt_speed);
    printf("SET CUTTER OFF\r\n");
    printf("SET TEAR ON\r\n");
    printf("CODEPAGE UTF-8\r\n");
    printf("CLS\r\n");
}

/* Convert one CUPS raster page into a TSPL BITMAP block.
 * CUPS 1-bit-K: bit=1 means black. TSPL BITMAP mode 0 (OVERWRITE)
 * treats bit=0 as a dot (ink), so we invert every byte on output.  */
static int emit_page_bitmap(cups_raster_t *ras,
                            const cups_page_header2_t *hdr)
{
    unsigned width_bytes = (hdr->cupsWidth + 7u) / 8u;
    unsigned char *line  = malloc(hdr->cupsBytesPerLine);
    if (!line) {
        fputs("ERROR: out of memory\n", stderr);
        return -1;
    }

    /* BITMAP x,y,width_bytes,height,mode, <binary data> */
    printf("BITMAP 0,0,%u,%u,0,", width_bytes, hdr->cupsHeight);
    fflush(stdout);

    for (unsigned y = 0; y < hdr->cupsHeight && !job_canceled; y++) {
        if (cupsRasterReadPixels(ras, line, hdr->cupsBytesPerLine) < 1) {
            fprintf(stderr, "ERROR: short read at row %u\n", y);
            free(line);
            return -1;
        }
        /* Only first width_bytes belong to the image; rest is line padding */
        for (unsigned i = 0; i < width_bytes; i++) {
            unsigned char b = (unsigned char)~line[i];
            fputc(b, stdout);
        }
    }
    fputs("\r\n", stdout);
    free(line);
    return 0;
}

int main(int argc, char *argv[])
{
    if (argc < 6 || argc > 7) {
        fputs("Usage: rastertotspl job-id user title copies options [file]\n",
              stderr);
        return 1;
    }

    /* Signals for cancel */
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = cancel_handler;
    sigaction(SIGTERM, &sa, NULL);

    /* Options string → cups_option_t */
    int num_options = 0;
    cups_option_t *options = NULL;
    num_options = cupsParseOptions(argv[5], 0, &options);
    parse_options(num_options, options);

    /* Input */
    int fd = 0;
    if (argc == 7) {
        fd = open(argv[6], O_RDONLY);
        if (fd < 0) {
            perror("ERROR: open raster file");
            return 1;
        }
    }

    cups_raster_t *ras = cupsRasterOpen(fd, CUPS_RASTER_READ);
    if (!ras) {
        fputs("ERROR: cupsRasterOpen failed\n", stderr);
        if (fd != 0) close(fd);
        return 1;
    }

    int copies = atoi(argv[4]);
    if (copies < 1) copies = 1;

    int page = 0;
    cups_page_header2_t hdr;
    while (cupsRasterReadHeader2(ras, &hdr) && !job_canceled) {
        page++;
        fprintf(stderr, "PAGE: %d %d\n", page, copies);

        emit_page_header(&hdr, num_options, options);
        if (emit_page_bitmap(ras, &hdr) != 0) {
            cupsRasterClose(ras);
            if (fd != 0) close(fd);
            return 1;
        }
        printf("PRINT 1,%d\r\n", copies);
        fflush(stdout);
    }

    cupsRasterClose(ras);
    if (fd != 0) close(fd);
    cupsFreeOptions(num_options, options);

    if (page == 0) {
        fputs("ERROR: No pages found\n", stderr);
        return 1;
    }
    fputs("INFO: Ready to print\n", stderr);
    return 0;
}
