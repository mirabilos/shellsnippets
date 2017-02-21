#!/bin/mksh
#-
# Copyright © 2017
#	mirabilos <mirabilos@evolvis.org>
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

export LC_ALL=C; unset LANGUAGE
cd "$(dirname "$0")"
grv=0
gcc -Wall -fprofile-arcs -ftest-coverage csv2ssv.c -o csv2ssv || exit 255

runtest() {
	local name=$1; shift

	[[ $name = -E* ]] || cat >x.csv
	if [[ $name = -* ]]; then
		./csv2ssv "$@" x.csv >/dev/null 2>&1
		set -A rvs -- ${PIPESTATUS[@]} 0
	else
		./csv2ssv "$@" x.csv | \
		    diff -u --label expected --label got /dev/fd/4 -
		set -A rvs -- ${PIPESTATUS[@]}
	fi
	set -A rvr
	rv=0
	case ${rvs[1]} {
	(0)
		;;
	(1)
		rv=1
		rvr+=(diff-delta)
		;;
	(*)
		rv=1
		rvr+=(diff-trouble-${rvs[1]})
		;;
	}
	case ${rvs[0]} {
	(0)
		if [[ $name = -* ]]; then
			rv=1
			rvr+=(expected-fail)
		fi
		;;
	(*)
		if [[ $name != -* ]]; then
			rv=1
			rvr+=(unexpected-${rvs[0]})
		fi
		;;
	}
	if (( rv )); then
		print -r -- "FAIL $name ${rvr[@]}"
		grv=1
	else
		print -r -- "pass $name"
	fi
}

runtest usage -h <<\EOI 4<<\EOO
EOI
EOO

runtest -usage -? <<\EOI
EOI

runtest -args foo <<\EOI
EOI

:>x.csv
runtest -Esize

chmod 000 x.csv
runtest -Eopen

rm -f x.csv

runtest basic-quoted -s , -q \" <<\EOI 4<<\EOO
Key,Value
first,1\"23
4""5,6"7"8\"
second,ab
third,abc
fourth,"ab

c
d
e"
fifth,a
sixth,"a
b"
EOI
KeyValue
first1\234"5,678\
secondab
thirdabc
fourthabcde
fiftha
sixthab
EOO
#"

runtest basic-unquoted -s , <<\EOI 4<<\EOO
Key,Value
first,1\"23
4""5,6"7"8\"
second,ab
third,abc
fourth,"ab

c
d
e"
fifth,a
EOI
KeyValue
first1\"23
4""56"7"8\"
secondab
thirdabc
fourth"ab

c
d
e"
fiftha
EOO

print 'a\0b' >x.csv
runtest -Enormalnul

runtest -normalsep <<\EOI
ab
EOI

print '"a\0b"' >x.csv
runtest -Eqnul -q \"

runtest -qsep -q \" <<\EOI
"ab"
EOI

print -nr -- "x" >x.csv
runtest -Eueof

print -nr -- "x" >x.csv
runtest -Ecreof

runtest -qeof -q \" <<\EOI
foo"bar
EOI
#"

gcov csv2ssv.c || exit 255
exit $grv
