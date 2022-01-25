#!/bin/mksh
# $Id: getjpics.cgi 2530 2011-11-23 15:09:41Z tglase $
#-
# Copyright © 2011
#	Thorsten Glaser <t.glaser@tarent.de>
# Copyright (c) 2002, 2003, 2004, 2006, 2007, 2008, 2009, 2010, 2011
#	Thorsten Glaser <tg@mirbsd.org>
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
#-
# root@ucs:/usr/lib/cgi-bin/getjpics.cgi

export LC_ALL=C
unset LANGUAGE

if [[ $1 != really ]]; then
	cd /var/www/jpics
	if ! T=$(mktemp /var/www/jpics/index.htm.XXXXXXXXXX); then
		print Status: 501 Internal Server Error
		print
		print Could not create temporary file.
		exit 1
	fi
	chmod 644 "$T"
	(mksh "$0" really "$@" >"$T") 2>&1 | \
	    logger -t 'getjpics stderr'
	mv -f "$T" index.htm
	print Status: 302 Moved
	print Location: https://ucs.tarent.de/jpics/index.htm
	print
	print 'Moved <a href="/jpics/index.htm">here</a>.'
	exit 0
fi

function ldapshow {
	ldapsearch -xLLL "$@" | \
	    tr '\n' $'\a' | sed -e $'s/\a //g' | tr $'\a' '\n'
	return ${PIPESTATUS[0]}
}

function b64decode {
	[[ -o utf8-mode ]]; local u=$?
	set +U
	local c s="$*" t=
	[[ -n $s ]] || { s=$(cat;print .); s=${s%.}; }
	local -i i=0 n=${#s} p=0 v x
	local -i16 o

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
		t+=\\x${o#16#}
	done
	print -n $t
	(( u )) || set -U
}

function emit_html_start {
	cat <<'EOF'
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
 "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en"><head>
 <meta http-equiv="cache-control" content="no-cache" />
 <meta http-equiv="content-type" content="text/html; charset=utf-8" />
 <title>Jabber User Overview</title>
</head><body>
<h1>Jabber Groups</h1>
<p>As the Jabber server sees them.
 <a href="/cgi-bin/getjpics.cgi">Refresh</a> (takes a few minutes!)
</p>
EOF
}

function emit_html_grpbeg {
	local cn=$1 dsc=$2

	print "<h2>$cn</h2>"
	[[ -n $dsc ]] && print "<p style=\"font-size:large;\">$dsc</p>"
	print '<table style="border:3px blue outset;" cellpadding="3">'
}

function emit_html_grpend {
	print '</table>'
}

function emit_html_end {
	print '</body></html>'
}

function process_dn {
	local dn=$1 uid curdn curname curuid curphoto curtel skipped
	local key value iserr e tdstyle

	print '<tr>'
	if [[ $dn != uid=+([0-9a-z-]),cn=users,dc=tarent,dc=de ]]; then
		print '<td colspan="2" style="background-color:red;"' \
		    'align="left" valign="top">'
		print "\tInvald member DN: '$dn'"
		print '</td></tr>'
		return
	fi
	uid=${dn%%,*}
	uid=${uid#*=}
	curdn= curname= curuid= curphoto= curtel= skipped=-
	set -A curmails
	ldapshow -b cn=users,dc=tarent,dc=de -s one \
	    "(&(uid=${uid})(isJabberAccount=1))" \
	    dn mail uid jpegPhoto displayName telephoneNumber |&
	while read -p key value; do
		if [[ $skipped != - ]]; then
			skipped+="$key $value|"
			continue
		fi
		case $key {
		(dn:)		curdn=$value ;;
		(dn::)		curdn=$(b64decode "$value") ;;
		(mail:)		curmails+=("$value") ;;
		(mail::)	curmails+=($(b64decode "$value")) ;;
		(uid:)		curuid=$value ;;
		(uid::)		curuid=$(b64decode "$value") ;;
		(jpegPhoto::)	curphoto=$value ;;
		(displayName:)		curname=$value ;;
		(displayName::)		curname=$(b64decode "$value") ;;
		(telephoneNumber:)	curtel=$value ;;
		(telephoneNumber::)	curtel=$(b64decode "$value") ;;
		}
		[[ -n $key ]] || skipped=
	done
	iserr=1
	if [[ -z $curdn ]]; then
		e="No Jabber flag for '$dn'"
	elif [[ $curdn != "$dn" ]]; then
		e="DN '$curdn' ≠ '$dn'"
	elif [[ $curuid != "$uid" ]]; then
		e="UID '$curuid' ≠ '$uid' for '$dn'"
	elif [[ -z $curname ]]; then
		e="No displayName in '$dn'"
	elif [[ -n $skipped ]]; then
		e="Skipped content in '$dn': $skipped"
	else
		iserr=0
	fi
	if (( iserr )); then
		print '<td colspan="2" style="background-color:red;"' \
		    'align="left" valign="top">'
		print '\t'"$e"
		print '</td></tr>'
		return
	fi
	print '<td align="center" valign="center" rowspan="3"' \
	    'style="border:1px solid grey;">'
	tdstyle=
	if [[ -n $curphoto ]]; then
		[[ $alldns = *":$dn:"* ]] || \
		    b64decode "$curphoto" >$curuid.jpg
		print "\t<img alt=\"$curuid photo\"" \
		    "src=\"$curuid.jpg\" />"
	else
		print -- -
		tdstyle='background-color:#999999; '
	fi
	tdstyle+='border:1px solid grey;'
	print "</td><td style=\"$tdstyle"'" align="left" valign="top" height="1">'
	print "\t<tt>$curuid</tt>"
	print "</td></tr>"
	print "<tr><td style=\"$tdstyle"'" align="left" valign="top">'
	print '\t<div style="font-size:large;">'
	print "\t\t$curname\n\t</div>"
	[[ -n $curtel ]] && \
	    print "\t<p>$curtel</p>"
	if (( ${#curmails[*]} > 0 )); then
		print '\t<p>'
		for x in "${curmails[@]}"; do
			print "\t\t$x<br />"
		done
		print '\t</p>'
	fi
	print "</td></tr>"
	print "<tr><td style=\"$tdstyle"'" align="left" valign="bottom" height="1">'
	print "\t<span style=\"font-size:small;\">$curdn</span>"
	print '</td></tr>'
}


emit_html_start

alldns=:
curcn=
curgdsc=
set -A curmembers
ldapshow -b dc=tarent,dc=de -s sub \
    '(&(objectClass=posixGroup)(|(cn=freelancer)(cn=mitarbeiter-berlin)(cn=systemaccount)(cn=mitarbeiter-bonn)))' \
    cn description uniqueMember |&
exec 4>&p; exec 4>&-
exec 5<&p
while read -u5 key value; do
	case $key {
	(cn:)	curcn=$value ;;
	(cn::)	curcn=$(b64decode "$value") ;;
	(description:)
		curgdsc=$value ;;
	(description::)
		curgdsc=$(b64decode "$value") ;;
	(uniqueMember:)
		curmembers+=("$value")
		;;
	(uniqueMember::)
		curmembers+=($(b64decode "$value"))
		;;
	}

	# ignore unknown lines / keys
	[[ -z $key ]] || continue
	# empty lines separate records

	# ignore empty entries
	if [[ -z $curcn ]]; then
		curgdsc=
		set -A curmembers
		continue
	fi

	emit_html_grpbeg "$curcn" "$curgdsc"

	# short-circuit empty groups
	if (( ${#curmembers[*]} == 0 )); then
		print '<tr><td colspan="2" align="center" valign="top">'
		print '\tEmpty group.'
		print '</td></tr>'
		emit_html_grpend
		curcn=
		curgdsc=
		set -A curmembers
		continue
	fi

	for dn in "${curmembers[@]}"; do
		print -r -- "$dn"
	done | sort -u |&
	exec 4>&p; exec 4>&-
	exec 6<&p
	while IFS= read -u6 dn; do
		process_dn "$dn"
		alldns+=$dn:
	done

	emit_html_grpend
	curcn=
	curgdsc=
	set -A curmembers
done

emitted=0
ldapshow isJabberAccount=1 dn | sed -n '/^dn: /s///p' | sort -u | \
    while IFS= read -r dn; do
	[[ $alldns = *":$dn:"* ]] && continue
	if (( !emitted )); then
		emit_html_grpbeg ENOENT \
		    "This lists Jabber accounts in no Roster group"
		emitted=1
	fi
	process_dn "$dn"
done
(( emitted )) && emit_html_grpend

emit_html_end
exit 0
