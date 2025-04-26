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
# Bundesland-specific; here: Thüringen.
#
# apt-get install python-html5lib python-lxml xmlstarlet

export LC_ALL=C.UTF-8
me=$(realpath "$0/..")

for x in *.htm; do
	<"$x" python "$me/html5tidy/html5tidy" | sed 's!<br/>!|!g' | xmlstarlet sel -T \
	    -t -o 'Name=' -c '//td[@class="tispo_cn_header"]' -n \
	    -t -o 'Schulinfo=' -c '//div[@id="schulportraet_ueberblick_detail_allgemein_stammdaten"]/../div[2]' -n \
	    -t -o 'Adresse=' -c '//div[@id="schulportraet_ueberblick_detail_allgemein_stammdaten"]/../div[3]' -n \
	    -t -o 'eMail=' -c '//span[@id="schulportraet_ueberblick_detail_allgemein_tag_data_encrypter_span_2"]' -n \
	    -n
done | while IFS= read -r line; do
	case $line {
	(*=*)
		k=${line%%=*}
		v=${line#*=}
		;|
	(Schulinfo=*' (Schul-Nr. '+([0-9])\)*([	 ]))
		n=${line##*' (Schul-Nr. '}
		print -r -- "Nummer=${n%\)*}"
		v=${v%' (Schul-Nr. '*}
		;|
	(Schulinfo=*)
		k=Typ
		;|
	(eMail=*)
		# TopdevUtil.decryptZD
		v=${v//@( |#3b|3e#|o)}
		read -raN-1 a <<<"$v"
		v= i=0; (( n = ${#a[*]} - 1 ))
		typeset -Uui1 C
		while (( i < n )); do
			c=${a[i++]}
			(( C = (c < 0x30) || (c > 0x39) ? (c - 97 + 10) : (c - 0x30) ))
			c=${a[i++]}
			(( c = (c < 0x30) || (c > 0x39) ? (c - 97 + 10) : (c - 0x30) ))
			(( C = (C * 23 + c) / 2 ))
			v+=${C#1#}
		done
		;|
	(*=*)
		v=${v##+([	 ])}
		v=${v%%+([	 ])}
		line=$k=$v
		;;
	}
	print -r -- "$line"
done
