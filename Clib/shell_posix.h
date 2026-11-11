/* shell_posix.h - simple_shell's entry points off Windows: what the Eiffel classes' inline C
   sees when simple_shell.h is included on macOS (macos/shell_appkit.h includes this) or Linux
   (linux/shell_gtk.h includes this). One list for both halves, so they cannot drift. The
   bodies are in the macos .m files (AppKit) and the linux .c files (GTK 4), built by
   Clib/Makefile; an entry point a half has no body for yet answers "not available"
   through a stub that make_stubs.pl generates from this list.

   Contract, as on Windows (simple_shell.h is the reference):
   - The same entry points, the same event queue [type, a, b, c], the same event numbers.
   - Coordinates and sizes are DEVICE PIXELS, as for a DPI-aware Win32 process: a Retina
     window of 800 x 600 pixels is 400 x 300 points. The reported DPI (96 x the backing scale)
     lets simple_widgets scale its theme, so it draws crisply without knowing it is on a Mac.
   - Keys arrive as Windows virtual-key codes (event 4) and UTF-16 code units (event 3).
     Command is the primary modifier: `shell_control_down' is true while Command (or
     Control) is held, and Command+letter arrives as Windows delivers Ctrl+letter.
   - Text going in is UTF-8 (NATIVE_STRING's form on a Mac); text coming back is written in
     the form the Eiffel caller reads it (UTF-16 where it reads `read_natural_16').
   - There is no device context: `shell_get_dc' hands over the window's backing cairo image
     surface, which simple_cairo's off-Windows `make_for_dc' references (its documented
     contract), and `shell_release_dc' shows it.
   - Entry points of features that have no meaning on a platform yet answer "not available" (0). */

#ifndef SHELL_POSIX_H
#define SHELL_POSIX_H

#include <stddef.h>
#include <stdint.h>
#include <wchar.h>

/* ---- Windows names the Eiffel classes' inline C uses directly */
typedef void *HWND;
typedef void *HDC;
typedef struct { int32_t left, top, right, bottom; } RECT;
typedef struct { int32_t x, y; } POINT;
#define SPI_GETWORKAREA 0x0030
#define LOGPIXELSX 88
unsigned int GetTickCount(void);
int SystemParametersInfoW(unsigned int a_action, unsigned int a_param, void *a_out, unsigned int a_ini);
int SetProcessDPIAware(void);
HDC GetDC(HWND a_window);
int ReleaseDC(HWND a_window, HDC a_dc);
int GetDeviceCaps(HDC a_dc, int a_index);
unsigned int GetLogicalDrives(void);
int IsWindowVisible(HWND a_window);
int GetCursorPos(POINT *a_point);
int GetWindowRect(HWND a_window, RECT *a_rect);
int PtInRect(const RECT *a_rect, POINT a_point);

/* ---- shared state the inline C reads */
extern int s_shell_heartbeat_ms;

/* ---- the entry points (simple_shell.h's, text as UTF-8 in and the caller's form out) */
int shell_add_font(const char *path);
int shell_alt_down(void);
void shell_arm_dwell_timer(int l_ms);
int shell_can_grab_screen(void);
void shell_cancel_dwell_timer(void);
void shell_claim_pump_thread(int l_on);
int shell_clip_get(void *buf, int cap);
int shell_clip_get_image(void *bits, int w, int h, int stride);
int shell_clip_has_image(void);
int shell_clip_has_text(void);
int shell_clip_image_size(int *w, int *h);
int shell_clip_set(const void *s);
int shell_clip_set_image(const void *bits, int w, int h, int stride);
void shell_close_window(void);
int shell_contrast_changed(unsigned int l_spi);
int shell_control_down(void);
void* shell_create_window(const void* title, int px, int py, int cw, int ch);
int shell_drop_paths(void *buf, int cap);
int shell_dwell_is_armed(void);
void* shell_get_dc(void);
int shell_grab_screen(int x, int y, int w, int h, void* bits, int stride);
void shell_hide_overlay(void);
void shell_hide_strip(void);
int shell_high_contrast_on(void);
int shell_hotkey_can_register(void);
int shell_hotkey_register(int l_id, int l_mods, int l_vk);
void shell_hotkey_simulate(int l_id, int l_mods, int l_vk);
void shell_hotkey_unregister(int l_id);
int shell_input_chord(int ctrl, int shift, int alt, int vk);
int shell_input_click(int x, int y, int restore_cursor, int restore_focus);
int shell_input_can_send(void);
int shell_input_last_error(void);
int shell_input_on_desktop(int x, int y);
int shell_input_pointer(int *x, int *y);
int shell_input_type(const void *s);
int shell_input_type_units(const void *s);
int shell_keydown_is_ours(int l_vk, int l_ctrl, int l_alt);
void shell_kill_fast_timer(void);
void* shell_main_icon(void);
int shell_main_is_shown(void);
int shell_minutes_of_day(void);
int shell_monitor_field(int l_i, int l_f);
int shell_monitor_name(int l_i, void* l_buf, int l_cap);
int shell_monitors_refresh(void);
int shell_motion_changed(unsigned int l_spi);
int shell_next_event(int* out4);
double shell_now_ms(void);
int shell_open_file_dialog(const void* l_title, const void* l_filter, const void* l_initial_dir, void* l_out, int l_cap);
void shell_outline_hide(int slot);
void shell_outline_show(int slot, int x, int y, int w, int h, int thick, int rgb);
void* shell_overlay_dc(void);
void shell_overlay_release(void* dc);
int shell_panel_accepts_files(int l_slot);
int shell_panel_can_minimize(int l_slot);
int shell_panel_capture_affinity(int l_slot);
void shell_panel_client_size(int l_slot, int* l_w, int* l_h);
void shell_panel_close(int l_slot);
void* shell_panel_dc(int l_slot);
void shell_panel_destroy_behind(int l_slot);
void shell_panel_fill(int l_slot, int l_rgb);
int shell_panel_grip_code(int l_slot, int l_x, int l_y);
int shell_panel_has_owner(int l_slot);
void shell_panel_hide(int l_slot);
HWND shell_panel_hwnd(int l_slot);
void* shell_panel_icon(int l_slot);
void shell_panel_invalidate(int l_slot);
int shell_panel_is_click_through(int l_slot);
int shell_panel_is_tool_window(int l_slot);
int shell_panel_is_topmost(int l_slot);
int shell_panel_is_visible(int l_slot);
int shell_panel_opacity(int l_slot);
int shell_panel_open(int l_x, int l_y, int l_w, int l_h);
int shell_panel_open_framed(int l_x, int l_y, int l_w, int l_h, const void* l_title);
int shell_panel_open_framed_as(int l_x, int l_y, int l_w, int l_h, const void* l_title, int l_document);
void shell_panel_place(int l_slot, int l_x, int l_y, int l_w, int l_h);
int shell_panel_press_code(int l_slot, int l_x, int l_y, int l_shift);
void shell_panel_rect(int l_slot, int* l_x, int* l_y, int* l_w, int* l_h);
void shell_panel_release_dc(int l_slot, void* l_dc);
int shell_panel_send(int l_slot, int l_msg, int l_w, int l_l);
void shell_panel_set_accepts_files(int l_slot, int l_on);
void shell_panel_set_accepts_text(int l_slot, int l_on);
int shell_panel_accepts_text(int l_slot);
void shell_panel_set_axis(int l_slot, int l_axis);
void shell_panel_set_bottom_grip(int l_slot, int l_on);
void shell_panel_set_capture_excluded(int l_slot, int l_on);
void shell_panel_set_click_through(int l_slot, int l_on);
void shell_panel_set_draggable(int l_slot, int l_on);
void shell_panel_set_opacity(int l_slot, int l_alpha);
void shell_panel_set_press_drag(int l_slot, int l_on);
void shell_panel_set_resizable(int l_slot, int l_grip, int l_min_w, int l_min_h);
void shell_panel_set_side_grip(int l_slot, int l_on);
void shell_panel_set_title(int l_slot, const void* l_title);
void shell_panel_show(int l_slot, int l_x, int l_y, int l_w, int l_h);
void shell_panel_try_drop(int l_slot, int l_x, int l_y, const void* l_paths);
void shell_panel_try_drag_in(int l_slot, int l_x, int l_y, const void* l_text, const void* l_paths);
int shell_dropped_text(void* l_buf, int l_cap);
int shell_drag_out(const void* l_text, const void* l_paths);
void shell_panel_try_move(int l_slot, int l_dx, int l_dy, int* l_x, int* l_y);
void shell_print_abort(void);
int shell_print_begin(const void* l_printer, const void* l_title, const void* l_output, int l_paper, int l_landscape);
int shell_print_begin_page(void);
int shell_print_caps(int l_index);
void* shell_print_dc(void);
int shell_print_default(void* l_buf, int l_cap);
int shell_print_end(void);
int shell_print_end_page(void);
int shell_print_in_page(void);
int shell_print_names(void* l_buf, int l_cap);
int shell_pump(void);
void shell_pump_for(int ms);
int shell_pump_pending(void);
int shell_pump_until(int ms);
void shell_push(int t, int a, int b, int c);
int shell_reduces_motion(void);
void shell_release_dc(void* dc);
void shell_request_close(void);
int shell_screen_h(void);
int shell_screen_w(void);
int shell_screen_x(void);
int shell_screen_y(void);
void shell_set_backdrop(void* hwnd, int rgb);
void shell_set_caption(const void* l_title);
void shell_set_close_requests(int on);
void shell_set_cursor_kind(int k);
int shell_set_dark_title_bar(void* hwnd, int l_on);
void shell_set_fast_timer(int ms);
void shell_set_heartbeat(int l_ms);
void shell_set_start_hidden(int l_on);
void shell_set_window_icon(const void* path);
int shell_setting_changed(const void* l_area);
int shell_shell_open(const void* path);
int shell_shift_down(void);
int shell_shift_held(void);
void shell_show_main(int l_on);
void* shell_show_overlay(void);
void* shell_show_strip(int x, int y, int w, int h);
int shell_spell_add(const void *word);
int shell_spell_check(const void *text, int *out, int cap_pairs);
int shell_spell_ignore(const void *word);
int shell_spell_suggest(const void *word, void *buf, int cap);
void* shell_strip_dc(void);
void shell_strip_release(void* dc);
int shell_syschar_is_ours(int l_ch);
int shell_syskey_is_ours(int l_vk);
unsigned int shell_system_color(int l_index);
void shell_system_colors_changed(void);
int shell_system_prefers_dark(void);
int shell_text_menu(int can_cut, int can_copy, int can_paste, int can_select);
HWND shell_tray_add(const void* tip);
int shell_tray_balloon(HWND h, const void* title, const void* body);
int shell_tray_id(HWND h);
int shell_tray_menu(HWND h, const void* l_items);
int shell_tray_remove(HWND h);
int shell_tray_set_tip(HWND h, const void* tip);
void shell_tray_try_click(HWND h, int l_msg);
int shell_uia_add(int l_id, int l_parent, int l_role, int l_focusable, int l_enabled, double l_x, double l_y, double l_w, double l_h, const void* l_name, const void* l_value);
int shell_uia_begin(int l_cap);
int shell_uia_clients_listening(void);
void shell_uia_commit(void* l_hwnd);
void shell_uia_disable(void);
void shell_uia_focus_changed(int l_id);
int shell_uia_row_count(void);
int shell_uia_row_int(int l_i, int l_field);
int shell_uia_row_text(int l_i, int l_which, void* l_out, int l_cap);
int shell_uia_served_focus(void);
void* shell_uia_served_window(void);
int shell_wake(void);
int shell_is_pump_thread(void);
int shell_uia_describe_last(const void* l_text);

#endif
