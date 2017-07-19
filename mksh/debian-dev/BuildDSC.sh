#!/bin/mksh
# $MirOS: contrib/hosted/tg/deb/BuildDSC.sh,v 1.20 2016/11/12 04:02:48 tg Exp $
#-
# Copyright (c) 2010, 2011
#	Thorsten Glaser <t.glaser@tarent.de>
# Copyright © 2015, 2016
#	mirabilos <m@mirbsd.org>
#
# Provided that these terms and disclaimer and all copyright notices
# are retained or reproduced in an accompanying document, permission
# is granted to deal in this work without restriction, including un‐
# limited rights to use, publicly perform, distribute, sell, modify,
# merge, give away, or sublicence.
#
# This work is provided “AS IS” and WITHOUT WARRANTY of any kind, to
# the utmost extent permitted by applicable law, neither express nor
# implied; without malicious intent or gross negligence. In no event
# may a licensor, author or contributor be held liable for indirect,
# direct, other damage, loss, or other issues arising in any way out
# of dealing in the work, even if advised of the possibility of such
# damage or existence of a defect, except proven that it results out
# of said person’s immediate fault when using the work as intended.
#-
# The current working directory, or else the directory in which this
# script resides, must be the root directory of a (extracted) Debian
# source package. It will then be renamed to the proper dirname, and
# a source package (*.dsc + others) will be created, then it will be
# renamed back.
# -a: pass -sa to dpkg-buildpackage (include origtgz)
# -d: pass -d to dpkg-buildpackage (ignore B-D absence)
# -N: pass -nc to dpkg-buildpackage (do not clean)
# -s arg: make a snapshot with “arg” being the version number suffix
# -S: build a snapshot with snapshot.YYYYMMDD.HHMMSS (UTC) as suffix
# -v: pass -v$OPTARG to dpkg-buildpackage (changelog since)
# Any further arguments will be passed to debian/rules via MAKEFLAGS

# sanitise environment
unset LANGUAGE
export LC_ALL=C
cd "$(realpath .)"

# preload
sync
date >/dev/null
stime_rfc=$(date +"%a, %d %b %Y %H:%M:%S %z")
stime_vsn=$(date -u +"%Y%m%d.%H%M%S")

opta=
optd=
optN=
optv=
snap=0
ssuf=
while getopts "adNSs:v:" ch; do
	case $ch {
	(a)	opta=-sa
		;;
	(+a)	opta=
		;;
	(d)	optd=-d
		;;
	(+d)	optd=
		;;
	(N)	optN=-nc
		;;
	(+N)	optN=
		;;
	(S)	snap=1
		ssuf=snapshot.$stime_vsn
		;;
	(+S)	snap=0
		ssuf=
		;;
	(s)	snap=1
		ssuf=$OPTARG
		;;
	(+s)	snap=0
		ssuf=
		;;
	(v)	optv=-v$OPTARG
		;;
	(*)	print -u2 Syntax error.
		exit 1
		;;
	}
done
shift $((OPTIND - 1))
export MAKEFLAGS="$*"

if (( snap )) && [[ $DEBEMAIL != +([A-Za-z])*' <'*'>' ]]; then
	print -u2 'Please set $DEBEMAIL to "First M. Last <email@domain.com>"'
	exit 1
fi

rmc=0
while :; do
	echo >&2 "=== trying . = $(pwd)"
	dh_testdir >/dev/null 2>&1 && break
	if [[ -s debian/control.in && -s debian/rules && \
	    -x debian/rules && ! -e debian/control ]]; then
		rmc=1
		debian/rules debian/control
	fi
	dh_testdir >/dev/null 2>&1 && break
	(( rmc )) && debian/rules remove/control
	rmc=0
	cd "$(dirname "$0")"
	print -u2 "=== trying basedir = $(pwd)"
	dh_testdir >/dev/null 2>&1 && break
	if [[ -s debian/control.in && -s debian/rules && \
	    -x debian/rules && ! -e debian/control ]]; then
		rmc=1
		debian/rules debian/control
	fi
	dh_testdir >/dev/null 2>&1 && break
	(( rmc )) && debian/rules remove/control
	print -u2 "FAILED! Please change to the correct directory."
	exit 1
done
mydir=$(pwd)
pkgstem=$(dpkg-parsechangelog -n1 | sed -n '/^Source: /s///p')
version=$(dpkg-parsechangelog -n1 | sed -n '/^Version: /s///p')
if (( snap )); then
	updir=$(cd ..; pwd)
	if ! T=$(mktemp "$updir/BuildDSC.tmp.XXXXXXXXXX"); then
		(( rmc )) && debian/rules remove/control
		print -u2 Could not create temporary file.
		exit 1
	fi
	cat debian/changelog >"$T"
	touch -r debian/changelog "$T"
	dist=$(dpkg-parsechangelog -n1 | sed -n '/^Distribution: /s///p')
	if [[ $dist = UNRELEASED || $dist = x* ]]; then
		# we’re at “current” already, reduce
		version=$version'~'$ssuf
	else
		# we’re at an uploaded version, raise
		version=$version'+'$ssuf
	fi
	print "$pkgstem ($version) UNRELEASED; urgency=low\n\n  *" \
	    "Automatically built snapshot (not backport) package.\n\n --" \
	    "$DEBEMAIL  $stime_rfc\n" >debian/changelog
	cat "$T" >>debian/changelog
	touch -r "$T" debian/changelog
	if (( rmc )); then
		rm -f debian/control
		debian/rules debian/control
	fi
fi
upstreamversion=${version%%-*([!-])}
upstreamversion=${upstreamversion#+([0-9]):}
cd ..
curname=${mydir##*/}
newname=$pkgstem-$upstreamversion
[[ $newname = $curname ]] || mv "$curname" "$newname"
cd "$newname"
dpkg-buildpackage -rfakeroot -S -I -i $optd $optN $opta $optv -us -uc
rv=$?
[[ -n $optN ]] || fakeroot debian/rules clean
cd ..
[[ $newname = $curname ]] || mv "$newname" "$curname"

cd "$curname"
if (( snap )); then
	cat "$T" >debian/changelog
	touch -r "$T" debian/changelog
	rm -f "$T"
fi
(( rmc )) && debian/rules remove/control

exit $rv
