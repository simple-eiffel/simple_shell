/* shell_sdk_poison.h - TEST-ONLY, half one of the SDK-macro tripwire.
   Include this BEFORE simple_shell.h; include shell_sdk_tripwire.h after.

   What it arms: rpcndr.h does `#define small char' (and `#define hyper
   __int64'). Every COM header in the fleet reaches it - unknwn.h,
   objbase.h, mmdeviceapi.h (simple_audio), dwrite.h (simple_shaping),
   sapi.h (simple_speech). A finalized Eiffel build concatenates many
   classes into ONE translation unit, so a sibling library's COM header
   is routinely preprocessed ahead of simple_shell.h. That is how
   sw_demo's release build died on 2026-09-02: `HICON big, small;' read
   `HICON big, char;' - C2059 / C2513.

   Why the ordering check below matters more than it looks: simple_shell.h
   has an include guard. If ANOTHER class in the same concatenated unit
   included it FIRST - unpoisoned - the tripwire's own `#include
   "simple_shell.h"' collapses to nothing and the test passes on a broken
   header. That is exactly what happened on the first cut of this test.
   The tripwire is only armed while its class sorts ahead of every SHELL_*
   class in its partition (generated file names are the class name's first
   two letters, lowercased, and are concatenated alphabetically) - hence
   the class is SDK_MACRO_TRIPWIRE, "sd" < "sh". If that ever stops being
   true, the #error below fails the BUILD instead of letting the test lie. */

#ifndef SHELL_SDK_POISON_H
#define SHELL_SDK_POISON_H

#ifdef SIMPLE_SHELL_H
#error "SDK-macro tripwire DISARMED: simple_shell.h was already included (unpoisoned) earlier in this translation unit, so the tripwire's own include is a no-op. Rename SDK_MACRO_TRIPWIRE so its generated C file sorts ahead of every SHELL_* class, then rebuild."
#endif

#include <rpc.h>
#include <rpcndr.h>

#endif /* SHELL_SDK_POISON_H */
