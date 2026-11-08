/* shell_gtk.c - the Linux (GTK 4) half of simple_shell. Step 1 (item 2 of GUI_PLAN.md):
   the shared state and the Windows names the Eiffel inline C calls directly. The window,
   its pump, events and drawing come next; until then make_stubs.pl answers "not available"
   for them (see shell_gtk.h). */

#include <gtk/gtk.h>
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
