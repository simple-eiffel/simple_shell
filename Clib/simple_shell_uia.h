/* simple_shell_uia.h - the UI Automation bridge (1.22.0, GW-14).

   A drawn toolkit has no child windows for a screen reader to find, so
   this header serves UI Automation from a TABLE the application publishes:
   one row per element - id, parent, control type, name, value, bounds in
   client coordinates, focusable, enabled. Node 0 is the window's content
   root; every other node names its parent, and rows come in tree order
   (a parent before its children, siblings in reading order).

   HOW IT IS REACHED. simple_shell.h's window procedure answers
   WM_GETOBJECT through `s_shell_getobject_hook' when one is set; enabling
   the bridge sets it here. Keeping the COM headers in this file keeps them
   out of every translation unit that includes simple_shell.h (the 1.9.1
   SDK-macro lesson: see SDK_MACRO_TRIPWIRE).

   THREADS. UI Automation may call a provider on its own threads, so every
   read of the table happens under `s_uia_lock', and a published table is
   swapped in whole. Element objects carry only an id; an id no longer in
   the table answers UIA_E_ELEMENTNOTAVAILABLE.

   SHARED STATE follows simple_shell.h's law: SHELL_SHARED data with
   explicit initializers, so every translation unit sees one table.
   Identifiers carry the l_ / shell_ prefixes (no SDK macro may capture
   them). */

#ifndef SIMPLE_SHELL_UIA_H
#define SIMPLE_SHELL_UIA_H

#ifndef COBJMACROS
#define COBJMACROS
#endif
#include <stddef.h>
#include <windows.h>
#include <ole2.h>
#include <oleauto.h>
/* UIAutomationCore.h DEFINES `const double UIA_ScrollPatternNoScroll = -1;'
   at file scope - external linkage in C - so two translation units that
   include it fail to link (LNK2005, seen 2026-10-25). Renamed into a
   linker-merged (selectany) definition, the SHELL_SHARED pattern. */
#define UIA_ScrollPatternNoScroll SHELL_SHARED shell_uia_scroll_pattern_no_scroll
#include <UIAutomationCore.h>
#include <UIAutomationCoreApi.h>
#include "simple_shell.h"

#pragma comment(lib, "uiautomationcore.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

/* Ids, spelled out (UIAutomationClient.h is a client header). */
#define SHELL_UIA_PATTERN_VALUE        10002
#define SHELL_UIA_EVENT_FOCUS_CHANGED  20005
#define SHELL_UIA_PROP_CONTROL_TYPE    30003
#define SHELL_UIA_PROP_NAME            30005
#define SHELL_UIA_PROP_HAS_FOCUS       30008
#define SHELL_UIA_PROP_FOCUSABLE       30009
#define SHELL_UIA_PROP_ENABLED         30010
#define SHELL_UIA_PROP_AUTOMATION_ID   30011
#define SHELL_UIA_PROP_CLASS_NAME      30012
#define SHELL_UIA_PROP_CONTROL_ELEMENT 30016
#define SHELL_UIA_PROP_CONTENT_ELEMENT 30017
#define SHELL_UIA_PROP_FRAMEWORK_ID    30024
#define SHELL_UIA_E_NOT_AVAILABLE      ((HRESULT)0x80040201L)
#define SHELL_UIA_E_NOT_SUPPORTED      ((HRESULT)0x80040204L)

/* The interface ids, from UIAutomationCore.h's MIDL_INTERFACE lines (no
   import library is assumed to carry them). */
static const IID shell_iid_simple =
    {0xd6dd68d1, 0x86fd, 0x4332, {0x86, 0x66, 0x9a, 0xbe, 0xde, 0xa2, 0xd2, 0x4c}};
static const IID shell_iid_fragment =
    {0xf7063da8, 0x8359, 0x439c, {0x92, 0x97, 0xbb, 0xc5, 0x29, 0x9a, 0x7d, 0x87}};
static const IID shell_iid_fragment_root =
    {0x620ce2a5, 0xab8f, 0x40a9, {0x86, 0xcb, 0xde, 0x3c, 0x75, 0x59, 0x9b, 0x58}};
static const IID shell_iid_value =
    {0xc7935180, 0x6fb3, 0x4201, {0xb1, 0x74, 0x7d, 0xf7, 0x3a, 0xdb, 0xf6, 0x4a}};
static const IID shell_iid_unknown =
    {0x00000000, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};

/* ------------------------------------------------------------ the table */

typedef struct shell_uia_node_s {
    int l_id;
    int l_parent;
    int l_role;
    int l_focusable;
    int l_enabled;
    int l_has_value;
    double l_x, l_y, l_w, l_h;
    wchar_t* l_name;
    wchar_t* l_value;
} shell_uia_node;

SHELL_SHARED shell_uia_node* s_uia_nodes = 0;
SHELL_SHARED int s_uia_count = 0;
SHELL_SHARED shell_uia_node* s_uia_stage = 0;
SHELL_SHARED int s_uia_stage_count = 0;
SHELL_SHARED int s_uia_stage_cap = 0;
SHELL_SHARED HWND s_uia_hwnd = 0;
SHELL_SHARED int s_uia_focus = 0;
SHELL_SHARED LONG s_uia_lock_state = 0;
SHELL_SHARED CRITICAL_SECTION s_uia_lock = {0};

static void shell_uia_lock_enter(void) {
    if (InterlockedCompareExchange(&s_uia_lock_state, 1, 0) == 0) {
        InitializeCriticalSection(&s_uia_lock);
        InterlockedExchange(&s_uia_lock_state, 2);
    }
    while (s_uia_lock_state != 2) Sleep(0);
    EnterCriticalSection(&s_uia_lock);
}

static void shell_uia_lock_leave(void) {
    LeaveCriticalSection(&s_uia_lock);
}

static wchar_t* shell_uia_copy(const wchar_t* l_text) {
    size_t l_n;
    wchar_t* l_copy;
    if (!l_text) return 0;
    l_n = wcslen(l_text);
    l_copy = (wchar_t*)malloc((l_n + 1) * sizeof(wchar_t));
    if (l_copy) memcpy(l_copy, l_text, (l_n + 1) * sizeof(wchar_t));
    return l_copy;
}

static void shell_uia_free_table(shell_uia_node* l_table, int l_count) {
    int l_i;
    if (!l_table) return;
    for (l_i = 0; l_i < l_count; l_i++) {
        free(l_table[l_i].l_name);
        free(l_table[l_i].l_value);
    }
    free(l_table);
}

/* Index of node `l_id' in the live table, or -1. Call under the lock. */
static int shell_uia_index(int l_id) {
    int l_i;
    for (l_i = 0; l_i < s_uia_count; l_i++)
        if (s_uia_nodes[l_i].l_id == l_id) return l_i;
    return -1;
}

/* ------------------------------------------------------------ elements */

typedef struct shell_uia_el_s {
    IRawElementProviderSimpleVtbl* l_simple;
    IRawElementProviderFragmentVtbl* l_fragment;
    IRawElementProviderFragmentRootVtbl* l_root;
    IValueProviderVtbl* l_valuep;
    LONG l_refs;
    int l_id;
} shell_uia_el;

#define SHELL_UIA_FROM(l_p, l_field) \
    ((shell_uia_el*)((char*)(l_p) - offsetof(shell_uia_el, l_field)))

static shell_uia_el* shell_uia_new(int l_id);

static ULONG shell_uia_addref_el(shell_uia_el* l_el) {
    return (ULONG)InterlockedIncrement(&l_el->l_refs);
}

static ULONG shell_uia_release_el(shell_uia_el* l_el) {
    LONG l_left = InterlockedDecrement(&l_el->l_refs);
    if (l_left == 0) free(l_el);
    return (ULONG)l_left;
}

static int shell_uia_has_value(int l_id) {
    int l_k, l_has = 0;
    shell_uia_lock_enter();
    l_k = shell_uia_index(l_id);
    if (l_k >= 0) l_has = s_uia_nodes[l_k].l_has_value;
    shell_uia_lock_leave();
    return l_has;
}

static HRESULT shell_uia_qi_el(shell_uia_el* l_el, REFIID l_riid, void** l_out) {
    if (!l_out) return E_POINTER;
    *l_out = 0;
    if (IsEqualIID(l_riid, &shell_iid_unknown) || IsEqualIID(l_riid, &shell_iid_simple))
        *l_out = &l_el->l_simple;
    else if (IsEqualIID(l_riid, &shell_iid_fragment))
        *l_out = &l_el->l_fragment;
    else if (l_el->l_id == 0 && IsEqualIID(l_riid, &shell_iid_fragment_root))
        *l_out = &l_el->l_root;
    else if (IsEqualIID(l_riid, &shell_iid_value) && shell_uia_has_value(l_el->l_id))
        *l_out = &l_el->l_valuep;
    else
        return E_NOINTERFACE;
    shell_uia_addref_el(l_el);
    return S_OK;
}

/* --- IRawElementProviderSimple */

static HRESULT STDMETHODCALLTYPE shell_uia_s_qi(IRawElementProviderSimple* l_p, REFIID l_riid, void** l_out) {
    return shell_uia_qi_el(SHELL_UIA_FROM(l_p, l_simple), l_riid, l_out);
}
static ULONG STDMETHODCALLTYPE shell_uia_s_addref(IRawElementProviderSimple* l_p) {
    return shell_uia_addref_el(SHELL_UIA_FROM(l_p, l_simple));
}
static ULONG STDMETHODCALLTYPE shell_uia_s_release(IRawElementProviderSimple* l_p) {
    return shell_uia_release_el(SHELL_UIA_FROM(l_p, l_simple));
}
static HRESULT STDMETHODCALLTYPE shell_uia_s_options(IRawElementProviderSimple* l_p, enum ProviderOptions* l_out) {
    (void)l_p;
    if (!l_out) return E_POINTER;
    *l_out = ProviderOptions_ServerSideProvider;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE shell_uia_s_pattern(IRawElementProviderSimple* l_p, PATTERNID l_pattern, IUnknown** l_out) {
    shell_uia_el* l_el = SHELL_UIA_FROM(l_p, l_simple);
    if (!l_out) return E_POINTER;
    *l_out = 0;
    if (l_pattern == SHELL_UIA_PATTERN_VALUE && shell_uia_has_value(l_el->l_id)) {
        *l_out = (IUnknown*)&l_el->l_valuep;
        shell_uia_addref_el(l_el);
    }
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE shell_uia_s_property(IRawElementProviderSimple* l_p, PROPERTYID l_prop, VARIANT* l_out) {
    shell_uia_el* l_el = SHELL_UIA_FROM(l_p, l_simple);
    shell_uia_node* l_n;
    int l_k;
    wchar_t l_aid[32];
    if (!l_out) return E_POINTER;
    VariantInit(l_out);
    shell_uia_lock_enter();
    l_k = shell_uia_index(l_el->l_id);
    if (l_k < 0) {
        shell_uia_lock_leave();
        return SHELL_UIA_E_NOT_AVAILABLE;
    }
    l_n = &s_uia_nodes[l_k];
    switch (l_prop) {
        case SHELL_UIA_PROP_NAME:
            if (l_n->l_name) { l_out->vt = VT_BSTR; l_out->bstrVal = SysAllocString(l_n->l_name); }
            break;
        case SHELL_UIA_PROP_CONTROL_TYPE:
            l_out->vt = VT_I4; l_out->lVal = l_n->l_role;
            break;
        case SHELL_UIA_PROP_FOCUSABLE:
            l_out->vt = VT_BOOL; l_out->boolVal = l_n->l_focusable ? VARIANT_TRUE : VARIANT_FALSE;
            break;
        case SHELL_UIA_PROP_HAS_FOCUS:
            l_out->vt = VT_BOOL; l_out->boolVal = (s_uia_focus == l_n->l_id && l_n->l_id != 0) ? VARIANT_TRUE : VARIANT_FALSE;
            break;
        case SHELL_UIA_PROP_ENABLED:
            l_out->vt = VT_BOOL; l_out->boolVal = l_n->l_enabled ? VARIANT_TRUE : VARIANT_FALSE;
            break;
        case SHELL_UIA_PROP_AUTOMATION_ID:
            wsprintfW(l_aid, L"sw%d", l_n->l_id);
            l_out->vt = VT_BSTR; l_out->bstrVal = SysAllocString(l_aid);
            break;
        case SHELL_UIA_PROP_CLASS_NAME:
            l_out->vt = VT_BSTR; l_out->bstrVal = SysAllocString(L"SimpleWidget");
            break;
        case SHELL_UIA_PROP_FRAMEWORK_ID:
            l_out->vt = VT_BSTR; l_out->bstrVal = SysAllocString(L"simple_widgets");
            break;
        case SHELL_UIA_PROP_CONTROL_ELEMENT:
        case SHELL_UIA_PROP_CONTENT_ELEMENT:
            l_out->vt = VT_BOOL; l_out->boolVal = VARIANT_TRUE;
            break;
    }
    shell_uia_lock_leave();
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE shell_uia_s_host(IRawElementProviderSimple* l_p, IRawElementProviderSimple** l_out) {
    shell_uia_el* l_el = SHELL_UIA_FROM(l_p, l_simple);
    if (!l_out) return E_POINTER;
    *l_out = 0;
    if (l_el->l_id == 0 && s_uia_hwnd)
        return UiaHostProviderFromHwnd(s_uia_hwnd, l_out);
    return S_OK;
}

/* --- IRawElementProviderFragment */

static HRESULT STDMETHODCALLTYPE shell_uia_f_qi(IRawElementProviderFragment* l_p, REFIID l_riid, void** l_out) {
    return shell_uia_qi_el(SHELL_UIA_FROM(l_p, l_fragment), l_riid, l_out);
}
static ULONG STDMETHODCALLTYPE shell_uia_f_addref(IRawElementProviderFragment* l_p) {
    return shell_uia_addref_el(SHELL_UIA_FROM(l_p, l_fragment));
}
static ULONG STDMETHODCALLTYPE shell_uia_f_release(IRawElementProviderFragment* l_p) {
    return shell_uia_release_el(SHELL_UIA_FROM(l_p, l_fragment));
}
static HRESULT STDMETHODCALLTYPE shell_uia_f_navigate(IRawElementProviderFragment* l_p, enum NavigateDirection l_dir, IRawElementProviderFragment** l_out) {
    shell_uia_el* l_el = SHELL_UIA_FROM(l_p, l_fragment);
    int l_k, l_i, l_target = -1, l_parent;
    shell_uia_el* l_found;
    if (!l_out) return E_POINTER;
    *l_out = 0;
    shell_uia_lock_enter();
    l_k = shell_uia_index(l_el->l_id);
    if (l_k < 0) {
        shell_uia_lock_leave();
        return SHELL_UIA_E_NOT_AVAILABLE;
    }
    l_parent = s_uia_nodes[l_k].l_parent;
    switch (l_dir) {
        case NavigateDirection_Parent:
            if (l_el->l_id != 0) l_target = l_parent;
            break;
        case NavigateDirection_NextSibling:
            if (l_el->l_id != 0)
                for (l_i = l_k + 1; l_i < s_uia_count && l_target < 0; l_i++)
                    if (s_uia_nodes[l_i].l_parent == l_parent && s_uia_nodes[l_i].l_id != 0) l_target = s_uia_nodes[l_i].l_id;
            break;
        case NavigateDirection_PreviousSibling:
            if (l_el->l_id != 0)
                for (l_i = l_k - 1; l_i >= 0 && l_target < 0; l_i--)
                    if (s_uia_nodes[l_i].l_parent == l_parent && s_uia_nodes[l_i].l_id != 0) l_target = s_uia_nodes[l_i].l_id;
            break;
        case NavigateDirection_FirstChild:
            for (l_i = 0; l_i < s_uia_count && l_target < 0; l_i++)
                if (s_uia_nodes[l_i].l_parent == l_el->l_id && s_uia_nodes[l_i].l_id != l_el->l_id) l_target = s_uia_nodes[l_i].l_id;
            break;
        case NavigateDirection_LastChild:
            for (l_i = s_uia_count - 1; l_i >= 0 && l_target < 0; l_i--)
                if (s_uia_nodes[l_i].l_parent == l_el->l_id && s_uia_nodes[l_i].l_id != l_el->l_id) l_target = s_uia_nodes[l_i].l_id;
            break;
    }
    shell_uia_lock_leave();
    if (l_target >= 0) {
        l_found = shell_uia_new(l_target);
        if (!l_found) return E_OUTOFMEMORY;
        *l_out = (IRawElementProviderFragment*)&l_found->l_fragment;
    }
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE shell_uia_f_runtime_id(IRawElementProviderFragment* l_p, SAFEARRAY** l_out) {
    shell_uia_el* l_el = SHELL_UIA_FROM(l_p, l_fragment);
    LONG l_at;
    int l_part;
    if (!l_out) return E_POINTER;
    *l_out = 0;
    if (l_el->l_id == 0) return S_OK;   /* the host window supplies the root's */
    *l_out = SafeArrayCreateVector(VT_I4, 0, 2);
    if (!*l_out) return E_OUTOFMEMORY;
    l_at = 0; l_part = UiaAppendRuntimeId;
    SafeArrayPutElement(*l_out, &l_at, &l_part);
    l_at = 1; l_part = l_el->l_id;
    SafeArrayPutElement(*l_out, &l_at, &l_part);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE shell_uia_f_bounds(IRawElementProviderFragment* l_p, struct UiaRect* l_out) {
    shell_uia_el* l_el = SHELL_UIA_FROM(l_p, l_fragment);
    int l_k;
    POINT l_origin;
    if (!l_out) return E_POINTER;
    l_out->left = 0; l_out->top = 0; l_out->width = 0; l_out->height = 0;
    shell_uia_lock_enter();
    l_k = shell_uia_index(l_el->l_id);
    if (l_k < 0) {
        shell_uia_lock_leave();
        return SHELL_UIA_E_NOT_AVAILABLE;
    }
    l_origin.x = 0; l_origin.y = 0;
    if (s_uia_hwnd) ClientToScreen(s_uia_hwnd, &l_origin);
    l_out->left = l_origin.x + s_uia_nodes[l_k].l_x;
    l_out->top = l_origin.y + s_uia_nodes[l_k].l_y;
    l_out->width = s_uia_nodes[l_k].l_w;
    l_out->height = s_uia_nodes[l_k].l_h;
    shell_uia_lock_leave();
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE shell_uia_f_embedded(IRawElementProviderFragment* l_p, SAFEARRAY** l_out) {
    (void)l_p;
    if (!l_out) return E_POINTER;
    *l_out = 0;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE shell_uia_f_set_focus(IRawElementProviderFragment* l_p) {
    shell_uia_el* l_el = SHELL_UIA_FROM(l_p, l_fragment);
        /* the application moves its own focus: event 58, first field the id */
    shell_push(58, l_el->l_id, 0, 0);
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE shell_uia_f_root(IRawElementProviderFragment* l_p, IRawElementProviderFragmentRoot** l_out) {
    shell_uia_el* l_root;
    (void)l_p;
    if (!l_out) return E_POINTER;
    l_root = shell_uia_new(0);
    if (!l_root) return E_OUTOFMEMORY;
    *l_out = (IRawElementProviderFragmentRoot*)&l_root->l_root;
    return S_OK;
}

/* --- IRawElementProviderFragmentRoot (node 0 only) */

static HRESULT STDMETHODCALLTYPE shell_uia_r_qi(IRawElementProviderFragmentRoot* l_p, REFIID l_riid, void** l_out) {
    return shell_uia_qi_el(SHELL_UIA_FROM(l_p, l_root), l_riid, l_out);
}
static ULONG STDMETHODCALLTYPE shell_uia_r_addref(IRawElementProviderFragmentRoot* l_p) {
    return shell_uia_addref_el(SHELL_UIA_FROM(l_p, l_root));
}
static ULONG STDMETHODCALLTYPE shell_uia_r_release(IRawElementProviderFragmentRoot* l_p) {
    return shell_uia_release_el(SHELL_UIA_FROM(l_p, l_root));
}
static HRESULT STDMETHODCALLTYPE shell_uia_r_from_point(IRawElementProviderFragmentRoot* l_p, double l_sx, double l_sy, IRawElementProviderFragment** l_out) {
    int l_i, l_hit = 0;
    POINT l_origin;
    double l_cx, l_cy;
    shell_uia_el* l_found;
    (void)l_p;
    if (!l_out) return E_POINTER;
    *l_out = 0;
    l_origin.x = 0; l_origin.y = 0;
    if (s_uia_hwnd) ClientToScreen(s_uia_hwnd, &l_origin);
    l_cx = l_sx - l_origin.x;
    l_cy = l_sy - l_origin.y;
    shell_uia_lock_enter();
        /* tree order: the LAST box holding the point is the deepest */
    for (l_i = 0; l_i < s_uia_count; l_i++) {
        shell_uia_node* l_n = &s_uia_nodes[l_i];
        if (l_cx >= l_n->l_x && l_cx < l_n->l_x + l_n->l_w && l_cy >= l_n->l_y && l_cy < l_n->l_y + l_n->l_h)
            l_hit = l_n->l_id;
    }
    shell_uia_lock_leave();
    l_found = shell_uia_new(l_hit);
    if (!l_found) return E_OUTOFMEMORY;
    *l_out = (IRawElementProviderFragment*)&l_found->l_fragment;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE shell_uia_r_get_focus(IRawElementProviderFragmentRoot* l_p, IRawElementProviderFragment** l_out) {
    int l_focus, l_known;
    shell_uia_el* l_found;
    (void)l_p;
    if (!l_out) return E_POINTER;
    *l_out = 0;
    shell_uia_lock_enter();
    l_focus = s_uia_focus;
    l_known = l_focus > 0 && shell_uia_index(l_focus) >= 0;
    shell_uia_lock_leave();
    if (l_known) {
        l_found = shell_uia_new(l_focus);
        if (!l_found) return E_OUTOFMEMORY;
        *l_out = (IRawElementProviderFragment*)&l_found->l_fragment;
    }
    return S_OK;
}

/* --- IValueProvider (read-only) */

static HRESULT STDMETHODCALLTYPE shell_uia_v_qi(IValueProvider* l_p, REFIID l_riid, void** l_out) {
    return shell_uia_qi_el(SHELL_UIA_FROM(l_p, l_valuep), l_riid, l_out);
}
static ULONG STDMETHODCALLTYPE shell_uia_v_addref(IValueProvider* l_p) {
    return shell_uia_addref_el(SHELL_UIA_FROM(l_p, l_valuep));
}
static ULONG STDMETHODCALLTYPE shell_uia_v_release(IValueProvider* l_p) {
    return shell_uia_release_el(SHELL_UIA_FROM(l_p, l_valuep));
}
static HRESULT STDMETHODCALLTYPE shell_uia_v_set(IValueProvider* l_p, LPCWSTR l_text) {
    (void)l_p; (void)l_text;
    return SHELL_UIA_E_NOT_SUPPORTED;
}
static HRESULT STDMETHODCALLTYPE shell_uia_v_get(IValueProvider* l_p, BSTR* l_out) {
    shell_uia_el* l_el = SHELL_UIA_FROM(l_p, l_valuep);
    int l_k;
    if (!l_out) return E_POINTER;
    *l_out = 0;
    shell_uia_lock_enter();
    l_k = shell_uia_index(l_el->l_id);
    if (l_k < 0) {
        shell_uia_lock_leave();
        return SHELL_UIA_E_NOT_AVAILABLE;
    }
    *l_out = SysAllocString(s_uia_nodes[l_k].l_value ? s_uia_nodes[l_k].l_value : L"");
    shell_uia_lock_leave();
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE shell_uia_v_read_only(IValueProvider* l_p, BOOL* l_out) {
    (void)l_p;
    if (!l_out) return E_POINTER;
    *l_out = TRUE;
    return S_OK;
}

static IRawElementProviderSimpleVtbl shell_uia_simple_vtbl = {
    shell_uia_s_qi, shell_uia_s_addref, shell_uia_s_release,
    shell_uia_s_options, shell_uia_s_pattern, shell_uia_s_property, shell_uia_s_host
};
static IRawElementProviderFragmentVtbl shell_uia_fragment_vtbl = {
    shell_uia_f_qi, shell_uia_f_addref, shell_uia_f_release,
    shell_uia_f_navigate, shell_uia_f_runtime_id, shell_uia_f_bounds,
    shell_uia_f_embedded, shell_uia_f_set_focus, shell_uia_f_root
};
static IRawElementProviderFragmentRootVtbl shell_uia_root_vtbl = {
    shell_uia_r_qi, shell_uia_r_addref, shell_uia_r_release,
    shell_uia_r_from_point, shell_uia_r_get_focus
};
static IValueProviderVtbl shell_uia_value_vtbl = {
    shell_uia_v_qi, shell_uia_v_addref, shell_uia_v_release,
    shell_uia_v_set, shell_uia_v_get, shell_uia_v_read_only
};

static shell_uia_el* shell_uia_new(int l_id) {
    shell_uia_el* l_el = (shell_uia_el*)malloc(sizeof(shell_uia_el));
    if (!l_el) return 0;
    l_el->l_simple = &shell_uia_simple_vtbl;
    l_el->l_fragment = &shell_uia_fragment_vtbl;
    l_el->l_root = &shell_uia_root_vtbl;
    l_el->l_valuep = &shell_uia_value_vtbl;
    l_el->l_refs = 1;
    l_el->l_id = l_id;
    return l_el;
}

/* ------------------------------------------------------------ the hook */

static int shell_uia_getobject(HWND l_h, WPARAM l_w, LPARAM l_l, LRESULT* l_result) {
    shell_uia_el* l_root;
    int l_ready;
    if ((long)l_l != (long)UiaRootObjectId || l_h != s_uia_hwnd) return 0;
    shell_uia_lock_enter();
    l_ready = s_uia_count > 0;
    shell_uia_lock_leave();
    if (!l_ready) return 0;
    l_root = shell_uia_new(0);
    if (!l_root) return 0;
    *l_result = UiaReturnRawElementProvider(l_h, l_w, l_l, (IRawElementProviderSimple*)&l_root->l_simple);
    shell_uia_release_el(l_root);
    return 1;
}

/* ------------------------------------------------------------ publishing */

/* Start a new table of at most `l_cap' rows (the live one keeps serving). */
static int shell_uia_begin(int l_cap) {
    shell_uia_free_table(s_uia_stage, s_uia_stage_count);
    s_uia_stage_count = 0;
    s_uia_stage_cap = l_cap > 0 ? l_cap : 1;
    s_uia_stage = (shell_uia_node*)calloc((size_t)s_uia_stage_cap, sizeof(shell_uia_node));
    return s_uia_stage ? 1 : 0;
}

/* Add one row; answers 0 when the table is full or not begun. */
static int shell_uia_add(int l_id, int l_parent, int l_role, int l_focusable, int l_enabled,
        double l_x, double l_y, double l_w, double l_h,
        const wchar_t* l_name, const wchar_t* l_value) {
    shell_uia_node* l_n;
    if (!s_uia_stage || s_uia_stage_count >= s_uia_stage_cap) return 0;
    l_n = &s_uia_stage[s_uia_stage_count++];
    l_n->l_id = l_id;
    l_n->l_parent = l_parent;
    l_n->l_role = l_role;
    l_n->l_focusable = l_focusable;
    l_n->l_enabled = l_enabled;
    l_n->l_has_value = l_value ? 1 : 0;
    l_n->l_x = l_x; l_n->l_y = l_y; l_n->l_w = l_w; l_n->l_h = l_h;
    l_n->l_name = shell_uia_copy(l_name);
    l_n->l_value = shell_uia_copy(l_value);
    return 1;
}

/* Swap the new table in for window `l_hwnd' and answer WM_GETOBJECT for it. */
static void shell_uia_commit(void* l_hwnd) {
    shell_uia_node* l_old;
    int l_old_count;
    shell_uia_lock_enter();
    l_old = s_uia_nodes;
    l_old_count = s_uia_count;
    s_uia_nodes = s_uia_stage;
    s_uia_count = s_uia_stage_count;
    s_uia_hwnd = (HWND)l_hwnd;
    shell_uia_lock_leave();
    s_uia_stage = 0;
    s_uia_stage_count = 0;
    s_uia_stage_cap = 0;
    shell_uia_free_table(l_old, l_old_count);
    s_shell_getobject_hook = shell_uia_getobject;
}

/* Node `l_id' took the keyboard focus: tell any listening client. */
static void shell_uia_focus_changed(int l_id) {
    shell_uia_el* l_el;
    int l_known;
    shell_uia_lock_enter();
    s_uia_focus = l_id;
    l_known = shell_uia_index(l_id) >= 0;
    shell_uia_lock_leave();
    if (l_known && UiaClientsAreListening()) {
        l_el = shell_uia_new(l_id);
        if (l_el) {
            UiaRaiseAutomationEvent((IRawElementProviderSimple*)&l_el->l_simple, SHELL_UIA_EVENT_FOCUS_CHANGED);
            shell_uia_release_el(l_el);
        }
    }
}

/* Stop answering: clients see the window alone again. */
static void shell_uia_disable(void) {
    HWND l_was;
    s_shell_getobject_hook = 0;
    shell_uia_lock_enter();
    l_was = s_uia_hwnd;
    shell_uia_free_table(s_uia_nodes, s_uia_count);
    s_uia_nodes = 0;
    s_uia_count = 0;
    s_uia_hwnd = 0;
    s_uia_focus = 0;
    shell_uia_lock_leave();
    if (l_was) UiaReturnRawElementProvider(l_was, 0, 0, 0);
}

/* Readers of the served table, row `l_i' (0-based), for tests and tools. */
static int shell_uia_row_int(int l_i, int l_field) {
    int l_answer = -1;
    shell_uia_lock_enter();
    if (l_i >= 0 && l_i < s_uia_count) {
        switch (l_field) {
            case 0: l_answer = s_uia_nodes[l_i].l_id; break;
            case 1: l_answer = s_uia_nodes[l_i].l_parent; break;
            case 2: l_answer = s_uia_nodes[l_i].l_role; break;
            case 3: l_answer = s_uia_nodes[l_i].l_focusable; break;
            case 4: l_answer = s_uia_nodes[l_i].l_enabled; break;
            case 5: l_answer = s_uia_nodes[l_i].l_has_value; break;
        }
    }
    shell_uia_lock_leave();
    return l_answer;
}

/* Copy row `l_i''s name (`l_which' 0) or value (1) into `l_out'. */
static int shell_uia_row_text(int l_i, int l_which, wchar_t* l_out, int l_cap) {
    const wchar_t* l_text = 0;
    int l_n = 0;
    shell_uia_lock_enter();
    if (l_i >= 0 && l_i < s_uia_count)
        l_text = l_which == 0 ? s_uia_nodes[l_i].l_name : s_uia_nodes[l_i].l_value;
    while (l_text && l_text[l_n] && l_n < l_cap - 1) { l_out[l_n] = l_text[l_n]; l_n++; }
    l_out[l_n] = 0;
    shell_uia_lock_leave();
    return l_n;
}

static int shell_uia_served_focus(void) {
    return s_uia_focus;
}

static int shell_uia_clients_listening(void) {
    return UiaClientsAreListening() ? 1 : 0;
}

static int shell_uia_row_count(void) {
    int l_n;
    shell_uia_lock_enter();
    l_n = s_uia_count;
    shell_uia_lock_leave();
    return l_n;
}

#endif
