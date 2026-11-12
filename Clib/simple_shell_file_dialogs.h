/* simple_shell_file_dialogs.h - the system's own Save and folder dialogs (2026-11-11).

   Beside the Open dialog (shell_open_file_dialog in simple_shell.h), so a program asks
   where to save, and which folder, in the platform's own dialog: Windows here, GTK and
   AppKit in their halves (declared by shell_posix.h). Owned by the caller's window
   (null: the shell's own window), modal, blocking until the user answers. Answers 1
   and the full path in `l_out' when the user chose, 0 when cancelled. Nothing kept
   between calls. */

#ifndef SIMPLE_SHELL_FILE_DIALOGS_H
#define SIMPLE_SHELL_FILE_DIALOGS_H

#ifdef _WIN32

#include "simple_shell.h"
#include <commdlg.h>
/* IFileOpenDialog (folders) is Vista and later; raise the SDK target here only, as the
   spell-checking section does, and define the GUIDs locally (no initguid trouble). */
#undef NTDDI_VERSION
#define NTDDI_VERSION 0x06020000
#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0602
#include <objbase.h>
#include <shobjidl.h>
#pragma comment(lib, "comdlg32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

static const CLSID s_sfd_clsid_open = {0xDC1C5A9C,0xE88A,0x4DDE,{0xA5,0xA1,0x60,0xF8,0x2A,0x20,0xAE,0xF7}};
static const IID s_sfd_iid_open = {0xD57C7288,0xD4AD,0x4768,{0xBE,0x02,0x9D,0x96,0x95,0x32,0xD9,0x60}};
static const IID s_sfd_iid_item = {0x43826D1E,0xE718,0x42EE,{0xBC,0x55,0xA1,0xE2,0x61,0xC3,0x7B,0xFE}};

/* The filter "Desc|*.pdf;*.txt|All files|*.*" as the double-NUL list the API wants, and
   its first extension ("pdf") as the default the dialog adds to a bare name. */
static void shell_sfd_filter(const wchar_t* a_filter, wchar_t* a_pairs, int a_cap, wchar_t* a_ext, int a_ext_cap)
{
    int i = 0, k = 0;
    const wchar_t* l_star = a_filter ? wcsstr(a_filter, L"*.") : 0;
    while (a_filter && a_filter[i] && i < a_cap - 3) {
        a_pairs[i] = (a_filter[i] == L'|') ? 0 : a_filter[i];
        i++;
    }
    a_pairs[i] = 0;
    a_pairs[i + 1] = 0;
    a_ext[0] = 0;
    if (l_star && l_star[2] != L'*') {
        l_star += 2;
        while (l_star[k] && l_star[k] != L';' && l_star[k] != L'|' && k < a_ext_cap - 1) {
            a_ext[k] = l_star[k];
            k++;
        }
        a_ext[k] = 0;
    }
}

static const CLSID s_sfd_clsid_save = {0xC0B4E2F3,0xBA21,0x4773,{0x8D,0xBA,0x33,0x5E,0xC9,0x46,0xEB,0x8B}};
static const IID s_sfd_iid_save = {0x84BCCD23,0x5FDE,0x4CDB,{0xAE,0xA4,0xAF,0x64,0xB8,0x3D,0x78,0xAB}};

/* IFileSaveDialog: SetFolder starts in `a_initial_dir' whatever the user last used (the
   classic GetSaveFileNameW lets its remembered folder win, even over a full path). */
static int shell_save_file_dialog(void* a_owner, const wchar_t* a_title, const wchar_t* a_filter,
        const wchar_t* a_initial_dir, const wchar_t* a_name, wchar_t* l_out, int l_cap)
{
    IFileSaveDialog* d = NULL;
    IShellItem* l_item = NULL;
    IShellItem* l_start = NULL;
    FILEOPENDIALOGOPTIONS l_options = 0;
    COMDLG_FILTERSPEC l_specs[8];
    wchar_t l_pairs[1024];
    wchar_t l_ext[32];
    PWSTR l_path = NULL;
    HRESULT l_hr, l_init;
    int l_answer = 0, n = 0, i = 0;
    const wchar_t* l_part;
    if (!l_out || l_cap <= 1) return 0;
    l_out[0] = 0;
    shell_sfd_filter(a_filter, l_pairs, 1024, l_ext, 32);
    /* the double-NUL list as name/pattern pairs */
    l_part = l_pairs;
    while (*l_part && n < 8) {
        l_specs[n].pszName = l_part;
        l_part += wcslen(l_part) + 1;
        if (!*l_part) break;
        l_specs[n].pszSpec = l_part;
        l_part += wcslen(l_part) + 1;
        n++;
    }
    l_init = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    l_hr = CoCreateInstance(&s_sfd_clsid_save, NULL, CLSCTX_INPROC_SERVER, &s_sfd_iid_save, (void**) &d);
    if (SUCCEEDED(l_hr) && d) {
        if (SUCCEEDED(d->lpVtbl->GetOptions(d, &l_options))) {
            d->lpVtbl->SetOptions(d, l_options | FOS_OVERWRITEPROMPT | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
        }
        if (n > 0) d->lpVtbl->SetFileTypes(d, (UINT) n, l_specs);
        if (l_ext[0]) d->lpVtbl->SetDefaultExtension(d, l_ext);
        if (a_title && a_title[0]) d->lpVtbl->SetTitle(d, a_title);
        if (a_name && a_name[0]) d->lpVtbl->SetFileName(d, a_name);
        if (a_initial_dir && a_initial_dir[0]
            && SUCCEEDED(SHCreateItemFromParsingName(a_initial_dir, NULL, &s_sfd_iid_item, (void**) &l_start)) && l_start) {
            d->lpVtbl->SetFolder(d, l_start);
            l_start->lpVtbl->Release(l_start);
        }
        if (SUCCEEDED(d->lpVtbl->Show(d, a_owner ? (HWND) a_owner : s_shell_hwnd))
            && SUCCEEDED(d->lpVtbl->GetResult(d, &l_item)) && l_item) {
            if (SUCCEEDED(l_item->lpVtbl->GetDisplayName(l_item, SIGDN_FILESYSPATH, &l_path)) && l_path) {
                if ((int) wcslen(l_path) < l_cap) {
                    wcscpy(l_out, l_path);
                    l_answer = 1;
                }
                CoTaskMemFree(l_path);
            }
            l_item->lpVtbl->Release(l_item);
        }
        d->lpVtbl->Release(d);
    }
    if (SUCCEEDED(l_init)) CoUninitialize();
    (void) i;
    return l_answer;
}

static int shell_choose_folder_dialog(void* a_owner, const wchar_t* a_title, const wchar_t* a_initial_dir,
        wchar_t* l_out, int l_cap)
{
    IFileOpenDialog* d = NULL;
    IShellItem* l_item = NULL;
    IShellItem* l_start = NULL;
    FILEOPENDIALOGOPTIONS l_options = 0;
    PWSTR l_path = NULL;
    HRESULT l_hr, l_init;
    int l_answer = 0;
    if (!l_out || l_cap <= 1) return 0;
    l_out[0] = 0;
    l_init = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    l_hr = CoCreateInstance(&s_sfd_clsid_open, NULL, CLSCTX_INPROC_SERVER, &s_sfd_iid_open, (void**) &d);
    if (SUCCEEDED(l_hr) && d) {
        if (SUCCEEDED(d->lpVtbl->GetOptions(d, &l_options))) {
            d->lpVtbl->SetOptions(d, l_options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
        }
        if (a_title && a_title[0]) d->lpVtbl->SetTitle(d, a_title);
        if (a_initial_dir && a_initial_dir[0]
            && SUCCEEDED(SHCreateItemFromParsingName(a_initial_dir, NULL, &s_sfd_iid_item, (void**) &l_start)) && l_start) {
            d->lpVtbl->SetFolder(d, l_start);
            l_start->lpVtbl->Release(l_start);
        }
        if (SUCCEEDED(d->lpVtbl->Show(d, a_owner ? (HWND) a_owner : s_shell_hwnd))
            && SUCCEEDED(d->lpVtbl->GetResult(d, &l_item)) && l_item) {
            if (SUCCEEDED(l_item->lpVtbl->GetDisplayName(l_item, SIGDN_FILESYSPATH, &l_path)) && l_path) {
                if ((int) wcslen(l_path) < l_cap) {
                    wcscpy(l_out, l_path);
                    l_answer = 1;
                }
                CoTaskMemFree(l_path);
            }
            l_item->lpVtbl->Release(l_item);
        }
        d->lpVtbl->Release(d);
    }
    if (SUCCEEDED(l_init)) CoUninitialize();
    return l_answer;
}

#else

#include "shell_posix.h"

#endif /* _WIN32 */

#endif /* SIMPLE_SHELL_FILE_DIALOGS_H */
