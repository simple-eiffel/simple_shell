/* shell_sdk_tripwire.h - TEST-ONLY, half two of the SDK-macro tripwire.
   Not shipped in Clib/, not on any consumer's include path; only the
   simple_shell_tests target adds testing/Clib.

   Include order in the tripwire's translation unit:

       shell_sdk_poison.h      <- arms the SDK macros (rpcndr.h)
       simple_shell.h          <- must parse cleanly with them in force
       shell_sdk_tripwire.h    <- this file

   The 1.9.1 defect and the disarming trap are documented in
   shell_sdk_poison.h. The two functions here are the proof:

     - shell_tripwire_poison_in_force  reports whether the poison is
       actually ARMED. If a future SDK stops defining `small', this
       returns 0 and the run-time test fails loudly, telling us to
       re-point the tripwire. A silent tripwire is worse than none.

     - shell_tripwire_shell_header_survived  cannot even COMPILE unless
       simple_shell.h parsed under the poison. On the pre-1.9.1 header the
       C phase fails and the test target never links - which is the test. */

#ifndef SHELL_SDK_TRIPWIRE_H
#define SHELL_SDK_TRIPWIRE_H

#ifndef SIMPLE_SHELL_H
#error "shell_sdk_tripwire.h must be included AFTER simple_shell.h"
#endif

#ifndef SHELL_SDK_POISON_H
#error "shell_sdk_tripwire.h is meaningless without shell_sdk_poison.h included ahead of simple_shell.h"
#endif

static int shell_tripwire_poison_in_force(void) {
#ifdef small
    return 1;
#else
    return 0;
#endif
}

static int shell_tripwire_shell_header_survived(void) {
    /* Reach the features that carried the defect. Both refuse the call at
       their own guard, so this is a compile-and-link proof with no side
       effect: shell_set_window_icon returns on `!path', and
       shell_set_fast_timer returns on `ms > 0' being false. */
    shell_set_window_icon(0);
    shell_set_fast_timer(0);
    return 1;
}

#endif /* SHELL_SDK_TRIPWIRE_H */
