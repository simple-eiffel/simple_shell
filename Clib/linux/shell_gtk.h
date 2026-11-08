/* shell_gtk.h - the Linux (GTK 4) half of simple_shell: what the Eiffel classes' inline C
   sees when simple_shell.h is included on Linux. The bodies are in shell_gtk.c, built into
   simple_shell_gtk.o by Clib/Makefile; an entry point without a body yet answers "not
   available" through a stub that make_stubs.pl generates, so the stub list is the to-do list.

   The contract is the macOS half's, word for word (../shell_posix.h, and
   port-coordination docs/SHELL_SEAM.md): device pixels, Windows virtual keys and UTF-16 code
   units, UTF-8 in, and the window's backing cairo image surface in place of a device context.
   So the declarations are shared with the macOS half: shell_posix.h, one list that cannot
   drift. Screen-reader serving
   (AT-SPI, checked with Orca) comes last, by Larry's order (2026-11-08). */

#ifndef SHELL_GTK_H
#define SHELL_GTK_H

#include "../shell_posix.h"

#endif
