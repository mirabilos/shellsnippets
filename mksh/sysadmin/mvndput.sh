#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright (c) 2011
#	mirabilos <m$(date +%Y)@mirbsd.de>
#
# Provided that these terms and disclaimer and all copyright notices
# are retained or reproduced in an accompanying document, permission
# is granted to deal in this work without restriction, including un-
# limited rights to use, publicly perform, distribute, sell, modify,
# merge, give away, or sublicence.
#
# This work is provided "AS IS" and WITHOUT WARRANTY of any kind, to
# the utmost extent permitted by applicable law, neither express nor
# implied; without malicious intent or gross negligence. In no event
# may a licensor, author or contributor be held liable for indirect,
# direct, other damage, loss, or other issues arising in any way out
# of dealing in the work, even if advised of the possibility of such
# damage or existence of a defect, except proven that it results out
# of said person's immediate fault when using the work as intended.

whereami=$(realpath "$(dirname "$0")")

usage() {
	print -u2 "Syntax: /opt/mvn-debs/mvndput.sh job squeeze main *.changes"
	exit ${1:-2}
}

(( $# < 4 )) && usage
jobname=$1
suitename=$2
distname=$3
shift
shift
shift

if [[ $jobname != +([a-z0-9_-]) ]]; then
	print -u2 "Invalid job name '$jobname'"
	usage
fi

if [[ $suitename != +([a-z0-9_]) ]]; then
	print -u2 "Invalid suite name '$suitename'"
	usage
fi

if [[ $distname != +([a-z0-9_-]) ]]; then
	print -u2 "Invalid dist name '$distname'"
	usage
fi

if ! T=$(mktemp /tmp/mvndput.XXXXXXXXXX); then
	print -u2 Cannot create temporary file.
	exit 255
fi
tag=mvndebs$RANDOM

rc=0
for changesfile in "$@"; do
	if [[ $changesfile != *.changes ]]; then
		print -u2 "Not a *.changes file: '$changesfile'"
		continue
	fi

	pkgname=$(sed -e '/^-----BEGIN PGP/,/^$/d' -e '/^$/,$d' \
	    <"$changesfile" | sed -n '/^Source: /s///p')
	if [[ $pkgname != [a-z0-9]+([a-z0-9+.-]) ]]; then
		print -u2 "Invalid Source '$pkgname' in '$changesfile'"
		continue
	fi

	cat >"$T" <<-EOF
		[$tag]
		method = local
		allow_unsigned_uploads = 1
		incoming = ${whereami}/$jobname/dists/$suitename/$distname/Pkgs/$pkgname
		pre_upload_command = mkdir -p ${whereami}/$jobname/dists/$suitename/$distname/Pkgs/$pkgname
		post_upload_command = mksh ${whereami}/mvndebri.sh ${whereami} $jobname $suitename
EOF
	print -u2 "Processing ${changesfile}..."
	dput -c "$T" $tag "$changesfile"
	rc=$?
	if (( rc )); then
		print -u2 "===> failed with errorlevel $rc"
		rc=1
	fi
done
rm -f "$T"
(( rc )) && usage 1
exit 0
