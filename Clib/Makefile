# macOS build of simple_shell's AppKit half (M1), the object simple_shell.ecf links on a Mac.
# Usage: make -C Clib. On Windows the shell is header-only (simple_shell.h), so there is
# nothing to build.
ifeq ($(shell uname -s),Darwin)

CC ?= cc
CAIRO_CFLAGS := $(shell pkg-config --cflags cairo 2>/dev/null || echo -I/opt/homebrew/include/cairo)
CFLAGS ?= -O2 -g
CFLAGS += -Wall $(CAIRO_CFLAGS)

# The accessibility table is shared with the Linux half (shell_ax_table.c, plain C); its
# object goes in macos/ so the two halves' objects never meet.
APPKIT_SOURCES := macos/shell_appkit.m macos/shell_appkit_print.m
SOURCES := $(APPKIT_SOURCES) shell_ax_table.c
OBJECTS := $(APPKIT_SOURCES:.m=.o) macos/shell_ax_table.o macos/shell_appkit_stubs.o

simple_shell_appkit.o: $(OBJECTS)
	ld -r $(OBJECTS) -o simple_shell_appkit.o

macos/%.o: macos/%.m macos/shell_appkit.h shell_posix.h
	$(CC) $(CFLAGS) -fobjc-arc -c $< -o $@

macos/shell_ax_table.o: shell_ax_table.c shell_posix.h
	$(CC) $(CFLAGS) -c shell_ax_table.c -o macos/shell_ax_table.o

macos/shell_appkit_stubs.c: shell_posix.h $(SOURCES) make_stubs.pl
	perl make_stubs.pl shell_posix.h $(SOURCES) > macos/shell_appkit_stubs.c

macos/shell_appkit_stubs.o: macos/shell_appkit_stubs.c shell_posix.h
	$(CC) $(CFLAGS) -Wno-unused-parameter -c macos/shell_appkit_stubs.c -o macos/shell_appkit_stubs.o

clean:
	rm -f simple_shell_appkit.o macos/*.o macos/shell_appkit_stubs.c

else ifeq ($(shell uname -s),Linux)

# Linux build of simple_shell's GTK 4 half (item 2 of GUI_PLAN.md), the object simple_shell.ecf
# links on Linux. The entry points without a body yet get make_stubs.pl's "not available" stubs,
# generated from the declarations shared with the macOS half.
CC ?= cc
GTK_CFLAGS := $(shell pkg-config --cflags gtk4 fontconfig)
CFLAGS ?= -O2 -g
CFLAGS += -Wall -fPIC $(GTK_CFLAGS)

SOURCES := linux/shell_gtk.c shell_ax_table.c
OBJECTS := $(SOURCES:.c=.o) linux/shell_gtk_stubs.o

simple_shell_gtk.o: $(OBJECTS)
	ld -r $(OBJECTS) -o simple_shell_gtk.o

linux/%.o: linux/%.c linux/shell_gtk.h shell_posix.h
	$(CC) $(CFLAGS) -c $< -o $@

linux/shell_gtk_stubs.c: shell_posix.h $(SOURCES) make_stubs.pl
	perl make_stubs.pl shell_posix.h $(SOURCES) > linux/shell_gtk_stubs.c

linux/shell_gtk_stubs.o: linux/shell_gtk_stubs.c shell_posix.h
	$(CC) $(CFLAGS) -Wno-unused-parameter -c linux/shell_gtk_stubs.c -o linux/shell_gtk_stubs.o

clean:
	rm -f simple_shell_gtk.o linux/*.o linux/shell_gtk_stubs.c shell_ax_table.o

else

all:
	@echo "simple_shell Clib: nothing to build here (the Windows shell is header-only)."

clean:
	@true

endif

.PHONY: all clean
