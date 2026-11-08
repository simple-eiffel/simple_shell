# macOS build of simple_shell's AppKit half (M1), the object simple_shell.ecf links on a Mac.
# Usage: make -C Clib. On Windows the shell is header-only (simple_shell.h), so there is
# nothing to build.
ifeq ($(shell uname -s),Darwin)

CC ?= cc
CAIRO_CFLAGS := $(shell pkg-config --cflags cairo 2>/dev/null || echo -I/opt/homebrew/include/cairo)
CFLAGS ?= -O2 -g
CFLAGS += -Wall $(CAIRO_CFLAGS)

SOURCES := macos/shell_appkit.m macos/shell_appkit_ax.m macos/shell_appkit_print.m
OBJECTS := $(SOURCES:.m=.o) macos/shell_appkit_stubs.o

simple_shell_appkit.o: $(OBJECTS)
	ld -r $(OBJECTS) -o simple_shell_appkit.o

macos/%.o: macos/%.m macos/shell_appkit.h
	$(CC) $(CFLAGS) -fobjc-arc -c $< -o $@

macos/shell_appkit_stubs.c: macos/shell_appkit.h $(SOURCES) macos/make_stubs.pl
	perl macos/make_stubs.pl macos/shell_appkit.h $(SOURCES) > macos/shell_appkit_stubs.c

macos/shell_appkit_stubs.o: macos/shell_appkit_stubs.c macos/shell_appkit.h
	$(CC) $(CFLAGS) -Wno-unused-parameter -c macos/shell_appkit_stubs.c -o macos/shell_appkit_stubs.o

clean:
	rm -f simple_shell_appkit.o macos/*.o macos/shell_appkit_stubs.c

else

all:
	@echo "simple_shell Clib: nothing to build here (the Windows shell is header-only)."

clean:
	@true

endif

.PHONY: all clean
