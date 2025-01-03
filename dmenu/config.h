/* See LICENSE file for copyright and license details. */
/* Default settings; can be overriden by command line. */

static int topbar = 1;                      /* -b  option; if 0, dmenu appears at bottom     */
/* -fn option overrides fonts[0]; default X11 font or font set */
static const char *fonts[] = {
	"monospace:size=11.25"
};
static const char *prompt      = NULL;      /* -p  option; prompt to the left of input field */
static const char col_fg[]          = "#e6eaea";
static const char col_bg[]          = "#101719";
static const char col_border_norm[] = "#7aa4a1";
static const char *colors[SchemeLast][2] = {
	/*     fg         bg       */
	[SchemeNorm] = { col_fg, col_bg },
	[SchemeSel] = { col_bg, col_border_norm },
	[SchemeOut] = { col_bg, col_border_norm },
};
/* -l option; if nonzero, dmenu uses vertical list with given number of lines */
static unsigned int lines      = 0;

/*
 * Characters not considered part of a word while deleting words
 * for example: " /?\"&[]"
 */
static const char worddelimiters[] = " ";
