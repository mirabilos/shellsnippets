#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2002, 2003, 2004, 2006, 2007, 2008, 2009, 2010,
#	      2011, 2012, 2013, 2014
#	mirabilos <m$(date +%Y)@mirbsd.de>
# Copyright © 2013, 2014, 2015
#	mirabilos
# Copyright © 2015
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

exec 2>/tmp/a
set -x

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

function xdie {
	local body x funcname=$1 rc=$2; shift; shift

	for x in "$@"; do
		body+="<p class=\"cgierr\">$(xhtml_escape "$x")</p>$nl"
	done
	body+='
<p>Kontaktieren Sie uns ggfs. direkt per eMail unter <a
 href="mailto:vorstand@teckids.org">&lt;vorstand@teckids.org&gt;</a>,
 oder per IRC, Jabber oder telefonisch unter <a
 href="tel:+49-228-92934160">+49 228 92934160</a>, falls
 dieser Fehler bestehenbleibt.</p>'

	print Content-type: text/html
	print
	sed \
	    -e "s@!name!@CGI-Fehler" \
	    -e 's@!head!@CGI-Fehler' \
	    -e "s@!body!@${|sed_escape "$body";}" \
	    -e "s^.*TECKIDS_HTSCONV_GENDATE_TAG.*$<p class=\"rcsdiv\">Erstellt am <span class=\"rcsid\">$(date +'%F um %T Uhr').</span></p>" \
	    <EMPTY.htm
	exit $rc
}

function die {
	xdie die 1 "Fehler: $*"
}

[[ $HTTP_HOST = staging.teckids.org ]] || [[ $HTTPS = on ]] || die Keine gesicherte Verbindung.

# Look for vote definition file
vd=/var/lib/teckids/vote
cd "$vd"

# Iterate over votes, sorted by date
set -A votes_open; set -A votes_voted; set -A votes_missed
for v in *; do
	[[ $v = "*" ]] && continue
	print -r -- "$(sed -n '/^Until: /s///p' "$v/vote") $v"
done | LC_ALL=de_DE.UTF-8 sort -k1,1nr -k2 |&
exec 3>&p; exec 3>&-; exec 3<&p
while read -u3 v v; do
	# Get vote group names
	groups=$(grep "^Groups: " "$vd/$v/vote")
	groups="|${groups#Groups: }|"

	# Find end date
	until=$(grep "^Until: " "$vd/$v/vote")
	until=${until#Until: }

	# Get vote initiator
	initiator=$(grep "^Initiator: " "$vd/$v/vote")
	initiator=${initiator#Initiator: }

	# Check authenticated user is in the group defined in the vote definition
	group_ok=0
	id -nGz "$REMOTE_USER" |&
	while IFS= read -r -d '' -p group; do
		if [[ $groups = *"|$group|"* ]]; then
			group_ok=1
			break
		fi
	done
	(( group_ok )) || [[ $initiator = $REMOTE_USER ]] || continue

	if [[ -e "$vd/$v/replies/$REMOTE_USER" ]]; then
		votes_voted+=($v)
	elif [[ -z $until ]] || (( $(date +"%s") < $until )); then
		votes_open+=($v)
	else
		votes_missed+=($v)
	fi
done
cd - >/dev/null

out=

out+="<h2>Offene Abstimmungen - bitte abstimmen!</h2>"
out+="<table border=\"1\" style=\"width: 100%\"><tr><th>Abstimmung</th><th>Enddatum</th><th>Aktion</th></tr>"
for v in "${votes_open[@]}"; do
	name=$(grep "^Title: " "$vd/$v/vote")
	name=${name#Title: }
	until=$(grep "^Until: " "$vd/$v/vote")
	until=${until#Until: }
	out+="<tr><td>$(xhtml_escape "$name")</td><td>"
	if [[ -n $until ]]; then
		out+=$(LC_ALL=de_DE.UTF-8 date -d @$until +'%A, den %d.%m.%Y, um %H:%M Uhr')
	fi
	out+="</td><td><a href=\"auth_vote.cgi?vote=$v\">Jetzt abstimmen</a></td></tr>"
done
out+="</table>"

out+="<h2>Abstimmungen, an denen du teilgenommen hast</h2>"
out+="<table border=\"1\" style=\"width: 100%\"><tr><th>Abstimmung</th><th>Enddatum</th><th>Aktion</th></tr>"
for v in "${votes_voted[@]}"; do
	name=$(grep "^Title: " "$vd/$v/vote")
	name=${name#Title: }
	until=$(grep "^Until: " "$vd/$v/vote")
	until=${until#Until: }
	out+="<tr><td>$(xhtml_escape "$name")</td><td>"
	if [[ -n $until ]]; then
		out+=$(LC_ALL=de_DE.UTF-8 date -d @$until +'%A, den %d.%m.%Y, um %H:%M Uhr')
	fi
	out+="</td><td><a href=\"auth_vote.cgi?vote=$v\\&amp;mode=results\">Ergebnis anzeigen</a></td></tr>"
done
out+="</table>"

out+="<h2>Verpasste Abstimmungen</h2>"
out+="<table border=\"1\" style=\"width: 100%\"><tr><th>Abstimmung</th><th>Enddatum</th><th>Aktion</th></tr>"
for v in "${votes_missed[@]}"; do
	name=$(grep "^Title: " "$vd/$v/vote")
	name=${name#Title: }
	until=$(grep "^Until: " "$vd/$v/vote")
	until=${until#Until: }
	out+="<tr><td>$(xhtml_escape "$name")</td><td>"
	if [[ -n $until ]]; then
		out+=$(LC_ALL=de_DE.UTF-8 date -d @$until +'%A, den %d.%m.%Y, um %H:%M Uhr')
	fi
	out+="</td><td><a href=\"auth_vote.cgi?vote=$v\\&amp;mode=results\">Ergebnis anzeigen</a></td></tr>"
done
out+="</table>"

print Content-type: text/html
print
sed \
    -e "s@!name!@Abstimmungen" \
    -e "s@!head!@Abstimmungen" \
    -e "s@!body!@$out" \
    -e "s^.*TECKIDS_HTSCONV_GENDATE_TAG.*$<p class=\"rcsdiv\">Erstellt am <span class=\"rcsid\">$(date +'%F um %T Uhr').</span></p>" \
    <EMPTY.htm

exit 0
