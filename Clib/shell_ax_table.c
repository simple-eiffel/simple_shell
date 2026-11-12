/* shell_ax_table.c - simple_shell's accessibility tables off Windows (macOS and Linux share it;
   it was macos/shell_appkit_ax.m, pure C apart from an unused Foundation import).
   The same contract as the Windows bridge (simple_shell_uia.h): `shell_uia_begin' stages a
   table, `shell_uia_add' and `shell_uia_describe_last' fill it, `shell_uia_commit' publishes
   it for a window - every window keeps its own (simple_shell#48) - and the *_of functions
   read a window's published table back. Text is kept and answered as UTF-8 (the Eiffel side
   reads it through NATIVE_STRING).
   Not yet: serving the tables to a screen reader (VoiceOver on macOS, AT-SPI on Linux; last,
   by Larry's order), so `shell_uia_clients_listening' answers 0. */

#include <stdlib.h>
#include <string.h>
#include "shell_posix.h"

typedef struct {
	int l_id, l_parent, l_role, l_focusable, l_enabled, l_has_value;
	double l_x, l_y, l_w, l_h;
	char *l_name, *l_value, *l_description;
} shell_ax_node;

typedef struct {
	int l_used;
	void *l_window;
	shell_ax_node *l_nodes;
	int l_count, l_focus;
} shell_ax_window;

static shell_ax_window *s_windows = NULL;
static int s_window_cap = 0;
static shell_ax_node *s_stage = NULL;
static int s_stage_count = 0, s_stage_cap = 0;

static char *shell_ax_copy(const void *a_text) { return a_text ? strdup((const char *)a_text) : NULL; }

static void shell_ax_free(shell_ax_node *a_nodes, int a_count)
{
	if (!a_nodes) return;
	for (int i = 0; i < a_count; i++) { free(a_nodes[i].l_name); free(a_nodes[i].l_value); free(a_nodes[i].l_description); }
	free(a_nodes);
}

static shell_ax_window *shell_ax_find(void *a_window)
{
	for (int i = 0; i < s_window_cap; i++)
		if (s_windows[i].l_used && s_windows[i].l_window == a_window) return &s_windows[i];
	return NULL;
}

/* The records grow as windows publish (as on Windows). */
static shell_ax_window *shell_ax_claim(void *a_window)
{
	shell_ax_window *w = shell_ax_find(a_window);
	int l_free = -1;
	if (w) return w;
	for (int i = 0; i < s_window_cap && l_free < 0; i++)
		if (!s_windows[i].l_used) l_free = i;
	if (l_free < 0) {
		int l_cap = s_window_cap > 0 ? s_window_cap * 2 : 8;
		shell_ax_window *l_grown = realloc(s_windows, (size_t)l_cap * sizeof(shell_ax_window));
		if (!l_grown) return NULL;
		memset(l_grown + s_window_cap, 0, (size_t)(l_cap - s_window_cap) * sizeof(shell_ax_window));
		l_free = s_window_cap;
		s_windows = l_grown;
		s_window_cap = l_cap;
	}
	memset(&s_windows[l_free], 0, sizeof(shell_ax_window));
	s_windows[l_free].l_used = 1;
	s_windows[l_free].l_window = a_window;
	return &s_windows[l_free];
}

int shell_uia_begin(int l_cap)
{
	shell_ax_free(s_stage, s_stage_count);
	s_stage_count = 0;
	s_stage_cap = l_cap > 0 ? l_cap : 1;
	s_stage = calloc((size_t)s_stage_cap, sizeof(shell_ax_node));
	return s_stage ? 1 : 0;
}

int shell_uia_add(int l_id, int l_parent, int l_role, int l_focusable, int l_enabled,
	double l_x, double l_y, double l_w, double l_h, const void *l_name, const void *l_value)
{
	if (!s_stage || s_stage_count >= s_stage_cap) return 0;
	shell_ax_node *n = &s_stage[s_stage_count++];
	n->l_id = l_id; n->l_parent = l_parent; n->l_role = l_role;
	n->l_focusable = l_focusable; n->l_enabled = l_enabled; n->l_has_value = l_value ? 1 : 0;
	n->l_x = l_x; n->l_y = l_y; n->l_w = l_w; n->l_h = l_h;
	n->l_name = shell_ax_copy(l_name);
	n->l_value = shell_ax_copy(l_value);
	n->l_description = NULL;
	return 1;
}

int shell_uia_describe_last(const void *l_text)
{
	if (!s_stage || s_stage_count < 1) return 0;
	shell_ax_node *n = &s_stage[s_stage_count - 1];
	free(n->l_description);
	n->l_description = shell_ax_copy(l_text);
	return 1;
}

void shell_uia_commit(void *l_hwnd)
{
	shell_ax_window *w = shell_ax_claim(l_hwnd);
	if (w) {
		shell_ax_node *l_old = w->l_nodes;
		int l_old_count = w->l_count;
		w->l_nodes = s_stage; w->l_count = s_stage_count;
		shell_ax_free(l_old, l_old_count);
	} else {
		shell_ax_free(s_stage, s_stage_count);
	}
	s_stage = NULL; s_stage_count = 0; s_stage_cap = 0;
}

int shell_uia_row_count_of(void *l_hwnd)
{
	shell_ax_window *w = shell_ax_find(l_hwnd);
	return w ? w->l_count : 0;
}

int shell_uia_row_int_of(void *l_hwnd, int l_i, int l_field)
{
	shell_ax_window *w = shell_ax_find(l_hwnd);
	if (!w || l_i < 0 || l_i >= w->l_count) return -1;
	shell_ax_node *n = &w->l_nodes[l_i];
	switch (l_field) {
		case 0: return n->l_id; case 1: return n->l_parent; case 2: return n->l_role;
		case 3: return n->l_focusable; case 4: return n->l_enabled; case 5: return n->l_has_value;
	}
	return -1;
}

int shell_uia_row_text_of(void *l_hwnd, int l_i, int l_which, void *l_out, int l_cap)
{
	shell_ax_window *w = shell_ax_find(l_hwnd);
	const char *l_text = NULL;
	int l_n = 0;
	if (l_cap < 1) return 0;
	if (w && l_i >= 0 && l_i < w->l_count)
		l_text = l_which == 0 ? w->l_nodes[l_i].l_name : l_which == 1 ? w->l_nodes[l_i].l_value : w->l_nodes[l_i].l_description;
	if (l_text) { l_n = (int)strlen(l_text); if (l_n > l_cap - 1) l_n = l_cap - 1; memcpy(l_out, l_text, (size_t)l_n); }
	((char *)l_out)[l_n] = 0;
	return l_n;
}

int shell_uia_served_focus_of(void *l_hwnd)
{
	shell_ax_window *w = shell_ax_find(l_hwnd);
	return w ? w->l_focus : 0;
}

int shell_uia_clients_listening(void) { return 0; }

void shell_uia_focus_changed_in(void *l_hwnd, int l_id)
{
	shell_ax_window *w = shell_ax_find(l_hwnd);
	if (w) w->l_focus = l_id;
}

void shell_uia_disable_window(void *l_hwnd)
{
	shell_ax_window *w = shell_ax_find(l_hwnd);
	if (w) { shell_ax_free(w->l_nodes, w->l_count); memset(w, 0, sizeof(shell_ax_window)); }
}

int shell_uia_window_count(void)
{
	int l_n = 0;
	for (int i = 0; i < s_window_cap; i++) if (s_windows[i].l_used) l_n++;
	return l_n;
}
