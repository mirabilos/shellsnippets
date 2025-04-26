#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2002, 2003, 2004, 2006, 2007, 2008, 2009, 2010,
#		2011, 2012, 2013, 2014
#	Thorsten “mirabilos” Glaser <tg@mirbsd.org>
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
set -A fields -- vote mode
inp=$QUERY_STRING
while [[ $inp = *'&'* ]]; do
	fld=${inp%%'&'*}
	inp=${inp#*'&'}
	dofield "$fld"
done
[[ -n $inp ]] && dofield "$inp"
[[ -z $mode ]] && mode=vote

# Validate name of vote
[[ $vote = +([a-z]|[A-Z]|[0-9]|_|-) ]] || die Ungültiger Abstimmungsname!

# Look for vote definition file
vd=/var/lib/teckids/vote/$vote
[[ -e "$vd/vote" ]] || die Ungültiger Abstimmungsname!

# Parse vote definition file in state machine
s=0; q=0; set -A q_questions; set -A q_types; set -A q_choices; set -A q_detail
while IFS= read -r line; do
	case $s in
	0)
		# First block: global metadata
		k=${line%%: *}
		v=${line#*: }

		# FIXME do something useful on missing tags
		case $k in
		Title)
			v_title=$v
			;;
		Description)
			v_desc=$v
			;;
		Initiator)
			v_initiator=$v
			;;
		Group|Groups)
			v_groups="|$v|"
			;;
		Anonymous)
			v_anonymous=$v
			;;
		Until)
			v_until=$v
			;;
		esac

		[[ -z $k ]] && s=1
		;;
	1)
		# Following blocks: question definitions
		k=${line%%: *}
		v=${line#*: }

		# FIXME do something useful on missing tags
		case $k in
		Question)
			q_questions+=("$v")
			eval set -A q_answers_$q
			;;
		Detail)
			q_detail+=("$v")
			;;
		Type)
			q_types+=("$v")
			;;
		Choice)
			q_choices+=("$v")
			c=0
			sIFS=$IFS; IFS="|"; set -A choices -- ${q_choices[q]}; IFS=$sIFS
			j=0; while (( j < ${#choices[@]} )); do
				eval "q_answers_${q}_$j=0"
				eval "set -A q_answers_${q}_${j}_names"
				(( j++ ))
			done
			;;
		esac

		[[ -z $k ]] && (( q++ ))
		;;
	esac
done <"$vd/vote"
(( q++ ))

# Check authenticated user is in the group defined in the vote definition
group_ok=0
id -nGz "$REMOTE_USER" |&
while IFS= read -r -d '' -p group; do
	if [[ $v_groups = *"|$group|"* ]]; then
		group_ok=1
		break
	fi
done
(( group_ok )) || [[ $v_initiator = "$REMOTE_USER" ]] || \
    die Nicht zur Abstimmung berechtigt!

# If we got a GET request and mode is vote, render the form
if [[ $REQUEST_METHOD = GET && $mode = vote ]]; then
	# Bail out if end date has passed
	[[ -n $v_until ]] && (( $(date +"%s") > $v_until )) && die Abstimmung abgelaufen!

	# Check whether the authenticated user has not yet voted
	[[ -e "$vd/replies/$REMOTE_USER" ]] && die Bereits abgestimmt!

	# Get full name of vote initiator from nss/GECOS
	fn_initiator=$(getent passwd "$v_initiator" | cut -d: -f5)

	out=
	out+="<p>Diese Abstimmung wurde von $(xhtml_escape "$fn_initiator") gestartet.</p>"
	if [[ -n $v_until ]]; then
		out+="<p>Die Abstimmung ist bis <b>$(LC_ALL=de_DE.UTF-8 date -d @$v_until +'%A, den %d.%m.%Y, um %H:%M Uhr')</b> möglich.</p>"
	fi
	out+="<p>$(xhtml_escape "$v_desc")</p>"
	out+="<hr /><form method=\"post\" enctype=\"application/x-www-form-urlencoded\" accept-charset=\"utf-8\">"

	i=0
	while (( i < q )); do
		out+="<h2>Frage Nr. $(( i+1 ))</h2>"
		out+="<p style=\"font-weight:bold\">$(xhtml_escape "${q_questions[i]}")</p>"
		out+="<p>$(xhtml_escape "${q_detail[i]}")</p>"
		case ${q_types[i]} in
		radio)
			sIFS=$IFS; IFS="|"; set -A choices -- ${q_choices[i]}; IFS=$sIFS
			j=0
			for c in "${choices[@]}"; do
				out+="<input type=\"radio\" name=\"q_$i\" value=\"$j\" /> $(xhtml_escape "$c")<br />"
				(( j++ ))
			done
			out+="<input type=\"radio\" name=\"q_$i\" value=\"-1\" /> Enthaltung<br />"
			;;
		check)
			sIFS=$IFS; IFS="|"; set -A choices -- ${q_choices[i]}; IFS=$sIFS
			j=0
			for c in "${choices[@]}"; do
				out+="<input type=\"checkbox\" name=\"q_${i}_$j\" value=\"$j\" /> $(xhtml_escape "$c")<br />"
				(( j++ ))
			done
			;;
		text)
			out+="<textarea name=\"q_$i\" cols=\"60\" rows=\"10\"></textarea><br />"
			;;
		esac
		(( i++ ))
	done

	out+="<hr /><input type=\"submit\" value=\"Abschicken\" /></form>"

	print Content-type: text/html
	print
	sed \
	    -e "s@!name!@Abstimmung: $(xhtml_escape "$v_title")" \
	    -e "s@!head!@Abstimmung: $(xhtml_escape "$v_title")" \
	    -e "s@!body!@$out" \
	    -e "s^.*TECKIDS_HTSCONV_GENDATE_TAG.*$<p class=\"rcsdiv\">Erstellt am <span class=\"rcsid\">$(date +'%F um %T Uhr').</span></p>" \
	    <EMPTY.htm
# If we got a GET request and mode is results, render the results
elif [[ $REQUEST_METHOD = GET && $mode = results ]]; then
	# Parse all results
	set -A a_dates; set -A a_users; set -A a_names
	for f in $vd/replies/*; do
		[[ $f = "$vd/replies/*" ]] && continue

		s=0
		while IFS= read -r line; do
			case $s in
			0)
				# First block: global metadata
				k=${line%%: *}
				v=${line#*: }

				# FIXME do something useful on missing tags
				case $k in
				Date)
					a_dates+=($v)
					;;
				User)
					u=$v
					a_users+=($v)
					fn=$(getent passwd "$v" | cut -d: -f5)
					a_names+=("$fn")
					;;
				esac

				[[ -z $k ]] && s=1
				;;
			1)
				# Following blocks: answer definitions
				k=${line%%: *}
				v=${line#*: }

				# Check for paragraph end
				if [[ $line = " ." ]]; then
					eval "q_answers_${i}+=(\"$a\")"
					eval "q_answers_${i}_names+=($u)"
					continue
				# Check for line continuation
				elif [[ $line = " "* ]]; then
					a+="${line# }"
					continue
				fi


				# FIXME do something useful on missing tags
				case $k in
				Question)
					i=$v
					a=
					;;
				Answer)
					case ${q_types[i]} in
					radio|check)
						sIFS=$IFS; IFS="|"; set -A choices -- $v; IFS=$sIFS
						for c in "${choices[@]}"; do
							eval "(( q_answers_${i}_$c++ ))"
							eval "q_answers_${i}_${c}_names+=($u)"
						done
						;;
					text)
						a=$v
						;;
					esac
					;;
				esac
				;;
			esac
		done <"$f"
	done

	# Find max values
	i=0
	while (( i < q )); do
		case ${q_types[i]} in
		radio|check)
			eval q_answers_${i}_max=0
			sIFS=$IFS; IFS="|"; set -A choices -- ${q_choices[i]}; IFS=$sIFS
			j=0
			for c in "${choices[@]}"; do
				eval r=\$q_answers_${i}_$j
				eval m=\$q_answers_${i}_max
				(( r > m )) && eval q_answers_${i}_max=$r
				(( j++ ))
			done
			;;
		esac

		out+="</table>"
		(( i++ ))
	done

	# Get full name of vote initiator from nss/GECOS
	fn_initiator=$(getent passwd "$v_initiator" | cut -d: -f5)

	out=
	out+="<p>Diese Abstimmung wurde von $(xhtml_escape "$fn_initiator") gestartet.</p>"
	out+="<p>$(xhtml_escape "$v_desc")</p>"
	out+="<hr />"
	out+="<h2>Abstimmungsteilnehmer</h2>"
	out+="<ul>"
	for n in "${a_names[@]}"; do
		out+="<li>$n</li>"
	done
	out+="</ul>"

	i=0
	while (( i < q )); do
		out+="<h2>Frage Nr. $(( i+1 ))</h2>"
		out+="<p style=\"font-weight:bold\">$(xhtml_escape "${q_questions[i]}")</p>"
		out+="<p>$(xhtml_escape "${q_detail[i]}")</p>"
		out+="<table border=\"1\" style=\"width: 100%\">"

		case ${q_types[i]} in
		radio|check)
			out+="<tr><th>Antwort</th><th>Personen</th><th>Anzahl</th></tr>"
			sIFS=$IFS; IFS="|"; set -A choices -- ${q_choices[i]}; IFS=$sIFS
			j=0
			for c in "${choices[@]}"; do
				eval r=\$q_answers_${i}_$j
				eval m=\$q_answers_${i}_max
				rowstyle=
				(( r == m)) && rowstyle=" style=\"background-color: #66ff66\""
				out+="<tr$rowstyle><td style=\"text-align: left\">$c</td><td><ul>"
				if [[ $v_anonymous = no ]]; then
					eval "nameref us=q_answers_${i}_${j}_names"
					for u in "${us[@]}"; do
						out+="<li>$(getent passwd "$u" | cut -d: -f5)</li>"
					done
				fi
				out+="</ul></td><td style=\"text-align: right\">$r</td></tr>"
				(( j++ ))
			done
			;;
		text)
			out+="<tr><th>Antwort</th><th>Person</th></tr>"
			eval "nameref as=q_answers_${i}"
			l=0
			for a in "${as[@]}"; do
				if [[ -n $a ]]; then
					eval "u=\${q_answers_${i}_names[l]}"
					out+="<tr><td>$(xhtml_escape "${a//"$lf"/}" | sed 's!!<br />!g')</td><td>"
					if [[ $v_anonymous = no ]]; then
						out+=$(getent passwd "$u" | cut -d: -f5)
					fi
					out+="</td></tr>"
				fi
				(( l++ ))
			done
		esac

		out+="</table>"
		(( i++ ))
	done

	out+="<hr />"

	print Content-type: text/html
	print
	sed \
	    -e "s@!name!@Abstimmungsergebnis: $(xhtml_escape "$v_title")" \
	    -e "s@!head!@Abstimmungsergebnis: $(xhtml_escape "$v_title")" \
	    -e "s@!body!@$out" \
	    -e "s^.*TECKIDS_HTSCONV_GENDATE_TAG.*$<p class=\"rcsdiv\">Erstellt am <span class=\"rcsid\">$(date +'%F um %T Uhr').</span></p>" \
	    <EMPTY.htm
elif [[ $REQUEST_METHOD = POST ]]; then
	# Parse POST data
	set -A fields --

	inp=$(cat)
	i=0
	while (( i < q )); do
		if [[ ${q_types[i]} = check ]]; then
			sIFS=$IFS; IFS="|"; set -A choices -- ${q_choices[i]}; IFS=$sIFS
			j=0
			for c in "${choices[@]}"; do
				fields+=(q_${i}_$j)
				(( j++ ))
			done
		else
			fields+=(q_$i)
		fi
		(( i++ ))
	done
	while [[ $inp = *'&'* ]]; do
		fld=${inp%%'&'*}
		inp=${inp#*'&'}
		dofield "$fld"
	done
	[[ -n $inp ]] && dofield "$inp"

	{
		print -r -- "Date: $(date)"
		print -r -- "User: $REMOTE_USER"
		print

		i=0
		while (( i < q )); do
			if [[ ${q_types[i]} = radio ]]; then
				eval v=\$q_$i
				if [[ $v = -1 ]]; then
					# Enthaltung; do not write to file at all
					(( i++ ))
					continue
				fi
			fi

			print -r -- "Question: $i"
			if [[ ${q_types[i]} = check ]]; then
				sIFS=$IFS; IFS="|"; set -A choices -- ${q_choices[i]}; IFS=$sIFS
				j=0
				a=
				for c in "${choices[@]}"; do
					eval v=\$q_${i}_$j
					[[ $v = $j ]] && a+="$j|"
					(( j++ ))
				done
				a=${a%\|}
				print -r -- "Answer: $a"
			elif [[ ${q_types[i]} = text ]]; then
				eval v=\$q_$i
				if [[ $v != *"$crlf"* ]]; then
					print -r -- "Answer: $v$lf ."
				else
					v=${v//$crlf/$lf }
					print -r -- "Answer: $v$lf ."
				fi
			else
				eval v=\$q_$i
				print -r -- "Answer: $v"
			fi
			(( i++ ))

			print
		done
	} >"$vd/replies/$REMOTE_USER"

	print Content-type: text/html
	print
	sed \
	    -e "s@!name!@Abstimmung: $(xhtml_escape "$v_title")" \
	    -e "s@!head!@Abstimmung: $(xhtml_escape "$v_title")" \
	    -e "s@!body!@<p>Deine Abstimmung wurde gespeichert!</p><p><a href=\"auth_votes.cgi\">Zurück zu der Liste der Abstimmungen</a></p>" \
	    -e "s^.*TECKIDS_HTSCONV_GENDATE_TAG.*$<p class=\"rcsdiv\">Erstellt am <span class=\"rcsid\">$(date +'%F um %T Uhr').</span></p>" \
	    <EMPTY.htm
fi

exit 0
