#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2015
#	mirabilos <thorsten.glaser@teckids.org>
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
# Quick hack to extract school information from web spider – this is
# Bundesland-specific; here: Bayern.
#
# apt-get install tidy xmlstarlet

export LC_ALL=C.UTF-8

for x in *.htm; do
	<"$x" iconv -f cp1252 -t utf-8 | \
	    tidy -q -asxhtml -w 0 -utf8 --quote-nbsp no 2>/dev/null | \
	    sed 's! xmlns="http://www.w3.org/1999/xhtml"!!' | \
	    xmlstarlet sel -T -t -o "Nummer=${x%.*}" -n \
	    -t -o 'Name=' -c '//span[@class="schulart_text"]/../h2' -n \
	    -t -o 'Typ=' -c '//span[@class="schulart_text"]' -n \
	    -t -o 'Rest=' -m '//span[@class="schulart_text"]/../p[1]' \
	      --var linebreak -n --break -v "translate(., \$linebreak, '\`')" -n \
	    -n
done | while IFS= read -r line; do
	case $line {
	(Typ=Schulart:*)
		print -r -- "Typ=${line##Typ=Schulart:*( )}"
		;;
	(Rest=*)
		line=\`${line#Rest=}\`
		if [[ $line = *'`Adresse:'* ]]; then
			x=${line##*'`Adresse:'*( )}
			x=${x%%*( )\`*}
			if [[ $x = *', '* ]]; then
				ort=${x%%, *}
				adresse=${x#*, }
			else
				ort=\? adresse=$x
			fi
			if [[ $ort = +([0-9])\ * ]]; then
				plz=${ort%% *}
				ort=${ort#* }
			else
				plz=\?
			fi
			print -r -- "Adresse=$adresse"
			print -r -- "PLZ=$plz"
			print -r -- "Ort=$ort"
		fi
		if [[ $line = *'`SchulWeb-Nummer:'* ]]; then
			x=${line##*'`SchulWeb-Nummer:'*( )}
			x=${x%%*( )\`*}
			print -r -- "SchulWebNr=$x"
		fi
		if [[ $line = *'`Email:'* ]]; then
			x=${line##*'`Email:'*( )}
			x=${x%%*( )\`*}
			print -r -- "eMail=$x"
		fi
		;;
	(*)
		print -r -- "$line"
		;;
	}
done
