#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2014, 2016
#	Dominik George <dominik.george@teckids.org>
# Copyright © 2016
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

cr=$'\r'

while :; do
	s=0
	a=0
	while IFS= read -r -- line; do
		if (( s == 0 )); then
			if [[ $line = "Message-Id: "* ]]; then
				msgid=${line#Message-Id: }
			elif [[ -z $line ]]; then
				s=1
				b64=
			fi
		elif (( s == 1 )); then
			if [[ -z $line ]]; then
				a=1
				break
			fi
			b64+=$line
		fi
	done
	(( a )) || exit 0

	print -r -- "$b64" | base64 -d | while IFS= read -r -- line; do
		line=${line%$cr}
		if [[ $line = *([ ])*([! :])": "* ]]; then
			val=${line##*([ ])*([! :]):*( )}
			val=${val%%*( )}
			print -rn -- "$val|"
		fi
	done

	print -r -- "$msgid"
done
