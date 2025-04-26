#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2015
#	mirabilos
# Copyright © 2007, 2008, 2012, 2013, 2014
#	Thorsten “mirabilos” Glaser <tg@mirbsd.org>
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
# Backend for auto-completion of schools.

unset HTTP_PROXY

export LC_ALL=C
unset LANGUAGE
set +U

function die {
	print 'Status: 400\r'
	print 'Content-Type: text/plain; charset="UTF-8"\r'
	print '\r'
	print -r -- "$@" | sed $'s/$/\r/'
	exit 0
}

# escape string into JSON string (with surrounding quotes)
function json_escape {
	local o=\" s
	if (( $# )); then
		read -raN-1 s <<<"$*"
		unset s[${#s[*]}-1]
	else
		read -raN-1 s
	fi
	local -i i=0 n=${#s[*]} wc
	local -Uui16 -Z7 x
	local -i1 ch

	while (( i < n )); do
		(( ch = x = wc = s[i++] ))
		case $wc {
		(8) o+=\\b ;;
		(9) o+=\\t ;;
		(10) o+=\\n ;;
		(12) o+=\\f ;;
		(13) o+=\\r ;;
		(34) o+=\\\" ;;
		(92) o+=\\\\ ;;
		(*)
			if (( wc < 0x20 || wc > 0xFFFD || \
			    (wc >= 0xD800 && wc <= 0xDFFF) || \
			    (wc > 0x7E && wc < 0xA0) )); then
				o+=\\u${x#16#}
			else
				o+=${ch#1#}
			fi
			;;
		}
	done
	REPLY="$o\""
}

set -A fields -- q

function dofield {
	if [[ $1 != *=* ]]; then
		#print -r -- "D: non-field '$1' found"
		return
	fi
	fldk=${1%%=*}
	fldv=${1#*=}
	# unescape spaces
	fldv=${fldv//'+'/ }
	# unescape percent via backslash-unescaping ksh print builtin
	fldv=${fldv//\\/\\\\}
	fldv=${fldv//@(%)/\\x}
	fldv=$(print -- "$fldv".)
	fldv=${fldv%.}
	for x in "${fields[@]}"; do
		[[ $fldk = "$x" ]] || continue
		eval $x=\$fldv
		break
	done
}

inp=$QUERY_STRING
while [[ $inp = *'&'* ]]; do
	fld=${inp%%'&'*}
	inp=${inp#*'&'}
	dofield "$fld"
done
[[ -n $inp ]] && dofield "$inp"

set -U
# trim
q=${q##+([	  ])}
q=${q%%+([	  ])}
# check
[[ -n $q ]] || die 'Leerer Suchbegriff'
export LC_ALL=C.UTF-8
[[ $q = +([ !\"&-*,-:A-Za-z ®ÄÖÜßäçèéöüž]) ]] || die 'Ungültiges Zeichen im Suchbegriff'

# ugh…
q=${q//\\/\\5C}
q=${q//'('/\\28}
q=${q//')'/\\29}
q=${q//'*'/\\2A}

# words to wildcards
q=\*${q//+([  ])/*}\*

# to LDAP
. /usr/local/share/teckids/mk/assockit.ksh
. /usr/local/share/teckids/mk/assoldap.ksh

asso_setldap_sasl r -- -b ou=Schulen,ou=Contacts,dc=teckids,dc=org \
    "(o=$q)" o l
asso_loadk r

# JSON output
print 'Content-Type: application/json; charset="UTF-8"\r'
print '\r'
print -n '['
sep=
for dn in "${asso_y[@]}"; do
	o=$(asso_getv r "$dn" o 0)
	l=$(asso_getv r "$dn" l 0)
	[[ -n $o ]] || continue
	print -nr -- "$sep{\"o\":${|json_escape "$o";},\"l\":${|json_escape "$l";}}"
	sep=,
done
print -n ']'
exit 0
