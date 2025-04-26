#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2015
#	mirabilos
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
# Bundesland-specific; here: Sachsen.
#
# apt-get install poppler-utils

export LC_ALL=C.UTF-8

function xtrim {
	REPLY="$*"
	REPLY=${REPLY##*([	 ])}
	REPLY=${REPLY%%*([	 ])}
	REPLY=${REPLY//+([	 ])/ }
}

function xout {
	print -r -- "${styp:-\?}	${snam:-\?}	${sadr:-\?}	${splz:-\?}	${sort:-\?}	${seml:-\?}"
}

styp=Schultyp
snam=Name
sadr=Adresse
splz=PLZ
sort=Ort
seml=eMail
xout

# sorted except for more specific before generic; Mittelschule after Oberschule
set -A typen -- 'Berufliches Schulzentrum' Berufsbildende Berufsfachschul \
    Berufsschul Ergänzungsschule Fachoberschule Fachschule Förderschul \
    Förderzentrum 'Grund- und Oberschule' Grundschule Gymnasium \
    Montessorischule Oberschule Mittelschule Universität Waldorfschule
set -A typlv
typeset -l lnam
for lnam in "${typen[@]}"; do typlv+=("$lnam"); done

s=0 last=
pdftotext -layout sachsen.pdf - | while IFS= read -r line; do
	case $s:$line {
	(0:)
		last=
		;;
	(0:+( )Adresse\ *)
		snam=${|xtrim "$last";}
		sadr=${|xtrim "${line#+( )Adresse}";}
		s=1
		;;
	(0:*)
		last+=\ $line
		;;
	(1:+( )@(Telefon|Fax|E-Mail|Homepage)*)
		print -ru2 -- parse error
		exit 1
		;;
	(1:*)
		splz=${|xtrim "$line";}
		sort=${splz#+([0-9]) }
		if [[ $splz = "$sort" ]]; then
			splz=?
		else
			splz=${splz%% *}
		fi
		s=2
		;;
	(2:+( )E-Mail\ *)
		seml=${|xtrim "${line#+( )E-Mail}";}
		lnam=$snam
		styp=?
		for x in ${!typlv[*]}; do
			[[ $lnam = *${typlv[x]}* ]] || continue
			styp=${typen[x]}
			break
		done
		xout
		s=0 last=
		;;
	}
done
