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
# Bundesland-specific; here: Sachsen-Anhalt.
#
# apt-get install tidy xmlstarlet

export LC_ALL=C.UTF-8

state=0 snam= sadr= splz= seml=
<sachsen-anhalt.html iconv -f cp1252 -t utf-8 | \
    tidy -q -asxhtml -w 0 -utf8 --quote-nbsp no 2>/dev/null | \
    xmlstarlet pyx | \
    while IFS= read -r line; do
	case $state:$line {
	([012]:')hr')
		let ++state
		;;
	([3569]:'Aclass standard01')
		let ++state
		;;
	(4:-*)
		snam+=${line#-}
		;;
	(4:*)
		state=5
		;;
	(7:-*)
		sadr+=${line#-}
		;;
	(7:*)
		state=8
		;;
	(8:'Ahref mailto:'*)
		seml=${line#'Ahref mailto:'}
		state=9
		;;
	(10:-*)
		splz+=${line#-}
		;;
	(10:*)
		cat <<-EOF
			Name=$snam
			Adresse=$sadr
			PLZ_Ort=$splz
			eMail=$seml

		EOF
		state=0 snam= sadr= splz= seml=
		;;
	}
done
