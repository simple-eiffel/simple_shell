/* shell_appkit.m - the macOS half of simple_shell (M1): the window, its pump and event
   queue, keys, the pointer, timers, the wake, the clipboard, appearance and the screen.
   The contract is simple_shell.h's (the Windows half) as summarized in shell_appkit.h;
   entry points not written here yet are generated as "not available" stubs by
   Clib/Makefile (shell_appkit_stubs.c). */

#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Carbon/Carbon.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
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

/* As `shell_coalesce', for a panel's event: only the same panel's (`c' is the slot). */
static int shell_coalesce_slot(int t, int a, int b, int a_slot)
{
	int last = (s_qtail + SHELL_QCAP - 1) % SHELL_QCAP;
	if (s_qtail == s_qhead || s_q[last][0] != t || s_q[last][3] != a_slot) return 0;
	s_q[last][1] = a; s_q[last][2] = b;
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
static SSView *s_view = nil;                  /* the main window's view (slot -1) */
#define SHELL_PANELS 8
static NSWindow *s_panel[SHELL_PANELS];       /* framed panels: windows of their own */
static NSTimer *s_panel_settle[SHELL_PANELS]; /* a move's end, after the last move notice */
static int s_panel_accepts[SHELL_PANELS];     /* does the panel take dropped files (event 50)? */
/* Each panel's settings, as the Windows half keeps them. */
static int s_panel_framed[SHELL_PANELS], s_panel_document[SHELL_PANELS], s_panel_alpha[SHELL_PANELS];
static int s_panel_drag[SHELL_PANELS], s_panel_press_drag[SHELL_PANELS], s_panel_axis[SHELL_PANELS];
static int s_panel_side_grip[SHELL_PANELS], s_panel_bottom_grip[SHELL_PANELS], s_panel_grip[SHELL_PANELS];
static int s_panel_minw[SHELL_PANELS], s_panel_minh[SHELL_PANELS];
/* Windows' hit-test codes, which the Eiffel reads back by number. */
enum { Shell_ht_caption = 2, Shell_ht_left = 10, Shell_ht_right = 11, Shell_ht_top = 12, Shell_ht_topleft = 13,
	Shell_ht_topright = 14, Shell_ht_bottom = 15, Shell_ht_bottomleft = 16, Shell_ht_bottomright = 17 };
static void shell_panel_track(int a_slot, int a_code);
/* View slots that are not the main window (-1) or a panel (0..7). */
enum { Shell_slot_overlay = -2, Shell_slot_strip = -3 };
static void shell_overlay_dismiss(void);
static void shell_strip_drag(void);
static NSRect shell_virtual_desktop(double *a_scale);
static NSCursor *shell_panel_cursor(int a_slot, int a_x, int a_y);
/* The last drop's paths, UTF-16 and one per line, as the Windows half keeps them for
   `shell_drop_paths'. */
#define SHELL_DROPS_CAP 16384
static unichar s_drops[SHELL_DROPS_CAP];
static int s_drops_len = 0;
static int s_quit = 0;                        /* the window is gone: the pump answers 0 */
static int s_start_hidden = 0, s_close_requests = 0, s_cursor = 0;
static int s_backdrop = 0x12141B;             /* Windows' default: RGB(18, 20, 27) */
static NSTimer *s_heartbeat = nil, *s_fast = nil, *s_dwell = nil;
static atomic_int s_wake_pending = 0;
static atomic_int s_pump_claimed = 0;   /* a host claimed the pump (shell_claim_pump_thread) */
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

/* Keep `a_paths' (one per line) for `shell_drop_paths'; answers how many paths. */
static int shell_keep_drops(NSString *a_paths)
{
	NSUInteger n = MIN([a_paths length], (NSUInteger)SHELL_DROPS_CAP - 1);
	[a_paths getCharacters:s_drops range:NSMakeRange(0, n)];
	s_drops_len = (int)n;
	s_drops[n] = 0;
	return n == 0 ? 0 : (int)[[a_paths componentsSeparatedByString:@"\n"] count];
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
	int slot;                  /* -1: the main window; 0..7: a framed panel */
	cairo_surface_t *backing;  /* the window's image, device pixels: the "DC" */
	int fill;                  /* painted where there is no image yet (RGB) */
	int right_click_pending;   /* a Control-click, reported as the right button on release */
	double wheel_rest;         /* a trackpad's fractional notches, carried to the next turn */
}
@end

/* An event from view `v': the main window's numbers as they are; a panel's as Windows
   numbers them for panels (simple_shell.h, shell_panel_proc), with the slot in `c'. `a_mode'
   0 adds, 1 replaces the same queued event, 2 adds a wheel turn to it. */
static void shell_emit(SSView *v, int t, int a, int b, int c, int a_mode)
{
	if (v->slot == Shell_slot_overlay) {
		/* the overlay: 31 move, 32 press, 33 release, 35 expose (keys in keyDown) */
		switch (t) {
			case 13: case 9: shell_push(31, a, b, 0); break;
			case 2: case 8: case 12: shell_push(32, a, b, 0); break;
			case 10: shell_push(33, a, b, 0); break;
			case 6: shell_push(35, 0, 0, 0); break;
		}
		shell_nudge();
		return;
	}
	if (v->slot == Shell_slot_strip) {
		/* the strip: 21 press, 23 expose (22 when a drag ends) */
		if (t == 2 || t == 8 || t == 12) shell_push(21, a, b, 0);
		else if (t == 6) shell_push(23, 0, 0, 0);
		shell_nudge();
		return;
	}
	if (v->slot < 0) {
		if (a_mode == 0 || !shell_coalesce(t, a, b, c, a_mode == 2)) shell_push(t, a, b, c);
	} else {
		int l_slot = v->slot, pt = 0;
		switch (t) {
			case 2: case 12: pt = 41; break;
			case 8: pt = 64; break;
			case 10: pt = 42; break;
			case 9: case 13: pt = 43; break;
			case 14: pt = 65; break;
			case 3: pt = 61; break;
			case 4: pt = 60; break;
			case 6: pt = 44; break;
			case 16: pt = 48; break;
			case 46: pt = 46; break;
			case 15: shell_push(45, c, 0, l_slot); break;   /* a panel's wheel: the delta alone */
		}
		if (pt && !((pt == 43 || pt == 48) && shell_coalesce_slot(pt, a, b, l_slot))) shell_push(pt, a, b, l_slot);
	}
	shell_nudge();
}

@implementation SSView
- (instancetype)initWithFrame:(NSRect)r slot:(int)a_slot
{
	self = [super initWithFrame:r];
	if (self) { slot = a_slot; fill = s_backdrop; }
	return self;
}
- (void)dealloc { if (backing) cairo_surface_destroy(backing); }
- (double)scale { NSWindow *w = [self window]; return w ? [w backingScaleFactor] : shell_scale(); }
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { (void)e; return YES; }
- (BOOL)isOpaque { return YES; }

- (void)drawRect:(NSRect)a_rect
{
	(void)a_rect;
	int l_fill = slot < 0 ? s_backdrop : fill;
	[[NSColor colorWithSRGBRed:((l_fill >> 16) & 0xFF) / 255.0 green:((l_fill >> 8) & 0xFF) / 255.0
		blue:(l_fill & 0xFF) / 255.0 alpha:1.0] setFill];
	NSRectFill([self bounds]);
	if (!backing) return;
	cairo_surface_flush(backing);
	int w = cairo_image_surface_get_width(backing), h = cairo_image_surface_get_height(backing);
	int l_stride = cairo_image_surface_get_stride(backing);
	CGColorSpaceRef l_srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGDataProviderRef l_provider = CGDataProviderCreateWithData(NULL, cairo_image_surface_get_data(backing), (size_t)l_stride * h, NULL);
	CGImageRef l_image = CGImageCreate((size_t)w, (size_t)h, 8, 32, (size_t)l_stride, l_srgb,
		kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, l_provider, NULL, false, kCGRenderingIntentDefault);
	CGContextRef l_cg = [[NSGraphicsContext currentContext] CGContext];
	double l_scale = [self scale];
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
	double l_scale = [self scale];
	NSSize l_size = [self bounds].size;
	int w = (int)lround(l_size.width * l_scale), h = (int)lround(l_size.height * l_scale);
	if (w < 1 || h < 1) return;
	if (backing && cairo_image_surface_get_width(backing) == w && cairo_image_surface_get_height(backing) == h) return;
	cairo_surface_t *l_new = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
	if (backing) {
		/* Keep the old picture until the program draws a new one. */
		cairo_t *cr = cairo_create(l_new);
		cairo_set_source_surface(cr, backing, 0, 0);
		cairo_paint(cr);
		cairo_destroy(cr);
		cairo_surface_destroy(backing);
	}
	backing = l_new;
	shell_emit(self, 16, w, h, 0, 1);
	shell_emit(self, 6, 0, 0, 0, 0);
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
	double l_scale = [self scale];
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
	if (slot == Shell_slot_strip) {
		/* A press reports 21 and drags the strip, except on its own buttons (the top right,
		   90 by 26 pixels), whose presses stay clicks, as on Windows. */
		shell_emit(self, 2, (int)p.x, (int)p.y, 0, 0);
		int l_w = backing ? cairo_image_surface_get_width(backing) : 0;
		if (!(p.y < 26 && p.x >= l_w - 90)) shell_strip_drag();
		return;
	}
	if (slot >= 0) {
		int l_code = shell_panel_press_code(slot, (int)p.x, (int)p.y, ([e modifierFlags] & NSEventModifierFlagShift) ? 1 : 0);
		if (l_code != 0) { shell_panel_track(slot, l_code); return; }
	}
	NSInteger n = [e clickCount];
	shell_emit(self, n == 2 ? 8 : n >= 3 ? 12 : 2, (int)p.x, (int)p.y, 0, 0);
}
- (void)mouseUp:(NSEvent *)e
{
	NSPoint p = [self pixelsOf:e];
	if (right_click_pending) {
		right_click_pending = 0;
		if (slot < 0) shell_emit(self, 11, (int)p.x, (int)p.y, 0, 0);
		else shell_emit(self, 46, (int)p.x, (int)p.y, 0, 0);
	} else shell_emit(self, 10, (int)p.x, (int)p.y, 0, 0);
}
- (void)mouseDragged:(NSEvent *)e
{
	if (right_click_pending) return;
	NSPoint p = [self pixelsOf:e];
	shell_emit(self, 9, (int)p.x, (int)p.y, 0, 0);
}
- (void)mouseMoved:(NSEvent *)e
{
	NSPoint p = [self pixelsOf:e];
	shell_emit(self, 13, (int)p.x, (int)p.y, 0, 1);
	NSCursor *l_grip = slot >= 0 ? shell_panel_cursor(slot, (int)p.x, (int)p.y) : nil;
	if (l_grip) [l_grip set]; else [self applyCursor];
}
- (void)mouseExited:(NSEvent *)e { (void)e; shell_emit(self, 14, 0, 0, 0, 0); }
/* The main window hears the right button on release (11); a panel on press (46), as on Windows. */
- (void)rightMouseDown:(NSEvent *)e
{
	if (slot == Shell_slot_overlay) { shell_overlay_dismiss(); return; }   /* a right press cancels the pick */
	[[self window] makeFirstResponder:self];
	if (slot >= 0) { NSPoint p = [self pixelsOf:e]; shell_emit(self, 46, (int)p.x, (int)p.y, 0, 0); }
}
- (void)rightMouseUp:(NSEvent *)e
{
	if (slot >= 0) return;
	NSPoint p = [self pixelsOf:e];
	shell_emit(self, 11, (int)p.x, (int)p.y, 0, 0);
}
- (void)otherMouseDown:(NSEvent *)e
{
	if (slot >= 0) return;
	NSPoint p = [self pixelsOf:e];
	shell_emit(self, 17, (int)p.x, (int)p.y, 0, 0);
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
	shell_emit(self, 15, (int)p.x, (int)p.y, l_delta, 2);
}

/* A key as Windows delivers it: the key-down the shell claims (4), then the character (3).
   Command+letter arrives as Ctrl+letter does there (the control code); Option+letter types
   its character, as Mac users expect. */
- (void)keyDown:(NSEvent *)e
{
	if (slot == Shell_slot_overlay) {
		/* Escape frees the screen in C first, then reports 34; Return accepts (36); the
		   arrows adjust (37, the virtual key). */
		int l_vk = shell_vk(e);
		if (l_vk == 0x1B) shell_overlay_dismiss();
		else if (l_vk == 0x0D) { shell_push(36, 0, 0, 0); shell_nudge(); }
		else if (l_vk >= 0x25 && l_vk <= 0x28) { shell_push(37, l_vk, 0, 0); shell_nudge(); }
		return;
	}
	NSEventModifierFlags f = [e modifierFlags];
	int l_ctrl = (f & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) ? 1 : 0;
	int l_alt = (f & NSEventModifierFlagOption) ? 1 : 0;
	int vk = shell_vk(e);
	if (vk && (shell_keydown_is_ours(vk, l_ctrl, l_alt) || (l_alt && (vk == 0x25 || vk == 0x27))))
		shell_emit(self, 4, vk, 0, 0, 0);
	switch (vk) {
		case 0x08: case 0x0D: case 0x09: case 0x1B:
			shell_emit(self, 3, vk, 0, 0, 0);
			break;
		default:
			if (l_ctrl) {
				if (vk >= 'A' && vk <= 'Z') shell_emit(self, 3, vk - 'A' + 1, 0, 0, 0);
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
	for (NSUInteger i = 0; i < [s length]; i++) shell_emit(self, 3, [s characterAtIndex:i], 0, 0, 0);
}
- (void)doCommandBySelector:(SEL)a_selector { (void)a_selector; }

/* Files dropped from Finder: the main window always takes them (event 18: x, y, count), a
   panel when it accepts files (event 50: x, y, slot). */
- (BOOL)takesDrops { return slot < 0 || (slot < SHELL_PANELS && s_panel_accepts[slot]); }
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)a_info { (void)a_info; return [self takesDrops] ? NSDragOperationCopy : NSDragOperationNone; }
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)a_info { (void)a_info; return [self takesDrops] ? NSDragOperationCopy : NSDragOperationNone; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)a_info
{
	if (![self takesDrops]) return NO;
	NSArray<NSURL *> *l_urls = [[a_info draggingPasteboard] readObjectsForClasses:@[[NSURL class]]
		options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
	if ([l_urls count] == 0) return NO;
	NSMutableArray<NSString *> *l_paths = [NSMutableArray array];
	for (NSURL *u in l_urls) [l_paths addObject:[u path]];
	int n = shell_keep_drops([l_paths componentsJoinedByString:@"\n"]);
	NSPoint p = [self convertPoint:[a_info draggingLocation] fromView:nil];
	double l_scale = [self scale];
	int x = (int)floor(p.x * l_scale), y = (int)floor(p.y * l_scale);
	if (slot < 0) shell_push(18, x, y, n); else shell_push(50, x, y, slot);
	shell_nudge();
	return YES;
}
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

static int shell_panel_slot_of(NSWindow *w)
{
	for (int i = 0; i < SHELL_PANELS; i++) if (w && s_panel[i] == w) return i;
	return -1;
}

@implementation SSTarget
/* The main window closes unless close requests are events (66); a framed panel's close is
   always a request (62), as on Windows: the program decides. */
- (BOOL)windowShouldClose:(NSWindow *)w
{
	int l_slot = shell_panel_slot_of(w);
	if (l_slot >= 0) { shell_push(62, 0, 0, l_slot); shell_nudge(); return NO; }
	if (s_close_requests) { shell_push(66, 0, 0, 0); shell_nudge(); return NO; }
	return YES;
}
- (void)windowDidBecomeKey:(NSNotification *)n
{
	int l_slot = shell_panel_slot_of([n object]);
	if (l_slot >= 0) { shell_push(63, 1, 0, l_slot); shell_nudge(); }
}
- (void)windowDidResignKey:(NSNotification *)n
{
	int l_slot = shell_panel_slot_of([n object]);
	if (l_slot >= 0) { shell_push(63, 0, 0, l_slot); shell_nudge(); }
}
/* A panel being moved: where it is now (49, coalesced), and once it has been still for a
   moment, where it ended (47): AppKit has no end-of-move notice. */
- (void)windowDidMove:(NSNotification *)n
{
	int l_slot = shell_panel_slot_of([n object]);
	if (l_slot < 0) return;
	RECT r;
	GetWindowRect((__bridge HWND)s_panel[l_slot], &r);
	if (!shell_coalesce_slot(49, r.left, r.top, l_slot)) shell_push(49, r.left, r.top, l_slot);
	[s_panel_settle[l_slot] invalidate];
	s_panel_settle[l_slot] = [NSTimer scheduledTimerWithTimeInterval:0.15 target:self selector:@selector(panelSettled:) userInfo:@(l_slot) repeats:NO];
	shell_nudge();
}
- (void)panelSettled:(NSTimer *)t
{
	int l_slot = [[t userInfo] intValue];
	s_panel_settle[l_slot] = nil;
	if (!s_panel[l_slot]) return;
	RECT r;
	GetWindowRect((__bridge HWND)s_panel[l_slot], &r);
	shell_push(47, r.left, r.top, l_slot);
	shell_nudge();
}
- (void)windowWillClose:(NSNotification *)n
{
	if ([n object] != s_window) return;   /* a panel: shell_panel_close keeps the books */
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
/* Increase Contrast (56) and Reduce Motion (57), each when it actually changed. */
- (void)displayOptionsChanged:(NSNotification *)n
{
	static int l_contrast = -1, l_motion = -1;
	(void)n;
	int c = shell_high_contrast_on(), m = shell_reduces_motion();
	if (l_contrast >= 0 && c != l_contrast) shell_push(56, c, 0, 0);
	if (l_motion >= 0 && m != l_motion) shell_push(57, m, 0, 0);
	l_contrast = c; l_motion = m;
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
	[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:s_target selector:@selector(displayOptionsChanged:)
		name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
	[s_target displayOptionsChanged:nil];   /* the starting values */
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
	s_view = [[SSView alloc] initWithFrame:l_content slot:-1];
	[w setContentView:s_view];
	[s_view registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
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

/* ------------------------------------------------------------------ framed panels */

/* A framed panel is a window of its own (simple_widgets' floating windows). Rectangles are
   the window's frame in pixels from the main screen's top-left, as on Windows; the client
   size is the content's. Unframed panels (borderless, always on top, never active) are not
   written yet: `shell_panel_open' answers -1. */
static NSScreen *shell_first_screen(void) { return [[NSScreen screens] count] ? [NSScreen screens][0] : [NSScreen mainScreen]; }
static NSRect shell_frame_of(int x, int y, int w, int h)
{
	NSScreen *l_screen = shell_first_screen();
	double l_scale = l_screen ? [l_screen backingScaleFactor] : 1.0, l_top = l_screen ? NSMaxY([l_screen frame]) : 0;
	return NSMakeRect(x / l_scale, l_top - (y + h) / l_scale, w / l_scale, h / l_scale);
}
static SSView *shell_panel_view(int l_slot)
{
	return l_slot >= 0 && l_slot < SHELL_PANELS && s_panel[l_slot] ? (SSView *)[s_panel[l_slot] contentView] : nil;
}

/* A panel's window and view in `l_slot', with the settings a new panel starts from. */
static int shell_panel_adopt(NSWindow *w, int l_slot, int l_framed, int l_document)
{
	[w setReleasedWhenClosed:NO];
	[w setDelegate:s_target];
	[w setAcceptsMouseMovedEvents:YES];
	s_panel[l_slot] = w;
	s_panel_framed[l_slot] = l_framed; s_panel_document[l_slot] = l_document; s_panel_alpha[l_slot] = 255;
	s_panel_drag[l_slot] = s_panel_press_drag[l_slot] = s_panel_axis[l_slot] = 0;
	s_panel_side_grip[l_slot] = s_panel_bottom_grip[l_slot] = s_panel_grip[l_slot] = 0;
	s_panel_minw[l_slot] = s_panel_minh[l_slot] = 0;
	s_panel_accepts[l_slot] = 0;
	SSView *v = [[SSView alloc] initWithFrame:[[w contentView] frame] slot:l_slot];
	[w setContentView:v];
	[v registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
	[w makeFirstResponder:v];
	[v rebuildBacking];
	return l_slot;
}
static int shell_panel_free_slot(void)
{
	for (int i = 0; i < SHELL_PANELS; i++) if (!s_panel[i]) return i;
	return -1;
}

/* A framed panel. A tool panel (`l_document' 0) is a utility panel: the small title bar, no
   minimize, as Windows' tool window. A document window (1) is an ordinary window, as Windows'
   unowned document window with its own taskbar button. */
int shell_panel_open_framed_as(int l_x, int l_y, int l_w, int l_h, const void *l_title, int l_document)
{
	int l_slot = shell_panel_free_slot();
	if (l_slot < 0 || l_w <= 0 || l_h <= 0 || !pthread_main_np()) return -1;
	shell_app();
	NSRect f = shell_frame_of(l_x, l_y, l_w, l_h);
	NSWindow *w;
	if (l_document) {
		NSUInteger l_style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
		w = [[NSWindow alloc] initWithContentRect:[NSWindow contentRectForFrameRect:f styleMask:l_style] styleMask:l_style backing:NSBackingStoreBuffered defer:NO];
	} else {
		NSUInteger l_style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow;
		NSPanel *l_panel = [[NSPanel alloc] initWithContentRect:[NSPanel contentRectForFrameRect:f styleMask:l_style] styleMask:l_style backing:NSBackingStoreBuffered defer:NO];
		[l_panel setHidesOnDeactivate:NO];   /* a floating window keeps its content in view, as on Windows */
		[l_panel setBecomesKeyOnlyIfNeeded:NO];
		/* A utility panel floats above every window by default; Windows' tool window is owned,
		   not topmost, so this one stays at the normal level. */
		[l_panel setFloatingPanel:NO];
		[l_panel setLevel:NSNormalWindowLevel];
		w = l_panel;
	}
	[w setTitle:shell_text(l_title)];
	return shell_panel_adopt(w, l_slot, 1, l_document ? 1 : 0);
}
int shell_panel_open_framed(int l_x, int l_y, int l_w, int l_h, const void *l_title)
{
	return shell_panel_open_framed_as(l_x, l_y, l_w, l_h, l_title, 0);
}
HWND shell_panel_hwnd(int l_slot) { return (l_slot >= 0 && l_slot < SHELL_PANELS) ? (__bridge HWND)s_panel[l_slot] : NULL; }
void shell_panel_place(int l_slot, int l_x, int l_y, int l_w, int l_h)
{
	if (shell_panel_view(l_slot) && l_w > 0 && l_h > 0) [s_panel[l_slot] setFrame:shell_frame_of(l_x, l_y, l_w, l_h) display:YES];
}
void shell_panel_show(int l_slot, int l_x, int l_y, int l_w, int l_h)
{
	if (!shell_panel_view(l_slot)) return;
	shell_panel_place(l_slot, l_x, l_y, l_w, l_h);
	[s_panel[l_slot] orderFront:nil];   /* shown, not made active (SWP_NOACTIVATE) */
}
void shell_panel_hide(int l_slot) { if (shell_panel_view(l_slot)) [s_panel[l_slot] orderOut:nil]; }
int shell_panel_is_visible(int l_slot) { return shell_panel_view(l_slot) && [s_panel[l_slot] isVisible] ? 1 : 0; }
void shell_panel_close(int l_slot)
{
	if (!shell_panel_view(l_slot)) return;
	NSWindow *w = s_panel[l_slot];
	s_panel[l_slot] = nil;
	s_panel_accepts[l_slot] = 0;
	[s_panel_settle[l_slot] invalidate]; s_panel_settle[l_slot] = nil;
	[w setDelegate:nil];
	[w close];
}
void shell_panel_set_title(int l_slot, const void *l_title) { if (shell_panel_view(l_slot)) [s_panel[l_slot] setTitle:shell_text(l_title)]; }
void shell_panel_invalidate(int l_slot) { [shell_panel_view(l_slot) setNeedsDisplay:YES]; }
void *shell_panel_dc(int l_slot) { SSView *v = shell_panel_view(l_slot); return v ? (void *)v->backing : NULL; }
void shell_panel_release_dc(int l_slot, void *l_dc) { if (l_dc) [shell_panel_view(l_slot) setNeedsDisplay:YES]; }
void shell_panel_client_size(int l_slot, int *l_w, int *l_h)
{
	SSView *v = shell_panel_view(l_slot);
	if (!v || !v->backing) return;
	*l_w = cairo_image_surface_get_width(v->backing);
	*l_h = cairo_image_surface_get_height(v->backing);
}
void shell_panel_rect(int l_slot, int *l_x, int *l_y, int *l_w, int *l_h)
{
	RECT r;
	if (!shell_panel_view(l_slot) || !GetWindowRect((__bridge HWND)s_panel[l_slot], &r)) return;
	*l_x = r.left; *l_y = r.top; *l_w = r.right - r.left; *l_h = r.bottom - r.top;
}
/* The panel's ground, and its image painted over with it (the Windows body fills the DC). */
void shell_panel_fill(int l_slot, int l_rgb)
{
	SSView *v = shell_panel_view(l_slot);
	if (!v) return;
	v->fill = l_rgb & 0xFFFFFF;
	if (v->backing) {
		cairo_t *cr = cairo_create(v->backing);
		cairo_set_source_rgb(cr, ((l_rgb >> 16) & 0xFF) / 255.0, ((l_rgb >> 8) & 0xFF) / 255.0, (l_rgb & 0xFF) / 255.0);
		cairo_paint(cr);
		cairo_destroy(cr);
	}
	[v setNeedsDisplay:YES];
}
/* An unframed panel: borderless, above other windows, never made active (WS_EX_TOPMOST,
   WS_EX_NOACTIVATE): a non-activating floating panel. */
int shell_panel_open(int l_x, int l_y, int l_w, int l_h)
{
	int l_slot = shell_panel_free_slot();
	if (l_slot < 0 || l_w <= 0 || l_h <= 0 || !pthread_main_np()) return -1;
	shell_app();
	NSUInteger l_style = NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel;
	NSPanel *w = [[NSPanel alloc] initWithContentRect:shell_frame_of(l_x, l_y, l_w, l_h) styleMask:l_style backing:NSBackingStoreBuffered defer:NO];
	[w setLevel:NSFloatingWindowLevel];
	[w setHidesOnDeactivate:NO];
	[w setFloatingPanel:YES];
	[w setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary];
	return shell_panel_adopt(w, l_slot, 0, 0);
}

/* ---- the rest of a panel's settings and questions */
static int shell_panel_ok(int l_slot) { return l_slot >= 0 && l_slot < SHELL_PANELS && s_panel[l_slot] ? 1 : 0; }
int shell_panel_is_tool_window(int l_slot) { return shell_panel_ok(l_slot) && !s_panel_document[l_slot] ? 1 : 0; }
int shell_panel_has_owner(int l_slot) { return shell_panel_ok(l_slot) && s_panel_framed[l_slot] && !s_panel_document[l_slot] ? 1 : 0; }
int shell_panel_can_minimize(int l_slot) { return shell_panel_ok(l_slot) && ([s_panel[l_slot] styleMask] & NSWindowStyleMaskMiniaturizable) ? 1 : 0; }
int shell_panel_is_topmost(int l_slot) { return shell_panel_ok(l_slot) && [s_panel[l_slot] level] > NSNormalWindowLevel ? 1 : 0; }
/* A document window shows the application's icon, as the Windows half copies the main
   window's; a tool panel has none. */
void *shell_panel_icon(int l_slot) { return shell_panel_ok(l_slot) && s_panel_document[l_slot] ? shell_main_icon() : NULL; }

void shell_panel_set_opacity(int l_slot, int l_alpha)
{
	if (!shell_panel_ok(l_slot) || l_alpha < 0 || l_alpha > 255) return;
	[s_panel[l_slot] setAlphaValue:l_alpha / 255.0];
	s_panel_alpha[l_slot] = l_alpha;
}
int shell_panel_opacity(int l_slot) { return shell_panel_ok(l_slot) ? s_panel_alpha[l_slot] : 0; }
void shell_panel_set_click_through(int l_slot, int l_on) { if (shell_panel_ok(l_slot)) [s_panel[l_slot] setIgnoresMouseEvents:l_on != 0]; }
int shell_panel_is_click_through(int l_slot) { return shell_panel_ok(l_slot) && [s_panel[l_slot] ignoresMouseEvents] ? 1 : 0; }

/* Kept out of screen captures and recordings: Windows' WDA_EXCLUDEFROMCAPTURE (0x11) is a
   window that shares nothing. */
void shell_panel_set_capture_excluded(int l_slot, int l_on)
{
	if (shell_panel_ok(l_slot)) [s_panel[l_slot] setSharingType:l_on ? NSWindowSharingNone : NSWindowSharingReadOnly];
}
int shell_panel_capture_affinity(int l_slot)
{
	return shell_panel_ok(l_slot) && [s_panel[l_slot] sharingType] == NSWindowSharingNone ? 0x11 : 0;
}

void shell_panel_set_draggable(int l_slot, int l_on) { if (shell_panel_ok(l_slot)) s_panel_drag[l_slot] = l_on ? 1 : 0; }
void shell_panel_set_press_drag(int l_slot, int l_on) { if (shell_panel_ok(l_slot)) s_panel_press_drag[l_slot] = l_on ? 1 : 0; }
void shell_panel_set_axis(int l_slot, int l_axis) { if (shell_panel_ok(l_slot)) s_panel_axis[l_slot] = (l_axis >= 0 && l_axis <= 2) ? l_axis : 0; }
void shell_panel_set_side_grip(int l_slot, int l_on) { if (shell_panel_ok(l_slot)) s_panel_side_grip[l_slot] = l_on ? 1 : 0; }
void shell_panel_set_bottom_grip(int l_slot, int l_on) { if (shell_panel_ok(l_slot)) s_panel_bottom_grip[l_slot] = l_on ? 1 : 0; }
void shell_panel_set_resizable(int l_slot, int l_grip, int l_min_w, int l_min_h)
{
	if (!shell_panel_ok(l_slot)) return;
	s_panel_grip[l_slot] = l_grip > 0 ? l_grip : 0;
	s_panel_minw[l_slot] = l_min_w > 0 ? l_min_w : 0;
	s_panel_minh[l_slot] = l_min_h > 0 ? l_min_h : 0;
	double k = [s_panel[l_slot] backingScaleFactor];
	if (s_panel_minw[l_slot] || s_panel_minh[l_slot]) [s_panel[l_slot] setContentMinSize:NSMakeSize(s_panel_minw[l_slot] / k, s_panel_minh[l_slot] / k)];
}

/* What a Shift+press at client point (x, y) does: a move (caption) or the resize grip there. */
int shell_panel_grip_code(int l_slot, int l_x, int l_y)
{
	SSView *v = shell_panel_view(l_slot);
	if (!v || s_panel_grip[l_slot] <= 0 || !v->backing) return Shell_ht_caption;
	int g = s_panel_grip[l_slot], w = cairo_image_surface_get_width(v->backing), h = cairo_image_surface_get_height(v->backing);
	int l_left = l_x < g, l_right = l_x >= w - g, l_top = l_y < g, l_bottom = l_y >= h - g;
	if (l_top && l_left) return Shell_ht_topleft;
	if (l_top && l_right) return Shell_ht_topright;
	if (l_bottom && l_left) return Shell_ht_bottomleft;
	if (l_bottom && l_right) return Shell_ht_bottomright;
	if (l_left) return Shell_ht_left;
	if (l_right) return Shell_ht_right;
	if (l_top) return Shell_ht_top;
	if (l_bottom) return Shell_ht_bottom;
	return Shell_ht_caption;
}

/* What a press at client point (x, y) does, as Windows' shell_panel_press_code: 0 for the
   program (event 41), or a move or resize the shell carries out. */
int shell_panel_press_code(int l_slot, int l_x, int l_y, int l_shift)
{
	SSView *v = shell_panel_view(l_slot);
	if (!v) return 0;
	if (s_panel_drag[l_slot] && l_shift) return shell_panel_grip_code(l_slot, l_x, l_y);
	if (s_panel_press_drag[l_slot]) return Shell_ht_caption;
	int g = s_panel_grip[l_slot];
	int w = v->backing ? cairo_image_surface_get_width(v->backing) : 0, h = v->backing ? cairo_image_surface_get_height(v->backing) : 0;
	if (s_panel_side_grip[l_slot] && g > 0) {
		if (l_x < g) return Shell_ht_left;
		if (l_x >= w - g) return Shell_ht_right;
	}
	if (s_panel_bottom_grip[l_slot] && g > 0 && l_y >= h - g) return Shell_ht_bottom;
	return 0;
}

/* The cursor a press would act with, as Windows' WM_SETCURSOR answers for the panel; nil
   for the program's own cursor. */
static NSCursor *shell_panel_cursor(int a_slot, int a_x, int a_y)
{
	int l_shift = shell_shift_down();
	int c = l_shift && s_panel_drag[a_slot] ? shell_panel_grip_code(a_slot, a_x, a_y) : shell_panel_press_code(a_slot, a_x, a_y, 0);
	switch (c) {
		case Shell_ht_caption:
			if (!l_shift && !s_panel_press_drag[a_slot]) return nil;
			return s_panel_axis[a_slot] == 1 ? [NSCursor resizeLeftRightCursor] : s_panel_axis[a_slot] == 2 ? [NSCursor resizeUpDownCursor] : [NSCursor openHandCursor];
		case Shell_ht_left: case Shell_ht_right: return [NSCursor resizeLeftRightCursor];
		case Shell_ht_top: case Shell_ht_bottom: return [NSCursor resizeUpDownCursor];
		case Shell_ht_topleft: case Shell_ht_topright: case Shell_ht_bottomleft: case Shell_ht_bottomright: return [NSCursor crosshairCursor];
	}
	return nil;
}

/* Carry out a move or resize from a press, until the button is released, as Windows' modal
   size-move loop does: a move keeps to the panel's axis (1 sideways only, 2 up and down only);
   a resize keeps the minimum size. The window's own notices report it (49 while moving, 47
   when still, 48 for the new size). */
static void shell_panel_track(int a_slot, int a_code)
{
	NSWindow *w = s_panel[a_slot];
	NSRect l_start = [w frame];
	NSPoint l_from = [NSEvent mouseLocation];
	double k = [w backingScaleFactor];
	double l_min_w = s_panel_minw[a_slot] / k, l_min_h = s_panel_minh[a_slot] / k;
	if (l_min_w < 24) l_min_w = 24;
	if (l_min_h < 16) l_min_h = 16;
	for (;;) {
		NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp
			untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];
		if (!e || [e type] == NSEventTypeLeftMouseUp) break;
		NSPoint l_now = [NSEvent mouseLocation];
		double dx = l_now.x - l_from.x, dy = l_now.y - l_from.y;
		NSRect f = l_start;
		switch (a_code) {
			case Shell_ht_caption:
				if (s_panel_axis[a_slot] == 1) dy = 0;
				if (s_panel_axis[a_slot] == 2) dx = 0;
				f.origin.x += dx; f.origin.y += dy;
				[w setFrameOrigin:f.origin];
				continue;
			case Shell_ht_left: case Shell_ht_topleft: case Shell_ht_bottomleft:
				f.size.width = fmax(l_min_w, l_start.size.width - dx); f.origin.x = NSMaxX(l_start) - f.size.width; break;
			case Shell_ht_right: case Shell_ht_topright: case Shell_ht_bottomright:
				f.size.width = fmax(l_min_w, l_start.size.width + dx); break;
			default: break;
		}
		switch (a_code) {
			case Shell_ht_top: case Shell_ht_topleft: case Shell_ht_topright:
				f.size.height = fmax(l_min_h, l_start.size.height + dy); break;
			case Shell_ht_bottom: case Shell_ht_bottomleft: case Shell_ht_bottomright:
				f.size.height = fmax(l_min_h, l_start.size.height - dy); f.origin.y = NSMaxY(l_start) - f.size.height; break;
			default: break;
		}
		[w setFrame:f display:YES];
	}
}

/* The test door to events 60 - 65: a Windows message, as the panel's window procedure would
   turn it into an event (the message numbers are Windows'). Answers 0, as the procedure does. */
int shell_panel_send(int l_slot, int l_msg, int l_w, int l_l)
{
	if (!shell_panel_ok(l_slot)) return 0;
	int x = (short)(l_l & 0xFFFF), y = (short)((l_l >> 16) & 0xFFFF);
	switch (l_msg) {
		case 0x0100: if (shell_keydown_is_ours(l_w, shell_control_down(), shell_alt_down())) shell_push(60, l_w, 0, l_slot); break; /* WM_KEYDOWN */
		case 0x0104: if (shell_syskey_is_ours(l_w)) shell_push(60, l_w, 0, l_slot); break;   /* WM_SYSKEYDOWN */
		case 0x0102: shell_push(61, l_w, 0, l_slot); break;                                  /* WM_CHAR */
		case 0x0010: shell_push(62, 0, 0, l_slot); break;                                    /* WM_CLOSE */
		case 0x0006: shell_push(63, (l_w & 0xFFFF) ? 1 : 0, 0, l_slot); break;               /* WM_ACTIVATE */
		case 0x0203: shell_push(64, x, y, l_slot); break;                                    /* WM_LBUTTONDBLCLK */
		case 0x02A3: shell_push(65, 0, 0, l_slot); break;                                    /* WM_MOUSELEAVE */
		case 0x0201: shell_push(41, x, y, l_slot); break;                                    /* WM_LBUTTONDOWN */
		case 0x0202: shell_push(42, x, y, l_slot); break;                                    /* WM_LBUTTONUP */
		case 0x0200: shell_push(43, x, y, l_slot); break;                                    /* WM_MOUSEMOVE */
		case 0x0204: shell_push(46, x, y, l_slot); break;                                    /* WM_RBUTTONDOWN */
		case 0x020A: shell_push(45, (short)((l_w >> 16) & 0xFFFF), 0, l_slot); break;        /* WM_MOUSEWHEEL */
		default: return 0;
	}
	shell_nudge();
	return 0;
}

/* A drag delivered as if by the pointer (the test door): a move of (dx, dy) pixels from where
   the panel is, kept to its axis and reported as event 49, without moving the window, as
   Windows' WM_MOVING alone does. */
void shell_panel_try_move(int l_slot, int l_dx, int l_dy, int *l_x, int *l_y)
{
	(void)l_x; (void)l_y;
	RECT r;
	if (!shell_panel_ok(l_slot) || !GetWindowRect((__bridge HWND)s_panel[l_slot], &r)) return;
	if (s_panel_axis[l_slot] == 1) l_dy = 0;
	if (s_panel_axis[l_slot] == 2) l_dx = 0;
	int l_left = r.left + l_dx, l_top = r.top + l_dy;
	if (!shell_coalesce_slot(49, l_left, l_top, l_slot)) shell_push(49, l_left, l_top, l_slot);
	shell_nudge();
}

/* The panel's window destroyed as its owner's destruction would, without the books being
   kept (the test door to a panel that died elsewhere). */
void shell_panel_destroy_behind(int l_slot)
{
	if (!shell_panel_ok(l_slot)) return;
	[s_panel[l_slot] setDelegate:nil];
	[s_panel[l_slot] close];
}
void shell_set_cursor_kind(int k) { s_cursor = k; [s_view applyCursor]; }

/* A .ico (or any image macOS reads) as the Dock icon. */
void shell_set_window_icon(const void *path)
{
	NSImage *i = [[NSImage alloc] initWithContentsOfFile:shell_text(path)];
	if (i) [NSApp setApplicationIconImage:i];
}

/* A font file for this process, as AddFontResourceEx(FR_PRIVATE): 1 on success. Windows
   counts repeated loads of one file and accepts each; Core Text refuses a file it already
   has, so "already registered" is a success here too. */
int shell_add_font(const char *path)
{
	NSURL *u = [NSURL fileURLWithPath:shell_text(path)];
	CFErrorRef l_error = NULL;
	if (CTFontManagerRegisterFontsForURL((__bridge CFURLRef)u, kCTFontManagerScopeProcess, &l_error)) return 1;
	int l_already = l_error && CFErrorGetCode(l_error) == kCTFontManagerErrorAlreadyRegistered;
	if (l_error) CFRelease(l_error);
	return l_already ? 1 : 0;
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
void *shell_get_dc(void) { return s_window && s_view ? (void *)s_view->backing : NULL; }
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
	/* Nobody to wake, as on Windows: no main window open and no thread claimed. */
	if (!NSApp || (!s_window && !atomic_load(&s_pump_claimed))) { atomic_store(&s_wake_pending, 0); return 0; }
	dispatch_async(dispatch_get_main_queue(), ^{
		atomic_store(&s_wake_pending, 0);
		shell_push(54, 0, 0, 0);
		shell_nudge();
	});
	return 1;
}
/* AppKit's pump is always the main thread; claiming it says only that a host pumps, so a
   wake has somebody to reach with no main window open. Releasing forgets that. */
void shell_claim_pump_thread(int l_on) { atomic_store(&s_pump_claimed, l_on ? 1 : 0); atomic_store(&s_wake_pending, 0); }
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

/* Images: 32-bit pixels as cairo keeps them (0xAARRGGBB, top row first), always opaque, as
   the Windows half reads and writes them. On the pasteboard as PNG and TIFF. */
static NSBitmapImageRep *shell_clip_rep(void)
{
	NSPasteboard *p = [NSPasteboard generalPasteboard];
	NSImage *i = [[NSImage alloc] initWithPasteboard:p];
	if (!i) return nil;
	for (NSImageRep *r in [i representations]) if ([r isKindOfClass:[NSBitmapImageRep class]]) return (NSBitmapImageRep *)r;
	CGImageRef c = [i CGImageForProposedRect:NULL context:nil hints:nil];
	return c ? [[NSBitmapImageRep alloc] initWithCGImage:c] : nil;
}

int shell_clip_set_image(const void *bits, int w, int h, int stride)
{
	if (!bits || w <= 0 || h <= 0 || stride < w * 4) return 0;
	NSBitmapImageRep *r = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
		bitmapFormat:0 bytesPerRow:w * 4 bitsPerPixel:32];
	if (!r) return 0;
	unsigned char *dst = [r bitmapData];
	for (int row = 0; row < h; row++) {
		const uint32_t *src = (const uint32_t *)((const char *)bits + (size_t)row * stride);
		unsigned char *out = dst + (size_t)row * w * 4;
		for (int col = 0; col < w; col++) {
			uint32_t v = src[col];
			out[col * 4] = (v >> 16) & 0xFF; out[col * 4 + 1] = (v >> 8) & 0xFF; out[col * 4 + 2] = v & 0xFF; out[col * 4 + 3] = 0xFF;
		}
	}
	NSData *l_png = [r representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
	NSPasteboard *p = [NSPasteboard generalPasteboard];
	[p clearContents];
	BOOL ok = l_png && [p setData:l_png forType:NSPasteboardTypePNG];
	NSData *l_tiff = [r TIFFRepresentation];
	if (l_tiff) ok = [p setData:l_tiff forType:NSPasteboardTypeTIFF] || ok;
	return ok ? 1 : 0;
}

int shell_clip_has_image(void)
{
	return [[NSPasteboard generalPasteboard] availableTypeFromArray:@[NSPasteboardTypePNG, NSPasteboardTypeTIFF]] ? 1 : 0;
}

int shell_clip_image_size(int *w, int *h)
{
	*w = 0; *h = 0;
	NSBitmapImageRep *r = shell_clip_rep();
	if (!r) return 0;
	*w = (int)[r pixelsWide]; *h = (int)[r pixelsHigh];
	return 1;
}

/* Only when the image is exactly `w' x `h' pixels, as on Windows. */
int shell_clip_get_image(void *bits, int w, int h, int stride)
{
	if (!bits || w <= 0 || h <= 0 || stride < w * 4) return 0;
	NSBitmapImageRep *r = shell_clip_rep();
	if (!r || [r pixelsWide] != w || [r pixelsHigh] != h) return 0;
	CGColorSpaceRef l_srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGContextRef c = CGBitmapContextCreate(bits, (size_t)w, (size_t)h, 8, (size_t)stride, l_srgb,
		kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
	CGColorSpaceRelease(l_srgb);
	if (!c) return 0;
	CGContextSetRGBFillColor(c, 1, 1, 1, 1);
	CGContextFillRect(c, CGRectMake(0, 0, w, h));
	CGContextDrawImage(c, CGRectMake(0, 0, w, h), [r CGImage]);
	CGContextRelease(c);
	for (int row = 0; row < h; row++) {
		uint32_t *px = (uint32_t *)((char *)bits + (size_t)row * stride);
		for (int col = 0; col < w; col++) px[col] |= 0xFF000000u;
	}
	return 1;
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

/* ------------------------------------------------------------------ files: the open dialog and drops */

/* The paths of the last drop, UTF-16 and one per line, into `buf' (the caller reads 16-bit
   units); taking them empties the store, as on Windows. */
int shell_drop_paths(void *buf, int cap)
{
	int n = s_drops_len;
	if (cap < 1) return 0;
	if (n >= cap) n = cap - 1;
	memcpy(buf, s_drops, (size_t)n * sizeof(unichar));
	((unichar *)buf)[n] = 0;
	s_drops_len = 0;
	return n;
}

void shell_panel_set_accepts_files(int l_slot, int l_on) { if (l_slot >= 0 && l_slot < SHELL_PANELS && s_panel[l_slot]) s_panel_accepts[l_slot] = l_on ? 1 : 0; }
int shell_panel_accepts_files(int l_slot) { return l_slot >= 0 && l_slot < SHELL_PANELS && s_panel[l_slot] && s_panel_accepts[l_slot] ? 1 : 0; }

/* A drop delivered as if from Finder (the test door): `l_paths' one per line, UTF-8. */
void shell_panel_try_drop(int l_slot, int l_x, int l_y, const void *l_paths)
{
	if (l_slot < 0 || l_slot >= SHELL_PANELS || !s_panel[l_slot] || !l_paths) return;
	shell_keep_drops(shell_text(l_paths));
	shell_push(50, l_x, l_y, l_slot);
	shell_nudge();
}

/* The file types a Windows filter allows ("Text|*.txt;*.md|All|*.*": description, patterns,
   ...), or nil for any file. */
static NSArray<UTType *> *shell_filter_types(NSString *a_filter)
{
	NSArray<NSString *> *l_parts = [a_filter componentsSeparatedByString:@"|"];
	NSMutableArray<UTType *> *l_types = [NSMutableArray array];
	for (NSUInteger i = 1; i < [l_parts count]; i += 2) {
		for (NSString *l_pattern in [l_parts[i] componentsSeparatedByString:@";"]) {
			NSString *t = [l_pattern stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			if ([t isEqualToString:@"*.*"] || [t isEqualToString:@"*"]) return nil;
			if ([t hasPrefix:@"*."]) {
				UTType *u = [UTType typeWithFilenameExtension:[t substringFromIndex:2]];
				if (u) [l_types addObject:u];
			}
		}
	}
	return [l_types count] ? l_types : nil;
}

/* Choose one existing file: its path, UTF-8, into `l_out' (the caller reads NATIVE_STRING;
   the buffer holds 2 * l_cap bytes). 1 when a file was chosen. */
int shell_open_file_dialog(const void *l_title, const void *l_filter, const void *l_initial_dir, void *l_out, int l_cap)
{
	if (!l_out || l_cap <= 1) return 0;
	((char *)l_out)[0] = 0;
	shell_app();
	NSOpenPanel *o = [NSOpenPanel openPanel];
	[o setCanChooseFiles:YES];
	[o setCanChooseDirectories:NO];
	[o setAllowsMultipleSelection:NO];
	NSString *t = shell_text(l_title);
	if ([t length]) { [o setTitle:t]; [o setMessage:t]; }
	NSArray<UTType *> *l_types = shell_filter_types(shell_text(l_filter));
	if (l_types) [o setAllowedContentTypes:l_types];
	NSString *d = shell_text(l_initial_dir);
	if ([d length]) [o setDirectoryURL:[NSURL fileURLWithPath:[d stringByExpandingTildeInPath] isDirectory:YES]];
	if ([o runModal] != NSModalResponseOK || ![o URL]) return 0;
	const char *l_path = [[[o URL] path] fileSystemRepresentation];
	size_t l_len = strlen(l_path), l_room = (size_t)l_cap * 2 - 1;
	if (l_len > l_room) return 0;
	memcpy(l_out, l_path, l_len + 1);
	return 1;
}

/* ------------------------------------------------------------------ spelling */

/* NSSpellChecker in American English, as the Windows half's ISpellChecker ("en-US"). Ranges
   and text are in UTF-16 units on both. Words ignored hold for this run (one document tag);
   a word added is learned into the user's dictionary, as ISpellChecker::Add does. */
static NSInteger s_spell_tag = 0;
static NSSpellChecker *shell_speller(void)
{
	shell_app();
	NSSpellChecker *c = [NSSpellChecker sharedSpellChecker];
	if (!s_spell_tag) s_spell_tag = [NSSpellChecker uniqueSpellDocumentTag];
	return c;
}
static NSString *const Shell_spell_language = @"en_US";

/* Misspellings in `text': (start, length) pairs into `out', at most `cap_pairs'; answers how many. */
int shell_spell_check(const void *text, int *out, int cap_pairs)
{
	NSString *t = shell_text(text);
	NSSpellChecker *c = shell_speller();
	int n = 0;
	NSUInteger l_at = 0;
	while (n < cap_pairs && l_at < [t length]) {
		NSRange r = [c checkSpellingOfString:t startingAt:(NSInteger)l_at language:Shell_spell_language wrap:NO
			inSpellDocumentWithTag:s_spell_tag wordCount:NULL];
		if (r.location == NSNotFound || r.length == 0) break;
		out[n * 2] = (int)r.location;
		out[n * 2 + 1] = (int)r.length;
		n++;
		l_at = NSMaxRange(r);
	}
	return n;
}

/* Up to five suggestions for `word', UTF-16 and one per line, into `buf'; answers how many. */
int shell_spell_suggest(const void *word, void *buf, int cap)
{
	unichar *b = (unichar *)buf;
	if (cap < 1) return 0;
	b[0] = 0;
	NSString *w = shell_text(word);
	if ([w length] == 0) return 0;
	NSArray<NSString *> *l_guesses = [shell_speller() guessesForWordRange:NSMakeRange(0, [w length]) inString:w
		language:Shell_spell_language inSpellDocumentWithTag:s_spell_tag];
	int n = 0, pos = 0;
	for (NSString *g in l_guesses) {
		if (n == 5) break;
		int L = (int)[g length];
		if (pos + L + 2 >= cap) break;
		if (n) b[pos++] = '\n';
		[g getCharacters:b + pos range:NSMakeRange(0, (NSUInteger)L)];
		pos += L;
		n++;
	}
	b[pos] = 0;
	return n;
}

int shell_spell_add(const void *word)
{
	NSString *w = shell_text(word);
	if ([w length] == 0) return 0;
	[shell_speller() learnWord:w];
	return 1;
}

int shell_spell_ignore(const void *word)
{
	NSString *w = shell_text(word);
	if ([w length] == 0) return 0;
	[shell_speller() ignoreWord:w inSpellDocumentWithTag:s_spell_tag];
	return 1;
}

/* ------------------------------------------------------------------ monitors */

/* Each screen as Windows' GetMonitorInfo answers it, in pixels from the main screen's
   top-left: the monitor (0-3: left, top, right, bottom), its work area without the menu bar
   and Dock (4-7), and whether it is the primary one (8, the screen with the menu bar). */
#define SHELL_MONITOR_CAP 16
static int s_mon[SHELL_MONITOR_CAP][9];
static unichar s_mon_name[SHELL_MONITOR_CAP][32];
static int s_mon_count = 0;

int shell_monitors_refresh(void)
{
	NSArray<NSScreen *> *l_all = [NSScreen screens];
	NSScreen *l_main = [l_all count] ? l_all[0] : nil;
	double k = l_main ? [l_main backingScaleFactor] : 1.0, l_top = l_main ? NSMaxY([l_main frame]) : 0;
	s_mon_count = 0;
	for (NSScreen *c in l_all) {
		if (s_mon_count == SHELL_MONITOR_CAP) break;
		int *m = s_mon[s_mon_count];
		NSRect f = [c frame], v = [c visibleFrame];
		m[0] = (int)lround(f.origin.x * k); m[1] = (int)lround((l_top - NSMaxY(f)) * k);
		m[2] = (int)lround(NSMaxX(f) * k); m[3] = (int)lround((l_top - f.origin.y) * k);
		m[4] = (int)lround(v.origin.x * k); m[5] = (int)lround((l_top - NSMaxY(v)) * k);
		m[6] = (int)lround(NSMaxX(v) * k); m[7] = (int)lround((l_top - v.origin.y) * k);
		m[8] = c == l_main ? 1 : 0;
		NSString *n = [c localizedName] ?: @"";
		NSUInteger l_len = MIN([n length], (NSUInteger)31);
		[n getCharacters:s_mon_name[s_mon_count] range:NSMakeRange(0, l_len)];
		s_mon_name[s_mon_count][l_len] = 0;
		s_mon_count++;
	}
	return s_mon_count;
}
int shell_monitor_field(int l_i, int l_f) { return (l_i >= 0 && l_i < s_mon_count && l_f >= 0 && l_f <= 8) ? s_mon[l_i][l_f] : 0; }

/* The screen's name, UTF-16 into `l_buf' (the caller reads 16-bit units). */
int shell_monitor_name(int l_i, void *l_buf, int l_cap)
{
	int n = 0;
	if (l_i < 0 || l_i >= s_mon_count || l_cap <= 0) return 0;
	unichar *b = (unichar *)l_buf;
	while (n < l_cap - 1 && n < 31 && s_mon_name[l_i][n]) { b[n] = s_mon_name[l_i][n]; n++; }
	b[n] = 0;
	return n;
}

/* ------------------------------------------------------------------ the overlay, the strip, outlines */

/* A borderless window that can still take the keyboard (the overlay's Escape and arrows). */
@interface SSKeyWindow : NSWindow
@end
@implementation SSKeyWindow
- (BOOL)canBecomeKeyWindow { return YES; }
@end

/* The overlay: the whole desktop under one borderless window above everything (WS_EX_TOPMOST
   over the virtual screen), for picking a region; the program draws on it through its DC.
   With "Displays have separate Spaces", a window shows on one display only. */
static SSKeyWindow *s_overlay = nil;
static SSView *s_overlay_view = nil;
static NSThread *s_watchdog = nil;

static void shell_overlay_dismiss(void)
{
	if (s_overlay) [s_overlay orderOut:nil];
	shell_push(34, 0, 0, 0);
	shell_nudge();
}

/* The safety net, as on Windows: Escape held 2 seconds while the overlay shows cancels it even
   if the program's loop is stuck; held 5 seconds, the process ends. */
static atomic_int s_overlay_shown = 0;
@interface SSWatchdog : NSObject
@end
@implementation SSWatchdog
- (void)watch:(id)unused
{
	(void)unused;
	int l_held = 0;
	for (;;) {
		[NSThread sleepForTimeInterval:0.1];
		if (atomic_load(&s_overlay_shown) && CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState, 53 /* Escape */)) {
			l_held++;
			if (l_held == 20) dispatch_async(dispatch_get_main_queue(), ^{ shell_overlay_dismiss(); atomic_store(&s_overlay_shown, 0); });
			if (l_held >= 50) _exit(1);
		} else l_held = 0;
	}
}
@end

void *shell_show_overlay(void)
{
	shell_app();
	double k; NSRect r = shell_virtual_desktop(&k);
	NSRect f = shell_frame_of((int)lround(r.origin.x * k), (int)lround(r.origin.y * k), (int)lround(r.size.width * k), (int)lround(r.size.height * k));
	if (!s_watchdog) {
		s_watchdog = [[NSThread alloc] initWithTarget:[[SSWatchdog alloc] init] selector:@selector(watch:) object:nil];
		[s_watchdog start];
	}
	if (!s_overlay) {
		s_overlay = [[SSKeyWindow alloc] initWithContentRect:f styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
		[s_overlay setReleasedWhenClosed:NO];
		[s_overlay setLevel:NSStatusWindowLevel + 1];   /* above the menu bar */
		[s_overlay setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary];
		[s_overlay setAcceptsMouseMovedEvents:YES];
		s_overlay_view = [[SSView alloc] initWithFrame:NSMakeRect(0, 0, f.size.width, f.size.height) slot:Shell_slot_overlay];
		[s_overlay setContentView:s_overlay_view];
	}
	[s_overlay setFrame:f display:NO];
	[s_overlay_view rebuildBacking];
	[NSApp activate];
	[s_overlay makeKeyAndOrderFront:nil];
	[s_overlay makeFirstResponder:s_overlay_view];
	[[NSCursor crosshairCursor] set];
	atomic_store(&s_overlay_shown, 1);
	return (__bridge void *)s_overlay;
}
void shell_hide_overlay(void) { if (s_overlay) [s_overlay orderOut:nil]; atomic_store(&s_overlay_shown, 0); }
void *shell_overlay_dc(void) { return s_overlay && s_overlay_view ? (void *)s_overlay_view->backing : NULL; }
void shell_overlay_release(void *dc) { if (dc) [s_overlay_view setNeedsDisplay:YES]; }

/* The strip: a small borderless window above others that never takes the focus, dragged by a
   press (21 at the press, 22 with its new top-left when the drag ends, 23 to draw). */
static NSPanel *s_strip = nil;
static SSView *s_strip_view = nil;

static void shell_strip_drag(void)
{
	NSRect l_start = [s_strip frame];
	NSPoint l_from = [NSEvent mouseLocation];
	BOOL l_moved = NO;
	for (;;) {
		NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp
			untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];
		if (!e || [e type] == NSEventTypeLeftMouseUp) break;
		NSPoint l_now = [NSEvent mouseLocation];
		[s_strip setFrameOrigin:NSMakePoint(l_start.origin.x + l_now.x - l_from.x, l_start.origin.y + l_now.y - l_from.y)];
		l_moved = YES;
	}
	if (l_moved) {
		RECT r;
		GetWindowRect((__bridge HWND)s_strip, &r);
		shell_push(22, r.left, r.top, 0);
		shell_nudge();
	}
}

void *shell_show_strip(int x, int y, int w, int h)
{
	if (w <= 0 || h <= 0) return NULL;
	shell_app();
	NSRect f = shell_frame_of(x, y, w, h);
	if (!s_strip) {
		s_strip = [[NSPanel alloc] initWithContentRect:f styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
			backing:NSBackingStoreBuffered defer:NO];
		[s_strip setReleasedWhenClosed:NO];
		[s_strip setLevel:NSFloatingWindowLevel];
		[s_strip setHidesOnDeactivate:NO];
		[s_strip setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary];
		s_strip_view = [[SSView alloc] initWithFrame:NSMakeRect(0, 0, f.size.width, f.size.height) slot:Shell_slot_strip];
		[s_strip setContentView:s_strip_view];
	}
	[s_strip setFrame:f display:NO];
	[s_strip_view rebuildBacking];
	[s_strip orderFront:nil];
	return (__bridge void *)s_strip;
}
void shell_hide_strip(void) { if (s_strip) [s_strip orderOut:nil]; }
void *shell_strip_dc(void) { return s_strip && s_strip_view ? (void *)s_strip_view->backing : NULL; }
void shell_strip_release(void *dc) { if (dc) [s_strip_view setNeedsDisplay:YES]; }

/* Outlines: up to four rectangles drawn as a frame `thick' pixels wide around (x, y, w, h),
   above everything, letting the pointer through (WS_EX_TRANSPARENT with a ring region). */
@interface SSOutlineView : NSView {
@public
	NSColor *color;
	double thick;
}
@end
@implementation SSOutlineView
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)a_rect
{
	(void)a_rect;
	[color setFill];
	NSRect b = [self bounds];
	NSBezierPath *l_ring = [NSBezierPath bezierPathWithRect:b];
	[l_ring appendBezierPathWithRect:NSInsetRect(b, thick, thick)];
	[l_ring setWindingRule:NSWindingRuleEvenOdd];
	[l_ring fill];
}
@end
static NSWindow *s_outline[4];

void shell_outline_show(int slot, int x, int y, int w, int h, int thick, int rgb)
{
	if (slot < 0 || slot > 3 || w <= 0 || h <= 0 || thick <= 0) return;
	shell_app();
	NSRect f = shell_frame_of(x, y, w, h);
	if (!s_outline[slot]) {
		NSWindow *o = [[NSWindow alloc] initWithContentRect:f styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
		[o setReleasedWhenClosed:NO];
		[o setOpaque:NO];
		[o setBackgroundColor:[NSColor clearColor]];
		[o setIgnoresMouseEvents:YES];
		[o setLevel:NSStatusWindowLevel];
		[o setHasShadow:NO];
		[o setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary];
		[o setContentView:[[SSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, f.size.width, f.size.height)]];
		s_outline[slot] = o;
	}
	SSOutlineView *v = (SSOutlineView *)[s_outline[slot] contentView];
	v->color = [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1.0];
	v->thick = thick / [s_outline[slot] backingScaleFactor];
	[s_outline[slot] setFrame:f display:NO];
	[v setNeedsDisplay:YES];
	[s_outline[slot] orderFront:nil];
}
void shell_outline_hide(int slot) { if (slot >= 0 && slot < 4 && s_outline[slot]) [s_outline[slot] orderOut:nil]; }

/* ------------------------------------------------------------------ the tray (menu bar icons) */

/* A notification-area icon is a menu bar status item showing the application's icon. A click
   reports 52 with the button (1 left, 2 right or Control-click, 3 double) and the tray's id, as
   on Windows. A balloon is a popover under the icon that closes itself: Notification Center
   needs a signed bundle and the user's permission, which a plain program has not got. */
@interface SSTray : NSObject {
@public
	NSStatusItem *item;
	int tray_id;
	NSPopover *balloon;
}
- (void)clicked:(id)sender;
@end
static NSMutableArray<SSTray *> *s_trays = nil;
static int s_tray_next = 1;

static void shell_tray_push(SSTray *t, int a_button) { shell_push(52, a_button, 0, t->tray_id); shell_nudge(); }

@implementation SSTray
- (void)clicked:(id)sender
{
	(void)sender;
	NSEvent *e = [NSApp currentEvent];
	BOOL l_right = [e type] == NSEventTypeRightMouseUp || ([e modifierFlags] & NSEventModifierFlagControl);
	shell_tray_push(self, l_right ? 2 : [e clickCount] >= 2 ? 3 : 1);
}
- (void)closeBalloon:(id)sender { (void)sender; [balloon close]; balloon = nil; }
@end

static SSTray *shell_tray_of(HWND h)
{
	for (SSTray *t in s_trays) if ((__bridge void *)t == h) return t;
	return nil;
}

HWND shell_tray_add(const void *tip)
{
	shell_app();
	if (!s_trays) s_trays = [NSMutableArray array];
	SSTray *t = [[SSTray alloc] init];
	t->item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
	NSImage *l_icon = [[NSApp applicationIconImage] copy];
	[l_icon setSize:NSMakeSize(18, 18)];
	[[t->item button] setImage:l_icon];
	[[t->item button] setToolTip:shell_text(tip)];
	[[t->item button] setTarget:t];
	[[t->item button] setAction:@selector(clicked:)];
	[[t->item button] sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
	t->tray_id = s_tray_next++;
	[s_trays addObject:t];
	return (__bridge HWND)t;
}
int shell_tray_id(HWND h) { SSTray *t = shell_tray_of(h); return t ? t->tray_id : 0; }
int shell_tray_set_tip(HWND h, const void *tip)
{
	SSTray *t = shell_tray_of(h);
	if (!t) return 0;
	[[t->item button] setToolTip:shell_text(tip)];
	return 1;
}
int shell_tray_balloon(HWND h, const void *title, const void *body)
{
	SSTray *t = shell_tray_of(h);
	if (!t || ![t->item button]) return 0;
	[t->balloon close];
	NSTextField *l_title = [NSTextField labelWithString:shell_text(title)];
	[l_title setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
	NSTextField *l_body = [NSTextField wrappingLabelWithString:shell_text(body)];
	[l_body setPreferredMaxLayoutWidth:280];
	NSStackView *l_stack = [NSStackView stackViewWithViews:@[l_title, l_body]];
	[l_stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[l_stack setAlignment:NSLayoutAttributeLeading];
	[l_stack setEdgeInsets:NSEdgeInsetsMake(10, 12, 10, 12)];
	NSViewController *c = [[NSViewController alloc] init];
	[c setView:l_stack];
	t->balloon = [[NSPopover alloc] init];
	[t->balloon setContentViewController:c];
	[t->balloon setBehavior:NSPopoverBehaviorTransient];
	[t->balloon showRelativeToRect:[[t->item button] bounds] ofView:[t->item button] preferredEdge:NSRectEdgeMinY];
	[NSTimer scheduledTimerWithTimeInterval:6.0 target:t selector:@selector(closeBalloon:) userInfo:nil repeats:NO];
	return 1;
}
int shell_tray_remove(HWND h)
{
	SSTray *t = shell_tray_of(h);
	if (!t) return 0;
	[t->balloon close];
	[[NSStatusBar systemStatusBar] removeStatusItem:t->item];
	[s_trays removeObject:t];
	return 1;
}

/* A menu from `l_items' (one item per line, "-" a separator) under the icon, waited for: the
   chosen line's number (separators count, as on Windows), or 0 when dismissed. */
static int s_tray_choice = 0;
@interface SSTrayChoice : NSObject
@end
@implementation SSTrayChoice
- (void)choose:(NSMenuItem *)i { s_tray_choice = (int)[i tag]; }
@end
int shell_tray_menu(HWND h, const void *l_items)
{
	SSTray *t = shell_tray_of(h);
	if (!t || !l_items) return 0;
	SSTrayChoice *l_target = [[SSTrayChoice alloc] init];
	NSMenu *m = [[NSMenu alloc] initWithTitle:@""];
	[m setAutoenablesItems:NO];
	int n = 0;
	for (NSString *l_line in [shell_text(l_items) componentsSeparatedByString:@"\n"]) {
		n++;
		if ([l_line isEqualToString:@"-"]) { [m addItem:[NSMenuItem separatorItem]]; continue; }
		NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:l_line action:@selector(choose:) keyEquivalent:@""];
		[i setTarget:l_target];
		[i setTag:n];
		[m addItem:i];
	}
	s_tray_choice = 0;
	NSStatusBarButton *b = [t->item button];
	[m popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSMinY([b bounds]) - 4) inView:b];
	return s_tray_choice;
}

/* The test door: a click delivered as Windows' tray callback would (WM_LBUTTONUP 0x202,
   WM_RBUTTONUP 0x205, WM_LBUTTONDBLCLK 0x203). */
void shell_tray_try_click(HWND h, int l_msg)
{
	SSTray *t = shell_tray_of(h);
	if (!t) return;
	switch (l_msg) {
		case 0x0202: shell_tray_push(t, 1); break;
		case 0x0205: shell_tray_push(t, 2); break;
		case 0x0203: shell_tray_push(t, 3); break;
	}
}

/* ------------------------------------------------------------------ keys by Windows' number */

/* The Mac key code for a Windows virtual key (the US layout's positions for letters and
   digits), or -1. The reverse of `shell_vk'. */
static int shell_keycode_of_vk(int a_vk)
{
	static const int l_letters[26] = {0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
		0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06};
	static const int l_digits[10] = {0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19};
	static const int l_f[12] = {122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111};
	if (a_vk >= 'A' && a_vk <= 'Z') return l_letters[a_vk - 'A'];
	if (a_vk >= '0' && a_vk <= '9') return l_digits[a_vk - '0'];
	if (a_vk >= 0x70 && a_vk <= 0x7B) return l_f[a_vk - 0x70];
	if (a_vk >= 0x60 && a_vk <= 0x69) { static const int k[10] = {82, 83, 84, 85, 86, 87, 88, 89, 91, 92}; return k[a_vk - 0x60]; }
	switch (a_vk) {
		case 0x25: return 123; case 0x27: return 124; case 0x28: return 125; case 0x26: return 126;
		case 0x24: return 115; case 0x23: return 119; case 0x21: return 116; case 0x22: return 121;
		case 0x2E: return 117; case 0x08: return 51; case 0x0D: return 36; case 0x09: return 48;
		case 0x1B: return 53; case 0x20: return 49;
		case 0xBB: return 24; case 0xBD: return 27; case 0x6B: return 69; case 0x6D: return 78;
		case 0xBA: return 41; case 0xBF: return 44; case 0xC0: return 50; case 0xDB: return 33;
		case 0xDC: return 42; case 0xDD: return 30; case 0xDE: return 39; case 0xBC: return 43; case 0xBE: return 47;
	}
	return -1;
}

/* ------------------------------------------------------------------ global hotkeys */

/* Carbon's system-wide hotkeys, which need no permission. Windows' modifiers (1 Alt, 2 Ctrl,
   4 Shift, 8 Win) become Option, Command (the primary modifier), Shift and Control; a press
   reports 51 (id, virtual key, modifiers) as WM_HOTKEY does. */
#define SHELL_HOTKEYS 64
static struct { int used, id, vk, mods; EventHotKeyRef ref; } s_hotkey[SHELL_HOTKEYS];
static int s_hotkey_handler = 0;

static OSStatus shell_hotkey_pressed(EventHandlerCallRef a_next, EventRef a_event, void *a_data)
{
	(void)a_next; (void)a_data;
	EventHotKeyID k;
	if (GetEventParameter(a_event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof k, NULL, &k) != noErr) return eventNotHandledErr;
	for (int i = 0; i < SHELL_HOTKEYS; i++)
		if (s_hotkey[i].used && s_hotkey[i].id == (int)k.id) { shell_push(51, s_hotkey[i].id, s_hotkey[i].vk, s_hotkey[i].mods); shell_nudge(); return noErr; }
	return eventNotHandledErr;
}

void shell_hotkey_unregister(int l_id)
{
	for (int i = 0; i < SHELL_HOTKEYS; i++)
		if (s_hotkey[i].used && s_hotkey[i].id == l_id) { UnregisterEventHotKey(s_hotkey[i].ref); s_hotkey[i].used = 0; }
}

int shell_hotkey_register(int l_id, int l_mods, int l_vk)
{
	shell_app();
	int l_code = shell_keycode_of_vk(l_vk), l_free = -1;
	if (l_code < 0) return 0;
	if (!s_hotkey_handler) {
		EventTypeSpec l_spec = {kEventClassKeyboard, kEventHotKeyPressed};
		if (InstallApplicationEventHandler(NewEventHandlerUPP(shell_hotkey_pressed), 1, &l_spec, NULL, NULL) != noErr) return 0;
		s_hotkey_handler = 1;
	}
	shell_hotkey_unregister(l_id);
	for (int i = 0; i < SHELL_HOTKEYS && l_free < 0; i++) if (!s_hotkey[i].used) l_free = i;
	if (l_free < 0) return 0;
	UInt32 m = ((l_mods & 1) ? optionKey : 0) | ((l_mods & 2) ? cmdKey : 0) | ((l_mods & 4) ? shiftKey : 0) | ((l_mods & 8) ? controlKey : 0);
	EventHotKeyID k = {'SShk', (UInt32)l_id};
	EventHotKeyRef r = NULL;
	if (RegisterEventHotKey((UInt32)l_code, m, k, GetApplicationEventTarget(), 0, &r) != noErr) return 0;
	s_hotkey[l_free].used = 1; s_hotkey[l_free].id = l_id; s_hotkey[l_free].vk = l_vk; s_hotkey[l_free].mods = l_mods; s_hotkey[l_free].ref = r;
	return 1;
}

/* The test door: a hotkey press as if from the keyboard. */
void shell_hotkey_simulate(int l_id, int l_mods, int l_vk) { shell_push(51, l_id, l_vk, l_mods); shell_nudge(); }

/* ------------------------------------------------------------------ input synthesis */

/* Clicks and typing posted to the system, as SendInput. macOS lets a process post input only
   with the Accessibility permission (System Settings, Privacy & Security, Accessibility); without
   it nothing is sent and the last error is 5, Windows' "access denied" for blocked input. */
static int s_input_error = 0;
static int shell_input_allowed(void)
{
	if (AXIsProcessTrusted()) return 1;
	s_input_error = 5;
	return 0;
}
int shell_input_last_error(void) { return s_input_error; }

/* A pixel point of the virtual desktop as a global display point (points, from the main
   screen's top-left). */
static CGPoint shell_display_point(int x, int y)
{
	NSScreen *l_main = [[NSScreen screens] count] ? [NSScreen screens][0] : nil;
	double k = l_main ? [l_main backingScaleFactor] : 1.0;
	return CGPointMake(x / k, y / k);
}

int shell_input_pointer(int *x, int *y)
{
	*x = 0; *y = 0;
	CGEventRef e = CGEventCreate(NULL);
	if (!e) return 0;
	CGPoint p = CGEventGetLocation(e);
	CFRelease(e);
	NSScreen *l_main = [[NSScreen screens] count] ? [NSScreen screens][0] : nil;
	double k = l_main ? [l_main backingScaleFactor] : 1.0;
	*x = (int)lround(p.x * k); *y = (int)lround(p.y * k);
	return 1;
}

int shell_input_on_desktop(int x, int y)
{
	return x >= shell_screen_x() && y >= shell_screen_y() && x < shell_screen_x() + shell_screen_w() && y < shell_screen_y() + shell_screen_h() ? 1 : 0;
}

int shell_input_click(int x, int y, int restore_cursor, int restore_focus)
{
	s_input_error = 0;
	if (!shell_input_allowed()) return 0;
	int l_bx, l_by;
	shell_input_pointer(&l_bx, &l_by);
	NSRunningApplication *l_front = [[NSWorkspace sharedWorkspace] frontmostApplication];
	CGPoint p = shell_display_point(x, y);
	CGEventType l_types[3] = {kCGEventMouseMoved, kCGEventLeftMouseDown, kCGEventLeftMouseUp};
	for (int i = 0; i < 3; i++) {
		CGEventRef e = CGEventCreateMouseEvent(NULL, l_types[i], p, kCGMouseButtonLeft);
		if (!e) { s_input_error = 8; return 0; }
		CGEventPost(kCGHIDEventTap, e);
		CFRelease(e);
	}
	if (restore_cursor) CGWarpMouseCursorPosition(shell_display_point(l_bx, l_by));
	if (restore_focus && l_front) {
		usleep(120000);   /* let the click's activation land first, as on Windows */
		if (![[[NSWorkspace sharedWorkspace] frontmostApplication] isEqual:l_front]) [l_front activateWithOptions:0];
	}
	return 1;
}

/* The UTF-16 units `s' (UTF-8) types: what `shell_input_type' sends, two events per unit. */
int shell_input_type_units(const void *s) { return s ? (int)[shell_text(s) length] : 0; }

int shell_input_type(const void *s)
{
	s_input_error = 0;
	if (!s || !shell_input_allowed()) return 0;
	NSString *t = shell_text(s);
	int l_sent = 0;
	for (NSUInteger i = 0; i < [t length]; i++) {
		UniChar u = [t characterAtIndex:i];
		for (int l_down = 1; l_down >= 0; l_down--) {
			CGEventRef e = CGEventCreateKeyboardEvent(NULL, 0, l_down != 0);
			if (!e) { s_input_error = 8; return l_sent; }
			CGEventKeyboardSetUnicodeString(e, 1, &u);
			CGEventPost(kCGHIDEventTap, e);
			CFRelease(e);
			l_sent++;
		}
	}
	return l_sent;
}

/* A chord: the modifiers down, the key down and up, the modifiers up; Ctrl as Command. */
int shell_input_chord(int ctrl, int shift, int alt, int vk)
{
	s_input_error = 0;
	int l_code = shell_keycode_of_vk(vk);
	if (l_code < 0) { s_input_error = 87; return 0; }   /* ERROR_INVALID_PARAMETER */
	if (!shell_input_allowed()) return 0;
	int l_mod_codes[3], l_n = 0, l_sent = 0;
	CGEventFlags f = 0;
	if (ctrl) { l_mod_codes[l_n++] = 0x37; f |= kCGEventFlagMaskCommand; }
	if (shift) { l_mod_codes[l_n++] = 0x38; f |= kCGEventFlagMaskShift; }
	if (alt) { l_mod_codes[l_n++] = 0x3A; f |= kCGEventFlagMaskAlternate; }
	for (int i = 0; i < l_n; i++) { CGEventRef e = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)l_mod_codes[i], true); CGEventPost(kCGHIDEventTap, e); CFRelease(e); l_sent++; }
	for (int l_down = 1; l_down >= 0; l_down--) {
		CGEventRef e = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)l_code, l_down != 0);
		CGEventSetFlags(e, f);
		CGEventPost(kCGHIDEventTap, e);
		CFRelease(e);
		l_sent++;
	}
	for (int i = l_n - 1; i >= 0; i--) { CGEventRef e = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)l_mod_codes[i], false); CGEventPost(kCGHIDEventTap, e); CFRelease(e); l_sent++; }
	return l_sent;
}

/* ------------------------------------------------------------------ the screen grab */

/* A region of the desktop, in pixels, into the caller's ARGB32 rows, opaque, as BitBlt from
   the screen. macOS shows other applications' windows only with the Screen Recording
   permission (System Settings, Privacy & Security, Screen & System Audio Recording); without
   it this answers 0 at once, and never asks the user itself. */
int shell_grab_screen(int x, int y, int w, int h, void *bits, int stride)
{
	if (!bits || w <= 0 || h <= 0 || stride < w * 4) return 0;
	if (!CGPreflightScreenCaptureAccess()) return 0;
	__block CGImageRef l_image = NULL;
	dispatch_semaphore_t l_done = dispatch_semaphore_create(0);
	CGPoint l_at = shell_display_point(x, y);
	NSScreen *l_main = [[NSScreen screens] count] ? [NSScreen screens][0] : nil;
	double k = l_main ? [l_main backingScaleFactor] : 1.0;
	[SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *c, NSError *err) {
		SCDisplay *d = nil;
		for (SCDisplay *l_d in [c displays]) if ([l_d displayID] == CGMainDisplayID()) d = l_d;
		if (err || !d) { dispatch_semaphore_signal(l_done); return; }
		SCContentFilter *l_filter = [[SCContentFilter alloc] initWithDisplay:d excludingWindows:@[]];
		SCStreamConfiguration *l_config = [[SCStreamConfiguration alloc] init];
		[l_config setSourceRect:CGRectMake(l_at.x, l_at.y, w / k, h / k)];
		[l_config setWidth:(size_t)w];
		[l_config setHeight:(size_t)h];
		[l_config setShowsCursor:NO];
		[SCScreenshotManager captureImageWithFilter:l_filter configuration:l_config completionHandler:^(CGImageRef img, NSError *e2) {
			if (!e2 && img) l_image = CGImageRetain(img);
			dispatch_semaphore_signal(l_done);
		}];
	}];
	if (dispatch_semaphore_wait(l_done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0 || !l_image) return 0;
	CGColorSpaceRef l_srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGContextRef c = CGBitmapContextCreate(bits, (size_t)w, (size_t)h, 8, (size_t)stride, l_srgb, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
	CGColorSpaceRelease(l_srgb);
	if (c) {
		CGContextDrawImage(c, CGRectMake(0, 0, w, h), l_image);
		CGContextRelease(c);
		for (int row = 0; row < h; row++) {
			uint32_t *px = (uint32_t *)((char *)bits + (size_t)row * stride);
			for (int col = 0; col < w; col++) px[col] |= 0xFF000000u;
		}
	}
	CGImageRelease(l_image);
	return c ? 1 : 0;
}

/* ------------------------------------------------------------------ the desktop, the clock, small things */

/* The virtual desktop (every screen together), in pixels from the main screen's top-left,
   as SM_XVIRTUALSCREEN and its kin answer it. */
static NSRect shell_virtual_desktop(double *a_scale)
{
	NSArray<NSScreen *> *l_all = [NSScreen screens];
	NSRect u = NSZeroRect;
	for (NSScreen *c in l_all) u = NSIsEmptyRect(u) ? [c frame] : NSUnionRect(u, [c frame]);
	NSScreen *l_main = [l_all count] ? l_all[0] : nil;
	*a_scale = l_main ? [l_main backingScaleFactor] : 1.0;
	double l_top = l_main ? NSMaxY([l_main frame]) : NSMaxY(u);
	return NSMakeRect(u.origin.x, l_top - NSMaxY(u), u.size.width, u.size.height);
}
int shell_screen_x(void) { double k; NSRect r = shell_virtual_desktop(&k); return (int)lround(r.origin.x * k); }
int shell_screen_y(void) { double k; NSRect r = shell_virtual_desktop(&k); return (int)lround(r.origin.y * k); }
int shell_screen_w(void) { double k; NSRect r = shell_virtual_desktop(&k); return (int)lround(r.size.width * k); }
int shell_screen_h(void) { double k; NSRect r = shell_virtual_desktop(&k); return (int)lround(r.size.height * k); }

/* Milliseconds from a steady clock (for intervals), and the local time of day in minutes. */
double shell_now_ms(void) { return (double)clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1.0e6; }
int shell_minutes_of_day(void)
{
	time_t t = time(NULL);
	struct tm l_local;
	localtime_r(&t, &l_local);
	return l_local.tm_hour * 60 + l_local.tm_min;
}

int shell_shift_held(void) { return shell_shift_down(); }

/* Open a file with its application, or a URL in the browser, as Windows' ShellExecute
   "open" does either: 1 on success. */
int shell_shell_open(const void *path)
{
	NSString *t = shell_text(path);
	if ([t length] == 0) return 0;
	NSURL *u = nil;
	if ([t rangeOfString:@"://"].location != NSNotFound || [t hasPrefix:@"mailto:"]) u = [NSURL URLWithString:t];
	if (!u) u = [NSURL fileURLWithPath:[t stringByExpandingTildeInPath]];
	if ([u isFileURL] && ![[NSFileManager defaultManager] fileExistsAtPath:[u path]]) return 0;
	return [[NSWorkspace sharedWorkspace] openURL:u] ? 1 : 0;
}

/* The application's icon (the Dock's), where Windows answers the main window's HICON. */
void *shell_main_icon(void) { shell_app(); return (__bridge void *)[NSApp applicationIconImage]; }

/* Windows' system colors by their COLOR_* index, as 0xRRGGBB in the app's current light or
   dark appearance: each index takes the Mac color that plays its part. */
unsigned int shell_system_color(int l_index)
{
	shell_app();
	NSColor *c;
	switch (l_index) {
		case 5: c = [NSColor textBackgroundColor]; break;                          /* COLOR_WINDOW */
		case 8: c = [NSColor textColor]; break;                                    /* COLOR_WINDOWTEXT */
		case 13: c = [NSColor selectedContentBackgroundColor]; break;              /* COLOR_HIGHLIGHT */
		case 14: c = [NSColor alternateSelectedControlTextColor]; break;           /* COLOR_HIGHLIGHTTEXT */
		case 15: c = [NSColor controlColor]; break;                                /* COLOR_BTNFACE */
		case 17: c = [NSColor disabledControlTextColor]; break;                    /* COLOR_GRAYTEXT */
		case 18: c = [NSColor controlTextColor]; break;                            /* COLOR_BTNTEXT */
		case 26: c = [NSColor linkColor]; break;                                   /* COLOR_HOTLIGHT */
		case 1: case 2: case 3: case 4: case 10: case 11: case 12: case 16: case 20: case 21: case 22:
			c = [NSColor windowBackgroundColor]; break;                          /* frames, faces, shadows */
		default: c = [NSColor labelColor];
	}
	/* Several Mac colors are translucent (white at 25% in dark mode for a control's face);
	   blend them over the window background, as they appear on screen. */
	__block unsigned int l_rgb = 0;
	[[NSApp effectiveAppearance] performAsCurrentDrawingAppearance:^{
		NSColor *r = [c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
		NSColor *g = [[NSColor windowBackgroundColor] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
		if (!r) return;
		double a = [r alphaComponent];
		double l_c[3] = {[r redComponent], [r greenComponent], [r blueComponent]};
		double l_g[3] = {g ? [g redComponent] : 1, g ? [g greenComponent] : 1, g ? [g blueComponent] : 1};
		unsigned int v[3];
		for (int i = 0; i < 3; i++) v[i] = (unsigned int)lround((l_c[i] * a + l_g[i] * (1 - a)) * 255);
		l_rgb = (v[0] << 16) | (v[1] << 8) | v[2];
	}];
	return l_rgb;
}

/* The standard text menu at the pointer, waited for: 1 Cut, 2 Copy, 3 Paste, 4 Select All, or
   0 when dismissed. */
static int s_text_menu_choice = 0;
@interface SSMenuChoice : NSObject
@end
@implementation SSMenuChoice
- (void)choose:(NSMenuItem *)i { s_text_menu_choice = (int)[i tag]; }
@end

int shell_text_menu(int can_cut, int can_copy, int can_paste, int can_select)
{
	shell_app();
	SSMenuChoice *l_target = [[SSMenuChoice alloc] init];
	NSMenu *m = [[NSMenu alloc] initWithTitle:@""];
	[m setAutoenablesItems:NO];
	NSString *const l_titles[] = {@"Cut", @"Copy", @"Paste", @"Select All"};
	NSString *const l_keys[] = {@"x", @"c", @"v", @"a"};
	int l_on[] = {can_cut, can_copy, can_paste, can_select};
	for (int i = 0; i < 4; i++) {
		if (i == 3) [m addItem:[NSMenuItem separatorItem]];
		NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:l_titles[i] action:@selector(choose:) keyEquivalent:l_keys[i]];
		[it setTarget:l_target];
		[it setTag:i + 1];
		[it setEnabled:l_on[i] != 0];
		[m addItem:it];
	}
	s_text_menu_choice = 0;
	[m popUpMenuPositioningItem:nil atLocation:[NSEvent mouseLocation] inView:nil];
	return s_text_menu_choice;
}

/* Handle events for `ms' milliseconds with or without a window (SHELL_DESKTOP.pump_for: a
   loop that is not the main window's, as simple_gui's windowless wake uses). */
void shell_pump_for(int ms)
{
	shell_app();
	NSDate *l_end = [NSDate dateWithTimeIntervalSinceNow:ms / 1000.0];
	while ([l_end timeIntervalSinceNow] > 0) {
		@autoreleasepool {
			NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:l_end inMode:NSDefaultRunLoopMode dequeue:YES];
			if (e) shell_send(e);
		}
	}
}

/* Windows message plumbing, kept for the code that calls it. The Mac reports these changes
   from its own notifications (53, 56, 57), so the filters answer "not mine"; the Alt-door
   character policy is Windows' own. */
int shell_setting_changed(const void *l_area) { (void)l_area; return 0; }
int shell_contrast_changed(unsigned int l_spi) { (void)l_spi; return 0; }
int shell_motion_changed(unsigned int l_spi) { (void)l_spi; return 0; }
void shell_system_colors_changed(void) { shell_push(56, shell_high_contrast_on(), 0, 0); shell_nudge(); }
int shell_syschar_is_ours(int l_ch)
{
	return (l_ch >= 'A' && l_ch <= 'Z') || (l_ch >= 'a' && l_ch <= 'z') || (l_ch >= '0' && l_ch <= '9')
		|| l_ch == '+' || l_ch == '-' || l_ch == '=';
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
