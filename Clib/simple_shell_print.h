/* simple_shell_print.h - printing (1.24.0, simple_bible GW-20).

   One document at a time per process: a printer device context made with
   the paper and orientation asked for (the printer's own DEVMODE, changed
   and validated through DocumentPropertiesW), StartDocW with an optional
   output file (a printer that writes files - Microsoft Print to PDF -
   then writes there without asking), pages by StartPage/EndPage. What is
   drawn on the DC is the caller's: simple_widgets draws it through cairo's
   Windows printing surface (simple_cairo 1.6.0).

   No print dialog: the application chooses the printer from
   `shell_print_names', so the whole path runs headless.

   SHARED STATE follows simple_shell.h's law: SHELL_SHARED data with
   explicit initializers. Identifiers carry the l_ / shell_ prefixes. */

#ifndef SIMPLE_SHELL_PRINT_H
#define SIMPLE_SHELL_PRINT_H

#include <stddef.h>
#include <stdlib.h>
#include <wchar.h>
#include <windows.h>
#include "simple_shell.h"
#include <winspool.h>

#pragma comment(lib, "winspool.lib")

SHELL_SHARED HDC s_shell_print_dc = 0;
/* scan 20: the one document is CLAIMED atomically, so two processors (SCOOP)
   cannot both begin it; released when it ends, aborts or fails to begin. */
SHELL_SHARED volatile LONG s_shell_print_claim = 0;
SHELL_SHARED int s_shell_print_in_page = 0;

/* The default printer's name into `l_buf' (`l_cap' characters); its length,
   or 0 when there is none. */
static int shell_print_default(wchar_t* l_buf, int l_cap) {
    DWORD l_n = (DWORD)l_cap;
    if (!l_buf || l_cap <= 0) return 0;
    l_buf[0] = 0;
    if (!GetDefaultPrinterW(l_buf, &l_n)) return 0;
    return (int)wcslen(l_buf);
}

/* Every local and connected printer's name, each followed by a newline,
   into `l_buf' (`l_cap' characters); the characters written. */
static int shell_print_names(wchar_t* l_buf, int l_cap) {
    DWORD l_needed = 0, l_count = 0, l_i;
    BYTE* l_data;
    PRINTER_INFO_4W* l_info;
    int l_len = 0;
    size_t l_n;
    if (!l_buf || l_cap <= 0) return 0;
    l_buf[0] = 0;
    EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 4, NULL, 0, &l_needed, &l_count);
    if (l_needed == 0) return 0;
    l_data = (BYTE*)malloc(l_needed);
    if (!l_data) return 0;
    if (!EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 4, l_data, l_needed, &l_needed, &l_count)) {
        free(l_data);
        return 0;
    }
    l_info = (PRINTER_INFO_4W*)l_data;
    for (l_i = 0; l_i < l_count; l_i++) {
        if (!l_info[l_i].pPrinterName) continue;
        l_n = wcslen(l_info[l_i].pPrinterName);
        if ((size_t)l_len + l_n + 2 > (size_t)l_cap) break;
        memcpy(l_buf + l_len, l_info[l_i].pPrinterName, l_n * sizeof(wchar_t));
        l_len += (int)l_n;
        l_buf[l_len++] = L'\n';
    }
    l_buf[l_len] = 0;
    free(l_data);
    return l_len;
}

/* Begin a document on `l_printer' titled `l_title', written to `l_output'
   when that is not empty, on paper `l_paper' (a DMPAPER code; 0 keeps the
   printer's) in landscape when `l_landscape'. 1 when it began. */
static int shell_print_begin(const wchar_t* l_printer, const wchar_t* l_title, const wchar_t* l_output,
                             int l_paper, int l_landscape) {
    HANDLE l_h = 0;
    DEVMODEW* l_dm = 0;
    LONG l_size;
    DOCINFOW l_di;
    HDC l_dc;
    if (!l_printer || !l_printer[0]) return 0;
    if (InterlockedCompareExchange(&s_shell_print_claim, 1, 0) != 0) return 0;
    if (OpenPrinterW((LPWSTR)l_printer, &l_h, NULL)) {
        l_size = DocumentPropertiesW(NULL, l_h, (LPWSTR)l_printer, NULL, NULL, 0);
        if (l_size > 0) {
            l_dm = (DEVMODEW*)malloc((size_t)l_size);
            if (l_dm && DocumentPropertiesW(NULL, l_h, (LPWSTR)l_printer, l_dm, NULL, DM_OUT_BUFFER) == IDOK) {
                if (l_paper > 0) {
                    l_dm->dmPaperSize = (short)l_paper;
                    l_dm->dmFields |= DM_PAPERSIZE;
                }
                l_dm->dmOrientation = (short)(l_landscape ? DMORIENT_LANDSCAPE : DMORIENT_PORTRAIT);
                l_dm->dmFields |= DM_ORIENTATION;
                DocumentPropertiesW(NULL, l_h, (LPWSTR)l_printer, l_dm, l_dm, DM_IN_BUFFER | DM_OUT_BUFFER);
            } else if (l_dm) {
                free(l_dm);
                l_dm = 0;
            }
        }
        ClosePrinter(l_h);
    }
    l_dc = CreateDCW(NULL, l_printer, NULL, l_dm);
    if (l_dm) free(l_dm);
    if (!l_dc) {
        InterlockedExchange(&s_shell_print_claim, 0);
        return 0;
    }
    ZeroMemory(&l_di, sizeof(l_di));
    l_di.cbSize = sizeof(l_di);
    l_di.lpszDocName = (l_title && l_title[0]) ? l_title : L"Document";
    l_di.lpszOutput = (l_output && l_output[0]) ? l_output : NULL;
    if (StartDocW(l_dc, &l_di) <= 0) {
        DeleteDC(l_dc);
        InterlockedExchange(&s_shell_print_claim, 0);
        return 0;
    }
    s_shell_print_dc = l_dc;
    s_shell_print_in_page = 0;
    return 1;
}

static int shell_print_begin_page(void) {
    if (!s_shell_print_dc || s_shell_print_in_page) return 0;
    if (StartPage(s_shell_print_dc) <= 0) return 0;
    s_shell_print_in_page = 1;
    return 1;
}

static int shell_print_end_page(void) {
    if (!s_shell_print_dc || !s_shell_print_in_page) return 0;
    s_shell_print_in_page = 0;
    return EndPage(s_shell_print_dc) > 0 ? 1 : 0;
}

/* End the document: the spooler takes it. 1 when it was accepted. */
static int shell_print_end(void) {
    int l_ok;
    if (!s_shell_print_dc) return 0;
    if (s_shell_print_in_page) EndPage(s_shell_print_dc);
    l_ok = EndDoc(s_shell_print_dc) > 0 ? 1 : 0;
    DeleteDC(s_shell_print_dc);
    s_shell_print_dc = 0;
    s_shell_print_in_page = 0;
    InterlockedExchange(&s_shell_print_claim, 0);
    return l_ok;
}

/* Throw the document away. */
static void shell_print_abort(void) {
    if (!s_shell_print_dc) return;
    AbortDoc(s_shell_print_dc);
    DeleteDC(s_shell_print_dc);
    s_shell_print_dc = 0;
    s_shell_print_in_page = 0;
    InterlockedExchange(&s_shell_print_claim, 0);
}

static int shell_print_caps(int l_index) {
    return s_shell_print_dc ? GetDeviceCaps(s_shell_print_dc, l_index) : 0;
}

static void* shell_print_dc(void) {
    return (void*)s_shell_print_dc;
}

static int shell_print_in_page(void) {
    return s_shell_print_in_page;
}

#endif
