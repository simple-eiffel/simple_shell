/* shell_appkit_ax.m - simple_shell's accessibility table on macOS (M1).
   The same contract as the Windows bridge (simple_shell_uia.h): `shell_uia_begin' stages a
   table, `shell_uia_add' and `shell_uia_describe_last' fill it, `shell_uia_commit' publishes
   it for a window, and the row_* functions read the published table back. Text is kept and
   answered as UTF-8 (the Eiffel side reads it through NATIVE_STRING).
   Not yet: serving the table to VoiceOver as NSAccessibilityElements (M1 step 2), so
   `shell_uia_clients_listening' answers 0. */

#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>
#include "shell_appkit.h"

typedef struct {
	int l_id, l_parent, l_role, l_focusable, l_enabled, l_has_value;
	double l_x, l_y, l_w, l_h;
	char *l_name, *l_value, *l_description;
} shell_ax_node;

static shell_ax_node *s_nodes = NULL, *s_stage = NULL;
static int s_count = 0, s_stage_count = 0, s_stage_cap = 0, s_focus = 0;
static void *s_window = NULL;

static char *shell_ax_copy(const void *a_text) { return a_text ? strdup((const char *)a_text) : NULL; }

static void shell_ax_free(shell_ax_node *a_nodes, int a_count)
{
	if (!a_nodes) return;
	for (int i = 0; i < a_count; i++) { free(a_nodes[i].l_name); free(a_nodes[i].l_value); free(a_nodes[i].l_description); }
	free(a_nodes);
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
	shell_ax_node *l_old = s_nodes;
	int l_old_count = s_count;
	s_nodes = s_stage; s_count = s_stage_count; s_window = l_hwnd;
	s_stage = NULL; s_stage_count = 0; s_stage_cap = 0;
	shell_ax_free(l_old, l_old_count);
}

int shell_uia_row_count(void) { return s_count; }

int shell_uia_row_int(int l_i, int l_field)
{
	if (l_i < 0 || l_i >= s_count) return -1;
	shell_ax_node *n = &s_nodes[l_i];
	switch (l_field) {
		case 0: return n->l_id; case 1: return n->l_parent; case 2: return n->l_role;
		case 3: return n->l_focusable; case 4: return n->l_enabled; case 5: return n->l_has_value;
	}
	return -1;
}

int shell_uia_row_text(int l_i, int l_which, void *l_out, int l_cap)
{
	const char *l_text = NULL;
	int l_n = 0;
	if (l_cap < 1) return 0;
	if (l_i >= 0 && l_i < s_count)
		l_text = l_which == 0 ? s_nodes[l_i].l_name : l_which == 1 ? s_nodes[l_i].l_value : s_nodes[l_i].l_description;
	if (l_text) { l_n = (int)strlen(l_text); if (l_n > l_cap - 1) l_n = l_cap - 1; memcpy(l_out, l_text, (size_t)l_n); }
	((char *)l_out)[l_n] = 0;
	return l_n;
}

void *shell_uia_served_window(void) { return s_window; }
int shell_uia_served_focus(void) { return s_focus; }
int shell_uia_clients_listening(void) { return 0; }
void shell_uia_focus_changed(int l_id) { s_focus = l_id; }
void shell_uia_disable(void) { shell_ax_free(s_nodes, s_count); s_nodes = NULL; s_count = 0; s_window = NULL; }
