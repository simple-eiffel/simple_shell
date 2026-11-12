/* shell_dialog_autoanswer.h - test only: answer the next system file dialog this process
   shows, so the Save and folder dialogs are tested with no person (2026-11-11).

   A thread waits for this process's visible dialog window (class #32770), then either
   types `text' into its file-name box (control 1148, the Explorer dialog's "File name"
   or "Folder" box, an Edit inside a combo box) and presses OK, or presses Cancel. */

#ifndef SHELL_DIALOG_AUTOANSWER_H
#define SHELL_DIALOG_AUTOANSWER_H

#ifdef _WIN32
#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

typedef struct { int action; wchar_t text[1024]; } SDA_JOB;

typedef struct { HWND found; DWORD pid; } SDA_FIND;

static BOOL CALLBACK sda_each(HWND h, LPARAM l)
{
    SDA_FIND* f = (SDA_FIND*) l;
    DWORD pid = 0;
    wchar_t cls[16];
    GetWindowThreadProcessId(h, &pid);
    if (pid == f->pid && IsWindowVisible(h) && GetClassNameW(h, cls, 16) && wcscmp(cls, L"#32770") == 0) {
        f->found = h;
        return FALSE;
    }
    return TRUE;
}

/* The file-name box: control 1148 at any depth (the modern dialog nests it in panes). */
static BOOL CALLBACK sda_box(HWND h, LPARAM l)
{
    if (GetDlgCtrlID(h) == 1148) {
        *(HWND*) l = h;
        return FALSE;
    }
    return TRUE;
}

/* The first Edit at any depth under the file-name box (combo box, then edit). */
static BOOL CALLBACK sda_edit(HWND h, LPARAM l)
{
    wchar_t cls[16];
    if (GetClassNameW(h, cls, 16) && wcscmp(cls, L"Edit") == 0) {
        *(HWND*) l = h;
        return FALSE;
    }
    return TRUE;
}

static DWORD WINAPI sda_thread(LPVOID p)
{
    SDA_JOB* job = (SDA_JOB*) p;
    SDA_FIND f;
    HWND box, edit;
    int i;
    f.found = NULL;
    f.pid = GetCurrentProcessId();
    for (i = 0; i < 150 && !f.found; i++) {
        Sleep(100);
        EnumWindows(sda_each, (LPARAM) &f);
    }
    if (f.found) {
        Sleep(400);
        if (job->action == 1) {
            box = NULL;
            EnumChildWindows(f.found, sda_box, (LPARAM) &box);
            edit = NULL;
            if (box) EnumChildWindows(box, sda_edit, (LPARAM) &edit);
            if (!edit) edit = box;
            if (edit && job->text[0]) SendMessageW(edit, WM_SETTEXT, 0, (LPARAM) job->text);
            Sleep(150);
            PostMessageW(f.found, WM_COMMAND, IDOK, 0);
        } else {
            PostMessageW(f.found, WM_COMMAND, IDCANCEL, 0);
        }
    }
    free(job);
    return 0;
}

/* Answer the next dialog: `a_action' 1 types `a_text' and presses OK, 0 presses Cancel. */
static void sda_answer_next(int a_action, const wchar_t* a_text)
{
    SDA_JOB* job = (SDA_JOB*) calloc(1, sizeof(SDA_JOB));
    HANDLE t;
    if (!job) return;
    job->action = a_action;
    if (a_text) wcsncpy(job->text, a_text, 1023);
    t = CreateThread(NULL, 0, sda_thread, job, 0, NULL);
    if (t) CloseHandle(t); else free(job);
}
#else
static void sda_answer_next(int a_action, const void* a_text) { (void) a_action; (void) a_text; }
#endif

#endif /* SHELL_DIALOG_AUTOANSWER_H */
