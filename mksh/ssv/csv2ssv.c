/*-
 * Copyright (c) 2015, 2017, 2020
 *	mirabilos <m$(date +%Y)@mirbsd.de>
 *
 * Provided that these terms and disclaimer and all copyright notices
 * are retained or reproduced in an accompanying document, permission
 * is granted to deal in this work without restriction, including un-
 * limited rights to use, publicly perform, distribute, sell, modify,
 * merge, give away, or sublicence.
 *
 * This work is provided "AS IS" and WITHOUT WARRANTY of any kind, to
 * the utmost extent permitted by applicable law, neither express nor
 * implied; without malicious intent or gross negligence. In no event
 * may a licensor, author or contributor be held liable for indirect,
 * direct, other damage, loss, or other issues arising in any way out
 * of dealing in the work, even if advised of the possibility of such
 * damage or existence of a defect, except proven that it results out
 * of said person's immediate fault when using the work as intended.
 */

#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <err.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#ifndef O_BINARY
#define O_BINARY	0
#endif

#ifndef SIZE_MAX
#ifdef SIZE_T_MAX
#define SIZE_MAX	SIZE_T_MAX
#else
#define SIZE_MAX	((size_t)-1)
#endif
#endif

static __attribute__((__noreturn__)) void
usage(int rv)
{
	fprintf(stderr, "Usage: csv2ssv [-q quotechar] [-s separator] infile\n"
	    "    Default separator is HT (Tab), quotechar is none.\n"
	    "Example: csv2ssv -q \\\" -s \\; foo.csv >foo.ssv\n");
	exit(rv);
}

int
main(int argc, char *argv[])
{
	unsigned char c;
	const unsigned char *cp;
	int i;
	unsigned char cq = 0, cs = '\t';
	const unsigned char *bp, *ep;
	unsigned char *mp;
	struct stat sb;

	while ((i = getopt(argc, argv, "hq:s:")) != -1)
		switch (i) {
		case 'h':
			usage(0);
		case 'q':
			cq = (unsigned char)optarg[0];
			break;
		case 's':
			cs = (unsigned char)optarg[0];
			break;
		default:
			usage(1);
		}
	argc -= optind;
	argv += optind;

	if (argc != 1)
		usage(1);

	if ((i = open(argv[0], O_RDONLY | O_BINARY)) == -1)
		err(1, "%s %s", "open", argv[0]);
	if (fstat(i, &sb))
		err(1, "%s %s", "stat", argv[0]);
	if (sb.st_size < 1)
		errx(1, "%s %s", "file too small", argv[0]);
	if ((sizeof(off_t) > sizeof(size_t)) && (sb.st_size > (off_t)SIZE_MAX))
		errx(1, "%s %s", "file too large", argv[0]);
	if ((mp = (unsigned char *)mmap(NULL, (size_t)sb.st_size, PROT_READ,
	    MAP_PRIVATE, i, 0)) == MAP_FAILED)
		err(1, "%s %s", "mmap", argv[0]);
	cp = bp = mp;
	ep = mp + ((size_t)sb.st_size - 1);

	setlinebuf(stdout);

	while (cp <= ep) {
 normal:
		switch ((c = *cp++)) {
		case 0x00:
		case 0x1F:
			errx(1, "\\x%02X found at offset %zu",
			    (unsigned int)c, (size_t)(cp - mp) - 1);
		case 0x0D:
			break;
		case 0x0A:
			if (cp > ep)
				goto nl_out;
			continue;
		default:
			if (c == cq || c == cs)
				break;
			continue;
		}

		if ((size_t)(cp - bp) > 1)
			fwrite(bp, (size_t)(cp - bp) - 1, 1, stdout);

		bp = cp;
		if (c == cs) {
			fputc(0x1F, stdout);
			continue;
		}

		if (c != cq) {
			/* 0x0D */
			while (cp <= ep) {
				switch ((c = *cp++)) {
				case 0x0A:
					bp = cp;
					/* FALLTHROUGH */
				default:
					--cp;
					--bp;
					goto normal;
				case 0x0D:
					break;
				}
			}
			continue;
		}

		/* c == cq */
		while (cp <= ep) {
			if (!(c = *cp++) || c == 0x1F) {
				errx(1, "\\x%02X found at offset %zu",
				    (unsigned int)c, (size_t)(cp - mp) - 1);
			} else if (c == cq) {
				/* next a quote? */
				if ((cp <= ep) && (*cp == cq)) {
					/* yes, un-escape */
					++cp;
				} else
					goto quote_out;
			} else if (c == 0x0D) {
				/* next a newline? */
				if ((cp <= ep) && (*cp == 0x0A)) {
					/* yes, skip it */
					++cp;
				}
			} else if (c == 0x0A) {
				/* encode newline as CR */
				c = 0x0D;
			}
			fputc(c, stdout);
		}
		errx(1, "unexpected EOF within quote starting at offset %zu",
		    (size_t)(bp - mp) - 1);

 quote_out:
		bp = cp;
	}
	errx(1, "unexpected EOF (newline expected)");

 nl_out:
	fwrite(bp, (size_t)(cp - bp), 1, stdout);
	fflush(stdout);

	if (munmap(mp, (size_t)sb.st_size))
		err(2, "%s %s", "munmap", argv[0]);
	if (close(i))
		err(2, "%s %s", "close", argv[0]);

	return (0);
}
