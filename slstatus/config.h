/*
 * interval is no longer used by slstatus.c.
 * But it is required for compilation (components/netspeeds.c).
 */
const unsigned int interval = 1000;

static const char unknown_str[] = "n/a";

#define MAXLEN 2048

static const struct arg args[] = {
	/* { battery_perc, "battery: %s%% ", "<battery>" },
	{ battery_remaining, "%s | ", "<battery>" }, */
	{ run_command, "source: %s | ", "pamixer --default-source --get-volume-human" },
	{ run_command, "sink: %s | ",   "pamixer --get-volume-human" },
	{ datetime, "%s ",              "%F %R" },
};
