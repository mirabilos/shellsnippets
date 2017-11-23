#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2014
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

myname=$(git config user.name)
myemail=$(git config user.email)

cat parsemail.csv |&
while IFS="|" read -rp -- vorname nachname geschlecht gebdat alter schule schulort klasse jgst email kontakt benutzer pwhash msgid; do
	print -- "$vorname\n$nachname\n$gebdat\n$email\n\n\n\n$schule\n$schulort\n$klasse" | teckids addperson -K
	print -- "$geschlecht\n$jgst\n$alter" | teckids projadd +V "$msgid"
	teckids intpasswd -U "$benutzer" -P "$pwhash"
	[[ $kontakt = all ]] && teckids groupadd kids
	cat <<-EOF | mail \
	    -a "From: $myname <$myemail>" \
	    -a "Content-Type: text/plain; charset=utf-8" \
	    -a "In-Reply-To: $msgid" \
	    -a "References: $msgid" \
	    -c "advent@lists.teckids.org" \
	    -s "Re: [Teckids advent] Anmeldung [Advent] von $vorname $nachname" \
	    "$email"
		Hallo $vorname,

		schön, dass du beim Teckids-Adventskalender 2014 mitmachst!

		Wir haben deinen Benutzerzugang angelegt. Ab dem 1.12.2014 kannst du dich damit
		im Adventskalender anmelden. Bitte beachte, dass du eventuell einen anderen
		Benutzernamen bekommen hast.

		    Benutzername:     $benutzer      (nur Kleinbuchstaben!)

		Viele Grüße und viel Erfolg,
		Dominik George (Nik)
	EOF
done
