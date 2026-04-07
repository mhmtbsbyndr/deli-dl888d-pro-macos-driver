/*
 * rastertotspl - CUPS raster filter for Deli DL-888D PRO
 *
 * Converts CUPS 1-bit raster output into TSPL/TSPL2 commands understood
 * by Deli thermal label printers (DL-880, DL-888, DL-886 and compatibles).
 *
 * Build: cc -O2 -Wall -o rastertotspl rastertotspl.c -lcupsimage -lcups
 *
 * Invoked by CUPS as:
 *   rastertotspl job user title copies options [filename]
 *
 * Key design decisions
 * --------------------
 * 1. SIZE is derived from hdr->PageSize (the PPD-declared media in
 *    points) rather than from cupsWidth/cupsHeight. The PPD is the
 *    source of truth for the physical label size. If an upstream
 *    filter rasterizes onto an oversized canvas, we still tell the
 *    printer the real label length, so it advances one label per job.
 *
 * 2. BITMAP dimensions are derived from PageSize × HWResolution, then
 *    clamped to whatever cupsWidth/cupsHeight actually provided. This
 *    guarantees that (a) we never ask the printer to read more bitmap
 *    bytes than we send, and (b) an oversized raster gets cropped to
 *    one label worth of dots, not spread across N labels.
 *
 * 3. Every page writes a diagnostic DEBUG line to stderr so CUPS
 *    captures it into /var/log/cups/error_log, making it trivial to
 *    spot resolution / page-size mismatches after the fact.
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
#include <locale.h>

/* ---- CLI options parsed from PPD ---- */
static int opt_density = 8;       /* 0..15          */
static int opt_speed   = 3;       /* ips            */
static const char *opt_gap = "2 mm,0 mm";

/* ---- Global cancel flag ---- */
static volatile int job_canceled = 0;
static void cancel_handler(int sig) { (void)sig; job_canceled = 1; }

/* Parse CUPS PPD options */
static void parse_options(int num_options, cups_option_t *options)
{
    const char *v;
    if ((v = cupsGetOption("Density", num_options, options)) != NULL)
        opt_density = atoi(v);
    if ((v = cupsGetOption("Speed", num_options, options)) != NULL)
        opt_speed = atoi(v);
    if ((v = cupsGetOption("MediaGap", num_options, options)) != NULL) {
        if (!strcmp(v, "Gap2mm"))          opt_gap = "2 mm,0 mm";
        else if (!strcmp(v, "Gap3mm"))     opt_gap = "3 mm,0 mm";
        else if (!strcmp(v, "Continuous")) opt_gap = "0 mm,0 mm";
        else if (!strcmp(v, "BlackMark"))  opt_gap = "0 mm,0 mm";
    }
}

/* Compute effective geometry for one page.
 *
 * PageSize comes from the PPD and is the authoritative label size in
 * points. cupsWidth/cupsHeight come from the rasterizer and are the
 * canvas size in pixels — hopefully matching PageSize × resolution,
 * but sometimes oversized by buggy apps / filters.
 *
 * We compute:
 *   w_mm, h_mm       — label physical size for TSPL SIZE command
 *   out_w_px, out_h_px — number of pixels we actually emit in BITMAP
 *                        (clamped so we never exceed the raster)
 */
static void compute_geometry(const cups_page_header2_t *hdr,
                             double *w_mm, double *h_mm,
                             unsigned *out_w_px, unsigned *out_h_px)
{
    double w_pt = hdr->PageSize[0];
    double h_pt = hdr->PageSize[1];

    /* Fall back to pixel-derived if PageSize missing */
    if (w_pt <= 0.0 || h_pt <= 0.0) {
        w_pt = (double)hdr->cupsWidth  * 72.0 / (double)hdr->HWResolution[0];
        h_pt = (double)hdr->cupsHeight * 72.0 / (double)hdr->HWResolution[1];
    }

    *w_mm = w_pt * 25.4 / 72.0;
    *h_mm = h_pt * 25.4 / 72.0;

    /* Expected bitmap dimensions given PPD + resolution */
    unsigned exp_w = (unsigned)(w_pt * (double)hdr->HWResolution[0] / 72.0 + 0.5);
    unsigned exp_h = (unsigned)(h_pt * (double)hdr->HWResolution[1] / 72.0 + 0.5);

    /* Clamp: never emit more pixels than the raster provides */
    *out_w_px = exp_w > hdr->cupsWidth  ? hdr->cupsWidth  : exp_w;
    *out_h_px = exp_h > hdr->cupsHeight ? hdr->cupsHeight : exp_h;

    /* Also clamp if the raster is much larger than PPD
     * (oversized canvas bug) — this is the key fix for the
     * "4 empty + 2 half-half" feeding symptom. */
    /* already clamped via MIN above — nothing more to do */
}

static void emit_tspl_header(double w_mm, double h_mm,
                             int num_options, cups_option_t *options)
{
    /* Use integer mm only — no floats, no printf decimal-point locale
     * dependency. TSPL accepts integer mm, and 1 mm precision is more
     * than enough for label sizes. Rounding up by 0.5 gives nearest int. */
    long w_mm_i = (long)(w_mm + 0.5);
    long h_mm_i = (long)(h_mm + 0.5);
    printf("SIZE %ld mm,%ld mm\r\n", w_mm_i, h_mm_i);

    const char *gap = cupsGetOption("MediaGap", num_options, options);
    if (gap && !strcmp(gap, "BlackMark"))
        printf("BLINE 3 mm,0 mm\r\n");
    else
        printf("GAP %s\r\n", opt_gap);

    printf("DIRECTION 1\r\n");
    printf("REFERENCE 0,0\r\n");
    printf("SHIFT 0\r\n");
    printf("OFFSET 0 mm\r\n");
    printf("DENSITY %d\r\n", opt_density);
    printf("SPEED %d\r\n", opt_speed);
    printf("SET CUTTER OFF\r\n");
    printf("SET TEAR ON\r\n");
    printf("SET PEEL OFF\r\n");
    printf("CODEPAGE UTF-8\r\n");
    printf("CLS\r\n");
}

static int emit_page_bitmap(cups_raster_t *ras,
                            const cups_page_header2_t *hdr,
                            unsigned out_w_px, unsigned out_h_px)
{
    unsigned width_bytes = (out_w_px + 7u) / 8u;
    unsigned char *line  = malloc(hdr->cupsBytesPerLine);
    if (!line) {
        fputs("ERROR: out of memory\n", stderr);
        return -1;
    }

    /* BITMAP x,y,width_bytes,height,mode,<binary> */
    printf("BITMAP 0,0,%u,%u,0,", width_bytes, out_h_px);
    fflush(stdout);

    /* Read the full raster, but only write out_h_px rows × width_bytes.
     * Extra rows / columns (oversized canvas) are drained and dropped. */
    for (unsigned y = 0; y < hdr->cupsHeight && !job_canceled; y++) {
        if (cupsRasterReadPixels(ras, line, hdr->cupsBytesPerLine) < 1) {
            fprintf(stderr, "ERROR: short raster read at row %u\n", y);
            free(line);
            return -1;
        }
        if (y < out_h_px) {
            /* CUPS 1-bit-K: 1 = ink, TSPL BITMAP mode 0: 0 = dot → invert */
            for (unsigned i = 0; i < width_bytes; i++) {
                fputc((unsigned char)~line[i], stdout);
            }
        }
    }
    fputs("\r\n", stdout);
    free(line);
    return 0;
}

int main(int argc, char *argv[])
{
    /* CRITICAL: Force C locale for all numeric output. CUPS passes the
     * job's LANG (often de_DE.UTF-8 on German macOS) into the filter
     * environment. Any CUPS library call may then internally invoke
     * setlocale(LC_ALL, "") and switch the decimal separator to ",".
     * That would turn `SIZE 60.0 mm,30.0 mm` into `SIZE 60,0 mm,30,0 mm`
     * which TSPL parses as garbage — the printer then uses its last
     * cached SIZE (e.g. factory default 100x150 mm) and feeds several
     * blank labels per job. This single line is the fix for that. */
    setlocale(LC_NUMERIC, "C");

    if (argc < 6 || argc > 7) {
        fputs("Usage: rastertotspl job-id user title copies options [file]\n",
              stderr);
        return 1;
    }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = cancel_handler;
    sigaction(SIGTERM, &sa, NULL);

    int num_options = 0;
    cups_option_t *options = NULL;
    num_options = cupsParseOptions(argv[5], 0, &options);
    parse_options(num_options, options);

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

        double   w_mm, h_mm;
        unsigned out_w_px, out_h_px;
        compute_geometry(&hdr, &w_mm, &h_mm, &out_w_px, &out_h_px);

        fprintf(stderr,
            "DEBUG: page=%d PageSize=[%d,%d]pt->%.1fx%.1fmm "
            "raster=%ux%u@%ux%udpi out=%ux%upx wb=%u copies=%d\n",
            page,
            hdr.PageSize[0], hdr.PageSize[1], w_mm, h_mm,
            hdr.cupsWidth, hdr.cupsHeight,
            hdr.HWResolution[0], hdr.HWResolution[1],
            out_w_px, out_h_px, (out_w_px + 7u) / 8u, copies);

        if (out_w_px == 0 || out_h_px == 0) {
            fprintf(stderr, "WARN: page %d has zero dimensions, skipping\n", page);
            /* still drain raster so we don't desync */
            unsigned char *drain = malloc(hdr.cupsBytesPerLine);
            for (unsigned y = 0; y < hdr.cupsHeight; y++)
                cupsRasterReadPixels(ras, drain, hdr.cupsBytesPerLine);
            free(drain);
            continue;
        }

        fprintf(stderr, "PAGE: %d %d\n", page, copies);
        emit_tspl_header(w_mm, h_mm, num_options, options);

        if (emit_page_bitmap(ras, &hdr, out_w_px, out_h_px) != 0) {
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
