#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright (c) 2002, 2003, 2004, 2006, 2007, 2008, 2009, 2010, 2012
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

# for debugging {{{
#print Content-type: text/plain
#print
#exec 2>&1
#set -x
# end debugging }}}

# basic input validation
if [[ $AUTH_TYPE != Basic || $HTTPS != on || -z $REMOTE_USER || \
    $REQUEST_METHOD != GET || -n $QUERY_STRING ]]; then
	print Status: 400 Bad Request
	print
	print Sorry, use the script or leave it.
	exit 1
fi

### BEGIN imported code {{{
# From MirOS: src/bin/mksh/dot.mkshrc,v 1.43 2009/05/31 17:17:33 tg Rel $

allu=QWERTYUIOPASDFGHJKLZXCVBNM
alll=qwertyuiopasdfghjklzxcvbnm
alln=0123456789

function Lb64decode {
	typeset u=$-
	set +U
	typeset c s="$*" t=
	[[ -n $s ]] || { s=$(cat;print .); s=${s%.}; }
	typeset -i i=0 n=${#s} p=0 v x
	typeset -i16 o

	while (( i < n )); do
		c=${s:(i++):1}
		case $c {
		(=)	break ;;
		([A-Z])	(( v = 1#$c - 65 )) ;;
		([a-z])	(( v = 1#$c - 71 )) ;;
		([0-9])	(( v = 1#$c + 4 )) ;;
		(+)	v=62 ;;
		(/)	v=63 ;;
		(*)	continue ;;
		}
		(( x = (x << 6) | v ))
		case $((p++)) {
		(0)	continue ;;
		(1)	(( o = (x >> 4) & 255 )) ;;
		(2)	(( o = (x >> 2) & 255 )) ;;
		(3)	(( o = x & 255 ))
			p=0
			;;
		}
		t=$t\\x${o#16#}
	done
	print -n $t
	[[ $u = *U* ]] && set -U
	:
}

### END imported code }}}

# get user information from LDAP
v_givenName=
v_mailPrimaryAddress=
v_o=
v_sn=
env LDAPTLS_CACERT=/etc/ssl/certs/dc.lan.tarent.de.cer \
    ldapsearch -x -LLL -ZZ -H ldap://dc1.lan.tarent.de -b dc=tarent,dc=de \
    uid="$REMOTE_USER" givenName mailPrimaryAddress o sn | \
    tr '\n' '' | sed 's/ //g' | tr '' '\n' |&
while read -p key value; do
	# parse ldap "foo:: BARINBASE64" lines
	[[ $key = *:: ]] && value=$(Lb64decode "$value")
	# parse ldap "foo: barunencoded" lines
	key=${key%%*(:)}
	eval v_$key=\$value
done

# required fields
if [[ -z $v_givenName || -z $v_mailPrimaryAddress || -z $v_sn ]]; then
	print Status: 400 Bad Request
	print
	print You don\'t exist. Go away.
	exit 1
fi

# output the response
print Content-type: text/plain
print Entropy: $RANDOM
print
print status ok
print name $v_givenName $v_sn
print mail $v_mailPrimaryAddress | tr $allu $alll
print comm $v_o
exit 0
