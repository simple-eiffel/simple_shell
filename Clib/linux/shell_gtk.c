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
static int shell_panel_begin_grip(int l_slot, GtkGesture *g, int l_code, double x, double y);   /* below, with the grips */
static void shell_panel_on_destroyed(GtkWidget *w, gpointer d);
static void shell_keep_text(const char *a_text);
static int shell_keep_drops(const char *a_paths);
static gboolean shell_drop_accept(GtkDropTarget *t, GdkDrop *drop, gpointer d);
static int s_dragging_out = 0, s_drag_landed_here = 0, s_main_takes_text = 0;

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
static gint s_pump_claimed = 0;            /* claim_pump_thread (1) until (0): a wake with no window has a pump to reach */
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
	/* A new window starts blank. The backing outlives a closed window (a resize keeps the old
	   picture until the program draws), so without this a new window of the same size began
	   with the last window's picture (seen as stray pixels in simple_widgets' tests). */
	if (s_backing) { cairo_surface_destroy(s_backing); s_backing = NULL; }
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
	if (!s_window && !g_atomic_int_get(&s_pump_claimed)) {
		/* as Windows: no window and no claimed pump, nobody to wake (Outcome_none) */
		g_atomic_int_set(&s_wake_pending, 0);
		return 0;
	}
	g_idle_add(shell_deliver_wake, NULL);   /* GLib's main context is safe to reach from any thread */
	g_main_context_wakeup(NULL);
	return 1;
}
void shell_claim_pump_thread(int l_on) { if (l_on) s_pump_thread = g_thread_self(); g_atomic_int_set(&s_pump_claimed, l_on ? 1 : 0); g_atomic_int_set(&s_wake_pending, 0); }
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
	/* the place the program asked for (Wayland tells no window's place) */
	int ax, ay, aw, ah;
	/* grips (1.11.0, 1.14.0, 1.15.0), as the Windows half keeps them */
	int drag, press_drag, axis, side_grip, bottom_grip, grip, minw, minh;
	/* 1.40.0: text dragged in */
	int takes_text;
	/* a framed panel's title bar height, in pixels: the window is the client plus it */
	int frame_h;
	/* the last window that had this slot, held until the slot's next window exists, so the two
	   never share an address (a handle compared after a destruction behind our back) */
	GtkWidget *gone;
} ShellPanel;
enum { Shell_ht_caption = 2, Shell_ht_left = 10, Shell_ht_right = 11, Shell_ht_top = 12, Shell_ht_topleft = 13,
	Shell_ht_topright = 14, Shell_ht_bottom = 15, Shell_ht_bottomleft = 16, Shell_ht_bottomright = 17 };
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
	p->aw = w; p->ah = h + p->frame_h;   /* laid out at a new size: that is the window's size now */
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
		GdkModifierType l_mods = gtk_event_controller_get_current_event_state(GTK_EVENT_CONTROLLER(g));
		int l_code = shell_panel_press_code(l_slot, shell_panel_px(l_slot, x), shell_panel_px(l_slot, y), (l_mods & GDK_SHIFT_MASK) ? 1 : 0);
		if (l_code && shell_panel_begin_grip(l_slot, GTK_GESTURE(g), l_code, x, y)) return;
	}
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
	GtkWidget *l_gone;
	gpointer d;
	shell_app();
	for (i = 0; i < SHELL_PANELS && l_slot < 0; i++) if (!s_panel[i].window) l_slot = i;
	if (l_slot < 0 || l_w <= 0 || l_h <= 0 || g_thread_self() != s_pump_thread) return -1;
	p = &s_panel[l_slot];
	l_gone = p->gone;
	memset(p, 0, sizeof *p);
	p->fill = 0xFFFFFF; p->framed = l_framed; p->document = l_document; p->alpha = 255;
	p->aw = l_w; p->ah = l_h;
	d = GINT_TO_POINTER(l_slot + 1);
	k = shell_scale();
	p->window = gtk_window_new();
	gtk_window_set_title(GTK_WINDOW(p->window), l_title ? (const char *)l_title : "");
	gtk_window_set_default_size(GTK_WINDOW(p->window), l_w / k, l_h / k);
	gtk_window_set_decorated(GTK_WINDOW(p->window), l_framed ? TRUE : FALSE);
	if (l_gone) g_object_unref(l_gone);   /* the new window has its own address now */
	if (l_framed) {
		/* a title bar of our own, so its height is known before the window is shown: the
		   client is the asked size less the caption, as on Windows */
		GtkWidget *l_bar = gtk_header_bar_new();
		int l_min = 0, l_nat = 0;
		gtk_window_set_titlebar(GTK_WINDOW(p->window), l_bar);
		gtk_widget_measure(l_bar, GTK_ORIENTATION_VERTICAL, -1, &l_min, &l_nat, NULL, NULL);
		p->frame_h = (l_nat > 0 ? l_nat : 37) * k;
		if (p->frame_h >= l_h) p->frame_h = 0;
	}
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
	g_signal_connect(p->window, "destroy", G_CALLBACK(shell_panel_on_destroyed), d);
	g_signal_connect(p->window, "notify::is-active", G_CALLBACK(shell_panel_on_active), d);
	/* a backing image from the start, at the asked size, so the program can draw before the
	   compositor has shown the window */
	p->backing = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, l_w, l_h - p->frame_h);
	return l_slot;
}

int shell_panel_open_framed_as(int l_x, int l_y, int l_w, int l_h, const void *l_title, int l_document)
{
	int l_slot = shell_panel_make(l_w, l_h, l_title, 1, l_document ? 1 : 0);
	if (l_slot >= 0) { s_panel[l_slot].ax = l_x; s_panel[l_slot].ay = l_y; }
	return l_slot;
}
int shell_panel_open_framed(int l_x, int l_y, int l_w, int l_h, const void *l_title) { return shell_panel_open_framed_as(l_x, l_y, l_w, l_h, l_title, 0); }
int shell_panel_open(int l_x, int l_y, int l_w, int l_h)
{
	int l_slot = shell_panel_make(l_w, l_h, NULL, 0, 0);
	if (l_slot >= 0) { s_panel[l_slot].ax = l_x; s_panel[l_slot].ay = l_y; }
	return l_slot;
}
void shell_panel_place(int l_slot, int l_x, int l_y, int l_w, int l_h)
{
	int k;
	if (!shell_panel_ok(l_slot) || l_w <= 0 || l_h <= 0) return;
	s_panel[l_slot].ax = l_x; s_panel[l_slot].ay = l_y; s_panel[l_slot].aw = l_w; s_panel[l_slot].ah = l_h;
	k = shell_panel_scale(l_slot);
	gtk_window_set_default_size(GTK_WINDOW(s_panel[l_slot].window), l_w / k, l_h / k);
	if (!gtk_widget_get_mapped(s_panel[l_slot].window)) {
		/* not on screen, so no layout will follow: the client takes the new size now and says
		   so (48), as Windows' WM_SIZE does for a hidden window */
		ShellPanel *p = &s_panel[l_slot];
		int cw = l_w, ch = l_h - p->frame_h;
		if (ch > 0 && (!p->backing || cairo_image_surface_get_width(p->backing) != cw || cairo_image_surface_get_height(p->backing) != ch)) {
			cairo_surface_t *l_new = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, cw, ch);
			cairo_t *cr = cairo_create(l_new);
			cairo_set_source_rgb(cr, ((p->fill >> 16) & 0xFF) / 255.0, ((p->fill >> 8) & 0xFF) / 255.0, (p->fill & 0xFF) / 255.0);
			cairo_paint(cr);
			if (p->backing) { cairo_set_source_surface(cr, p->backing, 0, 0); cairo_paint(cr); cairo_surface_destroy(p->backing); }
			cairo_destroy(cr);
			p->backing = l_new;
			if (!shell_coalesce_slot(48, cw, ch, l_slot)) shell_push(48, cw, ch, l_slot);
		}
	}
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
	if (p->gone) g_object_unref(p->gone);
	p->gone = g_object_ref(w);
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
/* Wayland tells no window's place: the rectangle is the place last asked for, at the size the
   program last asked for until the window has been laid out at another. */
void shell_panel_rect(int l_slot, int *l_x, int *l_y, int *l_w, int *l_h)
{
	if (!shell_panel_ok(l_slot) || !s_panel[l_slot].backing) return;
	*l_x = s_panel[l_slot].ax; *l_y = s_panel[l_slot].ay;
	*l_w = s_panel[l_slot].aw; *l_h = s_panel[l_slot].ah;
	return;   /* GTK 4 resizes a shown window only by the user's hand, which updates aw, ah */
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

/* ------------------------------------------------------------------ panel grips */

void shell_panel_set_draggable(int l_slot, int l_on) { if (shell_panel_ok(l_slot)) s_panel[l_slot].drag = l_on ? 1 : 0; }
void shell_panel_set_press_drag(int l_slot, int l_on) { if (shell_panel_ok(l_slot)) s_panel[l_slot].press_drag = l_on ? 1 : 0; }
void shell_panel_set_axis(int l_slot, int l_axis) { if (shell_panel_ok(l_slot)) s_panel[l_slot].axis = (l_axis >= 0 && l_axis <= 2) ? l_axis : 0; }
void shell_panel_set_side_grip(int l_slot, int l_on) { if (shell_panel_ok(l_slot)) s_panel[l_slot].side_grip = l_on ? 1 : 0; }
void shell_panel_set_bottom_grip(int l_slot, int l_on) { if (shell_panel_ok(l_slot)) s_panel[l_slot].bottom_grip = l_on ? 1 : 0; }
void shell_panel_set_resizable(int l_slot, int l_grip, int l_min_w, int l_min_h)
{
	ShellPanel *p;
	int k;
	if (!shell_panel_ok(l_slot)) return;
	p = &s_panel[l_slot];
	p->grip = l_grip > 0 ? l_grip : 0;
	p->minw = l_min_w > 0 ? l_min_w : 0;
	p->minh = l_min_h > 0 ? l_min_h : 0;
	k = shell_panel_scale(l_slot);
	gtk_widget_set_size_request(p->area, p->minw ? p->minw / k : -1, p->minh ? p->minh / k : -1);
}
static void shell_panel_wh(int l_slot, int *w, int *h)
{
	*w = s_panel[l_slot].backing ? cairo_image_surface_get_width(s_panel[l_slot].backing) : s_panel[l_slot].aw;
	*h = s_panel[l_slot].backing ? cairo_image_surface_get_height(s_panel[l_slot].backing) : s_panel[l_slot].ah;
}
/* What a Shift+press at client point (x, y) does: a move (caption) or the resize grip there. */
int shell_panel_grip_code(int l_slot, int l_x, int l_y)
{
	int g, w, h, l_left, l_right, l_top, l_bottom;
	if (!shell_panel_ok(l_slot) || s_panel[l_slot].grip <= 0) return Shell_ht_caption;
	g = s_panel[l_slot].grip;
	shell_panel_wh(l_slot, &w, &h);
	l_left = l_x < g; l_right = l_x >= w - g; l_top = l_y < g; l_bottom = l_y >= h - g;
	if (l_top && l_left) return Shell_ht_topleft;
	if (l_top && l_right) return Shell_ht_topright;
	if (l_bottom && l_left) return Shell_ht_bottomleft;
	if (l_bottom && l_right) return Shell_ht_bottomright;
	if (l_left) return Shell_ht_left;
	if (l_right) return Shell_ht_right;
	if (l_top) return Shell_ht_top;
	if (l_bottom) return Shell_ht_bottom;
	return Shell_ht_caption;
}
/* What a press at client point (x, y) does, as Windows' shell_panel_press_code: 0 for the
   program (event 41), or a move or resize the shell carries out. */
int shell_panel_press_code(int l_slot, int l_x, int l_y, int l_shift)
{
	ShellPanel *p;
	int w, h;
	if (!shell_panel_ok(l_slot)) return 0;
	p = &s_panel[l_slot];
	if (p->drag && l_shift) return shell_panel_grip_code(l_slot, l_x, l_y);
	if (p->press_drag) return Shell_ht_caption;
	shell_panel_wh(l_slot, &w, &h);
	if (p->side_grip && p->grip > 0) {
		if (l_x < p->grip) return Shell_ht_left;
		if (l_x >= w - p->grip) return Shell_ht_right;
	}
	if (p->bottom_grip && p->grip > 0 && l_y >= h - p->grip) return Shell_ht_bottom;
	return 0;
}
/* Hand a move or resize to the compositor, as Windows' modal size-move loop does. Wayland moves
   the window itself and tells nobody where it went, so a move cannot keep to one axis there
   and reports no 47 or 49. */
static int shell_panel_begin_grip(int l_slot, GtkGesture *g, int l_code, double x, double y)
{
	GtkNative *n = gtk_widget_get_native(s_panel[l_slot].area);
	GdkSurface *s = n ? gtk_native_get_surface(n) : NULL;
	GdkDevice *dev = gtk_gesture_get_device(g);
	guint32 l_time = gtk_event_controller_get_current_event_time(GTK_EVENT_CONTROLLER(g));
	double sx = x, sy = y;
	GdkSurfaceEdge l_edge;
	if (!s || !GDK_IS_TOPLEVEL(s) || !dev) return 0;
	{
		graphene_point_t a = GRAPHENE_POINT_INIT((float) x, (float) y), b;
		if (gtk_widget_compute_point(s_panel[l_slot].area, GTK_WIDGET(n), &a, &b)) { sx = b.x; sy = b.y; }
	}
	gtk_gesture_set_state(g, GTK_EVENT_SEQUENCE_CLAIMED);
	if (l_code == Shell_ht_caption) {
		gdk_toplevel_begin_move(GDK_TOPLEVEL(s), dev, GDK_BUTTON_PRIMARY, sx, sy, l_time);
		return 1;
	}
	switch (l_code) {
		case Shell_ht_left: l_edge = GDK_SURFACE_EDGE_WEST; break;
		case Shell_ht_right: l_edge = GDK_SURFACE_EDGE_EAST; break;
		case Shell_ht_top: l_edge = GDK_SURFACE_EDGE_NORTH; break;
		case Shell_ht_bottom: l_edge = GDK_SURFACE_EDGE_SOUTH; break;
		case Shell_ht_topleft: l_edge = GDK_SURFACE_EDGE_NORTH_WEST; break;
		case Shell_ht_topright: l_edge = GDK_SURFACE_EDGE_NORTH_EAST; break;
		case Shell_ht_bottomleft: l_edge = GDK_SURFACE_EDGE_SOUTH_WEST; break;
		default: l_edge = GDK_SURFACE_EDGE_SOUTH_EAST; break;
	}
	gdk_toplevel_begin_resize(GDK_TOPLEVEL(s), l_edge, dev, GDK_BUTTON_PRIMARY, sx, sy, l_time);
	return 1;
}
/* Where a move by (dx, dy) would put the panel, kept to its axis (the test door to a move);
   reported as 49, as Windows' WM_MOVING is. */
void shell_panel_try_move(int l_slot, int l_dx, int l_dy, int *l_x, int *l_y)
{
	int l_left, l_top;
	if (!shell_panel_ok(l_slot)) return;
	if (s_panel[l_slot].axis == 1) l_dy = 0;
	if (s_panel[l_slot].axis == 2) l_dx = 0;
	l_left = s_panel[l_slot].ax + l_dx; l_top = s_panel[l_slot].ay + l_dy;
	if (l_x) *l_x = l_left;
	if (l_y) *l_y = l_top;
	if (!shell_coalesce_slot(49, l_left, l_top, l_slot)) shell_push(49, l_left, l_top, l_slot);
}
/* The window went without `shell_panel_close' (its owner's destruction, or the test door): the
   slot is free again. */
static void shell_panel_on_destroyed(GtkWidget *w, gpointer d)
{
	int l_slot = shell_slot_of(d);
	ShellPanel *p;
	if (l_slot < 0 || l_slot >= SHELL_PANELS || s_panel[l_slot].window != w) return;
	p = &s_panel[l_slot];
	if (p->gone) g_object_unref(p->gone);
	p->gone = g_object_ref(w);
	p->window = NULL; p->area = NULL;
	if (p->backing) { cairo_surface_destroy(p->backing); p->backing = NULL; }
}
void shell_panel_destroy_behind(int l_slot) { if (shell_panel_ok(l_slot)) gtk_window_destroy(GTK_WINDOW(s_panel[l_slot].window)); }

/* Windows messages, as the panel's window procedure takes them (the test door): what a framed
   panel's keys, characters, close box, activation, double clicks and leaves queue. */
int shell_panel_send(int l_slot, int l_msg, int l_w, int l_l)
{
	int x = (short)(l_l & 0xFFFF), y = (short)((l_l >> 16) & 0xFFFF), l_framed;
	if (!shell_panel_ok(l_slot)) return 0;
	l_framed = s_panel[l_slot].framed;
	if (l_msg == 0x0021) return l_framed ? 1 : 3;   /* WM_MOUSEACTIVATE: MA_ACTIVATE, MA_NOACTIVATE */
	switch (l_msg) {
		case 0x0100: if (l_framed && shell_keydown_is_ours(l_w, shell_control_down(), shell_alt_down())) shell_push(60, l_w, 0, l_slot); break;
		case 0x0104: if (l_framed && shell_syskey_is_ours(l_w)) shell_push(60, l_w, 0, l_slot); break;
		case 0x0102: if (l_framed) shell_push(61, l_w, 0, l_slot); break;
		case 0x0010: if (l_framed) shell_push(62, 0, 0, l_slot); break;
		case 0x0006: if (l_framed) shell_push(63, (l_w & 0xFFFF) ? 1 : 0, 0, l_slot); break;
		case 0x0203: shell_push(64, x, y, l_slot); break;
		case 0x02A3: shell_push(65, 0, 0, l_slot); break;
		case 0x0201: shell_push(41, x, y, l_slot); break;
		case 0x0202: shell_push(42, x, y, l_slot); break;
		case 0x0200: shell_push(43, x, y, l_slot); break;
		case 0x0204: shell_push(46, x, y, l_slot); break;
		case 0x020A: shell_push(45, (short)((l_w >> 16) & 0xFFFF), 0, l_slot); break;
		default: return 0;
	}
	return 0;
}

/* ------------------------------------------------------------------ the status strip */

/* A small undecorated window of its own, drawn from a backing image (21 press, 23 expose). A
   press moves it through the compositor; Wayland tells nobody where it went, so 22 is not
   reported there. */
static GtkWidget *s_strip = NULL, *s_strip_area = NULL;
static cairo_surface_t *s_strip_backing = NULL;
static void shell_strip_draw(GtkDrawingArea *a, cairo_t *cr, int w, int h, gpointer d)
{
	int k = gtk_widget_get_scale_factor(GTK_WIDGET(a));
	(void)w; (void)h; (void)d;
	if (!s_strip_backing) return;
	cairo_scale(cr, 1.0 / k, 1.0 / k);
	cairo_set_source_surface(cr, s_strip_backing, 0, 0);
	cairo_paint(cr);
}
static void shell_strip_press(GtkGestureClick *g, int n, double x, double y, gpointer d)
{
	GtkNative *nat = gtk_widget_get_native(s_strip_area);
	GdkSurface *s = nat ? gtk_native_get_surface(nat) : NULL;
	int k = gtk_widget_get_scale_factor(s_strip_area);
	(void)n; (void)d;
	shell_push(21, (int)(x * k), (int)(y * k), 0);
	if (s && GDK_IS_TOPLEVEL(s) && gtk_gesture_get_device(GTK_GESTURE(g)))
		gdk_toplevel_begin_move(GDK_TOPLEVEL(s), gtk_gesture_get_device(GTK_GESTURE(g)), GDK_BUTTON_PRIMARY, x, y,
			gtk_event_controller_get_current_event_time(GTK_EVENT_CONTROLLER(g)));
}
void *shell_show_strip(int x, int y, int w, int h)
{
	int k;
	(void)x; (void)y;
	if (w <= 0 || h <= 0 || g_thread_self() != s_pump_thread) return NULL;
	shell_app();
	k = shell_scale();
	if (!s_strip) {
		GtkGesture *g;
		s_strip = gtk_window_new();
		gtk_window_set_decorated(GTK_WINDOW(s_strip), FALSE);
		s_strip_area = gtk_drawing_area_new();
		gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(s_strip_area), shell_strip_draw, NULL, NULL);
		g = gtk_gesture_click_new();
		g_signal_connect(g, "pressed", G_CALLBACK(shell_strip_press), NULL);
		gtk_widget_add_controller(s_strip_area, GTK_EVENT_CONTROLLER(g));
		gtk_window_set_child(GTK_WINDOW(s_strip), s_strip_area);
		g_object_add_weak_pointer(G_OBJECT(s_strip), (gpointer *)&s_strip);
	}
	if (!s_strip_backing || cairo_image_surface_get_width(s_strip_backing) != w || cairo_image_surface_get_height(s_strip_backing) != h) {
		if (s_strip_backing) cairo_surface_destroy(s_strip_backing);
		s_strip_backing = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
	}
	gtk_window_set_default_size(GTK_WINDOW(s_strip), w / k > 0 ? w / k : 1, h / k > 0 ? h / k : 1);
	gtk_widget_set_visible(s_strip, TRUE);
	shell_push(23, 0, 0, 0);
	return s_strip;
}
void shell_hide_strip(void) { if (s_strip) gtk_widget_set_visible(s_strip, FALSE); }
void *shell_strip_dc(void) { return s_strip ? (void *)s_strip_backing : NULL; }
void shell_strip_release(void *dc) { if (dc && s_strip_area) gtk_widget_queue_draw(s_strip_area); }

/* ------------------------------------------------------------------ text in, drags out (1.40.0) */

#define SHELL_TEXT_CAP 32768
static gunichar2 s_drop_text[SHELL_TEXT_CAP];
static int s_drop_text_len = 0;
static void shell_keep_text(const char *a_text)
{
	glong n = 0;
	gunichar2 *u = g_utf8_to_utf16(a_text ? a_text : "", -1, NULL, &n, NULL);
	if (!u) { s_drop_text_len = 0; return; }
	if (n > SHELL_TEXT_CAP - 1) n = SHELL_TEXT_CAP - 1;
	memcpy(s_drop_text, u, (size_t)n * sizeof(gunichar2));
	s_drop_text[n] = 0;
	s_drop_text_len = (int)n;
	g_free(u);
}
/* The text dropped last, UTF-16 into `buf'; taking it empties the store. */
int shell_dropped_text(void *buf, int cap)
{
	int n = s_drop_text_len;
	if (cap < 1) return 0;
	if (n >= cap) n = cap - 1;
	memcpy(buf, s_drop_text, (size_t)n * sizeof(gunichar2));
	((gunichar2 *)buf)[n] = 0;
	s_drop_text_len = 0;
	return n;
}
void shell_panel_set_accepts_text(int l_slot, int l_on)
{
	if (l_slot < 0) s_main_takes_text = l_on ? 1 : 0;
	else if (shell_panel_ok(l_slot)) s_panel[l_slot].takes_text = l_on ? 1 : 0;
}
int shell_panel_accepts_text(int l_slot)
{
	if (l_slot < 0) return s_main_takes_text;
	return shell_panel_ok(l_slot) && s_panel[l_slot].takes_text ? 1 : 0;
}
static int shell_takes_files_at(int l_slot) { return l_slot < 0 ? 1 : shell_panel_accepts_files(l_slot); }
/* A drag is welcome when it carries files and the window takes files, or (no files) text and
   it takes text. A drag carrying files is files only. */
static gboolean shell_drop_accept(GtkDropTarget *t, GdkDrop *drop, gpointer d)
{
	int l_slot = GPOINTER_TO_INT(d) - 1;
	GdkContentFormats *f = gdk_drop_get_formats(drop);
	(void)t;
	if (gdk_content_formats_contain_gtype(f, GDK_TYPE_FILE_LIST)) return shell_takes_files_at(l_slot);
	return gdk_content_formats_contain_gtype(f, G_TYPE_STRING) && shell_panel_accepts_text(l_slot);
}
/* The test door: what a drag of `l_text' and `l_paths' (UTF-8, paths one per line) brings
   to client point (x, y), as another program's drag arrives. */
void shell_panel_try_drag_in(int l_slot, int l_x, int l_y, const void *l_text, const void *l_paths)
{
	const char *l_t = l_text ? (const char *)l_text : "", *l_p = l_paths ? (const char *)l_paths : "";
	int n;
	if (l_slot >= 0 && !shell_panel_ok(l_slot)) return;
	if (*l_p) {
		if (!shell_takes_files_at(l_slot)) return;
		n = shell_keep_drops(l_p);
		if (l_slot < 0) shell_push(18, l_x, l_y, n); else shell_push(50, l_x, l_y, l_slot);
	} else if (*l_t && shell_panel_accepts_text(l_slot)) {
		shell_keep_text(l_t);
		if (l_slot < 0) shell_push(68, l_x, l_y, 0); else shell_push(67, l_x, l_y, l_slot);
	}
}

typedef struct { int done, taken; } ShellDragOut;
static void shell_drag_out_dropped(GdkDrag *g, gpointer d) { (void)g; ((ShellDragOut *)d)->taken = 1; }
static void shell_drag_out_finished(GdkDrag *g, gpointer d) { (void)g; ((ShellDragOut *)d)->done = 1; }
static void shell_drag_out_canceled(GdkDrag *g, GdkDragCancelReason r, gpointer d) { (void)g; (void)r; ((ShellDragOut *)d)->done = 1; }
/* Drag `l_text' and the paths (UTF-8, one per line) out with the pointer, waiting until the drag
   ends, as Windows' DoDragDrop does: 1 another program took it, 0 refused, -1 it landed on one
   of our own windows (which pushed its own 50 or 67). */
int shell_drag_out(const void *l_text, const void *l_paths)
{
	const char *l_t = l_text ? (const char *)l_text : "", *l_p = l_paths ? (const char *)l_paths : "";
	GtkWidget *w = s_window;
	GtkNative *n;
	GdkSurface *s;
	GdkSeat *seat;
	GdkDevice *dev;
	GdkContentProvider *parts[2];
	GdkContentProvider *content;
	GdkDrag *g;
	ShellDragOut st = {0, 0};
	int i, k = 0;
	if (!w) for (i = 0; i < SHELL_PANELS && !w; i++) if (s_panel[i].window) w = s_panel[i].window;
	if (!w || s_dragging_out || (!*l_t && !*l_p)) return 0;
	n = GTK_NATIVE(w);
	s = gtk_native_get_surface(n);
	seat = gdk_display_get_default_seat(gtk_widget_get_display(w));
	dev = seat ? gdk_seat_get_pointer(seat) : NULL;
	if (!s || !dev) return 0;
	if (*l_p) {
		GSList *files = NULL;
		char **lines = g_strsplit(l_p, "\n", -1), **it;
		for (it = lines; *it; it++) if (**it) files = g_slist_append(files, g_file_new_for_path(*it));
		g_strfreev(lines);
		if (files) {
			parts[k++] = gdk_content_provider_new_typed(GDK_TYPE_FILE_LIST, files);
			g_slist_free_full(files, g_object_unref);
		}
	}
	if (*l_t) parts[k++] = gdk_content_provider_new_typed(G_TYPE_STRING, l_t);
	if (k == 0) return 0;
	content = k == 1 ? parts[0] : gdk_content_provider_new_union(parts, 2);
	s_dragging_out = 1; s_drag_landed_here = 0;
	g = gdk_drag_begin(s, dev, content, GDK_ACTION_COPY, 0, 0);
	g_object_unref(content);
	if (!g) { s_dragging_out = 0; return 0; }
	g_signal_connect(g, "drop-performed", G_CALLBACK(shell_drag_out_dropped), &st);
	g_signal_connect(g, "dnd-finished", G_CALLBACK(shell_drag_out_finished), &st);
	g_signal_connect(g, "cancel", G_CALLBACK(shell_drag_out_canceled), &st);
	while (!st.done) g_main_context_iteration(NULL, TRUE);
	g_signal_handlers_disconnect_matched(g, G_SIGNAL_MATCH_DATA, 0, 0, NULL, NULL, &st);
	g_object_unref(g);
	s_dragging_out = 0;
	if (!st.taken) return 0;
	return s_drag_landed_here ? -1 : 1;
}

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
	if (G_VALUE_HOLDS(v, G_TYPE_STRING)) {
		if (!shell_panel_accepts_text(l_slot)) return FALSE;   /* slot -1: the main window */
		shell_keep_text(g_value_get_string(v));
		if (l_slot < 0) shell_push(68, shell_px(x), shell_px(y), 0);
		else shell_push(67, shell_panel_px(l_slot, x), shell_panel_px(l_slot, y), l_slot);
		if (s_dragging_out) s_drag_landed_here = 1;
		return TRUE;
	}
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
	if (s_dragging_out) s_drag_landed_here = 1;
	return TRUE;
}
static void shell_take_drops(GtkWidget *a_widget, gpointer d)
{
	GtkDropTarget *t = gtk_drop_target_new(G_TYPE_INVALID, GDK_ACTION_COPY);
	GType l_types[2];
	l_types[0] = GDK_TYPE_FILE_LIST; l_types[1] = G_TYPE_STRING;   /* files first: a drag carrying both is files */
	gtk_drop_target_set_gtypes(t, l_types, 2);
	g_signal_connect(t, "accept", G_CALLBACK(shell_drop_accept), d);
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

/* ---------------- Wayland: the xdg-desktop-portal (stage 3; until then, not available) */
static int shell_portal_hotkey_register(int l_id, int l_mods, int l_vk) { (void)l_id; (void)l_mods; (void)l_vk; return 0; }
static void shell_portal_hotkey_unregister(int l_id) { (void)l_id; }
static int shell_portal_grab_screen(int x, int y, int w, int h, void *bits, int stride) { (void)x; (void)y; (void)w; (void)h; (void)bits; (void)stride; return 0; }

/* ------------------------------------------------------------------ X11 and Wayland (Larry 2026-11-10: both)

   On an X11 session (or XWayland, GDK_BACKEND=x11) the desktop is reached directly: hotkeys by
   XGrabKey on the root window, input by XTest, the screen by XGetImage. On Wayland these go
   through the xdg-desktop-portal (asking the user), below; where neither exists the answer is
   "not available": 0, and for input OS error 50 (ERROR_NOT_SUPPORTED). */
#ifdef GDK_WINDOWING_X11
#include <gdk/x11/gdkx.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#endif

static Display *shell_x11(void)
{
#ifdef GDK_WINDOWING_X11
	GdkDisplay *d;
	shell_app();
	d = gdk_display_get_default();
	if (d && GDK_IS_X11_DISPLAY(d)) return gdk_x11_display_get_xdisplay(d);
#endif
	return NULL;
}

/* Is (x, y) on the virtual desktop? Any session. */
int shell_input_on_desktop(int x, int y)
{
	int dx, dy, dw, dh;
	shell_virtual_desktop(&dx, &dy, &dw, &dh);
	return x >= dx && y >= dy && x < dx + dw && y < dy + dh ? 1 : 0;
}

#ifdef GDK_WINDOWING_X11
/* A Windows virtual key as an X keysym (0: none). */
static KeySym shell_keysym_of_vk(int vk)
{
	if ((vk >= 'A' && vk <= 'Z')) return XK_a + (vk - 'A');
	if (vk >= '0' && vk <= '9') return XK_0 + (vk - '0');
	if (vk >= 0x70 && vk <= 0x87) return XK_F1 + (vk - 0x70);   /* F1 - F24 */
	if (vk >= 0x60 && vk <= 0x69) return XK_KP_0 + (vk - 0x60);
	switch (vk) {
		case 0x25: return XK_Left; case 0x26: return XK_Up; case 0x27: return XK_Right; case 0x28: return XK_Down;
		case 0x24: return XK_Home; case 0x23: return XK_End; case 0x21: return XK_Page_Up; case 0x22: return XK_Page_Down;
		case 0x2E: return XK_Delete; case 0x2D: return XK_Insert; case 0x08: return XK_BackSpace; case 0x0D: return XK_Return;
		case 0x09: return XK_Tab; case 0x1B: return XK_Escape; case 0x20: return XK_space;
		case 0x10: case 0xA0: return XK_Shift_L; case 0xA1: return XK_Shift_R;
		case 0x11: case 0xA2: return XK_Control_L; case 0xA3: return XK_Control_R;
		case 0x12: case 0xA4: return XK_Alt_L; case 0xA5: return XK_Alt_R;
		case 0x5B: return XK_Super_L; case 0x5C: return XK_Super_R;
		case 0xBB: return XK_equal; case 0xBD: return XK_minus; case 0x6B: return XK_KP_Add; case 0x6D: return XK_KP_Subtract;
		case 0xBA: return XK_semicolon; case 0xBF: return XK_slash; case 0xC0: return XK_grave; case 0xDB: return XK_bracketleft;
		case 0xDC: return XK_backslash; case 0xDD: return XK_bracketright; case 0xDE: return XK_apostrophe;
		case 0xBC: return XK_comma; case 0xBE: return XK_period;
	}
	return 0;
}
#endif

#ifdef GDK_WINDOWING_X11
/* A key code no keysym is mapped to (0: none free). */
static int shell_x11_spare_keycode(Display *d)
{
	int l_min, l_max, l_per, k, l_spare = 0;
	KeySym *l_map;
	XDisplayKeycodes(d, &l_min, &l_max);
	l_map = XGetKeyboardMapping(d, (KeyCode)l_min, l_max - l_min + 1, &l_per);
	if (!l_map) return 0;
	for (k = l_max; k >= l_min && !l_spare; k--) {
		int j, l_empty = 1;
		for (j = 0; j < l_per; j++) if (l_map[(k - l_min) * l_per + j] != NoSymbol) l_empty = 0;
		if (l_empty) l_spare = k;
	}
	XFree(l_map);
	return l_spare;
}
/* Give back a spare key code we mapped (0: nothing to give back). */
static void shell_x11_unmap(Display *d, int a_code)
{
	KeySym l_none = NoSymbol;
	if (!d || !a_code) return;
	XChangeKeyboardMapping(d, a_code, 1, &l_none, 1);
	XSync(d, False);
}
#endif

/* ---------------- hotkeys */

#define SHELL_HOTKEYS 32
typedef struct { int used, id, vk, mods, code, mapped; unsigned int xmods; } ShellHotkey;   /* mapped: a spare key code we gave the keysym */
static ShellHotkey s_hotkey[SHELL_HOTKEYS];
static int s_hotkey_hooked = 0;

#ifdef GDK_WINDOWING_X11
static const unsigned int s_lock_variants[4] = {0, LockMask, Mod2Mask, LockMask | Mod2Mask};   /* Caps and Num Lock */
static gboolean shell_on_xevent(GdkX11Display *d, gpointer a_event, gpointer data)
{
	XEvent *e = a_event;
	int i;
	(void)d; (void)data;
	if (e->type != KeyPress) return FALSE;
	for (i = 0; i < SHELL_HOTKEYS; i++)
		if (s_hotkey[i].used && s_hotkey[i].code == (int)e->xkey.keycode
				&& (e->xkey.state & (ShiftMask | ControlMask | Mod1Mask | Mod4Mask)) == s_hotkey[i].xmods) {
			shell_push(51, s_hotkey[i].id, s_hotkey[i].vk, s_hotkey[i].mods);
			return TRUE;
		}
	return FALSE;
}
#endif

/* Hold a system-wide chord (mods: 1 Alt, 2 Ctrl, 4 Shift, 8 Win, as RegisterHotKey); 1 when
   held, 0 when refused: another holder (here or another program), or not available. */
int shell_hotkey_register(int l_id, int l_mods, int l_vk)
{
#ifdef GDK_WINDOWING_X11
	Display *x = shell_x11();
	KeySym ks;
	int i, l_free = -1, l_code, l_failed, l_mapped;
	unsigned int m;
	Window root;
	if (!x) return shell_portal_hotkey_register(l_id, l_mods, l_vk);
	ks = shell_keysym_of_vk(l_vk);
	if (!ks) return 0;
	shell_hotkey_unregister(l_id);
	l_code = XKeysymToKeycode(x, ks);
	l_mapped = 0;
	if (!l_code) {
		/* the keyboard map has no key for it (F13 - F24 often): give it a spare key code while
		   held, as Windows registers a key no keyboard has */
		l_code = shell_x11_spare_keycode(x);
		if (!l_code) return 0;
		XChangeKeyboardMapping(x, l_code, 1, &ks, 1);
		XSync(x, False);
		l_mapped = 1;
	}
	for (i = 0; i < SHELL_HOTKEYS; i++)
		if (s_hotkey[i].used && s_hotkey[i].vk == l_vk && s_hotkey[i].mods == l_mods) { shell_x11_unmap(x, l_mapped ? l_code : 0); return 0; }   /* held here already */
	for (i = 0; i < SHELL_HOTKEYS && l_free < 0; i++) if (!s_hotkey[i].used) l_free = i;
	if (l_free < 0) { shell_x11_unmap(x, l_mapped ? l_code : 0); return 0; }
	m = ((l_mods & 1) ? Mod1Mask : 0) | ((l_mods & 2) ? ControlMask : 0) | ((l_mods & 4) ? ShiftMask : 0) | ((l_mods & 8) ? Mod4Mask : 0);
	root = DefaultRootWindow(x);
	gdk_x11_display_error_trap_push(gdk_display_get_default());
	for (i = 0; i < 4; i++) XGrabKey(x, l_code, m | s_lock_variants[i], root, False, GrabModeAsync, GrabModeAsync);
	XSync(x, False);
	l_failed = gdk_x11_display_error_trap_pop(gdk_display_get_default());
	if (l_failed) {   /* another program holds it (BadAccess): let go of what we took */
		gdk_x11_display_error_trap_push(gdk_display_get_default());
		for (i = 0; i < 4; i++) XUngrabKey(x, l_code, m | s_lock_variants[i], root);
		XSync(x, False);
		gdk_x11_display_error_trap_pop_ignored(gdk_display_get_default());
		shell_x11_unmap(x, l_mapped ? l_code : 0);
		return 0;
	}
	if (!s_hotkey_hooked) {
		g_signal_connect(gdk_display_get_default(), "xevent", G_CALLBACK(shell_on_xevent), NULL);
		s_hotkey_hooked = 1;
	}
	s_hotkey[l_free].used = 1; s_hotkey[l_free].id = l_id; s_hotkey[l_free].vk = l_vk; s_hotkey[l_free].mods = l_mods;
	s_hotkey[l_free].code = l_code; s_hotkey[l_free].xmods = m; s_hotkey[l_free].mapped = l_mapped;
	return 1;
#else
	return shell_portal_hotkey_register(l_id, l_mods, l_vk);
#endif
}
void shell_hotkey_unregister(int l_id)
{
	int i;
#ifdef GDK_WINDOWING_X11
	Display *x = shell_x11();
	int j;
#endif
	for (i = 0; i < SHELL_HOTKEYS; i++)
		if (s_hotkey[i].used && s_hotkey[i].id == l_id) {
#ifdef GDK_WINDOWING_X11
			if (x && s_hotkey[i].code) {
				gdk_x11_display_error_trap_push(gdk_display_get_default());
				for (j = 0; j < 4; j++) XUngrabKey(x, s_hotkey[i].code, s_hotkey[i].xmods | s_lock_variants[j], DefaultRootWindow(x));
				XSync(x, False);
				gdk_x11_display_error_trap_pop_ignored(gdk_display_get_default());
				shell_x11_unmap(x, s_hotkey[i].mapped ? s_hotkey[i].code : 0);
			}
#endif
			s_hotkey[i].used = 0;
		}
	shell_portal_hotkey_unregister(l_id);
}
/* The test door: the chord pressed, as the system delivers it (event 51). */
void shell_hotkey_simulate(int l_id, int l_mods, int l_vk) { shell_push(51, l_id, l_vk, l_mods); }

/* ---------------- input synthesis */

static int s_input_error = 0;
int shell_input_last_error(void) { return s_input_error; }
int shell_input_type_units(const void *s)
{
	glong n = 0;
	gunichar2 *u;
	if (!s) return 0;
	u = g_utf8_to_utf16((const char *)s, -1, NULL, &n, NULL);
	g_free(u);
	return (int)n;
}
int shell_input_pointer(int *x, int *y)
{
#ifdef GDK_WINDOWING_X11
	Display *d = shell_x11();
	Window r, c;
	int rx, ry, wx, wy;
	unsigned int m;
	*x = 0; *y = 0;
	if (d && XQueryPointer(d, DefaultRootWindow(d), &r, &c, &rx, &ry, &wx, &wy, &m)) { *x = rx; *y = ry; return 1; }
#else
	*x = 0; *y = 0;
#endif
	return 0;   /* Wayland tells no program where the pointer is outside its own windows */
}
#ifdef GDK_WINDOWING_X11
static void shell_x11_key(Display *d, KeyCode k, int a_down) { XTestFakeKeyEvent(d, k, a_down ? True : False, CurrentTime); }
#endif
int shell_input_click(int x, int y, int restore_cursor, int restore_focus)
{
#ifdef GDK_WINDOWING_X11
	Display *d = shell_x11();
	int bx = 0, by = 0, l_revert;
	Window l_focus = None;
	s_input_error = 0;
	if (!d) { s_input_error = 50; return 0; }
	shell_input_pointer(&bx, &by);
	XGetInputFocus(d, &l_focus, &l_revert);
	XTestFakeMotionEvent(d, -1, x, y, CurrentTime);
	XTestFakeButtonEvent(d, 1, True, CurrentTime);
	XTestFakeButtonEvent(d, 1, False, CurrentTime);
	XSync(d, False);
	if (restore_cursor) { XTestFakeMotionEvent(d, -1, bx, by, CurrentTime); XSync(d, False); }
	if (restore_focus && l_focus != None && l_focus != PointerRoot) {
		g_usleep(120000);   /* let the click's activation land first, as on Windows */
		gdk_x11_display_error_trap_push(gdk_display_get_default());
		XSetInputFocus(d, l_focus, RevertToParent, CurrentTime);
		XSync(d, False);
		gdk_x11_display_error_trap_pop_ignored(gdk_display_get_default());
	}
	return 1;
#else
	(void)x; (void)y; (void)restore_cursor; (void)restore_focus;
	s_input_error = 50;
	return 0;
#endif
}
/* Type text, two events per UTF-16 unit as SendInput counts them. Each character goes through a
   spare key code mapped to its keysym for the moment, so any character types on any layout. */
int shell_input_type(const void *s)
{
#ifdef GDK_WINDOWING_X11
	Display *d = shell_x11();
	int l_spare = 0, l_sent = 0;
	const char *c;
	s_input_error = 0;
	if (!s) return 0;
	if (!d) { s_input_error = 50; return 0; }
	l_spare = shell_x11_spare_keycode(d);
	if (!l_spare) { s_input_error = 8; return 0; }
	for (c = (const char *)s; *c; c = g_utf8_next_char(c)) {
		gunichar u = g_utf8_get_char(c);
		KeySym ks = (KeySym)gdk_unicode_to_keyval(u);
		XChangeKeyboardMapping(d, l_spare, 1, &ks, 1);
		XSync(d, False);
		shell_x11_key(d, (KeyCode)l_spare, 1);
		shell_x11_key(d, (KeyCode)l_spare, 0);
		XSync(d, False);
		l_sent += u > 0xFFFF ? 4 : 2;
	}
	shell_x11_unmap(d, l_spare);
	return l_sent;
#else
	(void)s;
	s_input_error = 50;
	return 0;
#endif
}
/* A chord: the modifiers down, the key down and up, the modifiers up; answers the events sent. */
int shell_input_chord(int ctrl, int shift, int alt, int vk)
{
#ifdef GDK_WINDOWING_X11
	Display *d = shell_x11();
	KeySym ks = shell_keysym_of_vk(vk);
	KeyCode l_mods[3], l_key;
	int n = 0, i, l_sent = 0;
	s_input_error = 0;
	if (!d) { s_input_error = 50; return 0; }
	l_key = ks ? XKeysymToKeycode(d, ks) : 0;
	if (!l_key) { s_input_error = 87; return 0; }   /* ERROR_INVALID_PARAMETER */
	if (ctrl) l_mods[n++] = XKeysymToKeycode(d, XK_Control_L);
	if (shift) l_mods[n++] = XKeysymToKeycode(d, XK_Shift_L);
	if (alt) l_mods[n++] = XKeysymToKeycode(d, XK_Alt_L);
	for (i = 0; i < n; i++) { shell_x11_key(d, l_mods[i], 1); l_sent++; }
	shell_x11_key(d, l_key, 1); l_sent++;
	shell_x11_key(d, l_key, 0); l_sent++;
	for (i = n - 1; i >= 0; i--) { shell_x11_key(d, l_mods[i], 0); l_sent++; }
	XSync(d, False);
	return l_sent;
#else
	(void)ctrl; (void)shift; (void)alt; (void)vk;
	s_input_error = 50;
	return 0;
#endif
}

/* ---------------- the screen */

/* Copy the desktop rectangle into `bits' (BGRA rows of `stride' bytes, alpha forced opaque). */
int shell_grab_screen(int x, int y, int w, int h, void *bits, int stride)
{
#ifdef GDK_WINDOWING_X11
	Display *d = shell_x11();
	XImage *im;
	int r, c;
	if (!bits || w <= 0 || h <= 0 || stride < w * 4) return 0;
	if (!d) return shell_portal_grab_screen(x, y, w, h, bits, stride);
	gdk_x11_display_error_trap_push(gdk_display_get_default());
	im = XGetImage(d, DefaultRootWindow(d), x, y, (unsigned int)w, (unsigned int)h, AllPlanes, ZPixmap);
	gdk_x11_display_error_trap_pop_ignored(gdk_display_get_default());
	if (!im) return 0;
	for (r = 0; r < h; r++) {
		unsigned char *row = (unsigned char *)bits + (size_t)r * (size_t)stride;
		for (c = 0; c < w; c++) {
			unsigned long p = XGetPixel(im, c, r);
			unsigned int rr = (unsigned int)((p & im->red_mask) >> (__builtin_ctzl(im->red_mask)));
			unsigned int gg = (unsigned int)((p & im->green_mask) >> (__builtin_ctzl(im->green_mask)));
			unsigned int bb = (unsigned int)((p & im->blue_mask) >> (__builtin_ctzl(im->blue_mask)));
			row[c * 4] = (unsigned char)bb; row[c * 4 + 1] = (unsigned char)gg; row[c * 4 + 2] = (unsigned char)rr; row[c * 4 + 3] = 255;
		}
	}
	XDestroyImage(im);
	return 1;
#else
	return shell_portal_grab_screen(x, y, w, h, bits, stride);
#endif
}

/* Neither X11 nor Wayland can keep a window out of other programs' captures: not available,
   and the affinity says none. */
void shell_panel_set_capture_excluded(int l_slot, int l_on) { (void)l_slot; (void)l_on; }
int shell_panel_capture_affinity(int l_slot) { (void)l_slot; return 0; }

/* ------------------------------------------------------------------ appearance: the palette

   GTK 4 offers no system palette to read. The colors are Adwaita's for the light or dark style
   in force (GNOME's own, and GTK's default), and the high-contrast palette when that theme is
   on: what a GTK program's windows actually show. Indices are Windows' COLOR_* numbers. */
unsigned int shell_system_color(int l_index)
{
	int l_dark = shell_system_prefers_dark(), l_hc = shell_high_contrast_on();
	if (l_hc) {
		switch (l_index) {
			case 5: case 15: return l_dark ? 0x000000 : 0xFFFFFF;
			case 13: case 26: return l_dark ? 0x78AEED : 0x1C71D8;
			case 17: return l_dark ? 0xC0C0C0 : 0x404040;
			default: return l_dark ? 0xFFFFFF : 0x000000;
		}
	}
	switch (l_index) {
		case 5: return l_dark ? 0x1E1E1E : 0xFFFFFF;                 /* COLOR_WINDOW: a view */
		case 8: case 18: return l_dark ? 0xFFFFFF : 0x000000;        /* text */
		case 13: return 0x3584E4;                                    /* COLOR_HIGHLIGHT: the accent */
		case 14: return 0xFFFFFF;                                    /* COLOR_HIGHLIGHTTEXT */
		case 15: return l_dark ? 0x303030 : 0xFAFAFA;                /* COLOR_BTNFACE: window and headers */
		case 17: return l_dark ? 0x9A9A9A : 0x7E7E7E;                /* COLOR_GRAYTEXT */
		case 26: return l_dark ? 0x78AEED : 0x1C71D8;                /* COLOR_HOTLIGHT: links */
		case 1: case 2: case 3: case 4: case 10: case 11: case 12: case 16: case 20: case 21: case 22:
			return l_dark ? 0x242424 : 0xFAFAFA;                     /* frames, faces, shadows */
	}
	return l_dark ? 0xFFFFFF : 0x000000;
}
void shell_system_colors_changed(void) { shell_push(56, shell_high_contrast_on(), 0, 0); }

/* ------------------------------------------------------------------ icons

   GTK 4 names icons: the image's folder joins the icon theme's search path and its name (the
   file name less its extension) becomes every window's icon. */
static char *s_icon_name = NULL;
void shell_set_window_icon(const void *path)
{
	char *l_dir, *l_base, *l_dot;
	GtkIconTheme *l_theme;
	if (!path || !*(const char *)path) return;
	shell_app();
	l_theme = gtk_icon_theme_get_for_display(gdk_display_get_default());
	l_dir = g_path_get_dirname((const char *)path);
	l_base = g_path_get_basename((const char *)path);
	l_dot = strrchr(l_base, '.');
	if (l_dot) *l_dot = 0;
	gtk_icon_theme_add_search_path(l_theme, l_dir);
	gtk_window_set_default_icon_name(l_base);
	g_free(s_icon_name);
	s_icon_name = l_base;
	g_free(l_dir);
}
/* The application's icon, as a handle to compare (Void until one is set). */
void *shell_main_icon(void) { return s_icon_name; }
/* A document window shows the application's icon on its taskbar button, as on Windows. */
void *shell_panel_icon(int l_slot) { return shell_panel_ok(l_slot) && s_panel[l_slot].document ? shell_main_icon() : NULL; }

/* ------------------------------------------------------------------ the text menu

   Cut, Copy, Paste and Select All at the pointer, waiting for the choice as TrackPopupMenu
   does: 1 Cut, 2 Copy, 3 Paste, 4 Select All, 0 none. */
static int s_text_menu_choice = 0, s_text_menu_open = 0;
static void shell_text_menu_pick(GtkButton *b, gpointer d)
{
	s_text_menu_choice = GPOINTER_TO_INT(d);
	gtk_popover_popdown(GTK_POPOVER(g_object_get_data(G_OBJECT(b), "sg-popover")));
}
static void shell_text_menu_closed(GtkPopover *p, gpointer d) { (void)p; (void)d; s_text_menu_open = 0; }
int shell_text_menu(int can_cut, int can_copy, int can_paste, int can_select)
{
	static const char *l_titles[4] = {"Cut", "Copy", "Paste", "Select All"};
	int l_on[4];
	GtkWidget *l_parent = s_area, *l_pop, *l_box;
	GdkRectangle r;
	int i;
	l_on[0] = can_cut; l_on[1] = can_copy; l_on[2] = can_paste; l_on[3] = can_select;
	if (!l_parent) for (i = 0; i < SHELL_PANELS && !l_parent; i++) if (s_panel[i].window && gtk_window_is_active(GTK_WINDOW(s_panel[i].window))) l_parent = s_panel[i].area;
	if (!l_parent || !gtk_widget_get_mapped(l_parent)) return 0;
	l_pop = gtk_popover_new();
	l_box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
	for (i = 0; i < 4; i++) {
		GtkWidget *b = gtk_button_new_with_label(l_titles[i]);
		gtk_button_set_has_frame(GTK_BUTTON(b), FALSE);
		gtk_widget_set_sensitive(b, l_on[i] != 0);
		g_object_set_data(G_OBJECT(b), "sg-popover", l_pop);
		g_signal_connect(b, "clicked", G_CALLBACK(shell_text_menu_pick), GINT_TO_POINTER(i + 1));
		if (i == 3) gtk_box_append(GTK_BOX(l_box), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL));
		gtk_box_append(GTK_BOX(l_box), b);
	}
	gtk_popover_set_child(GTK_POPOVER(l_pop), l_box);
	gtk_widget_set_parent(l_pop, l_parent);
	r.x = (int)s_pointer_x; r.y = (int)s_pointer_y; r.width = 1; r.height = 1;
	gtk_popover_set_pointing_to(GTK_POPOVER(l_pop), &r);
	gtk_popover_set_has_arrow(GTK_POPOVER(l_pop), FALSE);
	g_signal_connect(l_pop, "closed", G_CALLBACK(shell_text_menu_closed), NULL);
	s_text_menu_choice = 0;
	s_text_menu_open = 1;
	gtk_popover_popup(GTK_POPOVER(l_pop));
	while (s_text_menu_open) g_main_context_iteration(NULL, TRUE);
	gtk_widget_unparent(l_pop);
	return s_text_menu_choice;
}

/* ------------------------------------------------------------------ the overlay

   A full-screen window for picking a region (31 move, 32 press, 33 release, 34 cancel: Escape
   or a right press, already hidden; 35 expose; 36 Enter; 37 an arrow key). Wayland gives it the
   monitor it opens on; X11 the whole desktop. */
static GtkWidget *s_overlay = NULL, *s_overlay_area = NULL;
static cairo_surface_t *s_overlay_backing = NULL;
static void shell_overlay_draw(GtkDrawingArea *a, cairo_t *cr, int w, int h, gpointer d)
{
	int k = gtk_widget_get_scale_factor(GTK_WIDGET(a));
	(void)w; (void)h; (void)d;
	if (!s_overlay_backing) return;
	cairo_scale(cr, 1.0 / k, 1.0 / k);
	cairo_set_source_surface(cr, s_overlay_backing, 0, 0);
	cairo_paint(cr);
}
static int shell_overlay_px(double v) { return (int)floor(v * (s_overlay_area ? gtk_widget_get_scale_factor(s_overlay_area) : 1)); }
static void shell_overlay_motion(GtkEventControllerMotion *m, double x, double y, gpointer d)
{
	int last = (s_qtail + SHELL_QCAP - 1) % SHELL_QCAP;
	(void)m; (void)d;
	if (s_qtail != s_qhead && s_q[last][0] == 31) { s_q[last][1] = shell_overlay_px(x); s_q[last][2] = shell_overlay_px(y); }
	else shell_push(31, shell_overlay_px(x), shell_overlay_px(y), 0);
}
static void shell_overlay_press(GtkGestureClick *g, int n, double x, double y, gpointer d)
{
	(void)n; (void)d;
	if (gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(g)) == GDK_BUTTON_SECONDARY) { shell_hide_overlay(); shell_push(34, 0, 0, 0); }
	else shell_push(32, shell_overlay_px(x), shell_overlay_px(y), 0);
}
static void shell_overlay_release_cb(GtkGestureClick *g, int n, double x, double y, gpointer d)
{
	(void)n; (void)d;
	if (gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(g)) == GDK_BUTTON_PRIMARY) shell_push(33, shell_overlay_px(x), shell_overlay_px(y), 0);
}
static gboolean shell_overlay_key(GtkEventControllerKey *k, guint a_keyval, guint a_code, GdkModifierType a_state, gpointer d)
{
	(void)k; (void)a_code; (void)a_state; (void)d;
	switch (a_keyval) {
		case GDK_KEY_Escape: shell_hide_overlay(); shell_push(34, 0, 0, 0); return TRUE;
		case GDK_KEY_Return: case GDK_KEY_KP_Enter: shell_push(36, 0, 0, 0); return TRUE;
		case GDK_KEY_Left: case GDK_KEY_Up: case GDK_KEY_Right: case GDK_KEY_Down: shell_push(37, shell_vk(a_keyval), 0, 0); return TRUE;
	}
	return FALSE;
}
static gboolean shell_overlay_close(GtkWindow *w, gpointer d) { (void)w; (void)d; shell_hide_overlay(); shell_push(34, 0, 0, 0); return TRUE; }
void *shell_show_overlay(void)
{
	int x, y, w, h;
	shell_app();
	if (g_thread_self() != s_pump_thread) return NULL;
	shell_virtual_desktop(&x, &y, &w, &h);
	if (w <= 0 || h <= 0) return NULL;
	if (!s_overlay) {
		GtkGesture *g;
		GtkEventController *m, *key;
		s_overlay = gtk_window_new();
		gtk_window_set_decorated(GTK_WINDOW(s_overlay), FALSE);
		s_overlay_area = gtk_drawing_area_new();
		gtk_widget_set_focusable(s_overlay_area, TRUE);
		gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(s_overlay_area), shell_overlay_draw, NULL, NULL);
		m = gtk_event_controller_motion_new();
		g_signal_connect(m, "motion", G_CALLBACK(shell_overlay_motion), NULL);
		gtk_widget_add_controller(s_overlay_area, m);
		g = gtk_gesture_click_new();
		gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(g), 0);
		g_signal_connect(g, "pressed", G_CALLBACK(shell_overlay_press), NULL);
		g_signal_connect(g, "released", G_CALLBACK(shell_overlay_release_cb), NULL);
		gtk_widget_add_controller(s_overlay_area, GTK_EVENT_CONTROLLER(g));
		key = gtk_event_controller_key_new();
		g_signal_connect(key, "key-pressed", G_CALLBACK(shell_overlay_key), NULL);
		gtk_widget_add_controller(s_overlay, key);
		gtk_window_set_child(GTK_WINDOW(s_overlay), s_overlay_area);
		g_signal_connect(s_overlay, "close-request", G_CALLBACK(shell_overlay_close), NULL);
		g_object_add_weak_pointer(G_OBJECT(s_overlay), (gpointer *)&s_overlay);
	}
	if (!s_overlay_backing || cairo_image_surface_get_width(s_overlay_backing) != w || cairo_image_surface_get_height(s_overlay_backing) != h) {
		if (s_overlay_backing) cairo_surface_destroy(s_overlay_backing);
		s_overlay_backing = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
	}
	gtk_window_fullscreen(GTK_WINDOW(s_overlay));
	gtk_window_present(GTK_WINDOW(s_overlay));
	gtk_widget_grab_focus(s_overlay_area);
	gtk_widget_set_cursor_from_name(s_overlay_area, "crosshair");
	shell_push(35, 0, 0, 0);
	return s_overlay;
}
void shell_hide_overlay(void) { if (s_overlay) gtk_widget_set_visible(s_overlay, FALSE); }
void *shell_overlay_dc(void) { return s_overlay ? (void *)s_overlay_backing : NULL; }
void shell_overlay_release(void *dc) { if (dc && s_overlay_area) gtk_widget_queue_draw(s_overlay_area); }

/* ------------------------------------------------------------------ outlines

   Click-through colored frames at exact desktop places (8 slots). X11 places them exactly
   (override-redirect, above everything); Wayland lets no program place a window, so there they
   are not available. */
#define SHELL_OUTLINES 8
typedef struct { GtkWidget *window; int thick, rgb; } ShellOutline;
static ShellOutline s_outline[SHELL_OUTLINES];
static int s_outline_css = 0;
static void shell_outline_draw(GtkDrawingArea *a, cairo_t *cr, int w, int h, gpointer d)
{
	int l_slot = GPOINTER_TO_INT(d), k = gtk_widget_get_scale_factor(GTK_WIDGET(a));
	double t;
	if (l_slot < 0 || l_slot >= SHELL_OUTLINES) return;
	t = (double)s_outline[l_slot].thick / k;
	cairo_set_source_rgb(cr, ((s_outline[l_slot].rgb >> 16) & 0xFF) / 255.0, ((s_outline[l_slot].rgb >> 8) & 0xFF) / 255.0, (s_outline[l_slot].rgb & 0xFF) / 255.0);
	cairo_set_line_width(cr, t);
	cairo_rectangle(cr, t / 2, t / 2, w - t, h - t);
	cairo_stroke(cr);
}
void shell_outline_show(int slot, int x, int y, int w, int h, int thick, int rgb)
{
#ifdef GDK_WINDOWING_X11
	Display *d = shell_x11();
	ShellOutline *o;
	int k;
	if (slot < 0 || slot >= SHELL_OUTLINES || w <= 0 || h <= 0 || !d || g_thread_self() != s_pump_thread) return;
	o = &s_outline[slot];
	o->thick = thick > 0 ? thick : 1; o->rgb = rgb;
	k = shell_scale();
	if (!s_outline_css) {
		GtkCssProvider *p = gtk_css_provider_new();
		gtk_css_provider_load_from_string(p, "window.ss-outline { background: transparent; }");
		gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(p), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
		g_object_unref(p);
		s_outline_css = 1;
	}
	if (!o->window) {
		GtkWidget *a = gtk_drawing_area_new();
		o->window = gtk_window_new();
		gtk_window_set_decorated(GTK_WINDOW(o->window), FALSE);
		gtk_widget_add_css_class(o->window, "ss-outline");
		gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(a), shell_outline_draw, GINT_TO_POINTER(slot), NULL);
		gtk_window_set_child(GTK_WINDOW(o->window), a);
		g_object_add_weak_pointer(G_OBJECT(o->window), (gpointer *)&o->window);
	}
	gtk_window_set_default_size(GTK_WINDOW(o->window), w / k > 0 ? w / k : 1, h / k > 0 ? h / k : 1);
	gtk_widget_realize(o->window);
	{
		GdkSurface *s = gtk_native_get_surface(GTK_NATIVE(o->window));
		Window xid = gdk_x11_surface_get_xid(s);
		XSetWindowAttributes l_a;
		cairo_region_t *l_none = cairo_region_create();
		gdk_surface_set_input_region(s, l_none);   /* clicks pass through */
		cairo_region_destroy(l_none);
		l_a.override_redirect = True;
		XChangeWindowAttributes(d, xid, CWOverrideRedirect, &l_a);
		gtk_widget_set_visible(o->window, TRUE);
		XMoveResizeWindow(d, xid, x, y, (unsigned int)w, (unsigned int)h);
		XRaiseWindow(d, xid);
		XFlush(d);
	}
	gtk_widget_queue_draw(gtk_window_get_child(GTK_WINDOW(o->window)));
#else
	(void)slot; (void)x; (void)y; (void)w; (void)h; (void)thick; (void)rgb;
#endif
}
void shell_outline_hide(int slot)
{
#ifdef GDK_WINDOWING_X11
	if (slot >= 0 && slot < SHELL_OUTLINES && s_outline[slot].window) gtk_widget_set_visible(s_outline[slot].window, FALSE);
#else
	(void)slot;
#endif
}
