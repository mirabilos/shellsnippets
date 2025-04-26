#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2013, 2015
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
# Language selector/redirector, based on user’s preferences.

unset HTTP_PROXY

nl='
'
set -o noglob
while :; do
	defaultlanguage=de
	set -A languages -- de en

	set -A hdrlang
	set -A hdrqval
	nlang=0
	IFS=" ""	${nl},"
	set -A langs -- $HTTP_ACCEPT_LANGUAGE
	IFS=" ""	${nl}"
	for lang in "${langs[@]}"; do
		if [[ $lang = *';'* ]]; then
			qval=${lang#*';'}
			lang=${lang%%';'*}
			lang=${lang%%*([	 ])}
		else
			qval=q=1
		fi
		[[ $lang = '*' || $lang = +([A-Za-z])?(-+([A-Za-z])) ]] || continue
		hdrlang[nlang]=${lang%-*}
		qval=${qval##*([	 ])}
		[[ $qval = q*([	 ])=*([	 ])+([0-9.]) ]] || continue
		qval=${qval##*=*([	 ])}
		if [[ $qval = 0?(.) ]]; then
			qval=0
		elif [[ $qval = 1?(.?(0)?(0)?(0)) ]]; then
			qval=1000
		elif [[ $qval = 0.?([0-9])?([0-9])?([0-9]) ]]; then
			qval=${qval#0.}000
			qval=${qval::3}
		else
			continue
		fi
		hdrqval[nlang++]=$((10#$qval))
	done
	(( nlang )) || break
	# anything found at all
	set -A userlang
	i=-1
	while (( ++i < nlang )); do
		curqval=-1
		curidx=-1
		j=-1
		while (( ++j < nlang )); do
			[[ -n ${hdrlang[j]} ]] || continue
			(( hdrqval[j] > curqval )) || continue
			curqval=${hdrqval[j]}
			curidx=$j
		done
		userlang[i]=${hdrlang[curidx]}
		unset hdrlang[curidx]
	done
	# got a sorted list of prefs
	changeddefault=0
	for lang in "${userlang[@]}"; do
		found=0
		for x in "${languages[@]}"; do
			[[ $lang = "$x" ]] || continue
			found=1
			break
		done
		if (( found )); then
			defaultlanguage=$lang
			break
		fi
		(( changeddefault )) && continue
		# if not in list and not “*” switch fallback to en
		# if “*” is first not-in-list keep fallback as de
		[[ $lang = '*' ]] || defaultlanguage=en
		changeddefault=1
	done
	# when we arrive here, it's from one of these scenarios:
	# - one of the ${languages[@]} was found: first match wins
	# - none was found; first was *: keep de
	# - none was found; first was not *: fall back to en
	# when no valid lang pref was given by the user we break much earlier
	# in all cases, $defaultlanguage is set
	break
done

print 'Content-type: text/plain'
print
print -nr -- $defaultlanguage
