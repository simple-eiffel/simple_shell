/* shell_gtk.c - the Linux (GTK 4) half of simple_shell (item 2 of GUI_PLAN.md), built to
   port-coordination docs/SHELL_SEAM.md and following the macOS half section by section:
   the shared state, the Windows names the Eiffel inline C calls directly, then the queue,
   keys, the view, the window and its timers, drawing, the pump, the wake, appearance and
   the desktop. Panels and the rest come next; until then make_stubs.pl answers "not
   available" for them (see shell_gtk.h). */

#include <gtk/gtk.h>
#include <fontconfig/fontconfig.h>
#include <string.h>
#include "shell_gtk.h"

/* ------------------------------------------------------------------ shared state the inline C reads */

int s_shell_heartbeat_ms = 250;

/* ------------------------------------------------------------------ Windows names the Eiffel inline C uses */

unsigned int GetTickCount(void) { return (unsigned int)(g_get_monotonic_time() / 1000); }
int SetProcessDPIAware(void) { return 1; }   /* a GTK process is always told its scale */
HDC GetDC(HWND a_window) { (void)a_window; return (HDC)1; }
int ReleaseDC(HWND a_window, HDC a_dc) { (void)a_window; (void)a_dc; return 1; }

/* The first monitor, once GTK has a display (NULL before). */
static GdkMonitor *shell_first_monitor(void)
{
	GdkDisplay *l_display = gdk_display_get_default();
	GListModel *l_monitors;
	GdkMonitor *l_first;
	if (!l_display) return NULL;
	l_monitors = gdk_display_get_monitors(l_display);
	if (g_list_model_get_n_items(l_monitors) == 0) return NULL;
	l_first = g_list_model_get_item(l_monitors, 0);
	g_object_unref(l_first);   /* the display keeps it */
	return l_first;
}
int GetDeviceCaps(HDC a_dc, int a_index)
{
	GdkMonitor *l_monitor = shell_first_monitor();
	(void)a_dc;
	if (a_index != LOGPIXELSX) return 0;
	return l_monitor ? 96 * gdk_monitor_get_scale_factor(l_monitor) : 96;
}
unsigned int GetLogicalDrives(void) { return 0; }   /* no drive letters */
int IsWindowVisible(HWND a_window) { return a_window && gtk_widget_get_visible(GTK_WIDGET(a_window)) ? 1 : 0; }
/* Wayland gives no global pointer position, nor a window's place on the screen. */
int GetCursorPos(POINT *a_point) { if (a_point) { a_point->x = 0; a_point->y = 0; } return 0; }
int GetWindowRect(HWND a_window, RECT *a_rect) { (void)a_window; if (a_rect) { a_rect->left = a_rect->top = a_rect->right = a_rect->bottom = 0; } return 0; }
int PtInRect(const RECT *a_rect, POINT a_point)
{
	return a_rect && a_point.x >= a_rect->left && a_point.x < a_rect->right && a_point.y >= a_rect->top && a_point.y < a_rect->bottom;
}
/* The work area as SPI_GETWORKAREA answers it: the first monitor's geometry in pixels
   (GTK 4 has no "work area" query; panels and docks are the compositor's business). */
int SystemParametersInfoW(unsigned int a_action, unsigned int a_param, void *a_out, unsigned int a_ini)
{
	GdkMonitor *l_monitor = shell_first_monitor();
	GdkRectangle g;
	int l_scale;
	RECT *r = (RECT *)a_out;
	(void)a_param; (void)a_ini;
	if (a_action != SPI_GETWORKAREA || !a_out || !l_monitor) return 0;
	gdk_monitor_get_geometry(l_monitor, &g);
	l_scale = gdk_monitor_get_scale_factor(l_monitor);
	r->left = g.x * l_scale;
	r->top = g.y * l_scale;
	r->right = (g.x + g.width) * l_scale;
	r->bottom = (g.y + g.height) * l_scale;
	return 1;
}

static void shell_take_drops(GtkWidget *a_widget, gpointer d);   /* below, with files */

/* ------------------------------------------------------------------ the queue */

/* [type, a, b, c] per slot, as on Windows. Pushed on the GTK thread only (a worker's wake
   reaches it through g_idle_add). */
#define SHELL_QCAP 1024
static int s_q[SHELL_QCAP][4];
static int s_qhead = 0, s_qtail = 0;

void shell_push(int t, int a, int b, int c)
{
	int next = (s_qtail + 1) % SHELL_QCAP;
	if (next == s_qhead) return;
	s_q[s_qtail][0] = t; s_q[s_qtail][1] = a; s_q[s_qtail][2] = b; s_q[s_qtail][3] = c;
	s_qtail = next;
}

/* Replace the last queued event of type `t' instead of adding one (moves, resizes), or,
   with `a_sum', add to its third field (wheel turns). Answers whether it did. */
static int shell_coalesce(int t, int a, int b, int c, int a_sum)
{
	int last = (s_qtail + SHELL_QCAP - 1) % SHELL_QCAP;
	if (s_qtail == s_qhead || s_q[last][0] != t) return 0;
	s_q[last][1] = a; s_q[last][2] = b;
	if (a_sum) s_q[last][3] += c; else s_q[last][3] = c;
	return 1;
}

int shell_next_event(int *out4)
{
	int i;
	if (s_qhead == s_qtail) return 0;
	for (i = 0; i < 4; i++) out4[i] = s_q[s_qhead][i];
	s_qhead = (s_qhead + 1) % SHELL_QCAP;
	return out4[0];
}

/* ------------------------------------------------------------------ state */

static GtkWidget *s_window = NULL;            /* the main window */
static GtkWidget *s_area = NULL;              /* its drawing area */
static cairo_surface_t *s_backing = NULL;     /* the window's image, device pixels: the "DC" */
static int s_quit = 0;                        /* the window is gone: the pump answers 0 */
static int s_start_hidden = 0, s_close_requests = 0, s_cursor = 0;
static int s_backdrop = 0x12141B;             /* Windows' default: RGB(18, 20, 27) */
static guint s_heartbeat = 0, s_fast = 0, s_dwell = 0;
static gint s_wake_pending = 0;
static GThread *s_pump_thread = NULL;
static double s_pointer_x = 0, s_pointer_y = 0; /* the last pointer position, pixels */
static int s_primary_down = 0;                /* the primary button is held: a move is a drag */

static void shell_app(void)
{
	static int l_done = 0;
	if (l_done) return;
	l_done = 1;
	gtk_init();
	s_pump_thread = g_thread_self();
}

/* Device pixels per logical pixel of the main window (of the first monitor before it opens). */
static int shell_scale(void)
{
	GdkMonitor *l_monitor;
	if (s_window) return gtk_widget_get_scale_factor(s_window);
	l_monitor = shell_first_monitor();
	return l_monitor ? gdk_monitor_get_scale_factor(l_monitor) : 1;
}

/* ------------------------------------------------------------------ keys */

/* Windows virtual-key codes, from a GDK key value: letters and digits by the character
   (so the layout decides, as on Windows), the rest by the key. 0 when the key has no
   Windows equivalent the shell reports. */
static int shell_vk(guint a_keyval)
{
	guint u;
	switch (a_keyval) {
		case GDK_KEY_Left: case GDK_KEY_KP_Left: return 0x25;
		case GDK_KEY_Up: case GDK_KEY_KP_Up: return 0x26;
		case GDK_KEY_Right: case GDK_KEY_KP_Right: return 0x27;
		case GDK_KEY_Down: case GDK_KEY_KP_Down: return 0x28;
		case GDK_KEY_Home: case GDK_KEY_KP_Home: return 0x24;
		case GDK_KEY_End: case GDK_KEY_KP_End: return 0x23;
		case GDK_KEY_Page_Up: case GDK_KEY_KP_Page_Up: return 0x21;
		case GDK_KEY_Page_Down: case GDK_KEY_KP_Page_Down: return 0x22;
		case GDK_KEY_Delete: case GDK_KEY_KP_Delete: return 0x2E;
		case GDK_KEY_BackSpace: return 0x08;
		case GDK_KEY_Return: case GDK_KEY_KP_Enter: return 0x0D;
		case GDK_KEY_Tab: case GDK_KEY_ISO_Left_Tab: return 0x09;
		case GDK_KEY_Escape: return 0x1B;
		case GDK_KEY_space: return 0x20;
		case GDK_KEY_plus: case GDK_KEY_equal: return 0xBB;
		case GDK_KEY_minus: case GDK_KEY_underscore: return 0xBD;
		case GDK_KEY_KP_Add: return 0x6B;
		case GDK_KEY_KP_Subtract: return 0x6D;
		case GDK_KEY_semicolon: case GDK_KEY_colon: return 0xBA;
		case GDK_KEY_slash: case GDK_KEY_question: return 0xBF;
		case GDK_KEY_grave: case GDK_KEY_asciitilde: return 0xC0;
		case GDK_KEY_bracketleft: case GDK_KEY_braceleft: return 0xDB;
		case GDK_KEY_backslash: case GDK_KEY_bar: return 0xDC;
		case GDK_KEY_bracketright: case GDK_KEY_braceright: return 0xDD;
		case GDK_KEY_apostrophe: case GDK_KEY_quotedbl: return 0xDE;
		case GDK_KEY_comma: case GDK_KEY_less: return 0xBC;
		case GDK_KEY_period: case GDK_KEY_greater: return 0xBE;
	}
	if (a_keyval >= GDK_KEY_F1 && a_keyval <= GDK_KEY_F12) return 0x70 + (int)(a_keyval - GDK_KEY_F1);
	if (a_keyval >= GDK_KEY_KP_0 && a_keyval <= GDK_KEY_KP_9) return 0x60 + (int)(a_keyval - GDK_KEY_KP_0);
	u = gdk_keyval_to_unicode(gdk_keyval_to_upper(a_keyval));
	if ((u >= 'A' && u <= 'Z') || (u >= '0' && u <= '9')) return (int)u;
	return 0;
}

/* Windows' policy (simple_shell.h): which key-downs the window hears as event 4. */
int shell_keydown_is_ours(int l_vk, int l_ctrl, int l_alt)
{
	if (l_vk == 0x25 || l_vk == 0x27 || l_vk == 0x24 || l_vk == 0x23 || l_vk == 0x2E || l_vk == 0x26 ||
		l_vk == 0x28 || l_vk == 0x21 || l_vk == 0x22 || l_vk == 0xBB || l_vk == 0xBD || l_vk == 0x6B || l_vk == 0x6D)
		return 1;
	if (l_vk >= 0x70 && l_vk <= 0x7B) return 1;
	if (l_ctrl && !l_alt)
		return (l_vk >= '0' && l_vk <= '9') || (l_vk >= 0x60 && l_vk <= 0x69)
			|| (l_vk >= 0xBA && l_vk <= 0xC0) || (l_vk >= 0xDB && l_vk <= 0xDE);
	return 0;
}

/* Windows' Alt-door policy, kept for the code that asks it. */
int shell_syskey_is_ours(int l_vk)
{
	return (l_vk >= 'A' && l_vk <= 'Z') || (l_vk >= '0' && l_vk <= '9') || l_vk == 0xBB || l_vk == 0xBD
		|| l_vk == 0x6B || l_vk == 0x6D || l_vk == 0x79 || l_vk == 0x25 || l_vk == 0x27;
}
int shell_syschar_is_ours(int l_ch)
{
	return (l_ch >= 'A' && l_ch <= 'Z') || (l_ch >= 'a' && l_ch <= 'z') || (l_ch >= '0' && l_ch <= '9')
		|| l_ch == '+' || l_ch == '-' || l_ch == '=';
}

/* The keyboard's modifiers now (GDK keeps them per seat). */
static GdkModifierType shell_modifiers(void)
{
	GdkDisplay *l_display = gdk_display_get_default();
	GdkSeat *l_seat = l_display ? gdk_display_get_default_seat(l_display) : NULL;
	GdkDevice *l_keyboard = l_seat ? gdk_seat_get_keyboard(l_seat) : NULL;
	return l_keyboard ? gdk_device_get_modifier_state(l_keyboard) : 0;
}
int shell_control_down(void) { return (shell_modifiers() & GDK_CONTROL_MASK) ? 1 : 0; }
int shell_alt_down(void) { return (shell_modifiers() & GDK_ALT_MASK) ? 1 : 0; }
int shell_shift_down(void) { return (shell_modifiers() & GDK_SHIFT_MASK) ? 1 : 0; }
int shell_shift_held(void) { return shell_shift_down(); }

/* A character as Windows delivers it: one event 3 per UTF-16 code unit. */
static void shell_emit_char(guint32 a_code)
{
	if (a_code >= 0x10000) {
		guint32 v = a_code - 0x10000;
		shell_push(3, (int)(0xD800 + (v >> 10)), 0, 0);
		shell_push(3, (int)(0xDC00 + (v & 0x3FF)), 0, 0);
	} else if (a_code > 0) shell_push(3, (int)a_code, 0, 0);
}

static gboolean shell_on_key(GtkEventControllerKey *k, guint a_keyval, guint a_code, GdkModifierType a_state, gpointer d)
{
	int l_ctrl = (a_state & GDK_CONTROL_MASK) ? 1 : 0, l_alt = (a_state & GDK_ALT_MASK) ? 1 : 0;
	int vk = shell_vk(a_keyval);
	(void)k; (void)a_code; (void)d;
	if (vk && (shell_keydown_is_ours(vk, l_ctrl, l_alt) || (l_alt && (vk == 0x25 || vk == 0x27))))
		shell_push(4, vk, 0, 0);
	switch (vk) {
		case 0x08: case 0x0D: case 0x09: case 0x1B:
			shell_push(3, vk, 0, 0);
			break;
		default:
			if (l_ctrl) {
				if (vk >= 'A' && vk <= 'Z') shell_push(3, vk - 'A' + 1, 0, 0);
			} else shell_emit_char(gdk_keyval_to_unicode(a_keyval));
	}
	return TRUE;
}

/* ------------------------------------------------------------------ the view */

/* The backing image follows the drawing area's size in device pixels; Eiffel hears the new
   size (16) and is asked to draw (6), as Windows sends WM_SIZE then WM_PAINT. */
static void shell_rebuild_backing(void)
{
	int l_scale = shell_scale();
	int w = s_area ? gtk_widget_get_width(s_area) * l_scale : 0, h = s_area ? gtk_widget_get_height(s_area) * l_scale : 0;
	cairo_surface_t *l_new;
	if (w < 1 || h < 1) return;
	if (s_backing && cairo_image_surface_get_width(s_backing) == w && cairo_image_surface_get_height(s_backing) == h) return;
	l_new = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
	if (s_backing) {
		/* keep the old picture until the program draws a new one */
		cairo_t *cr = cairo_create(l_new);
		cairo_set_source_surface(cr, s_backing, 0, 0);
		cairo_paint(cr);
		cairo_destroy(cr);
		cairo_surface_destroy(s_backing);
	}
	s_backing = l_new;
	if (!shell_coalesce(16, w, h, 0, 0)) shell_push(16, w, h, 0);
	shell_push(6, 0, 0, 0);
}
static void shell_on_resize(GtkDrawingArea *a, int w, int h, gpointer d) { (void)a; (void)w; (void)h; (void)d; shell_rebuild_backing(); }
static void shell_on_scale(GObject *o, GParamSpec *p, gpointer d) { (void)o; (void)p; (void)d; shell_rebuild_backing(); }

/* Paint the backdrop, then the program's picture at its natural size, anchored top-left. */
static void shell_draw(GtkDrawingArea *a, cairo_t *cr, int w, int h, gpointer d)
{
	int l_scale = shell_scale();
	(void)a; (void)d;
	cairo_set_source_rgb(cr, ((s_backdrop >> 16) & 0xFF) / 255.0, ((s_backdrop >> 8) & 0xFF) / 255.0, (s_backdrop & 0xFF) / 255.0);
	cairo_rectangle(cr, 0, 0, w, h);
	cairo_fill(cr);
	if (!s_backing) return;
	cairo_surface_flush(s_backing);
	cairo_save(cr);
	cairo_scale(cr, 1.0 / l_scale, 1.0 / l_scale);
	cairo_set_source_surface(cr, s_backing, 0, 0);
	cairo_paint(cr);
	cairo_restore(cr);
}

/* Pointer positions in device pixels. */
static int shell_px(double a_logical) { return (int)floor(a_logical * shell_scale()); }

static void shell_on_press(GtkGestureClick *g, int n, double x, double y, gpointer d)
{
	guint b = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(g));
	(void)d;
	s_pointer_x = x; s_pointer_y = y;
	if (s_area) gtk_widget_grab_focus(s_area);
	if (b == GDK_BUTTON_PRIMARY) {
		s_primary_down = 1;
		shell_push(n == 2 ? 8 : n >= 3 ? 12 : 2, shell_px(x), shell_px(y), 0);
	} else if (b == GDK_BUTTON_MIDDLE) shell_push(17, shell_px(x), shell_px(y), 0);
}
/* The main window hears the right button on release (11), as on Windows. */
static void shell_on_release(GtkGestureClick *g, int n, double x, double y, gpointer d)
{
	guint b = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(g));
	(void)n; (void)d;
	if (b == GDK_BUTTON_PRIMARY) { s_primary_down = 0; shell_push(10, shell_px(x), shell_px(y), 0); }
	else if (b == GDK_BUTTON_SECONDARY) shell_push(11, shell_px(x), shell_px(y), 0);
}
static void shell_on_motion(GtkEventControllerMotion *m, double x, double y, gpointer d)
{
	(void)m; (void)d;
	s_pointer_x = x; s_pointer_y = y;
	if (s_primary_down) shell_push(9, shell_px(x), shell_px(y), 0);
	else if (!shell_coalesce(13, shell_px(x), shell_px(y), 0, 0)) shell_push(13, shell_px(x), shell_px(y), 0);
}
static void shell_on_leave(GtkEventControllerMotion *m, gpointer d) { (void)m; (void)d; shell_push(14, 0, 0, 0); }
/* Windows counts 120 per notch, positive away from the user; GTK's dy is positive toward. */
static gboolean shell_on_scroll(GtkEventControllerScroll *s, double dx, double dy, gpointer d)
{
	static double l_rest = 0;
	double v = -dy * 120.0 + l_rest;
	int l_delta = (int)v;
	(void)s; (void)dx; (void)d;
	l_rest = v - l_delta;
	if (l_delta == 0) return TRUE;
	if (!shell_coalesce(15, shell_px(s_pointer_x), shell_px(s_pointer_y), l_delta, 1))
		shell_push(15, shell_px(s_pointer_x), shell_px(s_pointer_y), l_delta);
	return TRUE;
}

/* ------------------------------------------------------------------ window, timers */

static gboolean shell_on_close_request(GtkWindow *w, gpointer d)
{
	(void)w; (void)d;
	if (s_close_requests) { shell_push(66, 0, 0, 0); return TRUE; }   /* the program decides */
	return FALSE;
}
static void shell_on_destroy(GtkWidget *w, gpointer d)
{
	(void)w; (void)d;
	if (s_heartbeat) { g_source_remove(s_heartbeat); s_heartbeat = 0; }
	if (s_fast) { g_source_remove(s_fast); s_fast = 0; }
	if (s_dwell) { g_source_remove(s_dwell); s_dwell = 0; }
	s_close_requests = 0;
	s_quit = 1;
	s_window = NULL;
	s_area = NULL;
}
static gboolean shell_heartbeat(gpointer d) { (void)d; g_atomic_int_set(&s_wake_pending, 0); shell_push(7, 0, 0, 0); return G_SOURCE_CONTINUE; }
static gboolean shell_fast_tick(gpointer d) { (void)d; shell_push(25, 0, 0, 0); return G_SOURCE_CONTINUE; }
static gboolean shell_dwell(gpointer d) { (void)d; s_dwell = 0; shell_push(55, 0, 0, 0); return G_SOURCE_REMOVE; }

void *shell_create_window(const void *title, int px, int py, int cw, int ch)
{
	GtkEventController *k, *m, *s;
	GtkGesture *g;
	int l_scale;
	shell_app();
	if (g_thread_self() != s_pump_thread) return NULL;
	(void)px; (void)py;   /* GTK 4 does not place windows: the compositor does */
	s_quit = 0;
	l_scale = shell_scale();
	s_window = gtk_window_new();
	gtk_window_set_title(GTK_WINDOW(s_window), title ? (const char *)title : "");
	gtk_window_set_default_size(GTK_WINDOW(s_window), cw / l_scale, ch / l_scale);
	s_area = gtk_drawing_area_new();
	gtk_widget_set_focusable(s_area, TRUE);
	gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(s_area), shell_draw, NULL, NULL);
	g_signal_connect(s_area, "resize", G_CALLBACK(shell_on_resize), NULL);
	g_signal_connect(s_window, "notify::scale-factor", G_CALLBACK(shell_on_scale), NULL);
	g = gtk_gesture_click_new();
	gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(g), 0);   /* every button */
	g_signal_connect(g, "pressed", G_CALLBACK(shell_on_press), NULL);
	g_signal_connect(g, "released", G_CALLBACK(shell_on_release), NULL);
	gtk_widget_add_controller(s_area, GTK_EVENT_CONTROLLER(g));
	m = gtk_event_controller_motion_new();
	g_signal_connect(m, "motion", G_CALLBACK(shell_on_motion), NULL);
	g_signal_connect(m, "leave", G_CALLBACK(shell_on_leave), NULL);
	gtk_widget_add_controller(s_area, m);
	s = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_VERTICAL);
	g_signal_connect(s, "scroll", G_CALLBACK(shell_on_scroll), NULL);
	gtk_widget_add_controller(s_area, s);
	k = gtk_event_controller_key_new();
	g_signal_connect(k, "key-pressed", G_CALLBACK(shell_on_key), NULL);
	gtk_widget_add_controller(s_window, k);
	shell_take_drops(s_area, GINT_TO_POINTER(0));
	gtk_window_set_child(GTK_WINDOW(s_window), s_area);
	g_signal_connect(s_window, "close-request", G_CALLBACK(shell_on_close_request), NULL);
	g_signal_connect(s_window, "destroy", G_CALLBACK(shell_on_destroy), NULL);
	if (!s_start_hidden) gtk_window_present(GTK_WINDOW(s_window));
	gtk_widget_grab_focus(s_area);
	s_heartbeat = g_timeout_add(s_shell_heartbeat_ms, shell_heartbeat, NULL);
	return s_window;
}

void shell_close_window(void) { if (s_window) gtk_window_destroy(GTK_WINDOW(s_window)); }
void shell_request_close(void) { if (s_window) gtk_window_close(GTK_WINDOW(s_window)); }
void shell_set_close_requests(int on) { s_close_requests = on ? 1 : 0; }
void shell_set_start_hidden(int l_on) { s_start_hidden = l_on ? 1 : 0; }
void shell_set_caption(const void *l_title) { if (s_window) gtk_window_set_title(GTK_WINDOW(s_window), l_title ? (const char *)l_title : ""); }
int shell_main_is_shown(void) { return s_window && gtk_widget_get_visible(s_window) ? 1 : 0; }
void shell_show_main(int l_on)
{
	if (!s_window) return;
	if (l_on) gtk_window_present(GTK_WINDOW(s_window)); else gtk_widget_set_visible(s_window, FALSE);
}
void shell_set_backdrop(void *hwnd, int rgb) { (void)hwnd; s_backdrop = rgb & 0xFFFFFF; if (s_area) gtk_widget_queue_draw(s_area); }
void shell_set_cursor_kind(int k)
{
	static const char *const l_names[] = {"default", "text", "pointer", "ew-resize", "ns-resize", "crosshair"};
	s_cursor = k;
	if (s_area) gtk_widget_set_cursor_from_name(s_area, l_names[(k >= 0 && k <= 5) ? k : 0]);
}
void shell_set_heartbeat(int l_ms)
{
	s_shell_heartbeat_ms = l_ms;
	if (s_heartbeat) { g_source_remove(s_heartbeat); s_heartbeat = g_timeout_add(l_ms, shell_heartbeat, NULL); }
}
void shell_set_fast_timer(int ms)
{
	if (!s_window || ms <= 0) return;
	if (s_fast) g_source_remove(s_fast);
	s_fast = g_timeout_add(ms, shell_fast_tick, NULL);
}
void shell_kill_fast_timer(void) { if (s_fast) { g_source_remove(s_fast); s_fast = 0; } }
void shell_arm_dwell_timer(int l_ms)
{
	if (l_ms <= 0) return;
	if (s_dwell) g_source_remove(s_dwell);
	s_dwell = g_timeout_add(l_ms, shell_dwell, NULL);
}
void shell_cancel_dwell_timer(void) { if (s_dwell) { g_source_remove(s_dwell); s_dwell = 0; } }
int shell_dwell_is_armed(void) { return s_dwell ? 1 : 0; }

/* ------------------------------------------------------------------ drawing */

/* No device context on GTK: the "DC" is the window's backing image, which simple_cairo's
   off-Windows surface-for-DC references; releasing it shows it. */
void *shell_get_dc(void) { return s_window ? (void *)s_backing : NULL; }
void shell_release_dc(void *dc) { if (dc && s_area) gtk_widget_queue_draw(s_area); }

/* ------------------------------------------------------------------ the pump */

/* Wait for one event and handle it: 0 once the window is gone (Windows' WM_QUIT). */
int shell_pump(void)
{
	if (s_quit) return 0;
	g_main_context_iteration(NULL, TRUE);
	return s_quit ? 0 : 1;
}
/* Handle every event already waiting: 0 once the window is gone. */
int shell_pump_pending(void)
{
	while (!s_quit && g_main_context_iteration(NULL, FALSE)) { }
	return s_quit ? 0 : 1;
}
static gboolean shell_stop_waiting(gpointer d) { *(int *)d = 1; return G_SOURCE_REMOVE; }
/* Handle events until one is queued for Eiffel or `ms' has passed: 0 once the window is gone. */
int shell_pump_until(int ms)
{
	gint64 l_end = g_get_monotonic_time() + (gint64)ms * 1000;
	for (;;) {
		int l_timed_out = 0;
		guint l_timer;
		gint64 l_left;
		if (!shell_pump_pending()) return 0;
		if (s_qhead != s_qtail) return 1;
		l_left = l_end - g_get_monotonic_time();
		if (l_left <= 0) return 1;
		l_timer = g_timeout_add((guint)((l_left + 999) / 1000), shell_stop_waiting, &l_timed_out);
		g_main_context_iteration(NULL, TRUE);
		if (!l_timed_out) g_source_remove(l_timer);
		if (s_quit) return 0;
	}
}
/* Handle events for `ms' milliseconds with or without a window (SHELL_DESKTOP.pump_for). */
void shell_pump_for(int ms)
{
	gint64 l_end;
	shell_app();
	l_end = g_get_monotonic_time() + (gint64)ms * 1000;
	for (;;) {
		int l_timed_out = 0;
		guint l_timer;
		gint64 l_left = l_end - g_get_monotonic_time();
		if (l_left <= 0) return;
		l_timer = g_timeout_add((guint)((l_left + 999) / 1000), shell_stop_waiting, &l_timed_out);
		g_main_context_iteration(NULL, TRUE);
		if (!l_timed_out) g_source_remove(l_timer);
	}
}

/* ------------------------------------------------------------------ the wake */

static gboolean shell_deliver_wake(gpointer d) { (void)d; g_atomic_int_set(&s_wake_pending, 0); shell_push(54, 0, 0, 0); return G_SOURCE_REMOVE; }
/* From any thread: make the pump return with event 54. 1 sent, 2 one already on its way. */
int shell_wake(void)
{
	if (!g_atomic_int_compare_and_exchange(&s_wake_pending, 0, 1)) return 2;
	g_idle_add(shell_deliver_wake, NULL);   /* GLib's main context is safe to reach from any thread */
	g_main_context_wakeup(NULL);
	return 1;
}
void shell_claim_pump_thread(int l_on) { if (l_on) s_pump_thread = g_thread_self(); g_atomic_int_set(&s_wake_pending, 0); }
int shell_is_pump_thread(void) { return s_pump_thread == NULL || g_thread_self() == s_pump_thread; }

/* ------------------------------------------------------------------ appearance */

/* GTK 4 knows the app's own preference; a desktop's dark style shows in the theme's name. */
int shell_system_prefers_dark(void)
{
	GtkSettings *l_settings;
	gboolean l_dark = FALSE;
	char *l_theme = NULL;
	int l_result;
	shell_app();
	l_settings = gtk_settings_get_default();
	if (!l_settings) return 0;
	g_object_get(l_settings, "gtk-application-prefer-dark-theme", &l_dark, "gtk-theme-name", &l_theme, NULL);
	l_result = l_dark || (l_theme && g_str_has_suffix(l_theme, "-dark")) ? 1 : 0;
	g_free(l_theme);
	return l_result;
}
int shell_high_contrast_on(void)
{
	GtkSettings *l_settings = gtk_settings_get_default();
	char *l_theme = NULL;
	int l_result;
	if (!l_settings) return 0;
	g_object_get(l_settings, "gtk-theme-name", &l_theme, NULL);
	l_result = l_theme && g_str_has_prefix(l_theme, "HighContrast") ? 1 : 0;
	g_free(l_theme);
	return l_result;
}
int shell_reduces_motion(void)
{
	GtkSettings *l_settings = gtk_settings_get_default();
	gboolean l_animate = TRUE;
	if (!l_settings) return 0;
	g_object_get(l_settings, "gtk-enable-animations", &l_animate, NULL);
	return l_animate ? 0 : 1;
}
int shell_set_dark_title_bar(void *hwnd, int l_on)
{
	GtkSettings *l_settings = gtk_settings_get_default();
	(void)hwnd;
	if (!l_settings) return 0;
	g_object_set(l_settings, "gtk-application-prefer-dark-theme", l_on ? TRUE : FALSE, NULL);
	return 1;
}
/* Windows message plumbing, kept for the code that calls it: GTK reports these changes
   itself, so the filters answer "not mine". */
int shell_setting_changed(const void *l_area) { (void)l_area; return 0; }
int shell_contrast_changed(unsigned int l_spi) { (void)l_spi; return 0; }
int shell_motion_changed(unsigned int l_spi) { (void)l_spi; return 0; }

/* ------------------------------------------------------------------ the desktop, the clock */

/* The virtual desktop (every monitor together), in pixels, as SM_XVIRTUALSCREEN and kin. */
static void shell_virtual_desktop(int *x, int *y, int *w, int *h)
{
	GdkDisplay *l_display;
	GListModel *l_all;
	guint i, n;
	int l_left = 0, l_top = 0, l_right = 0, l_bottom = 0, l_first = 1;
	shell_app();
	l_display = gdk_display_get_default();
	l_all = l_display ? gdk_display_get_monitors(l_display) : NULL;
	n = l_all ? g_list_model_get_n_items(l_all) : 0;
	for (i = 0; i < n; i++) {
		GdkMonitor *l_m = g_list_model_get_item(l_all, i);
		GdkRectangle g;
		int k = gdk_monitor_get_scale_factor(l_m);
		gdk_monitor_get_geometry(l_m, &g);
		g_object_unref(l_m);
		if (l_first || g.x * k < l_left) l_left = g.x * k;
		if (l_first || g.y * k < l_top) l_top = g.y * k;
		if (l_first || (g.x + g.width) * k > l_right) l_right = (g.x + g.width) * k;
		if (l_first || (g.y + g.height) * k > l_bottom) l_bottom = (g.y + g.height) * k;
		l_first = 0;
	}
	*x = l_left; *y = l_top; *w = l_right - l_left; *h = l_bottom - l_top;
}
int shell_screen_x(void) { int x, y, w, h; shell_virtual_desktop(&x, &y, &w, &h); return x; }
int shell_screen_y(void) { int x, y, w, h; shell_virtual_desktop(&x, &y, &w, &h); return y; }
int shell_screen_w(void) { int x, y, w, h; shell_virtual_desktop(&x, &y, &w, &h); return w; }
int shell_screen_h(void) { int x, y, w, h; shell_virtual_desktop(&x, &y, &w, &h); return h; }
double shell_now_ms(void) { return (double)g_get_monotonic_time() / 1000.0; }
int shell_minutes_of_day(void)
{
	GDateTime *l_now = g_date_time_new_now_local();
	int l_minutes = g_date_time_get_hour(l_now) * 60 + g_date_time_get_minute(l_now);
	g_date_time_unref(l_now);
	return l_minutes;
}

/* ------------------------------------------------------------------ fonts */

/* A font file for this process, as AddFontResourceEx(FR_PRIVATE): 1 on success (a font
   already added counts). fontconfig is what GTK, Pango and simple_shaping all ask. */
int shell_add_font(const char *path)
{
	if (!path || !*path) return 0;
	return FcConfigAppFontAddFile(FcConfigGetCurrent(), (const FcChar8 *)path) ? 1 : 0;
}

/* ------------------------------------------------------------------ clipboard */

/* GTK 4's clipboard answers asynchronously; the shell's contract is synchronous, so a read
   runs the main loop until its answer arrives (a second at most). */
typedef struct { int done; char *text; GdkTexture *texture; } ShellClipRead;
static GdkClipboard *shell_clipboard(void)
{
	GdkDisplay *l_display;
	shell_app();
	l_display = gdk_display_get_default();
	return l_display ? gdk_display_get_clipboard(l_display) : NULL;
}
static void shell_clip_wait(ShellClipRead *a_read)
{
	gint64 l_end = g_get_monotonic_time() + 1000000;
	while (!a_read->done && g_get_monotonic_time() < l_end) g_main_context_iteration(NULL, FALSE);
}
static void shell_clip_text_done(GObject *o, GAsyncResult *r, gpointer d)
{
	ShellClipRead *l_read = d;
	l_read->text = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(o), r, NULL);
	l_read->done = 1;
}
static void shell_clip_texture_done(GObject *o, GAsyncResult *r, gpointer d)
{
	ShellClipRead *l_read = d;
	l_read->texture = gdk_clipboard_read_texture_finish(GDK_CLIPBOARD(o), r, NULL);
	l_read->done = 1;
}

/* Text in as UTF-8. */
int shell_clip_set(const void *s)
{
	GdkClipboard *c = shell_clipboard();
	if (!c) return 0;
	gdk_clipboard_set_text(c, s ? (const char *)s : "");
	return 1;
}
/* UTF-16 into `buf' (the caller reads 16-bit units), at most cap - 1 and a terminator. */
int shell_clip_get(void *buf, int cap)
{
	GdkClipboard *c = shell_clipboard();
	ShellClipRead l_read = {0, NULL, NULL};
	gunichar2 *l_units;
	glong l_n = 0;
	if (!c || cap < 1) return 0;
	gdk_clipboard_read_text_async(c, NULL, shell_clip_text_done, &l_read);
	shell_clip_wait(&l_read);
	if (!l_read.text) return 0;
	l_units = g_utf8_to_utf16(l_read.text, -1, NULL, &l_n, NULL);
	g_free(l_read.text);
	if (!l_units) return 0;
	if (l_n > cap - 1) l_n = cap - 1;
	memcpy(buf, l_units, (size_t)l_n * sizeof(gunichar2));
	((gunichar2 *)buf)[l_n] = 0;
	g_free(l_units);
	return (int)l_n;
}
int shell_clip_has_text(void)
{
	GdkClipboard *c = shell_clipboard();
	GdkContentFormats *f = c ? gdk_clipboard_get_formats(c) : NULL;
	return f && (gdk_content_formats_contain_gtype(f, G_TYPE_STRING)
		|| gdk_content_formats_contain_mime_type(f, "text/plain;charset=utf-8")
		|| gdk_content_formats_contain_mime_type(f, "text/plain")) ? 1 : 0;
}

/* Images: 32-bit pixels as cairo keeps them (0xAARRGGBB, top row first; in memory B G R A,
   which is GDK's default memory format), always opaque, as the Windows half reads and
   writes them. */
int shell_clip_set_image(const void *bits, int w, int h, int stride)
{
	GdkClipboard *c = shell_clipboard();
	GBytes *l_bytes;
	GdkTexture *t;
	guchar *l_copy;
	int row, col;
	if (!c || !bits || w <= 0 || h <= 0 || stride < w * 4) return 0;
	l_copy = g_malloc((gsize)h * (gsize)w * 4);
	for (row = 0; row < h; row++) {
		const guint32 *src = (const guint32 *)((const char *)bits + (size_t)row * stride);
		guint32 *dst = (guint32 *)(l_copy + (size_t)row * w * 4);
		for (col = 0; col < w; col++) dst[col] = src[col] | 0xFF000000u;
	}
	l_bytes = g_bytes_new_take(l_copy, (gsize)h * (gsize)w * 4);
	t = gdk_memory_texture_new(w, h, GDK_MEMORY_DEFAULT, l_bytes, (gsize)w * 4);
	g_bytes_unref(l_bytes);
	gdk_clipboard_set_texture(c, t);
	g_object_unref(t);
	return 1;
}
int shell_clip_has_image(void)
{
	GdkClipboard *c = shell_clipboard();
	GdkContentFormats *f = c ? gdk_clipboard_get_formats(c) : NULL;
	return f && (gdk_content_formats_contain_gtype(f, GDK_TYPE_TEXTURE)
		|| gdk_content_formats_contain_mime_type(f, "image/png")) ? 1 : 0;
}
static GdkTexture *shell_clip_texture(void)
{
	GdkClipboard *c = shell_clipboard();
	ShellClipRead l_read = {0, NULL, NULL};
	if (!c) return NULL;
	gdk_clipboard_read_texture_async(c, NULL, shell_clip_texture_done, &l_read);
	shell_clip_wait(&l_read);
	return l_read.texture;
}
int shell_clip_image_size(int *w, int *h)
{
	GdkTexture *t = shell_clip_texture();
	*w = 0; *h = 0;
	if (!t) return 0;
	*w = gdk_texture_get_width(t);
	*h = gdk_texture_get_height(t);
	g_object_unref(t);
	return 1;
}
/* Only when the image is exactly `w' x `h' pixels, as on Windows. */
int shell_clip_get_image(void *bits, int w, int h, int stride)
{
	GdkTexture *t;
	int row, col;
	if (!bits || w <= 0 || h <= 0 || stride < w * 4) return 0;
	t = shell_clip_texture();
	if (!t) return 0;
	if (gdk_texture_get_width(t) != w || gdk_texture_get_height(t) != h) { g_object_unref(t); return 0; }
	gdk_texture_download(t, bits, (gsize)stride);
	g_object_unref(t);
	for (row = 0; row < h; row++) {
		guint32 *px = (guint32 *)((char *)bits + (size_t)row * stride);
		for (col = 0; col < w; col++) px[col] |= 0xFF000000u;
	}
	return 1;
}

/* ------------------------------------------------------------------ panels */

/* A panel is a window of its own (simple_widgets' floating windows, a document window). Its
   events use Windows' panel numbers with the slot in `c': 41 press, 64 double, 42 release,
   43 move, 65 leave, 45 wheel (the delta alone), 46 right press, 44 expose, 48 resized,
   60 key, 61 character, 62 close request (always: the program decides), 63 activated.
   Wayland neither places windows nor tells where they are, so a panel's place is its size
   alone, and moves (47, 49) are not reported. */
#define SHELL_PANELS 8
typedef struct {
	GtkWidget *window, *area;
	cairo_surface_t *backing;
	int fill, framed, document, alpha, accepts, primary_down, click_through;
	double px, py;
} ShellPanel;
static ShellPanel s_panel[SHELL_PANELS];

static int shell_panel_ok(int l_slot) { return l_slot >= 0 && l_slot < SHELL_PANELS && s_panel[l_slot].window ? 1 : 0; }
static int shell_coalesce_slot(int t, int a, int b, int a_slot)
{
	int last = (s_qtail + SHELL_QCAP - 1) % SHELL_QCAP;
	if (s_qtail == s_qhead || s_q[last][0] != t || s_q[last][3] != a_slot) return 0;
	s_q[last][1] = a; s_q[last][2] = b;
	return 1;
}
static int shell_panel_scale(int l_slot) { return shell_panel_ok(l_slot) ? gtk_widget_get_scale_factor(s_panel[l_slot].window) : shell_scale(); }
static int shell_panel_px(int l_slot, double a_logical) { return (int)floor(a_logical * shell_panel_scale(l_slot)); }

static void shell_panel_rebuild(int l_slot)
{
	ShellPanel *p = &s_panel[l_slot];
	int k = shell_panel_scale(l_slot);
	int w = gtk_widget_get_width(p->area) * k, h = gtk_widget_get_height(p->area) * k;
	cairo_surface_t *l_new;
	if (w < 1 || h < 1) return;
	if (p->backing && cairo_image_surface_get_width(p->backing) == w && cairo_image_surface_get_height(p->backing) == h) return;
	l_new = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
	{
		cairo_t *cr = cairo_create(l_new);
		cairo_set_source_rgb(cr, ((p->fill >> 16) & 0xFF) / 255.0, ((p->fill >> 8) & 0xFF) / 255.0, (p->fill & 0xFF) / 255.0);
		cairo_paint(cr);
		if (p->backing) { cairo_set_source_surface(cr, p->backing, 0, 0); cairo_paint(cr); }
		cairo_destroy(cr);
	}
	if (p->backing) cairo_surface_destroy(p->backing);
	p->backing = l_new;
	if (!shell_coalesce_slot(48, w, h, l_slot)) shell_push(48, w, h, l_slot);
	shell_push(44, 0, 0, l_slot);
}
static int shell_slot_of(gpointer d) { return GPOINTER_TO_INT(d) - 1; }
static void shell_panel_on_resize(GtkDrawingArea *a, int w, int h, gpointer d) { (void)a; (void)w; (void)h; shell_panel_rebuild(shell_slot_of(d)); }
static void shell_panel_draw(GtkDrawingArea *a, cairo_t *cr, int w, int h, gpointer d)
{
	int l_slot = shell_slot_of(d), k;
	ShellPanel *p;
	(void)a;
	if (!shell_panel_ok(l_slot)) return;
	p = &s_panel[l_slot];
	k = shell_panel_scale(l_slot);
	cairo_set_source_rgb(cr, ((p->fill >> 16) & 0xFF) / 255.0, ((p->fill >> 8) & 0xFF) / 255.0, (p->fill & 0xFF) / 255.0);
	cairo_rectangle(cr, 0, 0, w, h);
	cairo_fill(cr);
	if (!p->backing) return;
	cairo_surface_flush(p->backing);
	cairo_save(cr);
	cairo_scale(cr, 1.0 / k, 1.0 / k);
	cairo_set_source_surface(cr, p->backing, 0, 0);
	cairo_paint(cr);
	cairo_restore(cr);
}
static void shell_panel_on_press(GtkGestureClick *g, int n, double x, double y, gpointer d)
{
	int l_slot = shell_slot_of(d);
	guint b = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(g));
	if (!shell_panel_ok(l_slot)) return;
	s_panel[l_slot].px = x; s_panel[l_slot].py = y;
	gtk_widget_grab_focus(s_panel[l_slot].area);
	if (b == GDK_BUTTON_PRIMARY) {
		s_panel[l_slot].primary_down = 1;
		shell_push(n == 2 ? 64 : 41, shell_panel_px(l_slot, x), shell_panel_px(l_slot, y), l_slot);
	} else if (b == GDK_BUTTON_SECONDARY) shell_push(46, shell_panel_px(l_slot, x), shell_panel_px(l_slot, y), l_slot);
}
static void shell_panel_on_release(GtkGestureClick *g, int n, double x, double y, gpointer d)
{
	int l_slot = shell_slot_of(d);
	guint b = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(g));
	(void)n;
	if (!shell_panel_ok(l_slot) || b != GDK_BUTTON_PRIMARY) return;
	s_panel[l_slot].primary_down = 0;
	shell_push(42, shell_panel_px(l_slot, x), shell_panel_px(l_slot, y), l_slot);
}
static void shell_panel_on_motion(GtkEventControllerMotion *m, double x, double y, gpointer d)
{
	int l_slot = shell_slot_of(d), px, py;
	(void)m;
	if (!shell_panel_ok(l_slot)) return;
	s_panel[l_slot].px = x; s_panel[l_slot].py = y;
	px = shell_panel_px(l_slot, x); py = shell_panel_px(l_slot, y);
	if (!shell_coalesce_slot(43, px, py, l_slot)) shell_push(43, px, py, l_slot);
}
static void shell_panel_on_leave(GtkEventControllerMotion *m, gpointer d) { (void)m; shell_push(65, 0, 0, shell_slot_of(d)); }
static gboolean shell_panel_on_scroll(GtkEventControllerScroll *s, double dx, double dy, gpointer d)
{
	int l_delta = (int)(-dy * 120.0);
	(void)s; (void)dx;
	if (l_delta != 0) shell_push(45, l_delta, 0, shell_slot_of(d));
	return TRUE;
}
static gboolean shell_panel_on_key(GtkEventControllerKey *k, guint a_keyval, guint a_code, GdkModifierType a_state, gpointer d)
{
	int l_slot = shell_slot_of(d);
	int l_ctrl = (a_state & GDK_CONTROL_MASK) ? 1 : 0, l_alt = (a_state & GDK_ALT_MASK) ? 1 : 0;
	int vk = shell_vk(a_keyval);
	guint32 u;
	(void)k; (void)a_code;
	if (vk && (shell_keydown_is_ours(vk, l_ctrl, l_alt) || (l_alt && (vk == 0x25 || vk == 0x27)))) shell_push(60, vk, 0, l_slot);
	switch (vk) {
		case 0x08: case 0x0D: case 0x09: case 0x1B: shell_push(61, vk, 0, l_slot); break;
		default:
			if (l_ctrl) {
				if (vk >= 'A' && vk <= 'Z') shell_push(61, vk - 'A' + 1, 0, l_slot);
			} else if ((u = gdk_keyval_to_unicode(a_keyval)) != 0) {
				if (u >= 0x10000) {
					guint32 v = u - 0x10000;
					shell_push(61, (int)(0xD800 + (v >> 10)), 0, l_slot);
					shell_push(61, (int)(0xDC00 + (v & 0x3FF)), 0, l_slot);
				} else shell_push(61, (int)u, 0, l_slot);
			}
	}
	return TRUE;
}
static gboolean shell_panel_on_close(GtkWindow *w, gpointer d) { (void)w; shell_push(62, 0, 0, shell_slot_of(d)); return TRUE; }
static void shell_panel_on_active(GObject *o, GParamSpec *ps, gpointer d)
{
	(void)ps;
	shell_push(63, gtk_window_is_active(GTK_WINDOW(o)) ? 1 : 0, 0, shell_slot_of(d));
}

static int shell_panel_make(int l_w, int l_h, const void *l_title, int l_framed, int l_document)
{
	int l_slot = -1, i, k;
	ShellPanel *p;
	GtkGesture *g;
	GtkEventController *m, *s, *key;
	gpointer d;
	shell_app();
	for (i = 0; i < SHELL_PANELS && l_slot < 0; i++) if (!s_panel[i].window) l_slot = i;
	if (l_slot < 0 || l_w <= 0 || l_h <= 0 || g_thread_self() != s_pump_thread) return -1;
	p = &s_panel[l_slot];
	memset(p, 0, sizeof *p);
	p->fill = 0xFFFFFF; p->framed = l_framed; p->document = l_document; p->alpha = 255;
	d = GINT_TO_POINTER(l_slot + 1);
	k = shell_scale();
	p->window = gtk_window_new();
	gtk_window_set_title(GTK_WINDOW(p->window), l_title ? (const char *)l_title : "");
	gtk_window_set_default_size(GTK_WINDOW(p->window), l_w / k, l_h / k);
	gtk_window_set_decorated(GTK_WINDOW(p->window), l_framed ? TRUE : FALSE);
	if (l_framed && !l_document && s_window) gtk_window_set_transient_for(GTK_WINDOW(p->window), GTK_WINDOW(s_window));
	p->area = gtk_drawing_area_new();
	gtk_widget_set_focusable(p->area, TRUE);
	gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(p->area), shell_panel_draw, d, NULL);
	g_signal_connect(p->area, "resize", G_CALLBACK(shell_panel_on_resize), d);
	g = gtk_gesture_click_new();
	gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(g), 0);
	g_signal_connect(g, "pressed", G_CALLBACK(shell_panel_on_press), d);
	g_signal_connect(g, "released", G_CALLBACK(shell_panel_on_release), d);
	gtk_widget_add_controller(p->area, GTK_EVENT_CONTROLLER(g));
	m = gtk_event_controller_motion_new();
	g_signal_connect(m, "motion", G_CALLBACK(shell_panel_on_motion), d);
	g_signal_connect(m, "leave", G_CALLBACK(shell_panel_on_leave), d);
	gtk_widget_add_controller(p->area, m);
	s = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_VERTICAL);
	g_signal_connect(s, "scroll", G_CALLBACK(shell_panel_on_scroll), d);
	gtk_widget_add_controller(p->area, s);
	key = gtk_event_controller_key_new();
	g_signal_connect(key, "key-pressed", G_CALLBACK(shell_panel_on_key), d);
	gtk_widget_add_controller(p->window, key);
	shell_take_drops(p->area, d);
	gtk_window_set_child(GTK_WINDOW(p->window), p->area);
	g_signal_connect(p->window, "close-request", G_CALLBACK(shell_panel_on_close), d);
	g_signal_connect(p->window, "notify::is-active", G_CALLBACK(shell_panel_on_active), d);
	/* a backing image from the start, at the asked size, so the program can draw before the
	   compositor has shown the window */
	p->backing = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, l_w, l_h);
	return l_slot;
}

int shell_panel_open_framed_as(int l_x, int l_y, int l_w, int l_h, const void *l_title, int l_document)
{
	(void)l_x; (void)l_y;
	return shell_panel_make(l_w, l_h, l_title, 1, l_document ? 1 : 0);
}
int shell_panel_open_framed(int l_x, int l_y, int l_w, int l_h, const void *l_title) { return shell_panel_open_framed_as(l_x, l_y, l_w, l_h, l_title, 0); }
int shell_panel_open(int l_x, int l_y, int l_w, int l_h) { (void)l_x; (void)l_y; return shell_panel_make(l_w, l_h, NULL, 0, 0); }
void shell_panel_place(int l_slot, int l_x, int l_y, int l_w, int l_h)
{
	int k;
	(void)l_x; (void)l_y;
	if (!shell_panel_ok(l_slot) || l_w <= 0 || l_h <= 0) return;
	k = shell_panel_scale(l_slot);
	gtk_window_set_default_size(GTK_WINDOW(s_panel[l_slot].window), l_w / k, l_h / k);
}
void shell_panel_show(int l_slot, int l_x, int l_y, int l_w, int l_h)
{
	if (!shell_panel_ok(l_slot)) return;
	shell_panel_place(l_slot, l_x, l_y, l_w, l_h);
	gtk_widget_set_visible(s_panel[l_slot].window, TRUE);   /* shown, not presented (SWP_NOACTIVATE) */
}
void shell_panel_hide(int l_slot) { if (shell_panel_ok(l_slot)) gtk_widget_set_visible(s_panel[l_slot].window, FALSE); }
int shell_panel_is_visible(int l_slot) { return shell_panel_ok(l_slot) && gtk_widget_get_visible(s_panel[l_slot].window) ? 1 : 0; }
void shell_panel_close(int l_slot)
{
	ShellPanel *p;
	GtkWidget *w;
	if (!shell_panel_ok(l_slot)) return;
	p = &s_panel[l_slot];
	w = p->window;
	p->window = NULL; p->area = NULL;
	if (p->backing) { cairo_surface_destroy(p->backing); p->backing = NULL; }
	g_signal_handlers_disconnect_matched(w, G_SIGNAL_MATCH_DATA, 0, 0, NULL, NULL, GINT_TO_POINTER(l_slot + 1));
	gtk_window_destroy(GTK_WINDOW(w));
}
void shell_panel_set_title(int l_slot, const void *l_title) { if (shell_panel_ok(l_slot)) gtk_window_set_title(GTK_WINDOW(s_panel[l_slot].window), l_title ? (const char *)l_title : ""); }
void shell_panel_invalidate(int l_slot) { if (shell_panel_ok(l_slot)) gtk_widget_queue_draw(s_panel[l_slot].area); }
void *shell_panel_dc(int l_slot) { return shell_panel_ok(l_slot) ? (void *)s_panel[l_slot].backing : NULL; }
void shell_panel_release_dc(int l_slot, void *l_dc) { if (l_dc && shell_panel_ok(l_slot)) gtk_widget_queue_draw(s_panel[l_slot].area); }
void shell_panel_client_size(int l_slot, int *l_w, int *l_h)
{
	if (!shell_panel_ok(l_slot) || !s_panel[l_slot].backing) return;
	*l_w = cairo_image_surface_get_width(s_panel[l_slot].backing);
	*l_h = cairo_image_surface_get_height(s_panel[l_slot].backing);
}
/* Wayland tells no window's place: the rectangle is the size at the origin. */
void shell_panel_rect(int l_slot, int *l_x, int *l_y, int *l_w, int *l_h)
{
	if (!shell_panel_ok(l_slot) || !s_panel[l_slot].backing) return;
	*l_x = 0; *l_y = 0;
	*l_w = cairo_image_surface_get_width(s_panel[l_slot].backing);
	*l_h = cairo_image_surface_get_height(s_panel[l_slot].backing);
}
/* The panel's ground, and its image painted over with it (the Windows body fills the DC). */
void shell_panel_fill(int l_slot, int l_rgb)
{
	ShellPanel *p;
	if (!shell_panel_ok(l_slot)) return;
	p = &s_panel[l_slot];
	p->fill = l_rgb & 0xFFFFFF;
	if (p->backing) {
		cairo_t *cr = cairo_create(p->backing);
		cairo_set_source_rgb(cr, ((l_rgb >> 16) & 0xFF) / 255.0, ((l_rgb >> 8) & 0xFF) / 255.0, (l_rgb & 0xFF) / 255.0);
		cairo_paint(cr);
		cairo_destroy(cr);
	}
	gtk_widget_queue_draw(p->area);
}
int shell_panel_is_tool_window(int l_slot) { return shell_panel_ok(l_slot) && !s_panel[l_slot].document ? 1 : 0; }
int shell_panel_has_owner(int l_slot) { return shell_panel_ok(l_slot) && s_panel[l_slot].framed && !s_panel[l_slot].document ? 1 : 0; }
int shell_panel_can_minimize(int l_slot) { return shell_panel_ok(l_slot) && s_panel[l_slot].document ? 1 : 0; }
int shell_panel_is_topmost(int l_slot) { return shell_panel_ok(l_slot) && !s_panel[l_slot].framed ? 1 : 0; }
void shell_panel_set_opacity(int l_slot, int l_alpha)
{
	if (!shell_panel_ok(l_slot) || l_alpha < 0 || l_alpha > 255) return;
	gtk_widget_set_opacity(s_panel[l_slot].window, l_alpha / 255.0);
	s_panel[l_slot].alpha = l_alpha;
}
int shell_panel_opacity(int l_slot) { return shell_panel_ok(l_slot) ? s_panel[l_slot].alpha : 0; }
void shell_panel_set_click_through(int l_slot, int l_on)
{
	if (!shell_panel_ok(l_slot)) return;
	gtk_widget_set_can_target(s_panel[l_slot].area, l_on ? FALSE : TRUE);
	s_panel[l_slot].click_through = l_on ? 1 : 0;
}
int shell_panel_is_click_through(int l_slot) { return shell_panel_ok(l_slot) && s_panel[l_slot].click_through ? 1 : 0; }
void shell_panel_set_accepts_files(int l_slot, int l_on) { if (shell_panel_ok(l_slot)) s_panel[l_slot].accepts = l_on ? 1 : 0; }
int shell_panel_accepts_files(int l_slot) { return shell_panel_ok(l_slot) && s_panel[l_slot].accepts ? 1 : 0; }
HWND shell_panel_hwnd(int l_slot) { return shell_panel_ok(l_slot) ? (HWND)s_panel[l_slot].window : NULL; }

/* ------------------------------------------------------------------ files: drops and the open dialog */

/* The last drop's paths, UTF-16 and one per line, as the Windows half keeps them for
   `shell_drop_paths'. */
#define SHELL_DROPS_CAP 16384
static gunichar2 s_drops[SHELL_DROPS_CAP];
static int s_drops_len = 0;

/* Keep `a_paths' (UTF-8, one per line); answers how many paths. */
static int shell_keep_drops(const char *a_paths)
{
	glong n = 0;
	int l_count = 0;
	const char *c;
	gunichar2 *u = g_utf8_to_utf16(a_paths ? a_paths : "", -1, NULL, &n, NULL);
	if (!u) { s_drops_len = 0; return 0; }
	if (n > SHELL_DROPS_CAP - 1) n = SHELL_DROPS_CAP - 1;
	memcpy(s_drops, u, (size_t)n * sizeof(gunichar2));
	s_drops[n] = 0;
	s_drops_len = (int)n;
	g_free(u);
	if (n > 0) for (l_count = 1, c = a_paths; *c; c++) if (*c == '\n') l_count++;
	return l_count;
}
/* The paths of the last drop, UTF-16 and one per line, into `buf' (the caller reads 16-bit
   units); taking them empties the store, as on Windows. */
int shell_drop_paths(void *buf, int cap)
{
	int n = s_drops_len;
	if (cap < 1) return 0;
	if (n >= cap) n = cap - 1;
	memcpy(buf, s_drops, (size_t)n * sizeof(gunichar2));
	((gunichar2 *)buf)[n] = 0;
	s_drops_len = 0;
	return n;
}
/* A drop delivered as if from the file manager (the test door): `l_paths' one per line, UTF-8. */
void shell_panel_try_drop(int l_slot, int l_x, int l_y, const void *l_paths)
{
	if (!shell_panel_ok(l_slot) || !l_paths) return;
	shell_keep_drops((const char *)l_paths);
	shell_push(50, l_x, l_y, l_slot);
}
/* Files dropped: the main window always takes them (event 18: x, y, count), a panel when it
   accepts files (event 50: x, y, slot). `d' is the slot plus 1, or 0 for the main window. */
static gboolean shell_on_drop(GtkDropTarget *t, const GValue *v, double x, double y, gpointer d)
{
	int l_slot = GPOINTER_TO_INT(d) - 1, n;
	GString *l_paths;
	GSList *l;
	(void)t;
	if (!G_VALUE_HOLDS(v, GDK_TYPE_FILE_LIST)) return FALSE;
	if (l_slot >= 0 && !shell_panel_accepts_files(l_slot)) return FALSE;
	l_paths = g_string_new(NULL);
	for (l = g_value_get_boxed(v); l; l = l->next) {
		char *p = g_file_get_path(G_FILE(l->data));
		if (p) { if (l_paths->len) g_string_append_c(l_paths, '\n'); g_string_append(l_paths, p); g_free(p); }
	}
	n = shell_keep_drops(l_paths->str);
	g_string_free(l_paths, TRUE);
	if (n == 0) return FALSE;
	if (l_slot < 0) shell_push(18, shell_px(x), shell_px(y), n);
	else shell_push(50, shell_panel_px(l_slot, x), shell_panel_px(l_slot, y), l_slot);
	return TRUE;
}
static void shell_take_drops(GtkWidget *a_widget, gpointer d)
{
	GtkDropTarget *t = gtk_drop_target_new(GDK_TYPE_FILE_LIST, GDK_ACTION_COPY);
	g_signal_connect(t, "drop", G_CALLBACK(shell_on_drop), d);
	gtk_widget_add_controller(a_widget, GTK_EVENT_CONTROLLER(t));
}

/* The open dialog: GtkFileDialog answers asynchronously, so the call waits on the main loop. */
typedef struct { int done; GFile *file; } ShellFileChoice;
static void shell_file_chosen(GObject *o, GAsyncResult *r, gpointer d)
{
	ShellFileChoice *c = d;
	c->file = gtk_file_dialog_open_finish(GTK_FILE_DIALOG(o), r, NULL);
	c->done = 1;
}
/* A Windows filter ("Text|*.txt;*.md|All|*.*": description, patterns, ...) as GTK filters;
   NULL when it allows any file. */
static GListModel *shell_filters(const char *a_filter)
{
	gchar **l_parts;
	GListStore *l_store;
	int i, l_any = 0;
	if (!a_filter || !*a_filter) return NULL;
	l_parts = g_strsplit(a_filter, "|", -1);
	l_store = g_list_store_new(GTK_TYPE_FILE_FILTER);
	for (i = 0; l_parts[i] && l_parts[i + 1]; i += 2) {
		GtkFileFilter *f = gtk_file_filter_new();
		gchar **l_patterns = g_strsplit(l_parts[i + 1], ";", -1);
		int j;
		gtk_file_filter_set_name(f, l_parts[i]);
		for (j = 0; l_patterns[j]; j++) {
			char *p = g_strstrip(l_patterns[j]);
			if (strcmp(p, "*.*") == 0 || strcmp(p, "*") == 0) l_any = 1;
			gtk_file_filter_add_pattern(f, strcmp(p, "*.*") == 0 ? "*" : p);
		}
		g_strfreev(l_patterns);
		g_list_store_append(l_store, f);
		g_object_unref(f);
	}
	g_strfreev(l_parts);
	if (l_any && g_list_model_get_n_items(G_LIST_MODEL(l_store)) <= 1) { g_object_unref(l_store); return NULL; }
	return G_LIST_MODEL(l_store);
}
/* Choose one existing file: its path, UTF-8, into `l_out' (the caller reads NATIVE_STRING;
   the buffer holds 2 * l_cap bytes). 1 when a file was chosen. */
int shell_open_file_dialog(const void *l_title, const void *l_filter, const void *l_initial_dir, void *l_out, int l_cap)
{
	GtkFileDialog *g;
	GListModel *l_filters;
	ShellFileChoice c = {0, NULL};
	char *l_path;
	size_t l_len;
	if (!l_out || l_cap <= 1) return 0;
	((char *)l_out)[0] = 0;
	shell_app();
	g = gtk_file_dialog_new();
	if (l_title && *(const char *)l_title) gtk_file_dialog_set_title(g, (const char *)l_title);
	l_filters = shell_filters((const char *)l_filter);
	if (l_filters) { gtk_file_dialog_set_filters(g, l_filters); g_object_unref(l_filters); }
	if (l_initial_dir && *(const char *)l_initial_dir) {
		GFile *d = g_file_new_for_path((const char *)l_initial_dir);
		gtk_file_dialog_set_initial_folder(g, d);
		g_object_unref(d);
	}
	gtk_file_dialog_open(g, s_window ? GTK_WINDOW(s_window) : NULL, NULL, shell_file_chosen, &c);
	while (!c.done) g_main_context_iteration(NULL, TRUE);
	g_object_unref(g);
	if (!c.file) return 0;
	l_path = g_file_get_path(c.file);
	g_object_unref(c.file);
	if (!l_path) return 0;
	l_len = strlen(l_path);
	if (l_len > (size_t)l_cap * 2 - 1) { g_free(l_path); return 0; }
	memcpy(l_out, l_path, l_len + 1);
	g_free(l_path);
	return 1;
}

/* ------------------------------------------------------------------ monitors */

/* Each monitor as Windows' GetMonitorInfo answers it, in pixels: the monitor (0-3: left, top,
   right, bottom), its work area (4-7; GTK 4 has no work-area query, so the monitor again),
   and whether it is the primary one (8: the first GDK lists). */
#define SHELL_MONITOR_CAP 16
static int s_mon[SHELL_MONITOR_CAP][9];
static gunichar2 s_mon_name[SHELL_MONITOR_CAP][32];
static int s_mon_count = 0;

int shell_monitors_refresh(void)
{
	GdkDisplay *l_display;
	GListModel *l_all;
	guint i, n;
	shell_app();
	l_display = gdk_display_get_default();
	l_all = l_display ? gdk_display_get_monitors(l_display) : NULL;
	n = l_all ? g_list_model_get_n_items(l_all) : 0;
	s_mon_count = 0;
	for (i = 0; i < n && s_mon_count < SHELL_MONITOR_CAP; i++) {
		GdkMonitor *c = g_list_model_get_item(l_all, i);
		GdkRectangle g;
		int k = gdk_monitor_get_scale_factor(c), *m = s_mon[s_mon_count];
		const char *l_name = gdk_monitor_get_description(c);
		gunichar2 *u;
		glong l_len = 0;
		gdk_monitor_get_geometry(c, &g);
		m[0] = g.x * k; m[1] = g.y * k; m[2] = (g.x + g.width) * k; m[3] = (g.y + g.height) * k;
		m[4] = m[0]; m[5] = m[1]; m[6] = m[2]; m[7] = m[3];
		m[8] = i == 0 ? 1 : 0;
		if (!l_name) l_name = gdk_monitor_get_connector(c);
		u = g_utf8_to_utf16(l_name ? l_name : "", -1, NULL, &l_len, NULL);
		if (l_len > 31) l_len = 31;
		if (u) memcpy(s_mon_name[s_mon_count], u, (size_t)l_len * sizeof(gunichar2));
		s_mon_name[s_mon_count][u ? l_len : 0] = 0;
		g_free(u);
		g_object_unref(c);
		s_mon_count++;
	}
	return s_mon_count;
}
int shell_monitor_field(int l_i, int l_f) { return (l_i >= 0 && l_i < s_mon_count && l_f >= 0 && l_f <= 8) ? s_mon[l_i][l_f] : 0; }
/* The monitor's name, UTF-16 into `l_buf' (the caller reads 16-bit units). */
int shell_monitor_name(int l_i, void *l_buf, int l_cap)
{
	int n = 0;
	gunichar2 *b = (gunichar2 *)l_buf;
	if (l_i < 0 || l_i >= s_mon_count || l_cap <= 0) return 0;
	while (n < l_cap - 1 && n < 31 && s_mon_name[l_i][n]) { b[n] = s_mon_name[l_i][n]; n++; }
	b[n] = 0;
	return n;
}

/* ------------------------------------------------------------------ small things */

/* Open a file with its application, or a URL in the browser, as Windows' ShellExecute
   "open" does: 1 when it was handed over. */
int shell_shell_open(const void *path)
{
	const char *t = (const char *)path;
	char *l_uri;
	gboolean ok;
	if (!t || !*t) return 0;
	shell_app();
	if (strstr(t, "://") || g_str_has_prefix(t, "mailto:")) l_uri = g_strdup(t);
	else {
		if (!g_file_test(t, G_FILE_TEST_EXISTS)) return 0;
		l_uri = g_filename_to_uri(t, NULL, NULL);
		if (!l_uri) return 0;
	}
	ok = g_app_info_launch_default_for_uri(l_uri, NULL, NULL);
	g_free(l_uri);
	return ok ? 1 : 0;
}
