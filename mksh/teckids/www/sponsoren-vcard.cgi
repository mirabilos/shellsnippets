#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2002, 2003, 2004, 2006, 2007, 2008, 2009, 2010,
#		2011, 2012, 2013, 2014
#	Thorsten “mirabilos” Glaser <tg@mirbsd.org>
# Copyright © 2013, 2014, 2015
#	Thorsten Glaser <thorsten.glaser@teckids.org>
# Copyright © 2015, 2016
#	Dominik George <dominik.george@teckids.org>
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

unset HTTP_PROXY

set +U
cd "$(dirname "$0")"

function sed_escape {
	REPLY=$1
	REPLY=${REPLY//\\/\\\\}
	REPLY=${REPLY//[&]/\\&}
	REPLY=${REPLY//$'\n'/\\n}
}

#{{{ magic from MirOS: www/mk/common,v 1.7
# escape XHTML characters (three mandatory XML ones plus double quotes,
# the latter in an XML safe fashion numerically though)
function xhtml_escape {
	if (( $# )); then
		print -nr -- "$@"
	else
		cat
	fi | sed \
	    -e 's&\&amp;g' \
	    -e 's<\&lt;g' \
	    -e 's>\&gt;g' \
	    -e 's"\&#34;g'
}
#}}}

cr=$'\r'
lf=$'\n'
crlf=$'\r\n'

function dofield {
	# Parse one field from the query string
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

# Parse the GET query string
set -A fields -- who where
inp=$QUERY_STRING
while [[ $inp = *'&'* ]]; do
	fld=${inp%%'&'*}
	inp=${inp#*'&'}
	dofield "$fld"
done
[[ -n $inp ]] && dofield "$inp"

if [[ -n $where ]]; then
	 bei=" bei $(xhtml_escape "$where")"
fi

out+="<p>Vielen Dank, dass wir Sie als potentiellen Sponsor ansprechen durften!</p>"

if [[ -n $who ]]; then
	fn=$(getent passwd "$who" | cut -d: -f5)
	out+="<h3>Sie sprachen mit…</h3>"
	out+="<table style=\"border: 1px solid; width: 700px\"><tr><td><img src=\"/people/$who.jpg\" alt=\"$(xhtml_escape "$fn")\" style=\"width: 250px\" /></td>"
	out+="<td><p style=\"font-weight: bold; text-size: 150%\">$(xhtml_escape "$fn")</p>"
	out+="<p>Teckids e.V.<br />c/o tarent solutions GmbH<br />Rochusstr. 2-4<br />53123 Bonn</p>"
	out+="<p>Telefon: +49 228 9293416 0<br />E-Mail> <a href=\"mailto:verein@teckids.org\">verein@teckids.org</a></p></td></tr></table>"
fi

out+="<h3>Informationen über das Sponsoring</h3>"
out+="<p>Alle Informationen über die Möglichkeiten des Sponsorings haben wir in unseren <b>Sponsoring Facts</b> zusammengefasst. Sie finden das Dokument <a href=\"/docs/verein/docs/sponsoring-facts-allgemein.pdf\">hier zum Download</a></p>"
out+="<p>Bitte sprechen Sie uns jederzeit per Telefon oder E-Mail an!</p>"

print Content-type: text/html
print
sed \
    -e "s@!name!@Ihr Sponsoring-Gespräch" \
    -e "s@!head!@Ihr Sponsoring-Gespräch$bei" \
    -e "s@!body!@$out" \
    -e "s^.*TECKIDS_HTSCONV_GENDATE_TAG.*$<p class=\"rcsdiv\">Erstellt am <span class=\"rcsid\">$(date +'%F um %T Uhr').</span></p>" \
    <EMPTY.htm

exit 0
