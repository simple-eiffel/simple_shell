/* shell_key_probe.h - test-only: hand a key-down or a system key-down to the main
   window's procedure with a null handle. On Windows that is shell_wndproc itself.
   Elsewhere there is no window procedure; the stand-in does what its WM_KEYDOWN and
   WM_SYSKEYDOWN branches do with the same policy (shell_keydown_is_ours,
   shell_syskey_is_ours) and the same event (4), as the AppKit and GTK key paths do. */

#ifndef SHELL_KEY_PROBE_H
#define SHELL_KEY_PROBE_H

#include "simple_shell.h"

#ifdef _WIN32
static void shell_key_probe_keydown(int l_vk) { shell_wndproc((HWND)0, WM_KEYDOWN, (WPARAM)l_vk, (LPARAM)0); }
static void shell_key_probe_syskeydown(int l_vk) { shell_wndproc((HWND)0, WM_SYSKEYDOWN, (WPARAM)l_vk, (LPARAM)0); }
#else
static void shell_key_probe_keydown(int l_vk)
{
	if (shell_keydown_is_ours(l_vk, shell_control_down(), shell_alt_down())) shell_push(4, l_vk, 0, 0);
}
static void shell_key_probe_syskeydown(int l_vk) { if (shell_syskey_is_ours(l_vk)) shell_push(4, l_vk, 0, 0); }
#endif

#endif
