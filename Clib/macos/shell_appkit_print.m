/* shell_appkit_print.m - simple_shell's printing on macOS.
   The contract is the Windows half's (simple_shell_print.h): begin a document on a named
   printer, pages, end or abort, the printer's capabilities, and the "DC" the program draws
   through. Here the DC is a cairo PDF surface, which simple_cairo's off-Windows
   make_for_printer_dc references (as a window's backing image stands for its DC): each
   page's surface draws into the one PDF and its show_page adds a page. Units are points, so
   the reported resolution is 72 dots per inch and nothing is unprintable. At the end the PDF
   goes to the printer through CUPS, or to the output file when one was given. */

#import <Foundation/Foundation.h>
#include <cairo.h>
#include <cairo-pdf.h>
#include <cups/cups.h>
#include <stdatomic.h>
#include <unistd.h>
#include "shell_appkit.h"

static cairo_surface_t *s_doc = NULL;
static int s_in_page = 0;
static atomic_int s_claim = 0;   /* the one document, claimed atomically (two processors cannot both begin it) */
static double s_page_w = 0, s_page_h = 0;
static char s_printer[256], s_title[256], s_path[2048];
static int s_to_printer = 0;

/* UTF-8 `a_text' as UTF-16 into `buf' (the caller reads 16-bit units), from `a_at'; the new length. */
static int shell_print_put(void *buf, int cap, int a_at, const char *a_text)
{
	NSString *t = [NSString stringWithUTF8String:a_text] ?: @"";
	NSUInteger n = [t length];
	if (a_at + (int)n + 2 > cap) return -1;
	[t getCharacters:(unichar *)buf + a_at range:NSMakeRange(0, n)];
	((unichar *)buf)[a_at + n] = 0;
	return a_at + (int)n;
}

/* The default printer's name, UTF-16; its length, or 0 when there is none. */
int shell_print_default(void *l_buf, int l_cap)
{
	cups_dest_t *d;
	int l_n = 0, l_count = cupsGetDests(&d);
	if (!l_buf || l_cap <= 0) { cupsFreeDests(l_count, d); return 0; }
	((unichar *)l_buf)[0] = 0;
	for (int i = 0; i < l_count; i++)
		if (d[i].is_default && !d[i].instance) { int r = shell_print_put(l_buf, l_cap, 0, d[i].name); l_n = r < 0 ? 0 : r; break; }
	cupsFreeDests(l_count, d);
	return l_n;
}

/* Every printer's name, each followed by a newline, UTF-16; the characters written. */
int shell_print_names(void *l_buf, int l_cap)
{
	cups_dest_t *d;
	int l_len = 0, l_count = cupsGetDests(&d);
	if (!l_buf || l_cap <= 0) { cupsFreeDests(l_count, d); return 0; }
	((unichar *)l_buf)[0] = 0;
	for (int i = 0; i < l_count; i++) {
		if (d[i].instance) continue;
		int r = shell_print_put(l_buf, l_cap, l_len, d[i].name);
		if (r < 0) break;
		((unichar *)l_buf)[r] = '\n';
		l_len = r + 1;
		((unichar *)l_buf)[l_len] = 0;
	}
	cupsFreeDests(l_count, d);
	return l_len;
}

static int shell_print_known(const char *a_name)
{
	cups_dest_t *d;
	int l_count = cupsGetDests(&d), l_known = cupsGetDest(a_name, NULL, l_count, d) != NULL;
	cupsFreeDests(l_count, d);
	return l_known;
}

/* The paper in points: Windows' DMPAPER codes 1 Letter, 5 Legal, 9 A4; 0 the region's own
   (A4 where the metric system is used, Letter elsewhere). */
static void shell_print_paper(int a_paper, int a_landscape)
{
	if (a_paper == 0) a_paper = [[[NSLocale currentLocale] objectForKey:NSLocaleUsesMetricSystem] boolValue] ? 9 : 1;
	switch (a_paper) {
		case 5: s_page_w = 612; s_page_h = 1008; break;
		case 9: s_page_w = 595.276; s_page_h = 841.890; break;
		default: s_page_w = 612; s_page_h = 792;
	}
	if (a_landscape) { double t = s_page_w; s_page_w = s_page_h; s_page_h = t; }
}

/* Begin a document on `l_printer' (a known printer, as on Windows) titled `l_title', written
   to `l_output' when that is not empty, on paper `l_paper' in landscape when asked. 1 when it began. */
int shell_print_begin(const void *l_printer, const void *l_title, const void *l_output, int l_paper, int l_landscape)
{
	const char *p = (const char *)l_printer, *t = (const char *)l_title, *o = (const char *)l_output;
	int l_expected = 0;
	if (!p || !p[0] || !shell_print_known(p)) return 0;
	if (!atomic_compare_exchange_strong(&s_claim, &l_expected, 1)) return 0;
	snprintf(s_printer, sizeof s_printer, "%s", p);
	snprintf(s_title, sizeof s_title, "%s", t && t[0] ? t : "Document");
	s_to_printer = !(o && o[0]);
	if (s_to_printer) snprintf(s_path, sizeof s_path, "%s/simple_shell_print_%d.pdf", [NSTemporaryDirectory() fileSystemRepresentation], (int)getpid());
	else snprintf(s_path, sizeof s_path, "%s", o);
	shell_print_paper(l_paper, l_landscape);
	s_doc = cairo_pdf_surface_create(s_path, s_page_w, s_page_h);
	if (cairo_surface_status(s_doc) != CAIRO_STATUS_SUCCESS) {
		cairo_surface_destroy(s_doc);
		s_doc = NULL;
		atomic_store(&s_claim, 0);
		return 0;
	}
	cairo_pdf_surface_set_metadata(s_doc, CAIRO_PDF_METADATA_TITLE, s_title);
	s_in_page = 0;
	return 1;
}

int shell_print_begin_page(void)
{
	if (!s_doc || s_in_page) return 0;
	s_in_page = 1;
	return 1;
}

/* The page itself is added by the program's show_page on the surface. */
int shell_print_end_page(void)
{
	if (!s_doc || !s_in_page) return 0;
	s_in_page = 0;
	return 1;
}

static void shell_print_close(void)
{
	cairo_surface_destroy(s_doc);
	s_doc = NULL;
	s_in_page = 0;
	atomic_store(&s_claim, 0);
}

/* End the document: the PDF is written, then printed through CUPS (or left at the output
   path). 1 when it was accepted. */
int shell_print_end(void)
{
	if (!s_doc) return 0;
	s_in_page = 0;
	cairo_surface_finish(s_doc);
	int l_ok = cairo_surface_status(s_doc) == CAIRO_STATUS_SUCCESS;
	if (l_ok && s_to_printer) {
		l_ok = cupsPrintFile(s_printer, s_path, s_title, 0, NULL) > 0;
		unlink(s_path);
	}
	shell_print_close();
	return l_ok ? 1 : 0;
}

/* Throw the document away, the partial file with it. */
void shell_print_abort(void)
{
	if (!s_doc) return;
	cairo_surface_finish(s_doc);
	unlink(s_path);
	shell_print_close();
}

/* The printer's capabilities, by Windows' GetDeviceCaps index: 88/90 dots per inch (72: the
   units are points), 8/10 printable width and height, 110/111 the whole page, 112/113 the
   unprintable offsets (none on a PDF page). */
int shell_print_caps(int l_index)
{
	if (!s_doc) return 0;
	switch (l_index) {
		case 88: case 90: return 72;
		case 8: case 110: return (int)lround(s_page_w);
		case 10: case 111: return (int)lround(s_page_h);
		default: return 0;
	}
}

void *shell_print_dc(void) { return s_doc; }
int shell_print_in_page(void) { return s_in_page; }
