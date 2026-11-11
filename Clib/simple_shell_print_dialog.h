/* simple_shell_print_dialog.h - the Windows print dialog (1v-c, 2026-11-11).

   PrintDlgExW, owned by the caller's window. It only asks: the printer, the
   page range, copies and collation, and the DEVMODE choices a print helper
   can take (duplex, paper source, paper size, orientation). Nothing is kept
   between calls: every answer goes into the caller's buffers, so no static
   state forks per translation unit.

   Windows only. On Linux and macOS a program prints an existing PDF through
   its toolkit's print operation, whose dialog is part of it (simple_pdf's
   print library), so SHELL_PRINT_DIALOG.show requires Windows. */

#ifndef SIMPLE_SHELL_PRINT_DIALOG_H
#define SIMPLE_SHELL_PRINT_DIALOG_H

#ifdef _WIN32

#include <string.h>
#include <wchar.h>
#include <windows.h>
/* commdlg.h declares PRINTDLGEXW only when STDMETHOD is defined (objbase.h), which a
   lean windows.h does not bring in: a client's translation unit failed with C2065. */
#include <objbase.h>
#include <commdlg.h>

#pragma comment(lib, "comdlg32.lib")

/* Show the dialog over `a_owner' (the desktop when null) for a document of
   `a_max_page' pages (0: no page range). The chosen printer's name goes into
   `a_name' (`a_name_cap' wide characters, terminated). `a_ints' has 10 slots:
     [0] copies   [1] collated (0/1)   [2] all pages (0/1)
     [3] first page   [4] last page
     [5] duplex: 0 not set, 1 off, 2 long edge, 3 short edge
     [6] paper source (DMBIN_*; 0 not set)   [7] paper size (DMPAPER_*; 0 not set)
     [8] orientation: 0 not set, 1 portrait, 2 landscape
     [9] the error code when the answer is -1
   Answers 1 print, 0 cancel, -1 failed. */
static int shell_print_dialog_show(HWND a_owner, int a_max_page, wchar_t* a_name, int a_name_cap, int* a_ints)
{
    PRINTDLGEXW l_pd;
    PRINTPAGERANGE l_range;
    HRESULT l_hr;
    DEVNAMES* l_names;
    DEVMODEW* l_mode;
    int l_answer = -1;
    int l_i;

    for (l_i = 0; l_i < 10; l_i++) a_ints[l_i] = 0;
    if (a_name_cap > 0) a_name[0] = 0;
    memset(&l_pd, 0, sizeof(l_pd));
    memset(&l_range, 0, sizeof(l_range));
    l_pd.lStructSize = sizeof(l_pd);
    l_pd.hwndOwner = a_owner ? a_owner : GetDesktopWindow();
    l_pd.Flags = PD_NOSELECTION | PD_NOCURRENTPAGE;
    if (a_max_page > 0) {
        l_range.nFromPage = 1;
        l_range.nToPage = (DWORD) a_max_page;
        l_pd.nPageRanges = 0;
        l_pd.nMaxPageRanges = 1;
        l_pd.lpPageRanges = &l_range;
        l_pd.nMinPage = 1;
        l_pd.nMaxPage = (DWORD) a_max_page;
    } else {
        l_pd.Flags |= PD_NOPAGENUMS;
    }
    l_pd.nCopies = 1;
    l_pd.nStartPage = START_PAGE_GENERAL;

    l_hr = PrintDlgExW(&l_pd);
    if (l_hr != S_OK) {
        a_ints[9] = (int) l_hr;
    } else if (l_pd.dwResultAction != PD_RESULT_PRINT) {
        /* Cancel, or Apply then close: nothing is printed. */
        l_answer = 0;
    } else {
        l_answer = 1;
        a_ints[0] = l_pd.nCopies > 0 ? (int) l_pd.nCopies : 1;
        a_ints[1] = (l_pd.Flags & PD_COLLATE) ? 1 : 0;
        if ((l_pd.Flags & PD_PAGENUMS) && l_pd.nPageRanges > 0) {
            a_ints[2] = 0;
            a_ints[3] = (int) l_pd.lpPageRanges[0].nFromPage;
            a_ints[4] = (int) l_pd.lpPageRanges[0].nToPage;
        } else {
            a_ints[2] = 1;
        }
        if (l_pd.hDevNames && a_name_cap > 1) {
            l_names = (DEVNAMES*) GlobalLock(l_pd.hDevNames);
            if (l_names) {
                wcsncpy(a_name, (const wchar_t*) l_names + l_names->wDeviceOffset, (size_t) (a_name_cap - 1));
                a_name[a_name_cap - 1] = 0;
                GlobalUnlock(l_pd.hDevNames);
            }
        }
        if (l_pd.hDevMode) {
            l_mode = (DEVMODEW*) GlobalLock(l_pd.hDevMode);
            if (l_mode) {
                if (l_mode->dmFields & DM_DUPLEX) {
                    a_ints[5] = l_mode->dmDuplex == DMDUP_SIMPLEX ? 1
                              : l_mode->dmDuplex == DMDUP_VERTICAL ? 2
                              : l_mode->dmDuplex == DMDUP_HORIZONTAL ? 3 : 0;
                }
                if (l_mode->dmFields & DM_DEFAULTSOURCE) a_ints[6] = l_mode->dmDefaultSource;
                if (l_mode->dmFields & DM_PAPERSIZE) a_ints[7] = l_mode->dmPaperSize;
                if (l_mode->dmFields & DM_ORIENTATION) {
                    a_ints[8] = l_mode->dmOrientation == DMORIENT_LANDSCAPE ? 2 : 1;
                }
                GlobalUnlock(l_pd.hDevMode);
            }
        }
        if (a_name_cap > 0 && a_name[0] == 0) {
            /* Print without a printer name: report it rather than guess. */
            l_answer = -1;
            a_ints[9] = -2;
        }
    }
    if (l_pd.hDevMode) GlobalFree(l_pd.hDevMode);
    if (l_pd.hDevNames) GlobalFree(l_pd.hDevNames);
    return l_answer;
}

#endif /* _WIN32 */

#endif /* SIMPLE_SHELL_PRINT_DIALOG_H */
