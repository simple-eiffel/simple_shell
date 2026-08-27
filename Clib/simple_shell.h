/* simple_shell.h - the Win32 platform shell, one header.
   Window + message pump (queue-polled: NEVER $-callbacks, they SEGV
   under EIF_THREADS), clipboard, keyboard state, drag-drop, fonts,
   spell checking (ISpellChecker COM), virtual-screen metrics, screen
   grab into a caller buffer, frozen-desktop overlay and status strip.
   Lineage: born as ocr_cairo_win.h in simple_ocr_capture, matured
   inside simple_widgets, carved out 2026-08-23. */

#ifndef SIMPLE_SHELL_H
#define SIMPLE_SHELL_H

#include <windows.h>
#include <shellapi.h>
#pragma comment(lib, "shell32.lib")

/* Shared-state law (the 1.8.0 lockup): this header is included by the
   inline externals of SEVERAL classes, and finalized C compiles each
   class into its own translation unit - a file-scope `static' here is
   one PRIVATE copy per generated file. The overlay's wndproc pushed
   events into a queue copy the pump never drained, and the fullscreen
   topmost overlay ate every input with no way out. SHELL_SHARED data
   is linker-merged (COMDAT, the INITGUID pattern) into a single
   process-wide instance however many files include this header.
   Functions stay static - duplicated code is harmless once the DATA
   is one. Every SHELL_SHARED variable needs an explicit initializer:
   selectany applies only to an actual initialization. */
#if defined(_MSC_VER)
#define SHELL_SHARED __declspec(selectany)
#else
#define SHELL_SHARED __attribute__((selectany))
#endif

/* Event queue: [type, a, b, c] per slot.
   main window:  2 lbutton(x,y) | 3 char(code) | 4 keydown(vk) | 6 expose | 7 tick
   overlay:     31 move(x,y)   | 32 down(x,y) | 33 up(x,y)    | 34 cancel | 35 expose
                36 accept (Enter) | 37 arrow(vk) - the adjust-mode keys
   (overlay renumbered 2026-08-23: 12..16 collided with the main window's
   triple/move/leave/wheel/resize types once one pump served both) */
#define SHELL_QCAP 1024
SHELL_SHARED HWND s_shell_hwnd = 0;
SHELL_SHARED LONG s_shell_dbl_time = 0;
SHELL_SHARED int  s_shell_tracking = 0;
SHELL_SHARED int  s_shell_dbl_x = 0;
SHELL_SHARED int  s_shell_dbl_y = 0;
SHELL_SHARED HWND s_shell_overlay = 0;
SHELL_SHARED int  s_shell_q[SHELL_QCAP][4] = {{0}};
SHELL_SHARED wchar_t s_shell_drops[16384] = {0};
SHELL_SHARED int  s_shell_drops_len = 0;
SHELL_SHARED int  s_shell_qhead = 0;
SHELL_SHARED int  s_shell_qtail = 0;
SHELL_SHARED int  s_shell_cursor = 0;

/* 0 arrow, 1 ibeam, 2 hand, 3 size-we, 4 size-ns, 5 cross, 6 wait */
static void shell_set_cursor_kind(int k) {
    s_shell_cursor = k;
}


static void shell_push(int t, int a, int b, int c) {
    int next = (s_shell_qtail + 1) % SHELL_QCAP;
    if (next == s_shell_qhead) return;
    s_shell_q[s_shell_qtail][0] = t;
    s_shell_q[s_shell_qtail][1] = a;
    s_shell_q[s_shell_qtail][2] = b;
    s_shell_q[s_shell_qtail][3] = c;
    s_shell_qtail = next;
}

static LRESULT CALLBACK shell_wndproc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
        case WM_LBUTTONDOWN: {
            int cx = (int)(short)LOWORD(l), cy = (int)(short)HIWORD(l);
            SetFocus(h);
            SetCapture(h);
            if (s_shell_dbl_time != 0
                && GetMessageTime() - s_shell_dbl_time <= (LONG)GetDoubleClickTime()
                && abs(cx - s_shell_dbl_x) <= GetSystemMetrics(SM_CXDOUBLECLK)
                && abs(cy - s_shell_dbl_y) <= GetSystemMetrics(SM_CYDOUBLECLK)) {
                s_shell_dbl_time = 0;
                shell_push(12, cx, cy, 0);
            } else {
                shell_push(2, cx, cy, 0);
            }
            return 0;
        }
        case WM_LBUTTONUP:
            ReleaseCapture();
            shell_push(10, (int)(short)LOWORD(l), (int)(short)HIWORD(l), 0);
            return 0;
        case WM_LBUTTONDBLCLK:
            s_shell_dbl_time = GetMessageTime();
            s_shell_dbl_x = (int)(short)LOWORD(l);
            s_shell_dbl_y = (int)(short)HIWORD(l);
            shell_push(8, s_shell_dbl_x, s_shell_dbl_y, 0);
            return 0;
        case WM_RBUTTONDOWN:
            /* eat: the menu opens on BUTTON-UP, or the release event
               dismisses the popup the instant it appears */
            SetFocus(h);
            return 0;
        case WM_RBUTTONUP:
            shell_push(11, (int)(short)LOWORD(l), (int)(short)HIWORD(l), 0);
            return 0;
        case WM_MOUSEMOVE:
            if (!s_shell_tracking) {
                TRACKMOUSEEVENT tme;
                tme.cbSize = sizeof(tme);
                tme.dwFlags = TME_LEAVE;
                tme.hwndTrack = h;
                tme.dwHoverTime = 0;
                TrackMouseEvent(&tme);
                s_shell_tracking = 1;
            }
            if (w & MK_LBUTTON)
                shell_push(9, (int)(short)LOWORD(l), (int)(short)HIWORD(l), 0);
            else {
                /* coalesce plain moves: replace a queued move instead of flooding */
                int last = (s_shell_qtail + SHELL_QCAP - 1) % SHELL_QCAP;
                if (s_shell_qtail != s_shell_qhead && s_shell_q[last][0] == 13) {
                    s_shell_q[last][1] = (int)(short)LOWORD(l);
                    s_shell_q[last][2] = (int)(short)HIWORD(l);
                } else
                    shell_push(13, (int)(short)LOWORD(l), (int)(short)HIWORD(l), 0);
            }
            return 0;
        case WM_SIZE:
            if (w != SIZE_MINIMIZED) {
                /* coalesce like moves: replace a queued resize */
                int last = (s_shell_qtail + SHELL_QCAP - 1) % SHELL_QCAP;
                if (s_shell_qtail != s_shell_qhead && s_shell_q[last][0] == 16) {
                    s_shell_q[last][1] = (int)LOWORD(l);
                    s_shell_q[last][2] = (int)HIWORD(l);
                } else
                    shell_push(16, (int)LOWORD(l), (int)HIWORD(l), 0);
            }
            return 0;
        case WM_DROPFILES: {
            /* join every dropped path with newline into the static
               buffer; Eiffel pulls it on event 18 (the clipboard
               pull pattern - the queue carries only ints) */
            HDROP hd = (HDROP)w;
            POINT dp;
            UINT n, i, len;
            s_shell_drops_len = 0;
            DragQueryPoint(hd, &dp);
            n = DragQueryFileW(hd, 0xFFFFFFFF, NULL, 0);
            for (i = 0; i < n; i++) {
                len = DragQueryFileW(hd, i, NULL, 0);
                if (s_shell_drops_len + (int)len + 2 >= 16384) break;
                if (s_shell_drops_len > 0)
                    s_shell_drops[s_shell_drops_len++] = L'\n';
                DragQueryFileW(hd, i, s_shell_drops + s_shell_drops_len, 16384 - s_shell_drops_len);
                s_shell_drops_len += (int)len;
            }
            s_shell_drops[s_shell_drops_len] = 0;
            DragFinish(hd);
            shell_push(18, (int)dp.x, (int)dp.y, (int)n);
            return 0;
        }
        case WM_MOUSEWHEEL: {
            POINT wp;
            int last;
            wp.x = (int)(short)LOWORD(l);
            wp.y = (int)(short)HIWORD(l);
            ScreenToClient(h, &wp);
            /* coalesce spins like moves: SUM deltas into a queued
               wheel event so a fast spin is one scroll + one render,
               not a render per notch */
            last = (s_shell_qtail + SHELL_QCAP - 1) % SHELL_QCAP;
            if (s_shell_qtail != s_shell_qhead && s_shell_q[last][0] == 15) {
                s_shell_q[last][1] = (int)wp.x;
                s_shell_q[last][2] = (int)wp.y;
                s_shell_q[last][3] += (int)(short)HIWORD(w);
            } else
                shell_push(15, (int)wp.x, (int)wp.y, (int)(short)HIWORD(w));
            return 0;
        }
        case WM_MBUTTONDOWN:
            SetFocus(h);
            shell_push(17, (int)(short)LOWORD(l), (int)(short)HIWORD(l), 0);
            return 0;
        case WM_MOUSELEAVE:
            s_shell_tracking = 0;
            shell_push(14, 0, 0, 0);
            return 0;
        case WM_CHAR:
            shell_push(3, (int)w, 0, 0);
            return 0;
        case WM_KEYDOWN:
            if (w == VK_LEFT || w == VK_RIGHT || w == VK_HOME || w == VK_END ||
                w == VK_DELETE || w == VK_UP || w == VK_DOWN ||
                w == VK_PRIOR || w == VK_NEXT ||
                w == VK_OEM_PLUS || w == VK_OEM_MINUS ||
                w == VK_ADD || w == VK_SUBTRACT)
                shell_push(4, (int)w, 0, 0);
            return 0;
        case WM_SYSKEYDOWN:
            /* Alt-modified stepping keys (apps read Alt via shell_alt_down):
               forward them and keep the menu loop out of it. Every other
               syskey (Alt+F4, Alt+Space) keeps its system meaning. */
            if (w == VK_OEM_PLUS || w == VK_OEM_MINUS ||
                w == VK_ADD || w == VK_SUBTRACT) {
                shell_push(4, (int)w, 0, 0);
                return 0;
            }
            break;
        case WM_SYSCHAR:
            /* the beep for the swallowed Alt steps above */
            if (w == '+' || w == '-' || w == '=') return 0;
            break;
        case WM_TIMER:
            /* timer 1: the 250ms heartbeat; timer 2: the app-settable
               fast tick (event 25) - polling loops that outpace the
               heartbeat (the OCR capture cycle runs at 50ms) */
            if (w == 2) shell_push(25, 0, 0, 0);
            else        shell_push(7, 0, 0, 0);
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            BeginPaint(h, &ps);
            EndPaint(h, &ps);
            shell_push(6, 0, 0, 0);
            return 0;
        }
        case WM_SETCURSOR:
            if (LOWORD(l) == HTCLIENT) {
                LPCWSTR c = (LPCWSTR)IDC_ARROW;
                switch (s_shell_cursor) {
                    case 1: c = (LPCWSTR)IDC_IBEAM; break;
                    case 2: c = (LPCWSTR)IDC_HAND; break;
                    case 3: c = (LPCWSTR)IDC_SIZEWE; break;
                    case 4: c = (LPCWSTR)IDC_SIZENS; break;
                    case 5: c = (LPCWSTR)IDC_CROSS; break;
                    case 6: c = (LPCWSTR)IDC_WAIT; break;
                }
                SetCursor(LoadCursorW(0, c));
                return 1;
            }
            break;
        case WM_DESTROY:
            KillTimer(h, 1);
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(h, m, w, l);
}

static LRESULT CALLBACK shell_overlay_proc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
        case WM_MOUSEMOVE:
            shell_push(31, (int)(short)LOWORD(l), (int)(short)HIWORD(l), 0);
            return 0;
        case WM_LBUTTONDOWN:
            SetCapture(h);
            shell_push(32, (int)(short)LOWORD(l), (int)(short)HIWORD(l), 0);
            return 0;
        case WM_LBUTTONUP:
            ReleaseCapture();
            shell_push(33, (int)(short)LOWORD(l), (int)(short)HIWORD(l), 0);
            return 0;
        case WM_KEYDOWN:
            if (w == VK_ESCAPE) {
                /* dismiss in C FIRST: freeing the screen must never
                   depend on the Eiffel loop hearing event 34 */
                ReleaseCapture();
                ShowWindow(h, SW_HIDE);
                shell_push(34, 0, 0, 0);
            }
            else if (w == VK_RETURN)
                shell_push(36, 0, 0, 0);
            else if (w == VK_LEFT || w == VK_UP || w == VK_RIGHT || w == VK_DOWN)
                shell_push(37, (int)w, 0, 0);
            return 0;
        case WM_RBUTTONDOWN:
            ReleaseCapture();
            ShowWindow(h, SW_HIDE);
            shell_push(34, 0, 0, 0);
            return 0;
        case WM_CLOSE:
            /* Alt+F4 cancels the pick; the default DestroyWindow
               would leave s_shell_overlay dangling for the next show */
            ReleaseCapture();
            ShowWindow(h, SW_HIDE);
            shell_push(34, 0, 0, 0);
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            BeginPaint(h, &ps);
            EndPaint(h, &ps);
            shell_push(35, 0, 0, 0);
            return 0;
        }
        case WM_ERASEBKGND:
            return 1;
    }
    return DefWindowProcW(h, m, w, l);
}

/* ---- outline frames: up to four click-through coloured rectangle
   FRAMES on the desktop (topmost, no taskbar, no activation, no input -
   WS_EX_TRANSPARENT). One window per slot; the visible shape is a frame
   region (outer rect minus inner rect) so the middle is not even part
   of the window. The pure-route replacement for four-popup-edges. ---- */
SHELL_SHARED HWND   s_shell_outline[4]       = {0, 0, 0, 0};
SHELL_SHARED HBRUSH s_shell_outline_brush[4] = {0, 0, 0, 0};

static LRESULT CALLBACK shell_outline_proc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_PAINT) {
        PAINTSTRUCT ps;
        RECT r;
        int slot = (int)GetWindowLongPtrW(h, GWLP_USERDATA);
        HDC dc = BeginPaint(h, &ps);
        GetClientRect(h, &r);
        if (slot >= 0 && slot < 4 && s_shell_outline_brush[slot])
            FillRect(dc, &r, s_shell_outline_brush[slot]);
        EndPaint(h, &ps);
        return 0;
    }
    if (m == WM_ERASEBKGND) return 1;
    return DefWindowProcW(h, m, w, l);
}

static void shell_outline_show(int slot, int x, int y, int w, int h, int thick, int rgb) {
    WNDCLASSW wc;
    HRGN outer, inner;
    if (slot < 0 || slot > 3 || w <= 0 || h <= 0 || thick <= 0) return;
    if (!s_shell_outline[slot]) {
        ZeroMemory(&wc, sizeof(wc));
        wc.lpfnWndProc = shell_outline_proc;
        wc.hInstance = GetModuleHandleW(0);
        wc.lpszClassName = L"SimpleShellOutline";
        RegisterClassW(&wc);
        s_shell_outline[slot] = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT,
            L"SimpleShellOutline", L"", WS_POPUP,
            x, y, w, h, 0, 0, GetModuleHandleW(0), 0);
        SetWindowLongPtrW(s_shell_outline[slot], GWLP_USERDATA, (LONG_PTR)slot);
    }
    if (s_shell_outline_brush[slot]) DeleteObject(s_shell_outline_brush[slot]);
    s_shell_outline_brush[slot] =
        CreateSolidBrush(RGB((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF));
    outer = CreateRectRgn(0, 0, w, h);
    inner = CreateRectRgn(thick, thick, w - thick, h - thick);
    CombineRgn(outer, outer, inner, RGN_DIFF);
    DeleteObject(inner);
    SetWindowRgn(s_shell_outline[slot], outer, TRUE);   /* system owns it now */
    SetWindowPos(s_shell_outline[slot], HWND_TOPMOST, x, y, w, h,
        SWP_SHOWWINDOW | SWP_NOACTIVATE);
    InvalidateRect(s_shell_outline[slot], 0, TRUE);
}

static void shell_outline_hide(int slot) {
    if (slot >= 0 && slot < 4 && s_shell_outline[slot])
        ShowWindow(s_shell_outline[slot], SW_HIDE);
}

SHELL_SHARED HBRUSH s_shell_backdrop = 0;

/* Newly exposed pixels during a live resize are erased with the class
   brush BEFORE our next full frame lands - keep it the theme's ground
   so growth never flashes black. (Steady-state repaints never erase:
   we blit whole frames without invalidating.) */
static void shell_set_backdrop(void* hwnd, int rgb) {
    HBRUSH old_brush = s_shell_backdrop;
    s_shell_backdrop = CreateSolidBrush(RGB((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF));
    if (hwnd)
        SetClassLongPtrW((HWND)hwnd, GCLP_HBRBACKGROUND, (LONG_PTR)s_shell_backdrop);
    if (old_brush) DeleteObject(old_brush);
}

static void* shell_create_window(const wchar_t* title, int px, int py, int cw, int ch) {
    WNDCLASSW wc;
    RECT r;
    HWND h;
    SetProcessDPIAware();
    ZeroMemory(&wc, sizeof(wc));
    wc.style = CS_DBLCLKS;
    wc.lpfnWndProc = shell_wndproc;
    wc.hInstance = GetModuleHandleW(0);
    wc.hCursor = LoadCursorW(0, (LPCWSTR)IDC_ARROW);
    if (!s_shell_backdrop) s_shell_backdrop = CreateSolidBrush(RGB(18, 20, 27));
    wc.hbrBackground = s_shell_backdrop;
    wc.lpszClassName = L"SimpleShellWindow";
    RegisterClassW(&wc);
    r.left = 0; r.top = 0; r.right = cw; r.bottom = ch;
    AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, FALSE);
    h = CreateWindowExW(0, L"SimpleShellWindow", title,
        WS_OVERLAPPEDWINDOW,
        px, py,
        r.right - r.left, r.bottom - r.top, 0, 0, GetModuleHandleW(0), 0);
    s_shell_hwnd = h;
    if (h) {
        ShowWindow(h, SW_SHOW);
        UpdateWindow(h);
        SetTimer(h, 1, 250, 0);
        DragAcceptFiles(h, TRUE);
    }
    return (void*)h;
}

static void shell_set_fast_timer(int ms) {
    if (s_shell_hwnd && ms > 0) SetTimer(s_shell_hwnd, 2, ms, 0);
}

static void shell_set_window_icon(const wchar_t* path) {
    /* Title-bar and taskbar icon from a .ico FILE beside the exe -
       the resource-free route (finalized Eiffel binaries carry no
       custom resources). Multi-size .ico: Windows picks per use. */
    HICON big, small;
    if (!s_shell_hwnd || !path) return;
    big = (HICON)LoadImageW(NULL, path, IMAGE_ICON, 0, 0,
        LR_LOADFROMFILE | LR_DEFAULTSIZE);
    small = (HICON)LoadImageW(NULL, path, IMAGE_ICON, 16, 16, LR_LOADFROMFILE);
    if (big)   SendMessageW(s_shell_hwnd, WM_SETICON, ICON_BIG,   (LPARAM)big);
    if (small) SendMessageW(s_shell_hwnd, WM_SETICON, ICON_SMALL, (LPARAM)small);
}

static void shell_kill_fast_timer(void) {
    if (s_shell_hwnd) KillTimer(s_shell_hwnd, 2);
}

static void shell_close_window(void) {
    if (s_shell_hwnd) DestroyWindow(s_shell_hwnd);
}

/* Pump this thread's queue for ms milliseconds WITHOUT a main window:
   paints windowless-facility windows (outlines, strip) in short CLI
   diagnostics. PeekMessage so an empty queue cannot block past the
   deadline. */
static void shell_pump_for(int ms) {
    DWORD deadline = GetTickCount() + (DWORD)ms;
    MSG m;
    while (GetTickCount() < deadline) {
        while (PeekMessageW(&m, 0, 0, 0, PM_REMOVE)) {
            TranslateMessage(&m);
            DispatchMessageW(&m);
        }
        Sleep(5);
    }
}

static int shell_pump(void) {
    MSG m;
    BOOL r = GetMessageW(&m, 0, 0, 0);
    if (r <= 0) return 0;
    TranslateMessage(&m);
    DispatchMessageW(&m);
    return 1;
}

static int shell_next_event(int* out4) {
    if (s_shell_qhead == s_shell_qtail) return 0;
    out4[0] = s_shell_q[s_shell_qhead][0];
    out4[1] = s_shell_q[s_shell_qhead][1];
    out4[2] = s_shell_q[s_shell_qhead][2];
    out4[3] = s_shell_q[s_shell_qhead][3];
    s_shell_qhead = (s_shell_qhead + 1) % SHELL_QCAP;
    return out4[0];
}

static void* shell_get_dc(void)         { return s_shell_hwnd ? (void*)GetDC(s_shell_hwnd) : 0; }
static void  shell_release_dc(void* dc) { if (s_shell_hwnd && dc) ReleaseDC(s_shell_hwnd, (HDC)dc); }

static double shell_now_ms(void) {
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
}

static int shell_shell_open(const wchar_t* path) {
    return (int)(INT_PTR)ShellExecuteW(0, L"open", path, 0, 0, SW_SHOWNORMAL) > 32 ? 1 : 0;
}

/* ---- screen metrics (virtual desktop) ---- */
static int shell_screen_x(void) { return GetSystemMetrics(SM_XVIRTUALSCREEN); }
static int shell_screen_y(void) { return GetSystemMetrics(SM_YVIRTUALSCREEN); }
static int shell_screen_w(void) { return GetSystemMetrics(SM_CXVIRTUALSCREEN); }
static int shell_screen_h(void) { return GetSystemMetrics(SM_CYVIRTUALSCREEN); }

/* ---- pure screen grab: BitBlt the desktop region into a caller-supplied
   cairo ARGB32 buffer (bits/stride), alpha forced opaque. Replaces
   EV_SCREEN.sub_pixmap on the pure route. Returns 1 on success. ---- */
static int shell_grab_screen(int x, int y, int w, int h, void* bits, int stride) {
    HDC screen, mem;
    HBITMAP dib, old;
    BITMAPINFO bi;
    void* dib_bits = 0;
    int row, col, ok = 0;
    if (!bits || w <= 0 || h <= 0) return 0;
    screen = GetDC(0);
    if (!screen) return 0;
    mem = CreateCompatibleDC(screen);
    ZeroMemory(&bi, sizeof(bi));
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = w;
    bi.bmiHeader.biHeight = -h;               /* top-down */
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    dib = CreateDIBSection(mem, &bi, DIB_RGB_COLORS, &dib_bits, 0, 0);
    if (dib && dib_bits) {
        old = (HBITMAP)SelectObject(mem, dib);
        if (BitBlt(mem, 0, 0, w, h, screen, x, y, SRCCOPY | CAPTUREBLT)) {
            for (row = 0; row < h; row++) {
                unsigned int* src = (unsigned int*)((char*)dib_bits + (size_t)row * w * 4);
                unsigned int* dst = (unsigned int*)((char*)bits + (size_t)row * stride);
                for (col = 0; col < w; col++)
                    dst[col] = src[col] | 0xFF000000u;   /* opaque alpha */
            }
            ok = 1;
        }
        SelectObject(mem, old);
        DeleteObject(dib);
    }
    DeleteDC(mem);
    ReleaseDC(0, screen);
    return ok;
}

/* ---- frozen-desktop drag overlay ---- */

/* Dead-man watchdog: a desktop-covering overlay must never depend on
   a live Eiffel loop for its own dismissal. A plain OS thread (never
   touches the Eiffel runtime) polls the PHYSICAL Escape key -
   GetAsyncKeyState needs no focus and no message queue. Held ~2s with
   the overlay up: post the normal cancel through the GUI thread.
   Still up at ~5s: the loop is gone, and only process death is
   guaranteed to free the screen - losing the application beats
   losing the session. */
SHELL_SHARED HANDLE s_shell_watchdog = 0;

static DWORD WINAPI shell_watchdog_main(LPVOID unused) {
    int held = 0;
    (void)unused;
    for (;;) {
        Sleep(100);
        if (s_shell_overlay && IsWindowVisible(s_shell_overlay)
            && (GetAsyncKeyState(VK_ESCAPE) & 0x8000)) {
            held++;
            if (held == 20)
                PostMessageW(s_shell_overlay, WM_KEYDOWN, VK_ESCAPE, 0);
            if (held >= 50)
                ExitProcess(1);
        } else
            held = 0;
    }
}

static void* shell_show_overlay(void) {
    WNDCLASSW wc;
    int vx = shell_screen_x(), vy = shell_screen_y();
    int vw = shell_screen_w(), vh = shell_screen_h();
    if (!s_shell_watchdog)
        s_shell_watchdog = CreateThread(0, 0, shell_watchdog_main, 0, 0, 0);
    if (!s_shell_overlay) {
        ZeroMemory(&wc, sizeof(wc));
        wc.lpfnWndProc = shell_overlay_proc;
        wc.hInstance = GetModuleHandleW(0);
        wc.hCursor = LoadCursorW(0, (LPCWSTR)IDC_CROSS);
        wc.lpszClassName = L"SimpleShellOverlay";
        RegisterClassW(&wc);
        s_shell_overlay = CreateWindowExW(WS_EX_TOPMOST, L"SimpleShellOverlay", L"",
            WS_POPUP, vx, vy, vw, vh, 0, 0, GetModuleHandleW(0), 0);
    }
    if (s_shell_overlay) {
        SetWindowPos(s_shell_overlay, HWND_TOPMOST, vx, vy, vw, vh, SWP_SHOWWINDOW);
        SetForegroundWindow(s_shell_overlay);
        SetFocus(s_shell_overlay);
    }
    return (void*)s_shell_overlay;
}

static void shell_hide_overlay(void) {
    if (s_shell_overlay) ShowWindow(s_shell_overlay, SW_HIDE);
}

static void* shell_overlay_dc(void)         { return s_shell_overlay ? (void*)GetDC(s_shell_overlay) : 0; }
static void  shell_overlay_release(void* dc){ if (s_shell_overlay && dc) ReleaseDC(s_shell_overlay, (HDC)dc); }

/* ---- status strip: second topmost tool window ----
   events: 21 strip_lbutton(x,y) | 22 strip_moved(x,y) | 23 strip_expose */
SHELL_SHARED HWND s_shell_strip = 0;

static LRESULT CALLBACK shell_strip_proc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
        case WM_LBUTTONDOWN: {
            int x = (int)(short)LOWORD(l), y = (int)(short)HIWORD(l);
            shell_push(21, x, y, 0);
            {
                RECT cr;
                GetClientRect(h, &cr);
                /* drag anywhere except the transport corner (right 90px of
                   the top 26px), whose presses stay clicks for Eiffel */
                if (!(y < 26 && x >= cr.right - 90)) {
                    ReleaseCapture();
                    SendMessageW(h, WM_NCLBUTTONDOWN, HTCAPTION, 0);
                }
            }
            return 0;
        }
        case WM_EXITSIZEMOVE: {
            RECT r;
            GetWindowRect(h, &r);
            shell_push(22, r.left, r.top, 0);
            return 0;
        }
        case WM_PAINT: {
            PAINTSTRUCT ps;
            BeginPaint(h, &ps);
            EndPaint(h, &ps);
            shell_push(23, 0, 0, 0);
            return 0;
        }
        case WM_ERASEBKGND:
            return 1;
    }
    return DefWindowProcW(h, m, w, l);
}

static void* shell_show_strip(int x, int y, int w, int h) {
    WNDCLASSW wc;
    if (!s_shell_strip) {
        ZeroMemory(&wc, sizeof(wc));
        wc.lpfnWndProc = shell_strip_proc;
        wc.hInstance = GetModuleHandleW(0);
        wc.hCursor = LoadCursorW(0, (LPCWSTR)IDC_ARROW);
        wc.lpszClassName = L"SimpleShellAux";
        RegisterClassW(&wc);
        s_shell_strip = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
            L"SimpleShellAux", L"", WS_POPUP, x, y, w, h,
            0, 0, GetModuleHandleW(0), 0);
    }
    if (s_shell_strip)
        SetWindowPos(s_shell_strip, HWND_TOPMOST, x, y, w, h, SWP_SHOWWINDOW | SWP_NOACTIVATE);
    return (void*)s_shell_strip;
}

static void shell_hide_strip(void) {
    if (s_shell_strip) ShowWindow(s_shell_strip, SW_HIDE);
}

static void* shell_strip_dc(void)          { return s_shell_strip ? (void*)GetDC(s_shell_strip) : 0; }
static void  shell_strip_release(void* dc) { if (s_shell_strip && dc) ReleaseDC(s_shell_strip, (HDC)dc); }

/* ---- helpers for the run engine ---- */
static int shell_buffers_equal(const void* a, const void* b, int len) {
    return (a && b && len > 0 && memcmp(a, b, (size_t)len) == 0) ? 1 : 0;
}

static int shell_minutes_of_day(void) {
    SYSTEMTIME st;
    GetLocalTime(&st);
    return (int)st.wHour * 60 + (int)st.wMinute;
}


/* Private font loading: the vendored TTFs become selectable by family name
   through Cairo's Win32 font backend, process-only (FR_PRIVATE), no install. */
static int shell_add_font (const char *path) {
    return (int) AddFontResourceExA ((LPCSTR) path, FR_PRIVATE, 0);
}

static int shell_shift_down(void) {
    return (GetKeyState(VK_SHIFT) & 0x8000) ? 1 : 0;
}

static int shell_control_down(void) {
    return (GetKeyState(VK_CONTROL) & 0x8000) ? 1 : 0;
}

static int shell_alt_down(void) {
    return (GetKeyState(VK_MENU) & 0x8000) ? 1 : 0;
}

/* ---- clipboard (CF_UNICODETEXT) ---- */
static int shell_drop_paths (wchar_t *buf, int cap) {
    int n = s_shell_drops_len;
    if (n >= cap) n = cap - 1;
    memcpy(buf, s_shell_drops, n * sizeof(wchar_t));
    buf[n] = 0;
    s_shell_drops_len = 0;
    return n;
}

static int shell_clip_set (const wchar_t *s) {
    size_t n; HGLOBAL h; wchar_t *dst;
    if (!OpenClipboard(s_shell_hwnd)) return 0;
    EmptyClipboard();
    n = wcslen(s);
    h = GlobalAlloc(GMEM_MOVEABLE, (n + 1) * sizeof(wchar_t));
    if (h) {
        dst = (wchar_t*)GlobalLock(h);
        memcpy(dst, s, (n + 1) * sizeof(wchar_t));
        GlobalUnlock(h);
        SetClipboardData(CF_UNICODETEXT, h);
    }
    CloseClipboard();
    return h ? 1 : 0;
}

static int shell_clip_get (wchar_t *buf, int cap) {
    HANDLE h; wchar_t *src; int n = 0;
    if (!OpenClipboard(s_shell_hwnd)) return 0;
    h = GetClipboardData(CF_UNICODETEXT);
    if (h) {
        src = (wchar_t*)GlobalLock(h);
        if (src) {
            while (n < cap - 1 && src[n]) { buf[n] = src[n]; n++; }
            buf[n] = 0;
            GlobalUnlock(h);
        }
    }
    CloseClipboard();
    return n;
}

static int shell_clip_has_text (void) {
    return IsClipboardFormatAvailable(CF_UNICODETEXT) ? 1 : 0;
}

/* ---- native text context menu: returns 1 Cut, 2 Copy, 3 Paste, 4 Select All, 0 none ---- */
static int shell_text_menu (int can_cut, int can_copy, int can_paste, int can_select) {
    HMENU m; POINT pt; int r;
    m = CreatePopupMenu();
    AppendMenuW(m, can_cut ? MF_STRING : MF_STRING | MF_GRAYED, 1, L"Cu&t	Ctrl+X");
    AppendMenuW(m, can_copy ? MF_STRING : MF_STRING | MF_GRAYED, 2, L"&Copy	Ctrl+C");
    AppendMenuW(m, can_paste ? MF_STRING : MF_STRING | MF_GRAYED, 3, L"&Paste	Ctrl+V");
    AppendMenuW(m, MF_SEPARATOR, 0, 0);
    AppendMenuW(m, can_select ? MF_STRING : MF_STRING | MF_GRAYED, 4, L"Select &All	Ctrl+A");
    GetCursorPos(&pt);
    /* Canonical Win32 dance: without SetForegroundWindow the popup can
       open and instantly self-dismiss; the WM_NULL afterwards lets the
       menu close cleanly when the user clicks elsewhere. */
    SetForegroundWindow(s_shell_hwnd);
    r = (int)TrackPopupMenu(m, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.x, pt.y, 0, s_shell_hwnd, 0);
    PostMessageW(s_shell_hwnd, WM_NULL, 0, 0);
    DestroyMenu(m);
    return r;
}

/* ---- Windows inbox spell checking (ISpellChecker, Windows 8+) ----
   COM driven C-style; GUIDs defined locally to avoid initguid
   duplicate-symbol trouble across translation units. */
#undef NTDDI_VERSION
#define NTDDI_VERSION 0x06020000
#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0602
#include <objbase.h>
#include <spellcheck.h>

static const CLSID s_shell_clsid_scf =
    {0x7AB36653,0x1796,0x484B,{0xBD,0xFA,0xE7,0x4F,0x1D,0xB7,0xC1,0xDC}};
static const IID s_shell_iid_iscf =
    {0x8E018A9D,0x2415,0x4677,{0xBF,0x08,0x79,0x4E,0xA6,0x1F,0x94,0xBB}};

SHELL_SHARED ISpellChecker *s_shell_spell = 0;
SHELL_SHARED int s_shell_spell_tried = 0;

static int shell_spell_init(void) {
    ISpellCheckerFactory *f = 0;
    HRESULT hr;
    if (s_shell_spell) return 1;
    if (s_shell_spell_tried) return 0;
    s_shell_spell_tried = 1;
    CoInitializeEx(0, COINIT_APARTMENTTHREADED);
    hr = CoCreateInstance(&s_shell_clsid_scf, 0, CLSCTX_INPROC_SERVER,
        &s_shell_iid_iscf, (void**)&f);
    if (FAILED(hr) || !f) return 0;
    hr = f->lpVtbl->CreateSpellChecker(f, L"en-US", &s_shell_spell);
    f->lpVtbl->Release(f);
    return (SUCCEEDED(hr) && s_shell_spell) ? 1 : 0;
}

/* out receives (start,len) int pairs in UTF-16 units; returns pair count */
static int shell_spell_check(const wchar_t *text, int *out, int cap_pairs) {
    IEnumSpellingError *errs = 0;
    ISpellingError *e = 0;
    int n = 0;
    if (!shell_spell_init()) return 0;
    if (FAILED(s_shell_spell->lpVtbl->Check(s_shell_spell, text, &errs)) || !errs)
        return 0;
    while (n < cap_pairs && errs->lpVtbl->Next(errs, &e) == S_OK && e) {
        ULONG si = 0, ln = 0;
        e->lpVtbl->get_StartIndex(e, &si);
        e->lpVtbl->get_Length(e, &ln);
        out[n * 2] = (int)si;
        out[n * 2 + 1] = (int)ln;
        e->lpVtbl->Release(e);
        e = 0;
        n++;
    }
    errs->lpVtbl->Release(errs);
    return n;
}

/* teach the checker: Ignore is session-scoped, Add persists to the
   user's Windows dictionary (the same one Edge and Office honour) */
static int shell_spell_ignore(const wchar_t *word) {
    if (!shell_spell_init()) return 0;
    return SUCCEEDED(s_shell_spell->lpVtbl->Ignore(s_shell_spell, word)) ? 1 : 0;
}

static int shell_spell_add(const wchar_t *word) {
    if (!shell_spell_init()) return 0;
    return SUCCEEDED(s_shell_spell->lpVtbl->Add(s_shell_spell, word)) ? 1 : 0;
}

/* first few suggestions for word, newline-joined into buf */
static int shell_spell_suggest(const wchar_t *word, wchar_t *buf, int cap) {
    IEnumString *sugg = 0;
    LPOLESTR s = 0;
    int n = 0, pos = 0, L;
    buf[0] = 0;
    if (!shell_spell_init()) return 0;
    if (FAILED(s_shell_spell->lpVtbl->Suggest(s_shell_spell, word, &sugg)) || !sugg)
        return 0;
    while (n < 5 && sugg->lpVtbl->Next(sugg, 1, &s, 0) == S_OK && s) {
        L = (int)wcslen(s);
        if (pos + L + 2 >= cap) { CoTaskMemFree(s); break; }
        if (n) buf[pos++] = L'\n';
        memcpy(buf + pos, s, L * sizeof(wchar_t));
        pos += L;
        CoTaskMemFree(s);
        s = 0;
        n++;
    }
    buf[pos] = 0;
    sugg->lpVtbl->Release(sugg);
    return n;
}
#endif
