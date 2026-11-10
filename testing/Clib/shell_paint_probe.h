/* shell_paint_probe.h - test-only: an inch-square black block an inch in, for the
   printing test (GW-20). Windows only; off Windows it does nothing (the printing tests
   need "Microsoft Print to PDF" and skip themselves without it). */

#ifndef SHELL_PAINT_PROBE_H
#define SHELL_PAINT_PROBE_H

#ifdef _WIN32
#include <windows.h>
static void shell_paint_probe_block(void* l_dc, int l_dpi_x, int l_dpi_y) {
    PatBlt((HDC)l_dc, l_dpi_x, l_dpi_y, l_dpi_x, l_dpi_y, BLACKNESS);
}
#else
static void shell_paint_probe_block(void* l_dc, int l_dpi_x, int l_dpi_y) { (void)l_dc; (void)l_dpi_x; (void)l_dpi_y; }
#endif

#endif
