# -*- mode: sh -*-
#-
# Copyright © 2002, 2003, 2004, 2006, 2007, 2008, 2009, 2010,
#		2011, 2012, 2013, 2014
#	Thorsten “mirabilos” Glaser <tg@mirbsd.org>
# Copyright © 2013, 2014, 2015, 2016
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

: "${suffix:=anmeldung}"
: "${sepa_gid:=ZZZ}"
: "${sepa_betrag:=0}"

unset LANG LANGUAGE LC_ADDRESS LC_ALL LC_COLLATE LC_CTYPE LC_IDENTIFICATION \
    LC_MEASUREMENT LC_MESSAGES LC_MONETARY LC_NAME LC_NUMERIC LC_PAPER \
    LC_TELEPHONE LC_TIME
set +U
cd "$(dirname "$0")"
nl=$'\n'

function sed_escape {
	REPLY=$1
	REPLY=${REPLY//\\/\\\\}
	REPLY=${REPLY//[&]/\\&}
	REPLY=${REPLY//$'\n'/\\$'\n'}
}

function sed_escape_re {
	REPLY=$(sed -e 's[^^][&]g; s\^\\^g; $!a\'$'\n''\\n' <<<"$1" | \
	    tr -d '\n')
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

# magic from MirOS: src/kern/c/mirtime.c,v 1.3 2011/11/20 23:40:10 tg Exp $

# struct tm members and (POSIX) time functions
typeset -ir tm_sec=0		# seconds [0-59]
typeset -ir tm_min=1		# minutes [0-59]
typeset -ir tm_hour=2		# hours [0-23]
typeset -ir tm_mday=3		# day of month [1-31]
typeset -ir tm_mon=4		# month of year - 1 [0-11]
typeset -ir tm_year=5		# year - 1900
typeset -ir tm_wday=6		# day of week [0 = sunday]	input:ignored
typeset -ir tm_yday=7		# day of year [0-365]		input:ignored
typeset -ir tm_isdst=8		# summer time act.? [0/1] (0)	input:ignored
typeset -ir tm_gmtoff=9		# seconds offset from UTC (0)
typeset -ir tm_zone=10		# abbrev. of timezone ("UTC")	input:ignored

set -A mirtime_months -- Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec
set -A mirtime_wdays -- Sun Mon Tue Wed Thu Fri Sat
readonly mirtime_months[*] mirtime_wdays[*]

# $ timet2mjd posix_timet
# ⇒ mjd sec
function timet2mjd {
	local -i10 mjd=$1 sec

	(( sec = mjd % 86400 ))
	(( mjd = (mjd / 86400) + 40587 ))
	while (( sec < 0 )); do
		(( --mjd ))
		(( sec += 86400 ))
	done

	print -- $mjd $sec
}

# $ mjd2timet mjd sec
# ⇒ posix_timet
function mjd2timet {
	local -i10 t=$1 sec=$2

	(( t = (t - 40587) * 86400 + sec ))
	print -- $t
}

# $ mjd_explode mjd sec
# ⇒ tm_sec tm_min tm_hour tm_mday tm_mon tm_year \
#   tm_wday tm_yday "0" "0" "UTC"
function mjd_explode {
	local tm
	set -A tm
	local -i10 sec=$2 day yday mon year=$1

	while (( sec < 0 )); do
		(( --year ))
		(( sec += 86400 ))
	done
	while (( sec >= 86400 )); do
		(( ++year ))
		(( sec -= 86400 ))
	done

	(( day = year % 146097 + 678881 ))
	(( year = 4 * ((year / 146097) + (day / 146097)) ))
	(( day %= 146097 ))
	(( tm[tm_wday] = (day + 3) % 7 ))
	if (( day == 146096 )); then
		(( year += 3 ))
		(( day = 36524 ))
	else
		(( year += day / 36524 ))
		(( day %= 36524 ))
	fi
	(( year = 4 * ((year * 25) + (day / 1461)) ))
	(( day %= 1461 ))
	(( yday = (day < 306) ? 1 : 0 ))
	if (( day == 1460 )); then
		(( year += 3 ))
		(( day = 365 ))
	else
		(( year += day / 365 ))
		(( day %= 365 ))
	fi
	(( yday += day ))
	(( day *= 10 ))
	(( mon = (day + 5) / 306 ))
	(( day = ((day + 5) % 306) / 10 ))
	if (( mon >= 10 )); then
		(( mon -= 10 ))
		(( yday -= 306 ))
		(( ++year ))
	else
		(( mon += 2 ))
		(( yday += 59 ))
	fi
	(( tm[tm_sec] = sec % 60 ))
	(( sec /= 60 ))
	(( tm[tm_min] = sec % 60 ))
	(( tm[tm_hour] = sec / 60 ))
	(( tm[tm_mday] = day + 1 ))
	(( tm[tm_mon] = mon ))
	(( tm[tm_year] = (year < 1 ? year - 1 : year) - 1900 ))
	(( tm[tm_yday] = yday ))
	(( tm[tm_isdst] = 0 ))
	(( tm[tm_gmtoff] = 0 ))
	tm[tm_zone]=UTC

	print -r -- "${tm[@]}"
}

# $ mjd_implode tm_sec tm_min tm_hour tm_mday tm_mon tm_year \
#   ignored ignored ignored tm_gmtoff [ignored]
# ⇒ mjd sec
function mjd_implode {
	local tm
	set -A tm -- "$@"
	local -i10 day x y sec

	(( sec = tm[tm_sec] + 60 * tm[tm_min] + 3600 * tm[tm_hour] - \
	    tm[tm_gmtoff] ))
	(( (day = tm[tm_year] + 1900) < 0 )) && (( ++day ))
	(( y = day % 400 ))
	(( day = (day / 400) * 146097 - 678882 + tm[tm_mday] ))
	while (( sec < 0 )); do
		(( --day ))
		(( sec += 86400 ))
	done
	while (( sec >= 86400 )); do
		(( ++day ))
		(( sec -= 86400 ))
	done
	(( x = tm[tm_mon] ))
	while (( x < 0 )); do
		(( --y ))
		(( x += 12 ))
	done
	(( y += x / 12 ))
	(( x %= 12 ))
	if (( x < 2 )); then
		(( x += 10 ))
		(( --y ))
	else
		(( x -= 2 ))
	fi
	(( day += (306 * x + 5) / 10 ))
	while (( y < 0 )); do
		(( day -= 146097 ))
		(( y += 400 ))
	done
	(( day += 146097 * (y / 400) ))
	(( y %= 400 ))
	(( day += 365 * (y % 4) ))
	(( y /= 4 ))
	(( day += 1461 * (y % 25) + 36524 * (y / 25) ))

	print -- $day $sec
}

# convenience function to check (German) date input (no time-of-day)
# input is $2, MJD is written to $$1, normalised date to $$3 if $3 is set
function dtchk {
	local tm mjd x saveIFS r=${2//[	 ]}
	set -A tm
	set -A mjd
	set -A x

	errstr="'$r' not in DD.MM.YYYY format"
	[[ $r = +([0-9]).+([0-9]).+([0-9]) ]] || return 1
	saveIFS=$IFS
	IFS=.
	set -A x -- $r
	IFS=$saveIFS
	if (( x[2] > 0 && x[2] < 30 )); then
		# accept year w/o leading 20xx
		(( x[2] += 2000 ))
	elif (( x[2] >= 30 && x[2] <= 99 )); then
		# accept year w/o leading 19xx
		(( x[2] += 1900 ))
	fi
	(( x[2] > 1000 )) || return 1
	set -A tm -- 0 0 0 $((x[0])) $((x[1] - 1)) $((x[2] - 1900)) \
	    - - - 0 -
	set -A mjd -- $(mjd_implode "${tm[@]}")
	set -A x -- $(mjd_explode "${mjd[0]}" 0)
	local -i10 -Z2 rd rm
	local -i10 -Z4 ry
	(( rd = x[tm_mday] ))
	(( rm = x[tm_mon] + 1 ))
	(( ry = x[tm_year] + 1900 ))
	errstr="invalid date $r, normalises to $rd.$rm.$ry ${x[tm_hour]}:${x[tm_min]}:${x[tm_sec]}"
	[[ ${tm[tm_hour]} = ${x[tm_hour]} ]] || return 1
	[[ ${tm[tm_min]} = ${x[tm_min]} ]] || return 1
	[[ ${tm[tm_sec]} = ${x[tm_sec]} ]] || return 1
	errstr="bogus date $r, normalises to $rd.$rm.$ry"
	[[ ${tm[tm_mday]##*(0)} = ${x[tm_mday]##*(0)} ]] && tm[tm_mday]=${x[tm_mday]}	# accept day w/o leading zeroes
	[[ ${tm[tm_mday]} = ${x[tm_mday]} ]] || return 1
	[[ ${tm[tm_mon]##*(0)} = ${x[tm_mon]##*(0)} ]] && tm[tm_mon]=${x[tm_mon]}	# accept month w/o leading zeroes
	[[ ${tm[tm_mon]} = ${x[tm_mon]} ]] || return 1
	[[ ${tm[tm_year]} = ${x[tm_year]} ]] || return 1
	errstr=
	nameref r=$1
	r=${mjd[0]}
	if [[ -n $3 ]]; then
		nameref rr=$3
		rr="$rd.$rm.$ry"
	fi
	return 0
}
#}}} magic from MirOS: www/mk/common,v 1.7

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
 per Jabber oder telefonisch unter <a
 href="tel:+49-228-92934160">+49 228 92934160</a>, falls
 dieser Fehler bestehenbleibt.</p>'

	print Content-type: text/html
	print
	sed \
	    -e "s@!name!@Fehler im Anmeldeformular ${kurz}" \
	    -e 's@!head!@Anmeldefehler' \
	    -e "s@!body!@${|sed_escape "$body";}" \
	    -e "s^.*TECKIDS_HTSCONV_GENDATE_TAG.*$<p class=\"rcsdiv\">Erstellt am <span class=\"rcsid\">$(date +'%F um %T Uhr').</span></p>" \
	    <EMPTY.htm
	logger -t ${conf}_${suffix}.cgi "<${eltern_email:-$email}> $funcname($rc);"
	exit $rc
}

function die {
	xdie die 1 "Fehler: $*"
}

whence -p php >/dev/null || die Interner Fehler auf dem Server.

[[ $HTTP_HOST = staging.teckids.org ]] || [[ $HTTPS = on ]] || die Keine gesicherte Verbindung.
[[ $REQUEST_METHOD = POST ]] || die Formulareinsendung nicht gefunden.
# evtl. weglassen
[[ $HTTP_REFERER = @(https://www|http://staging).teckids.org/${conf}_${suffix}.@(cgi|htm) ]] || \
    die Unerwarteter Aufrufer.

set -A Lb64encode_code -- A B C D E F G H I J K L M N O P Q R S T U V W X Y Z \
    a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9 + /
function Lb64encode {
	[[ -o utf8-mode ]]; local u=$?
	set +U
	local c s t
	if (( $# )); then
		read -raN-1 s <<<"$*"
		unset s[${#s[*]}-1]
	else
		read -raN-1 s
	fi
	local -i i=0 n=${#s[*]} j v

	while (( i < n )); do
		(( v = s[i++] << 16 ))
		(( j = i < n ? s[i++] : 0 ))
		(( v |= j << 8 ))
		(( j = i < n ? s[i++] : 0 ))
		(( v |= j ))
		t+=${Lb64encode_code[v >> 18]}${Lb64encode_code[v >> 12 & 63]}
		c=${Lb64encode_code[v >> 6 & 63]}
		if (( i <= n )); then
			t+=$c${Lb64encode_code[v & 63]}
		elif (( i == n + 1 )); then
			t+=$c=
		else
			t+===
		fi
		if (( ${#t} == 76 || i >= n )); then
			print $t
			t=
		fi
	done
	(( u )) || set -U
}

function automail_and_out {
	automail
	rv=$?
	(( rv )) && xdie email_fail $rv \
	    'Fehler beim Versenden, bitte probieren Sie es später nochmals!'

	# oder weiterleiten auf Erfolgsseite (ggf. wenn $1)
	print Content-type: text/html
	print
	sed \
	    -e "s@!name!@Anmeldeformular ${kurz} erfolgreich" \
	    -e 's@!head!@Anmeldung erfolgreich' \
	    -e "s@!body!@<p>Anmeldeinformationen erfolgreich an das Teckids-Team versandt. Es kann bis zu 48 Stunden dauern, bis du eine Nachricht von uns erhältst!</p>${info}" \
	    -e "s^.*TECKIDS_HTSCONV_GENDATE_TAG.*$<p class=\"rcsdiv\">Erstellt am <span class=\"rcsid\">$(date +'%F um %T Uhr').</span></p>" \
	    <EMPTY.htm
	logger -t ${conf}_${suffix}.cgi "<${eltern_email:-$email}> success();"
	exit 0
}

function automail {
	local body k x keys values v f=$-
	set -A keys
	set -A values
	set -U
	local -l kl
	# zmax: length of max("Formular-ID", "Referer", "Alter")
	local -i n=0 zmax=11 z
	local -i has_dob=-1 has_age=-1 has_rem=0 has_sepa=0

	for k in "${fieldnames[@]}" "${mail_show[@]}"; do
		kl=${k//-}
		nameref V=$kl
		for x in "${mail_hide[@]}" formid; do
			# nicht "$x": wildcards können verwendet werden
			[[ $kl = $x ]] && continue 2
		done
		x=$V
		case $kl {
		(age|alter)
			has_age=$n
			;;
		(bemerkungen)
			has_rem=1
			continue
			;;
		(email*)
			x="<$x>"
			;;
		(geburtsdatum)
			has_dob=$n
			;;
		(ok_*)
			x=${x:-nein}
			;;
		(username)
			k=Benutzername
			;;
		(sepa|sepa_zahler|sepa_iban|sepa_bic)
			has_sepa=1
			continue
			;;
		}
		z=${%k}
		(( z = z == -1 ? ${#k} : z ))
		(( zmax = z > zmax ? z : zmax ))
		keys[n]=$k
		values[n++]=$x
	done

	typeset -R$zmax k
	typeset -R$((zmax + 2)) sep='| '
	z=-1
	while (( ++z < n )); do
		k=${keys[z]}
		v=${values[z]}
		if [[ $v = *"$nl"* ]]; then
			body+="$nl$k:$nl$sep${v//"$nl"/"$nl$sep"}"
		else
			body+="$nl$k: $v"
		fi
		if (( (has_age == -1) && (has_dob == z) )); then
			k=Alter
			body+="$nl$k: ${age:-?}"
		fi
	done

	if (( has_rem )); then
		k=Bemerkungen
		body+="$nl$nl$k:$nl| ${bemerkungen//"$nl"/"$nl| "}"
	fi

	if (( has_sepa )) && [[ -n $sepa ]]; then
		body+="$nl${nl}SEPA-Lastschriftmandat:$nl"
		body+="| Ich ermächtige den Gläubiger Teckids e.V., Rochusstr. 2-4, 53123 Bonn$nl"
		body+="| mit der Gläubiger-ID DE70${sepa_gid}00001497650, den Betrag von $sepa_betrag € von$nl"
		body+="| meinem Konto einmalig mit dem SEPA-Basislastschriftverfahren einzu-$nl"
		body+="| ziehen. Gleichzeitig weise ich meine Bank an, die vom Teckids e.V.$nl"
		body+="| von meinem Konto eingezogene SEPA-Basislastschrift einzulösen.$nl"
		body+="|$nl"
		body+="|   Name des Zahlers:   $sepa_zahler$nl"
		body+="|   IBAN des Zahlers:   $sepa_iban$nl"
		body+="|   BIC des Zahlers:    $sepa_bic$nl"
		body+="|$nl"
		body+="| Die Mandatsreferenz wird mit der Zahlungsaufforderung mitgeteilt."
	fi

	if [[ -n $mail_extra ]]; then
		body+=$nl$nl
		body+=$mail_extra
		body+=$nl
	fi

	k=Referer
	body+="$nl$k: $HTTP_REFERER"
	k=Formular-ID
	body+="$nl$k: $formid"

	case $suffix {
	(anmeldung)
		typ=Anmeldung
		;;
	(elternformular)
		typ=Elternformular
		;;
	}

	mymail "$typ [$kurz] $vorname $nachname" <<EOF
Eingesendetes Anmeldeformular${encoding_ok:+; Kodierung nicht ok: $encoding_ok}
$body
EOF
	rv=$?

	# only necessary for mksh < R51
	[[ $f = *U* ]] || set +U

	return $rv
}

function addtorpl {
	nameref d=$1
	local namepart=$2 mailpart=$3 u=$- x y z
	integer i

	x=,
	set -U
	while [[ -n $namepart ]]; do
		i=45
		y=${namepart::i}
		set +U
		while (( ${#y} > 45 )); do
			let i--
			set -U
			y=${namepart::i}
			set +U
		done
		z=" =?utf-8?B?$(Lb64encode "$y")?="
		x+=$crlf$z
		set -U
		namepart=${namepart: i}
	done
	set +U
	(( ${#z} + 3 + ${#mailpart} > 77 )) && x+=$crlf
	x+=" <$mailpart>"
	[[ $u = *U* ]] && set -U
	d+=$x
}

function mymail {
	local msg subj="Subject: $1" replto="Reply-To: $to"

	[[ -n $email ]] && addtorpl replto "$vorname $nachname" "$email"
	[[ -n $eltern_email ]] && addtorpl replto "$vorname_eltern $nachname_eltern" "$eltern_email"
	[[ -z $to ]] && to="\"Teckids e.V. - Anmeldung\" <anmeldung@teckids.org>"

	[[ -n $email ]] && from="\"$vorname $nachname\" <$email>"
	[[ -z $from && -n $eltern_email ]] && from="\"$vorname_eltern $nachname_eltern\" <$eltern_email>"
	[[ -z $from ]] && from="\"Teckids e.V. Anmeldeformular\" <www-data@terra.teckids.org>"

	while IFS= read -r line; do
		msg+=${line%"$cr"}$crlf
	done
	msg=$(Lb64encode "$msg")
	msg=${msg//"$lf"/"$crlf"}

	subj=$(print -nr -- "$subj" | php -r '
		mb_internal_encoding("UTF-8");
		echo mb_encode_mimeheader(file_get_contents("php://stdin"),
		    "UTF-8", "Q", "\015\012");')

	/usr/sbin/sendmail -t <<EOF
MIME-Version: 1.0$cr
Content-Type: text/plain; charset=utf-8$cr
Content-Transfer-Encoding: base64$cr
$subj$cr
To: $to$cr
From: $from$cr
$replto$cr
X-Mailer: Teckids-Webseite: Anmeldeformular$cr
X-OTRS-DynamicField-TeckidsEvent: $lang
Date: $(date +'%a, %d %b %Y %H:%M:%S %z')$crlf$crlf$msg$cr
EOF
}

encoding_ok=unknown

set -A fields -- "${fieldnames[@]}"
typeset -l fields[*]
for x in "${fields[@]}"; do
	eval $x=
done

age=
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
	#print -r -- "D: field '$fldk' with value '$fldv' found"
	if [[ $fldk = utf8 ]]; then
		if [[ $encoding_ok != unknown ]]; then
			encoding_ok='multiple values found'
		elif [[ $fldv = ✓ ]]; then
			encoding_ok=yes
		else
			encoding_ok=no
		fi
		return
	elif [[ $fldk = geburtsdatum ]]; then
		if [[ $fldv = *([	 ]) ]]; then
			: handled further below
		elif ! dtchk dtJ "$fldv" dtv; then
			 handled further below
		elif ! dtchk dtJ "$fldv" dtv; then
			fldv+=" (invalid: $errstr)"
		else
			fldv=$dtv
			if (( ${#alter_am[*]} < 3 )); then
				set -A alter_am -- $(date +'%d %m %Y')	# Alter heute
			fi
			set -A tmGeb -- $(mjd_explode "$dtJ" 0)
			set -A tmNow -- $(mjd_explode $(mjd_implode 0 0 0 \
			    ${alter_am[0]} $((alter_am[1] - 1)) \
			    $((alter_am[2] - 1900)) 0 0 0 0 UTC))
			(( age = tmNow[tm_year] - tmGeb[tm_year] - \
			    ((tmNow[tm_yday] < tmGeb[tm_yday]) ? 1 : 0) ))
		fi
	fi
	for x in "${fields[@]}"; do
		[[ $fldk = "$x" ]] || continue
		eval $x=\$fldv
		break
	done
}
#print Content-type: text/plain; print; print Debugging:
inp=$(cat)
while [[ $inp = *'&'* ]]; do
	fld=${inp%%'&'*}
	inp=${inp#*'&'}
	dofield "$fld"
done
[[ -n $inp ]] && dofield "$inp"
#print D: encoding_ok=$encoding_ok

i=-1
for x in "${pflichtfeld[@]}"; do
	let ++i
	(( x )) || continue
	eval v=\$${fields[i]}
	[[ $v = *([	 ]) ]] && pflichtfelder_fehlen+=,\ ${fieldnames[i]//_/ }
done

text=
logt=
info=

if [[ " ${fieldnames[*]} " = *" Username Pw1 Pw2 "* ]]; then
	if [[ " ${fieldnames[*]} " != *" Account "* || $account = new ]]; then
		nu=$username
		typeset -l nu

		if [[ -z $skipchecks ]]; then
			if [[ $nu = *[!a-z0-9]* ]]; then
				text+="<p class=\"cgierr\">Dein Benutzername darf nur Kleinbuchstaben und Ziffern enthalten!</p>"
				logt+=" username_invalid()"
			elif (( ${#nu} < 3 )); then
				text+="<p class=\"cgierr\">Dein Benutzername muss mindestens drei Zeichen lang sein!</p>"
				logt+=" username_short()"
			elif [[ $nu = [0-9]* ]]; then
				text+="<p class=\"cgierr\">Dein Benutzername muss mit einem Buchstaben anfangen!</p>"
				logt+=" username_invalid()"
			elif getent passwd $nu >/dev/null 2>&1; then
				text+="<p class=\"cgierr\">Der Benutzername ist leider schon vergeben!</p>"
				logt+=" username_taken()"
			else
				info+="<p class=\"cgierr\">Dein neuer Benutzername lautet <b>$nu</b> (nur Kleinbuchstaben und Ziffern).</p>"
				username=$nu
			fi
		fi

		if [[ -z $pw1 || -z $pw2 || $pw1 != "$pw2" ]]; then
			text+="<p class=\"cgierr\">Du musst zwei mal das gleiche Passwort eingeben!</p>"
			logt+=" pw_mismatch()"
		fi

		pwhash=$(print -rn -- "$pw1" | /usr/sbin/slappasswd -T/dev/stdin)
	fi
fi

#XXX IBAN und BIC formatprüfen
[[ -n $sepa$sepa_zahler$sepa_iban$sepa_bic ]] && if [[ -z $sepa || \
    -z $sepa_zahler || -z $sepa_iban || -z $sepa_bic ]]; then
	text+="<p class=\"cgierr\">Falls SEPA Lastschrifteinzug gewünscht wird müssen <em>alle</em> relevanten Felder ausgefüllt werden!</p>"
	logt+=" sepa(teilweise)"
fi

typeset -l lc
for lc in "$email" "$eltern_email"; do
	if [[ $lc = *'@'@(gemskro.de|mail4kid[sz].*|kidzmail.@(de|eu)|schuelerpost.de|waldschule-quickborn.de) ]]; then
		text+="<p class=\"cgierr\">Dein Anbieter $(xhtml_escape "${lc#*@}") versteckt wichtige Nachrichten vor dir und ist nicht für E-Mails im Internet geeignet! Bitte verwende eine andere Mailadresse.</p>"
		logt+=" bogusmail($lc)"
	fi
done

if [[ -n $pflichtfelder_fehlen ]]; then
	text+="<p class=\"cgierr\">Bitte alle Pflichtfelder ausfüllen, es fehlt: ${pflichtfelder_fehlen#, }</p>"
	logt+=" pflichtfelder_fehlen(${pflichtfelder_fehlen#, })"
fi
if [[ -n $text ]]; then
	print Content-type: text/html
	print
	set -A repls -- -e "s<!-- REPL -->${text}" \
	    -e "schecked=\"checked\"g"
	for x in "${fields[@]}"; do
		eval y=\$$x
		[[ $y = *""* ]] && continue
		if [[ $x = bemerkungen ]]; then
			y=$(xhtml_escape "$y")
			set -A repls+ -- -e \
			    "sname=\"$x\"></textarea>name=\"$x\">${|sed_escape "$y";}</textarea>"
			continue
		fi
		[[ $y = *"$lf"* ]] && continue
		y=$(xhtml_escape "$y")
		set -A repls+ -- -e "sname=\"$x\" type=\"text\"& value=\"${|sed_escape "$y";}\""
		set -A repls+ -- -e "sname=\"$x\" value=\"${|sed_escape_re "$y";}\"& checked=\"checked\""
	done
	sed "${repls[@]}" <${conf}_${suffix}.htm
	logger -t ${conf}_${suffix}.cgi "<${eltern_email:-$email}>${logt};"
	exit 0
fi

[[ $encoding_ok = yes ]] && encoding_ok=
