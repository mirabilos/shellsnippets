#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2019
#	mirabilos <m$(date +%Y)@mirbsd.de>
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
# Shows all packages whose installed version is not available from a
# repository any more. Compare: ../debian-dev/aptcheck
#
# Suggested extra usage:
# apt-cache policy $(mksh showlcl.sh | while read a b; do echo $a; done) | less

unset LANGUAGE
export LC_ALL=C

. "$(dirname "$0")"/../progress-bar

if ! T=$(mktemp /tmp/showlcl.XXXXXXXXXX); then
	print -ru2 "E: cannot create temporary file"
	exit 1
fi

set -o noglob

dpkg-query -Wf '${binary:Package}\n' | \
    xargs apt-cache showpkg >"$T"
init_progress_bar $(grep -c '^Package: ' <"$T")
exec <"$T"
rm "$T"
s=0
while IFS= read -r line; do
	case $s:$line {
	(0:Package:+(\ )*)
		draw_progress_bar
		p=${line##*([!:]):*( )}
		s=1
		;;
	(1:Versions:*(\ ))
		s=2
		;;
	(2:[0-9]*)
		set -- $line
		if [[ $2 = '(/var/lib/dpkg/status)' && -z $3 ]]; then
			print -ru2 -- "D: found $p (= $1)"
			print -r -- "$p (= $1)"
		fi
		;;
	(2:[!\ 0-9]*)
		s=0
		;;
	}
	#print -ru2 -- "D: s=$s l=${line@Q}"
done | {
	res=$(sort -u)
	print -ru2 -- "I: outputting result set to stdout"
	done_progress_bar 0
	print -r -- "$res"
}
