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
# Bundesland-specific; here: Bremen.
#
# apt-get install tidy xmlstarlet

export LC_ALL=C.UTF-8

for x in *.htm; do
	<"$x" iconv -f cp1252 -t utf-8 | \
	    tidy -q -asxhtml -w 0 -utf8 --quote-nbsp no 2>/dev/null | \
	    sed 's! xmlns="http://www.w3.org/1999/xhtml"!!' | \
	    xmlstarlet sel -T -t -o "Nummer=${x%.*}" -n \
	    -t -o 'Name=' -m '//div[@class="main_article"]/h3[1]' \
	      --var linebreak -n --break -v "translate(., \$linebreak, ' ')" -n \
	    -t -o 'Adresse=' -m '//div[@class="kogis_main_visitenkarte"]/ul[1]/li[1]' \
	      --var linebreak -n --break -v "translate(., \$linebreak, '|')" -n \
	    -t -o 'eMail=' -c '//div[@class="kogis_main_visitenkarte"]/ul[2]/li[4]' -n \
	    -n
done
