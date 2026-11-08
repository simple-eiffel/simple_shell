/* shell_appkit.m - the macOS half of simple_shell (M1): the window, its pump and event
   queue, keys, the pointer, timers, the wake, the clipboard, appearance and the screen.
   The contract is simple_shell.h's (the Windows half) as summarized in shell_appkit.h;
   entry points not written here yet are generated as "not available" stubs by
   Clib/Makefile (shell_appkit_stubs.c). */

#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#include <cairo.h>
#include <stdatomic.h>
#include <pthread.h>
#include <time.h>
#include "shell_appkit.h"

/* ------------------------------------------------------------------ the queue */

/* [type, a, b, c] per slot, as on Windows. Pushed on the main thread only (a worker's
   wake reaches it through the main queue). */
#define SHELL_QCAP 1024
static int s_q[SHELL_QCAP][4];
static int s_qhead = 0, s_qtail = 0;

void shell_push(int t, int a, int b, int c)
{
	int next = (s_qtail + 1) % SHELL_QCAP;
	if (next == s_qhead) return;
	s_q[s_qtail][0] = t; s_q[s_qtail][1] = a; s_q[s_qtail][2] = b; s_q[s_qtail][3] = c;
	s_qtail = next;
}

/* Replace the last queued event of type `t' instead of adding one (moves, resizes), or,
   with `a_sum', add to its third field (wheel turns). Answers whether it did. */
static int shell_coalesce(int t, int a, int b, int c, int a_sum)
{
	int last = (s_qtail + SHELL_QCAP - 1) % SHELL_QCAP;
	if (s_qtail == s_qhead || s_q[last][0] != t) return 0;
	s_q[last][1] = a; s_q[last][2] = b;
	if (a_sum) s_q[last][3] += c; else s_q[last][3] = c;
	return 1;
}

int shell_next_event(int *out4)
{
	if (s_qhead == s_qtail) return 0;
	for (int i = 0; i < 4; i++) out4[i] = s_q[s_qhead][i];
	s_qhead = (s_qhead + 1) % SHELL_QCAP;
	return out4[0];
}

/* ------------------------------------------------------------------ state */

int s_shell_heartbeat_ms = 250;

@class SSView;
static NSWindow *s_window = nil;
static SSView *s_view = nil;
static cairo_surface_t *s_backing = NULL;     /* the window's image, device pixels */
static int s_quit = 0;                        /* the window is gone: the pump answers 0 */
static int s_start_hidden = 0, s_close_requests = 0, s_cursor = 0;
static int s_backdrop = 0x12141B;             /* Windows' default: RGB(18, 20, 27) */
static NSTimer *s_heartbeat = nil, *s_fast = nil, *s_dwell = nil;
static atomic_int s_wake_pending = 0;
static int s_nudged = 0;                      /* a nudge event is waiting in AppKit's queue */
static id s_target = nil;

/* An application-defined event that only makes a waiting pump return. */
static const short Shell_nudge_subtype = 0x5353;

static void shell_nudge(void)
{
	if (s_nudged || !NSApp) return;
	s_nudged = 1;
	NSEvent *e = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint
		modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:Shell_nudge_subtype data1:0 data2:0];
	[NSApp postEvent:e atStart:NO];
}

static double shell_scale(void)
{
	NSWindow *w = s_window;
	if (w) return [w backingScaleFactor];
	NSScreen *l_screen = [NSScreen mainScreen];
	return l_screen ? [l_screen backingScaleFactor] : 1.0;
}

static NSString *shell_text(const void *a_utf8)
{
	return a_utf8 ? [NSString stringWithUTF8String:(const char *)a_utf8] : @"";
}

/* ------------------------------------------------------------------ keys */

/* Windows virtual-key codes, from a Mac key event. Letters and digits by the character the
   key types without modifiers (so the layout decides, as it does on Windows); the rest by
   the physical key. 0 when the key has no Windows equivalent the shell reports. */
static int shell_vk(NSEvent *e)
{
	switch ([e keyCode]) {
		case 123: return 0x25; case 124: return 0x27; case 125: return 0x28; case 126: return 0x26;
		case 115: return 0x24; case 119: return 0x23; case 116: return 0x21; case 121: return 0x22;
		case 117: return 0x2E; case 51: return 0x08; case 36: case 76: return 0x0D;
		case 48: return 0x09; case 53: return 0x1B; case 49: return 0x20;
		case 122: return 0x70; case 120: return 0x71; case 99: return 0x72; case 118: return 0x73;
		case 96: return 0x74; case 97: return 0x75; case 98: return 0x76; case 100: return 0x77;
		case 101: return 0x78; case 109: return 0x79; case 103: return 0x7A; case 111: return 0x7B;
		case 24: return 0xBB; case 27: return 0xBD; case 69: return 0x6B; case 78: return 0x6D;
		case 41: return 0xBA; case 44: return 0xBF; case 50: return 0xC0; case 33: return 0xDB;
		case 42: return 0xDC; case 30: return 0xDD; case 39: return 0xDE; case 43: return 0xBC; case 47: return 0xBE;
		case 82: return 0x60; case 83: return 0x61; case 84: return 0x62; case 85: return 0x63; case 86: return 0x64;
		case 87: return 0x65; case 88: return 0x66; case 89: return 0x67; case 91: return 0x68; case 92: return 0x69;
	}
	NSString *l_plain = [[e charactersIgnoringModifiers] uppercaseString];
	if ([l_plain length] == 1) {
		unichar u = [l_plain characterAtIndex:0];
		if ((u >= 'A' && u <= 'Z') || (u >= '0' && u <= '9')) return u;
	}
	return 0;
}

/* Windows' policy (simple_shell.h): which key-downs the window hears as event 4. */
int shell_keydown_is_ours(int l_vk, int l_ctrl, int l_alt)
{
	if (l_vk == 0x25 || l_vk == 0x27 || l_vk == 0x24 || l_vk == 0x23 || l_vk == 0x2E || l_vk == 0x26 ||
		l_vk == 0x28 || l_vk == 0x21 || l_vk == 0x22 || l_vk == 0xBB || l_vk == 0xBD || l_vk == 0x6B || l_vk == 0x6D)
		return 1;
	if (l_vk >= 0x70 && l_vk <= 0x7B) return 1;
	if (l_ctrl && !l_alt)
		return (l_vk >= '0' && l_vk <= '9') || (l_vk >= 0x60 && l_vk <= 0x69)
			|| (l_vk >= 0xBA && l_vk <= 0xC0) || (l_vk >= 0xDB && l_vk <= 0xDE);
	return 0;
}

/* Windows' Alt-door policy, kept for the code that asks it: the keys a window claims while
   Alt is held. On a Mac, Option+letter types a character instead (keyDown). */
int shell_syskey_is_ours(int l_vk)
{
	return (l_vk >= 'A' && l_vk <= 'Z') || (l_vk >= '0' && l_vk <= '9') || l_vk == 0xBB || l_vk == 0xBD
		|| l_vk == 0x6B || l_vk == 0x6D || l_vk == 0x79 || l_vk == 0x25 || l_vk == 0x27;
}

static NSEventModifierFlags shell_flags(void) { return [NSEvent modifierFlags]; }

/* Command is the Mac's primary modifier, where Windows uses Ctrl. */
int shell_control_down(void) { return (shell_flags() & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) ? 1 : 0; }
int shell_alt_down(void) { return (shell_flags() & NSEventModifierFlagOption) ? 1 : 0; }
int shell_shift_down(void) { return (shell_flags() & NSEventModifierFlagShift) ? 1 : 0; }

/* ------------------------------------------------------------------ the view */

@interface SSView : NSView {
@public
	int right_click_pending;   /* a Control-click, reported as the right button on release */
	double wheel_rest;         /* a trackpad's fractional notches, carried to the next turn */
}
@end

@implementation SSView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { (void)e; return YES; }
- (BOOL)isOpaque { return YES; }

- (void)drawRect:(NSRect)a_rect
{
	(void)a_rect;
	[[NSColor colorWithSRGBRed:((s_backdrop >> 16) & 0xFF) / 255.0 green:((s_backdrop >> 8) & 0xFF) / 255.0
		blue:(s_backdrop & 0xFF) / 255.0 alpha:1.0] setFill];
	NSRectFill([self bounds]);
	if (!s_backing) return;
	cairo_surface_flush(s_backing);
	int w = cairo_image_surface_get_width(s_backing), h = cairo_image_surface_get_height(s_backing);
	int l_stride = cairo_image_surface_get_stride(s_backing);
	CGColorSpaceRef l_srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGDataProviderRef l_provider = CGDataProviderCreateWithData(NULL, cairo_image_surface_get_data(s_backing), (size_t)l_stride * h, NULL);
	CGImageRef l_image = CGImageCreate((size_t)w, (size_t)h, 8, 32, (size_t)l_stride, l_srgb,
		kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, l_provider, NULL, false, kCGRenderingIntentDefault);
	CGContextRef l_cg = [[NSGraphicsContext currentContext] CGContext];
	double l_scale = shell_scale();
	/* At its natural size, anchored top-left: during a live resize the program cannot draw
	   (AppKit holds the loop), and a stretched picture would be worse than a margin. */
	CGRect l_at = CGRectMake(0, 0, w / l_scale, h / l_scale);
	CGContextSaveGState(l_cg);
	CGContextTranslateCTM(l_cg, 0, l_at.size.height);
	CGContextScaleCTM(l_cg, 1, -1);
	CGContextDrawImage(l_cg, l_at, l_image);
	CGContextRestoreGState(l_cg);
	CGImageRelease(l_image);
	CGDataProviderRelease(l_provider);
	CGColorSpaceRelease(l_srgb);
}

/* The backing image follows the view's size in device pixels; Eiffel hears the new size
   (16) and is asked to draw (6), as Windows sends WM_SIZE then WM_PAINT. */
- (void)setFrameSize:(NSSize)a_size
{
	[super setFrameSize:a_size];
	[self rebuildBacking];
}
- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];
	[self rebuildBacking];
}
- (void)rebuildBacking
{
	double l_scale = shell_scale();
	NSSize l_size = [self bounds].size;
	int w = (int)lround(l_size.width * l_scale), h = (int)lround(l_size.height * l_scale);
	if (w < 1 || h < 1) return;
	if (s_backing && cairo_image_surface_get_width(s_backing) == w && cairo_image_surface_get_height(s_backing) == h) return;
	cairo_surface_t *l_new = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
	if (s_backing) {
		/* Keep the old picture until the program draws a new one. */
		cairo_t *cr = cairo_create(l_new);
		cairo_set_source_surface(cr, s_backing, 0, 0);
		cairo_paint(cr);
		cairo_destroy(cr);
		cairo_surface_destroy(s_backing);
	}
	s_backing = l_new;
	if (!shell_coalesce(16, w, h, 0, 0)) shell_push(16, w, h, 0);
	shell_push(6, 0, 0, 0);
	shell_nudge();
}

- (void)updateTrackingAreas
{
	for (NSTrackingArea *a in [[self trackingAreas] copy]) [self removeTrackingArea:a];
	[self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
		options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect | NSTrackingCursorUpdate
		owner:self userInfo:nil]];
	[super updateTrackingAreas];
}

- (NSPoint)pixelsOf:(NSEvent *)e
{
	NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
	double l_scale = shell_scale();
	return NSMakePoint(floor(p.x * l_scale), floor(p.y * l_scale));
}

- (void)applyCursor
{
	NSCursor *c;
	switch (s_cursor) {
		case 1: c = [NSCursor IBeamCursor]; break;
		case 2: c = [NSCursor pointingHandCursor]; break;
		case 3: c = [NSCursor resizeLeftRightCursor]; break;
		case 4: c = [NSCursor resizeUpDownCursor]; break;
		case 5: c = [NSCursor crosshairCursor]; break;
		default: c = [NSCursor arrowCursor];
	}
	[c set];
}
- (void)cursorUpdate:(NSEvent *)e { (void)e; [self applyCursor]; }

- (void)mouseDown:(NSEvent *)e
{
	[[self window] makeFirstResponder:self];
	NSPoint p = [self pixelsOf:e];
	if ([e modifierFlags] & NSEventModifierFlagControl) { right_click_pending = 1; return; }
	NSInteger n = [e clickCount];
	shell_push(n == 2 ? 8 : n >= 3 ? 12 : 2, (int)p.x, (int)p.y, 0);
	shell_nudge();
}
- (void)mouseUp:(NSEvent *)e
{
	NSPoint p = [self pixelsOf:e];
	if (right_click_pending) { right_click_pending = 0; shell_push(11, (int)p.x, (int)p.y, 0); }
	else shell_push(10, (int)p.x, (int)p.y, 0);
	shell_nudge();
}
- (void)mouseDragged:(NSEvent *)e
{
	if (right_click_pending) return;
	NSPoint p = [self pixelsOf:e];
	shell_push(9, (int)p.x, (int)p.y, 0);
	shell_nudge();
}
- (void)mouseMoved:(NSEvent *)e
{
	NSPoint p = [self pixelsOf:e];
	if (!shell_coalesce(13, (int)p.x, (int)p.y, 0, 0)) shell_push(13, (int)p.x, (int)p.y, 0);
	[self applyCursor];
	shell_nudge();
}
- (void)mouseExited:(NSEvent *)e { (void)e; shell_push(14, 0, 0, 0); shell_nudge(); }
- (void)rightMouseDown:(NSEvent *)e { (void)e; [[self window] makeFirstResponder:self]; }
- (void)rightMouseUp:(NSEvent *)e
{
	NSPoint p = [self pixelsOf:e];
	shell_push(11, (int)p.x, (int)p.y, 0);
	shell_nudge();
}
- (void)otherMouseDown:(NSEvent *)e
{
	NSPoint p = [self pixelsOf:e];
	shell_push(17, (int)p.x, (int)p.y, 0);
	shell_nudge();
}
/* Windows counts 120 per notch, positive away from the user. A wheel's line is one notch;
   a trackpad's points are carried until they make whole units. */
- (void)scrollWheel:(NSEvent *)e
{
	double d = [e hasPreciseScrollingDeltas] ? [e scrollingDeltaY] * 3.0 + wheel_rest : [e deltaY] * 120.0;
	int l_delta = (int)d;
	wheel_rest = [e hasPreciseScrollingDeltas] ? d - l_delta : 0.0;
	if (l_delta == 0) return;
	NSPoint p = [self pixelsOf:e];
	if (!shell_coalesce(15, (int)p.x, (int)p.y, l_delta, 1)) shell_push(15, (int)p.x, (int)p.y, l_delta);
	shell_nudge();
}

/* A key as Windows delivers it: the key-down the shell claims (4), then the character (3).
   Command+letter arrives as Ctrl+letter does there (the control code); Option+letter types
   its character, as Mac users expect. */
- (void)keyDown:(NSEvent *)e
{
	NSEventModifierFlags f = [e modifierFlags];
	int l_ctrl = (f & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) ? 1 : 0;
	int l_alt = (f & NSEventModifierFlagOption) ? 1 : 0;
	int vk = shell_vk(e);
	if (vk && (shell_keydown_is_ours(vk, l_ctrl, l_alt) || (l_alt && (vk == 0x25 || vk == 0x27))))
		shell_push(4, vk, 0, 0);
	switch (vk) {
		case 0x08: case 0x0D: case 0x09: case 0x1B:
			shell_push(3, vk, 0, 0);
			break;
		default:
			if (l_ctrl) {
				if (vk >= 'A' && vk <= 'Z') shell_push(3, vk - 'A' + 1, 0, 0);
			} else {
				NSString *s = [e characters];
				unichar u = [s length] ? [s characterAtIndex:0] : 0;
				if (!(u >= 0xF700 && u <= 0xF8FF)) [self interpretKeyEvents:@[e]];
			}
	}
	shell_nudge();
}
- (void)insertText:(id)a_text
{
	NSString *s = [a_text isKindOfClass:[NSAttributedString class]] ? [a_text string] : a_text;
	for (NSUInteger i = 0; i < [s length]; i++) shell_push(3, [s characterAtIndex:i], 0, 0);
}
- (void)doCommandBySelector:(SEL)a_selector { (void)a_selector; }
@end

/* ------------------------------------------------------------------ bring-up driver */

/* DIAGNOSTIC for bringing the Mac half up without a screen recording: when
   SHELL_APPKIT_SCRIPT is set, each heartbeat runs one step of it, through AppKit's real event
   dispatch. Steps, separated by ';':
     click:X,Y   a left click at pixel (X, Y) of the window's content
     type:TEXT   key presses typing TEXT
     shot:FILE   a PNG of what the view draws (its drawRect, at device pixels)
     close       the title bar's close button
     wait        nothing (lets the program catch up) */
static NSArray<NSString *> *s_script = nil;
static NSUInteger s_script_at = 0;

static void shell_post_mouse(NSEventType t, NSPoint a_at)
{
	NSEvent *e = [NSEvent mouseEventWithType:t location:a_at modifierFlags:0 timestamp:[[NSProcessInfo processInfo] systemUptime]
		windowNumber:[s_window windowNumber] context:nil eventNumber:0 clickCount:1 pressure:t == NSEventTypeLeftMouseDown ? 1.0 : 0.0];
	[NSApp postEvent:e atStart:NO];
}

static void shell_bringup_step(void)
{
	if (!s_script) {
		const char *l_env = getenv("SHELL_APPKIT_SCRIPT");
		if (!l_env) return;
		s_script = [[NSString stringWithUTF8String:l_env] componentsSeparatedByString:@";"];
	}
	if (s_script_at >= [s_script count] || !s_window) return;
	NSString *l_step = [s_script[s_script_at++] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSRange c = [l_step rangeOfString:@":"];
	NSString *l_verb = c.location == NSNotFound ? l_step : [l_step substringToIndex:c.location];
	NSString *l_arg = c.location == NSNotFound ? @"" : [l_step substringFromIndex:c.location + 1];
	fprintf(stderr, "shell_appkit script: %s\n", [l_step UTF8String]);
	if ([l_verb isEqualToString:@"click"]) {
		NSArray *xy = [l_arg componentsSeparatedByString:@","];
		double l_scale = shell_scale();
		NSPoint p = [s_view convertPoint:NSMakePoint([xy[0] doubleValue] / l_scale, [xy[1] doubleValue] / l_scale) toView:nil];
		shell_post_mouse(NSEventTypeLeftMouseDown, p);
		shell_post_mouse(NSEventTypeLeftMouseUp, p);
	} else if ([l_verb isEqualToString:@"type"]) {
		for (NSUInteger i = 0; i < [l_arg length]; i++) {
			NSString *ch = [l_arg substringWithRange:NSMakeRange(i, 1)];
			NSEvent *e = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
				timestamp:[[NSProcessInfo processInfo] systemUptime] windowNumber:[s_window windowNumber] context:nil
				characters:ch charactersIgnoringModifiers:ch isARepeat:NO keyCode:0xFFFF];
			[NSApp postEvent:e atStart:NO];
		}
	} else if ([l_verb isEqualToString:@"shot"]) {
		NSBitmapImageRep *r = [s_view bitmapImageRepForCachingDisplayInRect:[s_view bounds]];
		[s_view cacheDisplayInRect:[s_view bounds] toBitmapImageRep:r];
		[[r representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:l_arg atomically:YES];
	} else if ([l_verb isEqualToString:@"close"]) {
		[s_window performClose:nil];
	}
}

/* ------------------------------------------------------------------ window, app, timers */

@interface SSTarget : NSObject <NSWindowDelegate>
@end

@implementation SSTarget
- (BOOL)windowShouldClose:(NSWindow *)w
{
	(void)w;
	if (s_close_requests) { shell_push(66, 0, 0, 0); shell_nudge(); return NO; }
	return YES;
}
- (void)windowWillClose:(NSNotification *)n
{
	(void)n;
	[s_heartbeat invalidate]; s_heartbeat = nil;
	[s_fast invalidate]; s_fast = nil;
	s_close_requests = 0;
	s_quit = 1;
	s_window = nil;
	s_view = nil;
	shell_nudge();
}
- (void)heartbeat:(NSTimer *)t
{
	(void)t;
	atomic_store(&s_wake_pending, 0);
	shell_push(7, 0, 0, 0);
	shell_nudge();
	shell_bringup_step();
}
- (void)fastTick:(NSTimer *)t { (void)t; shell_push(25, 0, 0, 0); shell_nudge(); }
- (void)dwell:(NSTimer *)t { (void)t; s_dwell = nil; shell_push(55, 0, 0, 0); shell_nudge(); }
- (void)quit:(id)sender { (void)sender; shell_request_close(); }
- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)o change:(NSDictionary *)c context:(void *)x
{
	(void)k; (void)o; (void)c; (void)x;
	shell_push(53, shell_system_prefers_dark(), 0, 0);
	shell_nudge();
}
@end

static NSTimer *shell_timer(double a_ms, SEL a_selector, BOOL a_repeats)
{
	NSTimer *t = [NSTimer timerWithTimeInterval:a_ms / 1000.0 target:s_target selector:a_selector userInfo:nil repeats:a_repeats];
	[[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];   /* also in modal and tracking loops */
	return t;
}

/* The application, once: a regular app with the Mac's application menu (Hide, Quit). The
   window's own menus are drawn by simple_widgets inside it. */
static void shell_app(void)
{
	if (s_target) return;
	[NSApplication sharedApplication];
	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	s_target = [[SSTarget alloc] init];
	NSString *l_name = [[NSProcessInfo processInfo] processName];
	NSMenu *l_bar = [[NSMenu alloc] init], *l_app = [[NSMenu alloc] initWithTitle:l_name];
	NSMenuItem *l_top = [[NSMenuItem alloc] init];
	[l_app addItem:[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Hide %@", l_name] action:@selector(hide:) keyEquivalent:@"h"]];
	[l_app addItem:[NSMenuItem separatorItem]];
	NSMenuItem *l_quit = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Quit %@", l_name] action:@selector(quit:) keyEquivalent:@"q"];
	[l_quit setTarget:s_target];
	[l_app addItem:l_quit];
	[l_top setSubmenu:l_app];
	[l_bar addItem:l_top];
	[NSApp setMainMenu:l_bar];
	[NSApp addObserver:s_target forKeyPath:@"effectiveAppearance" options:0 context:NULL];
	[NSApp finishLaunching];
}

void *shell_create_window(const void *title, int px, int py, int cw, int ch)
{
	if (!pthread_main_np()) return NULL;
	shell_app();
	s_quit = 0;
	NSScreen *l_screen = [NSScreen mainScreen];
	double l_scale = l_screen ? [l_screen backingScaleFactor] : 1.0;
	NSRect l_content = NSMakeRect(0, 0, cw / l_scale, ch / l_scale);
	NSWindow *w = [[NSWindow alloc] initWithContentRect:l_content
		styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
		backing:NSBackingStoreBuffered defer:NO];
	[w setReleasedWhenClosed:NO];
	[w setTitle:shell_text(title)];
	[w setDelegate:s_target];
	[w setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
	[w setAcceptsMouseMovedEvents:YES];
	/* (px, py) are pixels from the top-left of the main screen, as on Windows; far off
	   screen (CW_USEDEFAULT) means "where the system likes". */
	if (l_screen && px > -10000 && py > -10000 && px < 100000 && py < 100000) {
		NSRect f = [l_screen frame];
		[w setFrameTopLeftPoint:NSMakePoint(f.origin.x + px / l_scale, NSMaxY(f) - py / l_scale)];
	} else [w center];
	s_window = w;
	s_view = [[SSView alloc] initWithFrame:l_content];
	[w setContentView:s_view];
	[w makeFirstResponder:s_view];
	[s_view rebuildBacking];
	if (!s_start_hidden) [w makeKeyAndOrderFront:nil];
	s_heartbeat = shell_timer(s_shell_heartbeat_ms, @selector(heartbeat:), YES);
	return (__bridge void *)w;
}

void shell_close_window(void) { if (s_window) [s_window close]; }
void shell_request_close(void) { if (s_window) [s_window performClose:nil]; }
void shell_set_close_requests(int on) { s_close_requests = on ? 1 : 0; }
void shell_set_start_hidden(int l_on) { s_start_hidden = l_on ? 1 : 0; }
void shell_set_caption(const void *l_title) { if (s_window) [s_window setTitle:shell_text(l_title)]; }
int shell_main_is_shown(void) { return s_window && [s_window isVisible] ? 1 : 0; }
void shell_show_main(int l_on)
{
	if (!s_window) return;
	if (l_on) { [s_window makeKeyAndOrderFront:nil]; [NSApp activate]; }
	else [s_window orderOut:nil];
}
void shell_set_backdrop(void *hwnd, int rgb) { (void)hwnd; s_backdrop = rgb & 0xFFFFFF; [s_view setNeedsDisplay:YES]; }
void shell_set_cursor_kind(int k) { s_cursor = k; [s_view applyCursor]; }

/* A .ico (or any image macOS reads) as the Dock icon. */
void shell_set_window_icon(const void *path)
{
	NSImage *i = [[NSImage alloc] initWithContentsOfFile:shell_text(path)];
	if (i) [NSApp setApplicationIconImage:i];
}

/* A font file for this process, as AddFontResourceEx(FR_PRIVATE): 1 on success. */
int shell_add_font(const char *path)
{
	NSURL *u = [NSURL fileURLWithPath:shell_text(path)];
	return CTFontManagerRegisterFontsForURL((__bridge CFURLRef)u, kCTFontManagerScopeProcess, NULL) ? 1 : 0;
}

void shell_set_heartbeat(int l_ms)
{
	s_shell_heartbeat_ms = l_ms;
	if (s_heartbeat) { [s_heartbeat invalidate]; s_heartbeat = shell_timer(l_ms, @selector(heartbeat:), YES); }
}
void shell_set_fast_timer(int ms)
{
	if (!s_window || ms <= 0) return;
	[s_fast invalidate];
	s_fast = shell_timer(ms, @selector(fastTick:), YES);
}
void shell_kill_fast_timer(void) { [s_fast invalidate]; s_fast = nil; }
void shell_arm_dwell_timer(int l_ms)
{
	if (l_ms <= 0) return;
	[s_dwell invalidate];
	s_dwell = shell_timer(l_ms, @selector(dwell:), NO);
}
void shell_cancel_dwell_timer(void) { [s_dwell invalidate]; s_dwell = nil; }
int shell_dwell_is_armed(void) { return s_dwell ? 1 : 0; }

/* ------------------------------------------------------------------ drawing */

/* No device context on a Mac: the "DC" is the window's backing image, which simple_cairo's
   off-Windows surface-for-DC references; releasing it shows it. */
void *shell_get_dc(void) { return s_window ? (void *)s_backing : NULL; }
void shell_release_dc(void *dc) { if (dc && s_view) [s_view setNeedsDisplay:YES]; }

/* ------------------------------------------------------------------ the pump */

/* One AppKit event to the app, unless it is the shell's own nudge. */
static void shell_send(NSEvent *e)
{
	if ([e type] == NSEventTypeApplicationDefined && [e subtype] == Shell_nudge_subtype) { s_nudged = 0; return; }
	[NSApp sendEvent:e];
}

/* Wait for one event and handle it: 0 once the window is gone (Windows' WM_QUIT). */
int shell_pump(void)
{
	if (s_quit || !NSApp) return 0;
	@autoreleasepool {
		NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantFuture] inMode:NSDefaultRunLoopMode dequeue:YES];
		if (e) shell_send(e);
	}
	return s_quit ? 0 : 1;
}

/* Handle every event already waiting: 0 once the window is gone. */
int shell_pump_pending(void)
{
	if (!NSApp) return s_quit ? 0 : 1;
	@autoreleasepool {
		NSEvent *e;
		while (!s_quit && (e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantPast] inMode:NSDefaultRunLoopMode dequeue:YES]))
			shell_send(e);
	}
	return s_quit ? 0 : 1;
}

/* Handle events until one is queued for Eiffel or `ms' has passed: 0 once the window is gone. */
int shell_pump_until(int ms)
{
	if (!NSApp) return s_quit ? 0 : 1;
	NSDate *l_end = [NSDate dateWithTimeIntervalSinceNow:ms / 1000.0];
	for (;;) {
		if (!shell_pump_pending()) return 0;
		if (s_qhead != s_qtail) return 1;
		if ([l_end timeIntervalSinceNow] <= 0) return 1;
		@autoreleasepool {
			NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:l_end inMode:NSDefaultRunLoopMode dequeue:YES];
			if (e) shell_send(e);
		}
		if (s_quit) return 0;
	}
}

/* ------------------------------------------------------------------ the wake */

/* From any thread: make the pump return with event 54. 1 sent, 2 one already on its way,
   0 no pump to wake. The main queue reaches the pump inside modal and tracking loops too. */
int shell_wake(void)
{
	int l_expected = 0;
	if (!atomic_compare_exchange_strong(&s_wake_pending, &l_expected, 1)) return 2;
	if (!NSApp) { atomic_store(&s_wake_pending, 0); return 0; }
	dispatch_async(dispatch_get_main_queue(), ^{
		atomic_store(&s_wake_pending, 0);
		shell_push(54, 0, 0, 0);
		shell_nudge();
	});
	return 1;
}
void shell_claim_pump_thread(int l_on) { (void)l_on; atomic_store(&s_wake_pending, 0); }
/* AppKit's pump is always the main thread's. */
int shell_is_pump_thread(void) { return pthread_main_np() ? 1 : 0; }

/* ------------------------------------------------------------------ clipboard */

int shell_clip_set(const void *s)
{
	NSPasteboard *p = [NSPasteboard generalPasteboard];
	[p clearContents];
	return [p setString:shell_text(s) forType:NSPasteboardTypeString] ? 1 : 0;
}

/* UTF-16 into `buf' (the caller reads 16-bit units), at most cap - 1 and a terminator. */
int shell_clip_get(void *buf, int cap)
{
	NSString *s = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
	if (!s || cap < 1) return 0;
	NSUInteger n = MIN([s length], (NSUInteger)(cap - 1));
	[s getCharacters:(unichar *)buf range:NSMakeRange(0, n)];
	((unichar *)buf)[n] = 0;
	return (int)n;
}
int shell_clip_has_text(void)
{
	return [[NSPasteboard generalPasteboard] availableTypeFromArray:@[NSPasteboardTypeString]] ? 1 : 0;
}

/* ------------------------------------------------------------------ appearance */

int shell_system_prefers_dark(void)
{
	shell_app();
	NSAppearanceName n = [[NSApp effectiveAppearance] bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
	return [n isEqualToString:NSAppearanceNameDarkAqua] ? 1 : 0;
}
int shell_high_contrast_on(void) { return [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldIncreaseContrast] ? 1 : 0; }
int shell_reduces_motion(void) { return [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion] ? 1 : 0; }
int shell_set_dark_title_bar(void *hwnd, int l_on)
{
	NSWindow *w = (__bridge NSWindow *)hwnd;
	if (!w) return 0;
	[w setAppearance:[NSAppearance appearanceNamed:l_on ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
	return 1;
}

/* ------------------------------------------------------------------ Windows names the Eiffel inline C uses */

unsigned int GetTickCount(void) { return (unsigned int)(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000ULL); }
int SetProcessDPIAware(void) { return 1; }   /* a Mac process is always told its scale */
HDC GetDC(HWND a_window) { (void)a_window; return (HDC)1; }
int ReleaseDC(HWND a_window, HDC a_dc) { (void)a_window; (void)a_dc; return 1; }
int GetDeviceCaps(HDC a_dc, int a_index)
{
	(void)a_dc;
	return a_index == LOGPIXELSX ? (int)lround(96.0 * shell_scale()) : 0;
}
unsigned int GetLogicalDrives(void) { return 0; }   /* no drive letters */

/* A window's frame and the pointer, in pixels from the main screen's top-left. */
static NSScreen *shell_main_screen(void) { return [[NSScreen screens] count] ? [NSScreen screens][0] : nil; }
int IsWindowVisible(HWND a_window) { return a_window && [(__bridge NSWindow *)a_window isVisible] ? 1 : 0; }
int GetCursorPos(POINT *a_point)
{
	NSScreen *l_screen = shell_main_screen();
	if (!a_point || !l_screen) return 0;
	double l_scale = [l_screen backingScaleFactor];
	NSPoint p = [NSEvent mouseLocation];
	a_point->x = (int32_t)lround(p.x * l_scale);
	a_point->y = (int32_t)lround((NSMaxY([l_screen frame]) - p.y) * l_scale);
	return 1;
}
int GetWindowRect(HWND a_window, RECT *a_rect)
{
	NSScreen *l_screen = shell_main_screen();
	if (!a_window || !a_rect || !l_screen) return 0;
	double l_scale = [l_screen backingScaleFactor], l_top = NSMaxY([l_screen frame]);
	NSRect f = [(__bridge NSWindow *)a_window frame];
	a_rect->left = (int32_t)lround(f.origin.x * l_scale);
	a_rect->top = (int32_t)lround((l_top - NSMaxY(f)) * l_scale);
	a_rect->right = (int32_t)lround(NSMaxX(f) * l_scale);
	a_rect->bottom = (int32_t)lround((l_top - f.origin.y) * l_scale);
	return 1;
}
int PtInRect(const RECT *a_rect, POINT a_point)
{
	return a_rect && a_point.x >= a_rect->left && a_point.x < a_rect->right && a_point.y >= a_rect->top && a_point.y < a_rect->bottom;
}

/* The work area (the screen less the menu bar and Dock), in pixels from the main screen's
   top-left, as SPI_GETWORKAREA answers it. */
int SystemParametersInfoW(unsigned int a_action, unsigned int a_param, void *a_out, unsigned int a_ini)
{
	(void)a_param; (void)a_ini;
	NSScreen *l_screen = [NSScreen mainScreen];
	if (a_action != SPI_GETWORKAREA || !a_out || !l_screen) return 0;
	double l_scale = [l_screen backingScaleFactor];
	NSRect f = [l_screen frame], v = [l_screen visibleFrame];
	RECT *r = (RECT *)a_out;
	r->left = (int32_t)lround((v.origin.x - f.origin.x) * l_scale);
	r->top = (int32_t)lround((NSMaxY(f) - NSMaxY(v)) * l_scale);
	r->right = (int32_t)lround((NSMaxX(v) - f.origin.x) * l_scale);
	r->bottom = (int32_t)lround((NSMaxY(f) - v.origin.y) * l_scale);
	return 1;
}
