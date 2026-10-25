/* shell_uia_client.h - test-only: a UI Automation CLIENT that reads back
   what simple_shell_uia.h serves (GW-14). It runs on a worker thread while
   the calling thread pumps messages, so WM_GETOBJECT is answered whatever
   thread UI Automation asks from. The probe window uses the real
   shell_wndproc, so the shipped WM_GETOBJECT path is the one tested. */

#ifndef SHELL_UIA_CLIENT_H
#define SHELL_UIA_CLIENT_H

#include "simple_shell_uia.h"
#include <UIAutomationClient.h>

static const CLSID shell_clsid_cuia =
    {0xff48dba4, 0x60ef, 0x4201, {0xaa, 0x87, 0x54, 0x10, 0x3e, 0xef, 0x59, 0x4e}};
static const IID shell_iid_iuia =
    {0x30cbe57d, 0xd9d0, 0x452a, {0xab, 0x13, 0x7a, 0xc5, 0xac, 0x48, 0x25, 0xee}};

typedef struct shell_uia_job_s {
    HWND l_hwnd;
    wchar_t* l_out;
    int l_cap;
    int l_len;
    HRESULT l_hr;
} shell_uia_job;

static void shell_uia_put(shell_uia_job* l_job, const wchar_t* l_text) {
    while (l_text && *l_text && l_job->l_len < l_job->l_cap - 1)
        l_job->l_out[l_job->l_len++] = *l_text++;
    l_job->l_out[l_job->l_len] = 0;
}

/* One line per descendant: name|control type[=value][*] (* has focus). */
static DWORD WINAPI shell_uia_client_main(LPVOID l_arg) {
    shell_uia_job* l_job = (shell_uia_job*)l_arg;
    IUIAutomation* l_ua = 0;
    IUIAutomationElement* l_root = 0;
    IUIAutomationCondition* l_cond = 0;
    IUIAutomationElementArray* l_all = 0;
    IUIAutomationElement* l_e;
    int l_n = 0, l_i;
    BSTR l_name;
    CONTROLTYPEID l_type;
    VARIANT l_v;
    wchar_t l_num[16];
    HRESULT l_hr;
    CoInitializeEx(0, COINIT_MULTITHREADED);
    l_hr = CoCreateInstance(&shell_clsid_cuia, 0, CLSCTX_INPROC_SERVER, &shell_iid_iuia, (void**)&l_ua);
    if (SUCCEEDED(l_hr)) l_hr = IUIAutomation_ElementFromHandle(l_ua, l_job->l_hwnd, &l_root);
    if (SUCCEEDED(l_hr)) l_hr = IUIAutomation_CreateTrueCondition(l_ua, &l_cond);
    if (SUCCEEDED(l_hr)) l_hr = IUIAutomationElement_FindAll(l_root, TreeScope_Descendants, l_cond, &l_all);
    if (SUCCEEDED(l_hr) && l_all) IUIAutomationElementArray_get_Length(l_all, &l_n);
    for (l_i = 0; SUCCEEDED(l_hr) && l_i < l_n; l_i++) {
        l_e = 0;
        if (SUCCEEDED(IUIAutomationElementArray_GetElement(l_all, l_i, &l_e)) && l_e) {
            l_name = 0; l_type = 0;
            IUIAutomationElement_get_CurrentName(l_e, &l_name);
            IUIAutomationElement_get_CurrentControlType(l_e, &l_type);
            shell_uia_put(l_job, l_name ? l_name : L"");
            wsprintfW(l_num, L"|%d", (int)l_type);
            shell_uia_put(l_job, l_num);
            VariantInit(&l_v);
            if (SUCCEEDED(IUIAutomationElement_GetCurrentPropertyValue(l_e, 30045, &l_v))
                && l_v.vt == VT_BSTR && l_v.bstrVal && l_v.bstrVal[0]) {
                shell_uia_put(l_job, L"=");
                shell_uia_put(l_job, l_v.bstrVal);
            }
            VariantClear(&l_v);
            VariantInit(&l_v);
            if (SUCCEEDED(IUIAutomationElement_GetCurrentPropertyValue(l_e, SHELL_UIA_PROP_HAS_FOCUS, &l_v))
                && l_v.vt == VT_BOOL && l_v.boolVal == VARIANT_TRUE)
                shell_uia_put(l_job, L"*");
            VariantClear(&l_v);
            shell_uia_put(l_job, L"\n");
            if (l_name) SysFreeString(l_name);
            IUIAutomationElement_Release(l_e);
        }
    }
    if (l_all) IUIAutomationElementArray_Release(l_all);
    if (l_cond) IUIAutomationCondition_Release(l_cond);
    if (l_root) IUIAutomationElement_Release(l_root);
    if (l_ua) IUIAutomation_Release(l_ua);
    l_job->l_hr = l_hr;
    CoUninitialize();
    return 0;
}

/* Read the tree under window `l_hwnd' into `l_out' (`l_cap' wide chars).
   Answers the length, or -1 when the client did not finish in 15 seconds,
   or -2 when it failed (its HRESULT in `last_uia_hr'). */
SHELL_SHARED HRESULT s_uia_client_hr = 0;

static int shell_uia_client_read(void* l_hwnd, wchar_t* l_out, int l_cap) {
    shell_uia_job l_job;
    HANDLE l_thread;
    MSG l_msg;
    DWORD l_start, l_wait;
    l_job.l_hwnd = (HWND)l_hwnd;
    l_job.l_out = l_out;
    l_job.l_cap = l_cap;
    l_job.l_len = 0;
    l_job.l_hr = E_FAIL;
    l_out[0] = 0;
    l_thread = CreateThread(0, 0, shell_uia_client_main, &l_job, 0, 0);
    if (!l_thread) return -2;
    l_start = GetTickCount();
    for (;;) {
        l_wait = MsgWaitForMultipleObjects(1, &l_thread, FALSE, 100, QS_ALLINPUT);
        if (l_wait == WAIT_OBJECT_0) break;
        while (PeekMessageW(&l_msg, 0, 0, 0, PM_REMOVE)) {
            TranslateMessage(&l_msg);
            DispatchMessageW(&l_msg);
        }
        if (GetTickCount() - l_start > 15000) return -1;
    }
    CloseHandle(l_thread);
    s_uia_client_hr = l_job.l_hr;
    if (FAILED(l_job.l_hr)) return -2;
    return l_job.l_len;
}

/* Call node `l_id''s SetFocus from a worker thread, as UI Automation would,
   pumping meanwhile; answers 1 when the call returned S_OK. */
typedef struct shell_uia_focus_job_s { int l_id; HRESULT l_hr; volatile LONG l_step; } shell_uia_focus_job;

static DWORD WINAPI shell_uia_focus_main(LPVOID l_arg) {
    shell_uia_focus_job* l_job = (shell_uia_focus_job*)l_arg;
    shell_uia_el* l_el = shell_uia_new(l_job->l_id);
    IRawElementProviderFragment* l_f;
    l_job->l_step = 1;
    if (!l_el) { l_job->l_hr = E_OUTOFMEMORY; return 0; }
    l_f = (IRawElementProviderFragment*)&l_el->l_fragment;
    l_job->l_step = 2;
    l_job->l_hr = l_f->lpVtbl->SetFocus(l_f);
    l_job->l_step = 3;
    l_f->lpVtbl->Release(l_f);
    l_job->l_step = 4;
    return 0;
}

static int shell_uia_focus_from_worker(int l_id) {
    shell_uia_focus_job l_job;
    HANDLE l_thread;
    MSG l_msg;
    DWORD l_start;
    l_job.l_id = l_id;
    l_job.l_hr = E_FAIL;
    l_job.l_step = 0;
    l_thread = CreateThread(0, 0, shell_uia_focus_main, &l_job, 0, 0);
    if (!l_thread) return -1;
    l_start = GetTickCount();
    /* pump while waiting: the posted focus message must reach the window
       procedure, and an unread message keeps MsgWait answering 'input' */
    while (WaitForSingleObject(l_thread, 0) != WAIT_OBJECT_0) {
        MsgWaitForMultipleObjects(1, &l_thread, FALSE, 50, QS_ALLINPUT);
        while (PeekMessageW(&l_msg, 0, 0, 0, PM_REMOVE)) {
            TranslateMessage(&l_msg);
            DispatchMessageW(&l_msg);
        }
        if (GetTickCount() - l_start > 5000) return -20 - (int)l_job.l_step;
    }
    CloseHandle(l_thread);
        /* then let the posted message reach the window procedure */
    while (PeekMessageW(&l_msg, 0, 0, 0, PM_REMOVE)) {
        TranslateMessage(&l_msg);
        DispatchMessageW(&l_msg);
    }
    return (int)l_job.l_hr;
}

static int shell_uia_focus_pushed_on_this_thread(void) {
    return s_uia_focus_push_thread == GetCurrentThreadId() ? 1 : 0;
}

/* A hidden, offscreen probe window on the shipped window procedure. */
static void* shell_uia_probe_window(void) {
    WNDCLASSEXW l_wc;
    ZeroMemory(&l_wc, sizeof(l_wc));
    l_wc.cbSize = sizeof(l_wc);
    l_wc.lpfnWndProc = shell_wndproc;
    l_wc.hInstance = GetModuleHandleW(0);
    l_wc.lpszClassName = L"SimpleShellUiaProbe";
    RegisterClassExW(&l_wc);
    return CreateWindowExW(WS_EX_TOOLWINDOW, L"SimpleShellUiaProbe", L"uia probe", WS_POPUP,
        -3000, -3000, 400, 300, 0, 0, GetModuleHandleW(0), 0);
}

/* Close it; shell_wndproc posts WM_QUIT on WM_DESTROY, which must not
   reach a later test's pump. */
static void shell_uia_probe_close(void* l_hwnd) {
    MSG l_msg;
    DestroyWindow((HWND)l_hwnd);
    while (PeekMessageW(&l_msg, 0, WM_QUIT, WM_QUIT, PM_REMOVE)) {}
}

#endif
