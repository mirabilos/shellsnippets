#!/bin/mksh
#-
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
#-
#XXX TODO: sanitätsprüfen

sigdashes='-- '

: "${TEST:=1}"
[[ $TEST = 0 ]] && unset TEST

# höchste benutzte User-ID (außer nobody) finden
highest_uid=$(getent passwd | sort -t: -nk3 | tail -n -2 |&
	IFS=: read -pA
	echo ${REPLY[2]}
    )

while IFS=";" read -r TODO Vorname Nachname Geburtsdatum Alter Schulname Schulort Klasse eMail Kontaktumfang Account Benutzername Kanal Mehrbetrag OK_Eltern OK_Datenschutz PWHash Referer FormularID MessageID rest; do
	eMail=${eMail%>}
	eMail=${eMail#<}

	if [[ $eMail != +([-!\#-\'*+/-9=?A-Z^-~])*(.+([-!\#-\'*+/-9=?A-Z^-~]))@[0-9A-Za-z]?(*([-0-9A-Za-z])[0-9A-Za-z])*(.[0-9A-Za-z]?(*([-0-9A-Za-z])[0-9A-Za-z])) ]]; then
		print -u2 -r -- "Ungültige E-Mail-Adresse: <$eMail>"
		continue
	fi
	if [[ $TODO = s ]]; then
		continue
	fi
	if [[ $TODO = rs ]]; then
		# Ablehnen wegen ungültiger Schulangabe
		heirloom-mailx ${TEST:+-d} -c advent@lists.teckids.org -r dominik.george@teckids.org -s "Anmeldung zum Adventskalender abgelehnt" "$eMail" >&2 <<-EOF
			Hallo $Vorname,

			leider konnten wir deine Anmeldung zum Adventskalender nicht annehmen.

			Du hast bei der Anmeldung nicht den richtigen Namen deiner Schule angegeben.

			Wenn du noch mitmachen möchtest, melde dich bitte bis spätestens 1.12. noch
			einmal mit richtigen Angaben an.

			Viele Grüße,
			Dominik George

			$sigdashes
			Dominik George (1. Vorstandsvorsitzender, pädagogischer Leiter)
			Teckids e.V. - Erkunden, Entdecken, Erfinden.
			https://www.teckids.org
		EOF
		continue
	fi
	if [[ $TODO = ra ]]; then
		# Ablehnen wegen ungültigem Geburtsdatum
		heirloom-mailx ${TEST:+-d} -c advent@lists.teckids.org -r dominik.george@teckids.org -s "Anmeldung zum Adventskalender abgelehnt" "$eMail" >&2 <<-EOF
			Hallo $Vorname,

			leider konnten wir deine Anmeldung zum Adventskalender nicht annehmen.

			Du hast bei der Anmeldung ein ungültiges Geburtsdatum angegeben.

			Wenn du noch mitmachen möchtest, melde dich bitte bis spätestens 1.12. noch
			einmal mit richtigen Angaben an.

			Viele Grüße,
			Dominik George

			$sigdashes
			Dominik George (1. Vorstandsvorsitzender, pädagogischer Leiter)
			Teckids e.V. - Erkunden, Entdecken, Erfinden.
			https://www.teckids.org
		EOF
		continue
	fi
	if [[ $TODO = rb ]]; then
		# Ablehnen wegen ungültigem Account
		heirloom-mailx ${TEST:+-d} -c advent@lists.teckids.org -r dominik.george@teckids.org -s "Anmeldung zum Adventskalender abgelehnt" "$eMail" >&2 <<-EOF
			Hallo $Vorname,

			leider konnten wir deine Anmeldung zum Adventskalender nicht annehmen.

			Du hast bei der Anmeldung keine gültigen Angaben zu Benutzername und
			Passwort gemacht.

			Wenn du noch mitmachen möchtest, melde dich bitte bis spätestens 1.12. noch
			einmal mit richtigen Angaben an.

			Viele Grüße,
			Dominik George

			$sigdashes
			Dominik George (1. Vorstandsvorsitzender, pädagogischer Leiter)
			Teckids e.V. - Erkunden, Entdecken, Erfinden.
			https://www.teckids.org
		EOF
		continue
	fi
	if [[ $TODO = rn ]]; then
		# Ablehnen wegen ungültigem Namen
		heirloom-mailx ${TEST:+-d} -c advent@lists.teckids.org -r dominik.george@teckids.org -s "Anmeldung zum Adventskalender abgelehnt" "$eMail" >&2 <<-EOF
			Hallo $Vorname,

			leider konnten wir deine Anmeldung zum Adventskalender nicht annehmen.

			Du hast bei der Anmeldung leider einen ungültigen Namen angegeben.

			Wenn du noch mitmachen möchtest, melde dich bitte bis spätestens 1.12. noch
			einmal mit richtigen Angaben an.

			Viele Grüße,
			Dominik George

			$sigdashes
			Dominik George (1. Vorstandsvorsitzender, pädagogischer Leiter)
			Teckids e.V. - Erkunden, Entdecken, Erfinden.
			https://www.teckids.org
		EOF
		continue
	fi

	# Anlegen oder updaten, Gruppe hinzufügen, etc.
	# Message-ID Vorname Nachname Geburtsdatum Alter Schulname Schulort Klasse eMail Kontaktumfang Account Benutzername Kanal OK_Eltern OK_Datenschutz PW-Hash

	if [[ $Account = new ]]; then
		if [[ $TODO = l ]]; then
			dn="cn=$Vorname $Nachname+uid=$Benutzername,ou=People,dc=teckids,dc=org"
		else
			dn="cn=$Vorname $Nachname+uid=$Benutzername,ou=Kids,ou=People,dc=teckids,dc=org"
		fi

		cat <<-EOF
			dn: $dn
			changetype: add
			objectClass: inetOrgPerson
			objectClass: posixAccount
			objectClass: shadowAccount
			objectClass: teckidsPerson
			cn: $Vorname $Nachname
			givenName: $Vorname
			sn: $Nachname
			dateOfBirth: $Geburtsdatum
			o: $Schulname
			ou: $Klasse
			l: $Schulort
			mail: $eMail
			uid: $Benutzername
			uidNumber: $(( ++highest_uid ))
			userPassword: ${PWHash}
			gidNumber: 100
			loginShell: /bin/bash
			homeDirectory: /home/$Benutzername
			anmMessageId: <${MessageID}>

		EOF
	else
		if ! dnline=$(ldapsearch -QLLL "(uid=$Benutzername)" dn); then
			print -ru2 -- "DN kaputt für $Benutzername ($?)"
			dnline='dn: invalid,dc=teckids,dc=org'
		fi
		dnline=$(print -r -- "$dnline" | \
		    tr '\n' $'\a' | sed -e $'s/\a //g' | tr $'\a' '\n' | \
		    head -n 1)
		dn=${dnline#* }
		[[ $dnline = dn::* ]] && dn=$(print -r -- "$dn" | base64 -di)
		if [[ $dn != *,dc=teckids,dc=org ]]; then
			print -ru2 -- "DN kaputt für $Benutzername (#2)"
			dn='invalid,dc=teckids,dc=org'
		fi

		cat <<-EOF
			dn: $dn
			changetype: modify
			replace: o
			o: $Schulname
			-
			replace: l
			l: $Schulort
			-
			replace: ou
			ou: $Klasse
			-
			replace: mail
			mail: $eMail
			-

		EOF
	fi

	cat <<-EOF
		dn: cn=advent-2016,ou=Projekte,ou=Groups,dc=teckids,dc=org
		changetype: modify
		add: member
		member: $dn
		-

	EOF

	if [[ $Kontaktumfang = all ]]; then
		g=kids
		[[ $TODO = l ]] && g=lehrer

		cat <<-EOF
			dn: cn=$g,ou=Groups,dc=teckids,dc=org
			changetype: modify
			add: member
			member: $dn
			-

		EOF
	fi

	heirloom-mailx ${TEST:+-d} -c advent@lists.teckids.org -r dominik.george@teckids.org -s "Anmeldung zum Adventskalender" "$eMail" >&2 <<-EOF
		Hallo $Vorname,

		vielen Dank für deine Anmeldung zum MINT-Adventskalender 2016!

		Dein Benutzername lautet: $Benutzername (nur Kleinbuchstabenund Ziffern)

		Der Login und das Bearbeiten der Aufgaben wird ab dem
		1.12. um etwa 13 Uhr funktionieren.

		Wenn du Fragen oder Probleme hast, schreibe uns jederzeit eine
		E-Mail an advent@lists.teckids.org!

		Viele Grüße,
		Dominik George

		$sigdashes
		Dominik George (1. Vorstandsvorsitzender, pädagogischer Leiter)
		Teckids e.V. - Erkunden, Entdecken, Erfinden.
		https://www.teckids.org
	EOF
done
