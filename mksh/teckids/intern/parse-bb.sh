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
# Bundesland-specific; here: Brandenburg.
#
# apt-get install tidy xmlstarlet

export LC_ALL=C.UTF-8

for x in *.htm; do
	<"$x" fgrep -v -e '<div id="cp">' | \
	    tidy -q -asxhtml -w 0 -utf8 --quote-nbsp no 2>/dev/null | \
	    xmlstarlet fo -D | \
	    xmlstarlet sel -T -t -o "Dateinummer=${x%.*}" -n \
	    -t -o 'Nummer=' -c "//*[.='Schulnummer']/../*[2]" -n \
	    -t -o 'Name=' -c "//*[@id='content']/*[1]/*[2]" -n \
	    -t -o 'Typ=' -c "//*[.='Schulform']/../*[2]" -n \
	    -t -o 'Adresse=' -m "//*[.='Adresse']/../*[2]" \
	      --var linebreak -n --break -v "translate(., \$linebreak, '|')" -n \
	    -t -o 'eMail=' -c "//*[.='E-Mail']/../*[2]/*[@href]" -n \
	    -n
done
